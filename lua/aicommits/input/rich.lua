-- Rich input mode: summarization pipeline for large staged diffs.
local M = {}

-- Split a full git diff into per-file entries.
-- Each entry: { path = string, diff = string, is_binary = boolean, is_empty = boolean }
-- @param diff string  Full output of git diff --cached
-- @return table  Array of { path, diff, is_binary, is_empty }
function M.split_diff_by_file(diff)
  if not diff or diff == "" then return {} end

  local entries = {}
  local current_path = nil
  local current_lines = {}

  local function flush()
    if current_path then
      local file_diff = table.concat(current_lines, "\n")
      local is_binary = file_diff:match("Binary files") ~= nil  -- no ^ anchor: first line is 'diff --git' header
      -- No @@ hunk means there is no content to summarize (pure rename, mode-only
      -- change, or empty file add); flag it so bucket_files routes it to stat_only.
      -- The diff always starts with the 'diff --git' header, so a hunk header is
      -- always preceded by a newline. [FINDING-002]
      local is_empty = (not is_binary) and (file_diff:match("\n@@") == nil)
      table.insert(entries, {
        path = current_path, diff = file_diff, is_binary = is_binary, is_empty = is_empty,
      })
    end
  end

  for line in (diff .. "\n"):gmatch("([^\n]*)\n") do
    local path = line:match("^diff %-%-git a/.+ b/(.+)$")
    if not path then
      local quoted = line:match('^diff %-%-git "a/.*" "b/(.+)"$')
      if quoted then
        quoted = quoted:gsub("\\(.)", function(c)
          if c == "t" then return "\t" end
          if c == "n" then return "\n" end
          return c
        end)
        path = quoted
      end
    end
    if path then
      flush()
      current_path = path
      current_lines = { line }
    elseif current_path then
      table.insert(current_lines, line)
    end
  end
  flush()

  return entries
end

