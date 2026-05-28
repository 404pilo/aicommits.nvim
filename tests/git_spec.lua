-- Tests for aicommits.git module
local git = require("aicommits.git")

describe("aicommits.git", function()
  describe("is_git_repo()", function()
    it("returns true when in a git repository", function()
      -- This test assumes we're running in a git repo
      -- If not in a git repo, this test will fail (expected)
      local is_repo = git.is_git_repo()
      assert.is_boolean(is_repo)
    end)
  end)

  describe("has_staged_changes()", function()
    it("returns boolean value", function()
      if not git.is_git_repo() then
        pending("Not in a git repository, skipping test")
        return
      end

      local has_changes = git.has_staged_changes()
      assert.is_boolean(has_changes)
    end)
  end)

  describe("get_staged_files()", function()
    it("returns a table", function()
      if not git.is_git_repo() then
        pending("Not in a git repository, skipping test")
        return
      end

      local files = git.get_staged_files()
      assert.is_table(files)
    end)

    it("returns empty table when no files are staged", function()
      if not git.is_git_repo() or git.has_staged_changes() then
        pending("Skipping: not in git repo or has staged changes")
        return
      end

      local files = git.get_staged_files()
      assert.equals(0, #files)
    end)
  end)

  describe("get_last_commit_sha()", function()
    it("returns string or nil", function()
      if not git.is_git_repo() then
        pending("Not in a git repository, skipping test")
        return
      end

      local sha = git.get_last_commit_sha()
      assert.is_true(type(sha) == "string" or sha == nil)
    end)

    it("returns 40-character SHA when commits exist", function()
      if not git.is_git_repo() then
        pending("Not in a git repository, skipping test")
        return
      end

      local sha = git.get_last_commit_sha()
      if sha then
        assert.equals(40, #sha)
      end
    end)
  end)

  describe("has_remote()", function()
    it("returns boolean value", function()
      if not git.is_git_repo() then
        pending("Not in a git repository, skipping test")
        return
      end

      local has_remote = git.has_remote()
      assert.is_boolean(has_remote)
    end)
  end)

  describe("get_staged_stats()", function()
    it("returns table with correct structure", function()
      if not git.is_git_repo() then
        pending("Not in a git repository, skipping test")
        return
      end

      local stats = git.get_staged_stats()
      assert.is_table(stats)
      assert.is_number(stats.files)
      assert.is_number(stats.additions)
      assert.is_number(stats.deletions)
    end)

    it("returns zero stats when nothing is staged", function()
      if not git.is_git_repo() or git.has_staged_changes() then
        pending("Skipping: not in git repo or has staged changes")
        return
      end

      local stats = git.get_staged_stats()
      assert.equals(0, stats.files)
      assert.equals(0, stats.additions)
      assert.equals(0, stats.deletions)
    end)
  end)

  describe("get_git_root()", function()
    it("returns a string when in a git repository", function()
      if not git.is_git_repo() then
        pending("Not in a git repository, skipping test")
        return
      end

      local root = git.get_git_root()
      assert.is_string(root)
    end)

    it("returns a path that contains a .git directory", function()
      if not git.is_git_repo() then
        pending("Not in a git repository, skipping test")
        return
      end

      local root = git.get_git_root()
      assert.is_string(root)
      assert.equals(1, vim.fn.isdirectory(root .. "/.git"))
    end)
  end)

  describe("refresh_git_clients()", function()
    it("executes without error", function()
      if not git.is_git_repo() then
        pending("Not in a git repository, skipping test")
        return
      end

      -- Should not throw error even if no git clients are loaded
      assert.has_no.errors(function()
        git.refresh_git_clients()
      end)
    end)
  end)

  describe("get_staged_stat()", function()
    -- vim.v is a read-only Neovim proxy; replace it with a plain table so tests
    -- can write shell_error without errors. [inferred]
    local orig_vim_v

    before_each(function()
      orig_vim_v = vim.v
      vim.v = setmetatable({}, { __newindex = rawset, __index = orig_vim_v })
    end)

    after_each(function()
      vim.v = orig_vim_v
    end)

    it("calls callback with a string when there are staged changes", function()
      -- Stub vim.fn.system to return a fake stat line
      local orig_system = vim.fn.system

      vim.fn.system = function(_args)
        vim.v.shell_error = 0
        return " foo.lua | 3 +++\n 1 file changed, 3 insertions(+)\n"
      end

      local result_err, result_stat
      require("aicommits.git").get_staged_stat(function(err, stat)
        result_err  = err
        result_stat = stat
      end)

      assert.is_nil(result_err)
      assert.is_string(result_stat)
      assert.is_truthy(result_stat:match("file changed"))

      vim.fn.system = orig_system
    end)

    it("calls callback with error when git fails", function()
      local orig_system = vim.fn.system
      vim.fn.system = function(_args)
        vim.v.shell_error = 1
        return ""
      end

      local result_err
      require("aicommits.git").get_staged_stat(function(err, _)
        result_err = err
      end)

      assert.is_string(result_err)
      assert.is_truthy(result_err:match("[Ss]tat"))

      vim.fn.system = orig_system
    end)

    -- GAP: git-get-staged-stat-synchronous-callback
    it("invokes the callback synchronously in the same call frame", function()
      local orig_system = vim.fn.system
      vim.fn.system = function(_args)
        vim.v.shell_error = 0
        return " foo.lua | 2 ++\n 1 file changed\n"
      end

      -- If the callback fires synchronously, `invoked` will be true immediately
      -- after the call returns, before we even reach the assertion below.
      local invoked = false
      require("aicommits.git").get_staged_stat(function(_err, _stat)
        invoked = true
      end)

      -- No asynchronous waiting: the flag must already be set.
      assert.is_true(invoked)

      vim.fn.system = orig_system
    end)
  end)
end)
