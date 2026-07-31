-- Unit tests for the Codex (ChatGPT OAuth) provider
local mock = require("tests.helpers.mock")

local SENTINEL = "SENTINEL-ACCESS-TOKEN-DO-NOT-LEAK"

local VALID_AUTH_JSON = '{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"id_token":"test-id-token",'
  .. '"access_token":"'
  .. SENTINEL
  .. '","refresh_token":"test-refresh-token","account_id":"test-account-id"},'
  .. '"last_refresh":"2026-07-30T00:00:00Z"}'

describe("codex provider", function()
  local codex
  local request
  local orig_send
  local captured
  local tmp
  local cleanup_env

  local function _write_auth(json_string)
    vim.fn.writefile({ json_string }, tmp .. "/auth.json")
  end

  local function _sse(frames)
    local parts = {}
    for _, frame in ipairs(frames) do
      table.insert(parts, "data: " .. vim.json.encode(frame))
    end
    return table.concat(parts, "\n\n")
  end

  local function _stub(status, body)
    request.send = function(opts, cb)
      captured = opts
      cb(nil, { status = status, body = body, headers = {} })
    end
  end

  before_each(function()
    package.loaded["aicommits.providers.codex"] = nil
    package.loaded["aicommits.request"] = nil

    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    cleanup_env = mock.mock_env({ CODEX_HOME = tmp })
    _write_auth(VALID_AUTH_JSON)

    request = require("aicommits.request")
    orig_send = request.send
    codex = require("aicommits.providers.codex")
    captured = nil
  end)

  after_each(function()
    request.send = orig_send
    cleanup_env()
    vim.fn.delete(tmp, "rf")
  end)

  describe("initialization/interface", function()
    it("has correct name", function()
      assert.equals("codex", codex.name)
    end)

    it("implements required methods and does not implement summarize", function()
      assert.is_function(codex.generate_text)
      assert.is_function(codex.validate_config)
      assert.is_function(codex.get_auth_headers)
      assert.is_function(codex.get_capabilities)
      assert.is_function(codex.generate_commit_message)
      assert.is_nil(codex.summarize)
    end)

    it("returns the expected capabilities", function()
      assert.same({
        supports_streaming = false,
        supports_multiple_generations = false,
        max_generations = 1,
      }, codex:get_capabilities())
    end)
  end)

  describe("success paths", function()
    it("concatenates output_text.delta events and returns one commit message", function()
      _stub(
        200,
        _sse({
          { type = "response.output_text.delta", delta = "feat: add " },
          { type = "response.output_text.delta", delta = "thing" },
          { type = "response.completed" },
        })
      )

      local err, texts
      codex:generate_text({ system = "S", user = "U", model = "gpt-5.6-terra" }, {}, function(e, t)
        err, texts = e, t
      end)

      assert.is_nil(err)
      assert.same({ "feat: add thing" }, texts)
    end)

    it("concatenates deltas in ARRIVAL order, not sorted by sequence_number", function()
      _stub(
        200,
        _sse({
          { type = "response.output_text.delta", delta = "feat: ", sequence_number = 5 },
          { type = "response.output_text.delta", delta = "add ", sequence_number = 3 },
          { type = "response.output_text.delta", delta = "thing", sequence_number = 1 },
          { type = "response.completed" },
        })
      )

      local err, texts
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, t)
        err, texts = e, t
      end)

      assert.is_nil(err)
      assert.same({ "feat: add thing" }, texts)
    end)

    it("ignores reasoning_summary_text.delta, unknown types, and SSE noise lines", function()
      local body_parts = {}
      table.insert(body_parts, "event: response.output_text.delta")
      table.insert(body_parts, "id: 1")
      table.insert(body_parts, ": this is a comment")
      table.insert(
        body_parts,
        "data: " .. vim.json.encode({ type = "response.reasoning_summary_text.delta", delta = "thinking..." })
      )
      table.insert(
        body_parts,
        "data: " .. vim.json.encode({ type = "some.unknown.event", delta = "should-not-appear" })
      )
      table.insert(body_parts, "data: " .. vim.json.encode({ type = "response.output_text.delta", delta = "feat: ok" }))
      table.insert(body_parts, "data: [DONE]")
      table.insert(body_parts, "")
      table.insert(body_parts, "data: " .. vim.json.encode({ type = "response.completed" }))

      -- Add trailing \r to every line to prove CRLF handling.
      local crlf_body = table.concat(body_parts, "\r\n")

      _stub(200, crlf_body)

      local err, texts
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, t)
        err, texts = e, t
      end)

      assert.is_nil(err)
      assert.same({ "feat: ok" }, texts)
    end)

    it("respects $CODEX_HOME and sends the resolved credentials as headers", function()
      _stub(200, _sse({ { type = "response.output_text.delta", delta = "feat: x" }, { type = "response.completed" } }))

      codex:generate_text({ system = "S", user = "U" }, {}, function() end)

      assert.is_not_nil(captured)
      assert.equals("Bearer " .. SENTINEL, captured.headers.Authorization)
      assert.equals("test-account-id", captured.headers["ChatGPT-Account-ID"])
    end)
  end)

  describe("request shape", function()
    it("builds the expected body and drops rejected envelope fields", function()
      _stub(200, _sse({ { type = "response.output_text.delta", delta = "feat: x" }, { type = "response.completed" } }))

      codex:generate_text({
        system = "SYSTEM PROMPT",
        user = "THE DIFF",
        model = "gpt-5.6-terra",
        temperature = 0.7,
        top_p = 0.9,
        max_output_tokens = 100,
        max_tokens = 100,
        n = 3,
        frequency_penalty = 0.5,
        presence_penalty = 0.5,
      }, { model = "gpt-5.6-terra" }, function() end)

      assert.equals("https://chatgpt.com/backend-api/codex/responses", captured.url)
      local body = vim.json.decode(captured.body)
      assert.is_true(body.stream)
      assert.is_false(body.store)
      assert.equals("developer", body.input[1].role)
      assert.equals("input_text", body.input[1].content[1].type)
      assert.equals("SYSTEM PROMPT", body.input[1].content[1].text)
      assert.equals("user", body.input[2].role)
      assert.equals("THE DIFF", body.input[2].content[1].text)

      assert.is_nil(body.temperature)
      assert.is_nil(body.top_p)
      assert.is_nil(body.max_output_tokens)
      assert.is_nil(body.max_tokens)
      assert.is_nil(body.n)
      assert.is_nil(body.frequency_penalty)
      assert.is_nil(body.presence_penalty)
    end)

    it("omits reasoning/text entirely when config has neither key", function()
      _stub(200, _sse({ { type = "response.output_text.delta", delta = "feat: x" }, { type = "response.completed" } }))

      codex:generate_text({ system = "S", user = "U" }, {}, function() end)

      assert.is_nil(captured.body:find('"reasoning"', 1, true))
      assert.is_nil(captured.body:find('"verbosity"', 1, true))
    end)

    it("includes reasoning/text when configured", function()
      _stub(200, _sse({ { type = "response.output_text.delta", delta = "feat: x" }, { type = "response.completed" } }))

      codex:generate_text(
        { system = "S", user = "U" },
        { reasoning_effort = "none", verbosity = "low" },
        function() end
      )

      local body = vim.json.decode(captured.body)
      assert.equals("none", body.reasoning.effort)
      assert.equals("low", body.text.verbosity)
    end)
  end)

  describe("headers", function()
    it("sets the client-identity headers and never sets Content-Type", function()
      _stub(200, _sse({ { type = "response.output_text.delta", delta = "feat: x" }, { type = "response.completed" } }))

      codex:generate_text({ system = "S", user = "U" }, {}, function() end)

      assert.equals("codex_cli_rs", captured.headers.originator)
      assert.equals("responses_websockets=2026-02-06", captured.headers["OpenAI-Beta"])
      assert.is_truthy(captured.headers["User-Agent"]:match("^codex_cli_rs/"))
      assert.is_nil(captured.headers["Content-Type"])
    end)
  end)

  describe("endpoint override and policy", function()
    it("uses config.endpoint when set, and falls back to default when empty string", function()
      _stub(200, _sse({ { type = "response.output_text.delta", delta = "feat: x" }, { type = "response.completed" } }))

      codex:generate_text({ system = "S", user = "U" }, { endpoint = "https://example.test/custom" }, function() end)
      assert.equals("https://example.test/custom", captured.url)

      codex:generate_text({ system = "S", user = "U" }, { endpoint = "" }, function() end)
      assert.equals("https://chatgpt.com/backend-api/codex/responses", captured.url)
    end)

    it("passes a policy table through request.send", function()
      _stub(200, _sse({ { type = "response.output_text.delta", delta = "feat: x" }, { type = "response.completed" } }))

      codex:generate_text({ system = "S", user = "U" }, {}, function() end)

      assert.is_table(captured.policy)
    end)
  end)

  describe("auth failures", function()
    local function assert_auth_failure()
      local send_called = false
      request.send = function(_opts, _cb)
        send_called = true
      end

      local err, texts
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, t)
        err, texts = e, t
      end)

      assert.equals("Codex credentials not found. Run: `codex login`", err)
      assert.is_nil(texts)
      assert.is_false(send_called)
    end

    it("fails when auth.json is missing", function()
      vim.fn.delete(tmp .. "/auth.json")
      assert_auth_failure()
    end)

    it("fails when auth.json is malformed JSON", function()
      _write_auth("{not valid json")
      assert_auth_failure()
    end)

    it("fails when tokens.access_token is absent", function()
      _write_auth(
        '{"auth_mode":"chatgpt","tokens":{"account_id":"test-account-id"},"last_refresh":"2026-07-30T00:00:00Z"}'
      )
      assert_auth_failure()
    end)

    it("fails when tokens.access_token is JSON null (vim.NIL)", function()
      _write_auth(
        '{"auth_mode":"chatgpt","tokens":{"access_token":null,"account_id":"test-account-id"},'
          .. '"last_refresh":"2026-07-30T00:00:00Z"}'
      )
      assert_auth_failure()
    end)

    it("fails when tokens.account_id is absent", function()
      _write_auth('{"auth_mode":"chatgpt","tokens":{"access_token":"' .. SENTINEL .. '"},"last_refresh":"x"}')
      assert_auth_failure()
    end)
  end)

  describe("HTTP failures", function()
    it("maps 401 to the session-expired message, never leaking the token", function()
      _stub(401, "")
      local err
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, _)
        err = e
      end)
      assert.equals("Codex session expired. Run: `codex login`", err)
      assert.is_nil(err:find(SENTINEL, 1, true))
    end)

    it("surfaces a flat 400 detail verbatim, framed as unsupported, never leaking the token", function()
      _stub(400, vim.json.encode({ detail = "Unsupported parameter: temperature" }))
      local err
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, _)
        err = e
      end)
      assert.is_truthy(err:find("Unsupported parameter: temperature", 1, true))
      assert.is_truthy(err:find("parameter not supported by the ChatGPT Codex backend", 1, true))
      assert.is_nil(err:find(SENTINEL, 1, true))
    end)

    it("surfaces a rich 400 error.message, never leaking the token", function()
      _stub(400, vim.json.encode({ error = { message = "bad value" } }))
      local err
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, _)
        err = e
      end)
      assert.equals("Codex API Error: bad value", err)
      assert.is_nil(err:find(SENTINEL, 1, true))
    end)

    it("surfaces exactly the HTTP-status form for an undecodable body, without echoing it or the token", function()
      _stub(400, "not json at all: <script>super-secret-body-content</script>")
      local err
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, _)
        err = e
      end)
      assert.equals("Codex API Error (HTTP 400)", err)
      assert.is_nil(err:find(SENTINEL, 1, true))
    end)

    it("passes a transport error through verbatim", function()
      request.send = function(_opts, cb)
        cb("connection reset", nil)
      end
      local err
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, _)
        err = e
      end)
      assert.equals("connection reset", err)
    end)

    it("returns the generic message when 200 but no response.completed arrived, never leaking the token", function()
      _stub(200, _sse({ { type = "response.output_text.delta", delta = "feat: x" } }))
      local err, texts
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, t)
        err, texts = e, t
      end)
      assert.equals("No commit messages were generated. Try again.", err)
      assert.is_nil(texts)
      assert.is_nil(err:find(SENTINEL, 1, true))
    end)

    it("returns the generic message when completed but deltas are whitespace-only", function()
      _stub(
        200,
        _sse({
          { type = "response.output_text.delta", delta = "   " },
          { type = "response.output_text.delta", delta = "\n" },
          { type = "response.completed" },
        })
      )
      local err, texts
      codex:generate_text({ system = "S", user = "U" }, {}, function(e, t)
        err, texts = e, t
      end)
      assert.equals("No commit messages were generated. Try again.", err)
      assert.is_nil(texts)
    end)
  end)

  describe("validate_config", function()
    local function base_valid_config()
      return {
        model = "gpt-5.6-terra",
        max_length = 50,
        generate = 1,
        reasoning_effort = "none",
        verbosity = "low",
      }
    end

    it("accepts a full valid config", function()
      local valid, errors = codex:validate_config(base_valid_config())
      assert.is_true(valid)
      assert.equals(0, #errors)
    end)

    it("rejects a missing model", function()
      local cfg = base_valid_config()
      cfg.model = nil
      local valid, errors = codex:validate_config(cfg)
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("rejects generate = 2 while 1 and nil pass", function()
      local cfg = base_valid_config()
      cfg.generate = 2
      local valid, errors = codex:validate_config(cfg)
      assert.is_false(valid)
      assert.is_true(#errors > 0)

      cfg.generate = 1
      valid, errors = codex:validate_config(cfg)
      assert.is_true(valid)

      cfg.generate = nil
      valid, errors = codex:validate_config(cfg)
      assert.is_true(valid)
    end)

    it("accepts each of the 7 reasoning efforts and rejects an out-of-enum value", function()
      local cfg = base_valid_config()
      for _, effort in ipairs({ "none", "minimal", "low", "medium", "high", "xhigh", "max" }) do
        cfg.reasoning_effort = effort
        local valid, _errors = codex:validate_config(cfg)
        assert.is_true(valid, "expected effort '" .. effort .. "' to be valid")
      end

      cfg.reasoning_effort = "ultra"
      local valid, errors = codex:validate_config(cfg)
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("rejects verbosity = 'verbose'", function()
      local cfg = base_valid_config()
      cfg.verbosity = "verbose"
      local valid, errors = codex:validate_config(cfg)
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("rejects max_length = 0 and max_length = 'x'", function()
      local cfg = base_valid_config()
      cfg.max_length = 0
      local valid, errors = codex:validate_config(cfg)
      assert.is_false(valid)
      assert.is_true(#errors > 0)

      cfg.max_length = "x"
      valid, errors = codex:validate_config(cfg)
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)

    it("reports a credentials error when auth.json is missing", function()
      vim.fn.delete(tmp .. "/auth.json")
      local cfg = base_valid_config()
      local valid, errors = codex:validate_config(cfg)
      assert.is_false(valid)
      local found = false
      for _, e in ipairs(errors) do
        if e:find("Codex credentials not found", 1, true) then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("collects >= 2 errors for a config that is bad in two ways (no early return)", function()
      local cfg = base_valid_config()
      cfg.model = nil
      cfg.generate = 2
      local valid, errors = codex:validate_config(cfg)
      assert.is_false(valid)
      assert.is_true(#errors >= 2)
    end)
  end)

  describe("security", function()
    it("get_auth_headers never raises when auth.json is missing, and returns a safe placeholder", function()
      vim.fn.delete(tmp .. "/auth.json")
      local headers
      assert.has_no.errors(function()
        headers = codex:get_auth_headers({})
      end)
      assert.is_table(headers)
      assert.equals("Bearer ", headers.Authorization)
    end)
  end)
end)
