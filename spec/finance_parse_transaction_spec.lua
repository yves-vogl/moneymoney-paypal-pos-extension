-- spec/finance_parse_transaction_spec.lua
-- Covers: M_finance.parse_transaction pure-logic kind dispatch (Phase 4 Plan 04-02,
-- D-46..D-49 / D-52 / ACCT-03 / FEE-01..03 / PAYOUT-01..03 / RESEARCH §1.6).
--
-- RED in Task 1: src/finance.lua does not yet exist; M_finance.parse_transaction
-- is not defined. Tests assert is_function(M_finance.parse_transaction) and fail.
-- Task 3 (GREEN) lands the impl and these turn green.

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("finance_parse_transaction_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

local function load_records(name)
  local _, decoded = Fixtures.load("finance/" .. name)
  return decoded.data
end

-- luacheck: globals M_finance M_mapping

describe("M_finance.parse_transaction", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  it("parse_transaction returns table with kind=PAYMENT for valid PAYMENT record", function()
    assert.is_function(M_finance.parse_transaction,
      "M_finance.parse_transaction must be a function (Task 3 GREEN)")
    local records = load_records("finance_single_page")
    local payment_raw = records[1]
    assert.equals("PAYMENT", payment_raw.originatorTransactionType,
      "fixture sanity: first record must be a PAYMENT")
    local parsed = M_finance.parse_transaction(payment_raw)
    assert.is_table(parsed, "parse_transaction must return a table for valid PAYMENT")
    assert.equals("PAYMENT", parsed.kind, "kind must be PAYMENT")
    assert.equals(479300, parsed.amount, "amount must be passed through unchanged")
    assert.equals("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", parsed.originatingTransactionUuid,
      "originatingTransactionUuid must be preserved")
    assert.is_number(parsed.timestamp_posix, "timestamp_posix must be a number")
  end)

  it("parse_transaction returns table with kind=PAYMENT_FEE for valid PAYMENT_FEE record", function()
    assert.is_function(M_finance.parse_transaction)
    local records = load_records("finance_single_page")
    local fee_raw = records[2]
    assert.equals("PAYMENT_FEE", fee_raw.originatorTransactionType,
      "fixture sanity: second record must be a PAYMENT_FEE")
    local parsed = M_finance.parse_transaction(fee_raw)
    assert.is_table(parsed)
    assert.equals("PAYMENT_FEE", parsed.kind)
    assert.equals(-8867, parsed.amount)
  end)

  it("parse_transaction returns table with kind=PAYOUT for valid PAYOUT record", function()
    assert.is_function(M_finance.parse_transaction)
    local records = load_records("finance_single_page")
    local payout_raw = records[3]
    assert.equals("PAYOUT", payout_raw.originatorTransactionType,
      "fixture sanity: third record must be a PAYOUT")
    local parsed = M_finance.parse_transaction(payout_raw)
    assert.is_table(parsed)
    assert.equals("PAYOUT", parsed.kind)
    assert.equals(-470433, parsed.amount)
    assert.equals("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", parsed.originatingTransactionUuid)
  end)

  it("parse_transaction returns nil for malformed record (missing fields)", function()
    assert.is_function(M_finance.parse_transaction)
    -- Missing originatingTransactionUuid
    assert.is_nil(M_finance.parse_transaction({
      originatorTransactionType = "PAYMENT",
      timestamp = "2026-06-01T10:00:00.000+0000",
      amount = 100,
    }), "must return nil when originatingTransactionUuid missing")
    -- Missing timestamp
    assert.is_nil(M_finance.parse_transaction({
      originatorTransactionType = "PAYMENT",
      originatingTransactionUuid = "uuid-1",
      amount = 100,
    }), "must return nil when timestamp missing")
    -- Missing amount
    assert.is_nil(M_finance.parse_transaction({
      originatorTransactionType = "PAYMENT",
      originatingTransactionUuid = "uuid-1",
      timestamp = "2026-06-01T10:00:00.000+0000",
    }), "must return nil when amount missing")
    -- Non-table input
    assert.is_nil(M_finance.parse_transaction(nil), "must return nil for nil input")
    assert.is_nil(M_finance.parse_transaction("not-a-table"), "must return nil for string input")
  end)

  it("parse_transaction returns nil for out-of-filter type (ADJUSTMENT, CASHBACK, FROZEN_FUNDS)", function()
    assert.is_function(M_finance.parse_transaction)
    local function build_record(typ)
      return {
        originatorTransactionType = typ,
        originatingTransactionUuid = "uuid-x",
        timestamp = "2026-06-01T10:00:00.000+0000",
        amount = 100,
      }
    end
    assert.is_nil(M_finance.parse_transaction(build_record("ADJUSTMENT")),
      "ADJUSTMENT must be filtered (Phase 4 scope: PAYMENT/PAYMENT_FEE/PAYOUT)")
    assert.is_nil(M_finance.parse_transaction(build_record("CASHBACK")),
      "CASHBACK must be filtered")
    assert.is_nil(M_finance.parse_transaction(build_record("FROZEN_FUNDS")),
      "FROZEN_FUNDS must be filtered")
    assert.is_nil(M_finance.parse_transaction(build_record("INVOICE_PAYMENT")),
      "INVOICE_PAYMENT must be filtered")
    assert.is_nil(M_finance.parse_transaction(build_record("PAYMENT_PAYOUT")),
      "PAYMENT_PAYOUT must be filtered")
  end)

  it("parse_transaction sets timestamp_posix using the same parser as Phase-3 mapping", function()
    -- Reuses _parse_iso8601_utc via M_mapping.parse_iso8601_utc public wrapper.
    -- For the same ISO-8601 input both APIs must yield byte-identical POSIX seconds.
    assert.is_function(M_finance.parse_transaction)
    assert.is_function(M_mapping.parse_iso8601_utc,
      "M_mapping.parse_iso8601_utc must be exposed publicly so finance.lua can reuse the parser")
    local iso = "2026-06-01T10:30:00.000+0000"
    local raw = {
      originatorTransactionType = "PAYMENT",
      originatingTransactionUuid = "uuid-stamp",
      timestamp = iso,
      amount = 1,
    }
    local parsed = M_finance.parse_transaction(raw)
    assert.is_table(parsed)
    assert.equals(M_mapping.parse_iso8601_utc(iso), parsed.timestamp_posix,
      "timestamp_posix must equal M_mapping.parse_iso8601_utc(iso) (byte-identical reuse)")
    -- Also tolerate Z suffix per RESEARCH §1.6
    local iso_z = "2026-06-01T10:30:00Z"
    local parsed_z = M_finance.parse_transaction({
      originatorTransactionType = "PAYMENT",
      originatingTransactionUuid = "uuid-stamp-z",
      timestamp = iso_z,
      amount = 1,
    })
    assert.is_table(parsed_z, "Z-suffix timestamps must parse")
    assert.equals(M_mapping.parse_iso8601_utc(iso_z), parsed_z.timestamp_posix)
  end)

end)
