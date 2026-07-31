# PR review contract

The single source of truth for PR review in this repo. Human-editable. Both the executor
skills (`reviewing-prs` and the lifecycle skills) and every generated `reviewing-<concern>`
lens read this file. Four sections: **the Bar**, **Deterministic gates**, **Repo invariants**,
and the **Lens registry**.

---

## 1. The Bar — what a finding must clear, and which findings hold up approval

A finding is reportable only if it clears **both** tests:

1. **Real** — concretely true in *this* diff, with evidence. Not speculative, not "could be
   cleaner," not future-hypothetical.

2. **Impactful if left unattended** — it would cause one or more of:
   - broken or incorrect behavior that ships,
   - a security, data-exposure, or compliance breach,
   - a violated **repo invariant** that section 3 marks `[blocking]` (see section 3). Section 3
     marks each invariant `[blocking]` or `[advisory]`. An invariant marked `[advisory]` is still
     reportable, at SHOULD FIX or NOTE, but not at MUST FIX,
   - an API key or credential written into the repository, a log line, or an error message,
   - a shell command built by string concatenation without `vim.fn.shellescape`,
   - a broken provider interface contract that stops a registered provider from loading,
   - a Neovim API call that fails on Neovim 0.9, the minimum supported version.

**Hard exclusion — never re-flag what a deterministic gate already owns.** See section 2 for
the exact gate commands. Style, formatting, and naming *preferences* that no repo invariant
binds are dropped.

**The first decision is binary: report or drop.** The buckets below sort what you report. They
never change whether you report it. The bias is permissive — only clear, real concerns surface.
"PR looks ok as is" is a valid and good result. No reviewer must find something.

**Report important findings only. Do not report everything you see.** The default answer is
silence. Nobody counts your findings. Drop a finding when you cannot name the damage it causes.
Drop a preference. Drop what the author sees without you. Five small remarks bury the one remark
that matters.

### Three severities: MUST FIX, SHOULD FIX, NOTE

Each reported finding gets exactly one of three labels: **MUST FIX**, **SHOULD FIX**, or **NOTE**.
The label decides **only** whether the finding holds up approval. It does not change what you
report.

**Only MUST FIX holds up approval. SHOULD FIX and NOTE never do.**

#### The MUST FIX test — all four parts must pass

Write MUST FIX only when all four parts below are true.

1. **Name the wrong result.** Complete this sentence from the diff: "After this merge, <who or
   what> gets <the wrong result> at <file>:<symbol>." You must fill every blank.
2. **Name a trigger that exists today.** Name a caller, a command, a user step, or a released
   artifact that reaches the defect now. A trigger that needs code nobody has written does not
   count.
3. **Name the line in this diff.** The line that causes the failure must sit inside this diff.
   Evidence outside the diff does not count.
4. **Match one of the six damage classes below.** The failure must be one of the six.

If any part fails, write SHOULD FIX or NOTE. The size of the fix is not part of this test. Your
opinion of the code is not part of this test.

#### The six damage classes (closed list)

1. The software gives a wrong result, or it stops.
2. Private data escapes, or a security control breaks.
3. Data is destroyed, or made unrecoverable.
4. A published interface breaks for a caller you can name.
5. A check stops running, or a check passes when it must fail.
6. An invariant marked `[blocking]` in section 3 breaks.

The list is closed. Do not add a class, do not remove one, and do not reword one.

#### Do not block on these

None of these reach MUST FIX on their own:

- Wording, tone, grammar, and voice.
- A missing test for code that already works.
- Naming, layout, duplication, and dead code.
- An input that no current caller sends.
- A risk that needs a future change to become real.
- Prose that no agent and no user follows to a wrong action.

**Most pull requests get zero MUST FIX.** A report with more than two MUST FIX entries is a
signal to read them again.

#### SHOULD FIX

The finding is real. You can name a defect. But you cannot complete all four parts of the MUST
FIX test above. Typical cases:

- The failure needs a caller that does not exist yet.
- The damage is latent.
- The evidence sits outside the diff.
- The failure is real, but it is not one of the six damage classes.

The author decides whether to fix it in this pull request.

#### NOTE

The finding is real. It clears the two report-or-drop tests above. It names no defect. Typical
cases:

- An invariant marked `[advisory]` is broken.
- The prose is unclear, but no agent or user acts wrongly on it.
- A test is missing for code that already works.

**The note cap.** Write a SHOULD FIX or a NOTE in two short sentences, maximum. One sentence for
what is wrong, one for why it matters. No third sentence, no example block, no patch. A finding
that needs more space than that is a must-fix, a should-fix, or not worth reporting — decide
which, then write it as one or drop it.

#### Dropped stays dropped

Three labels sort what you report. They never turn a dropped remark into a report. This is the
obvious failure mode of adding a lower label — watch for it. A style preference that no invariant
binds stays dropped. A remark the author sees without you stays dropped.

#### When you are not sure, use the lower label

Order: MUST FIX, then SHOULD FIX, then NOTE. When you are not sure which one fits, use the lower
one. An approval that a human must chase is more expensive than a note that a human ignores. "Not
sure" means you cannot complete the four-part test. It does not mean you completed it and think
the fix is small.

### Voice — ASD-STE100

Write every finding, digest, and receipt in ASD-STE100 Simplified Technical English:

- Write one idea in one sentence. Use a maximum of 20 words.
- Use the active voice and the present tense.
- Use one word for one meaning. Do not change the word for the same thing.
- Do not use idioms, metaphors, humor, or jargon.
- Name the file, the symbol, and the damage. Do not hedge.

