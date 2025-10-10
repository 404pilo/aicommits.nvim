-- OpenAI API client for commit message generation
local M = {}

local http = require("aicommits.http")

-- Get OpenAI API key from environment
-- Checks AICOMMITS_NVIM_OPENAI_API_KEY first, then OPENAI_API_KEY
-- @return string|nil The API key or nil if not found
function M.get_api_key()
  local key = vim.env.AICOMMITS_NVIM_OPENAI_API_KEY
  if key and key ~= "" then
    return key
  end

  key = vim.env.OPENAI_API_KEY
  if key and key ~= "" then
    return key
  end

  return nil
end

-- Generate system prompt for conventional commits
-- @param max_length number Maximum commit message length
-- @return string The system prompt
local function generate_system_prompt(max_length)
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
    "Generate a concise git commit message written in present tense for the following code diff with the given specifications below:",
    "Message language: en",
    string.format("Commit message must be a maximum of %d characters.", max_length),
    "Exclude anything unnecessary such as translation. Your entire response will be passed directly into git commit.",
    "Choose a type from the type-to-description JSON below that best describes the git diff:",
    vim.json.encode(commit_types),
    "The output response must be in format:",
    "<type>(<optional scope>): <commit message>",
  }

  return table.concat(parts, "\n")
end

-- Sanitize and deduplicate commit messages
-- @param messages table Array of raw commit messages
-- @return table Array of sanitized, unique messages
local function process_messages(messages)
  local seen = {}
  local result = {}

  for _, msg in ipairs(messages) do
    -- Sanitize: trim, remove newlines, remove trailing period
    local sanitized = msg:gsub("^%s+", ""):gsub("%s+$", "")
    sanitized = sanitized:gsub("[\n\r]", "")
    sanitized = sanitized:gsub("(%w)%.$", "%1")

    -- Deduplicate
    if not seen[sanitized] and sanitized ~= "" then
      seen[sanitized] = true
      table.insert(result, sanitized)
    end
  end

  return result
end

-- Generate commit message(s) using OpenAI API
-- @param diff string The git diff to generate message for
-- @param callback function(error, messages) Callback with error or array of messages
function M.generate_commit_message(diff, callback)
  local api_key = M.get_api_key()
  if not api_key then
    callback("OpenAI API key not found. Set AICOMMITS_NVIM_OPENAI_API_KEY or OPENAI_API_KEY environment variable.", nil)
    return
  end

  -- Get configuration
  local config = require("aicommits.config")
  local model = config.get("model") or "gpt-4.1-nano"
  local max_length = config.get("max_length") or 50
  local generate = config.get("generate") or 1

  -- Build request body
  local request_body = {
    model = model,
    messages = {
      {
        role = "system",
        content = generate_system_prompt(max_length),
      },
      {
        role = "user",
        content = diff,
      },
    },
    temperature = 0.7,
    top_p = 1,
    frequency_penalty = 0,
    presence_penalty = 0,
    max_tokens = 200,
    stream = false,
    n = generate,
  }

  -- Make API request
  http.post(
    "https://api.openai.com/v1/chat/completions",
    {
      Authorization = "Bearer " .. api_key,
    },
    vim.json.encode(request_body),
    function(err, response_body)
      if err then
        callback(err, nil)
        return
      end

      -- Parse JSON response
      local ok, response = pcall(vim.json.decode, response_body)
      if not ok then
        callback("Failed to parse OpenAI API response: " .. tostring(response), nil)
        return
      end

      -- Check for API errors
      if response.error then
        local error_msg = "OpenAI API Error: " .. (response.error.message or vim.inspect(response.error))
        callback(error_msg, nil)
        return
      end

      -- Extract messages from response
      if not response.choices or #response.choices == 0 then
        callback("No commit messages were generated. Try again.", nil)
        return
      end

      local messages = {}
      for _, choice in ipairs(response.choices) do
        if choice.message and choice.message.content then
          table.insert(messages, choice.message.content)
        end
      end

      -- Process and return messages
      local processed = process_messages(messages)
      if #processed == 0 then
        callback("No valid commit messages were generated. Try again.", nil)
        return
      end

      callback(nil, processed)
    end
  )
end

return M
