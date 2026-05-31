-- Default (passthrough) input preparator
-- Returns the raw diff string unchanged.
local M = {}

-- Prepare final payload by returning the raw diff as-is.
-- @param diff_data      table   { diff = string, files = table }
-- @param provider       table   Provider instance (unused)
-- @param provider_config table  Provider config (unused)
-- @param callback       function(error, final_payload)
function M.prepare(diff_data, provider, provider_config, callback)
  callback(nil, diff_data.diff)
end

return M
