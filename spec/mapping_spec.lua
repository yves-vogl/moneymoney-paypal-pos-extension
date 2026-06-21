-- spec/mapping_spec.lua
-- Unit tests for M_mapping (Phase 3, Wave 2, Plan 03-03).
-- Covers: purchase_to_transaction / refund_to_transaction pure-logic unit tests
-- (SALE-01, SALE-02, SALE-04, SALE-08, I18N-01, D-32, D-34, D-35, D-37, D-38).
--
-- Wave 2 fills the 16 pending scaffolds from Wave 0 with passing it() tests.
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so each test
-- starts with a clean global environment (pattern from spec/http_spec.lua L37-44).
-- luacheck: ignore 631

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("mapping_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("M_mapping", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Helper: load first purchase from a fixture file
  -- -------------------------------------------------------------------------
  local function load_first(name)
    local _, decoded = Fixtures.load("purchases/" .. name)
    return decoded.purchases[1]
  end

  -- -------------------------------------------------------------------------
  -- Sanity tests (non-pending) — confirm artifact loads and modules are present
  -- -------------------------------------------------------------------------

  it("M_mapping module table is exposed", function()
    assert.is_table(M_mapping)
  end)

  it("Fixtures.load reads purchases/purchase_simple_sale", function()
    local raw, decoded = Fixtures.load("purchases/purchase_simple_sale")
    assert.is_string(raw, "fixture raw must be a string")
    assert.is_table(decoded, "fixture must decode to a table")
    assert.is_table(decoded.purchases, "fixture must have a purchases array")
    assert.equals(1, #decoded.purchases, "simple_sale fixture must have exactly 1 purchase")
  end)

  -- -------------------------------------------------------------------------
  -- SALE-01 / amount mapping
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction maps amount to EUR float (SALE-01)", function()
    local p = load_first("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.equals(p.amount / 100, txn.amount,
      "amount must equal purchase.amount / 100, got: " .. tostring(txn.amount))
    assert.equals(5.00, txn.amount,
      "purchase_simple_sale amount=500 => 5.00, got: " .. tostring(txn.amount))
  end)

  -- -------------------------------------------------------------------------
  -- SALE-02 / D-38 / transactionCode
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction sets transactionCode = zettle:sale:<purchaseUUID1> (SALE-02 / D-38)", function()
    local p = load_first("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.equals("zettle:sale:11111111-1111-1111-1111-111111111111", txn.transactionCode,
      "transactionCode must be 'zettle:sale:<uuid>', got: " .. tostring(txn.transactionCode))
  end)

  -- -------------------------------------------------------------------------
  -- D-31 / Phase 3 contract: booked=false, no valueDate
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction sets booked = false and omits valueDate (D-31 / Phase 3 contract)", function()
    local p = load_first("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_false(txn.booked,
      "Phase 3: booked must be false (D-31), got: " .. tostring(txn.booked))
    assert.is_nil(txn.valueDate,
      "Phase 3: valueDate must be absent (D-31), got: " .. tostring(txn.valueDate))
    -- Verify the key is truly absent from the table
    assert.is_nil(rawget(txn, "valueDate"),
      "valueDate key must not exist in transaction table (D-31)")
  end)

  -- -------------------------------------------------------------------------
  -- SALE-04 / D-36 / bookingDate with Berlin local time
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction sets bookingDate via Berlin local time (SALE-04 / D-36)", function()
    -- purchase_dst_boundary_summer: timestamp = "2026-06-19T23:55:00.000+0000" (UTC)
    -- Berlin CEST (+2h): 2026-06-20T01:55 local
    -- os.date("!*t", bookingDate) decomposes the Berlin-local POSIX as if it were UTC,
    -- so year=2026, month=6, day=20, hour=1, min=55
    local p = load_first("purchase_dst_boundary_summer")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_number(txn.bookingDate,
      "bookingDate must be a number, got: " .. tostring(txn.bookingDate))
    local t = os.date("!*t", txn.bookingDate)
    assert.equals(2026, t.year,  "summer DST: year must be 2026, got: " .. tostring(t.year))
    assert.equals(6,    t.month, "summer DST: month must be 6, got: " .. tostring(t.month))
    assert.equals(20,   t.day,   "summer DST: local day must be 20 (CEST +2h), got: " .. tostring(t.day))
    assert.equals(1,    t.hour,  "summer DST: local hour must be 01 (CEST +2h), got: " .. tostring(t.hour))
    assert.equals(55,   t.min,   "summer DST: local min must be 55, got: " .. tostring(t.min))
  end)

  -- -------------------------------------------------------------------------
  -- SALE-08 / D-35 / payment label
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction defaults name to Kartenzahlung when payments empty (SALE-08 / D-35)", function()
    -- purchase_simple_sale has payments = []
    local p = load_first("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.equals("Kartenzahlung", txn.name,
      "default name must be 'Kartenzahlung', got: " .. tostring(txn.name))
  end)

  -- payments[0].attributes.cardType path per RESEARCH §1 (corrects CONTEXT D-35 wording)
  it("purchase_to_transaction upgrades name to <Brand> \xe2\x80\xa2\xe2\x80\xa2\xe2\x80\xa2\xe2\x80\xa2 <last4> when payments[0].attributes.cardType present (SALE-08 / D-35 corrected)", function()
    -- purchase_with_card_metadata: payments[0].attributes.cardType="VISA", maskedPan="411111******1111"
    local p = load_first("purchase_with_card_metadata")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    -- Expected: "Visa •••• 1111" (U+2022 bullet, UTF-8: \xe2\x80\xa2)
    local bullet = "\xe2\x80\xa2"
    local expected = "Visa " .. bullet .. bullet .. bullet .. bullet .. " 1111"
    assert.equals(expected, txn.name,
      "card name must be 'Visa •••• 1111', got: " .. tostring(txn.name))
  end)

  -- -------------------------------------------------------------------------
  -- I18N-01 / D-34 / purpose format
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction purpose contains Brutto / MwSt / Trinkgeld / Netto / Beleg German lines (I18N-01 / D-34)", function()
    -- purchase_with_vat_and_tip: amount=1995, vatAmount=318, gratuityAmount=100, purchaseNumber=1002
    -- Brutto: 19,95 € | MwSt: 3,18 € | Trinkgeld: 1,00 € | Netto: 15,77 € | Beleg #1002
    local p = load_first("purchase_with_vat_and_tip")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_string(txn.purpose, "purpose must be a string")
    assert.is_truthy(txn.purpose:find("Brutto: 19,95 \xe2\x82\xac", 1, true),
      "purpose must contain 'Brutto: 19,95 €', got:\n" .. tostring(txn.purpose))
    assert.is_truthy(txn.purpose:find("MwSt: 3,18 \xe2\x82\xac", 1, true),
      "purpose must contain 'MwSt: 3,18 €', got:\n" .. tostring(txn.purpose))
    assert.is_truthy(txn.purpose:find("Trinkgeld: 1,00 \xe2\x82\xac", 1, true),
      "purpose must contain 'Trinkgeld: 1,00 €', got:\n" .. tostring(txn.purpose))
    -- Netto = 1995 - 318 - 100 = 1577 minor units = 15,77 €
    assert.is_truthy(txn.purpose:find("Netto: 15,77 \xe2\x82\xac", 1, true),
      "purpose must contain 'Netto: 15,77 €', got:\n" .. tostring(txn.purpose))
    assert.is_truthy(txn.purpose:find("Beleg #1002", 1, true),
      "purpose must contain 'Beleg #1002', got:\n" .. tostring(txn.purpose))
  end)

  it("purchase_to_transaction omits MwSt line when vatAmount = 0 (D-34)", function()
    -- purchase_simple_sale: vatAmount=0
    local p = load_first("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_string(txn.purpose, "purpose must be a string")
    assert.is_falsy(txn.purpose:find("MwSt", 1, true),
      "MwSt line must be absent when vatAmount=0, got:\n" .. tostring(txn.purpose))
    assert.is_truthy(txn.purpose:find("Brutto: 5,00 \xe2\x82\xac", 1, true),
      "purpose must contain 'Brutto: 5,00 €', got:\n" .. tostring(txn.purpose))
    assert.is_truthy(txn.purpose:find("Netto: 5,00 \xe2\x82\xac", 1, true),
      "purpose must contain 'Netto: 5,00 €' (no vat/tip to deduct), got:\n" .. tostring(txn.purpose))
  end)

  it("purchase_to_transaction omits Trinkgeld line when payments[].gratuityAmount sums to 0 (D-34)", function()
    -- Inline purchase with empty payments and vatAmount=0
    local p = {
      purchaseUUID1  = "test-uuid-0001",
      amount         = 1000,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-05-01T10:00:00Z",
      purchaseNumber = 999,
      payments       = {},
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_string(txn.purpose, "purpose must be a string")
    assert.is_falsy(txn.purpose:find("Trinkgeld", 1, true),
      "Trinkgeld line must be absent when tip=0, got:\n" .. tostring(txn.purpose))
  end)

  -- -------------------------------------------------------------------------
  -- D-37 / non-EUR skip
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction returns nil for non-EUR purchase (D-37)", function()
    local p = load_first("purchase_non_eur")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_nil(txn,
      "non-EUR purchase must return nil (D-37), got: " .. tostring(txn))
  end)

  -- -------------------------------------------------------------------------
  -- D-32 / refund mapping
  -- -------------------------------------------------------------------------

  it("refund_to_transaction returns negative amount (D-32)", function()
    -- purchase_refund: amount=-995 (Zettle delivers negative amount on refund records)
    local p = load_first("purchase_refund")
    local txn = M_mapping.refund_to_transaction(p)
    assert.is_table(txn, "refund_to_transaction must return a table")
    assert.is_true(txn.amount < 0,
      "refund amount must be negative (D-32), got: " .. tostring(txn.amount))
    assert.equals(-9.95, txn.amount,
      "refund amount=-995 minor units => -9.95, got: " .. tostring(txn.amount))
  end)

  it("refund_to_transaction sets transactionCode = zettle:refund:<purchaseUUID1> (D-38)", function()
    local p = load_first("purchase_refund")
    local txn = M_mapping.refund_to_transaction(p)
    assert.is_table(txn, "refund_to_transaction must return a table")
    -- purchaseUUID1 of the refund record itself (33333333-...)
    assert.equals("zettle:refund:33333333-3333-3333-3333-333333333333", txn.transactionCode,
      "transactionCode must be 'zettle:refund:<own-uuid>', got: " .. tostring(txn.transactionCode))
  end)

  it("refund_to_transaction purpose references original purchaseNumber via refundsPurchaseUUID1 (D-32)", function()
    -- purchase_refund: refundsPurchaseUUID1 = "11111111-1111-1111-1111-111111111111"
    -- Phase 3 uses UUID as fallback (original purchaseNumber lookup is Phase 4)
    local p = load_first("purchase_refund")
    local txn = M_mapping.refund_to_transaction(p)
    assert.is_table(txn, "refund_to_transaction must return a table")
    assert.is_string(txn.purpose, "purpose must be a string")
    assert.is_truthy(txn.purpose:find("R\xc3\xbcckerstattung zu Beleg #", 1, true),
      "purpose must start with 'Rückerstattung zu Beleg #', got:\n" .. tostring(txn.purpose))
  end)

  it("refund_to_transaction name appends Rückerstattung suffix (D-32 / D-35)", function()
    -- purchase_refund has empty payments, so base label is "Kartenzahlung"
    -- Expected: "Kartenzahlung Rückerstattung"
    local p = load_first("purchase_refund")
    local txn = M_mapping.refund_to_transaction(p)
    assert.is_table(txn, "refund_to_transaction must return a table")
    assert.is_string(txn.name, "name must be a string")
    assert.is_truthy(txn.name:find("R\xc3\xbcckerstattung", 1, true),
      "name must contain 'Rückerstattung' suffix (D-32/D-35), got: " .. tostring(txn.name))
  end)

  -- -------------------------------------------------------------------------
  -- D-34 / _format_amount (tested indirectly via purpose substrings)
  -- -------------------------------------------------------------------------

  it("_format_amount renders 1995 minor units as 19,95 with German comma decimal (D-34)", function()
    -- Tested indirectly via purchase_with_vat_and_tip: amount=1995 => "Brutto: 19,95 €"
    local p = load_first("purchase_with_vat_and_tip")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_truthy(txn.purpose:find("Brutto: 19,95 \xe2\x82\xac", 1, true),
      "_format_amount(1995) must produce '19,95' in purpose, got:\n" .. tostring(txn.purpose))
  end)

  it("_format_amount renders 500 minor units as 5,00 (D-34)", function()
    -- Tested indirectly via purchase_simple_sale: amount=500 => "Brutto: 5,00 €"
    local p = load_first("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_truthy(txn.purpose:find("Brutto: 5,00 \xe2\x82\xac", 1, true),
      "_format_amount(500) must produce '5,00' in purpose, got:\n" .. tostring(txn.purpose))
  end)

  -- -------------------------------------------------------------------------
  -- S-02: _parse_iso8601_utc must return nil for out-of-range month/day (no crash)
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction does not crash on out-of-range month 00 (S-02)", function()
    -- Month 00 is outside [1..12]; _MONTH_DAYS[0]=nil causes arithmetic crash without guard.
    -- After fix: must return a table using os.time() fallback for bookingDate.
    local p = {
      purchaseUUID1  = "uuid-s02-month00",
      amount         = 100,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-00-01T00:00:00.000+0000",
      purchaseNumber = 9001,
      payments       = {},
    }
    local ok, result = pcall(M_mapping.purchase_to_transaction, p)
    assert.is_true(ok,
      "purchase_to_transaction must not crash on month=00 (S-02), error: " .. tostring(result))
    assert.is_table(result,
      "purchase_to_transaction must return a table (os.time() fallback) for month=00 (S-02)")
  end)

  it("purchase_to_transaction does not crash on out-of-range month 13 (S-02)", function()
    -- Month 13 is outside [1..12]; _MONTH_DAYS[13]=nil causes arithmetic crash without guard.
    local p = {
      purchaseUUID1  = "uuid-s02-month13",
      amount         = 200,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-13-01T00:00:00.000+0000",
      purchaseNumber = 9002,
      payments       = {},
    }
    local ok, result = pcall(M_mapping.purchase_to_transaction, p)
    assert.is_true(ok,
      "purchase_to_transaction must not crash on month=13 (S-02), error: " .. tostring(result))
    assert.is_table(result,
      "purchase_to_transaction must return a table (os.time() fallback) for month=13 (S-02)")
  end)

  it("purchase_to_transaction does not crash on out-of-range day 00 (S-02)", function()
    -- Day 00 should be caught by the D guard and trigger os.time() fallback.
    local p = {
      purchaseUUID1  = "uuid-s02-day00",
      amount         = 300,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-06-00T00:00:00.000+0000",
      purchaseNumber = 9003,
      payments       = {},
    }
    local ok, result = pcall(M_mapping.purchase_to_transaction, p)
    assert.is_true(ok,
      "purchase_to_transaction must not crash on day=00 (S-02), error: " .. tostring(result))
    assert.is_table(result,
      "purchase_to_transaction must return a table (os.time() fallback) for day=00 (S-02)")
  end)

  -- -------------------------------------------------------------------------
  -- S-03 / LO-03: nil or empty purchaseUUID1 must return nil (guard against collision)
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction returns nil for nil purchaseUUID1 (S-03 / LO-03)", function()
    -- nil UUID would produce transactionCode="zettle:sale:" — a collision risk.
    local p = {
      purchaseUUID1  = nil,
      amount         = 500,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-06-01T10:00:00Z",
      purchaseNumber = 9004,
      payments       = {},
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_nil(txn,
      "purchase_to_transaction must return nil when purchaseUUID1 is nil (S-03), got: " ..
      tostring(txn))
  end)

  it("purchase_to_transaction returns nil for empty string purchaseUUID1 (S-03 / LO-03)", function()
    local p = {
      purchaseUUID1  = "",
      amount         = 500,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-06-01T10:00:00Z",
      purchaseNumber = 9005,
      payments       = {},
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_nil(txn,
      "purchase_to_transaction must return nil when purchaseUUID1 is empty string (S-03), got: " ..
      tostring(txn))
  end)

  it("refund_to_transaction returns nil for nil purchaseUUID1 (S-03 / LO-03)", function()
    local p = {
      purchaseUUID1        = nil,
      amount               = -500,
      vatAmount            = -80,
      currency             = "EUR",
      timestamp            = "2026-06-01T10:00:00Z",
      purchaseNumber       = 9006,
      refund               = true,
      refundsPurchaseUUID1 = "orig-uuid",
      payments             = {},
    }
    local txn = M_mapping.refund_to_transaction(p)
    assert.is_nil(txn,
      "refund_to_transaction must return nil when purchaseUUID1 is nil (S-03), got: " ..
      tostring(txn))
  end)

  -- -------------------------------------------------------------------------
  -- S-01: D-37 log line must not propagate unbounded currency strings
  -- -------------------------------------------------------------------------

  it("purchase_to_transaction D-37 log line is length-capped for long currency values (S-01)", function()
    -- Attacker-controlled currency field: 1000 chars. After fix, log line must be short.
    local long_currency = string.rep("X", 1000)
    local p = {
      purchaseUUID1  = "uuid-s01",
      amount         = 100,
      vatAmount      = 0,
      currency       = long_currency,
      timestamp      = "2026-06-01T10:00:00Z",
      purchaseNumber = 9007,
      payments       = {},
    }
    -- Capture log output via M_log.info override
    local captured = {}
    local orig_info = M_log.info
    M_log.info = function(msg) captured[#captured + 1] = msg end
    local txn = M_mapping.purchase_to_transaction(p)
    M_log.info = orig_info
    -- Must return nil (non-EUR)
    assert.is_nil(txn,
      "non-EUR purchase must return nil even with long currency string (S-01)")
    -- The captured D-37 log line must not embed the full 1000-char string
    assert.is_true(#captured >= 1,
      "D-37 INFO log must have been emitted (S-01)")
    for _, line in ipairs(captured) do
      assert.is_true(#line < 200,
        "D-37 log line must not be unbounded; got length " .. #line .. " (S-01)")
    end
  end)

  -- -------------------------------------------------------------------------
  -- HI-01: refund purpose must include MwSt line when vatAmount is negative
  -- -------------------------------------------------------------------------

  it("refund_to_transaction purpose shows negative MwSt line when vatAmount < 0 (HI-01)", function()
    -- purchase_refund fixture: amount=-995, vatAmount=-159.
    -- German UStG-Voranmeldung requires the MwSt line even on refunds.
    -- Fix: change condition from 'vat > 0' to 'vat ~= 0' in _format_purpose.
    local p = load_first("purchase_refund")
    local txn = M_mapping.refund_to_transaction(p)
    assert.is_table(txn, "refund_to_transaction must return a table")
    assert.is_string(txn.purpose, "purpose must be a string")
    assert.is_truthy(txn.purpose:find("MwSt: -1,59 \xe2\x82\xac", 1, true),
      "refund purpose must contain 'MwSt: -1,59 \xe2\x82\xac' (HI-01), got:\n" ..
      tostring(txn.purpose))
    -- Netto = -995 - (-159) = -836 minor units = -8,36 EUR
    assert.is_truthy(txn.purpose:find("Netto: -8,36 \xe2\x82\xac", 1, true),
      "refund Netto must be '-8,36 \xe2\x82\xac' (HI-01), got:\n" .. tostring(txn.purpose))
  end)

  -- -------------------------------------------------------------------------
  -- Plan 04-02: fee_to_transaction (FEE-01)
  -- -------------------------------------------------------------------------

  it("fee_to_transaction returns valid transaction with zettle:fee: prefix for valid input (FEE-01)", function()
    local _, fin_decoded = Fixtures.load("finance/finance_payment_with_fee_linkage")
    local fee_raw = fin_decoded.data[2]
    assert.equals("PAYMENT_FEE", fee_raw.originatorTransactionType)
    local fee = M_finance.parse_transaction(fee_raw)
    assert.is_table(fee, "parse_transaction must yield a table for fee record")
    local _, purch_decoded = Fixtures.load("purchases/purchase_page_with_payments_for_fee_join")
    local purchase = purch_decoded.purchases[1]
    local txn = M_mapping.fee_to_transaction(fee, purchase)
    assert.is_table(txn)
    assert.equals("zettle:fee:cccccccc-cccc-cccc-cccc-cccccccccccc", txn.transactionCode)
    assert.is_true(txn.amount < 0, "fee amount must be negative on sale, got: " .. tostring(txn.amount))
    assert.is_true(txn.booked)
    assert.equals("EUR", txn.currency)
    assert.is_truthy(txn.purpose:find("Beleg #2001", 1, true),
      "purpose must cite originating purchaseNumber 2001, got:\n" .. tostring(txn.purpose))
    assert.equals(M_i18n.t("account.name.fee"), txn.name)
  end)

  it("fee_to_transaction returns nil for fee with empty originatingTransactionUuid", function()
    local txn = M_mapping.fee_to_transaction({
      kind = "PAYMENT_FEE",
      amount = -100,
      timestamp_iso = "2026-06-01T12:00:00.000+0000",
      originatingTransactionUuid = "",
    }, nil)
    assert.is_nil(txn, "must reject empty originatingTransactionUuid")
  end)

  it("fee_to_transaction falls back to '?' receipt when originating_purchase is nil", function()
    local txn = M_mapping.fee_to_transaction({
      kind = "PAYMENT_FEE",
      amount = -42,
      timestamp_iso = "2026-06-01T12:00:00.000+0000",
      originatingTransactionUuid = "uuid-orphan",
    }, nil)
    assert.is_table(txn)
    assert.is_truthy(txn.purpose:find("Beleg #?", 1, true),
      "purpose must contain 'Beleg #?' fallback when purchase is nil, got:\n" .. tostring(txn.purpose))
  end)

  -- -------------------------------------------------------------------------
  -- Plan 04-02: fee_aggregate_to_transaction (FEE-03 / D-49)
  -- -------------------------------------------------------------------------

  it("fee_aggregate_to_transaction sums minor units and emits stable transactionCode", function()
    local fees = {
      { amount = -100 }, { amount = -50 }, { amount = -200 },
    }
    local txn = M_mapping.fee_aggregate_to_transaction(fees, "2026-06-15", 3)
    assert.is_table(txn)
    assert.equals("zettle:fee:aggregate:2026-06-15", txn.transactionCode)
    assert.equals(-3.5, txn.amount, "sum/100 must be -3.50")
    assert.is_true(txn.booked)
    assert.equals("EUR", txn.currency)
    -- "3 Einzelgebühren" — UTF-8 ü is \xc3\xbc
    assert.is_truthy(txn.purpose:find("3 Einzelgeb\xc3\xbchren", 1, true),
      "purpose must contain '3 Einzelgebühren', got:\n" .. tostring(txn.purpose))
  end)

  it("fee_aggregate_to_transaction bookingDate is Berlin-local 00:00 of date_iso", function()
    -- date_iso "2026-06-15" -> CEST: bookingDate represents 2026-06-15 00:00 Berlin local.
    -- os.date("!*t", bookingDate) decomposes the Berlin-local POSIX as if UTC, so
    -- year=2026 month=6 day=15 hour=0 min=0 (same convention as Phase-3 D-36 tests).
    local txn = M_mapping.fee_aggregate_to_transaction({}, "2026-06-15", 0)
    assert.is_table(txn)
    local t = os.date("!*t", txn.bookingDate)
    assert.equals(2026, t.year)
    assert.equals(6, t.month)
    assert.equals(15, t.day)
    assert.equals(0, t.hour)
    assert.equals(0, t.min)
  end)

  it("fee_aggregate_to_transaction returns nil for malformed date_iso", function()
    assert.is_nil(M_mapping.fee_aggregate_to_transaction({}, "not-a-date", 0))
    assert.is_nil(M_mapping.fee_aggregate_to_transaction({}, "2026/06/15", 0))
    assert.is_nil(M_mapping.fee_aggregate_to_transaction({}, nil, 0))
  end)

  -- -------------------------------------------------------------------------
  -- Plan 04-02: payout_to_transaction (PAYOUT-01..03)
  -- -------------------------------------------------------------------------

  it("payout_to_transaction returns valid transaction with zettle:payout: prefix and 'Auszahlung an Bankkonto' name (PAYOUT-01/02/03)", function()
    local _, fin_decoded = Fixtures.load("finance/finance_payout")
    local payout = M_finance.parse_transaction(fin_decoded.data[1])
    assert.is_table(payout)
    local txn = M_mapping.payout_to_transaction(payout)
    assert.is_table(txn)
    assert.equals("zettle:payout:dddddddd-dddd-dddd-dddd-dddddddddddd", txn.transactionCode)
    assert.equals("Auszahlung an Bankkonto", txn.name)
    assert.equals(-1500.0, txn.amount, "150000 minor units negative -> -1500.00 EUR")
    assert.is_true(txn.booked)
    assert.equals("EUR", txn.currency)
    assert.is_truthy(txn.purpose:find("Auszahlung an Bankkonto am", 1, true),
      "purpose must mention 'Auszahlung an Bankkonto am', got:\n" .. tostring(txn.purpose))
  end)

  it("payout_to_transaction valueDate equals bookingDate (PAYOUT-03 / payout-is-settlement)", function()
    local _, fin_decoded = Fixtures.load("finance/finance_payout")
    local payout = M_finance.parse_transaction(fin_decoded.data[1])
    local txn = M_mapping.payout_to_transaction(payout)
    assert.equals(txn.bookingDate, txn.valueDate,
      "valueDate must equal bookingDate — PAYOUT IS the settlement event")
  end)

  it("payout_to_transaction returns nil for payout with missing originatingTransactionUuid", function()
    local txn = M_mapping.payout_to_transaction({
      kind = "PAYOUT",
      amount = -100,
      timestamp_iso = "2026-06-01T12:00:00.000+0000",
      originatingTransactionUuid = "",
    })
    assert.is_nil(txn)
  end)

  -- -------------------------------------------------------------------------
  -- Plan 04-02: promote_to_booked (D-56)
  -- -------------------------------------------------------------------------

  it("promote_to_booked sets booked=true and valueDate on a phase-3 sale txn (D-56)", function()
    local p = load_first("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    assert.is_false(txn.booked, "Phase 3 sale starts booked=false")
    local original_code = txn.transactionCode
    M_mapping.promote_to_booked(txn, 1781920500)
    assert.is_true(txn.booked)
    assert.equals(1781920500, txn.valueDate)
    assert.equals(original_code, txn.transactionCode,
      "transactionCode must remain unchanged so MoneyMoney dedup updates in place")
  end)

  it("promote_to_booked is idempotent (calling twice with same args is a no-op)", function()
    local txn = { booked = false }
    M_mapping.promote_to_booked(txn, 12345)
    M_mapping.promote_to_booked(txn, 12345)
    assert.is_true(txn.booked)
    assert.equals(12345, txn.valueDate)
  end)

  it("promote_to_booked silently returns on non-table input", function()
    assert.has_no.errors(function() M_mapping.promote_to_booked(nil, 0) end)
    assert.has_no.errors(function() M_mapping.promote_to_booked("not-a-txn", 0) end)
  end)

  -- -------------------------------------------------------------------------
  -- Plan 04-02: refund_to_transaction(p, opts) opts.original_receipt (REF-02 / D-50)
  -- -------------------------------------------------------------------------

  it("refund_to_transaction(p, opts) cites opts.original_receipt when provided (REF-02 / D-50)", function()
    local _, decoded = Fixtures.load("purchases/purchase_refund_with_original_in_page")
    local refund = decoded.purchases[2]
    assert.is_true(refund.refund, "fixture sanity: second purchase must be the refund")
    local txn = M_mapping.refund_to_transaction(refund, { original_receipt = 4001 })
    assert.is_table(txn)
    assert.is_truthy(txn.purpose:find("R\xc3\xbcckerstattung zu Beleg #4001", 1, true),
      "purpose must cite 'Rückerstattung zu Beleg #4001', got:\n" .. tostring(txn.purpose))
  end)

  it("refund_to_transaction(p) without opts falls back to UUID per Phase-3 D-32", function()
    local _, decoded = Fixtures.load("purchases/purchase_refund_with_original_in_page")
    local refund = decoded.purchases[2]
    local txn = M_mapping.refund_to_transaction(refund)
    assert.is_table(txn)
    assert.is_truthy(txn.purpose:find("30303030", 1, true),
      "purpose must contain refundsPurchaseUUID1 substring '30303030' as fallback, got:\n" ..
      tostring(txn.purpose))
  end)

  -- -------------------------------------------------------------------------
  -- Plan 04-04: META-01 — per-rate VAT lines in _format_purpose (D-53)
  -- -------------------------------------------------------------------------

  it("META-01: groupedVatAmounts with two rates produces two MwSt lines sorted descending", function()
    local p = load_first("purchase_vat_split_19_7")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    -- Two distinct per-rate lines: 19% (318 minor units = 3,18 EUR) then 7% (140 minor = 1,40 EUR).
    local pos19 = txn.purpose:find("19% MwSt: 3,18 EUR", 1, true)
    local pos7  = txn.purpose:find("7% MwSt: 1,40 EUR", 1, true)
    assert.is_truthy(pos19, "missing '19% MwSt: 3,18 EUR' in purpose:\n" .. tostring(txn.purpose))
    assert.is_truthy(pos7,  "missing '7% MwSt: 1,40 EUR' in purpose:\n" .. tostring(txn.purpose))
    assert.is_true(pos19 < pos7, "19% MwSt line must precede 7% MwSt line (descending sort)")
  end)

  it("META-01: groupedVatAmounts with single rate falls through to Phase-3 single MwSt line", function()
    local p = load_first("purchase_with_vat_and_tip")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    -- Exactly one MwSt: occurrence, and it uses the Phase-3 single-line format.
    local _, count = txn.purpose:gsub("MwSt:", "")
    assert.equals(1, count, "expected exactly one 'MwSt:' line, got " .. tostring(count) ..
      " in:\n" .. tostring(txn.purpose))
    assert.is_truthy(txn.purpose:find("MwSt: 3,18 €", 1, true),
      "expected Phase-3 single-line 'MwSt: 3,18 €' in:\n" .. tostring(txn.purpose))
    -- The per-rate prefix format ("19% MwSt") MUST NOT appear on the single-rate path.
    assert.is_nil(txn.purpose:find("19% MwSt", 1, true),
      "per-rate prefix must NOT appear on single-rate fallback path; got:\n" .. tostring(txn.purpose))
  end)

  it("META-01: groupedVatAmounts empty map falls through to Phase-3 single MwSt line (vatAmount only)", function()
    -- purchase_with_card_metadata has groupedVatAmounts={} and vatAmount=0 → no MwSt line at all (D-34).
    -- Use an inline record with vatAmount>0 and empty groupedVatAmounts to exercise the fallback branch.
    local p = {
      purchaseUUID1 = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      amount = 1000,
      vatAmount = 159,
      currency = "EUR",
      timestamp = "2026-06-15T10:00:00.000+0000",
      purchaseNumber = 7001,
      payments = {},
      groupedVatAmounts = {},
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    local _, count = txn.purpose:gsub("MwSt:", "")
    assert.equals(1, count, "expected exactly one 'MwSt:' line, got " .. tostring(count))
    assert.is_truthy(txn.purpose:find("MwSt: 1,59 €", 1, true))
    assert.is_nil(txn.purpose:find("% MwSt", 1, true),
      "per-rate prefix must NOT appear on empty-map fallback path")
  end)

  it("META-01: integer-string key '19' is accepted equivalently to decimal-string '19.0' (defensive — R-5)", function()
    local p = {
      purchaseUUID1 = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
      amount = 2000,
      vatAmount = 458,
      currency = "EUR",
      timestamp = "2026-06-15T10:00:00.000+0000",
      purchaseNumber = 7002,
      payments = {},
      groupedVatAmounts = { ["19"] = 318, ["7"] = 140 },
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    assert.is_truthy(txn.purpose:find("19% MwSt: 3,18 EUR", 1, true),
      "integer-string key '19' must produce '19% MwSt: 3,18 EUR' line, got:\n" .. tostring(txn.purpose))
    assert.is_truthy(txn.purpose:find("7% MwSt: 1,40 EUR", 1, true),
      "integer-string key '7' must produce '7% MwSt: 1,40 EUR' line, got:\n" .. tostring(txn.purpose))
  end)

  it("S-01: pathological groupedVatAmounts key (scientific notation, oversize, non-numeric) does NOT crash purchase_to_transaction", function()
    -- SEC-01 (HIGH): groupedVatAmounts keys come straight from the Zettle
    -- response (or a compromised CDN). string.format("%d", tonumber("1e308"))
    -- raises "number has no integer representation" — uncaught Lua error that
    -- would abort RefreshAccount. Range-guard tonumber(k) to [0, 100] (a real
    -- VAT rate cannot fall outside this range for any tax regime).
    local p = {
      purchaseUUID1 = "5e505e50-5e50-5e50-5e50-5e505e505e50",
      amount = 2000,
      vatAmount = 318,
      currency = "EUR",
      timestamp = "2026-06-15T10:00:00.000+0000",
      purchaseNumber = 7100,
      payments = {},
      -- Three pathological keys + one legitimate key.
      -- "1e308" parses to a finite float with no integer representation -> %d crash.
      -- "abc"   is non-numeric and must be skipped.
      -- "999"   is numeric but outside [0..100] and must be skipped.
      -- "19"    is legitimate and must drive the single-rate fallback.
      groupedVatAmounts = {
        ["1e308"] = 100,
        ["abc"] = 50,
        ["999"] = 10,
        ["19"] = 318,
      },
    }
    local ok, result = pcall(M_mapping.purchase_to_transaction, p)
    assert.is_true(ok,
      "S-01: purchase_to_transaction must NOT raise a Lua error on pathological "
      .. "groupedVatAmounts keys; got: " .. tostring(result))
    assert.is_table(result, "S-01: must still return a valid txn table")
    -- The "19" key is the only one to pass the range guard, so the single-rate
    -- fallback fires (only 1 entry in rate_entries -> not >= 2).
    -- Defensive: the resulting purpose must NOT contain "1e308" or "999%" or "abc".
    assert.is_falsy(result.purpose:find("1e308", 1, true),
      "S-01: pathological '1e308' key must NOT appear in purpose")
    assert.is_falsy(result.purpose:find("999%%", 1, false),
      "S-01: out-of-range '999' key must NOT appear in purpose")
  end)

  it("S-01: pathological groupedVatAmounts key in multi-rate path is skipped silently (oversize float, non-numeric)", function()
    -- Same defence with TWO legitimate rates so the multi-rate branch fires.
    local p = {
      purchaseUUID1 = "5e515e51-5e51-5e51-5e51-5e515e515e51",
      amount = 2000,
      vatAmount = 458,
      currency = "EUR",
      timestamp = "2026-06-15T10:00:00.000+0000",
      purchaseNumber = 7101,
      payments = {},
      groupedVatAmounts = {
        ["19.0"] = 318,
        ["7.0"]  = 140,
        ["1e308"] = 100,    -- range-guard rejects (math.huge > 100)
        ["-5"]    = 25,     -- range-guard rejects (rate < 0)
        ["abc"]   = 50,     -- tonumber returns nil, falls through guard
      },
    }
    local ok, result = pcall(M_mapping.purchase_to_transaction, p)
    assert.is_true(ok,
      "S-01: multi-rate path must NOT raise a Lua error on pathological keys; got: "
      .. tostring(result))
    assert.is_table(result)
    -- Multi-rate path emits 19% and 7% lines.
    assert.is_truthy(result.purpose:find("19% MwSt: 3,18 EUR", 1, true),
      "S-01: legitimate 19% rate must still render in multi-rate path")
    assert.is_truthy(result.purpose:find("7% MwSt: 1,40 EUR", 1, true),
      "S-01: legitimate 7% rate must still render in multi-rate path")
    -- Pathological rates must NOT appear.
    assert.is_falsy(result.purpose:find("1e308", 1, true),
      "S-01: oversize float rate '1e308' must be silently skipped")
    assert.is_falsy(result.purpose:find("-5%", 1, true),
      "S-01: negative rate must be silently skipped")
  end)

  it("META-01: negative VAT amounts on refund records render with leading minus", function()
    local p = {
      purchaseUUID1 = "cccccccc-cccc-cccc-cccc-cccccccccccc",
      amount = -500,
      vatAmount = -87,
      currency = "EUR",
      timestamp = "2026-06-15T10:00:00.000+0000",
      purchaseNumber = 7003,
      refund = true,
      refundsPurchaseUUID1 = "dddddddd-dddd-dddd-dddd-dddddddddddd",
      payments = {},
      groupedVatAmounts = { ["19.0"] = -57, ["7.0"] = -30 },
    }
    local txn = M_mapping.refund_to_transaction(p)
    assert.is_table(txn)
    assert.is_truthy(txn.purpose:find("19% MwSt: -0,57 EUR", 1, true),
      "expected '19% MwSt: -0,57 EUR' for negative refund VAT, got:\n" .. tostring(txn.purpose))
    assert.is_truthy(txn.purpose:find("7% MwSt: -0,30 EUR", 1, true),
      "expected '7% MwSt: -0,30 EUR' for negative refund VAT, got:\n" .. tostring(txn.purpose))
  end)

  -- -------------------------------------------------------------------------
  -- Plan 04-04: SALE-07 — card-brand + entry-mode tail line in _format_purpose (D-57)
  -- -------------------------------------------------------------------------

  it("SALE-07: both cardType and cardPaymentEntryMode present produces 'Zahlart: Visa (kontaktlos)'", function()
    local p = load_first("purchase_with_card_metadata_kontaktlos")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    assert.is_truthy(txn.purpose:find("Zahlart: Visa (kontaktlos)", 1, true),
      "expected 'Zahlart: Visa (kontaktlos)' tail line, got:\n" .. tostring(txn.purpose))
  end)

  it("SALE-07: only cardType present produces 'Zahlart: Visa' (no parens)", function()
    local p = {
      purchaseUUID1 = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
      amount = 500,
      vatAmount = 0,
      currency = "EUR",
      timestamp = "2026-06-15T10:00:00.000+0000",
      purchaseNumber = 7004,
      payments = {
        {
          uuid = "p1", type = "IZETTLE_CARD", amount = 500, gratuityAmount = 0,
          attributes = { cardType = "VISA", maskedPan = "411111******1111" },
        },
      },
      groupedVatAmounts = {},
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    local zpos = txn.purpose:find("Zahlart: Visa", 1, true)
    assert.is_truthy(zpos, "expected 'Zahlart: Visa' tail line, got:\n" .. tostring(txn.purpose))
    -- After the Zahlart line, there must be no opening paren on that line.
    local line_end = txn.purpose:find("\n", zpos, true) or (#txn.purpose + 1)
    local zahlart_line = txn.purpose:sub(zpos, line_end - 1)
    assert.is_nil(zahlart_line:find("(", 1, true),
      "Zahlart line must NOT contain '(' when entry-mode absent; got line: " .. zahlart_line)
  end)

  it("SALE-07: both fields absent — Zahlart line is OMITTED", function()
    local p = load_first("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    assert.is_nil(txn.purpose:find("Zahlart", 1, true),
      "Zahlart line must be omitted when both card fields absent; got:\n" .. tostring(txn.purpose))
  end)

  it("SALE-07: unknown cardPaymentEntryMode maps to 'unbekannt' fallback", function()
    local p = {
      purchaseUUID1 = "ffffffff-ffff-ffff-ffff-ffffffffffff",
      amount = 500,
      vatAmount = 0,
      currency = "EUR",
      timestamp = "2026-06-15T10:00:00.000+0000",
      purchaseNumber = 7005,
      payments = {
        {
          uuid = "p1", type = "IZETTLE_CARD", amount = 500, gratuityAmount = 0,
          attributes = {
            cardType = "VISA",
            maskedPan = "411111******1111",
            cardPaymentEntryMode = "SOMETHING_NEW_NOT_IN_MAP",
          },
        },
      },
      groupedVatAmounts = {},
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    assert.is_truthy(txn.purpose:find("Zahlart: Visa (unbekannt)", 1, true),
      "expected 'Zahlart: Visa (unbekannt)' for unmapped entry mode, got:\n" .. tostring(txn.purpose))
  end)

  -- -------------------------------------------------------------------------
  -- Plan 04-04: Phase-3 surface preservation (RESEARCH §Pitfall 8)
  -- -------------------------------------------------------------------------

  it("Phase-3 surface preservation: purchase_simple_sale produces byte-identical purpose to Phase 3", function()
    local p = load_first("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    local expected = "Brutto: 5,00 \xe2\x82\xac\nNetto: 5,00 \xe2\x82\xac\nBeleg #1001"
    assert.equals(expected, txn.purpose,
      "Phase-3 purpose surface must be byte-identical for no-VAT-no-card fixture")
  end)

  it("META-01: UTF-8 umlauts round-trip via dkjson and survive in fixture", function()
    local raw, decoded = Fixtures.load("purchases/purchase_umlauts_purpose")
    assert.is_string(raw)
    assert.is_table(decoded)
    -- Round-trip the raw fixture: decoded.userDisplayName must preserve "Café" UTF-8.
    local p = decoded.purchases[1]
    assert.is_table(p)
    assert.equals("Beispiel-Caf\xc3\xa9", p.userDisplayName,
      "Café (U+00E9 é = \\xc3\\xa9 UTF-8) must round-trip via dkjson; got: " ..
      tostring(p.userDisplayName))
    -- Sanity: _format_purpose still works on the umlauts fixture (no card meta, no VAT split).
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn)
    assert.is_truthy(txn.purpose:find("Beleg #6001", 1, true))
  end)

end)
