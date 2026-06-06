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
  end)
end)
