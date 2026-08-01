-- OpenAI provider implementation for aicommits.nvim
local base = require("aicommits.providers.base")
local request = require("aicommits.request")

-- Create OpenAI provider instance
local M = base.new({
  name = "openai",
})

-- Verified reasoning_effort/verbosity rules per gpt-5-family/o-series model, from
-- live probing of the public Chat Completions API (README.md carries the same table
-- for users). Add a row here only for a model that has actually been probed;
-- unmatched models are deliberately left unvalidated (see classify_model below).
--
-- Each enum is authored ONCE as an ordered list and its lookup `set` is derived.
-- Hand-writing both forms would let them drift, and a value present in `order` but
-- missing from `set` would be advertised by the error message and rejected by the
-- check at the same time.
-- @param order string[] Valid values, in the order error messages should list them
-- @return table { set, order }
local function enum(order)
  local set = {}
  for _, value in ipairs(order) do
    set[value] = true
  end
  return { set = set, order = order }
end

local FULL_VERBOSITY = enum({ "low", "medium", "high" })

local GPT5_BARE_RULE = {
  reasoning_effort = enum({ "minimal", "low", "medium", "high" }),
  verbosity = FULL_VERBOSITY,
}

local GPT5_1_RULE = {
  reasoning_effort = enum({ "none", "low", "medium", "high" }),
  verbosity = FULL_VERBOSITY,
}

local GPT5_2_TO_6_RULE = {
  reasoning_effort = enum({ "none", "low", "medium", "high", "xhigh" }),
  verbosity = FULL_VERBOSITY,
}

local GPT5_CHAT_LATEST_RULE = {
  reasoning_effort = enum({ "medium" }),
  verbosity = FULL_VERBOSITY,
}

local O_SERIES_RULE = {
  reasoning_effort = enum({ "low", "medium", "high", "xhigh" }),
  verbosity = enum({ "medium" }),
}

-- Which rule each PROBED gpt-5.N minor version maps to. Keys are the digit as it
-- appears in the model name; "0" is the sentinel for no version decimal at all
-- (bare gpt-5, gpt-5-mini, gpt-5-nano). Absent keys are deliberate: "3" because
-- bare gpt-5.3 does not exist on this endpoint (only gpt-5.3-chat-latest, handled
-- by the suffix override), and 7-9 because they do not exist yet.
local PROBED_MINOR_RULES = {
  ["0"] = GPT5_BARE_RULE,
  ["1"] = GPT5_1_RULE,
  ["2"] = GPT5_2_TO_6_RULE,
  ["4"] = GPT5_2_TO_6_RULE,
  ["5"] = GPT5_2_TO_6_RULE,
  ["6"] = GPT5_2_TO_6_RULE,
}

-- Suffixes verified not to change a gpt-5.N row's valid values, relative to the
-- bare version number (gpt-5-mini/gpt-5-nano, gpt-5.4-mini/nano, and the named
-- gpt-5.6 variants all matched their base version in probing).
local KNOWN_GPT5_SUFFIXES = {
  [""] = true,
  ["-mini"] = true,
  ["-nano"] = true,
  ["-luna"] = true,
  ["-sol"] = true,
  ["-terra"] = true,
}

-- Resolve a model name to its verified reasoning_effort/verbosity rule.
-- Returns nil for anything not explicitly probed; callers MUST treat nil as
-- "accept any non-empty value", never as "reject everything" -- this table
-- will go stale as OpenAI ships models, and a stale rejection is worse than
-- the 400 it's meant to prevent.
-- @param model string|nil
-- @return table|nil rule
local function classify_model(model)
  if type(model) ~= "string" then
    return nil
  end

  -- Only o3 and o4-mini were probed; the rest of the o-series (o1, o3-mini,
  -- o3-pro, o4-mini-deep-research, ...) is deliberately left unmatched.
  if model == "o3" or model == "o4-mini" then
    return O_SERIES_RULE
  end

  local minor, suffix = model:match("^gpt%-5%.(%d)(.-)$")
  if not minor and (model == "gpt-5" or model:match("^gpt%-5%-")) then
    minor = "0" -- sentinel: no version decimal (bare gpt-5, gpt-5-mini, gpt-5-nano, ...)
    suffix = model:sub(6) -- everything after "gpt-5"
  end
  if not minor then
    return nil
  end

  -- *-chat-latest overrides the row for any base version, including bare gpt-5.
  if suffix == "-chat-latest" then
    return GPT5_CHAT_LATEST_RULE
  end
  if not KNOWN_GPT5_SUFFIXES[suffix] then
    return nil
  end

  -- Keyed by the minor version actually probed, NOT by a ">= 2" range. A future
  -- gpt-5.7 that OpenAI ships with a new effort value would match a range test and
  -- get that value spuriously rejected -- exactly the stale-table failure this
  -- provider is built to avoid. Unprobed minors (3, and everything past 6) fall
  -- through to nil and are left to the API. Add a row here only after probing.
  return PROBED_MINOR_RULES[minor]
end

-- Build an actionable "<field> not supported by this model" error.
-- @param field string Config key name
-- @param model string
-- @param value string
-- @param field_enum table Enum returned by enum()
-- @return string
local function unsupported_error(field, model, value, field_enum)
  return string.format(
    '%s "%s" is not supported by model "%s". Supported values: %s.',
    field,
    value,
    model,
    table.concat(field_enum.order, ", ")
  )
end

-- As unsupported_error, plus the none/minimal naming split across model
-- generations -- the single most confusing cell in the table, and reachable
-- from a default the user never typed.
-- @param model string
-- @param value string
-- @param rule table Rule returned by classify_model
-- @return string
local function reasoning_effort_error(model, value, rule)
  local msg = unsupported_error("reasoning_effort", model, value, rule.reasoning_effort)
  if value == "none" and rule.reasoning_effort.set.minimal then
    msg = msg .. ' ("none" is the gpt-5.2+ spelling of "minimal" -- set reasoning_effort = "minimal" for this model.)'
  elseif value == "minimal" and rule.reasoning_effort.set.none then
    msg = msg .. ' ("minimal" is the gpt-5-base spelling of "none" -- set reasoning_effort = "none" for this model.)'
  end
  return msg
end

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

  -- reasoning_effort/verbosity are only enum-checked against a model we've actually
  -- probed (see classify_model); anything else gets only the non-empty-string floor.
  local rule = classify_model(config.model)

  if config.reasoning_effort ~= nil then
    if type(config.reasoning_effort) ~= "string" or config.reasoning_effort == "" then
      table.insert(errors, "reasoning_effort must be a non-empty string")
    elseif rule and not rule.reasoning_effort.set[config.reasoning_effort] then
      table.insert(errors, reasoning_effort_error(config.model, config.reasoning_effort, rule))
    end
  end

  if config.verbosity ~= nil then
    if type(config.verbosity) ~= "string" or config.verbosity == "" then
      table.insert(errors, "verbosity must be a non-empty string")
    elseif rule and not rule.verbosity.set[config.verbosity] then
      table.insert(errors, unsupported_error("verbosity", config.model, config.verbosity, rule.verbosity))
    end
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
