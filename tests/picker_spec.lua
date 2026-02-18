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
      assert.matches("commitlint", title)
    end)
  end)
end)
