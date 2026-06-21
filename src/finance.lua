-- src/finance.lua
-- Ownership: ACCT-03 / FEE-01..03 / PAYOUT-01..03 / D-46..D-49 / D-52.
-- Provides: M_finance.parse_transaction(raw) [Plan 04-02 Task 3]
--           M_finance.fetch / fetch_all / fetch_account_state [Plan 04-03]
-- The M_finance table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02). Cross-module helper access goes
-- through public wrappers exposed on M_mapping (D-02 / RESEARCH §Pitfall 10):
--   M_mapping.parse_iso8601_utc (the canonical Phase-3 ISO-8601 parser).

-- Phase 4 type filter: PAYMENT, PAYMENT_FEE, PAYOUT only. Every other
-- originatorTransactionType (ADJUSTMENT, CASHBACK, FROZEN_FUNDS, ADVANCE*,
-- INVOICE_*, PAYMENT_PAYOUT, FAILED_PAYOUT) is silently filtered out by
-- parse_transaction returning nil. RESEARCH §1.3 / T-04-W1-01.
local PHASE4_FILTER_TYPES = {
  PAYMENT     = true,
  PAYMENT_FEE = true,
  PAYOUT      = true,
}

-- M_finance.parse_transaction(raw) -> table|nil
-- Normalise a single Finance API record into a typed Lua table:
--   { kind, amount, timestamp_iso, timestamp_posix, originatingTransactionUuid }
-- Returns nil for:
--   * non-table input
--   * unknown / out-of-filter originatorTransactionType
--   * missing originatingTransactionUuid / timestamp / amount
--   * timestamp string that fails Phase-3's _parse_iso8601_utc parser
function M_finance.parse_transaction(raw)
  if type(raw) ~= "table" then return nil end

  local kind = raw.originatorTransactionType
  if type(kind) ~= "string" or not PHASE4_FILTER_TYPES[kind] then
    return nil
  end

  local uuid = raw.originatingTransactionUuid
  if type(uuid) ~= "string" or #uuid == 0 then return nil end

  local ts = raw.timestamp
  if type(ts) ~= "string" or #ts == 0 then return nil end

  local amount = raw.amount
  if type(amount) ~= "number" then return nil end

  local ts_posix = M_mapping.parse_iso8601_utc(ts)
  if not ts_posix then
    M_log.info("M_finance.parse_transaction: skipping record with malformed timestamp")
    return nil
  end

  return {
    kind                       = kind,
    amount                     = amount,
    timestamp_iso              = ts,
    timestamp_posix            = ts_posix,
    originatingTransactionUuid = uuid,
  }
end

-- ---------------------------------------------------------------------------
-- Plan 04-03: HTTP-bound functions (fetch / fetch_all / fetch_account_state).
-- All HTTP egress routes through M_http.get_json (D-42) — NO direct Connection()
-- use. All error handling routes through M_errors.from_http_status (D-43).
-- All Bearer assertions follow M_purchases.fetch belt-and-suspenders pattern
-- (Phase-3 D-41 / ME-01). Bearer is NEVER logged (SEC-03 inherited).
-- ---------------------------------------------------------------------------

-- _iso8601_utc_no_z(posix) -> string
-- RESEARCH §1.3 + §Pitfall 3: Finance API timestamps are YYYY-MM-DDThh:mm:ss
-- with NO `Z` suffix and NO millis. Distinct from Phase-3 purchase fetch's
-- YYYY-MM-DDTHH:MM:SSZ form (see src/purchases.lua _iso8601_utc).
local function _iso8601_utc_no_z(posix)
  if type(posix) ~= "number" then
    return os.date("!%Y-%m-%dT%H:%M:%S", 0)
  end
  return os.date("!%Y-%m-%dT%H:%M:%S", posix)
end

