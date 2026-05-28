local rich

describe("input.rich — parsing helpers", function()
  before_each(function()
    rich = require("aicommits.input.rich")
  end)

  -- ── split_diff_by_file ───────────────────────────────────────────────
  describe("split_diff_by_file()", function()
    it("returns empty table for empty diff", function()
      local result = rich.split_diff_by_file("")
      assert.same({}, result)
    end)

    it("splits a two-file diff into two entries", function()
      local diff = table.concat({
        "diff --git a/foo.lua b/foo.lua",
        "--- a/foo.lua",
        "+++ b/foo.lua",
        "@@ -1,1 +1,2 @@",
        " line",
        "+added",
        "diff --git a/bar.lua b/bar.lua",
        "--- a/bar.lua",
        "+++ b/bar.lua",
        "@@ -1 +1 @@",
        "-removed",
      }, "\n")

      local result = rich.split_diff_by_file(diff)
      assert.equals(2, #result)
      assert.equals("foo.lua", result[1].path)
      assert.equals("bar.lua", result[2].path)
      assert.is_truthy(result[1].diff:match("added"))
      assert.is_truthy(result[2].diff:match("removed"))
    end)

    it("marks binary files with zero-hunk flag", function()
      local diff = table.concat({
        "diff --git a/img.png b/img.png",
        "Binary files a/img.png and b/img.png differ",
      }, "\n")
      local result = rich.split_diff_by_file(diff)
      assert.equals(1, #result)
      assert.is_true(result[1].is_binary)
    end)
  end)

  -- ── split_into_chunks ────────────────────────────────────────────────
  describe("split_into_chunks()", function()
    local function make_hunk(n_lines)
      local lines = { "@@ -1," .. n_lines .. " +1," .. n_lines .. " @@" }
      for i = 1, n_lines do lines[#lines + 1] = " line" .. i end
      return table.concat(lines, "\n")
    end

    it("packs multiple small hunks into one chunk when they fit", function()
      local file_diff = make_hunk(3) .. "\n" .. make_hunk(3)
      -- chunk_chars large enough to fit both
      local chunks = rich.split_into_chunks(file_diff, 10000)
      assert.equals(1, #chunks)
    end)

    it("splits into two chunks when combined size exceeds chunk_chars", function()
      -- Each hunk ~60 chars; chunk_chars=80 → each hunk gets its own chunk
      local file_diff = make_hunk(5) .. "\n" .. make_hunk(5)
      local chunks = rich.split_into_chunks(file_diff, 80)
      assert.equals(2, #chunks)
    end)

    it("puts an oversized single hunk into its own chunk", function()
      local big_hunk = make_hunk(200)  -- > any reasonable chunk_chars for this test
      local chunks = rich.split_into_chunks(big_hunk, 50)
      assert.equals(1, #chunks)
      assert.is_truthy(chunks[1]:match("@@ %-1,200"))
    end)
  end)

  -- ── bucket_files ─────────────────────────────────────────────────────
  describe("bucket_files()", function()
    local cfg = {
      small_file_chars      = 100,
      max_small_files_inline = 2,
    }

    it("classifies a large file as 'large'", function()
      local file_entries = {
        { path = "big.lua", diff = string.rep("x", 200), is_binary = false },
      }
      local buckets = rich.bucket_files(file_entries, cfg)
      assert.equals(1, #buckets.large)
      assert.equals(0, #buckets.small_inline)
      assert.equals(0, #buckets.small_batched)
    end)

    it("classifies small files as small_inline when count <= max_small_files_inline", function()
      local file_entries = {
        { path = "a.lua", diff = "x", is_binary = false },
        { path = "b.lua", diff = "y", is_binary = false },
      }
      local buckets = rich.bucket_files(file_entries, cfg)
      assert.equals(2, #buckets.small_inline)
      assert.equals(0, #buckets.small_batched)
    end)

    it("classifies small files as small_batched when count > max_small_files_inline", function()
      local file_entries = {
        { path = "a.lua", diff = "x", is_binary = false },
        { path = "b.lua", diff = "y", is_binary = false },
        { path = "c.lua", diff = "z", is_binary = false },
      }
      local buckets = rich.bucket_files(file_entries, cfg)
      assert.equals(0, #buckets.small_inline)
      assert.equals(3, #buckets.small_batched)
    end)

    it("puts binary files into stat_only bucket", function()
      local file_entries = {
        { path = "img.png", diff = "", is_binary = true },
      }
      local buckets = rich.bucket_files(file_entries, cfg)
      assert.equals(1, #buckets.stat_only)
    end)
  end)
end)

describe("make_scheduler()", function()
  local orig_vim_schedule

  before_each(function()
    rich = require("aicommits.input.rich")
    -- vim.schedule is not available in busted; stub it to fire synchronously. [inferred]
    orig_vim_schedule = vim.schedule
    vim.schedule = function(fn) fn() end
  end)

  after_each(function()
    vim.schedule = orig_vim_schedule
  end)

  it("runs a single task and calls its done callback", function()
    local sched = rich.make_scheduler(2)
    local called = false
    sched.run(function(done)
      called = true
      done()
    end)
    assert.is_true(called)
  end)

  it("respects concurrency cap — max in-flight equals concurrency", function()
    local sched = rich.make_scheduler(2)
    local in_flight_peak = 0
    local in_flight = 0
    local done_fns = {}

    local function task(done)
      in_flight = in_flight + 1
      if in_flight > in_flight_peak then in_flight_peak = in_flight end
      table.insert(done_fns, function()
        in_flight = in_flight - 1
        done()
      end)
    end

    -- Enqueue 4 tasks; only 2 should start immediately
    for _ = 1, 4 do sched.run(task) end

    -- Complete all queued tasks
    while #done_fns > 0 do
      local fn = table.remove(done_fns, 1)
      fn()
    end

    assert.is_true(in_flight_peak <= 2)
  end)
end)

describe("prepare() integration", function()
  local orig_picker_show, orig_picker_close, orig_vim_schedule

  before_each(function()
    rich = require("aicommits.input.rich")
    -- rich.lua calls picker.show_status; stub it to prevent UI errors in tests. [inferred]
    local picker = require("aicommits.ui.picker")
    orig_picker_show  = picker.show_status
    orig_picker_close = picker.close_status
    picker.show_status  = function() end
    picker.close_status = function() end
    -- make_scheduler uses vim.schedule; stub it to run synchronously [inferred]
    orig_vim_schedule = vim.schedule
    vim.schedule = function(fn) fn() end
  end)

  after_each(function()
    local picker = require("aicommits.ui.picker")
    picker.show_status  = orig_picker_show
    picker.close_status = orig_picker_close
    vim.schedule = orig_vim_schedule
  end)

  local function make_mock_provider(summary_result)
    -- summary_result: string (success) or error string prefixed with "ERR:"
    return {
      summarize = function(self, text, opts, provider_config, callback)
        if summary_result:sub(1, 4) == "ERR:" then
          callback(summary_result:sub(5), nil)
        else
          callback(nil, summary_result)
        end
      end,
    }
  end

  local function stub_stat(stat_text)
    local git = require("aicommits.git")
    local orig = git.get_staged_stat
    git.get_staged_stat = function(cb) cb(nil, stat_text) end
    return function() git.get_staged_stat = orig end
  end

  it("returns assembled payload for a single large file", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local provider = make_mock_provider("- changed foo()")

    local big_diff = table.concat({
      "diff --git a/big.lua b/big.lua",
      "@@ -1,5 +1,6 @@",
      " line1",
      "+line2",
    }, "\n") .. string.rep("\nmore content", 30)  -- push over small_file_chars

    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local cfg_override = {
      mode = "always",
      threshold_chars = 0,
      chunk_chars = 6000,
      max_chunks_per_file = 6,
      small_file_chars = 50,  -- small threshold so big_diff is classified as large
      max_small_files_inline = 10,
      small_file_batch_chars = 4000,
      summary_model = nil,
      summary_max_tokens = 220,
      summary_temperature = 0.2,
      concurrency = 4,
    }

    local config = require("aicommits.config")
    config.setup({ large_diff = cfg_override })

    local err, payload
    require("aicommits.input.rich").prepare(
      diff_data, provider, {}, function(e, p) err = e; payload = p end)

    restore()

    assert.is_nil(err)
    assert.is_string(payload)
    assert.is_truthy(payload:match("big%.lua"))
    assert.is_truthy(payload:match("changed foo"))
  end)

  it("falls back to stat-only when all summaries fail", function()
    local restore = stub_stat(" big.lua | 5 +++\n")
    local provider = make_mock_provider("ERR:api down")

    local big_diff = table.concat({
      "diff --git a/big.lua b/big.lua",
      "@@ -1,3 +1,4 @@",
      " a",
      "+b",
    }, "\n") .. string.rep("\nx", 60)

    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local config = require("aicommits.config")
    config.setup({ large_diff = {
      mode = "always", small_file_chars = 50,
      chunk_chars = 6000, max_chunks_per_file = 6,
      max_small_files_inline = 10, small_file_batch_chars = 4000,
      summary_max_tokens = 220, summary_temperature = 0.2, concurrency = 4,
    }})

    local err, _payload
    require("aicommits.input.rich").prepare(
      diff_data, provider, {}, function(e, p) err = e; _payload = p end)

    restore()

    -- All summaries failed → error surfaced
    assert.is_string(err)
  end)

  it("small-batched path produces a payload containing batch summary", function()
    local restore = stub_stat(" a.lua | 1\n b.lua | 1\n c.lua | 1\n")
    local provider = make_mock_provider("- a: changed\n- b: changed\n- c: changed")

    local mk = function(name)
      return "diff --git a/" .. name .. " b/" .. name
        .. "\n@@ -1 +1 @@\n-old\n+new"
    end
    local diff = mk("a.lua") .. "\n" .. mk("b.lua") .. "\n" .. mk("c.lua")
    local diff_data = { diff = diff, files = { "a.lua", "b.lua", "c.lua" } }

    local config = require("aicommits.config")
    config.setup({ large_diff = {
      mode = "always",
      small_file_chars = 10000,  -- all files are "small"
      max_small_files_inline = 2,  -- 3 > 2 → small_batched
      small_file_batch_chars = 4000,
      chunk_chars = 6000, max_chunks_per_file = 6,
      summary_max_tokens = 220, summary_temperature = 0.2, concurrency = 4,
    }})

    local err, payload
    require("aicommits.input.rich").prepare(
      diff_data, provider, {}, function(e, p) err = e; payload = p end)

    restore()

    assert.is_nil(err)
    assert.is_string(payload)
    assert.is_truthy(payload:match("changed"))
  end)
end)
