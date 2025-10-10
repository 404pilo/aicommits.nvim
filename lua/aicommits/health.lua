-- Health check module for aicommits.nvim
-- Used by :checkhealth aicommits command

local M = {}

-- Helper to check if a command exists
local function command_exists(cmd)
  local handle = io.popen("command -v " .. cmd .. " 2>/dev/null")
  if not handle then
    return false
  end
  local result = handle:read("*a")
  handle:close()
  return result ~= ""
end

-- Helper to get command version
local function get_version(cmd, args)
  args = args or "--version"
  local handle = io.popen(cmd .. " " .. args .. " 2>/dev/null")
  if not handle then
    return nil
  end
  local result = handle:read("*a")
  handle:close()
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

-- Check OpenAI API key
local function check_api_key()
  local openai = require("aicommits.openai")
  local api_key = openai.get_api_key()

  if not api_key or api_key == "" then
    vim.health.error("OpenAI API key not found", {
      "Set AICOMMITS_NVIM_OPENAI_API_KEY environment variable (recommended)",
      "Or set OPENAI_API_KEY environment variable",
    })
    return false
  else
    -- Don't show the actual key, just confirm it exists
    local masked = api_key:sub(1, 7) .. "..." .. api_key:sub(-4)
    vim.health.ok(string.format("API key configured (%s)", masked))
    return true
  end
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
  local api_key_ok = check_api_key()

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
  local all_required = nvim_ok and git_ok and curl_ok and api_key_ok and config_ok

  if all_required then
    vim.health.ok("All required dependencies are satisfied. You're ready to use aicommits.nvim!")
  else
    vim.health.error("Some required dependencies are missing", "Fix the errors above to use aicommits.nvim")
  end
end

return M
