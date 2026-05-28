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

    -- GAP: provider-summarize-interface-exists (openai)
    it("exposes summarize as a function", function()
      assert.is_function(openai.summarize)
    end)
  end)

  describe("summarize()", function()
    it("calls callback with summary text on success", function()
      -- Stub http.post to return a canned OpenAI chat-completions response
      local http = require("aicommits.http")
      local orig_post = http.post
      http.post = function(_url, _headers, _body, cb)
        cb(nil, vim.json.encode({
          choices = {
            {
              message = { content = "- updated openai helper" },
            },
          },
        }))
      end

      local provider = require("aicommits.providers.openai")
      local err, summary
      provider:summarize(
        "diff text",
        { prompt_kind = "chunk", file_path = "a.lua", max_tokens = 220, temperature = 0.2 },
        { api_key = "test-key", model = "gpt-4.1-nano" },
        function(e, s) err = e; summary = s end
      )

      assert.is_nil(err)
      assert.is_string(summary)
      assert.is_truthy(summary:match("openai helper"))

      http.post = orig_post
    end)

    it("calls callback with error when http.post returns error", function()
      local http = require("aicommits.http")
      local orig_post = http.post
      http.post = function(_url, _headers, _body, cb)
        cb("network error", nil)
      end

      local err
      require("aicommits.providers.openai"):summarize(
        "diff text",
        { prompt_kind = "chunk", file_path = "a.lua", max_tokens = 220, temperature = 0.2 },
        { api_key = "test-key" },
        function(e, _) err = e end
      )

      assert.is_string(err)

      http.post = orig_post
    end)
  end)
end)
