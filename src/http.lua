-- src/http.lua
-- AUTH-02 / AUTH-05 / D-25 / Risk R-1 / Pitfall 1 ownership.
-- Provides: M_http.post_form, M_http.get_json, M_http.shutdown,
--           M_http._infer_status (plus private _get_connection, _form_encode,
--           _merge_headers).
-- The M_http table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02: amalgamator resolves cross-module
-- refs at build time via the shared module-table globals).

-- Module-local Connection, reused across requests (D-25).
-- Created lazily on first call; released by shutdown() in EndSession.
local _conn = nil

-- _get_connection() -> Connection
-- Returns the cached connection or creates one.
local function _get_connection()
  if _conn == nil then
    _conn = Connection()
    -- D-26 / SEC-02 reminder: the only hosts we ever pass to this connection
    -- are oauth.zettle.com / purchase.izettle.com / finance.izettle.com.
    -- No host strings are stored here; URLs arrive as function parameters.
  end
  return _conn
end

-- _form_encode(t) -> string
-- Pure-Lua x-www-form-urlencoded body builder.
-- Deterministic sorted-key ordering for reproducible SEC-03 assertions.
local function _form_encode(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = MM.urlencode(k) .. "=" .. MM.urlencode(t[k])
  end
  return table.concat(parts, "&")
end

-- _merge_headers(user_headers) -> table
-- Forces Accept: application/json unconditionally (Pitfall 1 / T-02-04-03).
-- Without this header MoneyMoney aborts the entire Lua chunk on any non-2xx
-- response, preventing D-24's error-routing logic from ever running.
-- NEVER concatenate the returned table into any log line (defense-in-depth;
-- T-02-04-02: Bearer values in Authorization headers must never reach logs).
local function _merge_headers(user_headers)
  local h = {}
  for k, v in pairs(user_headers or {}) do h[k] = v end
  h["Accept"] = "application/json"
  return h
end

-- M_http._infer_status(parsed) -> integer
--
-- Risk R-1: MoneyMoney's Connection():request returns five values
-- (content, charset, mimeType, filename, headers) and does NOT include a
-- separate HTTP status code. This function derives a status-equivalent integer
-- from the decoded response body so M_errors.from_http_status can route errors.
--
-- Contract (in priority order):
--   parsed.error == "invalid_grant"   | "invalid_request"    -> 400
--   parsed.error == "invalid_client"  | "unauthorized_client" -> 401
--   parsed.error non-nil (unknown)                           -> 400 (conservative; Pitfall 5)
--   otherwise                                                 -> 200
function M_http._infer_status(parsed)
  if parsed.error then
    if parsed.error == "invalid_grant" or parsed.error == "invalid_request" then
      return 400
    end
    if parsed.error == "invalid_client" or parsed.error == "unauthorized_client" then
      return 401
    end
    return 400  -- conservative: unknown error names treated as 400 (Pitfall 5)
  end
  return 200
end

-- M_http.post_form(url, body_table, headers)
--   -> (decoded_table|nil, status:integer|nil, raw_body:string)
--
-- Sends an x-www-form-urlencoded POST. Accept: application/json is always set
-- (see _merge_headers). Request and response bodies are passed through
-- M_log.redact before any DEBUG log (D-25 / T-02-04-01).
-- NO pcall around conn:request (Pitfall 3: pcall does NOT catch SSL errors).
-- pcall is ONLY used around JSON parse.
function M_http.post_form(url, body_table, headers)
  local conn = _get_connection()
  local body = _form_encode(body_table)
  local h = _merge_headers(headers)
  M_log.debug("POST " .. url .. " body=" .. M_log.redact(body))
  -- 5-tuple destructure per Risk R-1 / Connection() contract.
  -- charset, mime, filename, resp_headers are not used here but named to
  -- document the contract explicitly.
  local raw, charset, mime, filename, resp_headers = -- luacheck: ignore 211
    conn:request("POST", url, body, "application/x-www-form-urlencoded", h)
  raw = raw or ""
  M_log.debug("POST " .. url .. " response=" .. M_log.redact(raw))
  if #raw == 0 then
    -- Empty body: network-level anomaly (D-24). Return nil status so
    -- M_errors.from_http_status(nil, ...) routes to the network-error branch.
    return nil, nil, raw
  end
  local ok, parsed = pcall(function()
    return JSON(raw):dictionary()
  end)
  if not ok or type(parsed) ~= "table" then
    return nil, nil, raw
  end
  return parsed, M_http._infer_status(parsed), raw
end

-- M_http.get_json(url, headers)
--   -> (decoded_table|nil, status:integer|nil, raw_body:string)
--
-- Sends a GET request. Accept: application/json always set.
-- The DEBUG request log is JUST "GET " .. url -- headers are NEVER concatenated
-- into any log line (T-02-04-02: defense-in-depth against Bearer leakage).
function M_http.get_json(url, headers)
  local conn = _get_connection()
  local h = _merge_headers(headers)
  M_log.debug("GET " .. url)  -- headers intentionally absent from log (Bearer safety)
  local raw, charset, mime, filename, resp_headers = -- luacheck: ignore 211
    conn:request("GET", url, nil, nil, h)
  raw = raw or ""
  M_log.debug("GET " .. url .. " response=" .. M_log.redact(raw))
  if #raw == 0 then
    return nil, nil, raw
  end
  local ok, parsed = pcall(function()
    return JSON(raw):dictionary()
  end)
  if not ok or type(parsed) ~= "table" then
    return nil, nil, raw
  end
  return parsed, M_http._infer_status(parsed), raw
end

-- M_http.shutdown()
-- Closes the module-local Connection (D-25 EndSession contract).
-- Idempotent: safe to call with _conn == nil or if close is absent.
function M_http.shutdown()
  if _conn and _conn.close then _conn:close() end
  _conn = nil
end
