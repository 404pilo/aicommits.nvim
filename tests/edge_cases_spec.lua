-- Edge case tests for aicommits.nvim
-- Tests failure scenarios, boundary conditions, and error handling

local mock = require("tests.helpers.mock")

describe("edge cases", function()
  local git, config

  before_each(function()
    -- Reset modules
    package.loaded["aicommits.git"] = nil
    package.loaded["aicommits.config"] = nil

    git = require("aicommits.git")
    config = require("aicommits.config")
    config.setup({})
  end)

  describe("git repository validation", function()
    it("checks git repo without crashing", function()
      -- Test that the function executes without error
      local ok, result = pcall(git.is_git_repo)
      assert.is_true(ok)
      assert.is_boolean(result)
    end)

    it("handles git commands gracefully", function()
      -- Test that git functions handle edge cases
      local ok1 = pcall(git.is_git_repo)
      local ok2 = pcall(git.has_staged_changes)
      local ok3 = pcall(git.get_staged_files)

      assert.is_true(ok1)
      assert.is_true(ok2)
      assert.is_true(ok3)
    end)
  end)

  describe("staged changes detection", function()
    it("has_staged_changes returns boolean", function()
      local result = git.has_staged_changes()
      assert.is_boolean(result)
    end)

    it("get_staged_files returns table", function()
      local result = git.get_staged_files()
      assert.is_table(result)
    end)

    it("handles git operations gracefully", function()
      -- Test that functions don't crash on edge cases
      local ok, files = pcall(git.get_staged_files)
      assert.is_true(ok)
      assert.is_table(files)
    end)
  end)

  describe("API key management", function()
    it("can read environment variables", function()
      -- Test that env var reading works
      local api_key = vim.fn.getenv("OPENAI_API_KEY")
      -- Should be either a string or empty
      assert.is_true(type(api_key) == "string" or api_key == vim.NIL)
    end)

    it("can read alternative env var", function()
      local api_key = vim.fn.getenv("AICOMMITS_NVIM_OPENAI_API_KEY")
      -- Should be either a string or empty
      assert.is_true(type(api_key) == "string" or api_key == vim.NIL)
    end)

    it("provider validates missing API keys gracefully", function()
      local providers = require("aicommits.providers")
      providers.setup()
      local openai = providers.get("openai")

      -- validate_config should handle missing API key (can come from env)
      local valid, errors = openai:validate_config({ model = "gpt-4.1-nano" })
      assert.is_true(valid or #errors > 0) -- Either valid (from env) or has error
    end)
  end)

  describe("large file handling", function()
    it("handles large git diff output", function()
      local large_diff = string.rep("line\n", 10000)
      local cleanup = mock.mock_system({
        ["git diff %-%-cached %-%-name%-only"] = {
          output = large_diff,
          exit_code = 0,
        },
      })

      -- Should not hang or crash
      local result = git.get_staged_files()
      assert.is_not_nil(result)

      cleanup()
    end)
  end)

  describe("configuration edge cases", function()
    it("handles nil configuration gracefully", function()
      local ok = pcall(function()
        config.setup(nil)
      end)
      assert.is_true(ok)
    end)

    it("handles empty configuration", function()
      local ok = pcall(function()
        config.setup({})
      end)
      assert.is_true(ok)
    end)

    it("handles invalid configuration values", function()
      local ok = pcall(function()
        config.setup({
          providers = {
            openai = {
              model = 123, -- should be string
              max_length = "not a number", -- should be number
            },
          },
        })
      end)
      -- Should not crash during setup
      assert.is_true(ok)

      -- Provider validation should detect invalid model type
      local providers = require("aicommits.providers")
      providers.setup()
      local provider_config = config.get("providers.openai")
      local openai = providers.get("openai")
      local valid, errors = openai:validate_config(provider_config)

      -- Model with value 123 should fail validation
      assert.is_false(valid)
      assert.is_true(#errors > 0)
    end)
  end)
end)
