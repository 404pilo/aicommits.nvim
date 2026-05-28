-- Prompt engineering and message processing for aicommits.nvim
-- This module contains provider-agnostic prompt building and response processing logic

local M = {}

-- Build system prompt for conventional commit message generation
-- This prompt defines the format, rules, and structure for all AI providers
-- @param max_length number Maximum commit message length
-- @param commitlint_config string|nil Optional commitlint config content to enforce
-- @return string The system prompt to send to any AI provider
function M.build_system_prompt(max_length, commitlint_config)
  local commit_types = {
    docs = "Documentation only changes",
    style = "Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc)",
    refactor = "A code change that neither fixes a bug nor adds a feature",
    perf = "A code change that improves performance",
    test = "Adding missing tests or correcting existing tests",
    build = "Changes that affect the build system or external dependencies",
    ci = "Changes to our CI configuration files and scripts",
    chore = "Other changes that don't modify src or test files",
    revert = "Reverts a previous commit",
    feat = "A new feature",
    fix = "A bug fix",
  }

  local parts = {
    "Generate a single-sentence git commit message in present tense for the following diff.",
    "The message MUST be no more than 12 words. Be extremely brief.",
    "Message language: en",
    string.format("Commit message must be a maximum of %d characters.", max_length),
    "Exclude anything unnecessary such as translation. Your entire response will be passed directly into git commit.",
    "Strictly follow Conventional Commits 1.0.0 spec. The message MUST pass commitlint with @commitlint/config-conventional rules:",
    "- Subject line: lowercase, no period at end, imperative mood, no trailing whitespace.",
    "- Type MUST be one of the allowed types below. Scope is optional and lowercase.",
    "- Header (type + scope + subject) must not exceed " .. tostring(max_length) .. " characters total.",
    "- Do NOT include a body or footer. Output only the single header line.",
    "Choose a type from the type-to-description JSON below that best describes the git diff:",
    vim.json.encode(commit_types),
    "The output response must be in format:",
    "<type>(<optional scope>): <commit message>",
  }

  if commitlint_config then
    table.insert(parts, "IMPORTANT: The following commitlint rules are STRICTLY ENFORCED in this repository.")
    table.insert(parts, "You MUST follow every rule exactly. Violating any rule is not acceptable.")
    table.insert(parts, commitlint_config)
    table.insert(parts, "Double-check your message against every rule above before responding.")
  end

  return table.concat(parts, "\n")
end

-- Process and sanitize commit messages from AI provider responses
-- Performs deduplication, trimming, and cleanup of generated messages
-- @param messages table Array of raw commit messages from AI provider
-- @return table Array of sanitized, unique messages
function M.process_messages(messages)
  local seen = {}
  local result = {}

  for _, msg in ipairs(messages) do
    -- Sanitize: trim whitespace
    local sanitized = msg:gsub("^%s+", ""):gsub("%s+$", "")

    -- Remove newlines and carriage returns
    sanitized = sanitized:gsub("[\n\r]", "")

    -- Remove trailing period if present after a word character
    sanitized = sanitized:gsub("(%w)%.$", "%1")

    -- Deduplicate: only add if we haven't seen this message and it's not empty
    if not seen[sanitized] and sanitized ~= "" then
      seen[sanitized] = true
      table.insert(result, sanitized)
    end
  end

  return result
end

-- Build a prompt pair for summarization calls
-- @param kind  string  "chunk" | "file_rollup" | "small_batch"
-- @param payload string  The diff text or batch of chunk summaries
-- @param opts  table   { file_path = string|nil }
-- @return table { system = string, user = string }
function M.build_summary_prompt(kind, payload, opts)
  opts = opts or {}
  if kind == "chunk" then
    return {
      system = "You are a code-change summarizer. Produce a concise bullet-point summary"
        .. " (<=5 bullets, no markdown headers) of what this diff chunk changes."
        .. " Be specific: name functions, variables, or config keys that are added,"
        .. " removed, or modified.",
      user = string.format("File: %s\n\n%s", opts.file_path or "(unknown)", payload),
    }
  elseif kind == "file_rollup" then
    return {
      system = "You are a code-change summarizer. Given the following chunk summaries"
        .. " for a single file, produce a single concise paragraph (<=4 sentences)"
        .. " describing the net effect of the changes.",
      user = string.format(
        "File: %s\n\nChunk summaries:\n%s", opts.file_path or "(unknown)", payload),
    }
  elseif kind == "small_batch" then
    return {
      system = "You are a code-change summarizer. Given the following diffs for multiple"
        .. " small files, produce one concise bullet per file"
        .. " (format: '- <path>: <change summary>') describing the net change."
        .. " Do not merge bullets across files.",
      user = payload,
    }
  else
    error(string.format("build_summary_prompt: unknown kind '%s'", tostring(kind)))
  end
end

return M
