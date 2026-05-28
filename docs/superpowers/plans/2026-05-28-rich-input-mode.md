# Rich Input Mode Implementation Plan

**Goal:** Introduce an optional summarization pipeline that processes large staged diffs in pieces and composes a structured prompt for the final commit-message call, keeping the fast path intact for small/medium commits.

**Architecture:** A new `input/` module family dispatches between `default.lua` (passthrough) and `rich.lua` (summarization pipeline). `rich.lua` buckets per-file diffs into large/small-inline/small-batched categories, fans out parallel `provider:summarize()` calls bounded by a semaphore, then assembles a structured `final_payload` string for `provider:generate_commit_message`. `commit.lua` gains a single call to `input.prepare()` that wraps the existing `generate_commit_message` call.

**Tech Stack:** Lua 5.1 (LuaJIT / Neovim runtime), busted test framework, existing `http.lua` + `vim.fn.system` patterns.

---

## Overview

The feature is decomposed into eleven sequentially ordered tasks; Tasks 6–8 form a dependent chain on `rich.lua` and must be completed in order. [inferred] Each earlier task produces a stable module or method that later tasks depend on. All new files live under `lua/aicommits/` or `tests/`; no existing file other than those listed is touched.

The TDD rhythm for every task is: write a failing busted spec → confirm `FAIL` → write the minimal production code → confirm `PASS` → commit. All test commands assume busted is on `$PATH` and the repo root is the working directory; adjust the invocation to match the project's `Makefile` or `busted --config-file` as needed.

---

## Task 1: config.lua — add large_diff defaults and validation

**Goal:** Extend `M.defaults` in `config.lua` with the `large_diff` block and extend `M.validate()` to reject unknown `mode` values.

**Files touched:**
- Modify: `lua/aicommits/config.lua`
- Test: `tests/config_spec.lua`

**Steps:**
- [ ] Step 1 (failing test) — Add these cases to `tests/config_spec.lua` inside the existing `describe("aicommits.config", ...)` block:

```lua
describe("large_diff defaults", function()
  it("provides default large_diff block", function()
    config.setup({})
    local ld = config.get("large_diff")
    assert.is_table(ld)
    assert.equals("auto",  ld.mode)
    assert.equals(12000,   ld.threshold_chars)
    assert.equals(6000,    ld.chunk_chars)
    assert.equals(6,       ld.max_chunks_per_file)
    assert.equals(800,     ld.small_file_chars)
    assert.equals(10,      ld.max_small_files_inline)
    assert.equals(4000,    ld.small_file_batch_chars)
    assert.is_nil(ld.summary_model)
    assert.equals(220,     ld.summary_max_tokens)
    assert.equals(0.2,     ld.summary_temperature)
    assert.equals(4,       ld.concurrency)
  end)

  it("allows user to override individual large_diff fields", function()
    config.setup({ large_diff = { mode = "always", concurrency = 2 } })
    assert.equals("always", config.get("large_diff.mode"))
    assert.equals(2,        config.get("large_diff.concurrency"))
    -- Other defaults survive deep merge
    assert.equals(12000,    config.get("large_diff.threshold_chars"))
  end)
end)

describe("validate() large_diff.mode", function()
  it("accepts mode = 'off'", function()
    config.setup({ large_diff = { mode = "off" } })
    local ok, _ = config.validate()
    assert.is_true(ok)
  end)

  it("rejects unknown mode", function()
    config.setup({ large_diff = { mode = "banana" } })
    local ok, errors = config.validate()
    assert.is_false(ok)
    assert.is_true(#errors > 0)
    assert.is_truthy(errors[1]:match("large_diff.mode"))
  end)
end)
```

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/config_spec.lua
```

Expected failure: `large_diff` key is nil; `validate()` does not check `large_diff.mode`.

- [ ] Step 3 (minimal implementation) — In `lua/aicommits/config.lua`, add the `large_diff` block to `M.defaults` (after the `integrations` block) and add a validation clause in `M.validate()`:

```lua
-- In M.defaults, add after integrations:
large_diff = {
  mode                 = "auto",
  threshold_chars      = 12000,
  chunk_chars          = 6000,
  max_chunks_per_file  = 6,
  small_file_chars     = 800,
  max_small_files_inline = 10,
  small_file_batch_chars = 4000,
  summary_model        = nil,
  summary_max_tokens   = 220,
  summary_temperature  = 0.2,
  concurrency          = 4,
},
```

```lua
-- In M.validate(), add after the provider checks:
if config.large_diff then
  local valid_modes = { off = true, auto = true, always = true }
  local mode = config.large_diff.mode
  if mode and not valid_modes[mode] then
    table.insert(errors, string.format(
      "large_diff.mode must be 'off', 'auto', or 'always'; got '%s'", mode))
  end
end
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/config_spec.lua
```

Expected: all tests pass.

- [ ] Step 5 (commit):

```
git add lua/aicommits/config.lua tests/config_spec.lua
git commit -m "feat(config): add large_diff defaults and mode validation"
```

**Verification:**

```
busted tests/config_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: line containing `OK` with zero failures.

---

## Task 2: git.lua — add get_staged_stat()

**Goal:** Add a `get_staged_stat(callback)` function to `git.lua` that returns the output of `git diff --cached --stat` via callback, following the same sync-in-callback pattern as `get_staged_diff`.

**Files touched:**
- Modify: `lua/aicommits/git.lua`
- Test: `tests/git_spec.lua`

**Steps:**
- [ ] Step 1 (failing test) — Add to `tests/git_spec.lua`:

```lua
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
end)
```

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/git_spec.lua
```

Expected failure: `get_staged_stat` is nil.

- [ ] Step 3 (minimal implementation) — Add to `lua/aicommits/git.lua` before `return M`:

```lua
-- Get git diff --cached --stat output
-- @param callback function(error, stat_string)
function M.get_staged_stat(callback)
  local output = vim.fn.system({ "git", "diff", "--cached", "--stat" })
  if vim.v.shell_error ~= 0 then
    callback("Failed to get staged stat", nil)
    return
  end
  callback(nil, output)
end
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/git_spec.lua
```

Expected: all tests pass.

- [ ] Step 5 (commit):

```
git add lua/aicommits/git.lua tests/git_spec.lua
git commit -m "feat(git): add get_staged_stat helper"
```

**Verification:**

```
busted tests/git_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: line containing `OK` with zero failures.

---

## Task 3: prompts.lua — add build_summary_prompt()

**Goal:** Add `build_summary_prompt(kind, payload, opts)` to `prompts.lua` that returns `{ system, user }` for the three summary prompt kinds: `"chunk"`, `"file_rollup"`, `"small_batch"`.

**Files touched:**
- Modify: `lua/aicommits/prompts.lua`
- Test: `tests/prompts_spec.lua`

**Steps:**
- [ ] Step 1 (failing test) — Add to `tests/prompts_spec.lua`:

```lua
describe("build_summary_prompt()", function()
  local prompts = require("aicommits.prompts")

  it("returns system and user strings for 'chunk' kind", function()
    local result = prompts.build_summary_prompt("chunk", "- foo()\n+ bar()", { file_path = "src/mod.lua" })
    assert.is_table(result)
    assert.is_string(result.system)
    assert.is_string(result.user)
    assert.is_truthy(result.system:match("summarizer"))
    assert.is_truthy(result.user:match("src/mod.lua"))
    assert.is_truthy(result.user:match("foo"))
  end)

  it("returns system and user strings for 'file_rollup' kind", function()
    local result = prompts.build_summary_prompt("file_rollup", "- added x\n- removed y", { file_path = "a.lua" })
    assert.is_table(result)
    assert.is_truthy(result.system:match("paragraph"))
    assert.is_truthy(result.user:match("a.lua"))
    assert.is_truthy(result.user:match("Chunk summaries"))
  end)

  it("returns system and user strings for 'small_batch' kind", function()
    local payload = "file1.lua\n---\n+x\n---\nfile2.lua\n---\n+y"
    local result = prompts.build_summary_prompt("small_batch", payload, {})
    assert.is_table(result)
    assert.is_truthy(result.system:match("bullet per file"))
    assert.is_truthy(result.user:match("file1.lua"))
  end)

  it("errors on unknown kind", function()
    assert.has_error(function()
      prompts.build_summary_prompt("unknown", "", {})
    end)
  end)
end)
```

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/prompts_spec.lua
```

Expected failure: `build_summary_prompt` is nil.

- [ ] Step 3 (minimal implementation) — Add to `lua/aicommits/prompts.lua` before `return M`:

```lua
-- Build a prompt pair for summarization calls
-- @param kind  string  "chunk" | "file_rollup" | "small_batch"
-- @param payload string  The diff text or batch of chunk summaries
-- @param opts  table   { file_path = string|nil }
-- @return table { system = string, user = string }
function M.build_summary_prompt(kind, payload, opts)
  opts = opts or {}
  if kind == "chunk" then
    return {
      system = "You are a code-change summarizer. Produce a concise bullet-point summary"
        .. " (<=5 bullets, no markdown headers) of what this diff chunk changes."
        .. " Be specific: name functions, variables, or config keys that are added,"
        .. " removed, or modified.",
      user = string.format("File: %s\n\n%s", opts.file_path or "(unknown)", payload),
    }
  elseif kind == "file_rollup" then
    return {
      system = "You are a code-change summarizer. Given the following chunk summaries"
        .. " for a single file, produce a single concise paragraph (<=4 sentences)"
        .. " describing the net effect of the changes.",
      user = string.format(
        "File: %s\n\nChunk summaries:\n%s", opts.file_path or "(unknown)", payload),
    }
  elseif kind == "small_batch" then
    return {
      system = "You are a code-change summarizer. Given the following diffs for multiple"
        .. " small files, produce one concise bullet per file"
        .. " (format: '- <path>: <change summary>') describing the net change."
        .. " Do not merge bullets across files.",
      user = payload,
    }
  else
    error(string.format("build_summary_prompt: unknown kind '%s'", tostring(kind)))
  end
