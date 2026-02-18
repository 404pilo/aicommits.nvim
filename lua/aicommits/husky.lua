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
  ".commitlintrc.cjs",
  ".commitlintrc.mjs",
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

-- Try to get fully resolved commitlint config by running the CLI.
-- Returns the JSON output string, or nil if unavailable or failed.
-- @param root string Path to the project root directory
-- @return string|nil JSON config output, or nil
local function resolve_via_cli(root)
  local bin = root .. "/node_modules/.bin/commitlint"
  if vim.fn.executable(bin) == 0 then
    return nil
  end

  local cmd =
    string.format("(cd %s && ./node_modules/.bin/commitlint --print-config 2>/dev/null)", vim.fn.shellescape(root))
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 or vim.trim(output) == "" then
    return nil
  end

  return vim.trim(output)
end

-- Detect commitlint configuration under the given root directory.
-- Returns (content, is_resolved) where is_resolved is true only when the CLI
-- produced fully resolved rules (extended presets expanded). Returns (nil, false)
-- if nothing is found. Only runs when a .husky directory is present.
-- @param root string Path to the project root directory
-- @return string|nil, boolean commitlint config content and whether rules are resolved
function M.get_commitlint_rules(root)
  -- Require .husky directory to be present
  if vim.fn.isdirectory(root .. "/.husky") == 0 then
    return nil, false
  end

  -- Try to get fully resolved config via CLI (resolves extended presets)
  local resolved = resolve_via_cli(root)
  if resolved then
    return resolved, true
  end

  -- Fall back: check dedicated commitlint config files in priority order
  for _, filename in ipairs(CONFIG_FILES) do
    local path = root .. "/" .. filename
    if vim.fn.filereadable(path) == 1 then
      return read_file(path), false
    end
  end

  -- Fall back to commitlint key in package.json
  local pkg_path = root .. "/package.json"
  if vim.fn.filereadable(pkg_path) == 1 then
    local content = read_file(pkg_path)
    if content then
      local ok, pkg = pcall(vim.json.decode, content)
      if ok and pkg and pkg.commitlint then
        return vim.json.encode(pkg.commitlint), false
      end
    end
  end

  return nil, false
end

return M
