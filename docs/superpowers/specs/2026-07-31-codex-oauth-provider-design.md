# Codex OAuth Provider Design

**Date:** 2026-07-31
**Status:** Approved for implementation
**Topic:** A `codex` provider that authenticates by reading the local OpenAI Codex CLI OAuth session, so requests spend the user's ChatGPT subscription quota instead of per-token API credits.

---

## 1. Motivation and scope

aicommits.nvim currently bills every commit message to an API key: `openai` (per-token),
`vertex` (GCP project), `gemini-api` (AI Studio key). Users who already pay for a ChatGPT
subscription and have the Codex CLI installed hold a local OAuth session that the ChatGPT
Codex backend accepts. This provider reuses that session.

**Driver: cost.** The point is spending subscription quota, not saving a keystroke.

**In scope:** a new `codex` provider that reads `~/.codex/auth.json` read-only, calls the
ChatGPT Codex backend, and returns exactly one commit message.

**Out of scope, deliberately:**

- Any PKCE / login / device-code flow of our own. We never mint tokens.
- Any token refresh. We never write `auth.json`.
- Live streaming into the UI. The response is buffered and returned as final text.
- Multi-candidate generation. Capped at 1, documented.

---

## 2. Empirical findings (from validation spikes)

Everything in this section was verified against the live backend on a real ChatGPT account
during four validation spikes. It is not inferred from documentation — several published
claims turned out to be wrong here, so treat this section as the authority.

### 2.1 Credential file

`$CODEX_HOME/auth.json`, defaulting to `~/.codex/auth.json`. Mode `0600`. Written by
codex-cli (observed version 0.146.0). Structure:

```json
{
  "auth_mode": "chatgpt",
  "OPENAI_API_KEY": null,
  "tokens": {
    "id_token": "…",
    "access_token": "…",
    "refresh_token": "…",
    "account_id": "…"
  },
  "last_refresh": "…"
}
```

`account_id` is a plain field on `tokens`. **No JWT decoding is required** to obtain it.

The Codex CLI rewrites this file when it refreshes (~8 day cadence). Any write by us races
that and can clobber a live session, so this provider is **strictly read-only**.

The `codex` CLI has **no** token-printing subcommand — there is no equivalent of
`gcloud auth application-default print-access-token`. This is why the provider reads the
file directly rather than shelling out, which is the convention `vertex.lua` uses.

### 2.2 Endpoint

`https://chatgpt.com/backend-api/codex/responses` — **not** `api.openai.com`. This is an
undocumented internal endpoint.

Cloudflare TLS/JA3 fingerprint blocking has been reported against this endpoint for other
tools (notably LiteLLM). It **did not reproduce** on the development machine with plain
`curl`. Treat a sudden run of transport failures as a plausible fingerprinting block, not
necessarily a bug in this provider.

### 2.3 Request shape

Mandatory fields — omitting either yields HTTP 400:

- `stream: true`
- `store: false` (omitting gives `{"detail":"Store must be set to false"}`)

Accepted:

| Field | Notes |
| --- | --- |
| `model` | Only `gpt-5.6-terra` and `gpt-5.6-luna` worked on the test account. |
| `reasoning: { effort: … }` | Nested form only. |
| `text: { verbosity: … }` | `low` \| `medium` \| `high`. Genuinely applied. |
| `instructions` (top level) | Works, but lower precedence than a `developer` role. |
| `input[].role` = `system` / `developer` / `user` | |

Rejected outright, **regardless of reasoning effort**:

`temperature`, `top_p`, `max_output_tokens`, `max_tokens`, and a flat top-level
`reasoning_effort`.

> A hypothesis that `reasoning: {effort: "none"}` would unlock `temperature` — based on
> OpenAI's public docs stating temperature/top_p/logprobs are supported when effort is
> `none` — was **tested and disproved**. With `effort: "none"` the backend still returns
> `400 {"detail":"Unsupported parameter: temperature"}`. The ChatGPT Codex backend
> maintains its own allowlist and rejects these fields before they reach the model API.
> Do not re-add them.

All `*-codex` model names are rejected with "not supported when using Codex with a ChatGPT
account".

`assistant`-role messages cannot carry `input_text` parts (only `output_text` / `refusal`).
Irrelevant to us — we send only `developer` and `user` — but noted so nobody adds one.

`verbosity` is the **only** working length control, and it does work: on an identical
prompt, `low` produced 817 characters and `high` produced 3918.

