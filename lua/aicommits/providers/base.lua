-- Base provider interface for AI commit message generation
-- All providers must implement this interface
local M = {}

-- Provider interface (abstract class)
-- Each provider implementation should extend this interface
M.Provider = {
  -- Unique identifier for this provider (e.g., "openai", "anthropic")
  name = nil,

  -- Generate commit message(s) from a git diff
  -- @param diff string The git diff output
  -- @param config table Provider-specific configuration
  -- @param callback function(error, messages) Callback with error or array of commit messages
  generate_commit_message = function(self, diff, config, callback)
    error(string.format("Provider '%s' must implement generate_commit_message", self.name or "unknown"))
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

  -- Summarize a piece of text (diff chunk, chunk summaries, or small-file batch)
  -- @param text           string  The content to summarize
  -- @param opts           table   { prompt_kind, file_path, model, max_tokens, temperature }
  -- @param provider_config table  Same table as generate_commit_message receives
  -- @param callback       function(error, summary_text)
  summarize = function(self, text, opts, provider_config, callback)
    error(string.format("Provider '%s' must implement summarize", self.name or "unknown"))
  end,
}

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
