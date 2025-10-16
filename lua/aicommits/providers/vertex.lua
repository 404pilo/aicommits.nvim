-- Vertex AI provider implementation for aicommits.nvim
local base = require("aicommits.providers.base")
local http = require("aicommits.http")
local prompts = require("aicommits.prompts")

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

-- Implementation: Generate commit message(s) using Vertex AI API
-- @param diff string The git diff to generate message for
-- @param config table Provider-specific configuration
-- @param callback function(error, messages) Callback with error or array of messages
function M:generate_commit_message(diff, config, callback)
  -- Get access token first
  generate_token(function(err, token)
    if err then
      callback(err, nil)
      return
    end

    -- Get configuration with defaults
    local model = config.model or "gemini-2.0-flash-lite"
    local project = config.project
    local location = config.location or "us-central1"
    local max_length = config.max_length or 50
    local temperature = config.temperature or 0.7
    local max_tokens = config.max_tokens or 200

    -- Build Vertex AI endpoint
    local endpoint = string.format(
      "https://%s-aiplatform.googleapis.com/v1/projects/%s/locations/%s/publishers/google/models/%s:generateContent",
      location,
      project,
      location,
      model
    )

    -- Build system prompt and user content
    local system_prompt = prompts.build_system_prompt(max_length)

    -- Build Vertex AI API request body (Gemini format)
    local request_body = {
      contents = {
        {
          role = "user",
          parts = {
            {
              text = system_prompt .. "\n\n" .. diff,
            },
          },
        },
      },
      generationConfig = {
        temperature = temperature,
        maxOutputTokens = max_tokens,
        candidateCount = 3, -- Generate 3 commit message options
      },
    }

    -- Build auth headers
    local headers = {
      Authorization = "Bearer " .. token,
      ["Content-Type"] = "application/json",
    }

    -- Make API request
    http.post(endpoint, headers, vim.json.encode(request_body), function(http_err, response_body)
      if http_err then
        callback(http_err, nil)
        return
      end

      -- Parse JSON response
      local ok, response = pcall(vim.json.decode, response_body)
      if not ok then
        callback("Failed to parse Vertex AI API response: " .. tostring(response), nil)
        return
      end

      -- Check for API errors
      if response.error then
        local error_msg = "Vertex AI API Error: " .. (response.error.message or vim.inspect(response.error))
        callback(error_msg, nil)
        return
      end

      -- Extract messages from response (Vertex AI Gemini format)
      if not response.candidates or #response.candidates == 0 then
        callback("No commit messages were generated. Try again.", nil)
        return
      end

      local messages = {}
      for _, candidate in ipairs(response.candidates) do
        if candidate.content and candidate.content.parts then
          for _, part in ipairs(candidate.content.parts) do
            if part.text and part.text ~= "" then
              table.insert(messages, part.text)
            end
          end
        end
      end

      -- Process and return messages
      local processed = prompts.process_messages(messages)
      if #processed == 0 then
        callback("No valid commit messages were generated. Try again.", nil)
        return
      end

      callback(nil, processed)
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
