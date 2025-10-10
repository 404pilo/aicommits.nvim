-- Utility functions for aicommits.nvim
local M = {}

-- Send error notification to user
-- @param message string The error message to display
function M.notify_error(message)
  vim.notify("[aicommits.nvim] " .. message, vim.log.levels.ERROR)
end

-- Send info notification to user
-- @param message string The info message to display
function M.notify_info(message)
  vim.notify("[aicommits.nvim] " .. message, vim.log.levels.INFO)
end

-- Send warning notification to user
-- @param message string The warning message to display
function M.notify_warn(message)
  vim.notify("[aicommits.nvim] " .. message, vim.log.levels.WARN)
end

return M
