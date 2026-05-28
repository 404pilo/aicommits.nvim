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
