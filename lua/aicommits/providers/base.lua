-- Base provider interface for AI commit message generation
-- All providers must implement this interface
local M = {}

-- Provider interface (abstract class)
-- Each provider implementation should extend this interface
M.Provider = {
  -- Unique identifier for this provider (e.g., "openai", "anthropic")
  name = nil,

  -- Provider-agnostic transport: shape the envelope into the provider's API body,
  -- send via request.send, and parse the response into a normalized text array.
  -- @param envelope        table  Provider-agnostic LLM request (system/user/model/n/...)
  -- @param provider_config table  Provider-specific configuration
  -- @param callback        function(error, texts)  texts = array of candidate strings
  generate_text = function(self, envelope, provider_config, callback)
    error(string.format("Provider '%s' must implement generate_text", self.name or "unknown"))
  end,

  -- Validate provider configuration
  -- @param config table Provider-specific configuration
  -- @return boolean valid True if configuration is valid
  -- @return table errors Array of error messages (empty if valid)
  validate_config = function(self, config)
    return true, {}
  end,

  -- Get HTTP authentication headers for API requests
  -- @param config table Provider-specific configuration
  -- @return table headers Key-value pairs of HTTP headers
  get_auth_headers = function(self, config)
    return {}
  end,

  -- Get provider capabilities (optional, defaults provided)
  -- @return table capabilities Provider feature support
  get_capabilities = function(self)
    return {
      supports_streaming = false, -- Does provider support streaming responses?
      supports_multiple_generations = false, -- Can provider generate multiple options?
      max_generations = 1, -- Maximum number of messages that can be generated
    }
  end,
}

-- Generic commit-message generation, shared by all providers. Builds the universal
-- envelope from config, delegates transport to the provider's generate_text, then
-- normalizes the candidate texts into commit messages.
-- @param diff     string The git diff output
-- @param config   table  Provider-specific configuration
-- @param callback function(error, messages) error or array of commit messages
function M.Provider:generate_commit_message(diff, config, callback)
  local prompts = require("aicommits.prompts")
  local envelope = {
    system = prompts.build_system_prompt(config.max_length or 50, config.commitlint_config),
    user = diff,
    model = config.model,
    max_tokens = config.max_tokens,
    temperature = config.temperature,
    n = config.generate or 1,
    top_p = config.top_p,
    frequency_penalty = config.frequency_penalty,
    presence_penalty = config.presence_penalty,
    thinking_budget = config.thinking_budget,
  }
  self:generate_text(envelope, config, function(err, texts)
    if err then
      return callback(err, nil)
    end
    local processed = prompts.process_messages(texts or {})
    if #processed == 0 then
      return callback("No valid commit messages were generated. Try again.", nil)
    end
    callback(nil, processed)
  end)
end

-- Create a new provider instance
-- @param provider_impl table Provider implementation with methods
-- @return table provider A new provider instance
function M.new(provider_impl)
  if not provider_impl.name then
    error("Provider implementation must specify a 'name' field")
  end

  local instance = vim.tbl_extend("force", {}, M.Provider, provider_impl)
  return instance
end

return M
