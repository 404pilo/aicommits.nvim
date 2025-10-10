-- User commands registration for aicommits.nvim
local M = {}

-- Register all user commands
function M.setup()
  -- Main commit command
  vim.api.nvim_create_user_command("AICommit", function()
    require("aicommits").commit()
  end, {
    desc = "Generate AI-powered git commit message",
    nargs = 0,
  })

  -- Health check command
  vim.api.nvim_create_user_command("AICommitHealth", function()
    vim.cmd("checkhealth aicommits")
  end, {
    desc = "Check aicommits.nvim health",
    nargs = 0,
  })

  -- Debug command
  vim.api.nvim_create_user_command("AICommitDebug", function()
    require("aicommits").debug_info()
  end, {
    desc = "Show aicommits.nvim debug information",
    nargs = 0,
  })
end

return M
