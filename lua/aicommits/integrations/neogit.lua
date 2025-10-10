-- Neogit integration for aicommits.nvim
local M = {}

--- Setup Neogit keymap integration
--- Registers a customizable keymap in Neogit status view to trigger :AICommit
function M.setup()
  local config = require("aicommits.config")

  -- DEBUG: Notify that setup is running
  if config.get("debug") then
    vim.notify("[aicommits] Neogit integration setup() called", vim.log.levels.DEBUG)
  end

  -- Get neogit config with fallback to defaults
  local neogit_config = config.get("integrations.neogit")
    or {
      enabled = true,
      mappings = {
        enabled = true,
        key = "C",
      },
    }

  -- Check if neogit integration is enabled
  if not neogit_config.enabled then
    if config.get("debug") then
      vim.notify("[aicommits] Neogit integration disabled in config", vim.log.levels.DEBUG)
    end
    return
  end

  -- Check if keymap integration is enabled
  local mappings = neogit_config.mappings or { enabled = true, key = "C" }
  if not mappings.enabled then
    if config.get("debug") then
      vim.notify("[aicommits] Neogit mappings disabled in config", vim.log.levels.DEBUG)
    end
    return
  end

  -- Get the configured key (default: "C")
  local key = mappings.key or "C"

  -- DEBUG: Notify autocmd creation
  if config.get("debug") then
    vim.notify("[aicommits] Creating Neogit FileType autocmd for key: " .. key, vim.log.levels.INFO)
  end

  -- Create autocmd to register keymap when Neogit status buffer opens
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "NeogitStatus",
    group = vim.api.nvim_create_augroup("AicommitsNeogitIntegration", { clear = true }),
    callback = function(event)
      -- DEBUG: Notify autocmd fired
      if config.get("debug") then
        vim.notify(
          string.format(
            "[aicommits] Neogit FileType autocmd fired! Buffer: %d, Filetype: %s",
            event.buf,
            vim.bo[event.buf].filetype
          ),
          vim.log.levels.INFO
        )
      end

      -- Schedule keymap registration to run after Neogit's own setup completes
      -- This ensures our keymap won't be overridden by Neogit's keymaps
      vim.schedule(function()
        -- DEBUG: Notify keymap registration
        if config.get("debug") then
          vim.notify(
            string.format("[aicommits] Registering keymap '%s' on buffer %d", key, event.buf),
            vim.log.levels.INFO
          )
        end

        -- Register buffer-local keymap
        vim.keymap.set("n", key, function()
          require("aicommits").commit()
        end, {
          buffer = event.buf,
          desc = "AI Commit (aicommits.nvim)",
          silent = true,
        })

        -- DEBUG: Verify keymap was set and log result
        if config.get("debug") then
          local maps = vim.api.nvim_buf_get_keymap(event.buf, "n")
          local found = false
          for _, map in ipairs(maps) do
            if map.lhs == key then
              found = true
              vim.notify(
                string.format("[aicommits] ✓ Keymap '%s' verified on buffer %d", key, event.buf),
                vim.log.levels.INFO
              )
              break
            end
          end
          if not found then
            vim.notify(
              string.format(
                "[aicommits] ✗ WARNING: Keymap '%s' not found after registration on buffer %d",
                key,
                event.buf
              ),
              vim.log.levels.WARN
            )
          end
        end
      end)
    end,
  })

  -- DEBUG: Confirm autocmd created
  if config.get("debug") then
    vim.notify("[aicommits] Neogit FileType autocmd created successfully", vim.log.levels.INFO)
  end
end

--- Check if Neogit is available
--- @return boolean available True if Neogit is loaded
function M.is_available()
  return pcall(require, "neogit") and package.loaded["neogit"] ~= nil
end

return M
