describe("input.default", function()
  it("calls callback with raw diff string", function()
    local default = require("aicommits.input.default")
    local diff_data = { diff = "diff --git a/x.lua\n+hello", files = { "x.lua" } }

    local err, payload
    default.prepare(diff_data, {}, {}, function(e, p) err = e; payload = p end)

    assert.is_nil(err)
    assert.equals(diff_data.diff, payload)
  end)

  it("passes through even when diff is empty string", function()
    local default = require("aicommits.input.default")
    local err, payload
    default.prepare({ diff = "", files = {} }, {}, {}, function(e, p) err = e; payload = p end)
    assert.is_nil(err)
    assert.equals("", payload)
  end)
end)