-- _url_encode_query(t) -> string
-- Minimal sorted key=value encoder for query string assembly. Unlike Phase-3's
-- M_purchases._url_encode_query, this one does NOT percent-encode — Finance API
-- accepts literal `:` in start/end ISO-8601 values. Cannot emit repeated keys
-- (Lua table keys deduplicate); the includeTransactionType triplet is appended
-- as a literal suffix below (PATTERNS.md note + RESEARCH §Pitfall 7).
local function _url_encode_query(t)
  local parts = {}
  for k, v in pairs(t) do
    parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
  end
  table.sort(parts)
  return table.concat(parts, "&")
end

-- RESEARCH §1.3 / §Pitfall 7: includeTransactionType repeats three times for
-- the Phase-4 filter (PAYMENT, PAYMENT_FEE, PAYOUT). Appended as a literal
-- suffix because Lua table keys deduplicate — _url_encode_query cannot emit
-- three identical query-string keys from a single Lua table.
local _INCLUDE_TYPES_SUFFIX =
  "&includeTransactionType=PAYMENT"
  .. "&includeTransactionType=PAYMENT_FEE"
  .. "&includeTransactionType=PAYOUT"

-- M_finance.fetch(clamped_since, bearer, offset, end_posix)
--   clamped_since : number     -- POSIX seconds (already clamped by RefreshAccount per D-33)
--   bearer        : string     -- Bearer token from M_auth.cached_token (D-41 / D-42)
--   offset        : integer?   -- page offset; defaults to 0
--   end_posix     : integer?   -- explicit end anchor (POSIX seconds); defaults
--                                 to os.time()+60 if omitted (legacy behaviour,
--                                 used only by direct callers — fetch_all
--                                 always passes a fixed end_posix per WR-01).
--   -> (parsed_table|nil, status:integer|nil, raw_body:string)
--
-- GETs https://finance.izettle.com/v2/accounts/liquid/transactions with
-- start + end (both REQUIRED per RESEARCH §1.3 / §Pitfall 2), limit=1000,
-- offset, and the three appended includeTransactionType= suffix parameters
-- (PAYMENT, PAYMENT_FEE, PAYOUT). Returns the 3-tuple from M_http.get_json
-- verbatim so the caller can route errors via M_errors.from_http_status.
function M_finance.fetch(clamped_since, bearer, offset, end_posix)
  -- ME-01 belt-and-suspenders: RefreshAccount already guards nil bearer (D-41),
  -- but an explicit assertion here surfaces any future regression loudly rather
  -- than sending "Bearer nil" as the Authorization header value.
  assert(type(bearer) == "string" and #bearer > 0,
    "M_finance.fetch: bearer must be a non-empty string")
  offset = offset or 0
  end_posix = end_posix or (os.time() + 60)  -- legacy default + WR-01 anchor
  local q = {
    ["end"] = _iso8601_utc_no_z(end_posix),
    limit   = "1000",
    offset  = tostring(offset),
    start   = _iso8601_utc_no_z(clamped_since),
  }
  local url = "https://finance.izettle.com/v2/accounts/liquid/transactions?"
              .. _url_encode_query(q)
              .. _INCLUDE_TYPES_SUFFIX
  local headers = { Authorization = "Bearer " .. tostring(bearer) }
  return M_http.get_json(url, headers)
end

-- M_finance.fetch_all(clamped_since, bearer)
--   -> (records:table|nil, err:string|nil)
--
-- Drives the full offset-pagination loop via M_pagination.offset_iterate
-- (Plan 04-02 sibling iterator). fetch_page_fn closes over clamped_since +
-- bearer + end_posix and forwards params.offset to each M_finance.fetch call.
-- Returns (records, nil) on full success or (nil, err) on any sub-page error.
--
-- WR-01 (REVIEW): end_posix is computed ONCE before the iterator starts and
-- pinned for every page in the loop. The previous implementation recomputed
-- os.time()+60 in each M_finance.fetch call — across a multi-page pagination
-- the end-anchor drifted forward by however long the prior page took,
-- breaking offset-pagination's "stable dataset across pages" assumption and
-- causing records that landed in the result window during the loop to be
-- duplicated (at offset N and offset N-1) or missed (skipped past the limit
-- window). Pinning end_posix matches Zettle's official sample code.
function M_finance.fetch_all(clamped_since, bearer)
  assert(type(bearer) == "string" and #bearer > 0,
    "M_finance.fetch_all: bearer must be a non-empty string")
  local end_posix = os.time() + 60  -- pin once for the whole pagination loop
  local fetch_page_fn = function(params)
    return M_finance.fetch(clamped_since, bearer, params.offset, end_posix)
  end
  return M_pagination.offset_iterate(fetch_page_fn, { offset = 0, limit = 1000 })