### 2.4 Role precedence

Proven by probe: a `developer`-role message in `input` beat a conflicting top-level
`instructions` value. The chain is:

```
developer / system in input  >  top-level instructions  >  user
```

This matters for security — see §6.

### 2.5 Error envelopes

The backend returns **two different shapes**, and they mean different things:

- **Flat** `{"detail": "…"}` — the backend allowlist refused the field entirely. The
  parameter is not supported here at all.
- **Rich** `{"error": {"message", "type", "param", "code"}}` — the field was accepted but
  the value was invalid.

The provider must normalize both, and the surfaced message should preserve the distinction
because the remedy differs (drop the field vs. fix the value).

---

## 3. Files to touch

| File | Change |
| --- | --- |
| `lua/aicommits/providers/codex.lua` | New. The provider. |
| `lua/aicommits/providers/init.lua` | Register `codex` in `M.setup()`. |
| `lua/aicommits/config.lua` | Add the `codex` defaults block. |
| `tests/codex_spec.lua` | New. See §8. |
| `README.md` | Document the provider and its risk disclosure (§9). |

`lua/aicommits/health.lua` picks the provider up automatically — no change.

**`lua/aicommits/http.lua` and `lua/aicommits/request.lua` are unchanged.** `http.lua` uses
buffering `curl -s` (no `-N`), so the mandatory SSE stream arrives as one blob in
`result.body`. Streaming collapses into a parsing problem inside the provider. This is the
single most important structural consequence of §2.3 — resist any urge to add streaming
plumbing to the shared transport.

---

## 4. Authentication

A private, **synchronous** helper:

```lua
-- @return string|nil token, string|nil account_id, string|nil err
local function get_access_token(config)
```

Steps:

1. Resolve `vim.env.CODEX_HOME` or fall back to `~/.codex`.
2. Read `auth.json`. **Never write it.**
3. `vim.json.decode` under `pcall`.
4. Pull `tokens.access_token` and `tokens.account_id` as plain fields.
5. On any failure return the error
   ``"Codex credentials not found. Run: `codex login`"``.

**No single-flight machinery, no cache** — unlike `vertex.lua`. This is a conscious
deviation with two reasons: a file read is ~1ms, so there is no thundering-herd cost to
amortize; and reading fresh on every call means we automatically pick up refreshes the
Codex CLI performs behind our back. A cache would serve a stale token after the CLI rotates
it.

**No client-side expiry checking.** We do not decode the JWT or inspect `last_refresh`.
Instead, an HTTP 401 maps to ``"Codex session expired. Run: `codex login`"``. Checking
expiry locally would duplicate the server's authority and could reject a token the server
would have accepted.

---

## 5. Transport

Endpoint: `https://chatgpt.com/backend-api/codex/responses`, overridable via
`config.endpoint`.

Request body:

```lua
{
  model  = envelope.model or config.model,
  stream = true,
  store  = false,
  reasoning = { effort = config.reasoning_effort },
  text      = { verbosity = config.verbosity },
  input = {
    { role = "developer", content = {{ type = "input_text", text = envelope.system }} },
    { role = "user",      content = {{ type = "input_text", text = envelope.user   }} },
  },
}
```

Headers:

| Header | Value |
| --- | --- |
| `Authorization` | `Bearer <access_token>` |
| `ChatGPT-Account-ID` | `<account_id>` |
| `originator` | `codex_cli_rs` |
| `User-Agent` | `codex_cli_rs/<version> (<os> <arch>)` |
| `OpenAI-Beta` | `responses_websockets=2026-02-06` |
| `Content-Type` | `application/json` (added by `http.lua`) |

The `originator` and `User-Agent` values are part of a client-identity allowlist; the
backend is sensitive to them.

Sent through `request.send` with `request.resolve_policy(config)`, exactly like every other
provider.

### SSE parsing

The buffered blob is parsed inside the provider:

1. Split on lines.
2. JSON-decode the payload of each `data:` line (under `pcall`; skip undecodable lines).
3. Concatenate the `delta` of every `response.output_text.delta` event.
4. Confirm a `response.completed` event arrived.
5. Ignore reasoning and all other event types.

Return the concatenated text as a one-element `texts` array.

---

## 6. Security: role separation, not concatenation

`vertex.lua:144` concatenates system and user into a single message. **This provider
deliberately does not.**