end
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/prompts_spec.lua
```

Expected: all tests pass.

- [ ] Step 5 (commit):

```
git add lua/aicommits/prompts.lua tests/prompts_spec.lua
git commit -m "feat(prompts): add build_summary_prompt for chunk/file_rollup/small_batch"
```

**Verification:**

```
busted tests/prompts_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: line containing `OK` with zero failures.

---

## Task 4: provider:summarize() — implement on base, gemini-api, vertex, openai

**Goal:** Add a `summarize(text, opts, provider_config, callback)` method to `base.lua` (stub that errors), then implement it on the `gemini-api`, `vertex`, and `openai` providers.

**Files touched:**
- Modify: `lua/aicommits/providers/base.lua`
- Modify: `lua/aicommits/providers/gemini.lua`
- Modify: `lua/aicommits/providers/vertex.lua`
- Modify: `lua/aicommits/providers/openai.lua`
- Test: `tests/gemini_spec.lua`
- Test: `tests/vertex_spec.lua` [inferred]
- Test: `tests/openai_spec.lua` [inferred]

**Steps:**
- [ ] Step 1 (failing test) — Add to `tests/gemini_spec.lua` (adapt for the mock-http pattern already in the file):

```lua
describe("summarize()", function()
  it("calls callback with summary text", function()
    -- Stub http.post to return a canned response
    local http = require("aicommits.http")
    local orig_post = http.post
    http.post = function(_url, _headers, _body, cb)
      cb(nil, vim.json.encode({
        candidates = {
          {
            content = {
              parts = { { text = "- added helper function foo()" } },
            },
          },
        },
      }))
    end

    local provider = require("aicommits.providers.gemini")
    local err, summary
    provider:summarize(
      "diff text",
      { prompt_kind = "chunk", file_path = "a.lua", max_tokens = 220, temperature = 0.2 },
      { api_key = "test-key", model = "gemini-2.5-flash" },
      function(e, s) err = e; summary = s end
    )

    assert.is_nil(err)
    assert.is_string(summary)
    assert.is_truthy(summary:match("foo"))

    http.post = orig_post
  end)

  it("calls callback with error when API returns error", function()
    local http = require("aicommits.http")
    local orig_post = http.post
    http.post = function(_url, _headers, _body, cb)
      cb("network error", nil)
    end

    local provider = require("aicommits.providers.gemini")
    local err
    provider:summarize(
      "diff text",
      { prompt_kind = "chunk", file_path = "a.lua", max_tokens = 220, temperature = 0.2 },
      { api_key = "test-key" },
      function(e, _) err = e end
    )

    assert.is_string(err)

    http.post = orig_post
  end)
end)
```

Also add to `tests/vertex_spec.lua` (inside the existing `describe` block, mirroring the gemini pattern): [inferred]

```lua
describe("summarize()", function()
  local orig_jobstart
  local orig_executable  -- [inferred]
  local M  -- module reference for cache resets [inferred]

  before_each(function()
    -- Re-require to get a fresh module reference for cache fields. [inferred]
    package.loaded["aicommits.providers.vertex"] = nil
    M = require("aicommits.providers.vertex")
    -- Reset token cache so each test starts without a cached token. [inferred]
    M._cached_token = nil
    M._token_expiry = 0
    orig_jobstart = vim.fn.jobstart
    -- Stub vim.fn.executable so generate_token's is_gcloud_available() check
    -- always passes regardless of whether gcloud is installed on the test machine,
    -- mirroring the pattern at tests/vertex_spec.lua lines 214-225. [inferred]
    orig_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "gcloud" then return 1 end
      return orig_executable(cmd)
    end
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.fn.executable = orig_executable  -- [inferred]
  end)

  it("calls callback with summary text on success", function()
    -- Stub http.post to return a canned Vertex response [inferred]
    local http = require("aicommits.http")
    local orig_post = http.post
    http.post = function(_url, _headers, _body, cb)
      cb(nil, vim.json.encode({
        candidates = {
          {
            content = {
              parts = { { text = "- refactored vertex helper" } },
            },
          },
        },
      }))
    end

    -- Stub vim.fn.jobstart to inject a fake token synchronously,
    -- mirroring the pattern at tests/vertex_spec.lua lines 262-277. [inferred]
    vim.fn.jobstart = function(cmd, opts)
      if opts.on_stdout then opts.on_stdout(0, { "fake.token.here" }, "stdout") end
      if opts.on_exit   then opts.on_exit(0, 0, "exit") end
      return 1
    end

    local err, summary
    M:summarize(
      "diff text",
      { prompt_kind = "chunk", file_path = "a.lua", max_tokens = 220, temperature = 0.2 },
      { project = "my-project", location = "us-central1", model = "gemini-2.0-flash-lite" },
      function(e, s) err = e; summary = s end
    )

    assert.is_nil(err)
    assert.is_string(summary)
    assert.is_truthy(summary:match("vertex helper"))

    http.post = orig_post
  end)

  it("calls callback with error when http.post returns error", function()
    local http = require("aicommits.http")
    local orig_post = http.post
    http.post = function(_url, _headers, _body, cb)
      cb("network error", nil)
    end

    -- Stub vim.fn.jobstart to inject a fake token synchronously. [inferred]
    vim.fn.jobstart = function(cmd, opts)
      if opts.on_stdout then opts.on_stdout(0, { "fake.token.here" }, "stdout") end
      if opts.on_exit   then opts.on_exit(0, 0, "exit") end
      return 1
    end

    local err
    M:summarize(
      "diff text",
      { prompt_kind = "chunk", file_path = "a.lua", max_tokens = 220, temperature = 0.2 },
      { project = "my-project", location = "us-central1" },
      function(e, _) err = e end
    )

    assert.is_string(err)

    http.post = orig_post
  end)
end)
```

Also add to `tests/openai_spec.lua` (inside the existing `describe` block, mirroring the gemini pattern): [inferred]

```lua
describe("summarize()", function()
  it("calls callback with summary text on success", function()
    -- Stub http.post to return a canned OpenAI chat-completions response [inferred]
    local http = require("aicommits.http")
    local orig_post = http.post
    http.post = function(_url, _headers, _body, cb)
      cb(nil, vim.json.encode({
        choices = {
          {
            message = { content = "- updated openai helper" },
          },
        },
      }))
    end

    local provider = require("aicommits.providers.openai")
    local err, summary
    provider:summarize(
      "diff text",
      { prompt_kind = "chunk", file_path = "a.lua", max_tokens = 220, temperature = 0.2 },
      { api_key = "test-key", model = "gpt-4.1-nano" },
      function(e, s) err = e; summary = s end
    )

    assert.is_nil(err)
    assert.is_string(summary)
    assert.is_truthy(summary:match("openai helper"))

    http.post = orig_post
  end)

  it("calls callback with error when http.post returns error", function()
    local http = require("aicommits.http")
    local orig_post = http.post
    http.post = function(_url, _headers, _body, cb)
      cb("network error", nil)
    end

    local err
    require("aicommits.providers.openai"):summarize(
      "diff text",
      { prompt_kind = "chunk", file_path = "a.lua", max_tokens = 220, temperature = 0.2 },
      { api_key = "test-key" },
      function(e, _) err = e end
    )

    assert.is_string(err)

    http.post = orig_post
  end)
end)
```

