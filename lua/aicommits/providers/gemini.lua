-- Google Gemini API (AI Studio) provider implementation for aicommits.nvim
-- Uses generativelanguage.googleapis.com endpoint with simple API key authentication
local base = require("aicommits.providers.base")
local request = require("aicommits.request")

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

-- Provider-agnostic transport for Gemini API (AI Studio).
-- @param envelope table { system, user, model, max_tokens, temperature, n }
-- @param config   table Provider configuration
-- @param callback function(error, texts)
function M:generate_text(envelope, config, callback)
  local api_key = get_api_key(config)
  if not api_key then
    callback(
      "Gemini API key not found. Set 'providers[\"gemini-api\"].api_key' in config or environment variable AICOMMITS_NVIM_GEMINI_API_KEY or GEMINI_API_KEY",
      nil
    )
    return
  end

  local model = envelope.model or config.model or "gemini-2.5-flash"
  local endpoint = string.format("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)

  local generation_config = {
    temperature = envelope.temperature,
    maxOutputTokens = envelope.max_tokens,
    candidateCount = envelope.n or 1,
  }
  if config.thinking_budget ~= nil then
    generation_config.thinkingConfig = { thinkingBudget = config.thinking_budget }
  end

  local request_body = {
    contents = {
      { role = "user", parts = { { text = (envelope.system or "") .. "\n\n" .. (envelope.user or "") } } },
    },
    generationConfig = generation_config,
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
      callback("Failed to parse Gemini API response: " .. tostring(response), nil)
      return
    end

    if response.error then
      callback("Gemini API Error: " .. (response.error.message or vim.inspect(response.error)), nil)
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

  -- Validate thinking_budget (0 = disabled, -1 = dynamic, 1-24576 = manual)
  if config.thinking_budget then
    if type(config.thinking_budget) ~= "number" then
      table.insert(errors, "thinking_budget must be a number")
    elseif config.thinking_budget ~= -1 and (config.thinking_budget < 0 or config.thinking_budget > 24576) then
      table.insert(errors, "thinking_budget must be -1 (dynamic), 0 (disabled), or between 1 and 24576")
    end
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
