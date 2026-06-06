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

    it("does not leak a slot when http.post throws synchronously (F3)", function()
      -- First send: http.post raises synchronously (simulates vim.system ENOENT
      -- when curl is missing). The slot it acquired must be released, and the
      -- throw must surface as a transport error to the callback -- not propagate
      -- out of request.send.
      http.post = function()
        error("ENOENT: curl not found")
      end
      local got1
      request.send({ url = "x", headers = {}, body = "{}", policy = policy({ max_concurrency = 1 }) }, function(e, r)
        got1 = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got1 ~= nil
      end)
      assert.is_not_nil(got1, "callback must be invoked, not left hanging")
      assert.is_not_nil(got1.e, "synchronous throw must surface as an error to cb")
      assert.is_nil(got1.r)

      -- Second send (same session, max_concurrency=1): if the first leaked its
      -- slot, in_flight would still be 1 and this request would block forever in
      -- the waiters queue. With the fix the slot is free, so it runs immediately.
      http.post = function(_u, _h, _b, _o, cb)
        cb(nil, { status = 200, body = "ok", headers = {} })
      end
      local got2
      request.send({ url = "y", headers = {}, body = "{}", policy = policy({ max_concurrency = 1 }) }, function(e, r)
        got2 = { e = e, r = r }
      end)
      vim.wait(1000, function()
        return got2 ~= nil
      end)
      assert.is_not_nil(got2, "second request must not be stuck behind a leaked slot")
      assert.is_nil(got2.e)
      assert.equals(200, got2.r.status)
    end)

    it("drains a runnable trailing waiter past a stuck lower-max head (F6)", function()
      -- Reproduce the FIFO-gate hang: a low-max head waiter must not wedge a
      -- higher-max waiter behind it that the freed capacity could already run.
      -- http.post defers its callback so we control completion order precisely.
      local pending = {}
      http.post = function(_u, _h, _b, _o, cb)
        table.insert(pending, cb)
      end

      local done = {}
      local function send(tag, max)
        request.send(
          { url = tag, headers = {}, body = "{}", policy = policy({ max_concurrency = max, max_retries = 0 }) },
          function()
            done[tag] = true
          end
        )
      end

      -- Three sends at max=3 saturate the semaphore: in_flight=3, no waiters.
      send("a", 3)
      send("b", 3)
      send("c", 3)
      assert.equals(3, #pending, "three should be in flight")

      -- Now a lowered batch enqueues behind them. Head u4 has max=1 (so it needs
      -- in_flight=0); u5 has max=3 (runnable as soon as in_flight<3). Both queue.
      send("u4", 1)
      send("u5", 3)
      assert.equals(3, #pending, "u4 and u5 must be queued, not in flight")

      -- Complete ONE in-flight request -> in_flight drops 3->2.
      -- OLD behavior: only head u4 is tested, 2<1 is false, queue wedges; u5 is a
      -- WASTED SLOT (2<3 is true but never tested) and stays stuck until in_flight=0.
      -- NEW behavior: scan skips the non-runnable u4 and wakes u5 immediately.
      local first = table.remove(pending, 1)
      first()

      assert.is_true(done["a"], "first request should have completed")
      assert.is_true(
        done["u5"] == nil and #pending == 3,
        "u5 should now be in flight (a fresh pending cb), proving the slot was not wasted"
      )

      -- Drain everything; the whole batch must finish (no silent hang).
      vim.wait(2000, function()
        while #pending > 0 do
          local cb = table.remove(pending, 1)
          cb()
        end
        return done["a"] and done["b"] and done["c"] and done["u4"] and done["u5"]
      end)

      for _, tag in ipairs({ "a", "b", "c", "u4", "u5" }) do
        assert.is_true(done[tag], tag .. " never completed -> hang")
      end
    end)

    it("does not leak a slot when a queued waiter throws on wake (F3b)", function()
      -- HOLDER: an in-flight request at max=1 that we complete manually.
      -- SECOND: queued waiter whose http.post throws synchronously on wake.
      -- THIRD:  queued waiter that should complete normally after SECOND's slot
      --         is released.
      -- Before the fix: waiter.run() at line 72 is a bare call; SECOND's throw
      --   propagates out of sem_release (called when HOLDER finishes), aborting
      --   the drain loop and leaving in_flight=1 forever -> THIRD hangs.
      -- After the fix: run_waiter pcalls waiter.run; decrements in_flight on
      --   failure; continues the drain; THIRD completes.

      local pending_holder = nil
      local second_post_count = 0
      local third_got = nil

      -- Intercept http.post per-URL so we can control each request separately.
      local post_handlers = {
        holder = function(_u, _h, _b, _o, cb)
          -- Defer callback so SECOND and THIRD can be enqueued before HOLDER finishes.
          pending_holder = cb
        end,
        second = function()
          second_post_count = second_post_count + 1
          error("ENOENT: curl not found on wake")
        end,
        third = function(_u, _h, _b, _o, cb)
          cb(nil, { status = 200, body = "ok", headers = {} })
        end,
      }
      http.post = function(url, h, b, o, cb)
        local handler = post_handlers[url]
        if handler then
          handler(url, h, b, o, cb)
        else
          cb(nil, { status = 200, body = "ok", headers = {} })
        end
      end

      local p1 = policy({ max_concurrency = 1, max_retries = 0 })
      local holder_got, second_got

      -- HOLDER goes in-flight immediately (in_flight=1).
      local holder_ok, holder_err = pcall(function()
        request.send({ url = "holder", headers = {}, body = "{}", policy = p1 }, function(e, r)
          holder_got = { e = e, r = r }
        end)
      end)

      -- SECOND and THIRD are enqueued (in_flight=1 = max).
      local second_ok, second_pcall_err = pcall(function()
        request.send({ url = "second", headers = {}, body = "{}", policy = p1 }, function(e, r)
          second_got = { e = e, r = r }
        end)
      end)

      request.send({ url = "third", headers = {}, body = "{}", policy = p1 }, function(e, r)
        third_got = { e = e, r = r }
      end)

      -- Sanity: HOLDER is in flight, SECOND+THIRD are waiting.
      assert.is_not_nil(pending_holder, "HOLDER should be in-flight (pending cb)")
      assert.is_nil(third_got, "THIRD should not have run yet")

      -- Complete HOLDER -> sem_release -> drain wakes SECOND -> SECOND throws.
      pending_holder(nil, { status = 200, body = "ok", headers = {} })

      -- Wait briefly for synchronous propagation.
      vim.wait(200, function()
        return third_got ~= nil
      end)

      -- SECOND's throw must be surfaced to its callback, not propagate out.
      assert.is_not_nil(second_got, "SECOND callback must be invoked despite throw")
      assert.is_not_nil(second_got.e, "SECOND error must be non-nil")

      -- THIRD must have completed: if the slot leaked from SECOND, THIRD hangs.
      assert.is_not_nil(third_got, "THIRD must complete; slot must not be leaked by SECOND's throw")
      assert.is_nil(third_got.e)
      assert.equals(200, third_got.r.status)
    end)
  end)
end)
