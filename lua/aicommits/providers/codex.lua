-- Codex (ChatGPT OAuth) provider implementation for aicommits.nvim
--
-- Authenticates by reading the local Codex CLI OAuth session
-- ($CODEX_HOME/auth.json, defaulting to ~/.codex/auth.json) so requests spend
-- the user's ChatGPT subscription quota instead of per-token API credits.
--
-- Strictly read-only: this provider never writes auth.json, never mints or
-- refreshes tokens, and never shells out. See
-- docs/superpowers/specs/2026-07-31-codex-oauth-provider-design.md for the
-- empirical findings this implementation is built from.
local base = require("aicommits.providers.base")
local request = require("aicommits.request")

-- Create Codex provider instance
local M = base.new({
  name = "codex",
})

-- ── Constants ────────────────────────────────────────────────────────────
local DEFAULT_ENDPOINT = "https://chatgpt.com/backend-api/codex/responses"
local ORIGINATOR = "codex_cli_rs"
local OPENAI_BETA = "responses_websockets=2026-02-06"
local CODEX_CLI_VERSION = "0.146.0"

local VALID_REASONING_EFFORTS = {
  none = true,
  minimal = true,
  low = true,
  medium = true,
  high = true,
  xhigh = true,
  max = true,
}

local VALID_VERBOSITIES = {
  low = true,
  medium = true,
  high = true,
}

local CREDENTIALS_ERROR = "Codex credentials not found. Run: `codex login`"
local SESSION_EXPIRED_ERROR = "Codex session expired. Run: `codex login`"

-- ── Private helpers ──────────────────────────────────────────────────────

-- Resolve the Codex CLI OAuth session from $CODEX_HOME/auth.json (or
-- ~/.codex/auth.json). Synchronous, READ-ONLY: never writes, never caches,
-- never single-flights. A fresh read on every call means a refresh performed
-- by the Codex CLI behind our back is always picked up.
-- @param config table Provider configuration (unused; kept for interface symmetry)
-- @return string|nil token The access token, or nil on failure
-- @return string|nil account_id The ChatGPT account id, or nil on failure
-- @return string|nil err The user-facing error, or nil on success
local function _get_access_token(config)
  local home = vim.env.CODEX_HOME
  if not home or home == "" then
    home = vim.fn.expand("~/.codex")
  end
  home = home:gsub("/$", "")
  local path = home .. "/auth.json"

  if vim.fn.filereadable(path) ~= 1 then
    return nil, nil, CREDENTIALS_ERROR
  end

  local read_ok, lines = pcall(vim.fn.readfile, path)
  if not read_ok then
    return nil, nil, CREDENTIALS_ERROR
  end

  local decode_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decode_ok or type(decoded) ~= "table" or type(decoded.tokens) ~= "table" then
    return nil, nil, CREDENTIALS_ERROR
  end

  local access_token = decoded.tokens.access_token
  local account_id = decoded.tokens.account_id

  -- JSON null decodes to vim.NIL (truthy userdata), so validate by type, never
  -- by Lua truthiness.
  if type(access_token) ~= "string" or access_token == "" then
    return nil, nil, CREDENTIALS_ERROR
  end
  if type(account_id) ~= "string" or account_id == "" then
    return nil, nil, CREDENTIALS_ERROR
  end

  return access_token, account_id, nil
end

-- Build the fixed client-identity header set the ChatGPT Codex backend expects.
-- @param token string Access token (may be empty string as a safe placeholder)
-- @param account_id string ChatGPT account id (may be empty string)
-- @return table headers HTTP headers
local function _build_headers(token, account_id)
  local sysname, machine = "unknown", "unknown"
  local uname_ok, uname = pcall(function()
    return (vim.uv or vim.loop).os_uname()
  end)
  if uname_ok and type(uname) == "table" then
    sysname = uname.sysname or "unknown"
    machine = uname.machine or "unknown"
  end

  return {
    Authorization = "Bearer " .. token,
    ["ChatGPT-Account-ID"] = account_id,
    originator = ORIGINATOR,
    ["User-Agent"] = string.format("codex_cli_rs/%s (%s %s)", CODEX_CLI_VERSION, sysname, machine),
    ["OpenAI-Beta"] = OPENAI_BETA,
  }
end

-- Normalize the ChatGPT Codex backend's two error envelope shapes into one
-- user-facing string. Never echoes raw response body text.
-- @param status number HTTP status code
-- @param body string|nil Raw response body
-- @return string err
local function _extract_api_error(status, body)
  if status == 401 then
    return SESSION_EXPIRED_ERROR
  end

  local decode_ok, decoded = pcall(vim.json.decode, body)
  if not decode_ok or type(decoded) ~= "table" then
    return string.format("Codex API Error (HTTP %d)", status)
  end

  if type(decoded.detail) == "string" then
    return "Codex API Error: " .. decoded.detail .. " (parameter not supported by the ChatGPT Codex backend)"
  end

  if type(decoded.error) == "table" then
    local message = decoded.error.message
    return "Codex API Error: " .. (type(message) == "string" and message or vim.inspect(decoded.error))
  end

  return string.format("Codex API Error (HTTP %d)", status)
