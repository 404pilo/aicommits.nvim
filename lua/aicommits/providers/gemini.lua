-- Google Gemini API (AI Studio) provider implementation for aicommits.nvim
-- Uses generativelanguage.googleapis.com endpoint with simple API key authentication
local base = require("aicommits.providers.base")
local http = require("aicommits.http")
local prompts = require("aicommits.prompts")

-- Create Gemini API provider instance
local M = base.new({
  name = "gemini-api",
})

-- Get Gemini API key from configuration or environment variables
-- Priority: config.api_key > AICOMMITS_NVIM_GEMINI_API_KEY > GEMINI_API_KEY
-- @param config table Provider configuration
-- @return string|nil api_key The API key or nil if not found
local function get_api_key(config)
  -- Check config first
  if config.api_key and config.api_key ~= "" then
    return config.api_key
  end

  -- Check plugin-specific env var
  local key = vim.env.AICOMMITS_NVIM_GEMINI_API_KEY
  if key and key ~= "" then
    return key
  end

  -- Check generic Gemini env var
  key = vim.env.GEMINI_API_KEY
  if key and key ~= "" then
    return key
  end

  return nil
end

-- Implementation: Generate commit message(s) using Gemini API
-- @param diff string The git diff to generate message for
-- @param config table Provider-specific configuration
-- @param callback function(error, messages) Callback with error or array of messages
function M:generate_commit_message(diff, config, callback)
  local api_key = get_api_key(config)
  if not api_key then
    callback(
      "Gemini API key not found. Set 'providers[\"gemini-api\"].api_key' in config or environment variable AICOMMITS_NVIM_GEMINI_API_KEY or GEMINI_API_KEY",
      nil
    )
    return
  end

  -- Get configuration with defaults
  local model = config.model or "gemini-2.5-flash"
  local max_length = config.max_length or 50
  local temperature = config.temperature or 0.7
  local max_tokens = config.max_tokens or 200
  local generate = config.generate or 1

  -- Build Gemini API endpoint
  local endpoint = string.format("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)

  -- Build system prompt
  local system_prompt = prompts.build_system_prompt(max_length)

  -- Build Gemini API request body (contents array format)
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
      candidateCount = generate,
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
      callback("Failed to parse Gemini API response: " .. tostring(response), nil)
      return
    end

    -- Check for API errors
    if response.error then
      local error_msg = "Gemini API Error: " .. (response.error.message or vim.inspect(response.error))
      callback(error_msg, nil)
      return
    end

    -- Extract messages from response (Gemini candidates format)
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

-- Validate Gemini API provider configuration
-- @param config table Provider configuration
-- @return boolean valid True if configuration is valid
-- @return table errors Array of error messages (empty if valid)
function M:validate_config(config)
  local errors = {}

  -- Validate model
  if not config.model or config.model == "" then
    table.insert(errors, "model is required and must be a non-empty string")
  end

  -- Validate max_length
  if config.max_length and (type(config.max_length) ~= "number" or config.max_length <= 0) then
    table.insert(errors, "max_length must be a positive number")
  end

  -- Validate temperature
  if
    config.temperature and (type(config.temperature) ~= "number" or config.temperature < 0 or config.temperature > 2)
  then
    table.insert(errors, "temperature must be a number between 0 and 2")
  end

  -- Validate max_tokens
  if config.max_tokens and (type(config.max_tokens) ~= "number" or config.max_tokens <= 0) then
    table.insert(errors, "max_tokens must be a positive number")
  end

  -- Validate generate (candidateCount has max of 8)
  if config.generate and (type(config.generate) ~= "number" or config.generate < 1 or config.generate > 8) then
    table.insert(errors, "generate must be a number between 1 and 8")
  end

  -- Validate API key availability
  if not get_api_key(config) then
    table.insert(
      errors,
      "API key not found. Set 'providers[\"gemini-api\"].api_key' in config or environment variable AICOMMITS_NVIM_GEMINI_API_KEY or GEMINI_API_KEY"
    )
  end

  return #errors == 0, errors
end

-- Get authentication headers for Gemini API
-- @param config table Provider configuration
-- @return table headers HTTP headers with x-goog-api-key
function M:get_auth_headers(config)
  local api_key = get_api_key(config)
  return {
    ["x-goog-api-key"] = api_key or "",
    ["Content-Type"] = "application/json",
  }
end

-- Get Gemini API provider capabilities
-- @return table capabilities Provider feature support
function M:get_capabilities()
  return {
    supports_streaming = true, -- Gemini API supports streaming (not implemented yet)
    supports_multiple_generations = true, -- Can generate multiple commit message options
    max_generations = 8, -- Gemini API supports up to 8 with 'candidateCount' parameter
  }
end

return M
