-- OpenAI provider implementation for aicommits.nvim
local base = require("aicommits.providers.base")
local request = require("aicommits.request")

-- Create OpenAI provider instance
local M = base.new({
  name = "openai",
})

-- Public Chat Completions API values for reasoning_effort/verbosity. These differ from
-- codex.lua's enums (that backend accepts minimal/max; the public API 400s on them).
local VALID_REASONING_EFFORTS = {
  none = true,
  low = true,
  medium = true,
  high = true,
  xhigh = true,
}

local VALID_VERBOSITIES = {
  low = true,
  medium = true,
  high = true,
}

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

-- Detect GPT-5-family/o-series reasoning models (e.g. gpt-5.6-luna, o1, o3-mini).
-- @param model string Model name
-- @return boolean
local function is_reasoning_model(model)
  return type(model) == "string" and (model:match("^gpt%-5") ~= nil or model:match("^o%d") ~= nil)
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
  local model = envelope.model or config.model or "gpt-4.1-nano"

  local request_body = {
    model = model,
    messages = {
      { role = "system", content = envelope.system },
      { role = "user", content = envelope.user },
    },
    stream = false,
    n = envelope.n or 1,
  }

  if is_reasoning_model(model) then
    -- Reasoning models reject max_tokens, and fix temperature/top_p/frequency_penalty/
    -- presence_penalty at their own defaults; sending non-default values 400s.
    request_body.max_completion_tokens = envelope.max_tokens
    if type(config.reasoning_effort) == "string" and config.reasoning_effort ~= "" then
      request_body.reasoning_effort = config.reasoning_effort
    end
    if type(config.verbosity) == "string" and config.verbosity ~= "" then
      request_body.verbosity = config.verbosity
    end
  else
    request_body.temperature = envelope.temperature
    request_body.top_p = envelope.top_p
    request_body.frequency_penalty = envelope.frequency_penalty
    request_body.presence_penalty = envelope.presence_penalty
    request_body.max_tokens = envelope.max_tokens
  end

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

    -- At high reasoning effort the model can nondeterministically burn the whole
    -- token budget on reasoning and return HTTP 200 with empty content and
    -- finish_reason "length"; surface that distinctly from "no choices at all".
    local texts = {}
    local saw_length_truncation = false
    for _, choice in ipairs(response.choices) do
      local content = choice.message and choice.message.content
      if type(content) == "string" and content:match("%S") then
        table.insert(texts, content)
      elseif choice.finish_reason == "length" then
        saw_length_truncation = true
      end
    end

    if #texts == 0 then
      if saw_length_truncation then
        callback(
          "Response truncated: reasoning consumed the token budget. Increase max_tokens or lower reasoning_effort.",
          nil
        )
      else
        callback("No commit messages were generated. Try again.", nil)
      end
      return
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

  -- Validate reasoning_effort (only used for gpt-5-family reasoning models)
  if config.reasoning_effort ~= nil and not VALID_REASONING_EFFORTS[config.reasoning_effort] then
    table.insert(errors, "reasoning_effort must be one of: none, low, medium, high, xhigh")
  end

  -- Validate verbosity (only used for gpt-5-family reasoning models)
  if config.verbosity ~= nil and not VALID_VERBOSITIES[config.verbosity] then
    table.insert(errors, "verbosity must be one of: low, medium, high")
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
