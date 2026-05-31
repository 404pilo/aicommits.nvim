# Rich-Input Chunking Improvements: Self-Contained Chunks & Grow-Before-Demote

**Status:** Draft
**Date:** 2026-05-31
**Branch:** `worktree-issue-20-rich-input` (work lands here, then a **new PR** against `main` — PR #22 is already merged)
**Credit:** Both improvements originate from contributor **@Borber**'s fork
(<https://github.com/Borber/aicommits.nvim>, `split_diff_chunks` / `choose_chunk_size` in
`input.lua` @ `f0b43f2`). Every commit produced from this spec MUST carry:

```
Co-Authored-By: Borber <30563826+Borber@users.noreply.github.com>
```

## Problem

The rich-input summarization pipeline (`lua/aicommits/input/rich.lua`) splits a large file's
diff into hunk-boundary chunks, summarizes each chunk, then rolls the chunk summaries into one
file summary. Two weaknesses degrade summary quality for large files:

1. **Chunks 2..N lose filename context.** `split_into_chunks` emits the `diff --git` / `index` /
   `---` / `+++` header block only inside the first chunk. Every later chunk is a bare run of
   `@@` hunks, so the summarizer model no longer knows which file it is reading.

2. **Over-cap files lose all detail.** When a file would split into more than
   `max_chunks_per_file` chunks at the configured `chunk_chars`, the file is **demoted to
   stat-only** (`"(diff omitted: exceeded max_chunks_per_file)"`) and contributes no summary at
   all — a significant information loss for the largest, often most important, files.

## Goal

Fold @Borber's two fixes into our pipeline, integrated with our existing bucketing/scheduler
architecture and our existing hunk-boundary packing (which we keep — we are NOT adopting
Borber's line-level splitting):

1. **Change 1 — Replay the file header in every chunk.** Make each emitted chunk
   self-contained: `<file_header_block>\n<hunk(s)>`, where the header is the slice of the file
   diff before the first `^@@` line.
2. **Change 2 — Grow chunk size before demoting.** When chunking at `chunk_chars` would exceed
   `max_chunks_per_file`, recompute the chunk size as `math.ceil(#file_diff / max_chunks_per_file)`
   and re-chunk at the coarser size, so the file still gets summarized.

## Non-Goals

- No change to bucketing thresholds, concurrency, the rollup step, prompt templates, or the
  default-vs-rich dispatch.
- No change to `stat_only` routing for binary / empty / pure-rename files — those continue to be
  detected upstream via `is_binary` / `is_empty` in `split_diff_by_file` and never reach the
  large-file path.
- No drive-by refactors. Adjacent things Borber's fork does that we are deliberately **not**
  folding in: lockfile exclusion in `git.lua`, a "Do not mention chunk numbers" chunk prompt,
  and his abort-on-any-summary-error failure model. These are out of scope for these two changes.

## Alignment With Borber's Fork

A cross-reference of Borber's fork confirmed we are solving the **same two problems** with the
**same core mechanisms**, with two deliberate decisions recorded here:

| Aspect | Borber | This spec |
|---|---|---|
| Header definition (pre-first-`@@` slice) | same | same |
| Header replayed on every chunk | yes | yes |
| **Header counted toward `chunk_chars` budget** | yes (charged) | **yes (charged) — matches Borber** |
| Grow formula | `math.ceil(#text / max_chunks)` | identical |
| `#text` in the formula | full per-file diff incl. header | identical (`local_entry.diff`) |
| **Overflow after growing** | soft cap — emit > cap, never demote | **demote to stat-only (hard ceiling) — diverges from Borber** |
| Chunk packing granularity | line-level | **hunk-level (our existing, tested contract — preserved)** |

The **overflow policy is the one place we diverge from Borber**: Borber never demotes; we keep a
hard ceiling so a pathological file cannot silently spawn an unbounded number of summary calls.
This is an intentional, cost-bounding decision and is called out explicitly here because the work
is otherwise credited to Borber.

## Design

### Component 1 — `M.split_into_chunks(file_diff, chunk_chars)` (modified)

Today this splits on `^@@` and packs hunks up to `chunk_chars`, with the header riding inside
chunk 1. New behavior:

1. **Separate** `file_diff` into a `header` block (all lines before the first `^@@` line; may be
   `""`) and an ordered list of `hunks` (each `^@@…` block).
2. **Pack hunks into chunks at the `chunk_chars` budget, charging the header to the budget.**
   Each chunk is seeded with the header, so `current_len` starts at `#header` (which is `0` when
   the header is empty). The separator `\n` is charged exactly once per hunk, at the moment that
   hunk is added — never pre-charged into the seed. Concretely [inferred]:
   - **First hunk of a chunk** is always added regardless of budget (preserving today's contract
     that an oversized single hunk still becomes its own chunk). Its cost is
     `(#header > 0 and 1 or 0) + #hunk` — one separator byte only when a non-empty header precedes
     it, none when the header is empty. After adding, `current_len = #header + (#header > 0 and 1 or 0) + #hunk`.
     That chunk may exceed `chunk_chars`.
   - **Each subsequent hunk** costs `1 + #hunk` (one separator byte plus the hunk). It is added
     while `current_len + 1 + #hunk <= chunk_chars`; otherwise the chunk is flushed and a new chunk
     is started (re-seeded with the header, `current_len` reset to `#header`).

   The `current_len + 1 + #hunk <= chunk_chars` packing test therefore applies **only to non-first
   hunks**; the first separator is charged inside the first-hunk cost above and is never
   double-counted [inferred].
3. **Prepend** `header .. "\n"` to every flushed chunk when the header is non-empty.

Edge cases:
- **Header-less input** (header `== ""`, as in the existing unit-test fixtures that start with
  `@@`): prepend is a no-op and the header contributes `0` to the budget, so packing is
  byte-for-byte identical to today — existing `split_into_chunks` tests keep passing unchanged.
- **No hunks** (header-only diff): return `{}`. Such diffs are binary/empty/pure-rename and are
  already routed to `stat_only` upstream, so the large-file path never calls this on them.

### Component 2 — `M.chunk_file_capped(file_diff, chunk_chars, max_chunks)` (new pure helper)

Encapsulates the grow policy so it is unit-testable without the async pipeline:

```lua
function M.chunk_file_capped(file_diff, chunk_chars, max_chunks)
  local chunks = M.split_into_chunks(file_diff, chunk_chars)
  if #chunks > max_chunks then
    local grown = math.ceil(#file_diff / max_chunks)
    chunks = M.split_into_chunks(file_diff, grown)
  end
  return chunks
end
```

- `#file_diff` is the full per-file diff including the header (matches Borber and our
  `local_entry.diff`).
- The function returns the chunk list and does **not** itself demote — for a pathological file
  (a few hunks each larger than `grown`), the count can still exceed `max_chunks`. The
  demote decision stays with the caller (Component 3).
- **Precondition:** `max_chunks` must be a **positive integer** (`>= 1`). `chunk_file_capped`
  assumes this validated precondition — it does **not** guard against `0` or non-number values,
  since doing so would make `grown = math.ceil(#file_diff / max_chunks)` divide by zero or raise an
  arithmetic-type error [inferred]. The precondition is enforced at config-validation time, not in
  this helper (see below) [inferred].

**Config validation (`config.lua`).** `config.lua` validation already checks
`large_diff.concurrency`; add a parallel check that `large_diff.max_chunks_per_file` is a positive
integer, validated the same way, so the precondition above is guaranteed before any large-file diff
reaches `chunk_file_capped` [inferred].

### Component 3 — `prepare()` large-file branch integration (`rich.lua` ~370-382)

- Replace `local chunks = M.split_into_chunks(local_entry.diff, ld_cfg.chunk_chars)` with
  `local chunks = M.chunk_file_capped(local_entry.diff, ld_cfg.chunk_chars, ld_cfg.max_chunks_per_file)`.
- **Keep** the existing `if #chunks > ld_cfg.max_chunks_per_file then … demote to stat-only …`
  block as the residual **hard ceiling** — it now fires only when even the grown re-chunk still
  overflows. Update the explanatory comment (and optionally the `stat_line` wording) to reflect
  "grown, then demoted because still over cap" instead of "exceeded max_chunks_per_file".
- Everything downstream (per-chunk `summarize` with `prompt_kind = "chunk"`, the `file_rollup`
  step, error handling, `summary_attempts`/`summary_successes` accounting) is unchanged. Each
  chunk now carries its file header, giving the `chunk` prompt reliable filename context.

### Behavior matrix

| File shape | Before | After |
|---|---|---|
| Normal multi-chunk file | header in chunk 1 only | header replayed in every chunk |
| Would exceed cap at `chunk_chars`, packs fine when grown | demoted to stat-only (lost detail) | grown + summarized |
| A few hunks each larger than the grown size, still > cap | demoted | **still demoted** (hard ceiling) |
| Binary / empty / pure rename | stat-only | stat-only (unchanged) |

## Test Plan (`tests/input_rich_spec.lua`)

All assertions run under the existing headless plenary harness. Capture the baseline pass/fail
count **before** any change (see Verification) and confirm no regressions after each change.

**Change 1 — header replay** (in the `split_into_chunks()` describe block):
- Build a file diff with a real header (`diff --git a/big.lua b/big.lua`, `index …`, `--- …`,
  `+++ …`) followed by 3+ hunks, and a `chunk_chars` small enough (header + one hunk) to force
  one hunk per chunk → assert `#chunks >= 3` and **every** chunk matches `^diff %-%-git`.
- Sanity: assert the existing header-less fixtures still produce the same chunk counts
  (regression guard — these tests already exist and must stay green).

**Change 2 — grow** (new `chunk_file_capped()` describe block):
- Build a uniform-small-hunk file where `#chunks at chunk_chars > max_chunks`, but the grown
  size packs to `<= max_chunks`. Assert:
  1. `#rich.chunk_file_capped(diff, chunk_chars, max) <= max`.
  2. `#rich.chunk_file_capped(diff, chunk_chars, max) == #rich.split_into_chunks(diff, math.ceil(#diff / max))`
     (proves the grown size was actually used).
  3. `rich.bucket_files({entry}, cfg).large` contains the file (it is a large, summarizable file,
     not `stat_only`).
  4. **Integration through `prepare()` (proves the call-site was swapped) [inferred]:** drive a
     diff that exceeds the cap at `chunk_chars` but fits after growth through `prepare()` and assert
     that `provider:summarize` **IS** called for that file (i.e. it was chunked and summarized, not
     demoted), AND that the final assembled payload does **NOT** contain the overflow stat-only note.
     This assertion is what proves `prepare()` actually calls `chunk_file_capped` instead of the old
     `split_into_chunks`; assertions 1–3 alone can pass while the `prepare()` call site is still
     unchanged [inferred].

**Change 2 — hard-ceiling fallback** (locks the divergence decision):
- Build `max_chunks + 1` **equal-size** hunks (size `H`) chosen so that, at the grown size, any two
  hunks plus the charged header + separator exceed `grown` — i.e. each chunk holds at most one hunk
  even after growing, so the grown pass still emits `max_chunks + 1` chunks (> `max_chunks`),
  exercising the residual demote-to-stat-only path. Note that "each hunk larger than `grown`" is
  **impossible** here: `grown = math.ceil(#diff / max_chunks)` is computed from the full diff that
  already contains every hunk, so no hunk can exceed `grown` — the constraint must instead be on the
  *packing* (two-hunks-don't-fit), not on a single hunk's size [inferred].
  - **Why this is constructible [inferred]:** with `N = max_chunks + 1` equal hunks of size `H`,
    `grown = math.ceil(N*H / max_chunks) ≈ H + H/max_chunks < 2H`, so a second hunk never fits
    (`H + 1 + H = 2H + 1 > grown`) while the first hunk of each chunk is always admitted; the grown
    re-chunk therefore yields exactly `N = max_chunks + 1` chunks.
  - Assert `#rich.chunk_file_capped(diff, chunk_chars, max) > max` (demonstrating the caller will
    demote to stat-only).
  - The test SHOULD assert the computed `grown` (`== math.ceil(#diff / max)`) and the resulting
    chunk count (`== max + 1`) explicitly — or use a small helper fixture with asserted hunk sizes —
    so the construction is independently verifiable rather than relying on a hand-waved size
    choice [inferred].

**Config validation — `tests/config_spec.lua`** (locks the new `max_chunks_per_file` precondition) [inferred]:
- Mirror the existing `large_diff.concurrency` validation tests, asserting that each of these
  invalid `large_diff.max_chunks_per_file` values is rejected with an error whose message references
  `large_diff.max_chunks_per_file` [inferred]:
  1. `0` (not `>= 1`).
  2. A fractional number, e.g. `2.5` (not an integer).
  3. A non-number value, e.g. a string (wrong type).
- Confirm a valid positive integer (e.g. `3`) passes validation without error [inferred].

**Existing overflow fixtures in `tests/input_rich_spec.lua` (mandatory updates) [inferred]:**
- Existing `prepare()` overflow fixtures whose diffs now **fit after growth** must be **rewritten as
  grow-success coverage** — assert the file is summarized (`provider:summarize` called) and the
  payload no longer carries the stat-only note, rather than asserting the old demotion [inferred].
- Residual **hard-ceiling** tests must be reworked to use the same construction as the "Change 2 —
  hard-ceiling fallback" case above: `max_chunks + 1` **equal-size** hunks chosen/asserted so any two
  hunks plus the charged header + separator exceed `grown`, producing exactly `max_chunks + 1` chunks
  after growth (> `max_chunks`), so they continue to exercise the demotion path that survives the grow
  step. Do **not** construct these from "each hunk larger than `grown`" — that is impossible, since
  `grown = math.ceil(#diff / max_chunks)` is derived from the full diff containing every hunk (see the
  hard-ceiling fallback case for the constructibility proof) [inferred].
- If the `stat_line` wording is changed from `"(diff omitted: exceeded max_chunks_per_file)"` (see
  Component 3), the **new exact wording is mandatory** and every test that asserts on the stat-only
  note must assert the new string verbatim [inferred].

## Verification

1. **Baseline first.** Run the suite and record pass/fail/error counts before editing:
   `nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"`.
   This worktree already carries the env-test fixes (`2e84b37`), so the expected baseline here is
   **0 failures** (the "6 failures on `main`" referenced in the task brief are because those
   fixes are not on `main` yet).
2. After Change 1 + its tests: re-run; confirm new tests pass and total failures == baseline.
3. After Change 2 + its tests: re-run; confirm new tests pass and total failures == baseline.
4. Stylua: `./app.sh lint` must pass (`stylua --check lua/ tests/`); run `./app.sh format` if needed.

## Commits & PR

- **Two commits**, one per change (implementation + its tests), each carrying the
  `Co-Authored-By: Borber <30563826+Borber@users.noreply.github.com>` trailer.
- Push to `origin/worktree-issue-20-rich-input`.
- Open a **new PR** against `main` (PR #22 is already merged), noting both improvements and the
  intentional overflow-policy divergence from Borber.

## Refinement Status

Refinement: CONVERGED round 5 [inferred]

Refined via `relay:refine:spec` (acpx codex) — `spec-simulator` critic + `spec-fixer`.
Rounds: R1 4 important → R2 1 important → R3 1 important → R4 1 important → R5 clean (0/0/0).
Sidecar findings: `.relay-refine/round-{1..5}-findings.yaml`. [inferred]
