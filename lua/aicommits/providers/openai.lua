-- OpenAI provider implementation for aicommits.nvim
local base = require("aicommits.providers.base")
local request = require("aicommits.request")

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

-- Provider-agnostic transport for OpenAI chat-completions.
-- @param envelope table { system, user, model, max_tokens, temperature, n, top_p, frequency_penalty, presence_penalty }
-- @param config   table Provider configuration
-- @param callback function(error, texts)
function M:generate_text(envelope, config, callback)
  local api_key = get_api_key(config)
  if not api_key then
    callback(
      "OpenAI API key not found. Set 'providers.openai.api_key' in config or environment variable AICOMMITS_NVIM_OPENAI_API_KEY or OPENAI_API_KEY",
      nil
    )
    return
  end

  local endpoint = config.endpoint or "https://api.openai.com/v1/chat/completions"

  local request_body = {
    model = envelope.model or config.model or "gpt-4.1-nano",
    messages = {
      { role = "system", content = envelope.system },
      { role = "user", content = envelope.user },
    },
    temperature = envelope.temperature,
    top_p = envelope.top_p,
    frequency_penalty = envelope.frequency_penalty,
    presence_penalty = envelope.presence_penalty,
    max_tokens = envelope.max_tokens,
    stream = false,
    n = envelope.n or 1,
  }

  request.send({
    url = endpoint,
    headers = self:get_auth_headers(config),
    body = vim.json.encode(request_body),
    policy = request.resolve_policy(config),
  }, function(err, result)
    if err then
      callback(err, nil)
      return
    end

    local ok, response = pcall(vim.json.decode, result.body)
    if not ok then
      callback("Failed to parse OpenAI API response: " .. tostring(response), nil)
      return
    end

    if response.error then
      callback("OpenAI API Error: " .. (response.error.message or vim.inspect(response.error)), nil)
      return
    end

    if not response.choices or #response.choices == 0 then
      callback("No commit messages were generated. Try again.", nil)
      return
    end

    local texts = {}
    for _, choice in ipairs(response.choices) do
      if choice.message and choice.message.content then
        table.insert(texts, choice.message.content)
      end
    end

    callback(nil, texts)
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
