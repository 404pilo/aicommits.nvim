-- Unit tests for Anthropic Claude provider
describe("anthropic provider", function()
  local anthropic
  local base

  before_each(function()
    package.loaded["aicommits.providers.anthropic"] = nil
    package.loaded["aicommits.providers.base"] = nil

    base = require("aicommits.providers.base")
    anthropic = require("aicommits.providers.anthropic")
  end)

  describe("initialization", function()
    it("has correct name", function()
      assert.equals("anthropic", anthropic.name)
    end)

    it("implements required methods", function()
      assert.is_function(anthropic.generate_commit_message)
      assert.is_function(anthropic.validate_config)
      assert.is_function(anthropic.get_auth_headers)
      assert.is_function(anthropic.get_capabilities)
    end)
  end)

  describe("interface", function()
    it("implements generate_text and not summarize", function()
      assert.is_function(anthropic.generate_text)
      assert.is_nil(anthropic.summarize)
    end)
  end)

  describe("validate_config", function()
    it("accepts valid configuration", function()
      local valid, errors = anthropic:validate_config({
        model = "claude-haiku-4-5",
        api_key = "test-key",
      })

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects missing model", function()
      local valid, errors = anthropic:validate_config({
        api_key = "test-key",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("model", errors[1])
    end)

    it("rejects empty model", function()
      local valid, errors = anthropic:validate_config({
        model = "",
        api_key = "test-key",
      })

      assert.is_false(valid)
      assert.matches("model", errors[1])
    end)

    it("rejects invalid temperature (too high)", function()
      local valid, errors = anthropic:validate_config({
        model = "claude-haiku-4-5",
        api_key = "test-key",
        temperature = 1.5,
      })

      assert.is_false(valid)
      assert.matches("temperature", table.concat(errors, " "))
    end)

    it("rejects invalid temperature (negative)", function()
      local valid, errors = anthropic:validate_config({
        model = "claude-haiku-4-5",
        api_key = "test-key",
        temperature = -1,
      })

      assert.is_false(valid)
      assert.matches("temperature", table.concat(errors, " "))
    end)

    it("accepts temperature within valid range (0-1)", function()
      local valid, errors = anthropic:validate_config({
        model = "claude-haiku-4-5",
        api_key = "test-key",
        temperature = 1,
      })

      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects invalid max_length (negative)", function()
      local valid, errors = anthropic:validate_config({
        model = "claude-haiku-4-5",
        api_key = "test-key",
        max_length = -1,
      })

      assert.is_false(valid)
      assert.matches("max_length", table.concat(errors, " "))
    end)

    it("rejects invalid max_tokens", function()
      local valid, errors = anthropic:validate_config({
        model = "claude-haiku-4-5",
        api_key = "test-key",
        max_tokens = -1,
      })

      assert.is_false(valid)
      assert.matches("max_tokens", table.concat(errors, " "))
    end)

    it("rejects missing API key (no config or env vars)", function()
      vim.env.AICOMMITS_NVIM_ANTHROPIC_API_KEY = nil
      vim.env.ANTHROPIC_API_KEY = nil

      local valid, errors = anthropic:validate_config({
        model = "claude-haiku-4-5",
      })

      assert.is_false(valid)
      assert.is_true(#errors > 0)
      assert.matches("API key", table.concat(errors, " "))
    end)

    it("accepts API key from AICOMMITS_NVIM_ANTHROPIC_API_KEY", function()
      vim.env.AICOMMITS_NVIM_ANTHROPIC_API_KEY = "env-key-plugin"
      vim.env.ANTHROPIC_API_KEY = nil

      local valid, errors = anthropic:validate_config({
        model = "claude-haiku-4-5",
      })

      assert.is_true(valid)
      assert.equals(0, #errors)

      vim.env.AICOMMITS_NVIM_ANTHROPIC_API_KEY = nil
    end)

    it("accepts API key from generic ANTHROPIC_API_KEY", function()
      vim.env.AICOMMITS_NVIM_ANTHROPIC_API_KEY = nil
      vim.env.ANTHROPIC_API_KEY = "env-key-generic"

      local valid, errors = anthropic:validate_config({
        model = "claude-haiku-4-5",
      })

      assert.is_true(valid)
      assert.equals(0, #errors)

      vim.env.ANTHROPIC_API_KEY = nil
    end)
  end)

  describe("get_auth_headers", function()
    it("returns correct headers with API key from config", function()
      local headers = anthropic:get_auth_headers({
        api_key = "test-key-123",
      })

      assert.is_table(headers)
      assert.equals("test-key-123", headers["x-api-key"])
      assert.equals("2023-06-01", headers["anthropic-version"])
      assert.equals("application/json", headers["content-type"])
    end)

    it("prioritizes config.api_key over environment variables", function()
      vim.env.AICOMMITS_NVIM_ANTHROPIC_API_KEY = "env-key-plugin"
      vim.env.ANTHROPIC_API_KEY = "env-key-generic"

      local headers = anthropic:get_auth_headers({
        api_key = "config-key",
      })

      assert.equals("config-key", headers["x-api-key"])

      vim.env.AICOMMITS_NVIM_ANTHROPIC_API_KEY = nil
      vim.env.ANTHROPIC_API_KEY = nil
    end)
  end)

  describe("get_capabilities", function()
    it("returns capability table", function()
      local caps = anthropic:get_capabilities()

      assert.is_table(caps)
      assert.is_boolean(caps.supports_streaming)
      assert.is_boolean(caps.supports_multiple_generations)
      assert.is_number(caps.max_generations)
    end)

    it("reports correct capabilities", function()
      local caps = anthropic:get_capabilities()

      assert.equals(false, caps.supports_streaming)
      assert.equals(false, caps.supports_multiple_generations)
      assert.equals(1, caps.max_generations)
    end)
  end)

  describe("generate_text()", function()
    before_each(function()
      package.loaded["aicommits.providers.anthropic"] = nil
      package.loaded["aicommits.request"] = nil
      package.loaded["aicommits.http"] = nil
    end)

    it("calls back with an error when no API key is available", function()
      vim.env.AICOMMITS_NVIM_ANTHROPIC_API_KEY = nil
      vim.env.ANTHROPIC_API_KEY = nil

      local err, texts
      require("aicommits.providers.anthropic"):generate_text({ system = "S", user = "U" }, {}, function(e, t)
        err, texts = e, t
      end)

      assert.is_string(err)
      assert.matches("API key", err)
      assert.is_nil(texts)
    end)

    it("sends system/user content and parses text blocks", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      local captured
      request.send = function(send_opts, cb)
        captured = send_opts
        cb(nil, {
          status = 200,
          body = vim.json.encode({
            content = {
              { type = "text", text = "feat: add anthropic provider" },
            },
          }),
          headers = {},
        })
      end

      local err, texts
      require("aicommits.providers.anthropic"):generate_text(
        { system = "S", user = "U", model = "claude-haiku-4-5", temperature = 0.5 },
        { api_key = "k", model = "claude-haiku-4-5" },
        function(e, t)
          err, texts = e, t
        end
      )

      assert.is_nil(err)
      assert.same({ "feat: add anthropic provider" }, texts)
      local body = vim.json.decode(captured.body)
      assert.equals("S", body.system)
      assert.equals("U", body.messages[1].content)
      assert.equals(0.5, body.temperature)

      request.send = orig_send
    end)

    it("surfaces an API error in the response body", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      request.send = function(_o, cb)
        cb(nil, { status = 400, body = vim.json.encode({ error = { message = "invalid model" } }), headers = {} })
      end

      local err
      require("aicommits.providers.anthropic"):generate_text(
        { system = "S", user = "U" },
        { api_key = "k" },
        function(e, _)
          err = e
        end
      )

      assert.is_string(err)
      assert.is_truthy(err:match("invalid model"))
      request.send = orig_send
    end)

    it("reports an error when no text blocks are returned", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      request.send = function(_o, cb)
        cb(nil, { status = 200, body = vim.json.encode({ content = {} }), headers = {} })
      end

      local err, texts
      require("aicommits.providers.anthropic"):generate_text(
        { system = "S", user = "U" },
        { api_key = "k" },
        function(e, t)
          err, texts = e, t
        end
      )

      assert.is_string(err)
      assert.is_nil(texts)
      request.send = orig_send
    end)
  end)
end)
