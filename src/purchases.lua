-- src/purchases.lua
-- Ownership: SALE-06 / D-33 / D-42 / D-43.
-- Provides: M_purchases.fetch(clamped_since, bearer, cursor) -- single-page GET
--           M_purchases.fetch_all(clamped_since, bearer) -- drives M_pagination.iterate
--           when available; falls back to inline cursor loop during the
--           Phase-3 Wave-3 parallel-plan window before Plan 03-04 lands.
-- The M_purchases table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02: amalgamator resolves cross-module
-- refs at build time via the shared module-table globals).

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

-- _inline_iterate(fetch_page_fn, initial_params) -> (all_purchases|nil, error|nil)
-- Minimal inline cursor loop used when M_pagination.iterate is not yet available
-- (parallel-plan window before Plan 03-04 fills src/pagination.lua).
-- Mirrors the RESEARCH §2a repeat-until pattern and RESEARCH §3 anti-pattern 1:
-- terminates on empty purchases[] OR absent/empty lastPurchaseHash (both checked).
-- MAX_PAGES=50 guards against infinite loops on malformed responses (belt-and-suspenders).
-- Superseded by M_pagination.iterate once Plan 03-04 lands.
local function _inline_iterate(fetch_page_fn, initial_params)
  local all_purchases = {}
  local params = {}
  for k, v in pairs(initial_params) do params[k] = v end
  local MAX_PAGES = 50
  local page_count = 0

  repeat
    page_count = page_count + 1
    if page_count > MAX_PAGES then
      break  -- MAX_PAGES guard: prevent infinite loops on malformed responses
    end

    local page, status, raw = fetch_page_fn(params)
    local err = M_errors.from_http_status(status, raw)
    if err then return nil, err end
    if not page or type(page.purchases) ~= "table" then
      return nil, M_i18n.t("error.network", "bad_page")
    end

    for _, p in ipairs(page.purchases) do
      all_purchases[#all_purchases + 1] = p
    end

    -- Termination: check BOTH empty array AND absent cursor (RESEARCH §3, anti-pattern 1)
    local has_more = #page.purchases > 0
      and type(page.lastPurchaseHash) == "string"
      and page.lastPurchaseHash ~= ""
    if has_more then
      params.lastPurchaseHash = page.lastPurchaseHash
    else
      params.lastPurchaseHash = nil
    end

  until not (type(params.lastPurchaseHash) == "string" and params.lastPurchaseHash ~= "")

  return all_purchases, nil
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
function M_purchases.fetch(clamped_since, bearer, cursor)
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
-- Drives the full cursor loop over the Purchase API.
-- Delegates to M_pagination.iterate (Plan 03-04) when available, otherwise
-- falls back to the inline _inline_iterate helper above.
-- fetch_page_fn closure captures clamped_since and bearer and calls
-- M_purchases.fetch on each invocation; M_pagination.iterate (or _inline_iterate)
-- manages params.lastPurchaseHash between page calls.
function M_purchases.fetch_all(clamped_since, bearer)
  local fetch_page_fn = function(params)
    return M_purchases.fetch(clamped_since, bearer, params.lastPurchaseHash)
  end

  if type(M_pagination.iterate) == "function" then
    return M_pagination.iterate(fetch_page_fn, {})
  end

  -- Fallback: Plan 03-04 has not yet filled src/pagination.lua.
  -- _inline_iterate provides identical cursor-loop semantics so Wave-3
  -- purchases specs pass in the parallel-plan window. This path is
  -- superseded once Plan 03-04 merges and M_pagination.iterate is defined.
  return _inline_iterate(fetch_page_fn, {})
end