-- Split a single file's diff text into hunk-boundary chunks.
-- Hunks are never split mid-hunk; an oversized single hunk becomes its own chunk.
-- @param file_diff  string  Diff text for one file
-- @param chunk_chars number Maximum characters per chunk
-- @return table  Array of chunk strings
function M.split_into_chunks(file_diff, chunk_chars)
  if not file_diff or file_diff == "" then return {} end

  -- Collect individual hunks (split on @@ lines)
  local hunks = {}
  local current_hunk_lines = {}

  for line in (file_diff .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^@@") and #current_hunk_lines > 0 then
      table.insert(hunks, table.concat(current_hunk_lines, "\n"))
      current_hunk_lines = { line }
    else
      table.insert(current_hunk_lines, line)
    end
  end
  if #current_hunk_lines > 0 then
    table.insert(hunks, table.concat(current_hunk_lines, "\n"))
  end

  -- Pack hunks into chunks without splitting mid-hunk
  local chunks = {}
  local current_chunk_parts = {}
  local current_chunk_len = 0

  for _, hunk in ipairs(hunks) do
    local hlen = #hunk
    if #current_chunk_parts == 0 then
      -- Always start a new chunk with the first hunk
      table.insert(current_chunk_parts, hunk)
      current_chunk_len = hlen
    elseif current_chunk_len + 1 + hlen <= chunk_chars then
      table.insert(current_chunk_parts, hunk)
      current_chunk_len = current_chunk_len + 1 + hlen
    else
      table.insert(chunks, table.concat(current_chunk_parts, "\n"))
      current_chunk_parts = { hunk }
      current_chunk_len = hlen
    end
  end

  if #current_chunk_parts > 0 then
    table.insert(chunks, table.concat(current_chunk_parts, "\n"))
  end

  return chunks
end

-- Classify per-file diff entries into buckets.
-- Returns { large = [], small_inline = [], small_batched = [], stat_only = [] }
-- @param file_entries table  Array of { path, diff, is_binary, is_empty } from split_diff_by_file
-- @param cfg          table  large_diff config subset: { small_file_chars, max_small_files_inline }
-- @return table  Bucket table
function M.bucket_files(file_entries, cfg)
  local large        = {}
  local smalls       = {}
  local stat_only    = {}

  for _, entry in ipairs(file_entries) do
    if entry.is_binary or entry.diff == "" or entry.is_empty then
      table.insert(stat_only, entry)
    elseif #entry.diff > cfg.small_file_chars then
      table.insert(large, entry)
    else
      table.insert(smalls, entry)
    end
  end

  local small_inline   = {}
  local small_batched  = {}

  if #smalls <= cfg.max_small_files_inline then
    small_inline  = smalls
  else
    small_batched = smalls
  end

  return {
    large        = large,
    small_inline = small_inline,
    small_batched = small_batched,
    stat_only    = stat_only,
  }
end

-- Create a concurrency-bounded scheduler.
-- Tasks are functions with signature: fn(done) where done() signals completion.
-- @param concurrency number  Maximum parallel tasks
-- @return table { run = function(fn) }
function M.make_scheduler(concurrency)
  concurrency = math.max(1, math.floor(tonumber(concurrency) or 1))
  local in_flight = 0
  local pending   = {}

  local function try_dispatch()
    while in_flight < concurrency and #pending > 0 do
      local fn = table.remove(pending, 1)
      in_flight = in_flight + 1
      vim.schedule(function()
        fn(function()
          in_flight = in_flight - 1
          try_dispatch()
        end)
      end)
    end
  end

  return {
    run = function(fn)
      table.insert(pending, fn)
      try_dispatch()
    end,
  }
end

-- Pack small files into batches respecting small_file_batch_chars budget.
-- @param entries table  Array of file entries (small_batched bucket)
-- @param batch_chars number
-- @return table  Array of batch arrays
local function pack_small_batches(entries, batch_chars)
  local SEP = "\n---\n"
  local batches = {}
  local current_batch = {}
  local current_len = 0

  for _, entry in ipairs(entries) do
    local entry_len = #entry.path + 1 + #entry.diff
    local added = entry_len + ((#current_batch > 0) and #SEP or 0)
    if #current_batch > 0 and current_len + added > batch_chars then
      table.insert(batches, current_batch)
      current_batch = { entry }
      current_len = entry_len
    else
      table.insert(current_batch, entry)
      current_len = current_len + added
    end
  end

  if #current_batch > 0 then
    table.insert(batches, current_batch)
  end

  return batches
end

-- Assemble the final prompt string from all pipeline results.
-- @param stat_string      string
-- @param large_results    table  Array of { path, summary or stat_line, is_stat }
-- @param inline_entries   table  Array of { path, diff }
-- @param batch_results    table  Array of { paths, summary or nil, is_stat }
-- @param stat_only_entries table  Array of { path, diff, is_binary } (binary files, pure renames, mode-only / empty diffs)
-- @return string
local function assemble_prompt(stat_string, large_results, inline_entries, batch_results, stat_only_entries)
  local parts = {}

  table.insert(parts, "## Staged Changes Overview\n\n" .. stat_string)

  -- Large file sections
  for _, r in ipairs(large_results) do
    if r.is_stat then
      table.insert(parts, string.format("### %s\n%s", r.path, r.stat_line))
    else
      table.insert(parts, string.format("### %s\n%s", r.path, r.summary))
    end
  end

  -- Small-inline sections
  for _, entry in ipairs(inline_entries) do
    table.insert(parts, string.format("### %s\n```diff\n%s\n```", entry.path, entry.diff))
  end

  -- Batch summary sections
  for i, br in ipairs(batch_results) do
    local paths_str = table.concat(br.paths, ", ")
    if br.is_stat then
      table.insert(parts, string.format(
        "### Batch %d (%s)\n(summary unavailable — stat only)", i, paths_str))
    else
      table.insert(parts, string.format(
        "### Batch %d (%s)\n%s", i, paths_str, br.summary))
    end
  end

  -- Stat-only sections (binary files, empty-diff / pure renames)
  for _, entry in ipairs(stat_only_entries or {}) do
    table.insert(parts, string.format("### %s\n(binary or empty diff — stat only)", entry.path))
  end

  return table.concat(parts, "\n\n")
end

-- Prepare the final commit-message payload via the summarization pipeline.
-- @param diff_data      table   { diff = string, files = table }
-- @param provider       table   Provider instance (must implement :summarize())
-- @param provider_config table  Passed as-is to provider:summarize()
-- @param callback       function(error, final_payload)
function M.prepare(diff_data, provider, provider_config, callback)
  local config    = require("aicommits.config")
  local git       = require("aicommits.git")
  local picker    = require("aicommits.ui.picker")
  local ld_cfg    = config.get("large_diff")

  picker.show_status("Analyzing staged diff...")

  -- 1. Fetch stat
  git.get_staged_stat(function(stat_err, stat_string)
    if stat_err then
      picker.close_status()
      callback("Failed to get staged stat: " .. stat_err, nil)
      return
    end

    -- 2. Split and bucket
    local file_entries = M.split_diff_by_file(diff_data.diff)
    local buckets      = M.bucket_files(file_entries, ld_cfg)

    local sched = M.make_scheduler(ld_cfg.concurrency)
    -- A separate uncapped scheduler (concurrency = math.huge) is used for per-chunk calls
    -- within a large-file task so that inner chunk tasks never block waiting for outer task
    -- slots — which would deadlock when ld_cfg.concurrency is 1. [inferred]
    local chunk_sched = M.make_scheduler(math.huge)

    -- Track results
    local large_results = {}    -- { path, summary?, stat_line?, is_stat }
    local batch_results = {}    -- { paths, summary?, is_stat }

    local summary_attempts  = 0
    local summary_successes = 0

    -- Pre-populate large_results order
    for _, entry in ipairs(buckets.large) do
      table.insert(large_results, { path = entry.path, is_stat = true,
        stat_line = entry.path .. " (summary pending)" })
    end

    -- Pre-populate batch_results
    local batches = pack_small_batches(buckets.small_batched, ld_cfg.small_file_batch_chars)
    for _, batch in ipairs(batches) do
      local paths = {}
      for _, e in ipairs(batch) do table.insert(paths, e.path) end
      table.insert(batch_results, { paths = paths, is_stat = true })
    end

    local total_tasks = 0
    local done_tasks  = 0

    local function check_done()
      if done_tasks == total_tasks then
        -- Partial-failure semantics: if ≥1 summary succeeded, assemble a mixed payload
        -- where failed files appear as stat-only entries (already set on each failure path).
        -- Only abort when zero summaries succeeded out of those attempted. [inferred]
        if summary_attempts > 0 and summary_successes == 0 then
          picker.close_status()  -- close status before surfacing the all-failed error
          callback("All summary calls failed (0/" .. summary_attempts .. " succeeded); aborting rich input pipeline.", nil)
          return
        end

        local payload = assemble_prompt(
          stat_string, large_results, buckets.small_inline, batch_results, buckets.stat_only)
        picker.close_status()  -- close status before handing off to generate_commit_message
        callback(nil, payload)
      end
    end

    -- Count total async tasks: one per large file (chunks + rollup counted as one task group),
    -- one per batch.
    total_tasks = #buckets.large + #batches
    if total_tasks == 0 then
      -- Only small-inline files — assemble immediately
      local payload = assemble_prompt(stat_string, {}, buckets.small_inline, {}, buckets.stat_only)
      picker.close_status()  -- close status opened above before handing off
      callback(nil, payload)
      return
    end

    picker.show_status(string.format(
      "Summarizing %d files in parallel...", #buckets.large + #batches))

    -- ── Large file tasks ─────────────────────────────────────────────
    for idx, entry in ipairs(buckets.large) do
      local entry_idx = idx
      local local_entry = entry

      sched.run(function(task_done)
        -- Guard against double-completion from nested chunk/rollup paths. [inferred]
        local task_completed = false
        local function complete_task()
          if task_completed then return end
          task_completed = true
          done_tasks = done_tasks + 1
          task_done()
          check_done()
        end

        local chunks = M.split_into_chunks(local_entry.diff, ld_cfg.chunk_chars)

        -- Overflow check: when a file exceeds max_chunks_per_file it is demoted to
        -- stat-only and complete_task() is called immediately WITHOUT incrementing
        -- summary_attempts, so overflow files never count toward the all-failed
        -- threshold in check_done(). [inferred]
        if #chunks > ld_cfg.max_chunks_per_file then
          large_results[entry_idx] = {
            path = local_entry.path, is_stat = true,
            stat_line = local_entry.path
              .. " (diff omitted: exceeded max_chunks_per_file)",
          }
          complete_task()
          return
        end

        -- Per-chunk summaries
        local chunk_summaries = {}
        local chunk_err_flag  = false
        local chunks_done = 0

        if #chunks == 0 then
          -- No hunks — stat only
          large_results[entry_idx] = {
            path = local_entry.path, is_stat = true,
            stat_line = local_entry.path .. " (no hunks)",
          }
          complete_task()
          return
        end

        summary_attempts = summary_attempts + 1

        for c_idx, chunk in ipairs(chunks) do
          local c_idx_local = c_idx
          chunk_sched.run(function(chunk_done)  -- uses inner uncapped scheduler to avoid deadlock [inferred]
            if chunk_err_flag then
              chunks_done = chunks_done + 1
              chunk_done()
              if chunks_done == #chunks then
                large_results[entry_idx] = {
                  path = local_entry.path, is_stat = true,
                  stat_line = local_entry.path .. " (summary failed)",
                }
                complete_task()
              end
              return
            end
            provider:summarize(chunk,
              { prompt_kind = "chunk", file_path = local_entry.path,
                model = ld_cfg.summary_model,
                max_tokens = ld_cfg.summary_max_tokens,
                temperature = ld_cfg.summary_temperature },
              provider_config,
              function(err, summary_text)
                if err then
                  chunk_err_flag = true
                end
                chunk_summaries[c_idx_local] = summary_text or ""
                chunks_done = chunks_done + 1
                chunk_done()

                if chunks_done == #chunks then
                  if chunk_err_flag then
                    large_results[entry_idx] = {
                      path = local_entry.path, is_stat = true,
                      stat_line = local_entry.path .. " (summary failed)",
                    }
                    complete_task()
                    return
                  end

                  -- Roll-up
                  picker.show_status("Composing file summaries...")
                  summary_attempts = summary_attempts + 1
                  local combined = table.concat(chunk_summaries, "\n")
                  provider:summarize(combined,
                    { prompt_kind = "file_rollup", file_path = local_entry.path,
                      model = ld_cfg.summary_model,
                      max_tokens = ld_cfg.summary_max_tokens,
                      temperature = ld_cfg.summary_temperature },
                    provider_config,
                    function(rollup_err, rollup_text)
                      if rollup_err then
                        large_results[entry_idx] = {
                          path = local_entry.path, is_stat = true,
                          stat_line = local_entry.path .. " (rollup failed)",
                        }
                      else
                        summary_successes = summary_successes + 1
                        large_results[entry_idx] = {
                          path = local_entry.path, is_stat = false,
                          summary = rollup_text,
                        }
                      end
                      complete_task()
                    end)
                end
              end)
          end)
        end
      end)
    end

    -- ── Small-batch tasks ─────────────────────────────────────────────
    for b_idx, batch in ipairs(batches) do
      local b_idx_local = b_idx
      local local_batch = batch

      sched.run(function(task_done)
        -- Build payload
        local parts = {}
        for _, e in ipairs(local_batch) do
          table.insert(parts, e.path .. "\n" .. e.diff)
        end
        local batch_payload = table.concat(parts, "\n---\n")

        summary_attempts = summary_attempts + 1
        provider:summarize(batch_payload,
          { prompt_kind = "small_batch",
            model = ld_cfg.summary_model,
            max_tokens = ld_cfg.summary_max_tokens,
            temperature = ld_cfg.summary_temperature },
          provider_config,
          function(err, summary_text)
            if err then
              batch_results[b_idx_local].is_stat = true
            else
              summary_successes = summary_successes + 1
              batch_results[b_idx_local].is_stat = false
              batch_results[b_idx_local].summary = summary_text
            end
            done_tasks = done_tasks + 1
            task_done()
            check_done()
          end)
      end)
    end
  end)
end

return M
