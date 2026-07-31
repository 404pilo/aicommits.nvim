---
name: reviewing-error-handling
description: Checks that risky operations use pcall, asynchronous work uses the error-first callback signature, and user-interface calls inside callbacks run in vim.schedule.
allowed-tools: Read, Glob
---

# reviewing-error-handling

You are reviewing changes in this repo for **error handling**. This lens exists because this
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

## Your lens: error handling

**The rule** (from `AGENTS.md` § Error Handling Pattern and § Async Callback Pattern, plus
`CONTRIBUTING.md` § Troubleshooting Common Mistakes items 3, 4, and 6):

> Use `pcall` for risky operations. On failure, notify with `vim.log.levels.ERROR` and return.

> Error-first callback pattern (node.js style): `callback(error, result)`. Success is
> `callback(nil, messages)`. Failure is `callback("Error message", nil)`.

> Wrap user-interface updates inside an asynchronous callback in `vim.schedule`.

> Do not assume a response is always successful. Check each step: decode with `pcall`, check
> `response.error`, then check the result field exists and is not empty.

Read `lua/aicommits/http.lua` and `lua/aicommits/providers/base.lua` for the current
asynchronous contract before you judge the diff. `http.post` already wraps its callback in
`vim.schedule`; a callback reached only through `http.post` needs no second wrapper.

**Flag if:**

- The diff calls `vim.json.decode` on an external response without `pcall`, so malformed
  input raises an uncaught error.
- The diff reads a nested field of a decoded API response without checking the parent exists,
  for example `response.choices[1].message.content` with no check that `response.choices` is
  present and not empty.
- The diff calls a callback with the arguments reversed, such as `callback(result, error)`
  or `callback(messages)` where the interface expects `callback(error, result)`.
- The diff adds an error path that returns without calling the callback at all, so the caller
  waits forever.
- The diff calls `vim.notify`, opens a window, or writes to a buffer inside a callback that
  does not already run through `vim.schedule`, for example a raw `vim.fn.jobstart` handler
  such as the one in `lua/aicommits/providers/vertex.lua`.
- The diff swallows an error: it catches a failure with `pcall` and then continues with a
  `nil` or empty value, and the caller cannot tell the operation failed.
- The diff checks `vim.v.shell_error` after a `vim.fn.system` call is removed, or removes an
  existing `vim.v.shell_error` check, so a failed command now reads as success.

**Do not flag:**

- The wording of an error message. Voice and grammar never reach a finding on their own.
- A missing test for an error path — `reviewing-tests` owns test coverage.
- A credential inside an error message — `reviewing-security` owns that.
- A provider that omits a whole interface method — `reviewing-provider-contract` owns that.
- Names of error variables, such as `err` against `error` — `reviewing-naming` owns naming.
- A callback already reached through `lua/aicommits/http.lua`, which schedules for you. A
  second `vim.schedule` there is harmless, not a finding.
- Formatting and indentation of a `pcall` block — `./app.sh lint` owns those.

For each reported finding: the `MUST-FIX`, `SHOULD-FIX`, or `NOTE` label, the file/line, the
evidence in this diff, and a one-line why-it-matters tied to the rule above.

Report no finding at all when the rule holds. Say `concern not present` or show what you
attacked and what held. An empty result is the correct result for most diffs.

Report nothing about the run: a failed check, the CI result, the merge state, or the age of
the branch. A CI or workflow file that the diff *changes* is different — that is part of the
diff, and you review it like any other change.
Read the diff only.
