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

All knobs live under a single `large_diff` block:

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
| `"always"` | Always run the summarization pipeline.                                                  |

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

### Integration point

`commit.lua` is unchanged except for one new step between fetching the diff and calling the provider's `generate_commit_message`:

```lua
local input = require("aicommits.input")
input.prepare(diff_data, provider, provider_config, function(err, final_payload)
  -- final_payload is what gets passed to provider:generate_commit_message
end)
```

`final_payload` is a string (the body the existing commit-prompt builder uses), so downstream code (selection UI, husky injection, commit creation) is untouched.

### Provider interface change

Every provider gains a new method:

```lua
function Provider:summarize(text, opts, callback)
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

The prompt body itself is built by `prompts.lua` based on `prompt_kind` so providers stay thin.

## Pipeline (rich mode)

### Bucketing

For each file in `diff_data.files`, classify by per-file diff size:

| Bucket            | Condition                                          | Treatment                                                          |
|-------------------|----------------------------------------------------|--------------------------------------------------------------------|
| **large**         | `#file_diff > small_file_chars`                    | chunk by hunk → per-chunk summary → file-rollup summary            |
| **small-inline**  | `#file_diff <= small_file_chars` AND small-file count ≤ `max_small_files_inline` | raw diff inlined verbatim in the final prompt                       |
| **small-batched** | `#file_diff <= small_file_chars` AND small-file count > `max_small_files_inline`  | grouped into batches ≤ `small_file_batch_chars`, one summary per batch |

The small-inline vs small-batched decision is made once per invocation, based on the total small-file count. Files don't cross between the two.

### Large-file path

1. **Chunk by hunk.** Split the file's diff on `@@ ... @@` boundaries. Group hunks into chunks until adding the next hunk would exceed `chunk_chars`. A single hunk larger than `chunk_chars` becomes its own oversized chunk; hunks are never split mid-hunk.
2. **Overflow check.** If `#chunks > max_chunks_per_file`, abort summarization for this file and emit a stat-only entry (`git diff --cached --stat` line for that path).
3. **Per-chunk summary.** Call `provider:summarize` on each chunk in parallel (respecting `concurrency`).
4. **File roll-up.** Call `provider:summarize` once with `prompt_kind = "file_rollup"`, passing the concatenated chunk summaries.
5. **On any summary error in steps 3-4:** degrade to stat-only for that file (do not abort the whole pipeline).

### Small-batched path

1. Pack small files into batches: append files one at a time to the current batch until the next file would push the batch past `small_file_batch_chars`, then start a new batch.
2. Call `provider:summarize` once per batch with `prompt_kind = "small_batch"`. The batch payload is each file's path followed by its raw diff, separated by a delimiter.
3. **On batch error:** degrade — each file in the failed batch falls back to a stat-only entry.

### Final prompt assembly

The output of `input.prepare` (passed to `provider:generate_commit_message` as `diff`) is composed of:

1. **Overall stat block** — output of `git diff --cached --stat`. Always included; gives the model a directory-level overview.
2. **Per-file sections.** For each file, one of:
   - **Large file with summary:** `### <path>` header followed by the file roll-up summary.
   - **Small-inline file:** `### <path>` header followed by the raw diff verbatim.
   - **Small-batched file:** included implicitly via its batch summary (see batch sections below).
   - **Stat-only fallback:** `### <path>` header followed by the file's `--stat` line and a one-line note (e.g. `(diff omitted: exceeded max_chunks_per_file)`).
3. **Batch summary sections** — one section per small-file batch, listing the file paths in the batch followed by the batch summary text.

The exact markdown structure is owned by `prompts.lua` and documented there.

### Concurrency

All summary calls (per-chunk, file-rollup, small-batch) are dispatched through a shared semaphore-bounded scheduler with `concurrency` permits. Implementation: a queue + counter pattern compatible with neovim's async / `vim.schedule` model. File-rollup calls for a given file are blocked on that file's per-chunk summaries completing, but rollups across files are free to interleave.

### Status UI

`picker.show_status` is updated at phase boundaries:

1. `"Analyzing staged diff..."` (bucketing)
2. `"Summarizing N files in parallel..."` (per-chunk + small-batch phase)
3. `"Composing file summaries..."` (roll-up phase)
4. `"Generating commit message..."` (existing message)

No per-file status churn.

## Error Handling

| Failure                                  | Behavior                                                                                |
|------------------------------------------|-----------------------------------------------------------------------------------------|
| Single chunk summary fails               | Mark file for stat-only fallback; cancel remaining chunks for that file.                |
| File roll-up fails                       | Stat-only fallback for that file.                                                       |
| Small-batch summary fails                | Each file in the batch falls back to stat-only.                                         |
| All summary calls fail                   | Abort with error surfaced via `utils.notify_error`; do not silently send a stat-only-only prompt. |
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
