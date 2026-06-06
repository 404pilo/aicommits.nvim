-- Request policy layer: the single throttle + retry/backoff wrapper that every
-- provider's generate_text calls instead of http.post directly.
local http = require("aicommits.http")

local M = {}

-- ── Injectable timer seam ────────────────────────────────────────────────
-- Default wraps vim.defer_fn; tests override M._defer to run synchronously and
-- record scheduled delays for deterministic backoff assertions.
M._defer = function(delay_ms, fn)
  vim.defer_fn(fn, delay_ms)
end

-- ── Single process-global semaphore ──────────────────────────────────────
-- There is exactly ONE counter in the whole system. Its bound is read lazily at
-- each acquire from the active request's policy.max_concurrency. Mixing providers
-- within one commit is not a supported scenario (one commit = one active provider).
local sem = {
  in_flight = 0,
  waiters = {}, -- FIFO queue of functions waiting for a slot
}

-- Forward declaration: sem_acquire references sem_release (for release-on-throw),
-- but sem_release is defined after it. Declaring the local up front makes both
-- functions close over the SAME upvalue instead of sem_acquire capturing a nil global.
local sem_release

-- Note: a waiter records the bound it was enqueued under (`max`). Within a single
-- commit exactly one provider is active and its max_concurrency is constant, so the
-- enqueue-time bound is always the bound in effect when the waiter wakes. The spec's
-- "read lazily at each acquire" guarantee applies ACROSS commits (a setup() change
-- between commits takes effect on the next acquire), not to a waiter already queued
-- in an in-flight batch. [inferred]
local function sem_acquire(max_concurrency, on_acquired, on_error)
  if sem.in_flight < max_concurrency then
    sem.in_flight = sem.in_flight + 1
    -- on_acquired holds the slot. If it throws synchronously (e.g. vim.system
    -- raises ENOENT when curl is missing) the exception would propagate out of
    -- here without the slot ever being released, leaking it permanently and
    -- eventually deadlocking every later request in the waiters queue. Run it
    -- under pcall and release the slot on a synchronous throw before re-raising,
    -- so the leak can never happen.
    local ok, err = pcall(on_acquired)
    if not ok then
      sem_release()
      error(err, 0)
    end
  else
    -- on_error is called when the waiter throws on wake (see sem_release drain).
    -- Passing it through here keeps settle() reachable without closing over globals.
    table.insert(sem.waiters, { max = max_concurrency, run = on_acquired, on_error = on_error })
  end
end

function sem_release()
  sem.in_flight = sem.in_flight - 1
  -- Drain as many waiters as the freed capacity allows. We scan FIFO and wake the
  -- FIRST waiter whose enqueue-time bound the current in_flight satisfies, rather
  -- than testing only the head. If max_concurrency was lowered via setup() while a
  -- draining batch still has waiters queued, a low-max head (e.g. max=1 with
  -- in_flight=2) would otherwise fail its head test and wedge the whole FIFO behind
  -- it -- including higher-max waiters that the freed slot could already run -- with
  -- no further re-check scheduled, a silent hang. Skipping a non-runnable head to a
  -- runnable waiter behind it keeps releases propagating; the loop repeats because a
  -- woken waiter may itself free or take capacity that changes which waiters qualify.
  local progressed = true
  while progressed and #sem.waiters > 0 do
    progressed = false
    for i, waiter in ipairs(sem.waiters) do
      if sem.in_flight < waiter.max then
        table.remove(sem.waiters, i)
        sem.in_flight = sem.in_flight + 1
        progressed = true
        -- pcall-wrapped: if the woken waiter throws synchronously (e.g. http.post
        -- raises ENOENT), decrement in_flight so the slot is not permanently leaked
        -- and the drain loop can continue to wake subsequent waiters. Surface the
        -- error to the waiter's owner via on_error so the request.send callback
        -- contract is upheld (the outer pcall(attempt,1) has already returned when
        -- the waiter was originally enqueued, so it cannot catch this throw itself).
        local run_ok, run_err = pcall(waiter.run)
        if not run_ok then
          sem.in_flight = sem.in_flight - 1
          if waiter.on_error then
            waiter.on_error(run_err)
          end
        end
        break -- waiter.run() may re-enter (release/acquire); rescan from fresh state
      end
    end
  end
