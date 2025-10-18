describe("gemini-api provider", function()
  local gemini
  local base

  before_each(function()
    package.loaded["aicommits.providers.gemini"] = nil
    package.loaded["aicommits.providers.base"] = nil

    base = require("aicommits.providers.base")
    gemini = require("aicommits.providers.gemini")
  end)

  describe("initialization", function()
    it("has correct name", function()
      assert.equals("gemini-api", gemini.name)
    end)

    it("implements required methods", function()
      assert.is_function(gemini.generate_commit_message)
      assert.is_function(gemini.validate_config)
      assert.is_function(gemini.get_auth_headers)
      assert.is_function(gemini.get_capabilities)
    end)
  end)

  describe("validate_config", function()
    it("accepts valid configuration", function()
      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
        api_key = "test-key",
      })

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects missing model", function()
      local valid, errors = gemini:validate_config({
        api_key = "test-key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("model", errors[1])
    end)

    it("rejects empty model", function()
      local valid, errors = gemini:validate_config({
        model = "",
        api_key = "test-key",
      })

      assert.is_false(valid)
      assert.matches("model", errors[1])
    end)

    it("rejects invalid temperature (too high)", function()
      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
        api_key = "test-key",
        temperature = 5,
      })

      assert.is_false(valid)
      assert.matches("temperature", table.concat(errors, " "))
    end)

    it("rejects invalid temperature (negative)", function()
      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
        api_key = "test-key",
        temperature = -1,
      })

      assert.is_false(valid)
      assert.matches("temperature", table.concat(errors, " "))
    end)

    it("rejects invalid max_length (negative)", function()
      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
        api_key = "test-key",
        max_length = -1,
      })

      assert.is_false(valid)
      assert.matches("max_length", table.concat(errors, " "))
    end)

    it("rejects invalid max_length (zero)", function()
      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
        api_key = "test-key",
        max_length = 0,
      })

      assert.is_false(valid)
      assert.matches("max_length", table.concat(errors, " "))
    end)

    it("rejects invalid max_tokens", function()
      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
        api_key = "test-key",
        max_tokens = -1,
      })

      assert.is_false(valid)
      assert.matches("max_tokens", table.concat(errors, " "))
    end)

    it("rejects invalid generate (too low)", function()
      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
        api_key = "test-key",
        generate = 0,
      })

      assert.is_false(valid)
      assert.matches("generate", table.concat(errors, " "))
    end)

    it("rejects invalid generate (too high - max is 8)", function()
      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
        api_key = "test-key",
        generate = 9,
      })

      assert.is_false(valid)
      assert.matches("generate", table.concat(errors, " "))
    end)

    it("accepts valid generate within range (1-8)", function()
      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
        api_key = "test-key",
        generate = 8,
      })

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects missing API key (no config or env vars)", function()
      -- Clear any environment variables
      vim.env.AICOMMITS_NVIM_GEMINI_API_KEY = nil
      vim.env.GEMINI_API_KEY = nil

      local valid, errors = gemini:validate_config({
        model = "gemini-2.5-flash",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("API key", table.concat(errors, " "))
    end)
  end)

  describe("get_auth_headers", function()
    it("returns correct headers with API key from config", function()
      local headers = gemini:get_auth_headers({
        api_key = "test-key-123",
      })

      assert.is_table(headers)
      assert.equals("test-key-123", headers["x-goog-api-key"])
      assert.equals("application/json", headers["Content-Type"])
    end)

    it("returns headers structure even without API key", function()
      -- Clear env vars
      vim.env.AICOMMITS_NVIM_GEMINI_API_KEY = nil
      vim.env.GEMINI_API_KEY = nil

      local headers = gemini:get_auth_headers({})

      assert.is_table(headers)
      assert.is_not_nil(headers["x-goog-api-key"])
      assert.equals("application/json", headers["Content-Type"])
    end)

    it("prioritizes config.api_key over environment variables", function()
      vim.env.AICOMMITS_NVIM_GEMINI_API_KEY = "env-key-plugin"
      vim.env.GEMINI_API_KEY = "env-key-generic"

      local headers = gemini:get_auth_headers({
        api_key = "config-key",
      })

      assert.equals("config-key", headers["x-goog-api-key"])
    end)
  end)

  describe("get_capabilities", function()
    it("returns capability table", function()
      local caps = gemini:get_capabilities()

      assert.is_table(caps)
      assert.is_boolean(caps.supports_streaming)
      assert.is_boolean(caps.supports_multiple_generations)
      assert.is_number(caps.max_generations)
    end)

    it("reports correct capabilities", function()
      local caps = gemini:get_capabilities()

      assert.equals(true, caps.supports_streaming)
      assert.equals(true, caps.supports_multiple_generations)
      assert.equals(8, caps.max_generations)
    end)
  end)
end)
