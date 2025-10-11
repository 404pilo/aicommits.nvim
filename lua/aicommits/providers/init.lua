-- Provider registry and management for aicommits.nvim
-- Manages registration, discovery, and loading of AI providers
local M = {}

-- Internal provider registry
-- Maps provider name -> provider implementation
local providers = {}

-- Register a provider in the registry
-- @param name string Unique provider identifier
-- @param provider table Provider implementation (must implement base interface)
function M.register(name, provider)
  if not name or name == "" then
    error("Provider name cannot be empty")
  end

  if not provider then
    error(string.format("Cannot register nil provider for '%s'", name))
  end

  if not provider.generate_commit_message then
    error(string.format("Provider '%s' must implement generate_commit_message method", name))
  end

  providers[name] = provider
end

-- Get a provider by name
-- @param name string Provider identifier
-- @return table|nil provider The provider implementation or nil if not found
function M.get(name)
  return providers[name]
end

-- List all registered provider names
-- @return table names Array of provider names
function M.list()
  local names = {}
  for name, _ in pairs(providers) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

-- Get the active provider based on configuration
-- Validates that the provider is registered, enabled, and properly configured
-- @return table|nil provider The active provider instance
-- @return string|nil error Error message if provider cannot be loaded
function M.get_active_provider()
  local config = require("aicommits.config")
  local active_name = config.get("active_provider")

  -- Check if active provider is configured
  if not active_name or active_name == "" then
    return nil, "No active provider configured. Set 'active_provider' in your configuration."
  end

  -- Check if provider is registered
  local provider = providers[active_name]
  if not provider then
    local available = M.list()
    local available_str = #available > 0 and table.concat(available, ", ") or "none"
    return nil,
      string.format("Provider '%s' not found. Available providers: %s", active_name, available_str)
  end

  -- Get provider configuration
  local provider_config = config.get("providers." .. active_name)
  if not provider_config then
    return nil, string.format("No configuration found for provider '%s'", active_name)
  end

  -- Check if provider is enabled
  if provider_config.enabled == false then
    return nil, string.format("Provider '%s' is disabled. Set providers.%s.enabled = true", active_name, active_name)
  end

  -- Validate provider configuration
  local valid, errors = provider:validate_config(provider_config)
  if not valid then
    local error_msg = string.format("Provider '%s' configuration is invalid:\n  - %s", active_name, table.concat(errors, "\n  - "))
    return nil, error_msg
  end

  return provider, nil
end

-- Initialize built-in providers
-- Called during plugin setup to register default providers
function M.setup()
  -- Register OpenAI provider
  local ok, openai_provider = pcall(require, "aicommits.providers.openai")
  if ok then
    M.register("openai", openai_provider)
  else
    vim.notify("Failed to load OpenAI provider: " .. tostring(openai_provider), vim.log.levels.ERROR)
  end

  -- Future: Register additional built-in providers
  -- local ok, anthropic_provider = pcall(require, "aicommits.providers.anthropic")
  -- if ok then
  --   M.register("anthropic", anthropic_provider)
  -- end
end

return M
