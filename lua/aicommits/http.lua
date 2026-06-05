-- HTTP client wrapper using curl
local M = {}

-- Sentinel appended AFTER the response body via curl --write-out so we can recover
-- the HTTP status and Retry-After without a header file. Chosen to be unlikely to
-- collide with a JSON body; we always split at the LAST occurrence to be safe.
local META_SENTINEL = "<<<AICOMMITS_META>>>"

-- Make an HTTP POST request using curl.
-- @param url      string The URL to request
-- @param headers  table  Key-value pairs of HTTP headers
-- @param body     string The JSON body to send
-- @param opts     table  { timeout_ms = number|nil }
-- @param callback function(error, result) where
--        result = { status = number, body = string, headers = { retry_after = string|nil } }
--        error is set ONLY on transport failure (curl non-zero exit). An HTTP 4xx/5xx
--        is a successful transport: error = nil, result.status = the non-2xx code.
function M.post(url, headers, body, opts, callback)
  opts = opts or {}

  local args = {
    "-s", -- silent
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
    -- Append status + Retry-After after the body so we can parse them off the tail.
    "-w",
    "\n" .. META_SENTINEL .. "%{http_code} %{header{retry-after}}",
  }

  if opts.timeout_ms then
    -- curl --max-time is whole-second granularity; round sub-second up to 1s.
    local seconds = math.max(1, math.floor(opts.timeout_ms / 1000))
    table.insert(args, "--max-time")
    table.insert(args, tostring(seconds))
  end

  for key, value in pairs(headers) do
    table.insert(args, "-H")
    table.insert(args, key .. ": " .. value)
  end

  table.insert(args, "-d")
  table.insert(args, body)
  table.insert(args, url)

  vim.system({ "curl", unpack(args) }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        callback("HTTP request failed: " .. (obj.stderr or "Unknown error"), nil)
        return
      end

      local raw = obj.stdout or ""

      -- Split at the LAST sentinel: the body may itself contain the sentinel string.
      local sentinel_start, sentinel_end
      local search_from = 1
      while true do
        local s, e = raw:find(META_SENTINEL, search_from, true)
        if not s then
          break
        end
        sentinel_start, sentinel_end = s, e
        search_from = e + 1
      end

      local status = 0
      local retry_after = nil
      local body_text = raw

      if sentinel_start then
        -- Body is everything before the "\n<sentinel>"; drop the single newline we added.
        local body_end = sentinel_start - 1
        if raw:sub(body_end, body_end) == "\n" then
          body_end = body_end - 1
        end
        body_text = raw:sub(1, body_end)

        local meta = raw:sub(sentinel_end + 1)
        local code_str, ra = meta:match("^(%d+)%s*(.-)%s*$")
        if code_str then
          status = tonumber(code_str) or 0
        end
        if ra and ra ~= "" then
          retry_after = ra
        end
      end

      callback(nil, { status = status, body = body_text, headers = { retry_after = retry_after } })
    end)
  end)
end

return M
