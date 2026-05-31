# Rich Input Mode for Large Staged Diffs

**Issue:** [#20](https://github.com/404pilo/aicommits.nvim/issues/20)
**Status:** Draft
**Date:** 2026-05-28

## Problem

Large staged diffs are difficult for a single prompt to handle well. They also cause practical failures on Windows when the JSON request body is passed to `curl` as a command-line argument: very large diffs can exceed the OS process argument-length limit before the provider callback even runs.

The current flow sends the entire `git diff --cached` output as one prompt, with no fallback when the diff is too big.

## Goal

Introduce an optional **summarization pipeline** that processes large diffs in pieces, then composes a structured prompt for the final commit-message call. Keep the existing fast path intact for small/medium commits.

## Non-Goals

- Replacing the default pipeline. The raw-diff path remains the default behavior.
- Multi-commit splitting. This feature improves how *one* commit message is generated, not how many commits are produced.
- Cross-commit caching of summaries. Each invocation runs fresh.
- A new provider primitive beyond what summarization needs (no generic `complete()` refactor).

## User-Facing Configuration

All knobs live under a single `large_diff` block. `config.lua`'s `M.defaults` must be updated to include this table with the values shown below so that `config.get('large_diff')` returns a fully-populated table on first use. [inferred] `M.validate()` is extended to assert that `large_diff.mode` is one of `"off"`, `"auto"`, or `"always"`. [inferred]

```lua
require("aicommits").setup({
  large_diff = {
    -- "off" = always raw diff; "auto" = summarize when diff exceeds threshold_chars; "always" = always summarize.
    mode = "auto",

    -- In "auto" mode, total staged diff size that triggers summarization.
    threshold_chars = 12000,

    -- Target chunk size when splitting a large file's diff (splits on hunk boundaries, never mid-hunk).
    chunk_chars = 6000,

    -- If a file would produce more chunks than this, skip summaries for it and use `git diff --stat` only.
    max_chunks_per_file = 6,

    -- Diffs smaller than this are treated as "small files" and inlined raw into the final prompt.
    small_file_chars = 800,

    -- If the commit has more small files than this, group them into pre-summary batches instead of inlining.
    max_small_files_inline = 10,

    -- Character budget per small-file batch when batching kicks in.
    small_file_batch_chars = 4000,

    -- Optional model override for summary calls (chunks, roll-ups, batches). Nil = active provider's default.
    summary_model = nil,

    -- Max tokens per summary response; keeps summaries terse.
    summary_max_tokens = 220,

    -- Sampling temperature for summary calls only (final commit message uses provider's own temperature).
    summary_temperature = 0.2,

    -- Max parallel summary calls. Lower this if you hit rate limits.
    concurrency = 4,
  },
})
```

### Mode semantics

| `mode`     | Behavior                                                                                |
|------------|-----------------------------------------------------------------------------------------|
| `"off"`    | Always send the raw `git diff --cached` payload. Original plugin behavior.              |
| `"auto"`   | Send raw diff when `#diff <= threshold_chars`; otherwise run the summarization pipeline. |
| `"always"` | Always run the summarization pipeline. Note: `"always"` only bypasses the `threshold_chars` gate — bucketing (small-inline vs small-batched vs large) still applies to every file. [inferred] |

## Architecture

### Module layout

```
lua/aicommits/
├── commit.lua                 -- orchestrator (small change: routes through input.prepare)
├── input/
│   ├── init.lua               -- dispatch: chooses default vs rich based on config + diff size
│   ├── default.lua            -- returns raw diff as final-prompt payload
│   └── rich.lua               -- summarization pipeline
├── providers/<name>.lua       -- each gains a new `summarize()` method
└── prompts.lua                -- gains summary-prompt builders
```

`input/init.lua` dispatch logic: in `"auto"` mode, compares `#diff_data.diff` against `large_diff.threshold_chars`; if below, delegates to `default.lua`; otherwise delegates to `rich.lua`. [inferred] Both `default.lua` and `rich.lua` expose a single `prepare(diff_data, provider, provider_config, callback)` function as their public interface. [inferred]

### Prompt Templates

`prompts.lua` exports a `build_summary_prompt(kind, payload, opts)` function that returns `{ system, user }` strings. [inferred] Templates for each `prompt_kind`:

**`"chunk"`** — summarize one hunk-group from a single file. [inferred]

```
system: "You are a code-change summarizer. Produce a concise bullet-point summary (≤5 bullets, no markdown headers) of what this diff chunk changes. Be specific: name functions, variables, or config keys that are added, removed, or modified."

user: "File: <opts.file_path>\n\n<payload>"
```

**`"file_rollup"`** — synthesize per-chunk summaries into one file-level summary. [inferred]

```
system: "You are a code-change summarizer. Given the following chunk summaries for a single file, produce a single concise paragraph (≤4 sentences) describing the net effect of the changes."

user: "File: <opts.file_path>\n\nChunk summaries:\n<payload>"
```

**`"small_batch"`** — summarize a group of small files together. [inferred]

```
system: "You are a code-change summarizer. Given the following diffs for multiple small files, produce one concise bullet per file (format: '- <path>: <change summary>') describing the net change. Do not merge bullets across files."

user: "<payload>"
```

Where `<payload>` for `small_batch` is each file's path followed by its raw diff, separated by `\n---\n`. [inferred]

### Integration point

`commit.lua` requires the following changes: the husky/commitlint injection block that builds the final `provider_config` runs before `input.prepare` is called, exactly as today [inferred]. The existing `provider:generate_commit_message(diff_data.diff, ...)` call is moved inside the `input.prepare` callback and receives `final_payload` instead of `diff_data.diff` [inferred]. No other lines in `commit.lua` change.

```lua
-- husky injection runs here, producing provider_config (unchanged from today)
local input = require("aicommits.input")
input.prepare(diff_data, provider, provider_config, function(err, final_payload)
  if err then return utils.notify_error(err) end
  -- final_payload is what gets passed to provider:generate_commit_message
  provider:generate_commit_message(final_payload, provider_config, callback)
end)
```

`final_payload` is a string (the body the existing commit-prompt builder uses), so downstream code (selection UI, commit creation) is untouched.

### Provider interface change

Every provider gains a new method:

```lua
function Provider:summarize(text, opts, provider_config, callback)
  -- provider_config  = same table passed to generate_commit_message; provides api_key, endpoint, etc.
  -- opts = {
  --   model              = string|nil,   -- override; nil → provider default
  --   max_tokens         = number,
  --   temperature        = number,
  --   prompt_kind        = "chunk" | "file_rollup" | "small_batch",
  --   file_path          = string|nil,   -- context hint for the prompt builder
  -- }
  -- callback(err, summary_text)
end
```

`provider_config` is passed explicitly so providers can access auth credentials and endpoint settings exactly as they do in `generate_commit_message`. [inferred] The prompt body itself is built by `prompts.lua` based on `prompt_kind` so providers stay thin.

## Pipeline (rich mode)

### Per-file diff extraction

`input/rich.lua` obtains per-file diff text by parsing `diff_data.diff`, splitting on `diff --git a/...` boundary lines. Each segment (from one `diff --git` header to the next) becomes the per-file diff for that path. No new `git` subprocess is required. [inferred]

### Bucketing

For each file in `diff_data.files`, classify by per-file diff size (obtained via the extraction step above):

| Bucket            | Condition                                          | Treatment                                                          |
|-------------------|----------------------------------------------------|--------------------------------------------------------------------|
| **large**         | `#file_diff > small_file_chars`                    | chunk by hunk → per-chunk summary → file-rollup summary            |
| **small-inline**  | `#file_diff <= small_file_chars` AND small-file count ≤ `max_small_files_inline` | raw diff inlined verbatim in the final prompt                       |
| **small-batched** | `#file_diff <= small_file_chars` AND small-file count > `max_small_files_inline`  | grouped into batches ≤ `small_file_batch_chars`, one summary per batch |

The small-inline vs small-batched decision is made once per invocation, based on the total small-file count. Files don't cross between the two.

### Large-file path

Files with zero hunks after per-file diff extraction — binary files (matching `^Binary files`) and mode-only changes — are always treated as stat-only entries and bypass both bucketing paths entirely. [inferred]

1. **Chunk by hunk.** Split the file's diff on `@@ ... @@` boundaries. Group hunks into chunks until adding the next hunk would exceed `chunk_chars`. A single hunk larger than `chunk_chars` becomes its own oversized chunk; hunks are never split mid-hunk.
2. **Overflow check.** If `#chunks > max_chunks_per_file`, abort summarization for this file and emit a stat-only entry (`git diff --cached --stat` line for that path) with the note `(diff omitted: exceeded max_chunks_per_file)`. [inferred]
3. **Per-chunk summary.** Call `provider:summarize` on each chunk in parallel (respecting `concurrency`).
4. **File roll-up.** Call `provider:summarize` once with `prompt_kind = "file_rollup"`, passing the concatenated chunk summaries.
5. **On any summary error in steps 3-4:** degrade to stat-only for that file (do not abort the whole pipeline).

### Small-batched path

1. Pack small files into batches: append files one at a time to the current batch until the next file would push the batch past `small_file_batch_chars`, then start a new batch.
2. Call `provider:summarize` once per batch with `prompt_kind = "small_batch"`. The batch payload is each file's path followed by its raw diff, separated by a delimiter.
3. **On batch error:** degrade — each file in the failed batch falls back to a stat-only entry.

### Final prompt assembly

`git.lua` gains a new function `get_staged_stat(callback)` where `callback(err, stat_string)` receives the output of `git diff --cached --stat`. [inferred] `get_staged_stat` follows the same sync-wrapped-in-callback pattern as `get_staged_diff` — calls `vim.fn.system` synchronously and invokes the callback in the same call frame (no `vim.schedule` wrapping). [inferred] `input/rich.lua` calls `git.get_staged_stat` at pipeline start, before any summarization begins, and blocks final prompt assembly until the stat string is available. [inferred]

The output of `input.prepare` (passed to `provider:generate_commit_message` as `diff`) is composed of:

1. **Overall stat block** — output of `git diff --cached --stat` (fetched via `git.get_staged_stat`). Always included; gives the model a directory-level overview.
2. **Per-file sections.** For each file, one of:
   - **Large file with summary:** `### <path>` header followed by the file roll-up summary.
   - **Small-inline file:** `### <path>` header followed by the raw diff verbatim.
   - **Small-batched file:** included implicitly via its batch summary (see batch sections below).
   - **Stat-only fallback:** `### <path>` header followed by the file's `--stat` line and the note string defined at the overflow check step above.
3. **Batch summary sections** — one section per small-file batch, listing the file paths in the batch followed by the batch summary text.

The exact markdown structure is owned by `prompts.lua` and documented there.

### Concurrency

All summary calls (per-chunk, file-rollup, small-batch) are dispatched through a shared semaphore-bounded scheduler with `concurrency` permits. The scheduler is callback-based (not coroutine-based), matching the existing `http.lua` / `vim.system` pattern. [inferred] It maintains a `pending` queue (table of `{fn, args}`) and an `in_flight` integer counter. When a task completes it decrements `in_flight`; if `pending` is non-empty and `in_flight < concurrency`, it dequeues the next task and dispatches it via `vim.schedule`. [inferred] File-rollup calls for a given file are blocked on that file's per-chunk summaries completing, but rollups across files are free to interleave.

### Status UI

`picker.show_status` is updated at phase boundaries:

1. `"Analyzing staged diff..."` (bucketing)
2. `"Summarizing N files in parallel..."` — where N = count of large files + count of small-batched files (i.e., the total number of files that require at least one summary call) [inferred] (per-chunk + small-batch phase)
3. `"Composing file summaries..."` (roll-up phase)
4. `"Generating commit message..."` (existing message)

No per-file status churn.

## Error Handling

| Failure                                  | Behavior                                                                                |
|------------------------------------------|-----------------------------------------------------------------------------------------|
| Single chunk summary fails               | Mark file for stat-only fallback; cancel remaining chunks for that file.                |
| File roll-up fails                       | Stat-only fallback for that file.                                                       |
| Small-batch summary fails                | Each file in the batch falls back to stat-only.                                         |
| All summary calls fail                   | Abort with error surfaced via `utils.notify_error`; do not silently send a stat-only-only prompt. Applies only when at least one summary call was attempted; if all files are small-inline there are zero summary calls and this condition does not trigger. [inferred] |
| `git diff --cached --stat` fails         | Abort with error; the stat block is load-bearing for the prompt structure.              |

"All summary calls fail" is defined as: zero summaries succeeded across the whole invocation. A mix of successes and per-file fallbacks proceeds normally.

## Husky / Commitlint Integration

Unchanged. The existing husky-config injection in `commit.lua` runs against `provider_config` for the **final** `generate_commit_message` call only. Summary calls do not receive commitlint rules — they are not producing commit messages.

## Testing Strategy

- **Unit tests** for `input/rich.lua`:
  - Hunk-based chunking on synthetic diffs (single hunk, many small hunks, one oversized hunk).
  - Bucketing logic (large vs small-inline vs small-batched transitions).
  - Small-file batch packing (boundary cases at `small_file_batch_chars`).
  - Stat-only fallback rendering.
- **Integration tests** with a mock provider:
  - Per-chunk → roll-up flow for a multi-chunk file.
  - Per-file summary error → stat-only fallback path.
  - All-summaries-fail abort path.
  - Small-batched path with > `max_small_files_inline` files.
  - Concurrency cap honored (mock provider records max concurrent in-flight calls).
- **End-to-end smoke test** on real diffs of varying sizes with the existing test providers (a fake / echo provider in `tests/`).

## Open Questions

None at design time.

## Out of Scope (Future Work)

- A `complete()` primitive on the provider interface for general LLM use (richer features like PR descriptions, interactive refinement).
- Cross-invocation caching of summaries keyed on chunk content hash.
- Per-file status UI / progress bar.
- User-facing control to inspect the intermediate summaries before the final commit-message call.

## Refinement Status

Refinement: CONVERGED round 4

Loop summary: 4 rounds. Round 1 surfaced 2 critical + 4 important + 2 minor; round 2 surfaced 3 important + 2 minor (one carry-over); round 3 surfaced 1 important + 1 minor; round 4 surfaced 0 critical + 0 important + 2 cosmetic minors. Convergence predicate "no critical/important findings" met.
