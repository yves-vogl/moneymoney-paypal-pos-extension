-- src/purchases.lua
-- Ownership: SALE-06 / D-33 / D-42 / D-43.
-- Provides: M_purchases.fetch(clamped_since, bearer, cursor) -- single-page GET
--           M_purchases.fetch_all(clamped_since, bearer) -- drives M_pagination.iterate
-- The M_purchases table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02: amalgamator resolves cross-module
-- refs at build time via the shared module-table globals).
--
-- Wave-3 parallel-plan note: _inline_iterate (dead fallback code) was removed in
-- Plan 03-06 once M_pagination.iterate was confirmed available. See Plan 03-04.

-- _iso8601_utc(posix) -> string
-- Formats a POSIX timestamp as UTC ISO-8601: "YYYY-MM-DDTHH:MM:SSZ".
-- Used to build the startDate query parameter per RESEARCH §1.
-- Guard: non-number input falls back to epoch (caller error would be visible upstream).
local function _iso8601_utc(posix)
  if type(posix) ~= "number" then
    return os.date("!%Y-%m-%dT%H:%M:%SZ", 0)
  end
  return os.date("!%Y-%m-%dT%H:%M:%SZ", posix)
end

-- _url_encode_query(params) -> string
-- Builds a sorted, URL-encoded query string from a params table.
-- Keys are sorted alphabetically for byte-stable, reproducible output
-- (D-31 spirit / T-03-W3b-02). nil and empty-string values are skipped.
-- Each key and value is percent-encoded via MM.urlencode (Phase-1 mock in tests;
-- production MoneyMoney built-in). Shape borrowed from src/http.lua L29-38 (_form_encode).
local function _url_encode_query(params)
  local keys = {}
  for k in pairs(params) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = params[k]
    if v ~= nil and tostring(v) ~= "" then
      parts[#parts + 1] = MM.urlencode(k) .. "=" .. MM.urlencode(tostring(v))
    end
  end
  return table.concat(parts, "&")
end

-- M_purchases.fetch(clamped_since, bearer, cursor)
--   clamped_since : number     -- POSIX timestamp (already clamped by RefreshAccount per D-33)
--   bearer        : string     -- Bearer token from M_auth.cached_token (D-41 / D-42)
--   cursor        : string|nil -- lastPurchaseHash from previous page; nil omits the param
--   -> (parsed_table|nil, status:integer|nil, raw_body:string)
--
-- GETs the Purchase API endpoint with alphabetically sorted URL-encoded query params
-- (descending, lastPurchaseHash when non-nil/non-empty, limit, startDate) and
-- Authorization: Bearer header. Single egress host per T-03-W3b-03 / D-26.
-- Delegates to M_http.get_json (D-42) -- no direct Connection() call, no pcall
-- (D-45 / RESEARCH §3 anti-pattern 6). The Authorization header is never logged:
-- M_http.get_json logs only the URL (T-02-04-02 / T-03-W3b-01). Returns the
-- 3-tuple from M_http.get_json verbatim so callers can route via
-- M_errors.from_http_status (D-43).
--
-- Plan 05-04 / ERR-04: the post-mint 401-direct-check (justified exception to
-- D-43 per ADR-0005 Invariant 4 + RESEARCH §Pattern-2) lives in
-- M_pagination.iterate — NOT here. Keeping fetch's return contract as the raw
-- (parsed, status, raw) 3-tuple lets the iterator route both ERR-04 (401 ->
-- error.token_revoked) and the generic D-43 path (every other status) without
-- a special sentinel return shape from this function.
function M_purchases.fetch(clamped_since, bearer, cursor)
  -- ME-01: belt-and-suspenders guard. RefreshAccount already guards nil bearer (D-41),
  -- but an explicit assertion here surfaces any future regression loudly rather than
  -- silently sending "Bearer nil" as the Authorization header value.
  assert(type(bearer) == "string" and #bearer > 0,
    "M_purchases.fetch: bearer must be a non-empty string")
  -- Build query param table; _url_encode_query sorts keys alphabetically.
  local q = {
    descending = "false",
    limit      = "200",
    startDate  = _iso8601_utc(clamped_since),
  }
  -- lastPurchaseHash is omitted on the first page (cursor nil) and on empty cursor
  -- strings. Present only for cursor-continuation pages (RESEARCH §2a).
  if type(cursor) == "string" and #cursor > 0 then
    q.lastPurchaseHash = cursor
  end

  local url = "https://purchase.izettle.com/purchases/v2?" .. _url_encode_query(q)
  -- Authorization header: concatenation only inside the header table; M_http.get_json
  -- structurally omits headers from log output (T-02-04-02 / D-45 no new call sites).
  local headers = { Authorization = "Bearer " .. tostring(bearer) }

  return M_http.get_json(url, headers)
end

-- M_purchases.fetch_all(clamped_since, bearer)
--   clamped_since : number -- POSIX timestamp (already clamped per D-33)
--   bearer        : string -- Bearer token from M_auth.cached_token (D-41)
--   -> (all_purchases:table|nil, error:string|nil)
--
-- Drives the full cursor loop over the Purchase API via M_pagination.iterate (Plan 03-04).
-- fetch_page_fn closure captures clamped_since and bearer and calls M_purchases.fetch
-- on each invocation; M_pagination.iterate manages params.lastPurchaseHash between pages.
function M_purchases.fetch_all(clamped_since, bearer)
  local fetch_page_fn = function(params)
    return M_purchases.fetch(clamped_since, bearer, params.lastPurchaseHash)
  end

  return M_pagination.iterate(fetch_page_fn, {})
end
