-- Input dispatcher: routes diff preparation to default or rich pipeline.
local M = {}

local function supports_summarize(provider)
  local base = require("aicommits.providers.base")
  return type(provider) == "table"
    and type(provider.summarize) == "function"
    and provider.summarize ~= base.Provider.summarize
end

-- Prepare the final commit-message payload.
-- Reads large_diff config to decide which pipeline to use.
-- @param diff_data      table   { diff = string, files = table }
-- @param provider       table   Provider instance
-- @param provider_config table  Provider config
-- @param callback       function(error, final_payload)
function M.prepare(diff_data, provider, provider_config, callback)
  local config = require("aicommits.config")
  local MODES = config.LARGE_DIFF_MODES
  local ld = config.get("large_diff")
  local mode = ld and ld.mode or MODES.OFF

  local use_rich = false

  if mode == MODES.ALWAYS then
    use_rich = true
  elseif mode == MODES.AUTO then
    local threshold = ld.threshold_chars or 12000
    use_rich = #(diff_data.diff or "") > threshold
  end

  if use_rich and not supports_summarize(provider) then
    use_rich = false
    vim.notify(
      "aicommits: active provider does not support diff summarization; " .. "using standard input for this commit.",
      vim.log.levels.WARN
    )
  end

  if use_rich then
    require("aicommits.input.rich").prepare(diff_data, provider, provider_config, callback)
  else
    require("aicommits.input.default").prepare(diff_data, provider, provider_config, callback)
  end
end

return M
