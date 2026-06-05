-- Unit tests for the low-level curl transport (http.lua)
describe("http.post transport", function()
  local http
  local orig_system

  before_each(function()
    package.loaded["aicommits.http"] = nil
    http = require("aicommits.http")
    orig_system = vim.system
  end)

  after_each(function()
    vim.system = orig_system
  end)

  -- Stub vim.system to feed canned obj.stdout/obj.code and capture args.
  local function stub_system(stdout, code)
    local captured = {}
    vim.system = function(cmd, _opts, on_exit)
      captured.cmd = cmd
      vim.schedule(function()
        on_exit({ code = code or 0, stdout = stdout, stderr = "" })
      end)
      return { wait = function() end }
    end
    return captured
  end

  -- Drive the async callback to completion synchronously for assertions.
  local function run(opts, stdout, code)
    stub_system(stdout, code)
    local result_err, result_val, done
    http.post("https://x", {}, "{}", opts, function(e, r)
      result_err, result_val, done = e, r, true
    end)
    vim.wait(1000, function()
      return done == true
    end)
    return result_err, result_val
  end

  it("parses status and body from the sentinel tail (200)", function()
    local body = vim.json.encode({ ok = true })
    local stdout = body .. "\n<<<AICOMMITS_META>>>200 "
    local err, result = run({}, stdout, 0)
    assert.is_nil(err)
    assert.equals(200, result.status)
    assert.equals(body, result.body)
    -- [inferred] Empty %{header{retry-after}} (curl < 7.84 or no header) must
    -- degrade gracefully to a nil retry_after, not an empty string.
    assert.is_nil(result.headers.retry_after)
  end)

  it("parses retry_after from the sentinel tail when present (429)", function()
    local body = vim.json.encode({ error = "rate limited" })
    local stdout = body .. "\n<<<AICOMMITS_META>>>429 17"
    local err, result = run({}, stdout, 0)
    assert.is_nil(err)
    assert.equals(429, result.status)
    assert.equals("17", result.headers.retry_after)
  end)

  it("splits at the LAST sentinel when the body itself contains the sentinel string", function()
    local body = "prefix <<<AICOMMITS_META>>>fakeinbody suffix"
    local stdout = body .. "\n<<<AICOMMITS_META>>>503 5"
    local err, result = run({}, stdout, 0)
    assert.is_nil(err)
    assert.equals(503, result.status)
    assert.equals(body, result.body)
    assert.equals("5", result.headers.retry_after)
  end)

  it("returns err=nil with non-2xx status for a 4xx", function()
    local stdout = '{"error":"bad"}\n<<<AICOMMITS_META>>>400 '
    local err, result = run({}, stdout, 0)
    assert.is_nil(err)
    assert.equals(400, result.status)
  end)

  it("returns err set when curl exits non-zero (timeout exit 28)", function()
    local err, result = run({ timeout_ms = 1000 }, "", 28)
    assert.is_string(err)
    assert.is_nil(result)
  end)

  it("adds --max-time rounding sub-second timeout up to 1", function()
    local captured = stub_system("{}\n<<<AICOMMITS_META>>>200 ", 0)
    local done
    http.post("https://x", {}, "{}", { timeout_ms = 250 }, function()
      done = true
    end)
    vim.wait(1000, function()
      return done == true
    end)
    local found = false
    for i, a in ipairs(captured.cmd) do
      if a == "--max-time" then
        found = true
        assert.equals("1", captured.cmd[i + 1])
      end
    end
    assert.is_true(found)
  end)

  it("omits --max-time when no timeout_ms supplied", function()
    local captured = stub_system("{}\n<<<AICOMMITS_META>>>200 ", 0)
    local done
    http.post("https://x", {}, "{}", {}, function()
      done = true
    end)
    vim.wait(1000, function()
      return done == true
    end)
    for _, a in ipairs(captured.cmd) do
      assert.is_not.equals("--max-time", a)
    end
  end)
end)
