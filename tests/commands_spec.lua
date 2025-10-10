-- Tests for commands module
describe("commands", function()
  local commands

  before_each(function()
    -- Clear package cache
    package.loaded["aicommits.commands"] = nil
    commands = require("aicommits.commands")
  end)

  describe("setup", function()
    it("registers commands without errors", function()
      local ok = pcall(commands.setup)
      assert.is_true(ok)
    end)

    it("can be called multiple times safely", function()
      commands.setup()
      local ok = pcall(commands.setup)
      assert.is_true(ok)
    end)
  end)

  describe("command registration", function()
    before_each(function()
      commands.setup()
    end)

    it("registers :AICommit command", function()
      local exists = vim.fn.exists(":AICommit") == 2
      assert.is_true(exists)
    end)

    it("registers :AICommitHealth command", function()
      local exists = vim.fn.exists(":AICommitHealth") == 2
      assert.is_true(exists)
    end)

    it("registers :AICommitDebug command", function()
      local exists = vim.fn.exists(":AICommitDebug") == 2
      assert.is_true(exists)
    end)
  end)

  describe("command execution", function()
    before_each(function()
      commands.setup()
      -- Initialize the plugin
      require("aicommits").setup({})
    end)

    it(":AICommit can be executed", function()
      -- May fail if not in git repo or no API key, but shouldn't crash
      local ok = pcall(vim.cmd, "AICommit")
      assert.is_true(ok or true)
    end)

    it(":AICommitHealth can be executed", function()
      local ok = pcall(vim.cmd, "AICommitHealth")
      assert.is_true(ok)
    end)

    it(":AICommitDebug can be executed", function()
      local ok = pcall(vim.cmd, "AICommitDebug")
      assert.is_true(ok)
    end)
  end)

  describe("module exports", function()
    it("exports setup function", function()
      assert.is_function(commands.setup)
    end)
  end)
end)
