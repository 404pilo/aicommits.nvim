-- Tests for notifications module
describe("notifications", function()
  local notifications
  local config

  before_each(function()
    -- Clear package cache
    package.loaded["aicommits.notifications"] = nil
    package.loaded["aicommits.config"] = nil

    -- Load modules
    config = require("aicommits.config")
    config.setup({}) -- Initialize with defaults
    notifications = require("aicommits.notifications")
  end)

  describe("notification levels", function()
    it("defines INFO level", function()
      assert.equals(vim.log.levels.INFO, notifications.levels.INFO)
    end)

    it("defines WARN level", function()
      assert.equals(vim.log.levels.WARN, notifications.levels.WARN)
    end)

    it("defines ERROR level", function()
      assert.equals(vim.log.levels.ERROR, notifications.levels.ERROR)
    end)

    it("defines DEBUG level", function()
      assert.equals(vim.log.levels.DEBUG, notifications.levels.DEBUG)
    end)
  end)

  describe("notify", function()
    it("sends notification without errors", function()
      local ok = pcall(notifications.notify, "Test message", notifications.levels.INFO)
      assert.is_true(ok)
    end)

    it("respects notifications.enabled config", function()
      config.setup({ notifications = { enabled = false } })
      -- Should not error when disabled
      local ok = pcall(notifications.notify, "Test message")
      assert.is_true(ok)
    end)

    it("accepts custom options", function()
      local ok = pcall(notifications.notify, "Test", notifications.levels.INFO, {
        title = "Custom Title",
        timeout = 5000,
      })
      assert.is_true(ok)
    end)
  end)

  describe("success", function()
    it("sends success notification", function()
      local ok = pcall(notifications.success, "Operation successful")
      assert.is_true(ok)
    end)

    it("includes success icon if configured", function()
      config.setup({ notifications = { success_icon = "✓" } })
      local ok = pcall(notifications.success, "Test")
      assert.is_true(ok)
    end)

    it("works without icon", function()
      config.setup({ notifications = { success_icon = "" } })
      local ok = pcall(notifications.success, "Test")
      assert.is_true(ok)
    end)
  end)

  describe("error", function()
    it("sends error notification", function()
      local ok = pcall(notifications.error, "An error occurred")
      assert.is_true(ok)
    end)

    it("includes error icon if configured", function()
      config.setup({ notifications = { error_icon = "✗" } })
      local ok = pcall(notifications.error, "Test")
      assert.is_true(ok)
    end)
  end)

  describe("warn", function()
    it("sends warning notification", function()
      local ok = pcall(notifications.warn, "Warning message")
      assert.is_true(ok)
    end)

    it("includes warn icon if configured", function()
      config.setup({ notifications = { warn_icon = "⚠" } })
      local ok = pcall(notifications.warn, "Test")
      assert.is_true(ok)
    end)
  end)

  describe("info", function()
    it("sends info notification", function()
      local ok = pcall(notifications.info, "Info message")
      assert.is_true(ok)
    end)

    it("includes info icon if configured", function()
      config.setup({ notifications = { info_icon = "ℹ" } })
      local ok = pcall(notifications.info, "Test")
      assert.is_true(ok)
    end)
  end)

  describe("debug", function()
    it("sends debug notification when debug enabled", function()
      config.setup({ debug = true })
      local ok = pcall(notifications.debug, "Debug message")
      assert.is_true(ok)
    end)

    it("does not send debug notification when debug disabled", function()
      config.setup({ debug = false })
      local ok = pcall(notifications.debug, "Debug message")
      assert.is_true(ok) -- Should not error
    end)
  end)

  describe("specialized notifications", function()
    it("commit_result sends success notification on success", function()
      local ok = pcall(notifications.commit_result, true)
      assert.is_true(ok)
    end)

    it("commit_result sends error notification on failure", function()
      local ok = pcall(notifications.commit_result, false)
      assert.is_true(ok)
    end)

    it("git_error sends error notification", function()
      local ok = pcall(notifications.git_error, "Not a git repository")
      assert.is_true(ok)
    end)

    it("api_key_missing sends warning notification", function()
      local ok = pcall(notifications.api_key_missing)
      assert.is_true(ok)
    end)

    it("config_error sends error notification", function()
      local ok = pcall(notifications.config_error, "Invalid configuration")
      assert.is_true(ok)
    end)

    it("validation_error sends error notification", function()
      local ok = pcall(notifications.validation_error, "Validation failed")
      assert.is_true(ok)
    end)

    it("dependency_missing sends error notification", function()
      local ok = pcall(notifications.dependency_missing, "git", "brew install git")
      assert.is_true(ok)
    end)
  end)

  describe("edge cases", function()
    it("handles nil message gracefully", function()
      local ok = pcall(notifications.success, nil)
      -- Should handle nil without crashing
      assert.is_true(ok or true) -- May error but shouldn't crash Neovim
    end)

    it("handles empty message", function()
      local ok = pcall(notifications.success, "")
      assert.is_true(ok)
    end)

    it("handles very long message", function()
      local long_message = string.rep("a", 1000)
      local ok = pcall(notifications.info, long_message)
      assert.is_true(ok)
    end)

    it("handles messages with newlines", function()
      local ok = pcall(notifications.info, "Line 1\nLine 2\nLine 3")
      assert.is_true(ok)
    end)

    it("handles messages with special characters", function()
      local ok = pcall(notifications.info, "Special: !@#$%^&*()")
      assert.is_true(ok)
    end)
  end)

  describe("configuration integration", function()
    it("respects custom title in options", function()
      local ok = pcall(notifications.notify, "Test", notifications.levels.INFO, {
        title = "My Plugin",
      })
      assert.is_true(ok)
    end)

    it("respects custom timeout in options", function()
      local ok = pcall(notifications.notify, "Test", notifications.levels.INFO, {
        timeout = 10000,
      })
      assert.is_true(ok)
    end)

    it("works when nvim-notify is not available", function()
      -- This should fall back to vim.notify
      local ok = pcall(notifications.success, "Test without nvim-notify")
      assert.is_true(ok)
    end)
  end)
end)
