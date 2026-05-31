describe("input.init dispatcher", function()
  local config = require("aicommits.config")

  before_each(function()
    -- Reset module cache so require picks up fresh state each test
    package.loaded["aicommits.input"] = nil
    package.loaded["aicommits.input.default"] = nil
    package.loaded["aicommits.input.rich"] = nil
  end)

  it("routes to default when mode is 'off'", function()
    config.setup({ large_diff = { mode = "off" } })

    local called_default = false
    package.preload["aicommits.input.default"] = function()
      return { prepare = function(_dd, _p, _pc, cb)
        called_default = true
        cb(nil, "raw")
      end }
    end
    package.preload["aicommits.input.rich"] = function()
      return { prepare = function(_dd, _p, _pc, cb)
        error("should not be called")
      end }
    end

    local input = require("aicommits.input")
    input.prepare({ diff = "x", files = {} }, {}, {}, function(e, p)
      assert.is_nil(e)
      assert.equals("raw", p)
    end)

    assert.is_true(called_default)

    package.preload["aicommits.input.default"] = nil
    package.preload["aicommits.input.rich"] = nil
  end)

  it("routes to default when mode is 'auto' and diff is below threshold", function()
    config.setup({ large_diff = { mode = "auto", threshold_chars = 100 } })

    local called_default = false
    package.preload["aicommits.input.default"] = function()
      return { prepare = function(_dd, _p, _pc, cb)
        called_default = true; cb(nil, "raw")
      end }
    end
    package.preload["aicommits.input.rich"] = function()
      return { prepare = function() error("should not be called") end }
    end

    local input = require("aicommits.input")
    input.prepare({ diff = string.rep("x", 50), files = {} }, {}, {}, function() end)

    assert.is_true(called_default)
    package.preload["aicommits.input.default"] = nil
    package.preload["aicommits.input.rich"] = nil
  end)

  it("routes to rich when mode is 'auto' and diff exceeds threshold", function()
    config.setup({ large_diff = { mode = "auto", threshold_chars = 10 } })

    local called_rich = false
    package.preload["aicommits.input.default"] = function()
      return { prepare = function() error("should not be called") end }
    end
    package.preload["aicommits.input.rich"] = function()
      return { prepare = function(_dd, _p, _pc, cb)
        called_rich = true; cb(nil, "structured")
      end }
    end

    local input = require("aicommits.input")
    input.prepare({ diff = string.rep("x", 50), files = {} }, { summarize = function() end }, {}, function() end)

    assert.is_true(called_rich)
    package.preload["aicommits.input.default"] = nil
    package.preload["aicommits.input.rich"] = nil
  end)

  it("routes to rich when mode is 'always'", function()
    config.setup({ large_diff = { mode = "always" } })

    local called_rich = false
    package.preload["aicommits.input.default"] = function()
      return { prepare = function() error("should not be called") end }
    end
    package.preload["aicommits.input.rich"] = function()
      return { prepare = function(_dd, _p, _pc, cb)
        called_rich = true; cb(nil, "structured")
      end }
    end

    local input = require("aicommits.input")
    input.prepare({ diff = "x", files = {} }, { summarize = function() end }, {}, function() end)

    assert.is_true(called_rich)
    package.preload["aicommits.input.default"] = nil
    package.preload["aicommits.input.rich"] = nil
  end)

  it("falls back to default when rich mode selected but provider lacks summarize", function()
    config.setup({ large_diff = { mode = "always" } })

    local base = require("aicommits.providers.base")
    local provider = base.new({
      name = "x",
      generate_commit_message = function() end,
    })

    local called_default = false
    package.preload["aicommits.input.default"] = function()
      return { prepare = function(_dd, _p, _pc, cb)
        called_default = true
        cb(nil, "raw")
      end }
    end
    package.preload["aicommits.input.rich"] = function()
      return { prepare = function() error("should not be called") end }
    end

    local original_notify = vim.notify
    vim.notify = function() end

    local input = require("aicommits.input")
    input.prepare({ diff = "x", files = {} }, provider, {}, function(e, _p)
      assert.is_nil(e)
    end)

    vim.notify = original_notify
    assert.is_true(called_default)
    package.preload["aicommits.input.default"] = nil
    package.preload["aicommits.input.rich"] = nil
  end)

  it("routes to rich when provider implements summarize", function()
    config.setup({ large_diff = { mode = "always" } })

    local base = require("aicommits.providers.base")
    local provider = base.new({
      name = "x",
      generate_commit_message = function() end,
      summarize = function() end,
    })

    local called_rich = false
    package.preload["aicommits.input.default"] = function()
      return { prepare = function() error("should not be called") end }
    end
    package.preload["aicommits.input.rich"] = function()
      return { prepare = function(_dd, _p, _pc, cb)
        called_rich = true
        cb(nil, "structured")
      end }
    end

    local input = require("aicommits.input")
    input.prepare({ diff = "x", files = {} }, provider, {}, function() end)

    assert.is_true(called_rich)
    package.preload["aicommits.input.default"] = nil
    package.preload["aicommits.input.rich"] = nil
  end)
end)
