local M = {}

-- Import base provider to inherit from
local BaseProvider = require("aicommits.providers.base")
setmetatable(M, { __index = BaseProvider })
M.__index = M

--- Anthropic provider for commit message generation
--- @class AnthropicProvider
function M.new()
  local self = setmetatable({}, M)
  return self
end

--- Generate a commit message using Anthropic's Claude API
--- @param diff string The git diff
--- @param config table The provider configuration
--- @param callback function The callback for the result
function M:generate_commit_message(diff, config, callback)
  local api_key = config.api_key or os.getenv("ANTHROPIC_API_KEY")
  if not api_key then
    return callback("Anthropic API key not found. Please set it in config or ANTHROPIC_API_KEY env var.")
  end

  local payload = {
    model = config.model or "claude-3-5-haiku-20241022",
    max_tokens = config.max_tokens or 200,
    temperature = config.temperature or 0.7,
    system = "You are an expert software engineer. Generate a concise, professional conventional commit message based on the provided git diff. Return ONLY the commit message, no explanation.",
    messages = {
      { role = "user", content = "Generate a commit message for these changes:\n\n" .. diff },
    },
  }

  local request = {
    url = "https://api.anthropic.com/v1/messages",
    headers = {
      ["x-api-key"] = api_key,
      ["anthropic-version"] = "2023-06-01",
      ["content-type"] = "application/json",
    },
    body = vim.fn.json_encode(payload),
    method = "POST",
  }

  -- Use the shared HTTP helper
  local http = require("aicommits.http")
  http.request(request, function(err, response)
    if err then
      return callback(err)
    end

    local ok, data = pcall(vim.fn.json_decode, response)
    if not ok then
      return callback("Failed to decode Anthropic API response")
    end

    if data.error then
      return callback("Anthropic API error: " .. (data.error.message or "Unknown error"))
    end

    local content = data.content
    if type(content) == "table" and content[1] and content[1].text then
      callback(nil, content[1].text)
    else
      callback("Unexpected response format from Anthropic API")
    end
  end)
end

--- Health check for the Anthropic provider
function M.health_check(config)
  local api_key = config.api_key or os.getenv("ANTHROPIC_API_KEY")
  if not api_key then
    return false, "Missing API key (ANTHROPIC_API_KEY)"
  end
  return true, "Anthropic configured"
end

return M
