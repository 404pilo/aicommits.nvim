-- Anthropic Claude provider implementation for aicommits.nvim
local base = require("aicommits.providers.base")
local request = require("aicommits.request")

-- Create Anthropic provider instance
local M = base.new({
  name = "anthropic",
})

-- Get Anthropic API key from configuration or environment variables
-- Priority: config.api_key > AICOMMITS_NVIM_ANTHROPIC_API_KEY > ANTHROPIC_API_KEY
-- @param config table Provider configuration
-- @return string|nil api_key The API key or nil if not found
local function get_api_key(config)
  -- Check config first
  if config.api_key and config.api_key ~= "" then
    return config.api_key
  end

  -- Check plugin-specific env var
  local key = vim.env.AICOMMITS_NVIM_ANTHROPIC_API_KEY
  if key and key ~= "" then
    return key
  end

  -- Check generic Anthropic env var
  key = vim.env.ANTHROPIC_API_KEY
  if key and key ~= "" then
    return key
  end

  return nil
end

-- Provider-agnostic transport for Anthropic's Messages API.
-- @param envelope table { system, user, model, max_tokens, temperature, top_p }
-- @param config   table Provider configuration
-- @param callback function(error, texts)
function M:generate_text(envelope, config, callback)
  local api_key = get_api_key(config)
  if not api_key then
    callback(
      "Anthropic API key not found. Set 'providers.anthropic.api_key' in config or environment variable AICOMMITS_NVIM_ANTHROPIC_API_KEY or ANTHROPIC_API_KEY",
      nil
    )
    return
  end

  local request_body = {
    model = envelope.model or config.model or "claude-haiku-4-5",
    max_tokens = envelope.max_tokens or 200,
    temperature = envelope.temperature,
    top_p = envelope.top_p,
    system = envelope.system,
    messages = {
      { role = "user", content = envelope.user },
    },
  }

  request.send({
    url = "https://api.anthropic.com/v1/messages",
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
      callback("Failed to parse Anthropic API response: " .. tostring(response), nil)
      return
    end

    if response.error then
      callback("Anthropic API Error: " .. (response.error.message or vim.inspect(response.error)), nil)
      return
    end

    if not response.content or #response.content == 0 then
      callback("No commit messages were generated. Try again.", nil)
      return
    end

    local texts = {}
    for _, block in ipairs(response.content) do
      if block.type == "text" and block.text and block.text ~= "" then
        table.insert(texts, block.text)
      end
    end

    callback(nil, texts)
  end)
end

-- Validate Anthropic provider configuration
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

  -- Validate temperature (Claude accepts 0-1)
  if
    config.temperature and (type(config.temperature) ~= "number" or config.temperature < 0 or config.temperature > 1)
  then
    table.insert(errors, "temperature must be a number between 0 and 1")
  end

  -- Validate max_tokens
  if config.max_tokens and (type(config.max_tokens) ~= "number" or config.max_tokens <= 0) then
    table.insert(errors, "max_tokens must be a positive number")
  end

  -- Validate API key availability
  if not get_api_key(config) then
    table.insert(
      errors,
      "API key not found. Set 'providers.anthropic.api_key' in config or environment variable AICOMMITS_NVIM_ANTHROPIC_API_KEY or ANTHROPIC_API_KEY"
    )
  end

  return #errors == 0, errors
end

-- Get authentication headers for Anthropic's API
-- @param config table Provider configuration
-- @return table headers HTTP headers with x-api-key and anthropic-version
function M:get_auth_headers(config)
  local api_key = get_api_key(config)
  return {
    ["x-api-key"] = api_key or "",
    ["anthropic-version"] = "2023-06-01",
    ["content-type"] = "application/json",
  }
end

-- Get Anthropic provider capabilities
-- @return table capabilities Provider feature support
function M:get_capabilities()
  return {
    supports_streaming = false, -- Not implemented yet
    supports_multiple_generations = false, -- Messages API does not support an "n" parameter
    max_generations = 1,
  }
end

return M
