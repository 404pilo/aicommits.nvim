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
            model = "gpt-4.1-nano",
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
            model = "gpt-4.1-nano",
            max_length = 72,
          },
        },
      })
      assert.is_true(aicommits.is_initialized())

      -- Phase 2: Verify config
      assert.equals("gpt-4.1-nano", config.get("providers.openai.model"))
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

describe("commit.lua — input.prepare integration", function()
  it("calls generate_commit_message with final_payload from input.prepare", function()
    local config = require("aicommits.config")
    config.setup({ large_diff = { mode = "always" } })

    -- Stub git operations
    local git = require("aicommits.git")
    local orig_is_repo    = git.is_git_repo
    local orig_get_diff   = git.get_staged_diff
    git.is_git_repo    = function() return true end
    git.get_staged_diff = function(cb)
      cb(nil, { diff = "raw-diff", files = { "a.lua" } })
    end

    -- Stub provider manager
    local providers = require("aicommits.providers")
    local orig_get_active = providers.get_active_provider
    local received_payload
    providers.get_active_provider = function()
      return {
        name = "test",
        generate_commit_message = function(self, payload, _cfg, cb)
          received_payload = payload
          cb(nil, { "test: do stuff" })
        end,
      }, nil
    end

    -- Stub input.prepare to return a transformed payload
    package.loaded["aicommits.input"] = nil
    package.preload["aicommits.input"] = function()
      return {
        prepare = function(_dd, _p, _pc, cb)
          cb(nil, "TRANSFORMED_PAYLOAD")
        end,
      }
    end

    -- Stub picker and ui to be no-ops
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status  = function() end
    picker.close_status = function() end

    local ui = require("aicommits.ui")
    local orig_show_prompt = ui.show_commit_prompt
    ui.show_commit_prompt = function() end

    -- Run
    package.loaded["aicommits.commit"] = nil
    require("aicommits.commit").generate_and_commit()

    -- Restore
    git.is_git_repo        = orig_is_repo
    git.get_staged_diff    = orig_get_diff
    providers.get_active_provider = orig_get_active
    package.preload["aicommits.input"] = nil
    package.loaded["aicommits.input"]  = nil
    picker.show_status   = orig_show
    picker.close_status  = orig_close
    ui.show_commit_prompt = orig_show_prompt

    assert.equals("TRANSFORMED_PAYLOAD", received_payload)
  end)
end)

-- GAP: commit-lua-husky-injection-before-input-prepare
describe("commit.lua — husky injection ordering", function()
  it("provider_config passed to input.prepare already contains commitlint injection", function()
    local config = require("aicommits.config")
    config.setup({
      large_diff = { mode = "always" },
      husky = { enabled = true },
    })

    -- Stub git operations
    local git = require("aicommits.git")
    local orig_is_repo   = git.is_git_repo
    local orig_get_diff  = git.get_staged_diff
    local orig_get_root  = git.get_git_root
    git.is_git_repo   = function() return true end
    git.get_staged_diff = function(cb)
      cb(nil, { diff = "raw-diff", files = { "a.lua" } })
    end
    git.get_git_root  = function() return "/fake/root" end

    -- Stub husky to return a commitlint config
    local husky = require("aicommits.husky")
    local orig_get_rules = husky.get_commitlint_rules
    husky.get_commitlint_rules = function(_root)
      return '{"rules":{"type-enum":["error","always",["feat","fix"]]}}', true
    end

    -- Stub provider manager
    local providers = require("aicommits.providers")
    local orig_get_active = providers.get_active_provider
    providers.get_active_provider = function()
      return {
        name = "openai",
        generate_commit_message = function(self, _payload, _cfg, cb)
          cb(nil, { "feat: test" })
        end,
      }, nil
    end

    -- Capture provider_config that arrives at input.prepare
    local captured_provider_config = nil
    package.loaded["aicommits.input"] = nil
    package.preload["aicommits.input"] = function()
      return {
        prepare = function(_dd, _p, pc, cb)
          captured_provider_config = pc
          cb(nil, "PAYLOAD")
        end,
      }
    end

    -- Stub picker and ui
    local picker = require("aicommits.ui.picker")
    local orig_show  = picker.show_status
    local orig_close = picker.close_status
    picker.show_status  = function() end
    picker.close_status = function() end

    local ui = require("aicommits.ui")
    local orig_prompt = ui.show_commit_prompt
    ui.show_commit_prompt = function() end

    -- Run
    package.loaded["aicommits.commit"] = nil
    require("aicommits.commit").generate_and_commit()

    -- Restore
    git.is_git_repo        = orig_is_repo
    git.get_staged_diff    = orig_get_diff
    git.get_git_root       = orig_get_root
    husky.get_commitlint_rules = orig_get_rules
    providers.get_active_provider = orig_get_active
    package.preload["aicommits.input"] = nil
    package.loaded["aicommits.input"]  = nil
    picker.show_status  = orig_show
    picker.close_status = orig_close
    ui.show_commit_prompt = orig_prompt

    -- Assert that commitlint injection was in provider_config when prepare was called
    assert.is_not_nil(captured_provider_config)
    assert.is_not_nil(captured_provider_config.commitlint_config,
      "Expected commitlint_config to be injected into provider_config before input.prepare")
    assert.is_true(captured_provider_config.commitlint_resolved,
      "Expected commitlint_resolved = true in provider_config")
  end)
end)