end

-- Parse the buffered SSE blob curl returns (http.lua does not stream) into the
-- concatenated commit-message text.
-- @param body string Raw response body (one blob of SSE frames)
-- @return string text Concatenated `response.output_text.delta` text, arrival order
-- @return boolean saw_completed Whether a `response.completed` event arrived
local function _parse_sse(body)
  local chunks = {}
  local saw_completed = false

  for _, raw_line in ipairs(vim.split(body, "\n", { plain = true })) do
    local line = raw_line:gsub("\r$", "")
    if line ~= "" then
      local payload = line:match("^data:%s*(.*)$")
      if payload and payload ~= "" and payload ~= "[DONE]" then
        local decode_ok, event = pcall(vim.json.decode, payload)
        if decode_ok and type(event) == "table" and type(event.type) == "string" then
          if event.type == "response.output_text.delta" then
            if type(event.delta) == "string" then
              table.insert(chunks, event.delta)
            end
          elseif event.type == "response.completed" then
            saw_completed = true
          end
          -- All other event types (reasoning summaries, response.failed, error
          -- frames, unknown types) are deliberately ignored.
        end
      end
    end
  end

  return table.concat(chunks), saw_completed
end

-- ── Public methods ───────────────────────────────────────────────────────

--- Provider-agnostic transport for the ChatGPT Codex backend.
--- @param envelope table Provider-agnostic LLM request; only `model`, `system`, and `user` are read
--- @param config table Provider-specific configuration
--- @param callback function(error, texts) error string or one-element texts array
function M:generate_text(envelope, config, callback)
  local token, account_id, auth_err = _get_access_token(config)
  if auth_err then
    callback(auth_err, nil)
    return
  end

  local body = {
    model = envelope.model or config.model,
    stream = true,
    store = false,
    input = {
      { role = "developer", content = { { type = "input_text", text = envelope.system } } },
      { role = "user", content = { { type = "input_text", text = envelope.user } } },
    },
  }

  if type(config.reasoning_effort) == "string" and config.reasoning_effort ~= "" then
    body.reasoning = { effort = config.reasoning_effort }
  end
  if type(config.verbosity) == "string" and config.verbosity ~= "" then
    body.text = { verbosity = config.verbosity }
  end

  local endpoint = (config.endpoint and config.endpoint ~= "") and config.endpoint or DEFAULT_ENDPOINT

  request.send({
    url = endpoint,
    headers = _build_headers(token, account_id),
    body = vim.json.encode(body),
    policy = request.resolve_policy(config),
  }, function(err, result)
    if err then
      callback(err, nil)
      return
    end

    local status = result and result.status or 0
    if status >= 400 then
      callback(_extract_api_error(status, result.body), nil)
      return
    end

    local text, saw_completed = _parse_sse(result.body or "")
    if not saw_completed or text:match("^%s*$") then
      callback("No commit messages were generated. Try again.", nil)
      return
    end

    callback(nil, { text })
  end)
end

--- Validate Codex provider configuration.
--- @param config table Provider configuration
--- @return boolean valid True if configuration is valid
--- @return table errors Array of error messages (empty if valid)
function M:validate_config(config)
  local errors = {}

  if not config.model or config.model == "" then
    table.insert(errors, "model is required and must be a non-empty string")
  end

  if config.max_length ~= nil and (type(config.max_length) ~= "number" or config.max_length <= 0) then
    table.insert(errors, "max_length must be a positive number")
  end

  if config.generate ~= nil and config.generate ~= 1 then
    table.insert(errors, "generate must be 1; the ChatGPT Codex backend does not support multiple candidates")
  end

  if config.reasoning_effort ~= nil and not VALID_REASONING_EFFORTS[config.reasoning_effort] then
    table.insert(errors, "reasoning_effort must be one of: none, minimal, low, medium, high, xhigh, max")
  end

  if config.verbosity ~= nil and not VALID_VERBOSITIES[config.verbosity] then
    table.insert(errors, "verbosity must be one of: low, medium, high")
  end

  local _token, _account_id, auth_err = _get_access_token(config)
  if auth_err then
    table.insert(errors, auth_err)
  end

  return #errors == 0, errors
end

--- Get authentication headers for the ChatGPT Codex backend.
--- Never raises and never surfaces the auth error; callers that need the
--- error should use `validate_config` or `generate_text`'s callback instead.
--- @param config table Provider configuration
--- @return table headers HTTP headers
function M:get_auth_headers(config)
  local token, account_id, _err = _get_access_token(config)
  return _build_headers(token or "", account_id or "")
end

--- Get Codex provider capabilities.
--- @return table capabilities Provider feature support
function M:get_capabilities()
  return {
    supports_streaming = false,
    supports_multiple_generations = false,
    max_generations = 1,
  }
end

return M
