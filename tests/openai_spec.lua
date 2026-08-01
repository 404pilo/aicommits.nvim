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

    -- envelope.model overrides config.model per call (large_diff.summary_model does
    -- exactly this), so validate_config -- which only ever sees config.model -- cannot
    -- catch a summary model whose enum differs from the configured one.
    it("rejects a per-call envelope.model whose enum does not accept the configured effort", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      local sent = false
      request.send = function()
        sent = true
      end

      local err
      require("aicommits.providers.openai"):generate_text(
        { system = "S", user = "U", model = "gpt-5-mini", max_tokens = 100 },
        -- Valid for the configured model, invalid for the summary model.
        { api_key = "k", model = "gpt-5.6-luna", reasoning_effort = "none", verbosity = "low" },
        function(e)
          err = e
        end
      )

      request.send = orig_send

      assert.is_false(sent, "must not spend a request the API is known to reject")
      assert.is_truthy(err)
      assert.is_truthy(err:find("gpt%-5%-mini"), "error should name the effective model, not the configured one")
      assert.is_truthy(err:find("minimal"), "error should name the value this model wants instead")
    end)

    it("allows a per-call envelope.model whose enum does accept the configured effort", function()
      local request = require("aicommits.request")
      local orig_send = request.send
      local captured
      request.send = function(send_opts, cb)
        captured = send_opts
        cb(nil, {
          status = 200,
          body = vim.json.encode({ choices = { { message = { content = "sum" } } } }),
          headers = {},
        })
      end

      local err, texts
      require("aicommits.providers.openai"):generate_text(
        { system = "S", user = "U", model = "gpt-5.4-mini", max_tokens = 100 },
        { api_key = "k", model = "gpt-5.6-luna", reasoning_effort = "none", verbosity = "low" },
        function(e, t)
          err, texts = e, t
        end
      )

      request.send = orig_send

      assert.is_nil(err)
      assert.same({ "sum" }, texts)
      local body = vim.json.decode(captured.body)
      assert.equals("gpt-5.4-mini", body.model)
      assert.equals("none", body.reasoning_effort)
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

    it("never sends reasoning_effort/verbosity for a non-reasoning model even if configured", function()
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
        { system = "S", user = "U", model = "gpt-4.1-nano", max_tokens = 100 },
        { api_key = "k", model = "gpt-4.1-nano", reasoning_effort = "none", verbosity = "low" },
        function(_e, _t) end
      )

      local body = vim.json.decode(captured.body)
      assert.is_nil(body.reasoning_effort)
      assert.is_nil(body.verbosity)
      assert.is_not_nil(body.max_tokens)
      assert.is_nil(body.max_completion_tokens)

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
    it("rejects verbosity that is not a non-empty string regardless of model", function()
      local ok, errors = openai:validate_config({ api_key = "k", model = "gpt-5.6-luna", verbosity = "" })
      assert.is_false(ok)
      assert.is_truthy(vim.tbl_contains(errors, "verbosity must be a non-empty string"))
    end)

    it("rejects reasoning_effort that is not a non-empty string regardless of model", function()
      local ok, errors = openai:validate_config({ api_key = "k", model = "gpt-5.6-luna", reasoning_effort = "" })
      assert.is_false(ok)
      assert.is_truthy(vim.tbl_contains(errors, "reasoning_effort must be a non-empty string"))
    end)

    it("accepts a valid reasoning_effort string", function()
      local ok, errors = openai:validate_config({ api_key = "k", model = "gpt-5.6-luna", reasoning_effort = "medium" })
      assert.is_true(ok)
      assert.same({}, errors)
    end)

    describe("model-aware reasoning_effort/verbosity rules", function()
      it("bare gpt-5 (no version decimal): accepts minimal, rejects none", function()
        for _, model in ipairs({ "gpt-5", "gpt-5-mini", "gpt-5-nano" }) do
          local ok = openai:validate_config({ api_key = "k", model = model, reasoning_effort = "minimal" })
          assert.is_true(ok, model .. " should accept minimal")

          local ok2, errors2 = openai:validate_config({ api_key = "k", model = model, reasoning_effort = "none" })
          assert.is_false(ok2, model .. " should reject none")
          assert.is_truthy(errors2[1]:match('"minimal" for this model'))
        end
      end)

      it("gpt-5.1: accepts none, rejects xhigh (the cell that distinguishes 5.1 from 5.2+)", function()
        local ok = openai:validate_config({ api_key = "k", model = "gpt-5.1", reasoning_effort = "none" })
        assert.is_true(ok)

        local ok2, errors2 = openai:validate_config({ api_key = "k", model = "gpt-5.1", reasoning_effort = "xhigh" })
        assert.is_false(ok2)
        assert.is_truthy(errors2[1]:match('reasoning_effort "xhigh" is not supported by model "gpt%-5%.1"'))
      end)

      it("gpt-5.1-mini follows the 5.1 row (suffix does not change the base version's rule)", function()
        local ok = openai:validate_config({ api_key = "k", model = "gpt-5.1-mini", reasoning_effort = "none" })
        assert.is_true(ok)
        local ok2 = openai:validate_config({ api_key = "k", model = "gpt-5.1-mini", reasoning_effort = "xhigh" })
        assert.is_false(ok2)
      end)

      it("gpt-5.2+ (incl. 5.6-luna/sol/terra): rejects minimal, accepts none/xhigh", function()
        for _, model in ipairs({ "gpt-5.2", "gpt-5.5", "gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra" }) do
          local ok, errors = openai:validate_config({ api_key = "k", model = model, reasoning_effort = "minimal" })
          assert.is_false(ok, model .. " should reject minimal")
          assert.is_truthy(errors[1]:match('"none" for this model'))

          for _, value in ipairs({ "none", "low", "medium", "high", "xhigh" }) do
            local ok2 = openai:validate_config({ api_key = "k", model = model, reasoning_effort = value })
            assert.is_true(ok2, model .. " should accept " .. value)
          end
        end
      end)

      it("gpt-5.4-mini follows the 5.4 row (suffix must not break base-version matching)", function()
        local ok = openai:validate_config({ api_key = "k", model = "gpt-5.4-mini", reasoning_effort = "xhigh" })
        assert.is_true(ok)
        local ok2 = openai:validate_config({ api_key = "k", model = "gpt-5.4-mini", reasoning_effort = "minimal" })
        assert.is_false(ok2)
      end)

      it(
        "*-chat-latest overrides the base version to effort=medium only, even when the base version would allow more",
        function()
          -- gpt-5.2-chat-latest: the 5.2 base version alone would accept "none", but the
          -- -chat-latest suffix rule must win.
          local ok, errors =
            openai:validate_config({ api_key = "k", model = "gpt-5.2-chat-latest", reasoning_effort = "none" })
          assert.is_false(ok)
          assert.is_truthy(errors[1]:match("Supported values: medium%."))

          local ok2 =
            openai:validate_config({ api_key = "k", model = "gpt-5.2-chat-latest", reasoning_effort = "medium" })
          assert.is_true(ok2)
        end
      )

      it("o3 rejects verbosity outside medium, accepts medium; accepts xhigh reasoning_effort", function()
        local ok, errors = openai:validate_config({ api_key = "k", model = "o3", verbosity = "low" })
        assert.is_false(ok)
        assert.is_truthy(errors[1]:match('verbosity "low" is not supported by model "o3"%. Supported values: medium%.'))

        local ok2 = openai:validate_config({ api_key = "k", model = "o3", verbosity = "medium" })
        assert.is_true(ok2)

        local ok3 = openai:validate_config({ api_key = "k", model = "o3", reasoning_effort = "xhigh" })
        assert.is_true(ok3)
      end)

      it(
        "accepts any non-empty reasoning_effort/verbosity for an unrecognized model (permissiveness guarantee)",
        function()
          -- gpt-5.7/5.8 are NOT assumed to inherit the gpt-5.6 row: if OpenAI ships a
          -- new effort value with a new minor version, forward-matching would reject
          -- locally a value the API accepts. Unprobed minors stay permissive.
          for _, model in ipairs({ "gpt-6-whatever", "o5-mini", "o3-mini", "gpt-5.3", "gpt-5.7", "gpt-5.8-mini" }) do
            local ok = openai:validate_config({
              api_key = "k",
              model = model,
              reasoning_effort = "definitely-not-a-real-value",
              verbosity = "also-not-real",
            })
            assert.is_true(ok, model .. " should accept any non-empty value (unrecognized model)")
          end
        end
      )

      it(
        "gpt-5.6-luna with the config.lua defaults (reasoning_effort=none, verbosity=low) still validates clean",
        function()
          local ok, errors = openai:validate_config({
            api_key = "k",
            model = "gpt-5.6-luna",
            reasoning_effort = "none",
            verbosity = "low",
          })
          assert.is_true(ok)
          assert.same({}, errors)
        end
      )
    end)
  end)
end)
