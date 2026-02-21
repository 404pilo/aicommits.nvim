# Resolved Commitlint Config Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace raw commitlint config file injection with the fully resolved config (all rules from extended presets included) by running `./node_modules/.bin/commitlint --print-config`, so the AI model sees explicit rules like `subject-case` and follows them correctly.

**Architecture:** In `husky.lua`, add a `resolve_via_cli(root)` helper that runs `node_modules/.bin/commitlint --print-config` in a subshell from the git root and returns the JSON output. Update `get_commitlint_rules(root)` to call this first and fall back to the existing raw file reading logic if the CLI is unavailable or fails. No other files need to change — the resolved JSON is just a string that replaces the raw config string passed to the prompt builder.

**Tech Stack:** Lua 5.1/LuaJIT, Neovim `vim.fn.system`, plenary.nvim (test runner)

---

### Task 1: Write failing tests for `resolve_via_cli` behavior

**Files:**
- Modify: `tests/husky_spec.lua`

**Step 1: Add tests for CLI resolution**

Add the following `describe` block inside the existing `describe("aicommits.husky"` block in `tests/husky_spec.lua`, after the existing `get_commitlint_rules` tests:

```lua
describe("get_commitlint_rules() with CLI resolution", function()
  it("returns resolved JSON when node_modules/.bin/commitlint exists and succeeds", function()
    mkdir(tmp_root .. "/.husky")

    -- Create a fake commitlint binary that prints resolved config JSON
    local bin_dir = tmp_root .. "/node_modules/.bin"
    mkdir(bin_dir)
    local fake_bin = bin_dir .. "/commitlint"
    write_file(fake_bin, '#!/bin/sh\necho \'{"rules":{"subject-case":[2,"never",["sentence-case"]],"type-enum":[2,"always",["feat","fix","chore"]]},"extends":["@commitlint/config-conventional"]}\'')
    os.execute("chmod +x " .. fake_bin)

    local rules = husky.get_commitlint_rules(tmp_root)
    assert.is_string(rules)
    assert.matches("subject%-case", rules)
    assert.matches("sentence%-case", rules)
    assert.matches("type%-enum", rules)
  end)

  it("falls back to raw config file when node_modules/.bin/commitlint does not exist", function()
    mkdir(tmp_root .. "/.husky")
    write_file(tmp_root .. "/commitlint.config.js",
      "module.exports = { extends: ['@commitlint/config-conventional'] }")
    -- No node_modules/.bin/commitlint created

    local rules = husky.get_commitlint_rules(tmp_root)
    assert.is_string(rules)
    assert.matches("config%-conventional", rules)
  end)

  it("falls back to raw config file when CLI exits with error", function()
    mkdir(tmp_root .. "/.husky")
    write_file(tmp_root .. "/commitlint.config.js",
      "module.exports = { extends: ['@commitlint/config-conventional'] }")

    -- Create a fake commitlint binary that fails
    local bin_dir = tmp_root .. "/node_modules/.bin"
    mkdir(bin_dir)
    local fake_bin = bin_dir .. "/commitlint"
    write_file(fake_bin, "#!/bin/sh\nexit 1")
    os.execute("chmod +x " .. fake_bin)

    local rules = husky.get_commitlint_rules(tmp_root)
    assert.is_string(rules)
    assert.matches("config%-conventional", rules)
  end)

  it("returns nil when CLI fails and no config file exists", function()
    mkdir(tmp_root .. "/.husky")

    -- Create a fake commitlint binary that fails
    local bin_dir = tmp_root .. "/node_modules/.bin"
    mkdir(bin_dir)
    local fake_bin = bin_dir .. "/commitlint"
    write_file(fake_bin, "#!/bin/sh\nexit 1")
    os.execute("chmod +x " .. fake_bin)

    local rules = husky.get_commitlint_rules(tmp_root)
    assert.is_nil(rules)
  end)
end)
```

**Step 2: Run tests to verify they fail**

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/husky_spec.lua" 2>&1 | tail -15
```

Expected: 3-4 failures. The first test should fail because `get_commitlint_rules` currently reads the raw file rather than running the CLI.

---

### Task 2: Implement `resolve_via_cli` in `husky.lua`

**Files:**
- Modify: `lua/aicommits/husky.lua`

**Step 1: Add `resolve_via_cli` before `get_commitlint_rules`**

Insert this function in `lua/aicommits/husky.lua` between `read_file` and `M.get_commitlint_rules`:

```lua
-- Try to get fully resolved commitlint config by running the CLI.
-- Returns the JSON output string, or nil if unavailable or failed.
-- @param root string Path to the project root directory
-- @return string|nil JSON config output, or nil
local function resolve_via_cli(root)
  local bin = root .. "/node_modules/.bin/commitlint"
  if vim.fn.filereadable(bin) == 0 then
    return nil
  end

  local cmd = string.format(
    "(cd %s && ./node_modules/.bin/commitlint --print-config 2>/dev/null)",
    vim.fn.shellescape(root)
  )
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 or vim.trim(output) == "" then
    return nil
  end

  return vim.trim(output)
end
```

**Step 2: Update `get_commitlint_rules` to call CLI first**

Replace the section in `M.get_commitlint_rules` that checks dedicated config files with:

```lua
function M.get_commitlint_rules(root)
  -- Require .husky directory to be present
  if vim.fn.isdirectory(root .. "/.husky") == 0 then
    return nil
  end

  -- Try to get fully resolved config via CLI (resolves extended presets)
  local resolved = resolve_via_cli(root)
  if resolved then
    return resolved
  end

  -- Fall back: check dedicated commitlint config files in priority order
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
```

**Step 3: Run the new tests to verify they pass**

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/husky_spec.lua" 2>&1 | tail -15
```

Expected: All tests pass, 0 failures.

**Step 4: Run the full test suite to verify nothing regressed**

```bash
./app.sh test 2>&1 | tail -5
```

Expected: `✓ All tests passed!`

**Step 5: Commit**

```bash
git add lua/aicommits/husky.lua tests/husky_spec.lua
git commit -m "feat(husky): resolve commitlint config via CLI for accurate rule injection"
```

---

## Verification

After both tasks, manually verify in the target project:

```vim
:lua print(require("aicommits.husky").get_commitlint_rules(require("aicommits.husky").get_git_root()))
```

Expected: Full JSON with explicit rules (e.g. `subject-case`, `type-enum`) rather than just `extends: [...]`.

Then generate a commit — the AI should no longer suggest sentence-case subjects.
