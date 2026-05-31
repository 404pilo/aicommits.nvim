-- Tests for custom picker UI behavior
describe("picker", function()
  local picker

  before_each(function()
    package.loaded["aicommits.ui.picker"] = nil
    package.loaded["aicommits.config"] = nil
    picker = require("aicommits.ui.picker")
    require("aicommits.config").setup({})
  end)

  after_each(function()
    -- Ensure picker is closed after each test
    pcall(function()
      picker.close_status()
    end)
  end)

  describe("show() with commitlint_detected opt", function()
    it("accepts commitlint_detected opt without error", function()
      assert.has_no.errors(function()
        -- We just verify it doesn't crash; close immediately via cancel
        picker.show({ "feat: test message" }, { commitlint_detected = true }, {
          on_select = function() end,
          on_edit = function() end,
          on_cancel = function() end,
        })
        -- Close it right away
        local win = vim.api.nvim_get_current_win()
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end)
    end)

    it("accepts commitlint_detected = false without error", function()
      assert.has_no.errors(function()
        picker.show({ "feat: test message" }, { commitlint_detected = false }, {
          on_select = function() end,
          on_edit = function() end,
          on_cancel = function() end,
        })
        local win = vim.api.nvim_get_current_win()
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end)
    end)
  end)

  describe("get_picker_title()", function()
    it("returns default title when commitlint not detected", function()
      local title = picker.get_picker_title({ commitlint_detected = false })
      assert.equals(" Select Commit Message ", title)
    end)

    it("returns default title when opts is nil", function()
      local title = picker.get_picker_title(nil)
      assert.equals(" Select Commit Message ", title)
    end)

    it("includes commitlint indicator when commitlint_detected is true", function()
      local title = picker.get_picker_title({ commitlint_detected = true })
      assert.matches("commitlint%*", title)
    end)
  end)

  describe("show_status() in-place reuse", function()
    it("reuses the same window on repeated calls instead of recreating it", function()
      -- First call: creates the status float
      picker.show_status("First")

      -- Collect floating windows after the first call
      local function get_floats()
        local floats = {}
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(w).relative ~= "" then
            table.insert(floats, w)
          end
        end
        return floats
      end

      local floats_after_first = get_floats()
      assert.equals(1, #floats_after_first, "expected exactly 1 floating window after first show_status")
      local first_win = floats_after_first[1]

      -- Second call: should reuse the same window, not create a new one
      picker.show_status("Second")

      local floats_after_second = get_floats()
      assert.equals(1, #floats_after_second, "expected exactly 1 floating window after second show_status")
      local second_win = floats_after_second[1]

      -- The window id must be identical (reuse, not recreate)
      assert.equals(first_win, second_win, "show_status must reuse the existing window, not create a new one")

      -- The buffer content must now reflect "Second"
      local buf = vim.api.nvim_win_get_buf(second_win)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = table.concat(lines, "\n")
      assert.matches("Second", content, "buffer content must contain the new message")
    end)
  end)
end)
