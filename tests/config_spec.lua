-- Tests for aicommits.config module
local config = require("aicommits.config")

describe("aicommits.config", function()
  before_each(function()
    -- Reset config to defaults before each test
    config.setup({})
  end)

  describe("setup()", function()
    it("merges user options with defaults", function()
      config.setup({
        ui = {
          picker = {
            width = 0.8,
          },
        },
      })

      assert.equals(0.8, config.get("ui.picker.width"))
      -- Check that other defaults are preserved
      assert.equals(0.3, config.get("ui.picker.height"))
      assert.equals("rounded", config.get("ui.picker.border"))
    end)

    it("preserves all defaults when no options provided", function()
      config.setup({})

      assert.equals("openai", config.get("active_provider"))
      assert.equals("gpt-4.1-nano", config.get("providers.openai.model"))
      assert.equals(50, config.get("providers.openai.max_length"))
      assert.equals(1, config.get("providers.openai.generate"))
      assert.equals(true, config.get("ui.use_custom_picker"))
    end)

    it("defaults husky.enabled to true", function()
      config.setup({})

      assert.equals(true, config.get("husky.enabled"))
    end)

    it("allows opting out of husky detection", function()
      config.setup({ husky = { enabled = false } })

      assert.equals(false, config.get("husky.enabled"))
    end)

    it("allows deep nesting of custom options", function()
      config.setup({
        integrations = {
          neogit = {
            enabled = false,
          },
        },
      })

      assert.equals(false, config.get("integrations.neogit.enabled"))
    end)

    it("handles nested provider configuration", function()
      config.setup({
        providers = {
          openai = {
            model = "gpt-4.1-nano",
            max_length = 72,
          },
        },
      })

      assert.equals("gpt-4.1-nano", config.get("providers.openai.model"))
      assert.equals(72, config.get("providers.openai.max_length"))
      -- Check other defaults are preserved
      assert.equals(1, config.get("providers.openai.generate"))
    end)
  end)

  describe("get()", function()
    it("retrieves nested values using dot notation", function()
      config.setup({})

      assert.equals(0.4, config.get("ui.picker.width"))
      assert.equals("rounded", config.get("ui.picker.border"))
    end)

    it("returns nil for non-existent keys", function()
      config.setup({})

      assert.is_nil(config.get("nonexistent.key.path"))
    end)

    it("returns entire config when no key provided", function()
      config.setup({})

      local full_config = config.get()
      assert.is_table(full_config)
      assert.is_table(full_config.ui)
      assert.is_table(full_config.integrations)
    end)
  end)

  describe("set()", function()
    it("sets nested values using dot notation", function()
      config.setup({})

      config.set("ui.picker.width", 0.9)
      assert.equals(0.9, config.get("ui.picker.width"))
    end)

    it("creates intermediate tables if needed", function()
      config.setup({})

      config.set("custom.nested.value", "test")
      assert.equals("test", config.get("custom.nested.value"))
    end)
  end)

  describe("validate()", function()
    it("returns true for valid default configuration", function()
      config.setup({})

      local valid, errors = config.validate()
      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("detects missing active_provider", function()
      config.setup({
        active_provider = "",
      })

      local valid, errors = config.validate()
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("detects disabled active provider", function()
      config.setup({
        active_provider = "openai",
        providers = {
          openai = {
            enabled = false,
          },
        },
      })

      local valid, errors = config.validate()
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("detects missing provider configuration", function()
      config.setup({
        active_provider = "nonexistent",
        providers = {},
      })

      local valid, errors = config.validate()
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("accepts valid custom configuration", function()
      config.setup({
        active_provider = "openai",
        providers = {
          openai = {
            enabled = true,
            model = "gpt-4.1-nano",
            max_length = 72,
            generate = 3,
          },
        },
      })

      local valid, errors = config.validate()
      assert.is_true(valid)
      assert.equals(0, #errors)
    end)
  end)
end)
