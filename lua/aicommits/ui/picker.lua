-- Custom commit message picker with floating window
local M = {}

-- Current picker state
local state = {
  buf = nil,
  win = nil,
  current_idx = 1,
  messages = {},
  on_select = nil,
  on_edit = nil,
  on_cancel = nil,
}

-- Status window state (separate from picker)
local status_state = {
  buf = nil,
  win = nil,
}

-- Clean up picker state and close window
local function close_picker()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state = {
    buf = nil,
    win = nil,
    current_idx = 1,
    messages = {},
    on_select = nil,
    on_edit = nil,
    on_cancel = nil,
  }
end

-- Update the cursor position and highlighting
local function update_cursor()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  -- Set cursor to current selection (+ 1 for top padding line)
  vim.api.nvim_win_set_cursor(state.win, { state.current_idx + 1, 0 })
end

-- Handle message selection (Enter key)
local function select_message()
  local selected = state.messages[state.current_idx]
  local callback = state.on_select
  close_picker()

  if callback and selected then
    callback(selected)
  end
end

-- Handle edit action (e key)
local function edit_message()
  local selected = state.messages[state.current_idx]
  local callback = state.on_edit
  close_picker()

  if callback and selected then
    callback(selected)
  end
end

-- Handle cancel action (q or Esc)
local function cancel_picker()
  local callback = state.on_cancel
  close_picker()

  if callback then
    callback()
  end
end

-- Move selection up
local function move_up()
  if state.current_idx > 1 then
    state.current_idx = state.current_idx - 1
    update_cursor()
  end
end

-- Move selection down
local function move_down()
  if state.current_idx < #state.messages then
    state.current_idx = state.current_idx + 1
    update_cursor()
  end
end

-- Move to first item
local function move_first()
  state.current_idx = 1
  update_cursor()
end

-- Move to last item
local function move_last()
  state.current_idx = #state.messages
  update_cursor()
end

-- Set up buffer keymaps
local function setup_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true, nowait = true }

  -- Navigation
  vim.keymap.set("n", "j", move_down, opts)
  vim.keymap.set("n", "k", move_up, opts)
  vim.keymap.set("n", "<Down>", move_down, opts)
  vim.keymap.set("n", "<Up>", move_up, opts)
  vim.keymap.set("n", "gg", move_first, opts)
  vim.keymap.set("n", "G", move_last, opts)

  -- Actions
  vim.keymap.set("n", "<CR>", select_message, opts)
  vim.keymap.set("n", "e", edit_message, opts)
  vim.keymap.set("n", "q", cancel_picker, opts)
  vim.keymap.set("n", "<Esc>", cancel_picker, opts)
end

-- Calculate window dimensions
local function get_window_config()
  local config = require("aicommits.config")
  local ui_config = config.get("ui") or {}
  local picker_config = ui_config.picker or {}

  local width_percent = picker_config.width or 0.8
  local height_percent = picker_config.height or 0.6
  local border = picker_config.border or "rounded"

  local screen_width = vim.o.columns
  local screen_height = vim.o.lines

  local width = math.floor(screen_width * width_percent)
  local height = math.floor(screen_height * height_percent)

  local row = math.floor((screen_height - height) / 2)
  local col = math.floor((screen_width - width) / 2)

  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = border,
    title = " Select Commit Message ",
    title_pos = "center",
  }
end

-- Build the picker window title, adding a commitlint badge when detected
-- @param opts table Options passed to show() (may include commitlint_detected)
-- @return string Window title string
function M.get_picker_title(opts)
  if opts and opts.commitlint_detected then
    return " Select Commit Message · commitlint* "
  end
  return " Select Commit Message "
end

-- Create footer text with keybinding help
local function create_footer()
  return "" .. " " .. "[Enter] Accept   " .. "[e] Edit   " .. "[q] Cancel   " .. "[j/k] Navigate"
end

-- Close status window
local function close_status()
  if status_state.win and vim.api.nvim_win_is_valid(status_state.win) then
    vim.api.nvim_win_close(status_state.win, true)
  end
  if status_state.buf and vim.api.nvim_buf_is_valid(status_state.buf) then
    vim.api.nvim_buf_delete(status_state.buf, { force = true })
  end
  status_state.buf = nil
  status_state.win = nil
