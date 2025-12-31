-- Health check module for aicommits.nvim
-- Used by :checkhealth aicommits command

local M = {}

-- Helper to check if a command exists
local function command_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

-- Helper to get command version
local function get_version(cmd, args)
  args = args or "--version"
  local result = vim.fn.system({ cmd, args })
  return result:match("(%d+%.%d+%.%d+)") or result:match("(%d+%.%d+)")
end

-- Check Neovim version
local function check_neovim()
  local version = vim.version()
  local version_str = string.format("%d.%d.%d", version.major, version.minor, version.patch)

  if version.major == 0 and version.minor < 9 then
    vim.health.error(string.format("Neovim %s is too old", version_str), "Neovim 0.9+ is required. Please upgrade.")
    return false
  else
    vim.health.ok(string.format("Neovim version %s", version_str))
    return true
  end
end

-- Check Git availability
local function check_git()
  if not command_exists("git") then
    vim.health.error("Git not found", "Please install Git")
    return false
  end

  local version = get_version("git")
  if version then
    vim.health.ok(string.format("Git version %s", version))
    return true
  else
    vim.health.warn("Could not determine Git version")
    return true
  end
end

-- Check curl availability
local function check_curl()
  if not command_exists("curl") then
    vim.health.error("curl not found", "Please install curl for HTTP requests")
    return false
  end

  local version = get_version("curl")
  if version then
    vim.health.ok(string.format("curl version %s", version))
    return true
  else
    vim.health.ok("curl is available")
    return true
  end
end

-- Check provider configuration and availability
local function check_provider()
  local config = require("aicommits.config")
  local providers = require("aicommits.providers")

  local active_name = config.get("active_provider")

  if not active_name or active_name == "" then
    vim.health.error("No active provider configured", "Set 'active_provider' in your configuration")
    return false
  end

  vim.health.ok(string.format("Active provider: %s", active_name))

  -- Check if provider is registered
  local provider = providers.get(active_name)
  if not provider then
    local available = providers.list()
    local available_str = #available > 0 and table.concat(available, ", ") or "none"
    vim.health.error(
      string.format("Provider '%s' not found", active_name),
      string.format("Available providers: %s", available_str)
    )
    return false
  end

  vim.health.ok(string.format("Provider '%s' is registered", active_name))

  -- Get provider configuration
  local provider_config = config.get("providers." .. active_name)
  if not provider_config then
    vim.health.error(
      string.format("No configuration found for provider '%s'", active_name),
      string.format("Add 'providers.%s' configuration", active_name)
    )
    return false
  end

  -- Check if provider is enabled
  if provider_config.enabled == false then
    vim.health.error(
      string.format("Provider '%s' is disabled", active_name),
      string.format("Set 'providers.%s.enabled = true'", active_name)
    )
    return false
  end

  vim.health.ok(string.format("Provider '%s' is enabled", active_name))

  -- Validate provider configuration
  local valid, errors = provider:validate_config(provider_config)
  if not valid then
    vim.health.error(string.format("Provider '%s' configuration is invalid", active_name), errors)
    return false
  end

  vim.health.ok(string.format("Provider '%s' configuration is valid", active_name))
  return true
end

-- Check if in a git repository
local function check_git_repo()
  local git = require("aicommits.git")

  if git.is_git_repo() then
    vim.health.ok("Currently in a git repository")

    -- Additional git repo info
    if git.has_remote() then
      vim.health.ok("Git repository has remote configured")
    else
      vim.health.warn("No git remote configured", "Push functionality may be limited")
    end

    return true
  else
    vim.health.warn("Not currently in a git repository", "Navigate to a git repository to use aicommits.nvim")
    return false
  end
end

-- Check configuration validity
local function check_config()
  local config = require("aicommits.config")
  local valid, errors = config.validate()

  if valid then
    vim.health.ok("Configuration is valid")
    return true
  else
    vim.health.error("Configuration validation failed", errors)
    return false
  end
end

-- Check optional integrations
local function check_integrations()
  local config = require("aicommits.config")

  -- Check Neogit
  if config.get("integrations.neogit") then
    local has_neogit = pcall(require, "neogit")
    if has_neogit then
      vim.health.ok("Neogit integration enabled and available")
    else
      vim.health.warn(
        "Neogit integration enabled but plugin not found",
        "Install neogit or disable integration in config"
      )
    end
  end

  -- Check Fugitive
  if config.get("integrations.fugitive") then
    if vim.fn.exists(":Git") == 2 then
      vim.health.ok("Fugitive integration enabled and available")
    else
      vim.health.warn(
        "Fugitive integration enabled but plugin not found",
        "Install vim-fugitive or disable integration in config"
      )
    end
  end

  -- Check LazyGit
  if config.get("integrations.lazygit") then
    if command_exists("lazygit") then
      vim.health.ok("LazyGit integration enabled and available")
    else
      vim.health.warn(
        "LazyGit integration enabled but command not found",
        "Install lazygit or disable integration in config"
      )
    end
  end
end

-- Main health check function
function M.check()
  vim.health.start("aicommits.nvim - Pure Lua Implementation")

  -- Required dependencies
  vim.health.start("Required Dependencies")
  local nvim_ok = check_neovim()
  local git_ok = check_git()
  local curl_ok = check_curl()

  -- Provider configuration
  vim.health.start("Provider Configuration")
  local provider_ok = check_provider()

  -- Configuration
  vim.health.start("Configuration")
  local config_ok = check_config()

  -- Current environment
  vim.health.start("Current Environment")
  check_git_repo()

  -- Optional integrations
  vim.health.start("Optional Integrations")
  check_integrations()

  -- Summary
  vim.health.start("Summary")
  local all_required = nvim_ok and git_ok and curl_ok and provider_ok and config_ok

  if all_required then
    vim.health.ok("All required dependencies are satisfied. You're ready to use aicommits.nvim!")
  else
    vim.health.error("Some required dependencies are missing", "Fix the errors above to use aicommits.nvim")
  end
end

return M
