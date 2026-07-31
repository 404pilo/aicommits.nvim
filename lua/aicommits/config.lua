-- Configuration management for aicommits.nvim
local M = {}

-- Large-diff mode constants
M.LARGE_DIFF_MODES = {
  OFF = "off",
  AUTO = "auto",
  ALWAYS = "always",
}

-- Current configuration state
local config = {}

-- Default configuration schema
M.defaults = {
  -- Provider Configuration
  active_provider = "openai", -- Which provider to use for generating commit messages

  providers = {
    -- OpenAI Configuration
    openai = {
      enabled = true, -- Enable/disable this provider
      api_key = nil, -- API key (nil = use environment variables)
      endpoint = nil, -- API endpoint (nil = use default: https://api.openai.com/v1/chat/completions)
      model = "gpt-5.6-luna", -- OpenAI model to use
      max_length = 50, -- Maximum commit message length
      generate = 1, -- Number of commit message options to generate (1-5)
      -- Only used for gpt-5-family reasoning models (e.g. gpt-5.6-luna). Public Chat
      -- Completions API values: none|low|medium|high|xhigh (nil = let the API pick its
      -- own default). Do not reuse codex's minimal/max here; the public API rejects them.
      reasoning_effort = nil,
      verbosity = nil, -- Only used for gpt-5-family reasoning models: low|medium|high
      -- Advanced OpenAI options
      temperature = 0.7, -- Sampling temperature (0-2)
      top_p = 1, -- Nucleus sampling parameter
      frequency_penalty = 0, -- Frequency penalty (-2 to 2)
      presence_penalty = 0, -- Presence penalty (-2 to 2)
      max_tokens = 200, -- Maximum tokens in response
      request = { timeout_ms = 120000 }, -- Reasoning-model latency headroom
    },
    -- Google Vertex AI Configuration
    -- Requires gcloud CLI: https://cloud.google.com/sdk/install
    -- Authentication: gcloud auth application-default login
    -- Or set GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    vertex = {
      enabled = false, -- Enable/disable this provider (disabled by default)
      model = "gemini-2.0-flash-lite", -- Vertex AI model to use
      project = nil, -- GCP project ID (required)
      location = "us-central1", -- GCP location/region
      max_length = 50, -- Maximum commit message length
      generate = 3, -- Number of commit message options to generate
      temperature = 0.7, -- Sampling temperature (0-2)
      max_tokens = 200, -- Maximum tokens in response
    },
    -- Google Gemini API (AI Studio) Configuration
    -- Get API key from: https://aistudio.google.com
    -- Simpler alternative to Vertex AI - no GCP project required
    -- Uses generativelanguage.googleapis.com endpoint
    ["gemini-api"] = {
      enabled = false, -- Enable/disable this provider (disabled by default)
      api_key = nil, -- API key (nil = use environment variables AICOMMITS_NVIM_GEMINI_API_KEY or GEMINI_API_KEY)
      model = "gemini-2.5-flash", -- Gemini model to use (gemini-2.5-flash, gemini-2.0-flash-exp, gemini-1.5-flash)
      max_length = 50, -- Maximum commit message length
      generate = 1, -- Number of commit message options to generate (1-8)
      temperature = 0.7, -- Sampling temperature (0-2)
      max_tokens = 200, -- Maximum tokens in response
      thinking_budget = 0, -- Thinking budget (0 = disabled, -1 = dynamic, 1-24576 = manual). Set to 0 by default for lower cost/latency
    },
    -- Anthropic Claude Configuration
    -- Get API key from: https://console.anthropic.com
    anthropic = {
      enabled = false, -- Enable/disable this provider (disabled by default)
      api_key = nil, -- API key (nil = use environment variables AICOMMITS_NVIM_ANTHROPIC_API_KEY or ANTHROPIC_API_KEY)
      model = "claude-haiku-4-5", -- Claude model to use
      max_length = 50, -- Maximum commit message length
      temperature = 0.7, -- Sampling temperature (0-1)
      max_tokens = 200, -- Maximum tokens in response
    },
    -- Codex (ChatGPT OAuth) Configuration
    -- Reads the local Codex CLI session at $CODEX_HOME/auth.json (read-only).
    -- Requires the codex CLI and an active `codex login` session.
    codex = {
      enabled = false, -- Enable/disable this provider (disabled by default)
      endpoint = nil, -- API endpoint (nil = ChatGPT Codex backend default)
      model = "gpt-5.6-terra", -- Known-good models: gpt-5.6-terra, gpt-5.6-luna
      reasoning_effort = "none", -- none|minimal|low|medium|high|xhigh|max
      verbosity = "low", -- low|medium|high - the only supported length control
      max_length = 50, -- Maximum commit message length
      generate = 1, -- Must be 1; the backend gives no fan-out
      request = { timeout_ms = 120000 }, -- Reasoning-model latency headroom
    },
  },

  -- UI Configuration
  ui = {
    use_custom_picker = true, -- Use custom floating window picker (true) or vim.ui.select (false)
    picker = {
      width = 0.4, -- Width as percentage of screen (0.0 to 1.0)
      height = 0.3, -- Height as percentage of screen (0.0 to 1.0)
      border = "rounded", -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
    },
  },

  -- Husky Integration
  husky = {
    enabled = true, -- Auto-detect commitlint config from .husky projects (set to false to disable)
  },

  -- Debug Mode
  debug = false,

  -- Integration Options
  integrations = {
    neogit = {
      enabled = true, -- Auto-refresh after commit
      mappings = {
        enabled = true, -- Auto-add keymap in status view
        key = "C", -- Customize the key (default: "C")
      },
    },
  },

  -- Large Diff Summarization
  large_diff = {
    mode = "auto",
    threshold_chars = 60000,
    chunk_chars = 6000,
    max_chunks_per_file = 6,
    small_file_chars = 800,
    max_small_files_inline = 10,
    small_file_batch_chars = 4000,
    summary_model = nil,
    summary_max_tokens = 220,
    summary_temperature = 0.2,
    concurrency = 4,
  },

  -- Request policy (timeout, retry, backoff, global concurrency)
  request = {
    timeout_ms = 30000,
    max_retries = 2, -- total attempts = 1 + max_retries
    backoff_base_ms = 500,
    backoff_max_ms = 8000,
    backoff_jitter = true,
    -- 529 is Anthropic's "overloaded_error"; it is transient and safe to retry.
    retry_on_status = { 408, 429, 500, 502, 503, 504, 529 },
    respect_retry_after = true,
    max_concurrency = 4,
  },
}

-- Setup configuration by merging user options with defaults
function M.setup(user_opts)
  user_opts = user_opts or {}

  -- Deep-copy defaults first so post-merge mutations (e.g. the concurrency-alias
  -- fold below) never corrupt the shared M.defaults table — tbl_deep_extend aliases
  -- nested default tables that the user did not override.
  config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts)

  -- Back-compat: large_diff.concurrency is the legacy knob for what is now
  -- request.max_concurrency. Detect EXPLICIT user intent from user_opts (not the
  -- merged config, whose defaults are indistinguishable from user values).
  local user_ld = user_opts.large_diff or {}
  local user_req = user_opts.request or {}
  local legacy_set = user_ld.concurrency ~= nil
  local canonical_set = user_req.max_concurrency ~= nil

  if legacy_set then
    if not canonical_set then
      -- Fold the legacy value into the canonical knob.
      config.request.max_concurrency = user_ld.concurrency
    end
    -- Soft deprecation notice, emitted once per setup() call that passes the
    -- legacy key (fires whether or not we folded).
    vim.notify(
      "aicommits: large_diff.concurrency is deprecated; use request.max_concurrency instead.",
      vim.log.levels.WARN
    )
  end

  return config
