# Design: Centralize summary prompts, provider-agnostic `generate_text`, and a request policy layer

- **Date:** 2026-06-05
- **Issue:** [#24](https://github.com/404pilo/aicommits.nvim/issues/24) (refactor) + follow-up [comment](https://github.com/404pilo/aicommits.nvim/issues/24#issuecomment-4629721102) (request policy layer)
- **Scope:** Both pieces in one PR. `generate_text` is the **universal** request envelope (also backs `generate_commit_message`).

## Problem

Prompt engineering is coupled to both the rich-input pipeline and the provider layer. Each provider's `summarize(text, opts, cfg, cb)` *both* builds the summary prompt (via `prompts.build_summary_prompt`) *and* performs the HTTP POST. The main `generate_commit_message` is reimplemented per provider. There is no shared request policy: `http.post` uses `curl -s`, has no timeout, never inspects the HTTP status (so 429/5xx slip through as parsed JSON errors), and never retries. In rich-input mode a single commit fans out into many summary requests, so one flaky request or a short burst limit degrades the whole flow.

## Goals

1. Centralize summary prompt construction in `prompts.lua`.
2. Introduce a provider-agnostic `generate_text(request, cfg, cb)` envelope; make providers transport-only (body shaping + response parsing).
3. Add a shared request policy layer: timeout, retry on transient failures only, exponential backoff with a retry budget, and a single global concurrency limiter.
4. Retire `summarize` from the base interface and all providers.

## Non-goals

- Streaming responses.
- Per-request-kind distinct policies (one policy block, with per-provider override, is enough).
- Reworking the bucketing/chunking logic in `rich.lua` beyond the call-site change and the scheduler becoming unbounded.

## Architecture

### Data flow

```
rich.lua / base.generate_commit_message
  → build prompt (prompts.lua)
  → provider:generate_text(request, cfg, cb)
      → request.send(opts, cb)          -- policy: throttle → send → classify → retry/backoff
          → http.post(...)              -- curl: --max-time, capture %{http_code}
      ← normalized texts[]
```

### 1. Prompt centralization — `prompts.lua`

Add three explicit builders, each returning `{ system = string, user = string }`:

- `build_chunk_summary_prompt(file_path, chunk)`
- `build_file_rollup_prompt(file_path, chunk_summaries)`
- `build_small_batch_prompt(batch_payload)`

Their system/user text is moved verbatim from the current `build_summary_prompt` branches. The `build_summary_prompt(kind, ...)` dispatcher is **removed** — its only callers were the provider `summarize` methods. `build_system_prompt` and `process_messages` are unchanged.

### 2. Provider-agnostic envelope — `base.lua` + providers

**Envelope request** (provider-agnostic superset; providers read what they support):

```
request = {
  system            = string,
  user              = string,
  model             = string|nil,   -- falls back to provider config.model
  max_tokens        = number|nil,
  temperature       = number|nil,
  n                 = number|nil,   -- generations, default 1
  top_p             = number|nil,   -- OpenAI-style, optional
  frequency_penalty = number|nil,
  presence_penalty  = number|nil,
}
```

**New interface method** — the only transport each provider implements:

```
generate_text(request, provider_config, callback)
  callback(err, texts)   -- texts = normalized array of candidate strings (len <= n)
```

Each provider:
- maps the envelope onto its API body (OpenAI: `n`, `top_p`, penalties; Gemini/Vertex: `candidateCount`, ignoring unsupported fields),
- calls `request.send(...)` (never `http.post` directly),
- parses its response shape (`choices[].message.content` / `candidates[].content.parts[].text`) into a string array.

`summarize` is **removed** from `base.Provider` and from every provider.

**`generate_commit_message` moves up into `base.lua`** as a generic method:

```
function M.Provider:generate_commit_message(diff, config, callback)
  local request = {
    system = prompts.build_system_prompt(config.max_length or 50, config.commitlint_config),
    user = diff,
    model = config.model,
    max_tokens = config.max_tokens,
    temperature = config.temperature,
    n = config.generate or 1,
    top_p = config.top_p,
    frequency_penalty = config.frequency_penalty,
    presence_penalty = config.presence_penalty,
  }
  self:generate_text(request, config, function(err, texts)
    if err then return callback(err, nil) end
    local processed = prompts.process_messages(texts or {})
    if #processed == 0 then
      return callback("No valid commit messages were generated. Try again.", nil)
    end
    callback(nil, processed)
  end)
end
```

Providers no longer reimplement `generate_commit_message`; they only shape bodies and parse responses inside `generate_text`. Provider-specific concerns that don't fit the generic path (e.g. endpoint/model resolution, default values) live inside each provider's `generate_text`.

### 3. Request policy layer — `request.lua` (new) + `http.lua`

**`http.lua`** (low-level transport, stays dumb):
- Add timeout via curl `--max-time <timeout_ms/1000>`.
- Capture the HTTP status: append `%{http_code}` with `-w` using a sentinel marker, split it off the body.
- Return `(err, { status = number, body = string, headers = table })` where `err` is set only for transport-level failures (curl non-zero exit, e.g. timeout exit 28). Header capture is limited to what's needed for `Retry-After`.

**`request.lua`** (policy wrapper every `generate_text` calls):
- **Global semaphore** bounded by the effective `max_concurrency` — the single concurrency limiter in the system. Queued sends dispatch as slots free (same pattern as the existing `make_scheduler`, but global and bounding actual HTTP sends).
- **Retry transient failures only:** a transport error (network/timeout) or a response `status` in `retry_on_status`. Anything else (success, non-retryable 4xx) returns immediately.
- **Backoff:** `min(backoff_base_ms * 2^attempt, backoff_max_ms)`, plus optional full jitter when `backoff_jitter`. On a 429 with `respect_retry_after` and a `Retry-After` header, use that delay capped at `backoff_max_ms`. Delays scheduled with `vim.defer_fn`; the semaphore slot is **released during the backoff wait** so a sleeping retry does not block other requests.
- **Budget:** total attempts = `1 + max_retries`. On exhaustion, return the last result so the provider surfaces its parsed JSON error exactly as today.
- Effective policy is resolved per call: global `request` config merged with `providers.<name>.request` override.

### 4. `rich.lua`

- The three `provider:summarize(...)` call sites become: build the specific prompt (`prompts.build_*`), assemble the envelope (`model = ld_cfg.summary_model`, `max_tokens = ld_cfg.summary_max_tokens`, `temperature = ld_cfg.summary_temperature`, `n = 1`), call `provider:generate_text(request, cfg, cb)`, and use `texts[1]`.
- `make_scheduler` remains for orchestration but is created **unbounded** (`math.huge`). Concurrency is enforced solely by the request-layer semaphore. The existing comment about the inner chunk scheduler being uncapped to avoid deadlock still holds and is now the norm for both schedulers.
- All existing partial-failure / all-failed / demotion behavior is preserved; only the call mechanism changes.

### 5. Config — `config.lua`

New top-level block with defaults:

```lua
request = {
  timeout_ms          = 30000,
  max_retries         = 2,                              -- total attempts = 1 + max_retries
  backoff_base_ms     = 500,
  backoff_max_ms      = 8000,
  backoff_jitter      = true,
  retry_on_status     = { 408, 429, 500, 502, 503, 504 },
  respect_retry_after = true,
  max_concurrency     = 4,
}
```

- Per-provider override: `providers.<name>.request = { ... }` merged over the global block.
- **Back-compat:** if `large_diff.concurrency` is set, fold its value into the effective `max_concurrency` and emit a one-time soft deprecation notice (via `vim.notify`, WARN level). `request.max_concurrency` is canonical going forward. `large_diff.concurrency` is no longer read by `rich.lua`.
- Validation: `timeout_ms`, `max_retries`, `backoff_base_ms`, `backoff_max_ms`, `max_concurrency` are positive numbers (`max_retries` ≥ 0); `retry_on_status` is an array of integers; `respect_retry_after`/`backoff_jitter` are booleans.

### 6. Tests

- **New `tests/request_spec.lua`:** retry on a stubbed transient (timeout / 5xx / 429) succeeds on a later attempt; no retry on 400/401/403; backoff schedule respects base/max and is bounded; semaphore never exceeds `max_concurrency` in flight; `Retry-After` honored and capped; per-provider override merge.
- **Update** `prompts_spec.lua` (three new builders, dispatcher removed), provider specs (`generate_text` + parsing, no `summarize`), `rich`/integration specs (new call shape, unbounded scheduler still partial-fails correctly), `config_spec.lua` (new block validation + `large_diff.concurrency` alias + deprecation notice).
- Stub transport at the `http.post` boundary so `request.lua` policy can be tested deterministically without real curl.

## Risks / decisions

- **Status capture marker:** the body can contain anything, so the `%{http_code}` sentinel must be unambiguous (status is appended *after* the body; parse from the tail). Covered by an http-layer test.
- **Slot release during backoff:** required so a retrying request doesn't hold a concurrency slot while sleeping; otherwise a burst of 429s could deadlock throughput.
- **Gemini/Vertex `n`:** mapped to `candidateCount` where supported; unsupported envelope fields are silently ignored by those providers (existing behavior — they already ignored OpenAI-only params).
