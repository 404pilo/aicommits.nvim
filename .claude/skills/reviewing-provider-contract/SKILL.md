---
name: reviewing-provider-contract
description: Checks that a provider module implements the required interface, is created through base.new, returns M, registers itself, and adds its defaults to config.lua.
allowed-tools: Read, Glob
---

# reviewing-provider-contract

You are reviewing changes in this repo for **provider contract**. This lens exists because this
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

## Your lens: provider contract

**The rule** (from `CONTRIBUTING.md` § Provider Interface Requirements, § Checklist for New
Providers, and § Troubleshooting Common Mistakes):

> Required methods: `name`, `generate_commit_message`, `validate_config`.
> Optional methods with defaults: `get_auth_headers`, `get_capabilities`.

> - [ ] Provider file created in `lua/aicommits/providers/`
> - [ ] All required methods implemented
> - [ ] Provider registered in `lua/aicommits/providers/init.lua`
> - [ ] Default configuration added to `lua/aicommits/config.lua`
> - [ ] Documentation updated in README.md (add to supported providers list)
> - [ ] Health check validates your provider (`:checkhealth aicommits`)

Named pitfalls from the same document: a missing `return M`; a `base.new({})` call with no
`name`; assigning `M.name` after creation; a callback with the arguments in the wrong order.

Read `lua/aicommits/providers/base.lua` for the current interface, and
`lua/aicommits/providers/openai.lua` or `lua/aicommits/providers/gemini.lua` as reference
implementations, before you judge the diff. The base module now defines `generate_text` with
an envelope, and `M.Provider:generate_commit_message` calls it — check the diff against the
base file as it exists, not against the older prose in `CONTRIBUTING.md`.

**Flag if:**

- A new or changed file in `lua/aicommits/providers/` omits a required interface method, or
  gives one a signature that does not match `lua/aicommits/providers/base.lua`.
- A provider module does not end with `return M`.
- The diff calls `base.new({})` with no `name` field, or assigns `M.name` after the
  `base.new` call.
- A new provider file is added but `lua/aicommits/providers/init.lua` gains no matching
  `M.register` call, so the provider never loads.
- A new provider is registered but `lua/aicommits/config.lua` gains no default configuration
  block for it.
- The diff changes the interface in `lua/aicommits/providers/base.lua` and leaves an existing
  provider in `lua/aicommits/providers/` unchanged, so that provider now breaks.
- A provider's `validate_config` accepts a configuration that its `generate_text` then fails
  on, for example it never checks a field the request path reads.

**Do not flag:**

- The choice of model name, endpoint URL, or default parameter values inside a provider. These
  are the author's decision, not an interface rule.
- Credential handling inside a provider — `reviewing-security` owns that.
- Callback argument order, `pcall` use, and `vim.schedule` use — `reviewing-error-handling`
  owns those, including pitfalls 3 and 4 in `CONTRIBUTING.md`.
- A missing test for a new provider — `reviewing-tests` owns that.
- Function and constant names inside a provider — `reviewing-naming` owns those.
- Formatting and layout in provider files — `./app.sh lint` owns those.
- A failing provider test — `./app.sh test` owns that.

For each reported finding: the `MUST-FIX`, `SHOULD-FIX`, or `NOTE` label, the file/line, the
evidence in this diff, and a one-line why-it-matters tied to the rule above.

Report no finding at all when the rule holds. Say `concern not present` or show what you
attacked and what held. An empty result is the correct result for most diffs.

Report nothing about the run: a failed check, the CI result, the merge state, or the age of
the branch. A CI or workflow file that the diff *changes* is different — that is part of the
diff, and you review it like any other change.
Read the diff only.
