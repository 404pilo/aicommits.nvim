-- OpenAI provider implementation for aicommits.nvim
local base = require("aicommits.providers.base")
local http = require("aicommits.http")
local prompts = require("aicommits.prompts")

-- Create OpenAI provider instance
local M = base.new({
  name = "openai",
})

-- Get OpenAI API key from configuration or environment variables
-- Priority: config.api_key > AICOMMITS_NVIM_OPENAI_API_KEY > OPENAI_API_KEY
-- @param config table Provider configuration
-- @return string|nil api_key The API key or nil if not found
local function get_api_key(config)
  -- Check config first
  if config.api_key and config.api_key ~= "" then
    return config.api_key
  end

  -- Check plugin-specific env var
  local key = vim.env.AICOMMITS_NVIM_OPENAI_API_KEY
  if key and key ~= "" then
    return key
  end

  -- Check generic OpenAI env var
  key = vim.env.OPENAI_API_KEY
  if key and key ~= "" then
    return key
  end

  return nil
end

-- Implementation: Generate commit message(s) using OpenAI API
-- @param diff string The git diff to generate message for
-- @param config table Provider-specific configuration
-- @param callback function(error, messages) Callback with error or array of messages
function M:generate_commit_message(diff, config, callback)
  local api_key = get_api_key(config)
  if not api_key then
    callback(
      "OpenAI API key not found. Set 'providers.openai.api_key' in config or environment variable AICOMMITS_NVIM_OPENAI_API_KEY or OPENAI_API_KEY",
      nil
    )
    return
  end

  -- Get configuration with defaults
  local endpoint = config.endpoint or "https://api.openai.com/v1/chat/completions"
  local model = config.model or "gpt-4.1-nano"
  local max_length = config.max_length or 50
  local generate = config.generate or 1
  local temperature = config.temperature or 0.7
  local top_p = config.top_p or 1
  local frequency_penalty = config.frequency_penalty or 0
  local presence_penalty = config.presence_penalty or 0
  local max_tokens = config.max_tokens or 200

  -- Build OpenAI API request body
  local request_body = {
    model = model,
    messages = {
      {
        role = "system",
        content = prompts.build_system_prompt(max_length, config.commitlint_config),
      },
      {
        role = "user",
        content = diff,
      },
    },
    temperature = temperature,
    top_p = top_p,
    frequency_penalty = frequency_penalty,
    presence_penalty = presence_penalty,
    max_tokens = max_tokens,
    stream = false,
    n = generate,
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
      callback("Failed to parse OpenAI API response: " .. tostring(response), nil)
      return
    end

    -- Check for API errors
    if response.error then
      local error_msg = "OpenAI API Error: " .. (response.error.message or vim.inspect(response.error))
      callback(error_msg, nil)
      return
    end

    -- Extract messages from response
    if not response.choices or #response.choices == 0 then
      callback("No commit messages were generated. Try again.", nil)
      return
    end

    local messages = {}
    for _, choice in ipairs(response.choices) do
      if choice.message and choice.message.content then
        table.insert(messages, choice.message.content)
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

-- Validate OpenAI provider configuration
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

  -- Validate generate
  if config.generate and (type(config.generate) ~= "number" or config.generate < 1 or config.generate > 5) then
    table.insert(errors, "generate must be a number between 1 and 5")
  end

  -- Validate API key availability
  if not get_api_key(config) then
    table.insert(
      errors,
      "API key not found. Set 'providers.openai.api_key' in config or environment variable AICOMMITS_NVIM_OPENAI_API_KEY or OPENAI_API_KEY"
    )
  end

  return #errors == 0, errors
end

-- Get authentication headers for OpenAI API
-- @param config table Provider configuration
-- @return table headers HTTP headers with Authorization
function M:get_auth_headers(config)
  local api_key = get_api_key(config)
  return {
    Authorization = "Bearer " .. (api_key or ""),
  }
end

-- Get OpenAI provider capabilities
-- @return table capabilities Provider feature support
function M:get_capabilities()
  return {
    supports_streaming = true, -- OpenAI supports streaming (not implemented yet)
    supports_multiple_generations = true, -- Can generate multiple commit message options
    max_generations = 5, -- OpenAI supports up to 5 with 'n' parameter
  }
end

return M
