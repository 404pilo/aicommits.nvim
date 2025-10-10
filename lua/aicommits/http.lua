-- HTTP client wrapper using curl
local M = {}

-- Make an HTTP POST request using curl
-- @param url string The URL to request
-- @param headers table Key-value pairs of HTTP headers
-- @param body string The JSON body to send
-- @param callback function(error, response_body) Callback with error or response
function M.post(url, headers, body, callback)
  -- Build curl command arguments
  local args = {
    "-s", -- Silent mode
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
  }

  -- Add custom headers
  for key, value in pairs(headers) do
    table.insert(args, "-H")
    table.insert(args, key .. ": " .. value)
  end

  -- Add body
  table.insert(args, "-d")
  table.insert(args, body)

  -- Add URL
  table.insert(args, url)

  -- Execute curl command
  vim.system({ "curl", unpack(args) }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        callback("HTTP request failed: " .. (obj.stderr or "Unknown error"), nil)
        return
      end

      callback(nil, obj.stdout)
    end)
  end)
end

return M
