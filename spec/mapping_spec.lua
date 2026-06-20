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

end)