end

-- Show the picker with commit messages
-- @param messages table Array of commit messages
-- @param opts table Options for picker
-- @param callbacks table { on_select, on_edit, on_cancel }
function M.show(messages, opts, callbacks)
  opts = opts or {}
  callbacks = callbacks or {}

  -- Close status window when showing picker
  close_status()

  -- Validate inputs
  if not messages or #messages == 0 then
    if callbacks.on_cancel then
      callbacks.on_cancel()
    end
    return
  end

  -- Store state
  state.messages = messages
  state.current_idx = 1
  state.on_select = callbacks.on_select
  state.on_edit = callbacks.on_edit
  state.on_cancel = callbacks.on_cancel

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
  vim.api.nvim_buf_set_option(state.buf, "bufhidden", "wipe")

  -- Prepare content: messages + footer
  -- Add vertical padding (empty line at top)
  local lines = { "" }

  -- Add horizontal padding (prepend space to each message)
  for _, msg in ipairs(messages) do
    table.insert(lines, " " .. msg)
  end

  -- Add footer with padding
  table.insert(lines, "")
  table.insert(lines, " " .. create_footer())
  table.insert(lines, "") -- Empty line at bottom for vertical padding

  -- Set buffer content
  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

  -- Create floating window
  local win_config = get_window_config()
  win_config.title = M.get_picker_title(opts)
  state.win = vim.api.nvim_open_win(state.buf, true, win_config)

  -- Set window options
  vim.api.nvim_win_set_option(state.win, "cursorline", true)
  vim.api.nvim_win_set_option(state.win, "number", false)
  vim.api.nvim_win_set_option(state.win, "relativenumber", false)
  vim.api.nvim_win_set_option(state.win, "wrap", true)

  -- Apply Telescope-style highlights (falls back gracefully if not available)
  vim.api.nvim_win_set_option(
    state.win,
    "winhighlight",
    "Normal:TelescopeNormal,FloatBorder:TelescopePromptBorder,CursorLine:TelescopeSelection"
  )

  -- Highlight footer (accounting for padding)
  local footer_line = #messages + 2 -- Empty top line + messages + empty line before footer
  vim.api.nvim_buf_add_highlight(state.buf, -1, "Comment", footer_line, 0, -1)

  -- Set up keymaps
  setup_keymaps(state.buf)

  -- Set initial cursor position
  update_cursor()

  -- Auto-close on buffer leave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = state.buf,
    once = true,
    callback = function()
      -- Delay to allow keymap actions to complete
      vim.defer_fn(function()
        if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
          cancel_picker()
        end
      end, 50)
    end,
  })
end

-- Show a status message in a floating window
-- @param message string The status message to display
function M.show_status(message)
  -- Close any existing status window
  close_status()

  -- Also close picker if it's open (status transitions to picker)
  close_picker()

  -- Create buffer
  status_state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(status_state.buf, "modifiable", false)
  vim.api.nvim_buf_set_option(status_state.buf, "bufhidden", "wipe")

  -- Prepare content with padding
  local lines = {
    "", -- Top padding
    " " .. message, -- Message with horizontal padding
    "", -- Bottom padding
  }

  -- Set buffer content
  vim.api.nvim_buf_set_option(status_state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(status_state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(status_state.buf, "modifiable", false)

  -- Create floating window with same config as picker
  local win_config = get_window_config()
  win_config.title = " Status "
  status_state.win = vim.api.nvim_open_win(status_state.buf, false, win_config)

  -- Apply same styling as picker
  vim.api.nvim_win_set_option(status_state.win, "cursorline", false)
  vim.api.nvim_win_set_option(status_state.win, "number", false)
  vim.api.nvim_win_set_option(status_state.win, "relativenumber", false)
  vim.api.nvim_win_set_option(status_state.win, "wrap", true)
  vim.api.nvim_win_set_option(
    status_state.win,
    "winhighlight",
    "Normal:TelescopeNormal,FloatBorder:TelescopePromptBorder"
  )
end

-- Close status window (expose for external use)
function M.close_status()
  close_status()
end

return M
