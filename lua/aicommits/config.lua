-- Configuration management for aicommits.nvim
local M = {}

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
      model = "gpt-4.1-nano", -- OpenAI model to use
      max_length = 50, -- Maximum commit message length
      generate = 1, -- Number of commit message options to generate (1-5)
      -- Advanced OpenAI options
      temperature = 0.7, -- Sampling temperature (0-2)
      top_p = 1, -- Nucleus sampling parameter
      frequency_penalty = 0, -- Frequency penalty (-2 to 2)
      presence_penalty = 0, -- Presence penalty (-2 to 2)
      max_tokens = 200, -- Maximum tokens in response
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
    -- Future providers can be added here:
    -- anthropic = {
    --   enabled = false,
    --   api_key = nil,
    --   model = "claude-3-5-sonnet-20241022",
    --   max_tokens = 200,
    -- },
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
}

-- Setup configuration by merging user options with defaults
function M.setup(user_opts)
  user_opts = user_opts or {}

  config = vim.tbl_deep_extend("force", M.defaults, user_opts)
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

  return #errors == 0, errors
end

return M