end

-- M_finance.fetch_account_state(bearer)
--   -> ({balance, pendingBalance}|nil, err:string|nil)
--
-- ACCT-03 / D-52 / RESEARCH §1.4: issues TWO sequential GETs:
--   1) GET /v2/accounts/liquid/balance       -> settled balance
--   2) GET /v2/accounts/preliminary/balance  -> in-flight balance
-- On ANY HTTP error returns (nil, err) IMMEDIATELY (ERR-06 fail-whole-refresh).
-- The preliminary GET is NOT issued if the liquid GET errors.
-- Currency-guard per D-37 / R-4: if a side's currencyId is not "EUR", that
-- side's balance returns nil and an M_log.info line is emitted; the other
-- side still populates when valid.
function M_finance.fetch_account_state(bearer)
  assert(type(bearer) == "string" and #bearer > 0,
    "M_finance.fetch_account_state: bearer must be a non-empty string")
  local headers = { Authorization = "Bearer " .. tostring(bearer) }

  -- 1) Liquid (settled) balance — ACCT-03 `balance`
  local liquid, l_status, l_raw = M_http.get_json(
    "https://finance.izettle.com/v2/accounts/liquid/balance", headers)
  local l_err = M_errors.from_http_status(l_status, l_raw)
  if l_err then return nil, l_err end
  if type(liquid) ~= "table" or type(liquid.data) ~= "table" then
    return nil, M_i18n.t("error.network", "bad_page")
  end

  local balance_eur = nil
  if type(liquid.data.currencyId) == "string"
      and liquid.data.currencyId:upper() == "EUR"
      and type(liquid.data.totalBalance) == "number" then
    balance_eur = liquid.data.totalBalance / 100
  else
    -- S-02 (SEC MEDIUM): cap attacker-controllable currencyId at 8 chars
    -- before log concat (same pattern as Phase-3 S-01 mapping fix at
    -- src/mapping.lua:371). ISO 4217 codes are 3 chars; 8 provides margin.
    local cur = tostring(liquid.data.currencyId or "<nil>"):sub(1, 8)
    M_log.info("M_finance.fetch_account_state: liquid balance non-EUR, skipping (currencyId="
      .. cur .. ")")
  end

  -- 2) Preliminary (in-flight) balance — ACCT-03 `pendingBalance`
  local prelim, p_status, p_raw = M_http.get_json(
    "https://finance.izettle.com/v2/accounts/preliminary/balance", headers)
  local p_err = M_errors.from_http_status(p_status, p_raw)
  if p_err then return nil, p_err end
  if type(prelim) ~= "table" or type(prelim.data) ~= "table" then
    return nil, M_i18n.t("error.network", "bad_page")
  end

  local pending_eur = nil
  if type(prelim.data.currencyId) == "string"
      and prelim.data.currencyId:upper() == "EUR"
      and type(prelim.data.totalBalance) == "number" then
    pending_eur = prelim.data.totalBalance / 100
  else
    -- S-02 (SEC MEDIUM): same currency-cap pattern as the liquid site above.
    local cur = tostring(prelim.data.currencyId or "<nil>"):sub(1, 8)
    M_log.info("M_finance.fetch_account_state: preliminary balance non-EUR, skipping (currencyId="
      .. cur .. ")")
  end

  return { balance = balance_eur, pendingBalance = pending_eur }, nil
end
