-- Vertex AI provider implementation for aicommits.nvim
local base = require("aicommits.providers.base")
local http = require("aicommits.http")
local prompts = require("aicommits.prompts")

-- Create Vertex AI provider instance
local M = base.new({
  name = "vertex",
})

-- Get Vertex AI API key from configuration or environment variables
-- Priority: config.api_key > AICOMMITS_NVIM_VERTEX_API_KEY > VERTEX_API_KEY
-- @param config table Provider configuration
-- @return string|nil api_key The API key or nil if not found
local function get_api_key(config)
  -- Check config first
  if config.api_key and config.api_key ~= "" then
    return config.api_key
  end

  -- Check plugin-specific env var
  local key = vim.env.AICOMMITS_NVIM_VERTEX_API_KEY
  if key and key ~= "" then
    return key
  end

  -- Check generic Vertex AI env var
  key = vim.env.VERTEX_API_KEY
  if key and key ~= "" then
    return key
  end

  return nil
end

-- Implementation: Generate commit message(s) using Vertex AI API
-- @param diff string The git diff to generate message for
-- @param config table Provider-specific configuration
-- @param callback function(error, messages) Callback with error or array of messages
function M:generate_commit_message(diff, config, callback)
  local api_key = get_api_key(config)
  if not api_key then
    callback(
      "Vertex AI API key not found. Set 'providers.vertex.api_key' in config or environment variable AICOMMITS_NVIM_VERTEX_API_KEY or VERTEX_API_KEY",
      nil
    )
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
      candidateCount = 1, -- Vertex AI Gemini typically generates one response
    },
  }

  -- Make API request
  http.post(endpoint, self:get_auth_headers(config), vim.json.encode(request_body), function(err, response_body)
    if err then
      callback(err, nil)
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

  -- Validate API key availability
  if not get_api_key(config) then
    table.insert(
      errors,
      "API key not found. Set 'providers.vertex.api_key' in config or environment variable AICOMMITS_NVIM_VERTEX_API_KEY or VERTEX_API_KEY"
    )
  end

  return #errors == 0, errors
end

-- Get authentication headers for Vertex AI API
-- @param config table Provider configuration
-- @return table headers HTTP headers with Authorization
function M:get_auth_headers(config)
  local api_key = get_api_key(config)
  return {
    Authorization = "Bearer " .. (api_key or ""),
    ["Content-Type"] = "application/json",
  }
end

-- Get Vertex AI provider capabilities
-- @return table capabilities Provider feature support
function M:get_capabilities()
  return {
    supports_streaming = false, -- Streaming not implemented yet
    supports_multiple_generations = false, -- Vertex AI Gemini typically generates one response
    max_generations = 1,
  }
end

return M
