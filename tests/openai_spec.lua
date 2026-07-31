-- Unit tests for OpenAI provider
describe("openai provider", function()
  local openai
  local base

  before_each(function()
    package.loaded["aicommits.providers.openai"] = nil
    package.loaded["aicommits.providers.base"] = nil

    base = require("aicommits.providers.base")
    openai = require("aicommits.providers.openai")
  end)

  describe("initialization", function()
    it("has correct name", function()
      assert.equals("openai", openai.name)
    end)

    it("implements required methods", function()
      assert.is_function(openai.generate_commit_message)
      assert.is_function(openai.validate_config)
      assert.is_function(openai.get_auth_headers)
      assert.is_function(openai.get_capabilities)
    end)
  end)

  describe("interface", function()
    it("implements generate_text and not summarize", function()
      assert.is_function(openai.generate_text)
      assert.is_nil(openai.summarize)
    end)
  end)

  describe("generate_text()", function()
    local orig_post

    before_each(function()
      package.loaded["aicommits.providers.openai"] = nil
      package.loaded["aicommits.request"] = nil
      package.loaded["aicommits.http"] = nil
      orig_post = require("aicommits.http").post
    end)

    after_each(function()
      require("aicommits.http").post = orig_post
    end)

    it("calls request.send (not http.post) and maps n/top_p onto the body", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      local captured
      request.send = function(send_opts, cb)
        captured = send_opts
        cb(nil, {
          status = 200,
          body = vim.json.encode({
            choices = { { message = { content = "first" } }, { message = { content = "second" } } },
          }),
          headers = {},
        })
      end

      local err, texts
      require("aicommits.providers.openai"):generate_text(
        { system = "S", user = "U", model = "gpt-4.1-nano", n = 2, top_p = 0.9, temperature = 0.3, max_tokens = 100 },
        { api_key = "k", model = "gpt-4.1-nano" },
        function(e, t)
          err, texts = e, t
        end
      )

      assert.is_nil(err)
      assert.same({ "first", "second" }, texts)
      local body = vim.json.decode(captured.body)
      assert.equals(2, body.n)
      assert.equals(0.9, body.top_p)
      assert.equals("S", body.messages[1].content)
      assert.equals("U", body.messages[2].content)
      assert.equals(100, body.max_tokens)
      assert.is_nil(body.max_completion_tokens)

      request.send = orig_send
    end)

    it("surfaces an error string when request.send returns a transport error", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      request.send = function(_o, cb)
        cb("network error", nil)
      end
      local err
      require("aicommits.providers.openai"):generate_text(
        { system = "S", user = "U" },
        { api_key = "k" },
        function(e, _)
          err = e
        end
      )
      assert.is_string(err)
      request.send = orig_send
    end)

    it("surfaces an API error in the response body", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      request.send = function(_o, cb)
        cb(nil, { status = 400, body = vim.json.encode({ error = { message = "bad request" } }), headers = {} })
      end
      local err
      require("aicommits.providers.openai"):generate_text(
        { system = "S", user = "U" },
        { api_key = "k" },
        function(e, _)
          err = e
        end
      )
      assert.is_string(err)
      assert.is_truthy(err:match("bad request"))
      request.send = orig_send
    end)

    it("uses max_completion_tokens and omits temperature/top_p/penalties for a reasoning model", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      local captured
      request.send = function(send_opts, cb)
        captured = send_opts
        cb(nil, {
          status = 200,
          body = vim.json.encode({ choices = { { message = { content = "msg" } } } }),
          headers = {},
        })
      end

      require("aicommits.providers.openai"):generate_text({
        system = "S",
        user = "U",
        model = "gpt-5.6-luna",
        max_tokens = 150,
        temperature = 0.3,
        top_p = 0.9,
        frequency_penalty = 0.1,
        presence_penalty = 0.1,
      }, { api_key = "k", model = "gpt-5.6-luna" }, function(_e, _t) end)

      local body = vim.json.decode(captured.body)
      assert.equals(150, body.max_completion_tokens)
      assert.is_nil(body.max_tokens)
      assert.is_nil(body.temperature)
      assert.is_nil(body.top_p)
      assert.is_nil(body.frequency_penalty)
      assert.is_nil(body.presence_penalty)

      request.send = orig_send
    end)

    it("sets top-level reasoning_effort and verbosity for a reasoning model", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      local captured
      request.send = function(send_opts, cb)
        captured = send_opts
        cb(nil, {
          status = 200,
          body = vim.json.encode({ choices = { { message = { content = "msg" } } } }),
          headers = {},
        })
      end

      require("aicommits.providers.openai"):generate_text(
        { system = "S", user = "U", model = "gpt-5.6-luna", max_tokens = 150 },
        { api_key = "k", model = "gpt-5.6-luna", reasoning_effort = "low", verbosity = "medium" },
        function(_e, _t) end
      )

      local body = vim.json.decode(captured.body)
      assert.equals("low", body.reasoning_effort)
      assert.equals("medium", body.verbosity)

      request.send = orig_send
    end)

    it("surfaces an actionable error when reasoning consumes the whole token budget", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      request.send = function(_o, cb)
        cb(nil, {
          status = 200,
          body = vim.json.encode({
            choices = { { message = { content = "" }, finish_reason = "length" } },
          }),
          headers = {},
        })
      end

      local err, texts
      require("aicommits.providers.openai"):generate_text(
        { system = "S", user = "U", model = "gpt-5.6-luna", max_tokens = 200 },
        { api_key = "k", model = "gpt-5.6-luna", reasoning_effort = "xhigh" },
        function(e, t)
          err, texts = e, t
        end
      )

      assert.is_nil(texts)
      assert.is_string(err)
      assert.is_truthy(err:match("Response truncated"))

      request.send = orig_send
    end)

    it("filters out empty/whitespace-only choices while keeping non-empty ones", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      request.send = function(_o, cb)
        cb(nil, {
          status = 200,
          body = vim.json.encode({
            choices = {
              { message = { content = "  " }, finish_reason = "stop" },
              { message = { content = "real message" }, finish_reason = "stop" },
            },
          }),
          headers = {},
        })
      end

      local err, texts
      require("aicommits.providers.openai"):generate_text(
        { system = "S", user = "U" },
        { api_key = "k" },
        function(e, t)
          err, texts = e, t
        end
      )

      assert.is_nil(err)
      assert.same({ "real message" }, texts)

      request.send = orig_send
    end)
  end)

  describe("validate_config()", function()
    it("rejects verbosity outside low/medium/high", function()
      local ok, errors = openai:validate_config({ api_key = "k", model = "gpt-5.6-luna", verbosity = "extreme" })
      assert.is_false(ok)
      assert.is_truthy(vim.tbl_contains(errors, "verbosity must be one of: low, medium, high"))
    end)

    it("accepts a valid reasoning_effort string", function()
      local ok, errors = openai:validate_config({ api_key = "k", model = "gpt-5.6-luna", reasoning_effort = "medium" })
      assert.is_true(ok)
      assert.same({}, errors)
    end)

    it("rejects codex-only reasoning_effort values (minimal, max)", function()
      for _, value in ipairs({ "minimal", "max" }) do
        local ok, errors = openai:validate_config({ api_key = "k", model = "gpt-5.6-luna", reasoning_effort = value })
        assert.is_false(ok)
        assert.is_truthy(vim.tbl_contains(errors, "reasoning_effort must be one of: none, low, medium, high, xhigh"))
      end
    end)

    it("accepts all valid public-API reasoning_effort values", function()
      for _, value in ipairs({ "none", "low", "medium", "high", "xhigh" }) do
        local ok, errors = openai:validate_config({ api_key = "k", model = "gpt-5.6-luna", reasoning_effort = value })
        assert.is_true(ok)
        assert.same({}, errors)
      end
    end)
  end)
end)