end

-- Get configuration value by key path (dot notation)
-- Example: get('terminal.float_opts.width')
function M.get(key)
  if not key then
    return config
  end
  return vim.tbl_get(config, unpack(vim.split(key, ".", { plain = true })))
end

-- Set configuration value by key path
function M.set(key, value)
  local keys = vim.split(key, ".", { plain = true })
  local current = config

  for i = 1, #keys - 1 do
    if not current[keys[i]] then
      current[keys[i]] = {}
    end
    current = current[keys[i]]
  end

  current[keys[#keys]] = value
end

-- Validate current configuration
function M.validate()
  local errors = {}

  -- Validate active_provider
  if not config.active_provider or config.active_provider == "" then
    table.insert(errors, "active_provider must be set")
  end

  -- Validate provider exists in configuration
  if config.active_provider and not config.providers then
    table.insert(errors, "providers table is missing")
  end

  if config.active_provider and config.providers then
    local provider_config = config.providers[config.active_provider]
    if not provider_config then
      table.insert(errors, string.format("No configuration found for provider '%s'", config.active_provider))
    elseif provider_config.enabled == false then
      table.insert(errors, string.format("Provider '%s' is disabled", config.active_provider))
    end
  end

  if config.large_diff then
    local valid_modes = {
      [M.LARGE_DIFF_MODES.OFF] = true,
      [M.LARGE_DIFF_MODES.AUTO] = true,
      [M.LARGE_DIFF_MODES.ALWAYS] = true,
    }
    local mode = config.large_diff.mode
    if mode and not valid_modes[mode] then
      table.insert(errors, string.format("large_diff.mode must be 'off', 'auto', or 'always'; got '%s'", mode))
    end
    local concurrency = config.large_diff.concurrency
    if concurrency ~= nil and (type(concurrency) ~= "number" or concurrency < 1 or concurrency % 1 ~= 0) then
      table.insert(errors, string.format("large_diff.concurrency must be a positive integer; got '%s'", concurrency))
    end
    local max_chunks_per_file = config.large_diff.max_chunks_per_file
    if
      max_chunks_per_file ~= nil
      and (type(max_chunks_per_file) ~= "number" or max_chunks_per_file < 1 or max_chunks_per_file % 1 ~= 0)
    then
      table.insert(
        errors,
        string.format("large_diff.max_chunks_per_file must be a positive integer; got '%s'", max_chunks_per_file)
      )
    end
  end

  if config.request then
    local r = config.request

    local function check_positive(name, val)
      if val ~= nil and (type(val) ~= "number" or val <= 0) then
        table.insert(errors, string.format("request.%s must be a positive number; got '%s'", name, tostring(val)))
      end
    end

    check_positive("timeout_ms", r.timeout_ms)
    check_positive("backoff_base_ms", r.backoff_base_ms)
    check_positive("backoff_max_ms", r.backoff_max_ms)
    check_positive("max_concurrency", r.max_concurrency)

    if r.max_retries ~= nil and (type(r.max_retries) ~= "number" or r.max_retries < 0 or r.max_retries % 1 ~= 0) then
      table.insert(
        errors,
        string.format("request.max_retries must be an integer >= 0; got '%s'", tostring(r.max_retries))
      )
    end

    if r.respect_retry_after ~= nil and type(r.respect_retry_after) ~= "boolean" then
      table.insert(errors, "request.respect_retry_after must be a boolean")
    end
    if r.backoff_jitter ~= nil and type(r.backoff_jitter) ~= "boolean" then
      table.insert(errors, "request.backoff_jitter must be a boolean")
    end

    if r.retry_on_status ~= nil then
      if type(r.retry_on_status) ~= "table" then
        table.insert(errors, "request.retry_on_status must be an array of integers")
      else
        for _, code in ipairs(r.retry_on_status) do
          if type(code) ~= "number" or code % 1 ~= 0 then
            table.insert(errors, "request.retry_on_status must be an array of integers")
            break
          end
        end
      end
    end
  end

  return #errors == 0, errors
end

return M
