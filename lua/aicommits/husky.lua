-- Husky/commitlint detection for aicommits.nvim
-- Reads commitlint configuration to inject into the AI system prompt
local M = {}

-- Commitlint config files to check, in priority order
local CONFIG_FILES = {
  "commitlint.config.js",
  "commitlint.config.cjs",
  "commitlint.config.ts",
  ".commitlintrc",
  ".commitlintrc.json",
  ".commitlintrc.yaml",
  ".commitlintrc.yml",
}

-- Read a file and return its content, or nil on failure
local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content ~= "" and content or nil
end

-- Detect commitlint configuration under the given root directory.
-- Returns the raw config content as a string, or nil if not found.
-- Only returns content when a .husky directory is present.
-- @param root string Path to the project root directory
-- @return string|nil commitlint config content, or nil
function M.get_commitlint_rules(root)
  -- Require .husky directory to be present
  if vim.fn.isdirectory(root .. "/.husky") == 0 then
    return nil
  end

  -- Check dedicated commitlint config files in priority order
  for _, filename in ipairs(CONFIG_FILES) do
    local path = root .. "/" .. filename
    if vim.fn.filereadable(path) == 1 then
      return read_file(path)
    end
  end

  -- Fall back to commitlint key in package.json
  local pkg_path = root .. "/package.json"
  if vim.fn.filereadable(pkg_path) == 1 then
    local content = read_file(pkg_path)
    if content then
      local ok, pkg = pcall(vim.json.decode, content)
      if ok and pkg and pkg.commitlint then
        return vim.json.encode(pkg.commitlint)
      end
    end
  end

  return nil
end

-- Get the git root of the current working directory
-- @return string|nil git root path, or nil if not in a git repo
function M.get_git_root()
  local output = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(output)
end

return M
