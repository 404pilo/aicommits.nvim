---
name: reviewing-security
description: Checks that no API key or credential enters the repo, a log, or an error message, and that every shell command uses table arguments or vim.fn.shellescape.
allowed-tools: Read, Glob
---

# reviewing-security

You are reviewing changes in this repo for **security**. This lens exists because this
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

## Your lens: security

**The rule** (from `AGENTS.md` § Security Considerations, and commit 462ba29 "refactor: Use
`vim.fn.system` with table args (#17)"):

> **API Keys**: Never commit API keys or credentials to the repository.
>
> - Use environment variables for API keys, not hardcoded values
> - Validate API responses before processing
> - Handle API errors gracefully without exposing credentials

> Every shell command passes arguments as a table to `vim.fn.system`. When the string form is
> unavoidable, every interpolated value passes through `vim.fn.shellescape` first.

Read `lua/aicommits/config.lua` for the credential-resolution path and
`lua/aicommits/husky.lua` at `resolve_via_cli` for the correct `shellescape` pattern before
you judge the diff. Read `.gitignore` before you call a file committed.

**Flag if:**

- The diff adds a literal API key, token, bearer value, or service-account credential to any
  tracked file, including a test fixture. An `sk-` prefix, a `ya29.` prefix, or a long opaque
  string assigned to a name containing `key`, `token`, `secret`, or `credential` is evidence.
- The diff writes a credential value into a `vim.notify` call, an `error()` call, a returned
  error string, a `print`, or any log line. This includes interpolating a whole config table or
  a whole HTTP request table whose fields hold the key.
- The diff writes a credential into a URL query parameter instead of an authorization header.
- The diff builds a shell command as a string and interpolates a path, a filename, a branch
  name, a commit message, or any other runtime value without `vim.fn.shellescape`.
- The diff changes an existing `vim.fn.system({ ... })` table call into the string form.
- The diff adds a new file pattern that holds secrets and does not add it to `.gitignore`.

**Do not flag:**

- Environment-variable *names* in source or docs — `AICOMMITS_NVIM_OPENAI_API_KEY` and
  `OPENAI_API_KEY` are public identifiers, not secrets.
- Placeholder strings in documentation and examples, such as `"sk-..."` or `"your-api-key"`.
- A `vim.fn.system` string call with no interpolation at all, such as
  `vim.fn.system("git diff --cached --quiet")` in `lua/aicommits/git.lua`. A fixed string
  carries no injection risk.
- Formatting, quote style, and line length in any changed shell string — `./app.sh lint` owns
  those.
- A failing or missing test for the security path — `reviewing-tests` owns test coverage.
- The `memory-bank/` directory and `.env` files, which `.gitignore` already excludes.

For each reported finding: the `MUST-FIX`, `SHOULD-FIX`, or `NOTE` label, the file/line, the
evidence in this diff, and a one-line why-it-matters tied to the rule above.

Report no finding at all when the rule holds. Say `concern not present` or show what you
attacked and what held. An empty result is the correct result for most diffs.

Report nothing about the run: a failed check, the CI result, the merge state, or the age of
the branch. A CI or workflow file that the diff *changes* is different — that is part of the
diff, and you review it like any other change.
Read the diff only.
