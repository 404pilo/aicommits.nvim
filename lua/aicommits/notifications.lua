-- Notification and user feedback module for aicommits.nvim
-- Provides centralized notification system with configurable icons and levels

local M = {}

-- Notification levels
M.levels = {
  INFO = vim.log.levels.INFO,
  WARN = vim.log.levels.WARN,
  ERROR = vim.log.levels.ERROR,
  DEBUG = vim.log.levels.DEBUG,
}

-- Check if notifications are enabled
local function is_enabled()
  local config = require("aicommits.config")
  return config.get("notifications.enabled") ~= false
end

-- Get icon for notification type
local function get_icon(icon_type)
  local config = require("aicommits.config")
  return config.get("notifications." .. icon_type) or ""
end

-- Send a notification
function M.notify(message, level, opts)
  if not is_enabled() then
    return
  end

  opts = opts or {}
  level = level or M.levels.INFO

  -- Add title if provided
  local title = opts.title or "aicommits.nvim"

  -- Check if nvim-notify is available for enhanced notifications
  local has_notify, notify = pcall(require, "notify")

  if has_notify and opts.use_notify ~= false then
    notify(message, level, {
      title = title,
      timeout = opts.timeout or 3000,
      render = opts.render,
    })
  else
    -- Fall back to vim.notify
    local formatted_message = string.format("[%s] %s", title, message)
    vim.notify(formatted_message, level)
  end
end

-- Success notification
function M.success(message, opts)
  opts = opts or {}
  local icon = get_icon("success_icon")
  local formatted = icon ~= "" and (icon .. " " .. message) or message
  M.notify(formatted, M.levels.INFO, opts)
end

-- Error notification
function M.error(message, opts)
  opts = opts or {}
  local icon = get_icon("error_icon")
  local formatted = icon ~= "" and (icon .. " " .. message) or message
  M.notify(formatted, M.levels.ERROR, opts)
end

-- Warning notification
function M.warn(message, opts)
  opts = opts or {}
  local icon = get_icon("warn_icon")
  local formatted = icon ~= "" and (icon .. " " .. message) or message
  M.notify(formatted, M.levels.WARN, opts)
end

-- Info notification
function M.info(message, opts)
  opts = opts or {}
  local icon = get_icon("info_icon")
  local formatted = icon ~= "" and (icon .. " " .. message) or message
  M.notify(formatted, M.levels.INFO, opts)
end

-- Debug notification (only shown if debug mode is enabled)
function M.debug(message, opts)
  local config = require("aicommits.config")
  if not config.get("debug") then
    return
  end

  opts = opts or {}
  opts.title = opts.title or "aicommits.nvim [DEBUG]"
  M.notify(message, M.levels.DEBUG, opts)
end

-- Progress notification (for long-running operations)
function M.progress(message, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or false -- Don't auto-dismiss progress notifications
  M.info(message, opts)
end

-- Commit result notification
function M.commit_result(success, stats)
  if success then
    local message = "Commit created successfully"
    if stats and stats.files then
      message = string.format(
        "Commit created successfully (%d file%s, +%d -%d)",
        stats.files,
        stats.files == 1 and "" or "s",
        stats.additions or 0,
        stats.deletions or 0
      )
    end
    M.success(message)
  else
    M.error("Commit failed or was cancelled")
  end
end

-- Validation error notification
function M.validation_error(errors)
  if type(errors) == "string" then
    M.error(errors)
  elseif type(errors) == "table" then
    local message = "Validation failed:\n" .. table.concat(errors, "\n")
    M.error(message, { timeout = 5000 })
  end
end

-- Git operation error notification
function M.git_error(operation, details)
  local message = string.format("Git operation failed: %s", operation)
  if details then
    message = message .. "\n" .. details
  end
  M.error(message, { timeout = 5000 })
end

-- Dependency check notification
function M.dependency_missing(dependency, details)
  local message = string.format("Missing dependency: %s", dependency)
  if details then
    message = message .. "\n" .. details
  end
  M.warn(message, { timeout = 5000 })
end

-- API key missing notification
function M.api_key_missing()
  M.error(
    "OpenAI API key not found. Set OPENAI_API_KEY environment variable or configure in setup.",
    { timeout = 5000 }
  )
end

-- Configuration error notification
function M.config_error(errors)
  local message = "Configuration error"
  if type(errors) == "string" then
    message = message .. ": " .. errors
  elseif type(errors) == "table" and #errors > 0 then
    message = message .. ":\n" .. table.concat(errors, "\n")
  end
  M.error(message, { timeout = 5000 })
end

-- First-run welcome notification
function M.welcome()
  M.info("Welcome to aicommits.nvim! Run :AICommitHealth to check your setup.", { timeout = 5000 })
end

return M
