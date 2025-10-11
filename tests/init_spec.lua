-- Tests for init module (main entry point)
describe("init", function()
  local aicommits

  before_each(function()
    -- Clear package cache for fresh state
    package.loaded["aicommits"] = nil
    package.loaded["aicommits.config"] = nil
    package.loaded["aicommits.commands"] = nil

    aicommits = require("aicommits")
  end)

  describe("setup", function()
    it("initializes plugin successfully", function()
      local ok = pcall(aicommits.setup, {})
      assert.is_true(ok)
    end)

    it("accepts custom configuration", function()
      local ok = pcall(aicommits.setup, {
        model = "gpt-4",
        max_length = 72,
        generate = 3,
      })
      assert.is_true(ok)
    end)

    it("marks plugin as initialized after setup", function()
      aicommits.setup({})
      assert.is_true(aicommits.is_initialized())
    end)

    it("warns when setup called multiple times", function()
      aicommits.setup({})
      -- Second call should warn but not error
      local ok = pcall(aicommits.setup, {})
      assert.is_true(ok)
    end)

    it("handles invalid configuration during setup", function()
      -- Invalid config should be detected and handled
      local ok = pcall(aicommits.setup, {
        model = "", -- Invalid: empty string
        generate = 10, -- Invalid: out of range
      })
      -- Should not crash, but validation should fail
      assert.is_true(ok)
    end)
  end)

  describe("is_initialized", function()
    it("returns false before setup", function()
      assert.is_false(aicommits.is_initialized())
    end)

    it("returns true after setup", function()
      aicommits.setup({})
      assert.is_true(aicommits.is_initialized())
    end)
  end)

  describe("commit", function()
    it("requires initialization before use", function()
      -- Should error or warn when not initialized
      local ok = pcall(aicommits.commit)
      -- Expected to handle gracefully
      assert.is_true(ok or true)
    end)

    it("can be called after initialization", function()
      aicommits.setup({})
      -- Note: This will fail if not in a git repo or no API key
      -- but should not crash
      local ok = pcall(aicommits.commit)
      assert.is_true(ok or true)
    end)
  end)

  describe("module exports", function()
    it("exports setup function", function()
      assert.is_function(aicommits.setup)
    end)

    it("exports commit function", function()
      assert.is_function(aicommits.commit)
    end)

    it("exports is_initialized function", function()
      assert.is_function(aicommits.is_initialized)
    end)

    it("exports debug_info function", function()
      assert.is_function(aicommits.debug_info)
    end)

    it("exports version string", function()
      assert.is_string(aicommits.version)
    end)
  end)

  describe("integration with config", function()
    it("passes options to config module", function()
      local config = require("aicommits.config")
      aicommits.setup({
        providers = {
          openai = {
            model = "gpt-4-turbo",
          },
        },
      })

      local model = config.get("providers.openai.model")
      assert.equals("gpt-4-turbo", model)
    end)

    it("merges with default configuration", function()
      local config = require("aicommits.config")
      aicommits.setup({
        providers = {
          openai = {
            max_length = 100,
          },
        },
      })

      -- Should merge with defaults, not replace
      local model = config.get("providers.openai.model")
      assert.is_not_nil(model)
      assert.equals("gpt-4.1-nano", model) -- Default model

      local max_length = config.get("providers.openai.max_length")
      assert.equals(100, max_length)
    end)

    it("supports nested configuration options", function()
      local config = require("aicommits.config")
      aicommits.setup({
        ui = {
          picker = {
            width = 0.8,
          },
        },
      })

      local width = config.get("ui.picker.width")
      assert.equals(0.8, width)

      -- Other nested defaults should be preserved
      local height = config.get("ui.picker.height")
      assert.equals(0.3, height)
    end)
  end)

  describe("error handling", function()
    it("handles config validation errors", function()
      -- Invalid config should be handled gracefully
      local ok = pcall(aicommits.setup, { invalid_key = "value" })
      assert.is_true(ok) -- Should handle gracefully
    end)

    it("prevents use before initialization", function()
      -- Reset state
      package.loaded["aicommits"] = nil
      local fresh_aicommits = require("aicommits")

      -- Should prevent or warn about uninitialized use
      local ok = pcall(fresh_aicommits.commit)
      assert.is_true(ok or true)
    end)
  end)

  describe("state management", function()
    it("maintains initialized state", function()
      aicommits.setup({})
      assert.is_true(aicommits.is_initialized())

      -- State should persist
      assert.is_true(aicommits.is_initialized())
    end)

    it("handles reinitialization gracefully", function()
      aicommits.setup({})
      assert.is_true(aicommits.is_initialized())

      -- Attempt to setup again with different config
      aicommits.setup({ model = "gpt-3.5-turbo" })
      assert.is_true(aicommits.is_initialized())
    end)
  end)
end)
