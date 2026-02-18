-- Git operations for aicommits.nvim
local M = {}

-- Check if currently in a git repository
function M.is_git_repo()
  local result = vim.system({ "git", "rev-parse", "--is-inside-work-tree" }, { stderr = false }):wait()
  return result.code == 0
end

-- Check if there are staged changes
function M.has_staged_changes()
  local result = vim.fn.system("git diff --cached --quiet")
  -- Non-zero exit code means changes exist
  return vim.v.shell_error ~= 0
end

-- Get list of staged files
function M.get_staged_files()
  local output = vim.fn.system({ "git", "diff", "--cached", "--name-only" })
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local files = {}
  for file in output:gmatch("[^\r\n]+") do
    if file ~= "" then
      table.insert(files, file)
    end
  end
  return files
end

-- Get SHA of last commit
function M.get_last_commit_sha()
  local result = vim.system({ "git", "log", "-1", "--pretty=%H" }, { stderr = false }):wait()
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout)
end

-- Check if repository has a remote configured
function M.has_remote()
  local result = vim.system({ "git", "remote", "-v" }, { stderr = false }):wait()
  if result.code ~= 0 then
    return false
  end
  return result.stdout ~= "" and result.stdout ~= "\n"
end

-- Get number of staged changes (files + hunks)
function M.get_staged_stats()
  local files = M.get_staged_files()
  local output = vim.fn.system({ "git", "diff", "--cached", "--numstat" })

  local stats = {
    files = #files,
    additions = 0,
    deletions = 0,
  }

  if vim.v.shell_error == 0 then
    for line in output:gmatch("[^\r\n]+") do
      local additions, deletions = line:match("^(%d+)%s+(%d+)")
      if additions and deletions then
        stats.additions = stats.additions + tonumber(additions)
        stats.deletions = stats.deletions + tonumber(deletions)
      end
    end
  end

  return stats
end

-- Get full staged diff for AI processing
-- Excludes lock files and uses minimal diff algorithm
-- @param callback function(error, diff_data) Callback with error or {files, diff}
function M.get_staged_diff(callback)
  -- Files to exclude from diff
  local exclude_patterns = {
    ":(exclude)package-lock.json",
    ":(exclude)pnpm-lock.yaml",
    ":(exclude)*.lock",
  }

  local diff_args = {
    "diff",
    "--cached",
    "--diff-algorithm=minimal",
  }

  -- First, get list of staged files
  local file_args = vim.list_extend(vim.deepcopy(diff_args), { "--name-only" })
  file_args = vim.list_extend(file_args, exclude_patterns)

  local files_output = vim.fn.system(vim.list_extend({ "git" }, file_args))
  if vim.v.shell_error ~= 0 then
    callback("Failed to get staged files", nil)
    return
  end

  -- Check if there are any staged files
  if files_output == "" or files_output == "\n" then
    callback(nil, nil) -- No staged changes
    return
  end

  -- Parse file list
  local files = {}
  for file in files_output:gmatch("[^\r\n]+") do
    if file ~= "" then
      table.insert(files, file)
    end
  end

  -- Get full diff content
  local diff_args_full = vim.list_extend(vim.deepcopy(diff_args), exclude_patterns)
  local diff_output = vim.fn.system(vim.list_extend({ "git" }, diff_args_full))

  if vim.v.shell_error ~= 0 then
    callback("Failed to get staged diff", nil)
    return
  end

  callback(nil, {
    files = files,
    diff = diff_output,
  })
end

-- Create a git commit with the given message
-- @param message string The commit message
-- @param callback function(error) Callback with error or nil on success
function M.create_commit(message, callback)
  -- Escape message for shell
  local escaped_message = message:gsub('"', '\\"')

  -- Execute git commit
  local output = vim.fn.system({ "git", "commit", "-m", escaped_message })

  if vim.v.shell_error ~= 0 then
    callback("Git commit failed: " .. output)
    return
  end

  callback(nil)
end

-- Refresh integrated git clients after commit
function M.refresh_git_clients()
  local config = require("aicommits.config")

  -- Neogit integration
  local neogit_config = config.get("integrations.neogit")
  if neogit_config and neogit_config.enabled and package.loaded["neogit"] then
    vim.schedule(function()
      local ok = pcall(function()
        require("neogit").refresh()
      end)
      if not ok then
        -- Silently fail if Neogit refresh errors
      end
    end)
  end

  -- Fugitive integration (future)
  if config.get("integrations.fugitive") and vim.fn.exists(":Git") == 2 then
    vim.schedule(function()
      pcall(vim.cmd, "silent! Git")
    end)
  end
end

return M
