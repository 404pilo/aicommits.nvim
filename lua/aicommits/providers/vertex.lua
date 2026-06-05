-- Vertex AI provider implementation for aicommits.nvim
local base = require("aicommits.providers.base")
local request = require("aicommits.request")

-- Create Vertex AI provider instance
local M = base.new({
  name = "vertex",
})

-- Token cache to avoid repeated gcloud calls
M._cached_token = nil
M._token_expiry = 0

-- Check if gcloud CLI is installed
-- @return boolean true if gcloud is available
local function is_gcloud_available()
  return vim.fn.executable("gcloud") == 1
end

-- Generate OAuth access token using gcloud ADC
-- This automatically uses GOOGLE_APPLICATION_CREDENTIALS if set, or user credentials from 'gcloud auth application-default login'
-- @param callback function(error, token) Callback with error or access token
local function generate_token(callback)
  -- Check cache first
  if M._cached_token and M._token_expiry > os.time() then
    callback(nil, M._cached_token)
    return
  end

  -- Check if gcloud is available
  if not is_gcloud_available() then
    callback(
      "gcloud CLI not found. Install from: https://cloud.google.com/sdk/install\nOr run: brew install google-cloud-sdk",
      nil
    )
    return
  end

  -- Execute gcloud command asynchronously
  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart("gcloud auth application-default print-access-token", {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout_data, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(stderr_data, data)
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        local error_msg = table.concat(stderr_data, "\n")
        -- Clear cache on error
        M._cached_token = nil
        M._token_expiry = 0

        -- Provide helpful error message
        if error_msg:match("not authenticated") or error_msg:match("credentials") then
          callback(
            "gcloud not authenticated. Run one of:\n  gcloud auth application-default login\n  export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json",
            nil
          )
        else
          callback("Failed to get access token: " .. error_msg, nil)
        end
        return
      end

      -- Extract token from stdout
      local token = table.concat(stdout_data, "\n"):gsub("%s+$", "") -- trim whitespace
      if token == "" then
        callback("Empty token received from gcloud", nil)
        return
      end

      -- Cache token for 55 minutes (tokens are valid for 60 minutes)
      M._cached_token = token
      M._token_expiry = os.time() + (55 * 60)

      callback(nil, token)
    end,
  })
end

-- Provider-agnostic transport for Vertex AI (Gemini format).
-- @param envelope table { system, user, model, max_tokens, temperature, n }
-- @param config   table Provider configuration
-- @param callback function(error, texts)
function M:generate_text(envelope, config, callback)
  generate_token(function(err, token)
    if err then
      callback(err, nil)
      return
    end

    local model = envelope.model or config.model or "gemini-2.0-flash-lite"
    local project = config.project
    local location = config.location or "us-central1"

    local host = location == "global" and "aiplatform.googleapis.com" or location .. "-aiplatform.googleapis.com"
    local endpoint = string.format(
      "https://%s/v1/projects/%s/locations/%s/publishers/google/models/%s:generateContent",
      host,
      project,
      location,
      model
    )

    local request_body = {
      contents = {
        { role = "user", parts = { { text = (envelope.system or "") .. "\n\n" .. (envelope.user or "") } } },
      },
      generationConfig = {
        temperature = envelope.temperature,
        maxOutputTokens = envelope.max_tokens,
        candidateCount = envelope.n or 1,
      },
    }

    local headers = { Authorization = "Bearer " .. token, ["Content-Type"] = "application/json" }

    request.send({
      url = endpoint,
      headers = headers,
      body = vim.json.encode(request_body),
      policy = request.resolve_policy(config),
    }, function(http_err, result)
      if http_err then
        callback(http_err, nil)
        return
      end

      local ok, response = pcall(vim.json.decode, result.body)
      if not ok then
        callback("Failed to parse Vertex AI API response: " .. tostring(response), nil)
        return
      end

      if response.error then
        callback("Vertex AI API Error: " .. (response.error.message or vim.inspect(response.error)), nil)
        return
      end

      if not response.candidates or #response.candidates == 0 then
        callback("No commit messages were generated. Try again.", nil)
        return
      end

      local texts = {}
      for _, candidate in ipairs(response.candidates) do
        if candidate.content and candidate.content.parts then
          for _, part in ipairs(candidate.content.parts) do
            if part.text and part.text ~= "" then
              table.insert(texts, part.text)
            end
          end
        end
      end

      callback(nil, texts)
    end)
  end)
end

-- Validate Vertex AI provider configuration
-- @param config table Provider configuration
-- @return boolean valid True if configuration is valid
-- @return table errors Array of error messages (empty if valid)
function M:validate_config(config)
  local errors = {}

  -- Validate model
  if not config.model or config.model == "" then
    table.insert(errors, "model is required and must be a non-empty string")
  end

  -- Validate project (required for Vertex AI)
  if not config.project or config.project == "" then
    table.insert(errors, "project is required and must be a non-empty string")
  end

  -- Validate location
  if not config.location or config.location == "" then
    table.insert(errors, "location is required and must be a non-empty string")
  end

  -- Validate max_length
  if config.max_length and (type(config.max_length) ~= "number" or config.max_length <= 0) then
    table.insert(errors, "max_length must be a positive number")
  end

  -- Validate gcloud availability
  if not is_gcloud_available() then
    table.insert(
      errors,
      "gcloud CLI is required for Vertex AI authentication. Install from: https://cloud.google.com/sdk/install"
    )
  end

  return #errors == 0, errors
end

-- Get authentication headers for Vertex AI API
-- NOTE: This method is deprecated and kept for backward compatibility
-- Authentication is now handled automatically in generate_commit_message()
-- @param config table Provider configuration (unused)
-- @return table headers HTTP headers with Authorization placeholder
function M:get_auth_headers(config)
  return {
    Authorization = "Bearer <token-generated-automatically>",
    ["Content-Type"] = "application/json",
  }
end

-- Get Vertex AI provider capabilities
-- @return table capabilities Provider feature support
function M:get_capabilities()
  return {
    supports_streaming = false, -- Streaming not implemented yet
    supports_multiple_generations = true, -- Generates 3 commit message options
    max_generations = 3,
  }
end

return M
