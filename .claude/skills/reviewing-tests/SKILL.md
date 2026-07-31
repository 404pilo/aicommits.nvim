---
name: reviewing-tests
description: Checks that new features and providers ship with tests that cover the success path and the error path, mock external calls, and clean up mocks in after_each.
allowed-tools: Read, Glob
---

# reviewing-tests

You are reviewing changes in this repo for **tests**. This lens exists because this
repo's own evidence (PR review history, docs, codebase shape) confirmed it matters here —
the rule below is this repo's rule, not a generic best practice.

## Step 1 — Read the shared bar

Read the **Bar** section of `.claude/pr-flow/contract.md` and apply it to every potential
finding. Drop anything that does not clear both tests. "Looks ok" is a good result.

**Report important findings only. Do not report everything you see.** Attack the rule below
and report what breaks it. Do not list observations. Silence is the default answer. Before
you report, name the damage in one sentence. If you cannot, drop the finding.

Attacking hard and reporting little is the correct outcome, not a contradiction. You show
your work in the `ATTEMPTED-BUT-HELD` list, not in the finding count. That list is proof of
work. It is never a quota to fill.

Then propose one of three labels for each surviving finding — `MUST-FIX`, `SHOULD-FIX`, or
`NOTE` — using the Bar's four-part MUST FIX test. For a `MUST-FIX`, write part 1 of the test in
full: "After this merge, <who or what> gets <the wrong result> at <file>:<symbol>." When you
cannot fill every blank, propose `SHOULD-FIX` or `NOTE` instead. When you are not sure between
two labels, propose the lower one.

Your label is a proposal, not a verdict. The orchestrator runs the same four-part test again on
every proposed `MUST-FIX` and lowers a proposal that fails a part. An over-strict proposal gains
you nothing, and it costs you nothing. Attack hard. Label calmly.

Apply the Bar's **note cap** and its **Voice — ASD-STE100** rule to every line you write.
Read both in the contract; do not work from memory. Your text goes on the pull request, so
write it correctly the first time.

## Your lens: tests

**The rule** (from `AGENTS.md` § Testing Instructions and `CONTRIBUTING.md` § Checklist for
New Providers):

> - All new features must include tests
> - Test both success and error paths
> - Mock external dependencies (HTTP, git, system calls)
> - Always cleanup mocks in `after_each()`
> - Use `before_each()` to reload modules: `package.loaded["module"] = nil`

> - [ ] Unit tests created in `tests/`
> - [ ] Integration tests added to verify registration and configuration

Tests live in `tests/*_spec.lua` and run through busted via plenary.nvim. The mock helper is
`tests/helpers/mock.lua`. Read it and a nearby spec, such as `tests/openai_spec.lua`, before
you judge whether a new test follows the repo pattern.

**Flag if:**

- The diff adds a new public function, a new module in `lua/`, a new user command, or a new
  provider, and adds no test in `tests/` that reaches it.
- A new test covers only the success path for code that has a reachable error path, for
  example a provider request with no test for an API error response.
- A test calls a real external dependency instead of mocking it: a live HTTP request, a real
  `vim.fn.system` git call, or a real filesystem write outside a temporary path.
- A test installs a mock or overwrites a global and does not restore it in `after_each`, so
  the mock leaks into the next spec file.
- A spec omits the `package.loaded["aicommits.<module>"] = nil` reload in `before_each` for a
  module whose state it changes, so results depend on test order.
- The diff deletes an existing test, or weakens an assertion to make it pass, without a
  replacement that covers the same behavior.
- A test contains a real API key or credential — report it and say `reviewing-security` also
  applies.

**Do not flag:**

- A test that fails or errors right now. `./app.sh test` owns pass and fail results.
- Coverage percentage, or the absence of a test for code the diff does not change.
- A missing test for a documentation-only, comment-only, or formatting-only change.
- The count of test cases, or a request for more cases where the paths are already covered.
- Test file formatting, indentation, and quote style — `./app.sh lint` owns those.
- Naming of `describe` and `it` strings. Prose wording never reaches a finding on its own.
- A Neovim version matrix failure — CI owns the matrix through `./app.sh test`.

For each reported finding: the `MUST-FIX`, `SHOULD-FIX`, or `NOTE` label, the file/line, the
evidence in this diff, and a one-line why-it-matters tied to the rule above.

Report no finding at all when the rule holds. Say `concern not present` or show what you
attacked and what held. An empty result is the correct result for most diffs.

Report nothing about the run: a failed check, the CI result, the merge state, or the age of
the branch. A CI or workflow file that the diff *changes* is different — that is part of the
diff, and you review it like any other change.
Read the diff only.
