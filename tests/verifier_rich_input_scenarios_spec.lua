local rich
local config

local function make_hunk(idx, n_lines)
  local lines = { string.format("@@ -%d,%d +%d,%d @@", idx, n_lines, idx, n_lines) }
  for i = 1, n_lines do
    lines[#lines + 1] = string.format("-old_%d_%d", idx, i)
    lines[#lines + 1] = string.format("+new_%d_%d", idx, i)
  end
  return table.concat(lines, "\n")
end

local function make_header(path)
  return table.concat({
    "diff --git a/" .. path .. " b/" .. path,
    "index 1111111..2222222 100644",
    "--- a/" .. path,
    "+++ b/" .. path,
  }, "\n")
end

local function make_headered_diff(path, hunks)
  return table.concat({
    make_header(path),
    table.concat(hunks, "\n"),
  }, "\n")
end

local function count_hunks(chunk)
  local count = 0
  for line in (chunk .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^@@") then
      count = count + 1
    end
  end
  return count
end

local function with_stubbed_stat(stat_text, fn)
  local git = require("aicommits.git")
  local orig = git.get_staged_stat
  git.get_staged_stat = function(cb)
    cb(nil, stat_text)
  end

  local ok, err = pcall(fn)
  git.get_staged_stat = orig
  if not ok then
    error(err)
  end
end

describe("verifier rich-input scenarios", function()
  local orig_schedule
  local orig_picker_show
  local orig_picker_close

  before_each(function()
    package.loaded["aicommits.input.rich"] = nil
    package.loaded["aicommits.config"] = nil

    rich = require("aicommits.input.rich")
    config = require("aicommits.config")
    config.setup({})

    orig_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end

    local picker = require("aicommits.ui.picker")
    orig_picker_show = picker.show_status
    orig_picker_close = picker.close_status
    picker.show_status = function() end
    picker.close_status = function() end
  end)

  after_each(function()
    vim.schedule = orig_schedule
    local picker = require("aicommits.ui.picker")
    picker.show_status = orig_picker_show
    picker.close_status = orig_picker_close
  end)

  it("scenario 1: keeps header-less hunk chunking byte-for-byte unchanged", function()
    local h1 = make_hunk(1, 2)
    local h2 = make_hunk(2, 2)
    local file_diff = table.concat({ h1, h2 }, "\n")

    local chunks = rich.split_into_chunks(file_diff, #h1)

    assert.same({ h1, h2 }, chunks)
    assert.is_falsy(chunks[1]:match("^diff %-%-git"))
  end)

  it("scenario 2: replays file header into every emitted chunk", function()
    local h1 = make_hunk(1, 3)
    local h2 = make_hunk(2, 3)
    local h3 = make_hunk(3, 3)
    local diff = make_headered_diff("big.lua", { h1, h2, h3 })
    local header = make_header("big.lua")
    local chunk_chars = #header + 1 + #h1

    local chunks = rich.split_into_chunks(diff, chunk_chars)

    assert.is_true(#chunks >= 3)
    for _, chunk in ipairs(chunks) do
      assert.is_truthy(chunk:match("^diff %-%-git a/big%.lua b/big%.lua"))
      assert.is_truthy(chunk:match("\n@@ "))
    end
  end)

  it("scenario 3: charges header bytes against the chunk size budget", function()
    local h1 = make_hunk(1, 2)
    local h2 = make_hunk(2, 2)
    local diff = make_headered_diff("budget.lua", { h1, h2 })
    local chunk_chars = #h1 + 1 + #h2

    local chunks = rich.split_into_chunks(diff, chunk_chars)

    assert.equals(2, #chunks)
    assert.equals(1, count_hunks(chunks[1]))
    assert.equals(1, count_hunks(chunks[2]))
  end)

  it("scenario 4: returns no chunks for header-only diffs", function()
    local header_only = make_header("rename_only.lua")
    local chunks = rich.split_into_chunks(header_only, 1000)
    assert.same({}, chunks)
  end)

  it("scenario 5: grows chunk size before max-chunk demotion", function()
    local hunks = {
      "@@ -1,30 +1,30 @@\n" .. string.rep("-old-line\n", 30) .. string.rep("+new-line\n", 30),
      "@@ -2,1 +2,1 @@\n-old2\n+new2",
      "@@ -3,1 +3,1 @@\n-old3\n+new3",
      "@@ -4,1 +4,1 @@\n-old4\n+new4",
    }
    local diff = make_headered_diff("grow.lua", hunks)
    local max_chunks = 3
    local grown = math.ceil(#diff / max_chunks)

    local base_chunks = rich.split_into_chunks(diff, 10)
    local capped = rich.chunk_file_capped(diff, 10, max_chunks)
    local grown_chunks = rich.split_into_chunks(diff, grown)

    assert.is_true(#base_chunks > max_chunks)
    assert.is_true(#grown_chunks <= max_chunks)
    assert.is_true(#capped <= max_chunks)
    assert.equals(#grown_chunks, #capped)
  end)

  it("scenario 6: keeps grow-success large files in the large bucket", function()
    local hunks = {
      "@@ -1,30 +1,30 @@\n" .. string.rep("-old-line\n", 30) .. string.rep("+new-line\n", 30),
      "@@ -2,1 +2,1 @@\n-old2\n+new2",
      "@@ -3,1 +3,1 @@\n-old3\n+new3",
      "@@ -4,1 +4,1 @@\n-old4\n+new4",
    }
    local entry = {
      path = "grow-success.lua",
      diff = make_headered_diff("grow-success.lua", hunks),
      is_binary = false,
      is_empty = false,
    }

    local chunks = rich.chunk_file_capped(entry.diff, 10, 3)
    local buckets = rich.bucket_files({ entry }, { small_file_chars = 1, max_small_files_inline = 10 })

    assert.is_true(#chunks <= 3)
    assert.equals(1, #buckets.large)
    assert.equals(0, #buckets.stat_only)
  end)

  it("scenario 7: prepare summarizes grown chunks without overflow demotion note", function()
    local summarize_calls = 0
    local provider = {
      generate_text = function(self, _envelope, _provider_config, cb)
        summarize_calls = summarize_calls + 1
        cb(nil, { "summary" })
      end,
    }

    local hunks = {
      "@@ -1,30 +1,30 @@\n" .. string.rep("-old-line\n", 30) .. string.rep("+new-line\n", 30),
      "@@ -2,1 +2,1 @@\n-old2\n+new2",
      "@@ -3,1 +3,1 @@\n-old3\n+new3",
      "@@ -4,1 +4,1 @@\n-old4\n+new4",
    }
    local diff = make_headered_diff("big.lua", hunks)
    local diff_data = { diff = diff, files = { "big.lua" } }

    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 1,
        chunk_chars = 10,
        max_chunks_per_file = 3,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    with_stubbed_stat(" big.lua | 50 +++\n 1 file changed\n", function()
      rich.prepare(diff_data, provider, {}, function(e, p)
        err = e
        payload = p
      end)
    end)

    assert.is_nil(err)
    assert.is_true(summarize_calls > 0)
    assert.is_string(payload)
    assert.is_falsy(payload:match("diff omitted: exceeded max_chunks_per_file"))
  end)

  it("scenario 8: hard ceiling still demotes pathological files after growth", function()
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
    local diff = make_headered_diff("hard.lua", hunks)
    local grown = math.ceil(#diff / max_chunks)
    local capped = rich.chunk_file_capped(diff, 10, max_chunks)

    local summarize_calls = 0
    local provider = {
      generate_text = function(self, _envelope, _provider_config, cb)
        summarize_calls = summarize_calls + 1
        cb(nil, { "summary" })
      end,
    }

    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 1,
        chunk_chars = 10,
        max_chunks_per_file = max_chunks,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    with_stubbed_stat(" hard.lua | 90 +++\n 1 file changed\n", function()
      rich.prepare({ diff = diff, files = { "hard.lua" } }, provider, {}, function(e, p)
        err = e
        payload = p
      end)
    end)

    assert.equals(grown, math.ceil(#diff / max_chunks))
    assert.equals(max_chunks + 1, #capped)
    assert.equals(0, summarize_calls)
    assert.is_nil(err)
    assert.is_string(payload)
    assert.is_truthy(payload:match("diff omitted: exceeded max_chunks_per_file"))
  end)

  it("scenario 9: binary, empty, and rename-only files stay stat-only and skip chunk summarization", function()
    local combined = table.concat({
      "diff --git a/img.png b/img.png",
      "Binary files a/img.png and b/img.png differ",
      "diff --git a/empty.lua b/empty.lua",
      "new file mode 100644",
      "index 0000000..e69de29",
      "diff --git a/legacy_payments.py b/payments_gateway.py",
      "similarity index 100%",
      "rename from legacy_payments.py",
      "rename to payments_gateway.py",
    }, "\n")

    local entries = rich.split_diff_by_file(combined)
    local buckets = rich.bucket_files(entries, { small_file_chars = 1, max_small_files_inline = 10 })

    local chunk_file_capped_calls = 0
    local orig_chunk_file_capped = rich.chunk_file_capped
    rich.chunk_file_capped = function(...)
      chunk_file_capped_calls = chunk_file_capped_calls + 1
      return orig_chunk_file_capped(...)
    end

    local summarize_calls = 0
    local provider = {
      generate_text = function(self, _envelope, _provider_config, cb)
        summarize_calls = summarize_calls + 1
        cb(nil, { "summary" })
      end,
    }

    config.setup({
      large_diff = {
        mode = "always",
        small_file_chars = 1,
        chunk_chars = 10,
        max_chunks_per_file = 2,
        max_small_files_inline = 10,
        small_file_batch_chars = 4000,
        summary_max_tokens = 220,
        summary_temperature = 0.2,
        concurrency = 4,
      },
    })

    local err, payload
    with_stubbed_stat(" img.png | Bin\n empty.lua | 0\n payments_gateway.py | 0\n", function()
      rich.prepare(
        { diff = combined, files = { "img.png", "empty.lua", "payments_gateway.py" } },
        provider,
        {},
        function(e, p)
          err = e
          payload = p
        end
      )
    end)

    rich.chunk_file_capped = orig_chunk_file_capped

    assert.equals(3, #entries)
    assert.equals(3, #buckets.stat_only)
    assert.equals(0, #buckets.large)
    assert.equals(0, #buckets.small_inline)
    assert.equals(0, #buckets.small_batched)
    assert.equals(0, chunk_file_capped_calls)
    assert.equals(0, summarize_calls)
    assert.is_nil(err)
    assert.is_truthy(payload:match("binary or empty diff"))
  end)

  it("scenario 10: rejects invalid large_diff.max_chunks_per_file values", function()
    for _, invalid in ipairs({ 0, 2.5, "three" }) do
      config.setup({ large_diff = { mode = "auto", max_chunks_per_file = invalid } })
      local ok, errors = config.validate()
      assert.is_false(ok)
      assert.is_truthy(table.concat(errors, "\n"):match("large_diff%.max_chunks_per_file"))
    end
  end)

  it("scenario 11: accepts positive integer large_diff.max_chunks_per_file", function()
    config.setup({ large_diff = { mode = "auto", max_chunks_per_file = 3 } })
    local ok, errors = config.validate()
    assert.is_true(ok)
    assert.equals(0, #errors)
  end)

  it("scenario 12: keeps unrelated small-inline rich-input behavior unchanged", function()
    local summarize_calls = 0
    local provider = {
      generate_text = function(self, _envelope, _provider_config, cb)
        summarize_calls = summarize_calls + 1
        cb(nil, { "unused" })
      end,
    }

    local diff = table.concat({
      "diff --git a/small.lua b/small.lua",
      "@@ -1 +1 @@",
      "-old",
      "+new",
    }, "\n")

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

    local err, payload
    with_stubbed_stat(" small.lua | 2 +-\n 1 file changed\n", function()
      rich.prepare({ diff = diff, files = { "small.lua" } }, provider, {}, function(e, p)
        err = e
        payload = p
      end)
    end)

    assert.is_nil(err)
    assert.equals(0, summarize_calls)
    assert.is_truthy(payload:match("### small%.lua"))
    assert.is_truthy(payload:match("%-old"))
    assert.is_truthy(payload:match("%+new"))
  end)
end)
