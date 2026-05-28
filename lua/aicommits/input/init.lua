-- Input dispatcher: routes diff preparation to default or rich pipeline.
local M = {}

-- Prepare the final commit-message payload.
-- Reads large_diff config to decide which pipeline to use.
-- @param diff_data      table   { diff = string, files = table }
-- @param provider       table   Provider instance
-- @param provider_config table  Provider config
-- @param callback       function(error, final_payload)
function M.prepare(diff_data, provider, provider_config, callback)
  local config = require("aicommits.config")
  local ld     = config.get("large_diff")
  local mode   = ld and ld.mode or "off"

  local use_rich = false

  if mode == "always" then
    use_rich = true
  elseif mode == "auto" then
    local threshold = ld.threshold_chars or 12000
    use_rich = #(diff_data.diff or "") > threshold
  end

  if use_rich then
    require("aicommits.input.rich").prepare(diff_data, provider, provider_config, callback)
  else
    require("aicommits.input.default").prepare(diff_data, provider, provider_config, callback)
  end
end

return M