- [ ] Step 1b (run vertex and openai failing tests) — Run: [inferred]

```
busted tests/vertex_spec.lua
busted tests/openai_spec.lua
```

Expected failure: `summarize` is nil on each provider. [inferred]

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/gemini_spec.lua
```

Expected failure: `summarize` is nil on provider.

- [ ] Step 3 (minimal implementation):

In `lua/aicommits/providers/base.lua`, add inside `M.Provider`:

```lua
-- Summarize a piece of text (diff chunk, chunk summaries, or small-file batch)
-- @param text           string  The content to summarize
-- @param opts           table   { prompt_kind, file_path, model, max_tokens, temperature }
-- @param provider_config table  Same table as generate_commit_message receives
-- @param callback       function(error, summary_text)
summarize = function(self, text, opts, provider_config, callback)
  error(string.format("Provider '%s' must implement summarize", self.name or "unknown"))
end,
```

In `lua/aicommits/providers/gemini.lua`, add after `generate_commit_message`:

```lua
function M:summarize(text, opts, provider_config, callback)
  local api_key = get_api_key(provider_config)
  if not api_key then
    callback("Gemini API key not found for summarize call", nil)
    return
  end

  local model       = opts.model or provider_config.model or "gemini-2.5-flash"
  local max_tokens  = opts.max_tokens or 220
  local temperature = opts.temperature or 0.2

  local prompt = require("aicommits.prompts").build_summary_prompt(
    opts.prompt_kind, text, { file_path = opts.file_path })

  local endpoint = string.format(
    "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)

  local request_body = {
    contents = {
      { role = "user", parts = { { text = prompt.system .. "\n\n" .. prompt.user } } },
    },
    generationConfig = {
      temperature    = temperature,
      maxOutputTokens = max_tokens,
      candidateCount  = 1,
    },
  }

  http.post(endpoint, self:get_auth_headers(provider_config),
    vim.json.encode(request_body), function(err, response_body)
    if err then callback(err, nil); return end
    local ok, response = pcall(vim.json.decode, response_body)
    if not ok then
      callback("Failed to parse Gemini summarize response: " .. tostring(response), nil)
      return
    end
    if response.error then
      callback("Gemini API Error: " .. (response.error.message or vim.inspect(response.error)), nil)
      return
    end
    local text_out = (
      response.candidates
      and response.candidates[1]
      and response.candidates[1].content
      and response.candidates[1].content.parts
      and response.candidates[1].content.parts[1]
      and response.candidates[1].content.parts[1].text
    ) or ""
    if text_out == "" then
      callback("Gemini returned empty summary", nil)
      return
    end
    callback(nil, text_out)
  end)
end
```

In `lua/aicommits/providers/vertex.lua`, add after `generate_commit_message`. `generate_token` is defined as a module-scope local (line 24 of the existing file) and is visible to all functions in the same file, so no hoist is needed. [inferred]

```lua
function M:summarize(text, opts, provider_config, callback)
  generate_token(function(err, token)
    if err then callback(err, nil); return end

    local model       = opts.model or provider_config.model or "gemini-2.0-flash-lite"
    local project     = provider_config.project
    local location    = provider_config.location or "us-central1"
    local max_tokens  = opts.max_tokens or 220
    local temperature = opts.temperature or 0.2

    local prompt = require("aicommits.prompts").build_summary_prompt(
      opts.prompt_kind, text, { file_path = opts.file_path })

    local host = location == "global"
      and "aiplatform.googleapis.com"
      or  location .. "-aiplatform.googleapis.com"
    local endpoint = string.format(
      "https://%s/v1/projects/%s/locations/%s/publishers/google/models/%s:generateContent",
      host, project, location, model)

    local request_body = {
      contents = {
        { role = "user", parts = { { text = prompt.system .. "\n\n" .. prompt.user } } },
      },
      generationConfig = { temperature = temperature, maxOutputTokens = max_tokens, candidateCount = 1 },
    }

    local headers = { Authorization = "Bearer " .. token, ["Content-Type"] = "application/json" }

    http.post(endpoint, headers, vim.json.encode(request_body), function(http_err, response_body)
      if http_err then callback(http_err, nil); return end
      local ok, response = pcall(vim.json.decode, response_body)
      if not ok then
        callback("Failed to parse Vertex summarize response: " .. tostring(response), nil)
        return
      end
      if response.error then
        callback("Vertex AI Error: " .. (response.error.message or vim.inspect(response.error)), nil)
        return
      end
      local text_out = (
        response.candidates
        and response.candidates[1]
        and response.candidates[1].content
        and response.candidates[1].content.parts
        and response.candidates[1].content.parts[1]
        and response.candidates[1].content.parts[1].text
      ) or ""
      if text_out == "" then callback("Vertex returned empty summary", nil); return end
      callback(nil, text_out)
    end)
  end)
end
```

In `lua/aicommits/providers/openai.lua`, add after `generate_commit_message`:

```lua
function M:summarize(text, opts, provider_config, callback)
  local api_key = get_api_key(provider_config)
  if not api_key then
    callback("OpenAI API key not found for summarize call", nil)
    return
  end

  local model       = opts.model or provider_config.model or "gpt-4.1-nano"
  local max_tokens  = opts.max_tokens or 220
  local temperature = opts.temperature or 0.2
  local endpoint    = provider_config.endpoint or "https://api.openai.com/v1/chat/completions"

  local prompt = require("aicommits.prompts").build_summary_prompt(
    opts.prompt_kind, text, { file_path = opts.file_path })

  local request_body = {
    model    = model,
    messages = {
      { role = "system", content = prompt.system },
      { role = "user",   content = prompt.user },
    },
    max_tokens  = max_tokens,
    temperature = temperature,
    n           = 1,
  }

  http.post(endpoint, self:get_auth_headers(provider_config),
    vim.json.encode(request_body), function(err, response_body)
    if err then callback(err, nil); return end
    local ok, response = pcall(vim.json.decode, response_body)
    if not ok then
      callback("Failed to parse OpenAI summarize response: " .. tostring(response), nil)
      return
    end
    if response.error then
      callback("OpenAI Error: " .. (response.error.message or vim.inspect(response.error)), nil)
      return
    end
    local text_out = (
      response.choices
      and response.choices[1]
      and response.choices[1].message
      and response.choices[1].message.content
    ) or ""
    if text_out == "" then callback("OpenAI returned empty summary", nil); return end
    callback(nil, text_out)
  end)
end
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/gemini_spec.lua
busted tests/vertex_spec.lua
busted tests/openai_spec.lua
```

Expected: all tests pass across all three provider specs. [inferred]

- [ ] Step 5 (commit):

```
git add lua/aicommits/providers/base.lua lua/aicommits/providers/gemini.lua lua/aicommits/providers/vertex.lua lua/aicommits/providers/openai.lua tests/gemini_spec.lua tests/vertex_spec.lua tests/openai_spec.lua
git commit -m "feat(providers): add summarize() method to base, gemini-api, vertex, openai"
```

**Verification:**

```
busted tests/gemini_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
busted tests/vertex_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
busted tests/openai_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: each command produces a line containing `OK` with zero failures. [inferred]

---

## Task 5: input/default.lua — passthrough module

**Goal:** Create `lua/aicommits/input/default.lua` that exposes `prepare(diff_data, provider, provider_config, callback)` and calls `callback(nil, diff_data.diff)` immediately.

**Files touched:**
- Create: `lua/aicommits/input/default.lua`
- Test: `tests/input_default_spec.lua`

**Steps:**
- [ ] Step 1 (failing test) — Create `tests/input_default_spec.lua`:

```lua
describe("input.default", function()
  it("calls callback with raw diff string", function()
    local default = require("aicommits.input.default")
    local diff_data = { diff = "diff --git a/x.lua\n+hello", files = { "x.lua" } }

    local err, payload
    default.prepare(diff_data, {}, {}, function(e, p) err = e; payload = p end)

    assert.is_nil(err)
    assert.equals(diff_data.diff, payload)
  end)

  it("passes through even when diff is empty string", function()
    local default = require("aicommits.input.default")
    local err, payload
    default.prepare({ diff = "", files = {} }, {}, {}, function(e, p) err = e; payload = p end)
    assert.is_nil(err)
    assert.equals("", payload)
  end)
end)
```

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/input_default_spec.lua
```

Expected failure: module not found.

- [ ] Step 3 (minimal implementation) — Create `lua/aicommits/input/default.lua`:

```lua
-- Default (passthrough) input preparator
-- Returns the raw diff string unchanged.
local M = {}

-- Prepare final payload by returning the raw diff as-is.
-- @param diff_data      table   { diff = string, files = table }
-- @param provider       table   Provider instance (unused)
-- @param provider_config table  Provider config (unused)
-- @param callback       function(error, final_payload)
function M.prepare(diff_data, provider, provider_config, callback)
  callback(nil, diff_data.diff)
end

return M
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/input_default_spec.lua
```

Expected: all tests pass.

- [ ] Step 5 (commit):

```
git add lua/aicommits/input/default.lua tests/input_default_spec.lua
git commit -m "feat(input): add default passthrough preparator"
```

**Verification:**

```
busted tests/input_default_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: line containing `OK` with zero failures.

---

## Task 6: input/rich.lua — parsing helpers (diff splitting, chunking, bucketing)

**Goal:** Implement the pure (non-async) parsing helpers in `lua/aicommits/input/rich.lua`: `split_diff_by_file`, `split_into_chunks`, `bucket_files`. These are the deterministic core of the pipeline and can be fully unit-tested without a provider.

**Files touched:**
- Create: `lua/aicommits/input/rich.lua`
- Test: `tests/input_rich_spec.lua`

**Steps:**
- [ ] Step 1 (failing test) — Create `tests/input_rich_spec.lua` with the pure-function tests:

```lua
local rich

describe("input.rich — parsing helpers", function()
  before_each(function()
    rich = require("aicommits.input.rich")
  end)

  -- ── split_diff_by_file ───────────────────────────────────────────────
  describe("split_diff_by_file()", function()
    it("returns empty table for empty diff", function()
      local result = rich.split_diff_by_file("")
      assert.same({}, result)
    end)

    it("splits a two-file diff into two entries", function()
      local diff = table.concat({
        "diff --git a/foo.lua b/foo.lua",
        "--- a/foo.lua",
        "+++ b/foo.lua",
        "@@ -1,1 +1,2 @@",
        " line",
        "+added",
        "diff --git a/bar.lua b/bar.lua",
        "--- a/bar.lua",
        "+++ b/bar.lua",
        "@@ -1 +1 @@",
        "-removed",
      }, "\n")

      local result = rich.split_diff_by_file(diff)
      assert.equals(2, #result)
      assert.equals("foo.lua", result[1].path)
      assert.equals("bar.lua", result[2].path)
      assert.is_truthy(result[1].diff:match("added"))
      assert.is_truthy(result[2].diff:match("removed"))
    end)

    it("marks binary files with zero-hunk flag", function()
      local diff = table.concat({
        "diff --git a/img.png b/img.png",
        "Binary files a/img.png and b/img.png differ",
      }, "\n")
      local result = rich.split_diff_by_file(diff)
      assert.equals(1, #result)
      assert.is_true(result[1].is_binary)
    end)
  end)

  -- ── split_into_chunks ────────────────────────────────────────────────
  describe("split_into_chunks()", function()
    local function make_hunk(n_lines)
      local lines = { "@@ -1," .. n_lines .. " +1," .. n_lines .. " @@" }
      for i = 1, n_lines do lines[#lines + 1] = " line" .. i end
      return table.concat(lines, "\n")
    end

    it("packs multiple small hunks into one chunk when they fit", function()
      local file_diff = make_hunk(3) .. "\n" .. make_hunk(3)
      -- chunk_chars large enough to fit both
      local chunks = rich.split_into_chunks(file_diff, 10000)
      assert.equals(1, #chunks)
    end)

    it("splits into two chunks when combined size exceeds chunk_chars", function()
      -- Each hunk ~60 chars; chunk_chars=80 → each hunk gets its own chunk
      local file_diff = make_hunk(5) .. "\n" .. make_hunk(5)
      local chunks = rich.split_into_chunks(file_diff, 80)
      assert.equals(2, #chunks)
    end)

    it("puts an oversized single hunk into its own chunk", function()
      local big_hunk = make_hunk(200)  -- > any reasonable chunk_chars for this test
      local chunks = rich.split_into_chunks(big_hunk, 50)
      assert.equals(1, #chunks)
      assert.is_truthy(chunks[1]:match("@@ %-1,200"))
    end)
  end)

  -- ── bucket_files ─────────────────────────────────────────────────────
  describe("bucket_files()", function()
    local cfg = {
      small_file_chars      = 100,
      max_small_files_inline = 2,
    }

    it("classifies a large file as 'large'", function()
      local file_entries = {
        { path = "big.lua", diff = string.rep("x", 200), is_binary = false },
      }
      local buckets = rich.bucket_files(file_entries, cfg)
      assert.equals(1, #buckets.large)
      assert.equals(0, #buckets.small_inline)
      assert.equals(0, #buckets.small_batched)
    end)

    it("classifies small files as small_inline when count <= max_small_files_inline", function()
      local file_entries = {
        { path = "a.lua", diff = "x", is_binary = false },
        { path = "b.lua", diff = "y", is_binary = false },
      }
      local buckets = rich.bucket_files(file_entries, cfg)
      assert.equals(2, #buckets.small_inline)
      assert.equals(0, #buckets.small_batched)
    end)

    it("classifies small files as small_batched when count > max_small_files_inline", function()
      local file_entries = {
        { path = "a.lua", diff = "x", is_binary = false },
        { path = "b.lua", diff = "y", is_binary = false },
        { path = "c.lua", diff = "z", is_binary = false },
      }
      local buckets = rich.bucket_files(file_entries, cfg)
      assert.equals(0, #buckets.small_inline)
      assert.equals(3, #buckets.small_batched)
    end)

    it("puts binary files into stat_only bucket", function()
      local file_entries = {
        { path = "img.png", diff = "", is_binary = true },
      }
      local buckets = rich.bucket_files(file_entries, cfg)
      assert.equals(1, #buckets.stat_only)
    end)
  end)
end)
```

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/input_rich_spec.lua
```

Expected failure: module not found.

- [ ] Step 3 (minimal implementation) — Create `lua/aicommits/input/rich.lua` with the three helper functions (the `prepare` function is added in Task 7):

```lua
-- Rich input mode: summarization pipeline for large staged diffs.
local M = {}

-- Split a full git diff into per-file entries.
-- Each entry: { path = string, diff = string, is_binary = boolean }
-- @param diff string  Full output of git diff --cached
-- @return table  Array of { path, diff, is_binary }
function M.split_diff_by_file(diff)
  if not diff or diff == "" then return {} end

  local entries = {}
  local current_path = nil
  local current_lines = {}

  local function flush()
    if current_path then
      local file_diff = table.concat(current_lines, "\n")
      local is_binary = file_diff:match("Binary files") ~= nil  -- no ^ anchor: first line is 'diff --git' header [inferred]
      table.insert(entries, { path = current_path, diff = file_diff, is_binary = is_binary })
    end
  end

  for line in (diff .. "\n"):gmatch("([^\n]*)\n") do
    local path = line:match("^diff %-%-git a/.+ b/(.+)$")
    if path then
      flush()
      current_path = path
      current_lines = { line }
    elseif current_path then
      table.insert(current_lines, line)
    end
  end
  flush()

  return entries
end

-- Split a single file's diff text into hunk-boundary chunks.
-- Hunks are never split mid-hunk; an oversized single hunk becomes its own chunk.
-- @param file_diff  string  Diff text for one file
-- @param chunk_chars number Maximum characters per chunk
-- @return table  Array of chunk strings
function M.split_into_chunks(file_diff, chunk_chars)
  if not file_diff or file_diff == "" then return {} end

  -- Collect individual hunks (split on @@ lines)
  local hunks = {}
  local current_hunk_lines = {}

  for line in (file_diff .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^@@") and #current_hunk_lines > 0 then
      table.insert(hunks, table.concat(current_hunk_lines, "\n"))
      current_hunk_lines = { line }
    else
      table.insert(current_hunk_lines, line)
    end
  end
  if #current_hunk_lines > 0 then
    table.insert(hunks, table.concat(current_hunk_lines, "\n"))
  end

  -- Filter out leading non-hunk header lines into its own pseudo-entry or discard
  -- (they belong to no hunk; we keep them in the first chunk)
  local chunks = {}
  local current_chunk_parts = {}
  local current_chunk_len = 0

  for _, hunk in ipairs(hunks) do
    local hlen = #hunk
    if #current_chunk_parts == 0 then
      -- Always start a new chunk with the first hunk
      table.insert(current_chunk_parts, hunk)
      current_chunk_len = hlen
    elseif current_chunk_len + 1 + hlen <= chunk_chars then
      table.insert(current_chunk_parts, hunk)
      current_chunk_len = current_chunk_len + 1 + hlen
    else
      table.insert(chunks, table.concat(current_chunk_parts, "\n"))
      current_chunk_parts = { hunk }
      current_chunk_len = hlen
    end
  end

  if #current_chunk_parts > 0 then
    table.insert(chunks, table.concat(current_chunk_parts, "\n"))
  end

  return chunks
end

-- Classify per-file diff entries into buckets.
-- Returns { large = [], small_inline = [], small_batched = [], stat_only = [] }
-- @param file_entries table  Array of { path, diff, is_binary } from split_diff_by_file
-- @param cfg          table  large_diff config subset: { small_file_chars, max_small_files_inline }
-- @return table  Bucket table
function M.bucket_files(file_entries, cfg)
  local large        = {}
  local smalls       = {}
  local stat_only    = {}

  for _, entry in ipairs(file_entries) do
    if entry.is_binary or entry.diff == "" then
      table.insert(stat_only, entry)
    elseif #entry.diff > cfg.small_file_chars then
      table.insert(large, entry)
    else
      table.insert(smalls, entry)
    end
  end

  local small_inline   = {}
  local small_batched  = {}

  if #smalls <= cfg.max_small_files_inline then
    small_inline  = smalls
  else
    small_batched = smalls
  end

  return {
    large        = large,
    small_inline = small_inline,
    small_batched = small_batched,
    stat_only    = stat_only,
  }
end

return M
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/input_rich_spec.lua
```

Expected: all tests pass.

- [ ] Step 5 (commit):

```
git add lua/aicommits/input/rich.lua tests/input_rich_spec.lua
git commit -m "feat(input/rich): add split_diff_by_file, split_into_chunks, bucket_files"
```

**Verification:**

```
busted tests/input_rich_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: line containing `OK` with zero failures.

---

## Task 7: input/rich.lua — concurrency scheduler

**Goal:** Add a `make_scheduler(concurrency)` factory to `rich.lua` that returns a scheduler with a `run(fn)` method. The scheduler dispatches tasks via `vim.schedule`, enforcing the concurrency cap, and queues excess tasks. This is the engine that all summary calls in Task 8 flow through.

**Files touched:**
- Modify: `lua/aicommits/input/rich.lua`
- Test: `tests/input_rich_spec.lua`

**Steps:**
- [ ] Step 1 (failing test) — Add a new `describe` block inside `tests/input_rich_spec.lua`:

```lua
describe("make_scheduler()", function()
  local orig_vim_schedule

  before_each(function()
    -- vim.schedule is not available in busted; stub it to fire synchronously. [inferred]
    orig_vim_schedule = vim.schedule
    vim.schedule = function(fn) fn() end
  end)

  after_each(function()
    vim.schedule = orig_vim_schedule
  end)

  it("runs a single task and calls its done callback", function()
    local sched = rich.make_scheduler(2)
    local called = false
    sched.run(function(done)
      called = true
      done()
    end)
    assert.is_true(called)
  end)

  it("respects concurrency cap — max in-flight equals concurrency", function()
    local sched = rich.make_scheduler(2)
    local in_flight_peak = 0
    local in_flight = 0
    local done_fns = {}

    local function task(done)
      in_flight = in_flight + 1
      if in_flight > in_flight_peak then in_flight_peak = in_flight end
      table.insert(done_fns, function()
        in_flight = in_flight - 1
        done()
      end)
    end

    -- Enqueue 4 tasks; only 2 should start immediately
    for _ = 1, 4 do sched.run(task) end

    -- Complete all queued tasks
    while #done_fns > 0 do
      local fn = table.remove(done_fns, 1)
      fn()
    end

    assert.is_true(in_flight_peak <= 2)
  end)
end)
```

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/input_rich_spec.lua
```

Expected failure: `make_scheduler` is nil.

- [ ] Step 3 (minimal implementation) — Add to `lua/aicommits/input/rich.lua` before `return M`:

```lua
-- Create a concurrency-bounded scheduler.
-- Tasks are functions with signature: fn(done) where done() signals completion.
-- @param concurrency number  Maximum parallel tasks
-- @return table { run = function(fn) }
function M.make_scheduler(concurrency)
  local in_flight = 0
  local pending   = {}

  local function try_dispatch()
    while in_flight < concurrency and #pending > 0 do
      local fn = table.remove(pending, 1)
      in_flight = in_flight + 1
      vim.schedule(function()
        fn(function()
          in_flight = in_flight - 1
          try_dispatch()
        end)
      end)
    end
  end

  return {
    run = function(fn)
      table.insert(pending, fn)
      try_dispatch()
    end,
  }
end
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/input_rich_spec.lua
```

Expected: all tests pass including the new scheduler tests.

- [ ] Step 5 (commit):

```
git add lua/aicommits/input/rich.lua tests/input_rich_spec.lua
git commit -m "feat(input/rich): add concurrency-bounded scheduler"
```

**Verification:**

```
busted tests/input_rich_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: line containing `OK` with zero failures.

---

## Task 8: input/rich.lua — full prepare() pipeline

**Goal:** Add the `prepare(diff_data, provider, provider_config, callback)` function to `rich.lua` that orchestrates: staged-stat fetch, bucketing, parallel summarization, error/fallback handling, and final prompt assembly.

**Files touched:**
- Modify: `lua/aicommits/input/rich.lua`
- Test: `tests/input_rich_spec.lua`

**Steps:**
- [ ] Step 1 (failing test) — Add integration tests to `tests/input_rich_spec.lua`. These tests use a mock provider and a stubbed `git.get_staged_stat`:

```lua
describe("prepare() integration", function()
  local orig_picker_show, orig_picker_close

  before_each(function()
    -- rich.lua calls picker.show_status; stub it to prevent UI errors in tests. [inferred]
    local picker = require("aicommits.ui.picker")
    orig_picker_show  = picker.show_status
    orig_picker_close = picker.close_status
    picker.show_status  = function() end
    picker.close_status = function() end
  end)

  after_each(function()
    local picker = require("aicommits.ui.picker")
    picker.show_status  = orig_picker_show
    picker.close_status = orig_picker_close
  end)

  local function make_mock_provider(summary_result)
    -- summary_result: string (success) or error string prefixed with "ERR:"
    return {
      summarize = function(self, text, opts, provider_config, callback)
        if summary_result:sub(1, 4) == "ERR:" then
          callback(summary_result:sub(5), nil)
        else
          callback(nil, summary_result)
        end
      end,
    }
  end

  local function stub_stat(stat_text)
    local git = require("aicommits.git")
    local orig = git.get_staged_stat
    git.get_staged_stat = function(cb) cb(nil, stat_text) end
    return function() git.get_staged_stat = orig end
  end

  it("returns assembled payload for a single large file", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local provider = make_mock_provider("- changed foo()")

    local big_diff = table.concat({
      "diff --git a/big.lua b/big.lua",
      "@@ -1,5 +1,6 @@",
      " line1",
      "+line2",
    }, "\n") .. string.rep("\nmore content", 30)  -- push over small_file_chars

    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local cfg_override = {
      mode = "always",
      threshold_chars = 0,
      chunk_chars = 6000,
      max_chunks_per_file = 6,
      small_file_chars = 50,  -- small threshold so big_diff is classified as large
      max_small_files_inline = 10,
      small_file_batch_chars = 4000,
      summary_model = nil,
      summary_max_tokens = 220,
      summary_temperature = 0.2,
      concurrency = 4,
    }

    local config = require("aicommits.config")
    config.setup({ large_diff = cfg_override })

    local err, payload
    require("aicommits.input.rich").prepare(
      diff_data, provider, {}, function(e, p) err = e; payload = p end)

    restore()

    assert.is_nil(err)
    assert.is_string(payload)
    assert.is_truthy(payload:match("big%.lua"))
    assert.is_truthy(payload:match("changed foo"))
  end)

  it("falls back to stat-only when all summaries fail", function()
    local restore = stub_stat(" big.lua | 5 +++\n")
    local provider = make_mock_provider("ERR:api down")

    local big_diff = table.concat({
      "diff --git a/big.lua b/big.lua",
      "@@ -1,3 +1,4 @@",
      " a",
      "+b",
    }, "\n") .. string.rep("\nx", 60)

    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local config = require("aicommits.config")
    config.setup({ large_diff = {
      mode = "always", small_file_chars = 50,
      chunk_chars = 6000, max_chunks_per_file = 6,
      max_small_files_inline = 10, small_file_batch_chars = 4000,
      summary_max_tokens = 220, summary_temperature = 0.2, concurrency = 4,
    }})

    local err, _payload
    require("aicommits.input.rich").prepare(
      diff_data, provider, {}, function(e, p) err = e; _payload = p end)

    restore()

    -- All summaries failed → error surfaced
    assert.is_string(err)
  end)

  it("small-batched path produces a payload containing batch summary", function()
    local restore = stub_stat(" a.lua | 1\n b.lua | 1\n c.lua | 1\n")
    local provider = make_mock_provider("- a: changed\n- b: changed\n- c: changed")

    local mk = function(name)
      return "diff --git a/" .. name .. " b/" .. name
        .. "\n@@ -1 +1 @@\n-old\n+new"
    end
    local diff = mk("a.lua") .. "\n" .. mk("b.lua") .. "\n" .. mk("c.lua")
    local diff_data = { diff = diff, files = { "a.lua", "b.lua", "c.lua" } }

    local config = require("aicommits.config")
    config.setup({ large_diff = {
      mode = "always",
      small_file_chars = 10000,  -- all files are "small"
      max_small_files_inline = 2,  -- 3 > 2 → small_batched
      small_file_batch_chars = 4000,
      chunk_chars = 6000, max_chunks_per_file = 6,
      summary_max_tokens = 220, summary_temperature = 0.2, concurrency = 4,
    }})

    local err, payload
    require("aicommits.input.rich").prepare(
      diff_data, provider, {}, function(e, p) err = e; payload = p end)

    restore()

    assert.is_nil(err)
    assert.is_string(payload)
    assert.is_truthy(payload:match("changed"))
  end)
end)
```

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/input_rich_spec.lua
```

Expected failure: `prepare` is nil on the rich module.

- [ ] Step 3 (minimal implementation) — Add `prepare` to `lua/aicommits/input/rich.lua` before `return M`. The function uses all helpers defined in Tasks 6 and 7:

```lua
-- Pack small files into batches respecting small_file_batch_chars budget.
-- @param entries table  Array of file entries (small_batched bucket)
-- @param batch_chars number
-- @return table  Array of batch arrays
local function pack_small_batches(entries, batch_chars)
  local batches = {}
  local current_batch = {}
  local current_len = 0

  for _, entry in ipairs(entries) do
    local len = #entry.diff
    if #current_batch > 0 and current_len + len > batch_chars then
      table.insert(batches, current_batch)
      current_batch = { entry }
      current_len = len
    else
      table.insert(current_batch, entry)
      current_len = current_len + len
    end
  end

  if #current_batch > 0 then
    table.insert(batches, current_batch)
  end

  return batches
end

-- Assemble the final prompt string from all pipeline results.
-- @param stat_string   string
-- @param large_results  table  Array of { path, summary or stat_line, is_stat }
-- @param inline_entries table  Array of { path, diff }
-- @param batch_results  table  Array of { paths, summary or nil, is_stat }
-- @return string
local function assemble_prompt(stat_string, large_results, inline_entries, batch_results)
  local parts = {}

  table.insert(parts, "## Staged Changes Overview\n\n" .. stat_string)

  -- Large file sections
  for _, r in ipairs(large_results) do
    if r.is_stat then
      table.insert(parts, string.format("### %s\n%s", r.path, r.stat_line))
    else
      table.insert(parts, string.format("### %s\n%s", r.path, r.summary))
    end
  end

  -- Small-inline sections
  for _, entry in ipairs(inline_entries) do
    table.insert(parts, string.format("### %s\n```diff\n%s\n```", entry.path, entry.diff))
  end

  -- Batch summary sections
  for i, br in ipairs(batch_results) do
    local paths_str = table.concat(br.paths, ", ")
    if br.is_stat then
      table.insert(parts, string.format(
        "### Batch %d (%s)\n(summary unavailable — stat only)", i, paths_str))
    else
      table.insert(parts, string.format(
        "### Batch %d (%s)\n%s", i, paths_str, br.summary))
    end
  end

  return table.concat(parts, "\n\n")
end

-- Prepare the final commit-message payload via the summarization pipeline.
-- @param diff_data      table   { diff = string, files = table }
-- @param provider       table   Provider instance (must implement :summarize())
-- @param provider_config table  Passed as-is to provider:summarize()
-- @param callback       function(error, final_payload)
function M.prepare(diff_data, provider, provider_config, callback)
  local config    = require("aicommits.config")
  local git       = require("aicommits.git")
  local picker    = require("aicommits.ui.picker")
  local ld_cfg    = config.get("large_diff")

  picker.show_status("Analyzing staged diff...")

  -- 1. Fetch stat
  git.get_staged_stat(function(stat_err, stat_string)
    if stat_err then
      callback("Failed to get staged stat: " .. stat_err, nil)
      return
    end

    -- 2. Split and bucket
    local file_entries = M.split_diff_by_file(diff_data.diff)
    local buckets      = M.bucket_files(file_entries, ld_cfg)

    local sched = M.make_scheduler(ld_cfg.concurrency)
    -- A separate uncapped scheduler (concurrency = math.huge) is used for per-chunk calls
    -- within a large-file task so that inner chunk tasks never block waiting for outer task
    -- slots — which would deadlock when ld_cfg.concurrency is 1. [inferred]
    local chunk_sched = M.make_scheduler(math.huge)

    -- Track results
    local large_results = {}    -- { path, summary?, stat_line?, is_stat }
    local batch_results = {}    -- { paths, summary?, is_stat }

    local summary_attempts  = 0
    local summary_successes = 0

    -- Pre-populate large_results order
    for _, entry in ipairs(buckets.large) do
      table.insert(large_results, { path = entry.path, is_stat = true,
        stat_line = entry.path .. " (summary pending)" })
    end

    -- Pre-populate batch_results
    local batches = pack_small_batches(buckets.small_batched, ld_cfg.small_file_batch_chars)
    for _, batch in ipairs(batches) do
      local paths = {}
      for _, e in ipairs(batch) do table.insert(paths, e.path) end
      table.insert(batch_results, { paths = paths, is_stat = true })
    end

    local total_tasks = 0
    local done_tasks  = 0

    local function check_done()
      if done_tasks == total_tasks then
        -- Partial-failure semantics: if ≥1 summary succeeded, assemble a mixed payload
        -- where failed files appear as stat-only entries (already set on each failure path).
        -- Only abort when zero summaries succeeded out of those attempted. [inferred]
        if summary_attempts > 0 and summary_successes == 0 then
          picker.close_status()  -- [inferred] close status before surfacing the all-failed error
          callback("All summary calls failed (0/" .. summary_attempts .. " succeeded); aborting rich input pipeline.", nil)
          return
        end

        local payload = assemble_prompt(
          stat_string, large_results, buckets.small_inline, batch_results)
        picker.close_status()  -- [inferred] close status before handing off to generate_commit_message
        callback(nil, payload)
      end
    end

    -- Count total async tasks: one per large file (chunks + rollup counted as one task group),
    -- one per batch.
    total_tasks = #buckets.large + #batches
    if total_tasks == 0 then
      -- Only small-inline files — assemble immediately
      local payload = assemble_prompt(stat_string, {}, buckets.small_inline, {})
      picker.close_status()  -- [inferred] close status opened above before handing off
      callback(nil, payload)
      return
    end

    picker.show_status(string.format(
      "Summarizing %d files in parallel...", #buckets.large + #batches))

    -- ── Large file tasks ─────────────────────────────────────────────
    for idx, entry in ipairs(buckets.large) do
      local entry_idx = idx
      local local_entry = entry

      sched.run(function(task_done)
        -- Guard against double-completion from nested chunk/rollup paths. [inferred]
        local task_completed = false
        local function complete_task()
          if task_completed then return end
          task_completed = true
          done_tasks = done_tasks + 1
          task_done()
          check_done()
        end

        local chunks = M.split_into_chunks(local_entry.diff, ld_cfg.chunk_chars)

        -- Overflow check: when a file exceeds max_chunks_per_file it is demoted to
        -- stat-only and complete_task() is called immediately WITHOUT incrementing
        -- summary_attempts, so overflow files never count toward the all-failed
        -- threshold in check_done(). [inferred]
        if #chunks > ld_cfg.max_chunks_per_file then
          large_results[entry_idx] = {
            path = local_entry.path, is_stat = true,
            stat_line = local_entry.path
              .. " (diff omitted: exceeded max_chunks_per_file)",
          }
          complete_task()
          return
        end

        summary_attempts = summary_attempts + 1

        -- Per-chunk summaries
        local chunk_summaries = {}
        local chunk_err_flag  = false
        local chunks_done = 0

        if #chunks == 0 then
          -- No hunks — stat only
          large_results[entry_idx] = {
            path = local_entry.path, is_stat = true,
            stat_line = local_entry.path .. " (no hunks)",
          }
          complete_task()
          return
        end

        for c_idx, chunk in ipairs(chunks) do
          local c_idx_local = c_idx
          chunk_sched.run(function(chunk_done)  -- uses inner uncapped scheduler to avoid deadlock [inferred]
            if chunk_err_flag then chunk_done(); return end
            provider:summarize(chunk,
              { prompt_kind = "chunk", file_path = local_entry.path,
                model = ld_cfg.summary_model,
                max_tokens = ld_cfg.summary_max_tokens,
                temperature = ld_cfg.summary_temperature },
              provider_config,
              function(err, summary_text)
                if err then
                  chunk_err_flag = true
                end
                chunk_summaries[c_idx_local] = summary_text or ""
                chunks_done = chunks_done + 1
                chunk_done()

                if chunks_done == #chunks then
                  if chunk_err_flag then
                    large_results[entry_idx] = {
                      path = local_entry.path, is_stat = true,
                      stat_line = local_entry.path .. " (summary failed)",
                    }
                    complete_task()
                    return
                  end

                  -- Roll-up
                  picker.show_status("Composing file summaries...")
                  summary_attempts = summary_attempts + 1
                  local combined = table.concat(chunk_summaries, "\n")
                  provider:summarize(combined,
                    { prompt_kind = "file_rollup", file_path = local_entry.path,
                      model = ld_cfg.summary_model,
                      max_tokens = ld_cfg.summary_max_tokens,
                      temperature = ld_cfg.summary_temperature },
                    provider_config,
                    function(rollup_err, rollup_text)
                      if rollup_err then
                        large_results[entry_idx] = {
                          path = local_entry.path, is_stat = true,
                          stat_line = local_entry.path .. " (rollup failed)",
                        }
                      else
                        summary_successes = summary_successes + 1
                        large_results[entry_idx] = {
                          path = local_entry.path, is_stat = false,
                          summary = rollup_text,
                        }
                      end
                      complete_task()
                    end)
                end
              end)
          end)
        end
      end)
    end

    -- ── Small-batch tasks ─────────────────────────────────────────────
    for b_idx, batch in ipairs(batches) do
      local b_idx_local = b_idx
      local local_batch = batch

      sched.run(function(task_done)
        -- Build payload
        local parts = {}
        for _, e in ipairs(local_batch) do
          table.insert(parts, e.path .. "\n" .. e.diff)
        end
        local batch_payload = table.concat(parts, "\n---\n")

        summary_attempts = summary_attempts + 1
        provider:summarize(batch_payload,
          { prompt_kind = "small_batch",
            model = ld_cfg.summary_model,
            max_tokens = ld_cfg.summary_max_tokens,
            temperature = ld_cfg.summary_temperature },
          provider_config,
          function(err, summary_text)
            if err then
              batch_results[b_idx_local].is_stat = true
            else
              summary_successes = summary_successes + 1
              batch_results[b_idx_local].is_stat = false
              batch_results[b_idx_local].summary = summary_text
            end
            done_tasks = done_tasks + 1
            task_done()
            check_done()
          end)
      end)
    end
  end)
end
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/input_rich_spec.lua
```

Expected: all tests pass.

- [ ] Step 5 (commit):

```
git add lua/aicommits/input/rich.lua tests/input_rich_spec.lua
git commit -m "feat(input/rich): add full prepare() summarization pipeline"
```

**Verification:**

```
busted tests/input_rich_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: line containing `OK` with zero failures.

---

## Task 9: input/init.lua — dispatcher

**Goal:** Create `lua/aicommits/input/init.lua` that reads `large_diff` config, decides whether to use `default.lua` or `rich.lua`, and exposes a single `prepare(diff_data, provider, provider_config, callback)` function.

**Files touched:**
- Create: `lua/aicommits/input/init.lua`
- Test: `tests/input_init_spec.lua`

**Steps:**
- [ ] Step 1 (failing test) — Create `tests/input_init_spec.lua`:

```lua
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
    input.prepare({ diff = string.rep("x", 50), files = {} }, {}, {}, function() end)

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
    input.prepare({ diff = "x", files = {} }, {}, {}, function() end)

    assert.is_true(called_rich)
    package.preload["aicommits.input.default"] = nil
    package.preload["aicommits.input.rich"] = nil
  end)
end)
```

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/input_init_spec.lua
```

Expected failure: module not found.

- [ ] Step 3 (minimal implementation) — Create `lua/aicommits/input/init.lua`:

```lua
-- Input dispatcher: routes diff preparation to default or rich pipeline.
local M = {}

-- Prepare the final commit-message payload.
-- Reads large_diff config to decide which pipeline to use.
-- @param diff_data      table   { diff = string, files = table }
-- @param provider       table   Provider instance
-- @param provider_config table  Provider config
-- @param callback       function(error, final_payload)
function M.prepare(diff_data, provider, provider_config, callback)
  local config = require("aicommits.config")
  local ld     = config.get("large_diff")
  local mode   = ld and ld.mode or "off"

  local use_rich = false

  if mode == "always" then
    use_rich = true
  elseif mode == "auto" then
    local threshold = ld.threshold_chars or 12000
    use_rich = #(diff_data.diff or "") > threshold
  end

  if use_rich then
    require("aicommits.input.rich").prepare(diff_data, provider, provider_config, callback)
  else
    require("aicommits.input.default").prepare(diff_data, provider, provider_config, callback)
  end
end

return M
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/input_init_spec.lua
```

Expected: all tests pass.

- [ ] Step 5 (commit):

```
git add lua/aicommits/input/init.lua tests/input_init_spec.lua
git commit -m "feat(input): add dispatcher that routes to default or rich pipeline"
```

**Verification:**

```
busted tests/input_init_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: line containing `OK` with zero failures.

---

## Task 10: commit.lua — wire input.prepare into the workflow

**Goal:** Modify `commit.lua` to call `input.prepare()` around the existing `provider:generate_commit_message` call, replacing the raw `diff_data.diff` argument with `final_payload` from the callback.

**Files touched:**
- Modify: `lua/aicommits/commit.lua`
- Test: `tests/integration_spec.lua`

**Steps:**
- [ ] Step 1 (failing test) — Add a test to `tests/integration_spec.lua` that verifies the pipeline is invoked with the `final_payload` (not the raw diff) when `large_diff.mode = "always"`. Use a mock `input.prepare` preload:

```lua
describe("commit.lua — input.prepare integration", function()
  it("calls generate_commit_message with final_payload from input.prepare", function()
    local config = require("aicommits.config")
    config.setup({ large_diff = { mode = "always" } })

    -- Stub git operations
    local git = require("aicommits.git")
    local orig_is_repo    = git.is_git_repo
    local orig_get_diff   = git.get_staged_diff
    git.is_git_repo    = function() return true end
    git.get_staged_diff = function(cb)
      cb(nil, { diff = "raw-diff", files = { "a.lua" } })
    end

    -- Stub provider manager
    local providers = require("aicommits.providers")
    local orig_get_active = providers.get_active_provider
    local received_payload
    providers.get_active_provider = function()
      return {
        name = "test",
        generate_commit_message = function(self, payload, _cfg, cb)
          received_payload = payload
          cb(nil, { "test: do stuff" })
        end,
      }, nil
    end

    -- Stub input.prepare to return a transformed payload
    package.loaded["aicommits.input"] = nil
    package.preload["aicommits.input"] = function()
      return {
        prepare = function(_dd, _p, _pc, cb)
          cb(nil, "TRANSFORMED_PAYLOAD")
        end,
      }
    end

    -- Stub picker and ui to be no-ops
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status  = function() end
    picker.close_status = function() end

    local ui = require("aicommits.ui")
    local orig_show_prompt = ui.show_commit_prompt
    ui.show_commit_prompt = function() end

    -- Run
    package.loaded["aicommits.commit"] = nil
    require("aicommits.commit").generate_and_commit()

    -- Restore
    git.is_git_repo        = orig_is_repo
    git.get_staged_diff    = orig_get_diff
    providers.get_active_provider = orig_get_active
    package.preload["aicommits.input"] = nil
    package.loaded["aicommits.input"]  = nil
    picker.show_status   = orig_show
    picker.close_status  = orig_close
    ui.show_commit_prompt = orig_show_prompt

    assert.equals("TRANSFORMED_PAYLOAD", received_payload)
  end)
end)
```

- [ ] Step 2 (run test, observe FAIL) — Run:

```
busted tests/integration_spec.lua
```

Expected failure: `commit.lua` passes `diff_data.diff` directly (not through `input.prepare`), so `received_payload` equals `"raw-diff"`.

- [ ] Step 3 (minimal implementation) — In `lua/aicommits/commit.lua`:

Before making the replacement below, locate and delete the following exact 3-line block at lines 48–50 of `lua/aicommits/commit.lua` (the deferred status that fires after `input.prepare` has set its own status, causing a UI conflict [inferred]):

```lua
    vim.defer_fn(function()
      picker.show_status("The AI is analyzing your changes...")
    end, 500)
```

This block is distinct from the success-path `vim.defer_fn` near line 103 that calls `picker.close_status()` after a 1500ms delay — that one must be preserved. [inferred]

Replace the direct `provider:generate_commit_message` call block. Change:

```lua
    provider:generate_commit_message(diff_data.diff, provider_config, function(err, messages)
```

To the `input.prepare` wrapper pattern:

```lua
    local input = require("aicommits.input")
    input.prepare(diff_data, provider, provider_config, function(input_err, final_payload)
      if input_err then
        picker.close_status()
        utils.notify_error(input_err)
        return
      end

      provider:generate_commit_message(final_payload, provider_config, function(err, messages)
```

And close the new `input.prepare` callback's function block after the existing `generate_commit_message` callback closes. The existing closing `end)` for `generate_commit_message` stays. Add one additional `end)` to close `input.prepare`'s callback:

```lua
      end)  -- generate_commit_message
    end)    -- input.prepare
```

The full updated block in context (replace from the husky block end through the `git.get_staged_diff` callback's close):

```lua
    local input = require("aicommits.input")
    input.prepare(diff_data, provider, provider_config, function(input_err, final_payload)
      if input_err then
        picker.close_status()
        utils.notify_error(input_err)
        return
      end

      provider:generate_commit_message(final_payload, provider_config, function(err, messages)
        if err then
          picker.close_status()
          utils.notify_error(err)
          return
        end

        if not messages or #messages == 0 then
          picker.close_status()
          utils.notify_error("No commit messages were generated. Try again.")
          return
        end

        -- Step 5: Show user selection UI (status window auto-closes)
        local ui_opts = { commitlint_detected = provider_config.commitlint_resolved == true }
        ui.show_commit_prompt(
          messages,
          function(selected_message)
            picker.show_status("Creating commit...")

            git.create_commit(selected_message, function(err)
              if err then
                picker.close_status()
                utils.notify_error(err)
                return
              end

              picker.show_status("Successfully committed!")
              git.refresh_git_clients()

              vim.defer_fn(function()
                picker.close_status()
              end, 1500)
            end)
          end,
          function()
          end,
          ui_opts
        )
      end)
    end)
```

- [ ] Step 4 (run test, observe PASS) — Run:

```
busted tests/integration_spec.lua
```

Expected: all tests pass.

- [ ] Step 5 (commit):

```
git add lua/aicommits/commit.lua tests/integration_spec.lua
git commit -m "feat(commit): route diff through input.prepare before generate_commit_message"
```

**Verification:**

```
busted tests/integration_spec.lua 2>&1 | grep -E "OK|FAIL|Error"
```

Expected: line containing `OK` with zero failures.

---

## Task 11: full test suite green-check

**Goal:** Confirm all existing and new tests pass together after the full implementation; no regressions.

**Files touched:**
- Test: all spec files (read-only verification)

**Steps:**
- [ ] Step 1 (no new test to write) — This task is a verification-only task; skip to Step 3.
- [ ] Step 2 (not applicable)
- [ ] Step 3 (run full suite):

```
busted tests/
```

Expected: zero failures across all spec files.

- [ ] Step 4 (observe PASS):

```
busted tests/ 2>&1 | tail -5
```

Expected output contains a line like `X success(es), 0 failure(s)`.

- [ ] Step 5 (commit if any fixups were needed):

```
git add -p
git commit -m "fix: address full-suite regressions after rich-input integration"
```

(Skip this commit if the suite is already clean.)

**Verification:**

```
busted tests/ 2>&1 | grep -E "^[0-9]+ success"
```

Expected: a line like `42 successes, 0 failures, 0 errors`.

---

## Refinement Status

Refinement: CONVERGED round 6 [inferred]

Findings addressed (round 5):
- c1 (Task 4, Step 1 / vertex summarize() test): Replaced `vim.fn.system` + `vim.v.shell_error` stubs with `vim.fn.jobstart` stubs that call `opts.on_stdout(0, {"fake.token.here"}, "stdout")` and `opts.on_exit(0, 0, "exit")`, mirroring `tests/vertex_spec.lua` lines 262–277. Added `before_each` / `after_each` blocks that reset `package.loaded["aicommits.providers.vertex"]`, re-require the module, and zero out `M._cached_token` / `M._token_expiry` to prevent cached-token interference. [inferred]
- m1 (Task 8, Step 3 / `total_tasks == 0` branch): Added `picker.close_status()` before `callback(nil, payload)` in the early-return branch that handles all-small-inline files, so the status window opened by `picker.show_status("Analyzing staged diff...")` is always closed. [inferred]
- m2 (Task 4, Step 1 / vertex summarize() success test): Removed dangling `local orig_generate_token` declaration; the jobstart-based approach makes it unnecessary. [inferred]

Findings addressed (round 4):
- i1 (Task 4, Step 1 / Step 4 / Step 5): Added `describe('summarize()', ...)` blocks in `tests/vertex_spec.lua` and `tests/openai_spec.lua` mirroring the gemini pattern (stub `http.post` with canned response → assert extracted text; stub with error → assert error string surfaces). Added Step 1b to run those failing tests before implementation. Updated Step 4 run command, Step 5 `git add`, and Verification block to include all three spec files. [inferred]

Findings addressed (round 3):
- i1 (Task 10, Step 3): Quoted the exact 3-line `vim.defer_fn` block (lines 48–50 of commit.lua) to delete; added note distinguishing it from the success-path `vim.defer_fn` near line 103 that must be preserved. [inferred]
- m1 (Task 8, Step 3): Added `picker.close_status()` calls in `check_done()` — before `callback(err, nil)` on the all-failed path and before `callback(nil, payload)` on the success path. [inferred]
- m2 (Task 8, Step 3): Added inline comment on the overflow guard documenting that overflow files are stat-only and do not increment `summary_attempts`, so they never count toward the all-failed threshold. [inferred]

Findings addressed (round 2):
- i1 (Task 8): Introduced a separate `chunk_sched = M.make_scheduler(math.huge)` for inner per-chunk summarize calls so they never contend with outer file-level slots; prevents deadlock when `concurrency = 1`. [inferred]
- i2 (Task 8): Documented partial-failure semantics in `check_done`: mixed payload assembled when ≥1 summary succeeded; error message updated to report fraction (`0/N succeeded`) when all fail. [inferred]
- m1 (Overview): Replaced "independently completable" with "sequentially ordered" and noted Tasks 6–8 are a dependent chain. [inferred]

Findings addressed (round 1):
- c1 (Task 2): Added `vim.v` writable-proxy stub in `before_each` / `after_each` in the `get_staged_stat` test block. [inferred]
- c2 (Task 7): Added `vim.schedule` synchronous stub in `before_each` / `after_each` for `make_scheduler` tests. [inferred]
- i1 (Task 8): Added `picker.show_status` / `picker.close_status` stubs in `before_each` / `after_each` in the `prepare()` integration describe block. [inferred]
- i2 (Task 4): Confirmed `generate_token` is module-scope local (vertex.lua line 24); updated plan comment accordingly; no hoist step needed. [inferred]
- i3 (Task 8): Introduced `task_completed` boolean guard and `complete_task()` helper per large-file task; all early-return and rollup paths now call `complete_task()` instead of the raw triplet. [inferred]
- i4 (Task 10): Added explicit sub-step to remove the `vim.defer_fn` 500ms `show_status` call before wiring `input.prepare`. [inferred]
- m1 (Task 6): Dropped `^` anchor from `is_binary` pattern in `split_diff_by_file`. [inferred]
- m3 (Overview): Updated task count from "nine" to "eleven". [inferred]
