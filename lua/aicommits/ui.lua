-- User interface functions for aicommits.nvim
local M = {}

-- Check if custom picker should be used
local function should_use_custom_picker()
  local config = require("aicommits.config")
  local ui_config = config.get("ui") or {}
  -- Default to true (use custom picker)
  if ui_config.use_custom_picker == nil then
    return true
  end
  return ui_config.use_custom_picker
end

-- Show commit message selection or confirmation UI
-- @param messages table Array of commit messages
-- @param on_confirm function(message) Called when user confirms/selects a message
-- @param on_cancel function() Called when user cancels
function M.show_commit_prompt(messages, on_confirm, on_cancel)
  if #messages == 0 then
    on_cancel()
    return
  end

  if #messages == 1 then
    -- Single message: show confirmation with custom picker or vim.ui.select
    local message = messages[1]

    if should_use_custom_picker() then
      -- Use custom picker for single message with edit option
      local picker = require("aicommits.ui.picker")
      picker.show({ message }, {}, {
        on_select = function(selected)
          on_confirm(selected)
        end,
        on_edit = function(selected)
          M.show_edit_prompt(selected, on_confirm, on_cancel)
        end,
        on_cancel = on_cancel,
      })
    else
      -- Fallback to vim.ui.select for compatibility
      local prompt = string.format("Use this commit message?\n\n   %s\n\n", message)
      vim.ui.select({ "Confirm", "Edit", "Cancel" }, {
        prompt = prompt,
        format_item = function(item)
          return item
        end,
      }, function(choice)
        if not choice or choice == "Cancel" then
          on_cancel()
        elseif choice == "Confirm" then
          on_confirm(message)
        elseif choice == "Edit" then
          M.show_edit_prompt(message, on_confirm, on_cancel)
        end
      end)
    end
  else
    -- Multiple messages: use custom picker or fallback
    if should_use_custom_picker() then
      local picker = require("aicommits.ui.picker")
      picker.show(messages, {}, {
        on_select = on_confirm,
        on_edit = function(selected)
          M.show_edit_prompt(selected, on_confirm, on_cancel)
        end,
        on_cancel = on_cancel,
      })
    else
      -- Fallback to vim.ui.select
      vim.ui.select(messages, {
        prompt = "Pick a commit message to use (Ctrl+c to cancel):",
        format_item = function(item)
          return item
        end,
      }, function(choice)
        if not choice then
          on_cancel()
        else
          on_confirm(choice)
        end
      end)
    end
  end
end

-- Show edit prompt for modifying commit message
-- @param initial_message string The initial message to edit
-- @param on_confirm function(message) Called when user confirms edited message
-- @param on_cancel function() Called when user cancels
function M.show_edit_prompt(initial_message, on_confirm, on_cancel)
  vim.ui.input({
    prompt = "Edit commit message: ",
    default = initial_message,
  }, function(edited_message)
    if not edited_message or edited_message == "" then
      on_cancel()
    else
      on_confirm(edited_message)
    end
  end)
end

return M
