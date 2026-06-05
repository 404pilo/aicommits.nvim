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

-- Note: a waiter records the bound it was enqueued under (`max`). Within a single
-- commit exactly one provider is active and its max_concurrency is constant, so the
-- enqueue-time bound is always the bound in effect when the waiter wakes. The spec's
-- "read lazily at each acquire" guarantee applies ACROSS commits (a setup() change
-- between commits takes effect on the next acquire), not to a waiter already queued
-- in an in-flight batch. [inferred]
local function sem_acquire(max_concurrency, on_acquired)
  if sem.in_flight < max_concurrency then
    sem.in_flight = sem.in_flight + 1
    on_acquired()
  else
    table.insert(sem.waiters, { max = max_concurrency, run = on_acquired })
  end
end

local function sem_release()
  sem.in_flight = sem.in_flight - 1
  -- Wake the next waiter if the (possibly changed) bound allows it.
  if #sem.waiters > 0 then
    local next_waiter = sem.waiters[1]
    if sem.in_flight < next_waiter.max then
      table.remove(sem.waiters, 1)
      sem.in_flight = sem.in_flight + 1
      next_waiter.run()
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

  local function attempt(n)
    sem_acquire(policy.max_concurrency or 1, function()
      http.post(opts.url, opts.headers, opts.body, { timeout_ms = policy.timeout_ms }, function(err, result)
        if not is_transient(err, result, policy) or n >= max_attempts then
          -- Terminal: success, non-retryable, or budget exhausted. Release + return.
          sem_release()
          cb(err, result)
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
    end)
  end

  attempt(1)
end

return M
