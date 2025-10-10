-- Minimal init for testing aicommits.nvim
local M = {}

function M.setup()
  -- Add current plugin to runtimepath
  local plugin_dir = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
  vim.opt.runtimepath:append(plugin_dir)

  -- Add plenary.nvim to runtimepath (required for testing)
  -- Check multiple possible locations
  local plenary_locations = {
    vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
    vim.fn.stdpath("data") .. "/site/pack/vendor/start/plenary.nvim",
    vim.env.HOME .. "/.local/share/nvim/site/pack/vendor/start/plenary.nvim",
  }

  for _, plenary_dir in ipairs(plenary_locations) do
    if vim.fn.isdirectory(plenary_dir) == 1 then
      vim.opt.runtimepath:append(plenary_dir)
      break
    end
  end

  -- Load plenary test harness
  vim.cmd("runtime! plugin/plenary.vim")
end

-- Always run setup when this file is sourced
M.setup()

return M