This applies to all review text, local and posted. Paths, identifiers, commands, and quoted
source keep their exact spelling.

---

## 2. Deterministic gates (never re-flag)

The repo's own mechanical checks. A lens must never surface what one of these already owns; the
review is advisory and complements — never duplicates — these gates. All executor skills read
this list: `reviewing-prs` uses it as the hard-exclusion set, and the lifecycle skills
(`getting-prs-approved`, `getting-prs-merged`) run these as the CI-equivalent gate before
declaring a PR green.

- `./app.sh test` — runs the full plenary suite headless (`nvim --headless --noplugin -u
  tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"`). It owns every test pass, test
  failure, and test error in `tests/*_spec.lua`. CI runs it across a Neovim matrix of v0.9.5,
  v0.10.0, stable, and nightly, so it also owns version-matrix test breakage. It does **not**
  own a missing test file for new code — no test exists to fail, so a gate cannot see the gap.
- `./app.sh lint` — runs `stylua --check lua/ tests/` with `.stylua.toml`. It owns indentation
  (2 spaces), line length (120 characters), quote style (double preferred), call parentheses,
  and all whitespace and layout. It does **not** own identifier names, LuaDoc presence, or
  module structure — stylua reformats code, it never renames or documents anything.
- `./app.sh ci` — runs `./app.sh test` then `./app.sh lint` in sequence. This is the single
  command `CONTRIBUTING.md` and `.github/PULL_REQUEST_TEMPLATE.md` tell contributors to run.
  It owns nothing beyond the union of the two gates above.

---

## 3. Repo invariants

The mined, repo-specific rules that must always hold. Each lens ties its findings back to one
of these (or to a doc the invariant points at). Keep them concrete and falsifiable.

Each invariant bullet starts with `[blocking]` or `[advisory]`. A `[blocking]` invariant is
damage class 6 in section 1: a diff that breaks it can be a MUST FIX. An `[advisory]` invariant
can reach SHOULD FIX at most. An invariant with no marker reads as `[advisory]`.

- `[blocking]` No API key, token, or credential is ever hardcoded in source, committed to the
  repo, or written into a log line, error message, or test fixture. Keys come from environment
  variables only, in the priority order `AICOMMITS_NVIM_OPENAI_API_KEY` then `OPENAI_API_KEY`.
  Source: `AGENTS.md` § Security Considerations.
- `[blocking]` Every shell command passes arguments as a table to `vim.fn.system`, for example
  `vim.fn.system({ "git", "diff", "--cached" })`. When the string form is unavoidable, every
  interpolated value passes through `vim.fn.shellescape` first, as `lua/aicommits/husky.lua`
  does at `resolve_via_cli`. Source: commit 462ba29 "refactor: Use `vim.fn.system` with table
  args (#17)".
- `[blocking]` Every new feature and every new provider ships with tests in `tests/*_spec.lua`
  that cover the success path and the error path, mock all external calls (HTTP, git, system),
  and clean up mocks in `after_each`. Source: `AGENTS.md` § Testing Instructions, and
  `CONTRIBUTING.md` § Checklist for New Providers.
- `[blocking]` Identifiers follow the repo convention: `snake_case` for modules and functions,
  `UPPER_SNAKE_CASE` for constants, and a leading `_` for private functions. Every public
  function carries a LuaDoc block with `@param` and `@return`. Source: `AGENTS.md` § Code Style
  Guidelines, restated in `CONTRIBUTING.md` § Naming and § Documentation.
- `[advisory]` Every provider module implements the required interface — `name`,
  `generate_text`, and `validate_config` — is created through `base.new({ name = "..." })`,
  ends with `return M`, registers itself in `lua/aicommits/providers/init.lua`, and adds its
  defaults to `lua/aicommits/config.lua`. Source: `CONTRIBUTING.md` § Provider Interface
  Requirements and § Checklist for New Providers.
- `[advisory]` Asynchronous work uses the error-first callback signature
  `callback(error, result)`, wraps risky operations in `pcall`, and wraps user-interface calls
  inside a callback in `vim.schedule`. Source: `AGENTS.md` § Error Handling Pattern and
  § Async Callback Pattern, plus `CONTRIBUTING.md` § Troubleshooting Common Mistakes items 3
  and 4.
- `[advisory]` Code runs on Neovim 0.9 and later. CI tests v0.9.5, v0.10.0, stable, and
  nightly. Source: `.github/workflows/ci.yml` matrix, and `AGENTS.md` § Project Overview.

---

## 4. Lens registry

The authoritative list of active lenses. `reviewing-prs` reads this table to decide which
lenses to fan out for a given diff.

| name | when | skill path |
|------|------|------------|
| reviewing-security | `lua/**/*.lua`, `scripts/**`, `app.sh`, `.github/workflows/**` | `.claude/skills/reviewing-security` |
| reviewing-provider-contract | `lua/aicommits/providers/**`, `lua/aicommits/config.lua`, `adds-provider` | `.claude/skills/reviewing-provider-contract` |
| reviewing-error-handling | `lua/**/*.lua` | `.claude/skills/reviewing-error-handling` |
| reviewing-tests | `lua/**/*.lua`, `tests/**/*.lua`, `adds-feature` | `.claude/skills/reviewing-tests` |
| reviewing-naming | `lua/**/*.lua`, `renames-symbol` | `.claude/skills/reviewing-naming` |
