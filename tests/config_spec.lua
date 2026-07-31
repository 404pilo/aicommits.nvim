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
      assert.equals("gpt-5.6-luna", config.get("providers.openai.model"))
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
    assert.equals("auto", ld.mode)
    assert.equals(60000, ld.threshold_chars)
    assert.equals(6000, ld.chunk_chars)
    assert.equals(6, ld.max_chunks_per_file)
    assert.equals(800, ld.small_file_chars)
    assert.equals(10, ld.max_small_files_inline)
    assert.equals(4000, ld.small_file_batch_chars)
    assert.is_nil(ld.summary_model)
    assert.equals(220, ld.summary_max_tokens)
    assert.equals(0.2, ld.summary_temperature)
    assert.equals(4, ld.concurrency)
  end)

  it("allows user to override individual large_diff fields", function()
    config.setup({ large_diff = { mode = "always", concurrency = 2 } })
    assert.equals("always", config.get("large_diff.mode"))
    assert.equals(2, config.get("large_diff.concurrency"))
    -- Other defaults survive deep merge
    assert.equals(60000, config.get("large_diff.threshold_chars"))
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

  -- GAP: config-validate-mode-auto
  it("accepts mode = 'auto'", function()
    config.setup({ large_diff = { mode = "auto" } })
    local ok, errors = config.validate()
    assert.is_true(ok)
    assert.equals(0, #errors)
  end)

  -- GAP: config-validate-mode-always
  it("accepts mode = 'always'", function()
    config.setup({ large_diff = { mode = "always" } })
    local ok, errors = config.validate()
    assert.is_true(ok)
    assert.equals(0, #errors)
  end)

  it("rejects large_diff.concurrency = 0", function()
    config.setup({ large_diff = { mode = "auto", concurrency = 0 } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_true(#errors > 0)
    assert.is_truthy(errors[1]:match("large_diff%.concurrency"))
  end)

  it("rejects large_diff.max_chunks_per_file = 0", function()
    config.setup({ large_diff = { mode = "auto", max_chunks_per_file = 0 } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_truthy(table.concat(errors, "\n"):match("large_diff%.max_chunks_per_file"))
  end)

  it("rejects fractional large_diff.max_chunks_per_file", function()
    config.setup({ large_diff = { mode = "auto", max_chunks_per_file = 2.5 } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_truthy(table.concat(errors, "\n"):match("large_diff%.max_chunks_per_file"))
  end)

  it("rejects non-number large_diff.max_chunks_per_file", function()
    config.setup({ large_diff = { mode = "auto", max_chunks_per_file = "three" } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_truthy(table.concat(errors, "\n"):match("large_diff%.max_chunks_per_file"))
  end)

  it("accepts positive integer large_diff.max_chunks_per_file", function()
    config.setup({ large_diff = { mode = "auto", max_chunks_per_file = 3 } })
    local ok, errors = config.validate()
    assert.is_true(ok)
    assert.equals(0, #errors)
  end)
end)

describe("request config block", function()
  local config

  before_each(function()
    package.loaded["aicommits.config"] = nil
    config = require("aicommits.config")
  end)

  it("provides request defaults", function()
    config.setup({})
    local req = config.get("request")
    assert.equals(30000, req.timeout_ms)
    assert.equals(2, req.max_retries)
    assert.equals(500, req.backoff_base_ms)
    assert.equals(8000, req.backoff_max_ms)
    assert.is_true(req.backoff_jitter)
    assert.is_true(req.respect_retry_after)
    assert.equals(4, req.max_concurrency)
    assert.same({ 408, 429, 500, 502, 503, 504, 529 }, req.retry_on_status)
  end)

  it("folds user-set large_diff.concurrency into request.max_concurrency", function()
    local notified = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end

    config.setup({ large_diff = { concurrency = 7 } })
    assert.equals(7, config.get("request.max_concurrency"))
    -- deprecation notice fired exactly once
    local dep = 0
    for _, n in ipairs(notified) do
      if n.msg:match("large_diff%.concurrency") then
        dep = dep + 1
      end
    end
    assert.equals(1, dep)

    vim.notify = orig_notify
  end)

  it("request.max_concurrency wins when both are explicitly set, notice still fires", function()
    local notified = {}
    local orig_notify = vim.notify
    vim.notify = function(msg)
      table.insert(notified, msg)
    end

    config.setup({ large_diff = { concurrency = 7 }, request = { max_concurrency = 3 } })
    assert.equals(3, config.get("request.max_concurrency"))
    local dep = 0
    for _, m in ipairs(notified) do
      if m:match("large_diff%.concurrency") then
        dep = dep + 1
      end
    end
    assert.equals(1, dep)

    vim.notify = orig_notify
  end)

  it("does not fire deprecation notice when only request.max_concurrency is set", function()
    local notified = {}
    local orig_notify = vim.notify
    vim.notify = function(msg)
      table.insert(notified, msg)
    end

    config.setup({ request = { max_concurrency = 5 } })
    assert.equals(5, config.get("request.max_concurrency"))
    for _, m in ipairs(notified) do
      assert.is_nil(m:match("large_diff%.concurrency"))
    end

    vim.notify = orig_notify
  end)
end)

describe("validate() request block", function()
  local config

  before_each(function()
    package.loaded["aicommits.config"] = nil
    config = require("aicommits.config")
  end)

  it("rejects non-positive timeout_ms", function()
    config.setup({ request = { timeout_ms = 0 } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_truthy(errors[1]:match("timeout_ms"))
  end)

  it("accepts max_retries = 0", function()
    config.setup({ request = { max_retries = 0 } })
    local ok = config.validate()
    assert.is_true(ok)
  end)

  it("rejects negative max_retries", function()
    config.setup({ request = { max_retries = -1 } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_truthy(errors[1]:match("max_retries"))
  end)

  it("rejects non-positive max_concurrency", function()
    config.setup({ request = { max_concurrency = 0 } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_truthy(errors[1]:match("max_concurrency"))
  end)

  it("rejects non-boolean backoff_jitter", function()
    config.setup({ request = { backoff_jitter = "yes" } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_truthy(errors[1]:match("backoff_jitter"))
  end)

  it("rejects retry_on_status containing a non-integer", function()
    config.setup({ request = { retry_on_status = { 429, "x" } } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_truthy(errors[1]:match("retry_on_status"))
  end)
end)
