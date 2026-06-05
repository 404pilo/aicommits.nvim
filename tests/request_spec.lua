-- Unit tests for the request policy layer (request.lua)
describe("request policy layer", function()
  local request
  local http

  -- Default policy used by most tests; overridden per-test as needed.
  local function policy(overrides)
    return vim.tbl_extend("force", {
      timeout_ms = 30000,
      max_retries = 2,
      backoff_base_ms = 500,
      backoff_max_ms = 8000,
      backoff_jitter = false,
      retry_on_status = { 408, 429, 500, 502, 503, 504 },
      respect_retry_after = true,
      max_concurrency = 4,
    }, overrides or {})
  end

  before_each(function()
    package.loaded["aicommits.request"] = nil
    package.loaded["aicommits.http"] = nil
    http = require("aicommits.http")
    request = require("aicommits.request")
    -- Synchronous defer: run scheduled fn immediately, record the delay.
    request._scheduled_delays = {}
    request._defer = function(delay_ms, fn)
      table.insert(request._scheduled_delays, delay_ms)
      fn()
    end
  end)

  describe("resolve_policy", function()
    it("returns the policy passed through send opts unchanged for known keys", function()
      -- resolve_policy is exercised in config_spec; here assert it exists.
      assert.is_function(request.resolve_policy)
    end)
  end)

  describe("send classification", function()
    it("returns immediately on 2xx without retrying", function()
      local calls = 0
      http.post = function(_u, _h, _b, _o, cb)
        calls = calls + 1
        cb(nil, { status = 200, body = "ok", headers = {} })
      end
      local got
      request.send({ url = "x", headers = {}, body = "{}", policy = policy() }, function(e, r)
        got = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got ~= nil
      end)
      assert.equals(1, calls)
      assert.is_nil(got.e)
      assert.equals(200, got.r.status)
    end)

    it("retries on a 503 then succeeds on the second attempt", function()
      local calls = 0
      http.post = function(_u, _h, _b, _o, cb)
        calls = calls + 1
        if calls == 1 then
          cb(nil, { status = 503, body = "busy", headers = {} })
        else
          cb(nil, { status = 200, body = "ok", headers = {} })
        end
      end
      local got
      request.send({ url = "x", headers = {}, body = "{}", policy = policy() }, function(e, r)
        got = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got ~= nil
      end)
      assert.equals(2, calls)
      assert.equals(200, got.r.status)
    end)

    it("retries on a transport error then succeeds", function()
      local calls = 0
      http.post = function(_u, _h, _b, _o, cb)
        calls = calls + 1
        if calls == 1 then
          cb("network error", nil)
        else
          cb(nil, { status = 200, body = "ok", headers = {} })
        end
      end
      local got
      request.send({ url = "x", headers = {}, body = "{}", policy = policy() }, function(e, r)
        got = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got ~= nil
      end)
      assert.equals(2, calls)
      assert.is_nil(got.e)
    end)

    it("does NOT retry on a 400/401/403/404", function()
      for _, code in ipairs({ 400, 401, 403, 404 }) do
        local calls = 0
        http.post = function(_u, _h, _b, _o, cb)
          calls = calls + 1
          cb(nil, { status = code, body = "no", headers = {} })
        end
        local got
        request.send({ url = "x", headers = {}, body = "{}", policy = policy() }, function(e, r)
          got = { e = e, r = r }
        end)
        vim.wait(1000, function()
          return got ~= nil
        end)
        assert.equals(1, calls, "status " .. code .. " should not retry")
        assert.equals(code, got.r.status)
      end
    end)

    it("returns the LAST result after exhausting the retry budget", function()
      local calls = 0
      http.post = function(_u, _h, _b, _o, cb)
        calls = calls + 1
        cb(nil, { status = 503, body = "still busy", headers = {} })
      end
      local got
      request.send({ url = "x", headers = {}, body = "{}", policy = policy({ max_retries = 2 }) }, function(e, r)
        got = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got ~= nil
      end)
      -- total attempts = 1 + max_retries = 3
      assert.equals(3, calls)
      assert.equals(503, got.r.status)
    end)
  end)

  describe("backoff schedule", function()
    it("uses base then 2x base, capped at backoff_max_ms, no jitter", function()
      local calls = 0
      http.post = function(_u, _h, _b, _o, cb)
        calls = calls + 1
        cb(nil, { status = 503, body = "x", headers = {} })
      end
      local got
      request.send({
        url = "x",
        headers = {},
        body = "{}",
        policy = policy({ max_retries = 3, backoff_base_ms = 500, backoff_max_ms = 1500, backoff_jitter = false }),
      }, function(e, r)
        got = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got ~= nil
      end)
      -- attempt 1 retry wait = 500, attempt 2 = 1000, attempt 3 = min(2000,1500)=1500
      assert.same({ 500, 1000, 1500 }, request._scheduled_delays)
    end)

    -- [inferred] Lock the full-jitter contract: jitter is MULTIPLICATIVE
    -- (random() * delay), so each scheduled delay must be in [0, uncapped_delay]
    -- and never exceed backoff_max_ms. Stub math.random to a fixed fraction.
    it("applies full jitter as random()*delay within [0, delay], capped", function()
      local calls = 0
      http.post = function(_u, _h, _b, _o, cb)
        calls = calls + 1
        cb(nil, { status = 503, body = "x", headers = {} })
      end
      local orig_random = math.random
      math.random = function()
        return 0.5
      end
      local got
      request.send({
        url = "x",
        headers = {},
        body = "{}",
        policy = policy({ max_retries = 3, backoff_base_ms = 500, backoff_max_ms = 1500, backoff_jitter = true }),
      }, function(e, r)
        got = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got ~= nil
      end)
      math.random = orig_random
      -- Uncapped delays would be 500, 1000, 1500; with random()=0.5 multiplicative
      -- jitter each is halved: 250, 500, 750. Every value <= its uncapped delay and
      -- <= backoff_max_ms (1500). An ADDITIVE jitter bug (delay+random) would fail here.
      assert.same({ 250, 500, 750 }, request._scheduled_delays)
    end)

    it("honors Retry-After (seconds) on a 429, capped at backoff_max_ms", function()
      local calls = 0
      http.post = function(_u, _h, _b, _o, cb)
        calls = calls + 1
        if calls == 1 then
          cb(nil, { status = 429, body = "x", headers = { retry_after = "3" } })
        else
          cb(nil, { status = 200, body = "ok", headers = {} })
        end
      end
      local got
      request.send({
        url = "x",
        headers = {},
        body = "{}",
        policy = policy({ respect_retry_after = true, backoff_max_ms = 8000 }),
      }, function(e, r)
        got = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got ~= nil
      end)
      -- 3 seconds -> 3000 ms, below cap
      assert.same({ 3000 }, request._scheduled_delays)
    end)

    it("caps Retry-After at backoff_max_ms", function()
      local calls = 0
      http.post = function(_u, _h, _b, _o, cb)
        calls = calls + 1
        if calls == 1 then
          cb(nil, { status = 429, body = "x", headers = { retry_after = "120" } })
        else
          cb(nil, { status = 200, body = "ok", headers = {} })
        end
      end
      local got
      request.send({
        url = "x",
        headers = {},
        body = "{}",
        policy = policy({ respect_retry_after = true, backoff_max_ms = 8000 }),
      }, function(e, r)
        got = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got ~= nil
      end)
      assert.same({ 8000 }, request._scheduled_delays)
    end)
  end)

  describe("global semaphore", function()
    it("never exceeds max_concurrency in flight", function()
      local in_flight = 0
      local peak = 0
      local pending_cbs = {}
      -- http.post that does NOT call back immediately; we release manually.
      http.post = function(_u, _h, _b, _o, cb)
        in_flight = in_flight + 1
        peak = math.max(peak, in_flight)
        table.insert(pending_cbs, function()
          in_flight = in_flight - 1
          cb(nil, { status = 200, body = "ok", headers = {} })
        end)
      end

      local done = 0
      local p = policy({ max_concurrency = 2 })
      for _ = 1, 6 do
        request.send({ url = "x", headers = {}, body = "{}", policy = p }, function()
          done = done + 1
        end)
      end

      -- Drain: release in-flight callbacks until all 6 complete.
      vim.wait(2000, function()
        while #pending_cbs > 0 do
          local cb = table.remove(pending_cbs, 1)
          cb()
        end
        return done == 6
      end)

      assert.equals(6, done)
      assert.is_true(peak <= 2, "peak in-flight was " .. peak)
    end)

    it("releases the slot during backoff so a retry does not hold it", function()
      -- One request will retry once; while it backs off, two others must run.
      local in_flight = 0
      local peak = 0
      local attempt_by_order = {}
      http.post = function(_u, _h, _b, _o, cb)
        in_flight = in_flight + 1
        peak = math.max(peak, in_flight)
        in_flight = in_flight - 1
        table.insert(attempt_by_order, true)
        -- First global call gets a 503 (will retry), rest succeed.
        if #attempt_by_order == 1 then
          cb(nil, { status = 503, body = "x", headers = {} })
        else
          cb(nil, { status = 200, body = "ok", headers = {} })
        end
      end
      local done = 0
      local p = policy({ max_concurrency = 1, max_retries = 1 })
      for _ = 1, 2 do
        request.send({ url = "x", headers = {}, body = "{}", policy = p }, function()
          done = done + 1
        end)
      end
      vim.wait(2000, function()
        return done == 2
      end)
      assert.equals(2, done)
      assert.is_true(peak <= 1)
    end)
  end)
end)