A git diff is attacker-influenceable content — anyone who can land a commit, or open a PR a
user then stages, can put text in it. Concatenating would place our instructions at the same
precedence tier as that text. §2.4 established that a `developer` role outranks `user`, so
sending the system prompt as `developer` and the diff as `user` puts the instructions at a
strictly higher documented tier.

This is a flagged, intentional convention deviation. Keep it.

**Credential hygiene** (enforced by the repo's `reviewing-security` lens):

- The token is never logged.
- The token is never interpolated into an error string.
- The token is redacted even under `debug = true`.
- Any shell invocation uses table arguments or `vim.fn.shellescape`.

---

## 7. Configuration

```lua
codex = {
  enabled = false,
  endpoint = nil,             -- nil = ChatGPT Codex backend default
  model = "gpt-5.6-terra",
  reasoning_effort = "none",  -- none|minimal|low|medium|high|xhigh|max
  verbosity = "low",          -- low|medium|high — the only length control
  max_length = 50,
  generate = 1,               -- must be 1; the backend gives no fan-out
  request = { timeout_ms = 120000 },
},
```

No `api_key`, no `temperature`, no `top_p`, no `max_tokens` keys — including them would
advertise knobs the backend rejects.

The longer `timeout_ms` (120s vs. the 30s global default) reflects reasoning-model latency.

### `validate_config`

- `model` non-empty.
- `max_length` a positive number.
- `generate` must equal 1 — anything else is an error, not a silent clamp.
- `reasoning_effort` in the 7-value enum.
- `verbosity` in `low|medium|high`.
- Credentials resolve, else ``"Codex credentials not found. Run: `codex login`"``.

### `get_capabilities`

```lua
{ supports_streaming = false, supports_multiple_generations = false, max_generations = 1 }
```

`supports_streaming = false` is honest: the backend streams, but the provider surfaces only
final buffered text.

---

## 8. Error handling

A helper `extract_api_error(body)` normalizes both envelopes from §2.5.

| Condition | Surfaced message |
| --- | --- |
| HTTP 401 | ``"Codex session expired. Run: `codex login`"`` |
| HTTP 400, flat `detail` | The `detail` verbatim, framed as a parameter unsupported by the ChatGPT Codex backend |
| HTTP 400, rich `error` | The `error.message` |
| No `response.completed`, or empty text | `"No commit messages were generated. Try again."` |

401 is deliberately **not** added to `request.retry_on_status` — retrying an expired token
just burns the retry budget on a guaranteed failure.

---

## 9. Testing

`tests/codex_spec.lua`, following the existing provider-spec conventions (mocks cleaned in
`after_each`):

**Success paths**

- Canned SSE blob → one commit message.
- Multiple `output_text.delta` events concatenate in order.
- Reasoning and unknown event types are ignored.
- `$CODEX_HOME` is respected when set.

**Auth failures**

- `auth.json` missing.
- `auth.json` malformed JSON.
- `auth.json` present but missing `tokens.access_token`.

**HTTP failures**

- 401 → re-login message.
- 400 flat `{"detail":…}`.
- 400 rich `{"error":{…}}`.

**Validation**

- Rejects `generate = 2`.
- Rejects an out-of-enum `reasoning_effort`.
- Rejects an out-of-enum `verbosity`.

**Security**

- An explicit assertion that no error path leaks the access token into the returned message.

---

## 10. README disclosure

The README must be honest rather than promotional:

- The endpoint is undocumented and internal to ChatGPT.
- Requests spend ChatGPT subscription quota.
- OpenAI has not blessed third-party use of this session.
- Account-suspension risk is real, if unquantified. Anthropic banned third-party OAuth token
  reuse in February 2026; OpenAI has not followed suit, but the precedent exists.
- Business/Enterprise users should check with their workspace admin first.

`enabled = false` by default. Opting in is a deliberate act.

---

## 11. Open risks

| Risk | Mitigation |
| --- | --- |
| Endpoint changes or disappears | Provider is isolated; `enabled = false` by default; failure is loud. |
| Cloudflare fingerprint blocking | Not reproducible locally; surfaces as a transport error. Documented so it is diagnosable. |
| Codex CLI changes `auth.json` shape | Read is defensive; failure yields the actionable re-login message. |
| Model names churn | `model` is configurable; the two known-good names are documented. |
| OpenAI prohibits this | Documented in the README so the user chooses knowingly. |
