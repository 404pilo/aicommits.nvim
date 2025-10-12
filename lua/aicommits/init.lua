-- Main entry point for aicommits.nvim
local M = {}

-- Plugin version and metadata
M.version = "0.2.0-dev"
M._source = debug.getinfo(1, "S").source

-- Plugin state
local state = {
  initialized = false,
}

-- Setup plugin with user configuration
function M.setup(opts)
  local notifications = require("aicommits.notifications")

  if state.initialized then
    notifications.warn("aicommits.nvim is already initialized")
    return
  end

  -- Load and merge configuration
  local config = require("aicommits.config")
  config.setup(opts)

  -- Validate configuration
  local valid, errors = config.validate()
  if not valid then
    notifications.config_error(errors)
    return
  end

  -- Initialize provider registry
  local providers = require("aicommits.providers")
  providers.setup()

  -- Register commands
  local commands = require("aicommits.commands")
  commands.setup()

  -- Initialize integrations
  local neogit_integration = require("aicommits.integrations.neogit")
  neogit_integration.setup()

  state.initialized = true
end

-- Main commit function (pure Lua implementation)
function M.commit()
  local utils = require("aicommits.utils")

  if not state.initialized then
    utils.notify_error("aicommits.nvim is not initialized. Call setup() first.")
    return
  end

  -- Run the commit workflow (provider validation happens in commit.generate_and_commit)
  local commit = require("aicommits.commit")
  commit.generate_and_commit()
end

-- Check if plugin is initialized
function M.is_initialized()
  return state.initialized
end

-- Debug information
function M.debug_info()
  local config = require("aicommits.config")

  vim.print("=== aicommits.nvim Debug Info ===")
  vim.print("")

  -- Plugin info
  vim.print("1. PLUGIN INFO:")
  local plugin_info = {
    version = M.version,
    source = M._source,
    initialized = state.initialized,
    neogit_integration_loaded = package.loaded["aicommits.integrations.neogit"] ~= nil,
    config_loaded = package.loaded["aicommits.config"] ~= nil,
  }
  vim.print(plugin_info)
  vim.print("")

  -- Full config check
  vim.print("2. FULL CONFIG:")
  local full_config = config.get()
  vim.print(full_config)
  vim.print("")

  -- Neogit config check
  vim.print("3. NEOGIT CONFIG:")
  local neogit_config = config.get("integrations.neogit")
  vim.print(neogit_config)
  vim.print("")

  -- Debug mode check
  vim.print("4. DEBUG MODE:")
  vim.print("  debug = " .. tostring(config.get("debug")))
  vim.print("")

  -- Autocmd group check
  vim.print("5. AUTOCMD GROUP CHECK:")
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "AicommitsNeogitIntegration" })
  if ok then
    vim.print("  Group exists: YES")
    vim.print("  Autocmds count: " .. #autocmds)
    if #autocmds > 0 then
      vim.print("  Autocmds:")
      for i, ac in ipairs(autocmds) do
        vim.print(string.format("    [%d] event=%s, pattern=%s", i, ac.event, ac.pattern or "none"))
      end
    end
  else
    vim.print("  Group exists: NO")
    vim.print("  Error: " .. tostring(autocmds))
  end
  vim.print("")

  -- Current buffer check
  vim.print("6. CURRENT BUFFER:")
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local buftype = vim.bo[bufnr].buftype
  local filetype = vim.bo[bufnr].filetype
  vim.print(string.format("  Buffer: %d", bufnr))
  vim.print(string.format("  Name: %s", bufname))
  vim.print(string.format("  Buftype: %s", buftype))
  vim.print(string.format("  Filetype: %s", filetype))
  vim.print("")

  -- Check if in Neogit
  local in_neogit = filetype == "NeogitStatus"
  vim.print("7. IN NEOGIT STATUS?")
  vim.print("  " .. (in_neogit and "YES" or "NO"))
  if in_neogit then
    -- Check for keymap
    vim.print("")
    vim.print("8. KEYMAP CHECK (in Neogit):")
    local key = (neogit_config and neogit_config.mappings and neogit_config.mappings.key) or "C"
    local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
    local found = false
    for _, map in ipairs(maps) do
      if map.lhs == key then
        found = true
        vim.print(string.format("  Found '%s' -> %s", key, map.desc or map.rhs or "???"))
        break
      end
    end
    if not found then
      vim.print(string.format("  Keymap '%s' NOT FOUND", key))
    end
  end
  vim.print("")

  -- Manual setup test
  vim.print("9. MANUAL SETUP TEST:")
  vim.print("  Calling neogit integration setup()...")
  local setup_ok, setup_err = pcall(function()
    require("aicommits.integrations.neogit").setup()
  end)
  if setup_ok then
    vim.print("  SUCCESS - setup() ran without errors")
  else
    vim.print("  ERROR - " .. tostring(setup_err))
  end
  vim.print("")

  vim.print("=================================")

  return plugin_info
end

return M
