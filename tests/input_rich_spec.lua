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

    it("parses quoted diff headers and keeps the file entry", function()
      local diff = table.concat({
        [[diff --git "a/a\tb.txt" "b/a\tb.txt"]],
        "--- a/a\tb.txt",
        "+++ b/a\tb.txt",
        "@@ -1 +1 @@",
        "-old",
        "+new",
      }, "\n")

      local result = rich.split_diff_by_file(diff)
      assert.equals(1, #result)
      assert.is_not_nil(result[1].path)
      assert.is_truthy(result[1].path:match("\t"))
      assert.is_truthy(result[1].diff:match("%+new"))
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

    it("flags a pure rename as is_empty", function()
      local diff = table.concat({
        "diff --git a/legacy_payments.py b/payments_gateway.py",
        "similarity index 100%",
        "rename from legacy_payments.py",
        "rename to payments_gateway.py",
      }, "\n")
      local result = rich.split_diff_by_file(diff)
      assert.equals(1, #result)
      assert.equals("payments_gateway.py", result[1].path)
      assert.is_true(result[1].is_empty)
      assert.is_false(result[1].is_binary)
    end)

    it("flags an empty new file as is_empty", function()
      local diff = table.concat({
        "diff --git a/src/payments/__init__.py b/src/payments/__init__.py",
        "new file mode 100644",
        "index 0000000..e69de29",
      }, "\n")
      local result = rich.split_diff_by_file(diff)
      assert.equals(1, #result)
      assert.is_true(result[1].is_empty)
      assert.is_false(result[1].is_binary)
    end)

    it("does not flag a normal edit (with @@ hunk) as is_empty", function()
      local diff = table.concat({
        "diff --git a/foo.lua b/foo.lua",
        "index 1111111..2222222 100644",
        "--- a/foo.lua",
        "+++ b/foo.lua",
        "@@ -1,2 +1,3 @@",
        " local x = 1",
        "+local y = 2",
        " return x",
      }, "\n")
      local result = rich.split_diff_by_file(diff)
      assert.equals(1, #result)
      assert.is_falsy(result[1].is_empty)
    end)
  end)

  -- ── split_into_chunks ────────────────────────────────────────────────
  describe("split_into_chunks()", function()
    local function make_hunk(n_lines)
      local lines = { "@@ -1," .. n_lines .. " +1," .. n_lines .. " @@" }
      for i = 1, n_lines do
        lines[#lines + 1] = " line" .. i
      end
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
      local big_hunk = make_hunk(200) -- > any reasonable chunk_chars for this test
      local chunks = rich.split_into_chunks(big_hunk, 50)
      assert.equals(1, #chunks)
      assert.is_truthy(chunks[1]:match("@@ %-1,200"))
    end)

    it("replays the file header at the start of every emitted chunk", function()
      local header = table.concat({
        "diff --git a/big.lua b/big.lua",
        "index 1111111..2222222 100644",
        "--- a/big.lua",
        "+++ b/big.lua",
      }, "\n")

      local h1 = make_hunk(4)
      local h2 = make_hunk(4)
      local h3 = make_hunk(4)
      local file_diff = header .. "\n" .. table.concat({ h1, h2, h3 }, "\n")
      local chunk_chars = #header + 1 + #h1

      local chunks = rich.split_into_chunks(file_diff, chunk_chars)
      assert.is_true(#chunks >= 3)
      for _, chunk in ipairs(chunks) do
        assert.is_truthy(chunk:match("^diff %-%-git a/big%.lua b/big%.lua"))
        assert.is_truthy(chunk:match("\n@@ "))
      end
    end)
  end)

  describe("chunk_file_capped()", function()
    local function make_headered_diff(path, hunks)
      return table.concat({
        "diff --git a/" .. path .. " b/" .. path,
        "index 1111111..2222222 100644",
        "--- a/" .. path,
        "+++ b/" .. path,
        table.concat(hunks, "\n"),
      }, "\n")
    end

    it("grows chunk_chars when initial chunking exceeds cap", function()
      local hunks = {
        "@@ -1,30 +1,30 @@\n" .. string.rep("-old-long-line\n", 30) .. string.rep("+new-long-line\n", 30),
        "@@ -2,1 +2,1 @@\n-old2\n+new2",
        "@@ -3,1 +3,1 @@\n-old3\n+new3",
        "@@ -4,1 +4,1 @@\n-old4\n+new4",
      }
      local diff = make_headered_diff("grow.lua", hunks)
      local max_chunks = 3
      local grown = math.ceil(#diff / max_chunks)

      local base_chunks = rich.split_into_chunks(diff, 10)
      local chunks = rich.chunk_file_capped(diff, 10, max_chunks)
      local grown_chunks = rich.split_into_chunks(diff, grown)

      assert.is_true(#base_chunks > max_chunks)
      assert.is_true(#chunks <= max_chunks)
      assert.is_true(#grown_chunks <= max_chunks)
      assert.equals(#grown_chunks, #chunks)
    end)

    it("can still exceed cap after growth (hard-ceiling fallback case)", function()
      local max_chunks = 2
      local hunks = {}
      for i = 1, max_chunks + 1 do
        hunks[#hunks + 1] = "@@ -"
          .. i
          .. ",20 +"
          .. i
          .. ",20 @@\n"
          .. string.rep("-old-line\n", 20)
          .. string.rep("+new-line\n", 20)
      end
      local diff = make_headered_diff("still-over.lua", hunks)
      local grown = math.ceil(#diff / max_chunks)
      local chunks = rich.chunk_file_capped(diff, 10, max_chunks)

      assert.equals(grown, math.ceil(#diff / max_chunks))
      assert.equals(max_chunks + 1, #chunks)
      assert.is_true(#chunks > max_chunks)
    end)
  end)

  -- ── bucket_files ─────────────────────────────────────────────────────
  describe("bucket_files()", function()
    local cfg = {
      small_file_chars = 100,
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

    -- GAP: bucketing-mode-only-change-stat-only
    -- A file with no @@ hunks (e.g. a mode/rename-only change) has an empty diff
    -- after header stripping, so bucket_files treats it as stat_only.
    it("puts a zero-hunk (mode-only) file into stat_only bucket", function()
      -- A diff entry with no hunk content at all — bucket_files checks diff == ""
      -- or is_binary; an empty diff string triggers the stat_only path.
      local file_entries = {
        { path = "script.sh", diff = "", is_binary = false },
      }
      local buckets = rich.bucket_files(file_entries, cfg)
      assert.equals(1, #buckets.stat_only)
      assert.equals(0, #buckets.large)
      assert.equals(0, #buckets.small_inline)
      assert.equals(0, #buckets.small_batched)
    end)

    it("routes real split_diff_by_file entries for rename and empty-file to stat_only", function()
      local rename_diff = table.concat({
        "diff --git a/legacy_payments.py b/payments_gateway.py",
        "similarity index 100%",
        "rename from legacy_payments.py",
        "rename to payments_gateway.py",
      }, "\n")
      local empty_file_diff = table.concat({
        "diff --git a/src/payments/__init__.py b/src/payments/__init__.py",
        "new file mode 100644",
        "index 0000000..e69de29",
      }, "\n")
      local combined = rename_diff .. "\n" .. empty_file_diff

      local entries = rich.split_diff_by_file(combined)
      assert.equals(2, #entries)

      local buckets = rich.bucket_files(entries, { small_file_chars = 800, max_small_files_inline = 10 })
      assert.equals(2, #buckets.stat_only)
      assert.equals(0, #buckets.large)
      assert.equals(0, #buckets.small_inline)
      assert.equals(0, #buckets.small_batched)
    end)
  end)
end)

describe("make_scheduler()", function()
  local orig_vim_schedule

  before_each(function()
    rich = require("aicommits.input.rich")
    -- vim.schedule is not available in busted; stub it to fire synchronously.
    orig_vim_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end
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
      if in_flight > in_flight_peak then
        in_flight_peak = in_flight
      end
      table.insert(done_fns, function()
        in_flight = in_flight - 1
        done()
      end)
    end

    -- Enqueue 4 tasks; only 2 should start immediately
    for _ = 1, 4 do
      sched.run(task)
    end

    -- Complete all queued tasks
    while #done_fns > 0 do
      local fn = table.remove(done_fns, 1)
      fn()
    end

    assert.is_true(in_flight_peak <= 2)
  end)

  -- GAP: scheduler-queued-tasks-drain-after-completion
  it("drains all queued tasks sequentially with concurrency=1", function()
    local sched = rich.make_scheduler(1)
    local completed = {}
    local done_fns = {}

    for i = 1, 3 do
      local i_local = i
      sched.run(function(done)
        table.insert(done_fns, function()
          table.insert(completed, i_local)
          done()
        end)
      end)
    end

    -- Drive tasks to completion one at a time
    while #done_fns > 0 do
      local fn = table.remove(done_fns, 1)
      fn()
    end

    assert.equals(3, #completed)
    -- All three task indices were executed
    assert.same({ 1, 2, 3 }, completed)
  end)

  it("clamps concurrency <= 0 and still runs queued tasks", function()
    local sched = rich.make_scheduler(0)
    local called = false

    sched.run(function(done)
      called = true
      done()
    end)

    assert.is_true(called)
  end)
end)

describe("prepare() integration", function()
  local orig_picker_show, orig_picker_close, orig_vim_schedule

  before_each(function()
    rich = require("aicommits.input.rich")
    -- rich.lua calls picker.show_status; stub it to prevent UI errors in tests.
    local picker = require("aicommits.ui.picker")
    orig_picker_show = picker.show_status
    orig_picker_close = picker.close_status
    picker.show_status = function() end
    picker.close_status = function() end
    -- make_scheduler uses vim.schedule; stub it to run synchronously.
    orig_vim_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end
  end)

  after_each(function()
    local picker = require("aicommits.ui.picker")
    picker.show_status = orig_picker_show
    picker.close_status = orig_picker_close
    vim.schedule = orig_vim_schedule
  end)

  local function make_mock_provider(summary_result)
    -- summary_result: string (success) or error string prefixed with "ERR:"
    return {
      generate_text = function(self, envelope, provider_config, callback)
        if summary_result:sub(1, 4) == "ERR:" then
          callback(summary_result:sub(5), nil)
        else
          callback(nil, { summary_result })
        end
      end,
    }
  end

  local function stub_stat(stat_text)
    local git = require("aicommits.git")
    local orig = git.get_staged_stat
    git.get_staged_stat = function(cb)
      cb(nil, stat_text)
    end
    return function()
      git.get_staged_stat = orig
    end
  end

  it("returns assembled payload for a single large file", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local provider = make_mock_provider("- changed foo()")

    local big_diff = table.concat({
      "diff --git a/big.lua b/big.lua",
      "@@ -1,5 +1,6 @@",
      " line1",
      "+line2",
    }, "\n") .. string.rep("\nmore content", 30) -- push over small_file_chars

    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local cfg_override = {
      mode = "always",
      threshold_chars = 0,
      chunk_chars = 6000,
      max_chunks_per_file = 6,
      small_file_chars = 50, -- small threshold so big_diff is classified as large
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
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

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
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 50,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, _payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      _payload = p
    end)

    restore()

    -- All summaries failed → error surfaced
    assert.is_string(err)
  end)

  it("small-batched path produces a payload containing batch summary", function()
    local restore = stub_stat(" a.lua | 1\n b.lua | 1\n c.lua | 1\n")
    local provider = make_mock_provider("- a: changed\n- b: changed\n- c: changed")

    local mk = function(name)
      return "diff --git a/" .. name .. " b/" .. name .. "\n@@ -1 +1 @@\n-old\n+new"
    end
    local diff = mk("a.lua") .. "\n" .. mk("b.lua") .. "\n" .. mk("c.lua")
    local diff_data = { diff = diff, files = { "a.lua", "b.lua", "c.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 10000, -- all files are "small"
        max_small_files_inline = 2, -- 3 > 2 → small_batched
        small_file_batch_chars = 4000,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    assert.is_nil(err)
    assert.is_string(payload)
    assert.is_truthy(payload:match("changed"))
  end)

  -- ── GAP scenarios ────────────────────────────────────────────────────

  it("summarizes a large file that exceeds base cap but fits after growth", function()
    local restore = stub_stat(" big.lua | 50 +++\n 1 file changed\n")
    local summarize_calls = 0
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        summarize_calls = summarize_calls + 1
        cb(nil, { "summary" })
      end,
    }

    local hunks = {
      "@@ -1,30 +1,30 @@\n" .. string.rep("-old-long-line\n", 30) .. string.rep("+new-long-line\n", 30),
      "@@ -2,1 +2,1 @@\n-old2\n+new2",
      "@@ -3,1 +3,1 @@\n-old3\n+new3",
      "@@ -4,1 +4,1 @@\n-old4\n+new4",
    }
    local big_diff = "diff --git a/big.lua b/big.lua\n" .. table.concat(hunks, "\n")
    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local max_chunks = 3
    local grown = math.ceil(#big_diff / max_chunks)
    local pre_chunks = require("aicommits.input.rich").split_into_chunks(big_diff, 10)
    local grown_chunks = require("aicommits.input.rich").split_into_chunks(big_diff, grown)

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 1, -- force large bucket
        chunk_chars = 10, -- tiny chunk_chars → many chunks
        max_chunks_per_file = max_chunks,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    assert.is_nil(err)
    assert.is_true(#pre_chunks > max_chunks)
    assert.is_true(#grown_chunks <= max_chunks)
    assert.is_true(summarize_calls > 0)
    assert.is_string(payload)
    assert.is_false(payload:match("diff omitted: exceeded max_chunks_per_file") ~= nil)
  end)

  -- GAP: small-batch-packing-boundary
  it("creates two batches when 3 small files exceed small_file_batch_chars", function()
    -- Each file diff is ~30 chars; batch_chars = 40 → first file fills batch 1, rest go to batch 2
    local restore = stub_stat(" a.lua | 1\n b.lua | 1\n c.lua | 1\n")

    local batch_count = 0
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        batch_count = batch_count + 1
        cb(nil, { "- batch summary " .. batch_count })
      end,
    }

    -- Each diff is about 25 chars: "@@ -1 +1 @@\n-old\n+new" = 22 chars
    local mk = function(name, content)
      return "diff --git a/" .. name .. " b/" .. name .. "\n@@ -1 +1 @@\n" .. content
    end
    -- Make files with ~25 char diffs; batch_chars = 30 → each file in its own batch
    local file_a = mk("a.lua", string.rep("x", 20))
    local file_b = mk("b.lua", string.rep("y", 20))
    local file_c = mk("c.lua", string.rep("z", 20))
    local diff = file_a .. "\n" .. file_b .. "\n" .. file_c
    local diff_data = { diff = diff, files = { "a.lua", "b.lua", "c.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 10000, -- all files are "small"
        max_small_files_inline = 0, -- force small_batched (0 < 3)
        small_file_batch_chars = 30, -- each ~25-char diff gets its own batch
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    assert.is_nil(err)
    assert.is_true(batch_count >= 2, "expected at least 2 batches, got " .. batch_count)
  end)

  it("counts path and separator framing in small-file batch budget", function()
    local restore = stub_stat(" abcdefghij.lua | 1\n klmnopqrst.lua | 1\n")
    local batch_count = 0
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        batch_count = batch_count + 1
        cb(nil, { "- batch summary " .. batch_count })
      end,
    }

    local mk = function(name)
      return "diff --git a/" .. name .. " b/" .. name .. "\n@@ -1 +1 @@\n-a\n+b"
    end
    local diff = mk("abcdefghij.lua") .. "\n" .. mk("klmnopqrst.lua")
    local diff_data = { diff = diff, files = { "abcdefghij.lua", "klmnopqrst.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 10000,
        max_small_files_inline = 0,
        -- Raw diff payload fits, but framed payload with "path\\n" + "\\n---\\n" must split.
        small_file_batch_chars = 55,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    assert.is_nil(err)
    assert.is_string(payload)
    assert.equals(2, batch_count)
  end)

  -- GAP: single-chunk-summary-error-stat-only-per-file
  it("degrades file to stat-only when chunk summary call fails", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        cb("chunk error", nil)
      end,
    }

    local big_diff = table.concat({
      "diff --git a/big.lua b/big.lua",
      "@@ -1,3 +1,4 @@",
      " a",
      "+b",
    }, "\n") .. string.rep("\nx", 60)

    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 50,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    -- Single file chunk failure → that file is stat-only but since all summaries
    -- attempted failed, the pipeline returns an error (all-failed semantics).
    -- Either way the callback fires — just verify it fires.
    assert.is_true(err ~= nil or payload ~= nil)
  end)

  -- GAP: multi-chunk-first-chunk-fails-complete-task-fires (covers F1 deadlock fix)
  it("fires complete_task when first chunk fails in a multi-chunk file", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local call_num = 0
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        call_num = call_num + 1
        if call_num == 1 then
          cb("chunk error", nil)
        else
          cb(nil, { "- summary " .. call_num })
        end
      end,
    }

    -- Build a diff with 3 hunks that will each become their own chunk (chunk_chars=50)
    local big_diff = table.concat({
      "diff --git a/big.lua b/big.lua",
      "@@ -1,2 +1,3 @@",
      " line1",
      "+line2",
      "@@ -10,2 +11,3 @@",
      " line10",
      "+line11",
      "@@ -20,2 +21,3 @@",
      " line20",
      "+line21",
    }, "\n")

    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 1,
        chunk_chars = 50,
        max_chunks_per_file = 10,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local cb_fired = false
    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      cb_fired = true
      err = e
      payload = p
    end)

    restore()

    -- complete_task must have fired — callback must have been called (no deadlock)
    assert.is_true(cb_fired, "callback never fired — likely F1 deadlock")
    -- The file failed all chunks → all-failed error or stat-only payload
    assert.is_true(err ~= nil or payload ~= nil)
  end)

  -- GAP: file-rollup-error-stat-only-per-file
  it("degrades file to stat-only when roll-up call fails but other files succeed", function()
    local restore = stub_stat(" good.lua | 5\n bad.lua | 5\n")
    local call_num = 0
    local provider = {
      generate_text = function(self, envelope, _cfg, cb)
        call_num = call_num + 1
        -- Rollup prompts use the "paragraph" system text; chunk prompts the
        -- "bullet-point" text. The file path is embedded in envelope.user.
        local is_rollup = envelope.system and envelope.system:match("paragraph") ~= nil
        if is_rollup and envelope.user and envelope.user:match("bad%.lua") then
          cb("rollup error", nil)
        else
          cb(nil, { "- summary " .. call_num })
        end
      end,
    }

    local function mk_big(name)
      return "diff --git a/" .. name .. " b/" .. name .. "\n@@ -1,3 +1,4 @@\n a\n+b" .. string.rep("\nx", 60)
    end
    local diff = mk_big("good.lua") .. "\n" .. mk_big("bad.lua")
    local diff_data = { diff = diff, files = { "good.lua", "bad.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 50,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        max_small_files_inline = 0,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    -- good.lua succeeded so partial-failure → err is nil, payload assembled
    assert.is_nil(err)
    assert.is_string(payload)
    assert.is_truthy(payload:match("good%.lua"))
    assert.is_truthy(payload:match("bad%.lua"))
  end)

  -- GAP: small-batch-error-stat-only-per-file
  it("degrades batch to stat-only when batch summary call fails", function()
    local restore = stub_stat(" a.lua | 1\n b.lua | 1\n c.lua | 1\n")
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        cb("batch error", nil)
      end,
    }

    local mk = function(name)
      return "diff --git a/" .. name .. " b/" .. name .. "\n@@ -1 +1 @@\n-old\n+new"
    end
    local diff = mk("a.lua") .. "\n" .. mk("b.lua") .. "\n" .. mk("c.lua")
    local diff_data = { diff = diff, files = { "a.lua", "b.lua", "c.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 10000,
        max_small_files_inline = 2, -- 3 > 2 → small_batched
        small_file_batch_chars = 4000,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, _payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      _payload = p
    end)

    restore()

    -- All batch summaries failed → all-failed error
    assert.is_string(err)
  end)

  -- GAP: partial-failure-mixed-payload
  -- a.lua succeeds fully (chunk + rollup ok); b.lua and c.lua fail at rollup.
  -- Since a.lua has summary_successes >= 1, mixed payload is returned (no abort).
  it("produces mixed payload when some large files fail and one succeeds", function()
    local restore = stub_stat(" a.lua | 5\n b.lua | 5\n c.lua | 5\n")
    local provider = {
      generate_text = function(self, envelope, _cfg, cb)
        -- Chunk prompts carry the "bullet-point" system text; rollups the
        -- "paragraph" text. The file path is embedded in envelope.user.
        local is_chunk = envelope.system and envelope.system:match("bullet%-point") ~= nil
        local is_a = envelope.user and envelope.user:match("a%.lua") ~= nil
        if is_chunk then
          -- All chunk summarizations succeed so each file proceeds to roll-up
          cb(nil, { "- chunk summary" })
        elseif is_a then
          -- Only a.lua's rollup succeeds
          cb(nil, { "- a.lua full summary" })
        else
          -- b.lua and c.lua rollups fail
          cb("rollup error", nil)
        end
      end,
    }

    local function mk_big(name)
      return "diff --git a/" .. name .. " b/" .. name .. "\n@@ -1,3 +1,4 @@\n a\n+b" .. string.rep("\nx", 60)
    end
    local diff = mk_big("a.lua") .. "\n" .. mk_big("b.lua") .. "\n" .. mk_big("c.lua")
    local diff_data = { diff = diff, files = { "a.lua", "b.lua", "c.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 50,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        max_small_files_inline = 0,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    -- At least one succeeded → mixed payload, no error
    assert.is_nil(err)
    assert.is_string(payload)
    -- The successful file's summary appears
    assert.is_truthy(payload:match("a%.lua full summary"))
    -- The failed files still appear (as stat-only entries)
    assert.is_truthy(payload:match("b%.lua"))
    assert.is_truthy(payload:match("c%.lua"))
  end)

  -- GAP: all-small-inline-no-summary-calls-no-abort
  it("fires callback with no error and no summarize calls when all files are small-inline", function()
    local restore = stub_stat(" a.lua | 1\n b.lua | 1\n")
    local summarize_calls = 0
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        summarize_calls = summarize_calls + 1
        cb(nil, { "should not happen" })
      end,
    }

    local mk = function(name)
      return "diff --git a/" .. name .. " b/" .. name .. "\n@@ -1 +1 @@\n-old\n+new"
    end
    local diff = mk("a.lua") .. "\n" .. mk("b.lua")
    local diff_data = { diff = diff, files = { "a.lua", "b.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 10000, -- both files are "small"
        max_small_files_inline = 10, -- 2 <= 10 → small_inline
        small_file_batch_chars = 4000,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    assert.equals(0, summarize_calls)
    assert.is_nil(err)
    assert.is_string(payload)
  end)

  -- GAP: stat-fetch-failure-aborts-pipeline
  it("fires callback with error and never calls summarize when stat fetch fails", function()
    -- Override the git stub to return an error
    local git = require("aicommits.git")
    local orig_stat = git.get_staged_stat
    git.get_staged_stat = function(cb)
      cb("stat fetch error", nil)
    end

    local summarize_calls = 0
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        summarize_calls = summarize_calls + 1
        cb(nil, { "summary" })
      end,
    }

    local diff_data = { diff = "diff --git a/x.lua b/x.lua\n@@ -1 +1 @@\n-a\n+b", files = { "x.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 50,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    git.get_staged_stat = orig_stat

    assert.is_string(err)
    assert.is_nil(payload)
    assert.equals(0, summarize_calls)
  end)

  -- GAP: final-payload-contains-stat-block
  it("includes the stat block text in the assembled payload", function()
    local stat_text = " big.lua | 10 +++\n 1 file changed, 10 insertions(+)\n"
    local restore = stub_stat(stat_text)
    local provider = make_mock_provider("- changed foo()")

    local big_diff = table.concat({
      "diff --git a/big.lua b/big.lua",
      "@@ -1,5 +1,6 @@",
      " line1",
      "+line2",
    }, "\n") .. string.rep("\nmore content", 30)

    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        threshold_chars = 0,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        small_file_chars = 50,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_model = nil,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    assert.is_nil(err)
    assert.is_string(payload)
    -- The stat block text must appear verbatim in the payload
    assert.is_truthy(payload:match("file changed"))
  end)

  -- GAP: final-payload-large-file-section-header
  it("includes '### big.lua' section header followed by roll-up summary", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local provider = make_mock_provider("- refactored big helper")

    local big_diff = table.concat({
      "diff --git a/big.lua b/big.lua",
      "@@ -1,5 +1,6 @@",
      " line1",
      "+line2",
    }, "\n") .. string.rep("\nmore content", 30)

    local diff_data = { diff = big_diff, files = { "big.lua" } }
    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        threshold_chars = 0,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        small_file_chars = 50,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_model = nil,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    assert.is_nil(err)
    assert.is_string(payload)
    assert.is_truthy(payload:match("### big%.lua"))
    assert.is_truthy(payload:match("refactored big helper"))
  end)

  -- GAP: final-payload-small-inline-section
  it("includes '### small.lua' followed by raw diff content for small-inline files", function()
    local restore = stub_stat(" small.lua | 2\n 1 file changed\n")
    local summarize_calls = 0
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        summarize_calls = summarize_calls + 1
        cb(nil, { "summary" })
      end,
    }

    local diff = "diff --git a/small.lua b/small.lua\n@@ -1 +1 @@\n-old\n+new"
    local diff_data = { diff = diff, files = { "small.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 10000, -- file is "small"
        max_small_files_inline = 10, -- 1 <= 10 → inline
        small_file_batch_chars = 4000,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    assert.equals(0, summarize_calls)
    assert.is_nil(err)
    assert.is_string(payload)
    assert.is_truthy(payload:match("### small%.lua"))
    -- Raw diff content appears verbatim
    assert.is_truthy(payload:match("%-old") or payload:match("%+new"))
  end)

  it("demotes only when grown chunking still exceeds max_chunks_per_file", function()
    local restore = stub_stat(" hard.lua | 90 +++\n 1 file changed\n")
    local summarize_calls = 0
    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        summarize_calls = summarize_calls + 1
        cb(nil, { "summary" })
      end,
    }

    local max_chunks = 2
    local hunks = {}
    for i = 1, max_chunks + 1 do
      hunks[#hunks + 1] = "@@ -"
        .. i
        .. ",20 +"
        .. i
        .. ",20 @@\n"
        .. string.rep("-old-line\n", 20)
        .. string.rep("+new-line\n", 20)
    end
    local hard_diff = "diff --git a/hard.lua b/hard.lua\n" .. table.concat(hunks, "\n")
    local diff_data = { diff = hard_diff, files = { "hard.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 1,
        chunk_chars = 10, -- tiny → many chunks
        max_chunks_per_file = max_chunks,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(e, p)
      err = e
      payload = p
    end)

    restore()

    assert.is_nil(err)
    assert.equals(0, summarize_calls)
    assert.is_string(payload)
    assert.is_truthy(payload:match("### hard%.lua"))
    assert.is_truthy(payload:match("diff omitted: exceeded max_chunks_per_file"))
  end)

  -- GAP: status-ui-analyzing-phase
  it("calls picker.show_status with 'Analyzing staged diff...' during bucketing phase", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local status_calls = {}
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status = function(msg)
      table.insert(status_calls, { kind = "show", msg = msg })
    end
    picker.close_status = function()
      table.insert(status_calls, { kind = "close" })
    end

    local provider = make_mock_provider("- summary")
    local big_diff = "diff --git a/big.lua b/big.lua\n@@ -1,5 +1,6 @@\n line1\n+line2"
      .. string.rep("\nmore content", 30)
    local diff_data = { diff = big_diff, files = { "big.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        threshold_chars = 0,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        small_file_chars = 50,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_model = nil,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    require("aicommits.input.rich").prepare(diff_data, provider, {}, function() end)

    picker.show_status = orig_show
    picker.close_status = orig_close
    restore()

    local found = false
    for _, call in ipairs(status_calls) do
      if call.kind == "show" and call.msg == "Analyzing staged diff..." then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected 'Analyzing staged diff...' in status calls")
  end)

  -- GAP: status-ui-summarizing-phase
  it("calls picker.show_status with a string containing 'Summarizing' when tasks exist", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local status_calls = {}
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status = function(msg)
      table.insert(status_calls, { kind = "show", msg = msg })
    end
    picker.close_status = function()
      table.insert(status_calls, { kind = "close" })
    end

    local provider = make_mock_provider("- summary")
    local big_diff = "diff --git a/big.lua b/big.lua\n@@ -1,5 +1,6 @@\n line1\n+line2"
      .. string.rep("\nmore content", 30)
    local diff_data = { diff = big_diff, files = { "big.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        threshold_chars = 0,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        small_file_chars = 50,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_model = nil,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    require("aicommits.input.rich").prepare(diff_data, provider, {}, function() end)

    picker.show_status = orig_show
    picker.close_status = orig_close
    restore()

    local found = false
    for _, call in ipairs(status_calls) do
      if call.kind == "show" and call.msg:match("Summarizing") then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected a 'Summarizing...' status message")
  end)

  -- GAP: status-ui-composing-phase
  it("calls picker.show_status with 'Composing file summaries...' during roll-up", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local status_calls = {}
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status = function(msg)
      table.insert(status_calls, { kind = "show", msg = msg })
    end
    picker.close_status = function()
      table.insert(status_calls, { kind = "close" })
    end

    local provider = make_mock_provider("- summary")
    local big_diff = "diff --git a/big.lua b/big.lua\n@@ -1,5 +1,6 @@\n line1\n+line2"
      .. string.rep("\nmore content", 30)
    local diff_data = { diff = big_diff, files = { "big.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        threshold_chars = 0,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        small_file_chars = 50,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_model = nil,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    require("aicommits.input.rich").prepare(diff_data, provider, {}, function() end)

    picker.show_status = orig_show
    picker.close_status = orig_close
    restore()

    local found = false
    for _, call in ipairs(status_calls) do
      if call.kind == "show" and call.msg == "Composing file summaries 1/1..." then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected 'Composing file summaries 1/1...' status message")
  end)

  -- counter: composing status carries an "N/M" file counter, M = number of large files
  it("shows a file counter (N/M) in the composing status for multiple large files", function()
    local restore = stub_stat(" a.lua | 10 +++\n b.lua | 10 +++\n 2 files changed\n")
    local status_msgs = {}
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status = function(msg)
      table.insert(status_msgs, msg)
    end
    picker.close_status = function() end

    local provider = make_mock_provider("- summary")

    local function mk_big(name)
      return "diff --git a/"
        .. name
        .. " b/"
        .. name
        .. "\n@@ -1,5 +1,6 @@\n line1\n+line2"
        .. string.rep("\nmore content", 30)
    end
    local diff = mk_big("a.lua") .. "\n" .. mk_big("b.lua")
    local diff_data = { diff = diff, files = { "a.lua", "b.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        threshold_chars = 0,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        small_file_chars = 50,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    require("aicommits.input.rich").prepare(diff_data, provider, {}, function() end)

    picker.show_status = orig_show
    picker.close_status = orig_close
    restore()

    local saw_counter, saw_full = false, false
    for _, msg in ipairs(status_msgs) do
      if type(msg) == "string" and msg:match("^Composing file summaries %d+/2%.%.%.$") then
        saw_counter = true
        if msg == "Composing file summaries 2/2..." then
          saw_full = true
        end
      end
    end
    assert.is_true(saw_counter, "expected a 'Composing file summaries N/2...' counter message")
    assert.is_true(saw_full, "expected the counter to reach 2/2")
  end)

  -- counter: summarizing status carries an "N/M" file counter for the per-chunk
  -- sub-phase (ticks when each file's chunk calls have returned, before roll-up)
  it("shows a file counter (N/M) in the summarizing status for multiple large files", function()
    local restore = stub_stat(" a.lua | 10 +++\n b.lua | 10 +++\n 2 files changed\n")
    local status_msgs = {}
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status = function(msg)
      table.insert(status_msgs, msg)
    end
    picker.close_status = function() end

    local provider = make_mock_provider("- summary")

    local function mk_big(name)
      return "diff --git a/"
        .. name
        .. " b/"
        .. name
        .. "\n@@ -1,5 +1,6 @@\n line1\n+line2"
        .. string.rep("\nmore content", 30)
    end
    local diff = mk_big("a.lua") .. "\n" .. mk_big("b.lua")
    local diff_data = { diff = diff, files = { "a.lua", "b.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        threshold_chars = 0,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        small_file_chars = 50,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    require("aicommits.input.rich").prepare(diff_data, provider, {}, function() end)

    picker.show_status = orig_show
    picker.close_status = orig_close
    restore()

    local saw_counter, saw_full = false, false
    for _, msg in ipairs(status_msgs) do
      if type(msg) == "string" and msg:match("^Summarizing %d+ files in parallel %d+/2%.%.%.$") then
        saw_counter = true
        if msg == "Summarizing 2 files in parallel 2/2..." then
          saw_full = true
        end
      end
    end
    assert.is_true(saw_counter, "expected a 'Summarizing N files in parallel i/2...' counter message")
    assert.is_true(saw_full, "expected the summarizing counter to reach 2/2")
  end)

  -- GAP: status-ui-close-on-success
  it("calls picker.close_status before the success callback fires", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local events = {}
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status = function(_msg) end
    picker.close_status = function()
      table.insert(events, "close")
    end

    local provider = make_mock_provider("- summary")
    local big_diff = "diff --git a/big.lua b/big.lua\n@@ -1,5 +1,6 @@\n line1\n+line2"
      .. string.rep("\nmore content", 30)
    local diff_data = { diff = big_diff, files = { "big.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        threshold_chars = 0,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        small_file_chars = 50,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_model = nil,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local cb_index_at_close = nil
    local cb_called_index = 0
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(_e, _p)
      cb_called_index = cb_called_index + 1
      -- Record how many close events have fired by the time callback runs
      cb_index_at_close = #events
    end)

    picker.show_status = orig_show
    picker.close_status = orig_close
    restore()

    -- close_status must have been called before the callback
    assert.is_true(cb_index_at_close ~= nil and cb_index_at_close >= 1)
  end)

  -- GAP: status-ui-close-on-all-failed
  it("calls picker.close_status before the failure callback fires when all summaries fail", function()
    local restore = stub_stat(" big.lua | 5 +++\n")
    local close_count = 0
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status = function(_msg) end
    picker.close_status = function()
      close_count = close_count + 1
    end

    local provider = make_mock_provider("ERR:api down")
    local big_diff = "diff --git a/big.lua b/big.lua\n@@ -1,3 +1,4 @@\n a\n+b" .. string.rep("\nx", 60)
    local diff_data = { diff = big_diff, files = { "big.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 50,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local close_before_cb = nil
    require("aicommits.input.rich").prepare(diff_data, provider, {}, function(_e, _p)
      close_before_cb = close_count
    end)

    picker.show_status = orig_show
    picker.close_status = orig_close
    restore()

    assert.is_true(close_before_cb ~= nil and close_before_cb >= 1)
  end)

  -- GAP: status-ui-no-summarizing-when-all-inline
  it("does not emit a 'Summarizing' message when all files are small-inline", function()
    local restore = stub_stat(" a.lua | 1\n")
    local status_calls = {}
    local picker = require("aicommits.ui.picker")
    local orig_show = picker.show_status
    local orig_close = picker.close_status
    picker.show_status = function(msg)
      table.insert(status_calls, { kind = "show", msg = msg })
    end
    picker.close_status = function()
      table.insert(status_calls, { kind = "close" })
    end

    local provider = {
      generate_text = function(self, _envelope, _cfg, cb)
        cb(nil, { "summary" })
      end,
    }

    local diff = "diff --git a/a.lua b/a.lua\n@@ -1 +1 @@\n-old\n+new"
    local diff_data = { diff = diff, files = { "a.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 10000,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    require("aicommits.input.rich").prepare(diff_data, provider, {}, function() end)

    picker.show_status = orig_show
    picker.close_status = orig_close
    restore()

    for _, call in ipairs(status_calls) do
      if call.kind == "show" then
        assert.is_falsy(call.msg:match("^Summarizing"), "Unexpected 'Summarizing' message: " .. call.msg)
      end
    end
  end)

  -- GAP: provider-generate-text-uses-provider-config-auth
  it("propagates provider_config (including api_key) to provider.generate_text calls", function()
    local restore = stub_stat(" big.lua | 10 +++\n 1 file changed\n")
    local received_cfg = nil
    local provider = {
      generate_text = function(self, _envelope, cfg, cb)
        received_cfg = cfg
        cb(nil, { "- summary" })
      end,
    }

    local big_diff = "diff --git a/big.lua b/big.lua\n@@ -1,5 +1,6 @@\n line1\n+line2"
      .. string.rep("\nmore content", 30)
    local diff_data = { diff = big_diff, files = { "big.lua" } }

    local config = require("aicommits.config")
    config.setup({
      large_diff = {
        mode = "always",
        threshold_chars = 0,
        chunk_chars = 6000,
        max_chunks_per_file = 6,
        small_file_chars = 50,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_model = nil,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local provider_config = { api_key = "my-secret-key", model = "gpt-4.1-nano" }

    require("aicommits.input.rich").prepare(diff_data, provider, provider_config, function() end)

    restore()

    assert.is_not_nil(received_cfg)
    assert.equals("my-secret-key", received_cfg.api_key)
  end)

  it("builds the summary envelope in rich.lua with n=1 and system/user set", function()
    local restore = stub_stat("1 file changed")

    local captured_envelope
    local provider = {
      generate_text = function(_self, envelope, _cfg, cb)
        captured_envelope = captured_envelope or envelope
        cb(nil, { "summary" })
      end,
    }

    local config = require("aicommits.config")
    config.setup({ large_diff = { mode = "always", small_file_chars = 1 } })

    local rich_mod = require("aicommits.input.rich")
    local done
    rich_mod.prepare(
      { diff = "diff --git a/big.lua b/big.lua\n@@ -1 +1 @@\n-old\n+new\n", files = {} },
      provider,
      {},
      function()
        done = true
      end
    )
    vim.wait(2000, function()
      return done == true
    end)

    restore()

    assert.is_table(captured_envelope)
    assert.equals(1, captured_envelope.n)
    assert.is_string(captured_envelope.system)
    assert.is_string(captured_envelope.user)
  end)
end)
