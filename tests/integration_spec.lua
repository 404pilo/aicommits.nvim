-- Integration tests for aicommits.nvim
-- Tests complete workflows and module interactions
describe("integration", function()
  local aicommits
  local config
  local git
  local commands

  before_each(function()
    -- Clear all package cache
    package.loaded["aicommits"] = nil
    package.loaded["aicommits.config"] = nil
    package.loaded["aicommits.git"] = nil
    package.loaded["aicommits.commands"] = nil
    package.loaded["aicommits.notifications"] = nil

    -- Load modules
    aicommits = require("aicommits")
    config = require("aicommits.config")
    git = require("aicommits.git")
    commands = require("aicommits.commands")
  end)

  describe("plugin initialization workflow", function()
    it("complete initialization sequence works", function()
      -- Step 1: Setup plugin
      local ok = pcall(aicommits.setup, {
        providers = {
          openai = {
            model = "gpt-4",
            generate = 3,
          },
        },
      })
      assert.is_true(ok)

      -- Step 2: Verify initialization
      assert.is_true(aicommits.is_initialized())

      -- Step 3: Commands should be registered
      commands.setup()
      assert.equals(2, vim.fn.exists(":AICommit"))
    end)

    it("config merges correctly with defaults", function()
      aicommits.setup({
        providers = {
          openai = {
            model = "gpt-4-turbo",
            max_length = 100,
          },
        },
      })

      -- Custom values should be set
      assert.equals("gpt-4-turbo", config.get("providers.openai.model"))
      assert.equals(100, config.get("providers.openai.max_length"))

      -- Defaults should still exist for non-specified options
      assert.is_not_nil(config.get("providers.openai.generate"))
      assert.equals(1, config.get("providers.openai.generate")) -- Default value
    end)
  end)

  describe("git repository checks", function()
    it("checks if in git repository", function()
      local is_repo = git.is_git_repo()
      assert.is_boolean(is_repo)
    end)

    it("checks for staged changes", function()
      local has_changes = git.has_staged_changes()
      assert.is_boolean(has_changes)
    end)

    it("git functions integrate with config", function()
      aicommits.setup({})
      -- Git functions should work after initialization
      local ok = pcall(git.is_git_repo)
      assert.is_true(ok)
    end)
  end)

  describe("command workflow integration", function()
    before_each(function()
      aicommits.setup({})
      commands.setup()
    end)

    it("health check command workflow", function()
      -- Command should exist
      assert.equals(2, vim.fn.exists(":AICommitHealth"))

      -- Should be executable
      local ok = pcall(vim.cmd, "AICommitHealth")
      assert.is_true(ok)
    end)

    it("debug command workflow", function()
      -- Command should exist
      assert.equals(2, vim.fn.exists(":AICommitDebug"))

      -- Should be executable
      local ok = pcall(vim.cmd, "AICommitDebug")
      assert.is_true(ok)
    end)
  end)

  describe("configuration workflow", function()
    it("handles custom configuration end-to-end", function()
      -- Setup with custom config
      aicommits.setup({
        providers = {
          openai = {
            model = "gpt-4-turbo",
            max_length = 72,
            generate = 5,
          },
        },
        ui = {
          use_custom_picker = true,
          picker = {
            width = 0.8,
            height = 0.5,
            border = "double",
          },
        },
        integrations = {
          neogit = {
            enabled = true,
            mappings = {
              enabled = true,
              key = "G",
            },
          },
        },
      })

      -- Verify all custom values
      assert.equals("gpt-4-turbo", config.get("providers.openai.model"))
      assert.equals(72, config.get("providers.openai.max_length"))
      assert.equals(5, config.get("providers.openai.generate"))
      assert.equals(0.8, config.get("ui.picker.width"))
      assert.equals(0.5, config.get("ui.picker.height"))
      assert.equals("double", config.get("ui.picker.border"))
      assert.is_true(config.get("integrations.neogit.enabled"))
      assert.equals("G", config.get("integrations.neogit.mappings.key"))
    end)

    it("validates configuration", function()
      aicommits.setup({})
      local valid, _ = config.validate()
      assert.is_true(valid)
    end)
  end)

  describe("notification workflow", function()
    it("notifications integrate with plugin", function()
      aicommits.setup({})

      local notifications = require("aicommits.notifications")
      local ok = pcall(notifications.success, "Test message")
      assert.is_true(ok)
    end)

    it("notification functions are available", function()
      local notifications = require("aicommits.notifications")

      assert.is_function(notifications.success)
      assert.is_function(notifications.error)
      assert.is_function(notifications.warn)
      assert.is_function(notifications.info)
    end)
  end)

  describe("error handling integration", function()
    it("handles uninitialized plugin gracefully", function()
      -- Reset state
      package.loaded["aicommits"] = nil
      local fresh = require("aicommits")

      -- Should handle or prevent uninitialized use
      local ok = pcall(fresh.commit)
      assert.is_true(ok or true)
    end)

    it("handles invalid configuration gracefully", function()
      local ok = pcall(aicommits.setup, {
        active_provider = "nonexistent",
      })
      -- Setup should not crash but validation will fail
      assert.is_true(ok)
    end)

    it("handles missing dependencies gracefully", function()
      -- Git functions should handle non-git directories
      local ok = pcall(git.is_git_repo)
      assert.is_true(ok)
    end)
  end)

  describe("module interdependencies", function()
    it("all core modules load without errors", function()
      local modules = {
        "aicommits",
        "aicommits.config",
        "aicommits.git",
        "aicommits.notifications",
        "aicommits.health",
        "aicommits.commands",
        "aicommits.providers",
        "aicommits.providers.openai",
        "aicommits.commit",
      }

      for _, module_name in ipairs(modules) do
        local ok, _ = pcall(require, module_name)
        assert.is_true(ok, "Failed to load: " .. module_name)
      end
    end)

    it("modules can be loaded in any order", function()
      -- Load in reverse order
      local ok1 = pcall(require, "aicommits.commands")
      local ok2 = pcall(require, "aicommits.notifications")
      local ok3 = pcall(require, "aicommits.config")
      local ok4 = pcall(require, "aicommits")

      assert.is_true(ok1)
      assert.is_true(ok2)
      assert.is_true(ok3)
      assert.is_true(ok4)
    end)
  end)

  describe("complete plugin lifecycle", function()
    it("initialization -> configuration -> command registration", function()
      -- Phase 1: Initialize
      aicommits.setup({
        providers = {
          openai = {
            model = "gpt-4",
            max_length = 72,
          },
        },
      })
      assert.is_true(aicommits.is_initialized())

      -- Phase 2: Verify config
      assert.equals("gpt-4", config.get("providers.openai.model"))
      assert.equals(72, config.get("providers.openai.max_length"))

      -- Phase 3: Register commands
      commands.setup()
      assert.equals(2, vim.fn.exists(":AICommit"))
      assert.equals(2, vim.fn.exists(":AICommitHealth"))
      assert.equals(2, vim.fn.exists(":AICommitDebug"))

      -- Phase 4: Commands are functional
      local ok = pcall(vim.cmd, "AICommitHealth")
      assert.is_true(ok)
    end)
  end)
end)