end

-- Resolve the effective request policy for a provider config. Pure: no I/O.
-- Deep-merges the global `request` block with provider_config.request override.
-- (Config defaults + alias folding happen in config.lua; this function reads the
-- already-merged config and applies the per-provider override.)
-- @param provider_config table  Active provider's config (carries optional .request)
-- @return table policy
function M.resolve_policy(provider_config)
  local config = require("aicommits.config")
  local global = config.get("request") or {}
  local override = (provider_config and provider_config.request) or {}
  return vim.tbl_deep_extend("force", {}, global, override)
end

-- Compute the backoff delay (ms) for a given 1-based attempt.
local function backoff_delay(policy, attempt, retry_after_ms)
  local max_ms = policy.backoff_max_ms or 8000
  if retry_after_ms then
    return math.min(retry_after_ms, max_ms)
  end
  local base = policy.backoff_base_ms or 500
  local delay = math.min(base * (2 ^ (attempt - 1)), max_ms)
  if policy.backoff_jitter then
    delay = math.random() * delay
  end
  return delay
end

-- Is this (err, result) a transient failure worth retrying?
local function is_transient(err, result, policy)
  if err then
    return true -- transport-level failure (network/timeout)
  end
  local status = result and result.status or 0
  for _, code in ipairs(policy.retry_on_status or {}) do
    if status == code then
      return true
    end
  end
  return false
end

-- Send a request through the policy layer.
-- @param opts table { url, headers, body, policy }
-- @param cb   function(err, result)  result = { status, body, headers } (same as http.post)
function M.send(opts, cb)
  local policy = opts.policy or {}
  local max_attempts = 1 + (policy.max_retries or 0)

  -- Guard against a double callback: the synchronous-throw rescue below must not
  -- re-invoke cb if cb (or the http.post stub) already fired and then threw.
  local settled = false
  local function settle(err, result)
    if settled then
      return
    end
    settled = true
    cb(err, result)
  end

  local function attempt(n)
    -- on_error is passed to sem_acquire so that if this attempt's on_acquired
    -- throws AFTER being woken from the waiters queue (sem_release drain path),
    -- the error is still surfaced to the caller via settle rather than being
    -- silently discarded. In the direct-acquire path the outer pcall(attempt,1)
    -- below catches the re-raised error instead, so on_error only matters for
    -- the enqueued-then-woken case.
    local function on_error(err)
      settle("HTTP request failed: " .. tostring(err), nil)
    end
    sem_acquire(policy.max_concurrency or 1, function()
      http.post(opts.url, opts.headers, opts.body, { timeout_ms = policy.timeout_ms }, function(err, result)
        if not is_transient(err, result, policy) or n >= max_attempts then
          -- Terminal: success, non-retryable, or budget exhausted. Release + return.
          sem_release()
          settle(err, result)
          return
        end

        -- Transient and budget remains: release the slot during the backoff wait,
        -- then re-acquire before the retry send.
        local retry_after_ms = nil
        if policy.respect_retry_after and result and result.headers and result.headers.retry_after then
          local secs = tonumber(result.headers.retry_after)
          if secs then
            retry_after_ms = secs * 1000
          end
        end
        local delay = backoff_delay(policy, n, retry_after_ms)
        sem_release()
        M._defer(delay, function()
          attempt(n + 1)
        end)
      end)
    end, on_error)
  end

  -- A synchronous throw inside the slot-holding work (e.g. vim.system raising
  -- ENOENT when curl is missing) has already released the leaked slot inside
  -- sem_acquire; here we convert that throw into the normal transport-error
  -- callback contract (cb(err, nil)) so the failure is surfaced to the provider
  -- instead of propagating out of request.send and aborting the whole commit.
  local ok, err = pcall(attempt, 1)
  if not ok then
    settle("HTTP request failed: " .. tostring(err), nil)
  end
end

return M
