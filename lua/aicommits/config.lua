-- Configuration management for aicommits.nvim
local M = {}

-- Current configuration state
local config = {}

-- Default configuration schema
M.defaults = {
  -- OpenAI API Configuration
  model = "gpt-4.1-nano", -- OpenAI model to use
  max_length = 50, -- Maximum commit message length
  generate = 1, -- Number of commit message options to generate (1-5)

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

  -- Backward compatibility: convert boolean neogit to nested config
  if user_opts.integrations and type(user_opts.integrations.neogit) == "boolean" then
    local enabled = user_opts.integrations.neogit
    user_opts.integrations.neogit = {
      enabled = enabled,
      mappings = {
        enabled = enabled,
        key = "C",
      },
    }
  end

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

  -- Validate model
  if type(config.model) ~= "string" or config.model == "" then
    table.insert(errors, "model must be a non-empty string")
  end

  -- Validate max_length
  if type(config.max_length) ~= "number" or config.max_length <= 0 then
    table.insert(errors, "max_length must be a positive number")
  end

  -- Validate generate
  if type(config.generate) ~= "number" or config.generate < 1 or config.generate > 5 then
    table.insert(errors, "generate must be a number between 1 and 5")
  end

  return #errors == 0, errors
end

return M
