# Design: Centralize summary prompts, provider-agnostic `generate_text`, and a request policy layer

- **Date:** 2026-06-05
- **Issue:** [#24](https://github.com/404pilo/aicommits.nvim/issues/24) (refactor) + follow-up [comment](https://github.com/404pilo/aicommits.nvim/issues/24#issuecomment-4629721102) (request policy layer)
- **Scope:** Both pieces in one PR. `generate_text` is the **universal** request envelope (also backs `generate_commit_message`).

## Problem

Prompt engineering is coupled to both the rich-input pipeline and the provider layer. Each provider's `summarize(text, opts, cfg, cb)` *both* builds the summary prompt (via `prompts.build_summary_prompt`) *and* performs the HTTP POST. The main `generate_commit_message` is reimplemented per provider. There is no shared request policy: `http.post` uses `curl -s`, has no timeout, never inspects the HTTP status (so 429/5xx slip through as parsed JSON errors), and never retries. In rich-input mode a single commit fans out into many summary requests, so one flaky request or a short burst limit degrades the whole flow.

## Goals

1. Centralize summary prompt construction in `prompts.lua`.
2. Introduce a provider-agnostic `generate_text(envelope, cfg, cb)` method taking a universal request envelope; make providers transport-only (body shaping + response parsing).
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
  → provider:generate_text(envelope, cfg, cb)
      → request.send({ url, headers, body, policy }, cb)   -- policy: throttle → send → classify → retry/backoff
          → http.post(...)              -- curl: --max-time, capture %{http_code} + Retry-After
      ← normalized texts[]
```

**Naming:** the LLM-request table assembled by callers is the **envelope**; the policy
module is **`request.lua`** (its public function is `request.send`). The two are never the
same object — `generate_text` consumes the envelope and *produces* the `request.send` opts.

### 1. Prompt centralization — `prompts.lua`

Add three explicit builders, each returning `{ system = string, user = string }`:

- `build_chunk_summary_prompt(file_path, chunk)`
- `build_file_rollup_prompt(file_path, chunk_summaries)`
- `build_small_batch_prompt(batch_payload)`

Their system/user text is moved verbatim from the current `build_summary_prompt` branches. The `build_summary_prompt(kind, ...)` dispatcher is **removed** — its only callers were the provider `summarize` methods. `build_system_prompt` and `process_messages` are unchanged.

### 2. Provider-agnostic envelope — `base.lua` + providers

**Envelope** (provider-agnostic superset; providers read what they support):

```
envelope = {
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
generate_text(envelope, provider_config, callback)
  callback(err, texts)   -- texts = normalized array of candidate strings (len <= n)
```

Each provider:
- maps the envelope onto its API body (OpenAI: `n`, `top_p`, penalties; Gemini/Vertex: `candidateCount`, ignoring unsupported fields),
- resolves effective request policy via `request.resolve_policy(provider_config)` (global `request` block merged with `providers.<name>.request`),
- calls `request.send({ url, headers, body, policy }, cb)` (never `http.post` directly), where `cb(err, result)` and `result = { status, body, headers }` — the same shape `http.post` now returns (the policy layer is transparent on the result),
- parses `result.body` for its response shape (`choices[].message.content` / `candidates[].content.parts[].text`) into a string array. On a transport error (`err` set) or empty parse, surfaces an error string exactly as today.

> **`n`/candidateCount defaults are preserved per provider.** Vertex's commit path historically hardcoded `candidateCount = 3`. With the envelope carrying `n = config.generate or 1` and vertex's config default `generate = 3`, vertex maps `n` → `candidateCount` and the 3-option behavior is unchanged. OpenAI maps `n` directly; Gemini maps `n` → `candidateCount`. Summary calls pass `n = 1`.

`summarize` is **removed** from `base.Provider` and from every provider.

**`generate_commit_message` moves up into `base.lua`** as a generic method:

```
function M.Provider:generate_commit_message(diff, config, callback)
  local envelope = {
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
  self:generate_text(envelope, config, function(err, texts)
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

**Capability gate in `input/init.lua` must be retargeted.** Today `input/init.lua` routes rich-vs-default via `supports_summarize(provider)`, which checks `provider.summarize ~= base.Provider.summarize`. Removing `summarize` orphans this gate — it would always return false and silently disable rich mode for every provider. Since `generate_text` is now mandatory for all providers (every provider implements it; rich mode requires only `generate_text`), the gate is **removed entirely** along with its `vim.notify("…does not support diff summarization…")` fallback branch. `M.prepare` routes to rich purely on `large_diff.mode`/threshold. `input_init_spec.lua` loses its two `supports_summarize`-based cases and gains a case asserting rich routing no longer depends on a provider capability probe.

### 3. Request policy layer — `request.lua` (new) + `http.lua`

**`http.lua`** (low-level transport, stays dumb) — **signature change is breaking and intentional:**
- New signature `http.post(url, headers, body, opts, callback)` where `opts = { timeout_ms }` (optional; callers that omit it get no `--max-time`). Existing callers are all migrating to `request.send`, which always supplies `opts`.
- `callback(err, result)` now returns `result = { status = number, body = string, headers = table }` (was `callback(err, body_string)`). `err` is set **only** for transport-level failures (curl non-zero exit, e.g. timeout exit 28); an HTTP 4xx/5xx is a successful transport and returns `err = nil` with the non-2xx `status`.
- Add timeout via curl `--max-time <math.max(1, math.floor(timeout_ms/1000))>` (curl `--max-time` is whole-second granularity; sub-second timeouts round up to 1s — noted as an accepted limitation).
- Capture status + `Retry-After` in one curl invocation using `--write-out` with a unique sentinel that cannot occur in a JSON body, e.g. `-w "\n<<<AICOMMITS_META>>>%{http_code} %{header{retry-after}}"`. Split the body at the **last** occurrence of the sentinel (status is appended *after* the body). `%{header{name}}` requires **curl ≥ 7.84**; on older curl the `retry-after` field is empty, so `respect_retry_after` degrades gracefully to plain backoff (documented; health-check may warn). `headers` is therefore a minimal table populated only with `retry_after` when present — not a full header map.

**`request.lua`** (policy wrapper every `generate_text` calls). Public surface:
`request.send({ url, headers, body, policy }, cb)` and `request.resolve_policy(provider_config)`.

- **Single process-global semaphore.** There is exactly **one** module-level semaphore in `request.lua`, the only concurrency limiter in the system. Its bound is read **lazily at each acquire** from `request.resolve_policy(...).max_concurrency` of the *active provider* (so a `setup()` change between commits takes effect), but it is **one shared counter** regardless of provider. **Resolution of the contradiction with per-provider override:** `max_concurrency` is treated as a **global-only** knob — `providers.<name>.request.max_concurrency` is accepted by config but, because the semaphore is shared, the effective bound is whichever the *currently active* provider resolves to; mixing providers within one commit is not a supported scenario (one commit uses one active provider). All other policy fields (timeout/retry/backoff) are genuinely per-provider via the merge. This is called out explicitly so the override is not read as "N independent per-provider limiters."
- **`resolve_policy(provider_config)`** returns the global `request` block deep-merged with `provider_config.request` (the per-provider override), with `large_diff.concurrency` back-compat already folded in (see §5). Pure function of config; no I/O.
- **`request.send`** acquires a semaphore slot, calls `http.post(url, headers, body, { timeout_ms = policy.timeout_ms }, ...)`, classifies the result, and either returns or schedules a retry.
- **Retry transient failures only:** a transport error (network/timeout, `err` set) or a response `status` in `retry_on_status`. Anything else (2xx success, non-retryable 4xx) returns immediately with `(nil, result)`.
- **Backoff:** `min(backoff_base_ms * 2^(attempt-1), backoff_max_ms)` (attempt is 1-based; first retry waits `backoff_base_ms`), plus optional full jitter when `backoff_jitter` (`random()*delay`). On a 429/503 with `respect_retry_after` and a `retry_after` value present, use that delay (seconds → ms) capped at `backoff_max_ms`. Delays scheduled with an injectable timer seam — default `vim.defer_fn`, overridable in tests via a module-level `request._defer` so backoff timing is asserted deterministically without wall-clock sleeps. The semaphore slot is **released during the backoff wait** and re-acquired before the retry send, so a sleeping retry does not hold a slot.
- **Budget:** total attempts = `1 + max_retries`. On exhaustion, return the **last** `(err, result)` so the provider parses and surfaces the final response/JSON error exactly as today.

### 4. `rich.lua`

- The three `provider:summarize(...)` call sites become: build the specific prompt (`prompts.build_*` returning `{ system, user }`), assemble the envelope (`system`/`user` from the prompt, `model = ld_cfg.summary_model`, `max_tokens = ld_cfg.summary_max_tokens`, `temperature = ld_cfg.summary_temperature`, `n = 1`), call `provider:generate_text(envelope, cfg, cb)`, and use `texts[1]` (treating empty `texts` or `texts[1] == ""` as the per-call failure the existing partial-failure logic already handles via the `err` branch). The summarize-specific opts (`prompt_kind`, `file_path`) no longer cross the provider boundary — the prompt is fully built in `rich.lua` before the call.
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
- **Back-compat / precedence:** `request.max_concurrency` is canonical. If the **user explicitly set** `large_diff.concurrency` (distinguished from the default `4` by checking `user_opts`, not the merged config) **and did not explicitly set** `request.max_concurrency`, fold the legacy value into the effective `max_concurrency` and emit a one-time soft deprecation notice (`vim.notify`, WARN). If **both** are explicitly set, `request.max_concurrency` wins and the deprecation notice still fires. The fold happens once during `setup()` so `resolve_policy` reads a single canonical value. `large_diff.concurrency` is no longer read by `rich.lua`.
- Validation: `timeout_ms`, `max_retries`, `backoff_base_ms`, `backoff_max_ms`, `max_concurrency` are positive numbers (`max_retries` ≥ 0); `retry_on_status` is an array of integers; `respect_retry_after`/`backoff_jitter` are booleans.

### 6. Tests

- **New `tests/request_spec.lua`:** retry on a stubbed transient (transport err / 5xx / 429) succeeds on a later attempt; no retry on 400/401/403/404; backoff schedule respects base/max and is bounded (asserted via the injected `request._defer` timer seam capturing scheduled delays — no wall-clock waits); semaphore never exceeds `max_concurrency` in flight (drive several concurrent `send`s, assert peak in-flight); `retry_after` honored and capped at `backoff_max_ms`; `resolve_policy` merge (global + per-provider override) for timeout/retry fields. Stubs `http.post` returning the **new** `{ status, body, headers }` shape.
- **New `tests/http_spec.lua`:** sentinel split parses `status` + `retry_after` off the tail when the body itself contains the sentinel string and trailing newlines; `--max-time` rounding (sub-second → 1s); non-2xx returns `err = nil` with the status; transport failure (curl exit 28) returns `err` set. Stub `vim.system` to feed canned `obj.stdout`/`obj.code`.
- **Update provider specs (`openai_spec`, `gemini_spec`, `vertex_spec`):** migrate every `http.post` stub to the new `(url, headers, body, opts, cb)` signature returning `{ status = 200, body = json, headers = {} }`; assert providers read `result.body`; assert `generate_text` envelope mapping (`n`→`candidateCount` for gemini/vertex, vertex preserves 3-candidate default) and no `summarize` method remains. Add coverage that providers call `request.send`, not `http.post`, directly.
- **Update** `prompts_spec.lua` (three new builders, dispatcher removed); `input_init_spec.lua` (drop the two `supports_summarize`-based cases; assert rich routing no longer probes provider capability); `input_rich_spec.lua` / `verifier_rich_input_scenarios_spec.lua` (replace `summarize` stubs with `generate_text` stubs returning `texts[]`, new call shape, unbounded scheduler still partial-fails correctly); `integration_spec.lua` (unchanged `generate_commit_message` contract); `config_spec.lua` (new `request` block validation + `large_diff.concurrency` alias precedence + deprecation notice fires once).
- The deterministic seams are: stub `http.post` for `request.lua` policy tests, stub `vim.system` for `http.lua` tests, inject `request._defer` for backoff timing. No real curl, no real sleeps.

## Risks / decisions

- **Status capture marker:** the body can contain anything, so the sentinel must be unambiguous (status + `retry-after` appended *after* the body; parse from the **last** sentinel). Covered by `http_spec.lua`.
- **`http.post` signature change is breaking:** every existing provider spec stub and the three provider parsers migrate to `(url, headers, body, opts, cb)` / `result.body`. This is a one-time coordinated change inside this PR, not a back-compat shim. Decided: no dual-signature support — the codebase has no external callers of `http.post`.
- **Single global semaphore vs per-provider override:** decided that `max_concurrency` is effectively global (one shared counter, bound by the active provider's resolved value). Per-provider `max_concurrency` is accepted but does not create independent limiters; only timeout/retry/backoff are meaningfully per-provider. A single commit uses a single active provider, so this is not a practical limitation.
- **Slot release during backoff:** required so a retrying request doesn't hold a concurrency slot while sleeping; otherwise a burst of 429s could deadlock throughput.
- **`Retry-After` needs curl ≥ 7.84** (`%{header{…}}`): on older curl the field is empty and `respect_retry_after` degrades to plain exponential backoff. Decided acceptable; health-check may surface a soft notice.
- **Capability gate removed:** `input/init.lua`'s `supports_summarize` probe is deleted because `generate_text` is mandatory for all providers; rich routing now depends only on `large_diff.mode`/threshold.
- **Gemini/Vertex `n`:** mapped to `candidateCount` where supported (vertex preserves its historical 3-candidate default via `generate = 3`); unsupported envelope fields are silently ignored by those providers (existing behavior — they already ignored OpenAI-only params).

## Refinement Status

Refinement: CONVERGED round 2

Round 2 (spec-simulator re-pass on patched spec): no critical/important findings. Only a
single stale arg name in Goal #2 (`request` → `envelope`), fixed inline. Convergence predicate
`not critical_or_important(findings)` satisfied.

Round 1 findings resolved (spec-fixer applied inline):
- C1 orphaned `supports_summarize` capability gate in `input/init.lua` → gate removed (§2).
- C2 `http.post` return-signature change unacknowledged → breaking signature + provider/test migration made explicit (§3, §6, Risks).
- I3 `request.send`/module-vs-envelope naming + undefined interface → `envelope` vs `request.lua` disambiguated, `request.send`/`resolve_policy` signatures defined (data flow, §2, §3).
- I4 global-semaphore vs per-provider override contradiction → resolved to single global counter; per-provider override scoped to timeout/retry/backoff (§3, §5, Risks).
- I5 vertex 3-candidate default loss → `n` mapping preserves it (§2, Risks).
- I6 `Retry-After` curl mechanism + version → `%{header{retry-after}}`, curl ≥ 7.84, graceful degrade (§3, Risks).
- I7 request.lua test time-seam → injectable `request._defer`; http.post stub shape (§3, §6).
- m8 alias precedence → explicit user-set detection + both-set tie-break (§5).
- m9 missing test files → `input_rich_spec`, `verifier_rich_input_scenarios_spec`, `http_spec` added to test plan (§6).
