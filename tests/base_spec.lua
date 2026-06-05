-- Tests for the base provider generic generate_commit_message + interface.
describe("base provider", function()
  local base

  before_each(function()
    package.loaded["aicommits.providers.base"] = nil
    package.loaded["aicommits.prompts"] = nil
    base = require("aicommits.providers.base")
  end)

  it("no longer defines summarize on the Provider interface", function()
    assert.is_nil(base.Provider.summarize)
  end)

  it("defines generate_text on the Provider interface", function()
    assert.is_function(base.Provider.generate_text)
  end)

  it("generic generate_commit_message builds an envelope and processes texts", function()
    local captured_envelope
    local provider = base.new({
      name = "fake",
      generate_text = function(_self, envelope, _cfg, cb)
        captured_envelope = envelope
        cb(nil, { "feat: add thing", "feat: add thing" }) -- duplicate to test process_messages
      end,
    })

    local err, messages
    provider:generate_commit_message("DIFF", {
      max_length = 50,
      model = "m",
      generate = 2,
      temperature = 0.7,
    }, function(e, m)
      err, messages = e, m
    end)

    assert.is_nil(err)
    assert.equals("DIFF", captured_envelope.user)
    assert.equals("m", captured_envelope.model)
    assert.equals(2, captured_envelope.n)
    assert.is_string(captured_envelope.system)
    -- process_messages dedups the two identical candidates to one.
    assert.equals(1, #messages)
    assert.equals("feat: add thing", messages[1])
  end)

  it("generic generate_commit_message surfaces generate_text errors", function()
    local provider = base.new({
      name = "fake",
      generate_text = function(_self, _envelope, _cfg, cb)
        cb("boom", nil)
      end,
    })
    local err = nil
    provider:generate_commit_message("DIFF", {}, function(e, _)
      err = e
    end)
    assert.equals("boom", err)
  end)

  it("generic generate_commit_message errors when no valid messages produced", function()
    local provider = base.new({
      name = "fake",
      generate_text = function(_self, _envelope, _cfg, cb)
        cb(nil, { "", "   " })
      end,
    })
    local err, messages
    provider:generate_commit_message("DIFF", {}, function(e, m)
      err, messages = e, m
    end)
    assert.is_string(err)
    assert.is_nil(messages)
  end)
end)
