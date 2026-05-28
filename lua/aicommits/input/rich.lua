-- Rich input mode: summarization pipeline for large staged diffs.
local M = {}

-- Split a full git diff into per-file entries.
-- Each entry: { path = string, diff = string, is_binary = boolean }
-- @param diff string  Full output of git diff --cached
-- @return table  Array of { path, diff, is_binary }
function M.split_diff_by_file(diff)
  if not diff or diff == "" then return {} end

  local entries = {}
  local current_path = nil
  local current_lines = {}

  local function flush()
    if current_path then
      local file_diff = table.concat(current_lines, "\n")
      local is_binary = file_diff:match("Binary files") ~= nil  -- no ^ anchor: first line is 'diff --git' header
      table.insert(entries, { path = current_path, diff = file_diff, is_binary = is_binary })
    end
  end

  for line in (diff .. "\n"):gmatch("([^\n]*)\n") do
    local path = line:match("^diff %-%-git a/.+ b/(.+)$")
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
-- @param file_entries table  Array of { path, diff, is_binary } from split_diff_by_file
-- @param cfg          table  large_diff config subset: { small_file_chars, max_small_files_inline }
-- @return table  Bucket table
function M.bucket_files(file_entries, cfg)
  local large        = {}
  local smalls       = {}
  local stat_only    = {}

  for _, entry in ipairs(file_entries) do
    if entry.is_binary or entry.diff == "" then
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

return M
