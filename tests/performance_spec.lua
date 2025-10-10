-- Performance tests for aicommits.nvim
-- Ensures plugin meets performance targets

describe("performance", function()
  describe("plugin load time", function()
    it("loads within acceptable time (< 50ms)", function()
      -- Unload module first
      package.loaded["aicommits"] = nil
      package.loaded["aicommits.config"] = nil
      package.loaded["aicommits.git"] = nil
      package.loaded["aicommits.notifications"] = nil
      package.loaded["aicommits.openai"] = nil

      local start = vim.loop.hrtime()
      require("aicommits")
      local elapsed = (vim.loop.hrtime() - start) / 1e6 -- Convert to ms

      assert.is_true(elapsed < 50, string.format("Plugin loaded in %.2fms (threshold: 50ms)", elapsed))

      -- Print timing info for monitoring
      print(string.format("Plugin load time: %.2fms", elapsed))
    end)
  end)

  describe("config module performance", function()
    it("loads config quickly (< 10ms)", function()
      package.loaded["aicommits.config"] = nil

      local start = vim.loop.hrtime()
      local config = require("aicommits.config")
      config.setup({})
      local elapsed = (vim.loop.hrtime() - start) / 1e6

      assert.is_true(elapsed < 10, string.format("Config loaded in %.2fms (threshold: 10ms)", elapsed))
    end)

    it("handles repeated get calls efficiently", function()
      local config = require("aicommits.config")
      config.setup({})

      local iterations = 1000
      local start = vim.loop.hrtime()

      for _ = 1, iterations do
        config.get("ui.picker.width")
      end

      local elapsed = (vim.loop.hrtime() - start) / 1e6
      local per_call = elapsed / iterations

      assert.is_true(per_call < 0.1, string.format("Config get: %.4fms per call (threshold: 0.1ms)", per_call))
    end)
  end)

  describe("git operations performance", function()
    it("checks git repo quickly (< 100ms)", function()
      local git = require("aicommits.git")

      local start = vim.loop.hrtime()
      git.is_git_repo()
      local elapsed = (vim.loop.hrtime() - start) / 1e6

      assert.is_true(elapsed < 100, string.format("Git repo check: %.2fms (threshold: 100ms)", elapsed))
    end)

    it("checks staged changes quickly (< 100ms)", function()
      local git = require("aicommits.git")

      local start = vim.loop.hrtime()
      git.has_staged_changes()
      local elapsed = (vim.loop.hrtime() - start) / 1e6

      assert.is_true(elapsed < 100, string.format("Staged changes check: %.2fms (threshold: 100ms)", elapsed))
    end)

    it("gets staged files quickly (< 100ms)", function()
      local git = require("aicommits.git")

      local start = vim.loop.hrtime()
      git.get_staged_files()
      local elapsed = (vim.loop.hrtime() - start) / 1e6

      assert.is_true(elapsed < 100, string.format("Get staged files: %.2fms (threshold: 100ms)", elapsed))
    end)
  end)

  describe("notification module performance", function()
    it("loads notifications module quickly (< 10ms)", function()
      package.loaded["aicommits.notifications"] = nil

      local start = vim.loop.hrtime()
      require("aicommits.notifications")
      local elapsed = (vim.loop.hrtime() - start) / 1e6

      assert.is_true(elapsed < 10, string.format("Notifications loaded in %.2fms (threshold: 10ms)", elapsed))
    end)
  end)

  describe("memory usage", function()
    it("has reasonable memory footprint", function()
      -- Force garbage collection before measurement
      collectgarbage("collect")
      local mem_before = collectgarbage("count")

      -- Load plugin
      package.loaded["aicommits"] = nil
      require("aicommits").setup({})

      -- Force garbage collection after load
      collectgarbage("collect")
      local mem_after = collectgarbage("count")

      local mem_used = mem_after - mem_before

      -- Should use less than 1MB (1024KB)
      assert.is_true(mem_used < 1024, string.format("Memory used: %.2fKB (threshold: 1024KB)", mem_used))

      print(string.format("Memory footprint: %.2fKB", mem_used))
    end)
  end)

  describe("module loading", function()
    it("loads all core modules without errors", function()
      local modules = {
        "aicommits",
        "aicommits.config",
        "aicommits.git",
        "aicommits.notifications",
        "aicommits.health",
        "aicommits.commands",
        "aicommits.openai",
        "aicommits.commit",
        "aicommits.utils",
      }

      for _, module_name in ipairs(modules) do
        package.loaded[module_name] = nil
        local ok, module = pcall(require, module_name)
        assert.is_true(ok, string.format("Failed to load %s: %s", module_name, module))
        assert.is_not_nil(module)
      end
    end)
  end)
end)
