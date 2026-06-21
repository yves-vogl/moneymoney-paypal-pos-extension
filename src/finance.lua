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
