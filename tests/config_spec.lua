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

      assert.equals("gpt-4.1-nano", config.get("model"))
      assert.equals(50, config.get("max_length"))
      assert.equals(1, config.get("generate"))
      assert.equals(true, config.get("ui.use_custom_picker"))
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

    it("handles backward compatibility for boolean neogit config", function()
      config.setup({
        integrations = {
          neogit = false,
        },
      })

      assert.equals(false, config.get("integrations.neogit.enabled"))
      assert.equals(false, config.get("integrations.neogit.mappings.enabled"))
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

    it("detects invalid model (empty string)", function()
      config.setup({
        model = "",
      })

      local valid, errors = config.validate()
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("detects invalid model (non-string)", function()
      config.setup({
        model = 123,
      })

      local valid, errors = config.validate()
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("detects invalid max_length (negative)", function()
      config.setup({
        max_length = -10,
      })

      local valid, errors = config.validate()
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("detects invalid max_length (zero)", function()
      config.setup({
        max_length = 0,
      })

      local valid, errors = config.validate()
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("detects invalid generate (below range)", function()
      config.setup({
        generate = 0,
      })

      local valid, errors = config.validate()
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("detects invalid generate (above range)", function()
      config.setup({
        generate = 6,
      })

      local valid, errors = config.validate()
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("accepts valid custom configuration", function()
      config.setup({
        model = "gpt-4",
        max_length = 72,
        generate = 3,
      })

      local valid, errors = config.validate()
      assert.is_true(valid)
      assert.equals(0, #errors)
    end)
  end)
end)
