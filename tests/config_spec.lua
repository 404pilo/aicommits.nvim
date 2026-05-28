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

describe("large_diff defaults", function()
  it("provides default large_diff block", function()
    config.setup({})
    local ld = config.get("large_diff")
    assert.is_table(ld)
    assert.equals("auto",  ld.mode)
    assert.equals(12000,   ld.threshold_chars)
    assert.equals(6000,    ld.chunk_chars)
    assert.equals(6,       ld.max_chunks_per_file)
    assert.equals(800,     ld.small_file_chars)
    assert.equals(10,      ld.max_small_files_inline)
    assert.equals(4000,    ld.small_file_batch_chars)
    assert.is_nil(ld.summary_model)
    assert.equals(220,     ld.summary_max_tokens)
    assert.equals(0.2,     ld.summary_temperature)
    assert.equals(4,       ld.concurrency)
  end)

  it("allows user to override individual large_diff fields", function()
    config.setup({ large_diff = { mode = "always", concurrency = 2 } })
    assert.equals("always", config.get("large_diff.mode"))
    assert.equals(2,        config.get("large_diff.concurrency"))
    -- Other defaults survive deep merge
    assert.equals(12000,    config.get("large_diff.threshold_chars"))
  end)
end)

describe("validate() large_diff.mode", function()
  it("accepts mode = 'off'", function()
    config.setup({ large_diff = { mode = "off" } })
    local ok, _ = config.validate()
    assert.is_true(ok)
  end)

  it("rejects unknown mode", function()
    config.setup({ large_diff = { mode = "banana" } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_true(#errors > 0)
    assert.is_truthy(errors[1]:match("large_diff.mode"))
  end)
end)
