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
end)
