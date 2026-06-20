-- spec/mapping_spec.lua
-- Pending scaffold for M_mapping (Phase 3, Wave 2, Plan 03-03).
-- Covers: purchase_to_transaction / refund_to_transaction pure-logic unit tests
-- (SALE-01, SALE-02, SALE-04, SALE-08, I18N-01, D-32, D-34, D-35, D-37, D-38).
--
-- One non-pending sanity test and one Fixtures.load nested-path empirical proof
-- are active now. Wave 2 fills the pending bodies.
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
  -- Sanity tests (non-pending) — confirm artifact loads and modules are present
  -- -------------------------------------------------------------------------

  it("M_mapping module table is exposed", function()
    assert.is_table(M_mapping)
  end)

  it("Fixtures.load reads purchases/purchase_simple_sale", function()
    local raw, decoded = Fixtures.load("purchases/purchase_simple_sale")
    assert.is_string(raw)
    assert.is_table(decoded)
    assert.is_table(decoded.purchases)
    assert.equals(1, #decoded.purchases)
  end)

  -- -------------------------------------------------------------------------
  -- Pending tests — Wave 2 (Plan 03-03) fills these bodies
  -- -------------------------------------------------------------------------

  pending("purchase_to_transaction maps amount to EUR float (SALE-01)", function() end)

  pending("purchase_to_transaction sets transactionCode = zettle:sale:<purchaseUUID1> (SALE-02 / D-38)", function() end)

  pending("purchase_to_transaction sets booked = false and omits valueDate (D-31 / Phase 3 contract)", function() end)

  pending("purchase_to_transaction sets bookingDate via Berlin local time (SALE-04 / D-36)", function() end)

  pending("purchase_to_transaction defaults name to Kartenzahlung when payments empty (SALE-08 / D-35)", function() end)

  -- payments[0].attributes.cardType path per RESEARCH §1 (corrects CONTEXT D-35 wording)
  pending("purchase_to_transaction upgrades name to <Brand> •••• <last4> when payments[0].attributes.cardType present (SALE-08 / D-35 corrected)", function() end)

  pending("purchase_to_transaction purpose contains Brutto / MwSt / Trinkgeld / Netto / Beleg German lines (I18N-01 / D-34)", function() end)

  pending("purchase_to_transaction omits MwSt line when vatAmount = 0 (D-34)", function() end)

  pending("purchase_to_transaction omits Trinkgeld line when payments[].gratuityAmount sums to 0 (D-34)", function() end)

  pending("purchase_to_transaction returns nil for non-EUR purchase (D-37)", function() end)

  pending("refund_to_transaction returns negative amount (D-32)", function() end)

  pending("refund_to_transaction sets transactionCode = zettle:refund:<purchaseUUID1> (D-38)", function() end)

  pending("refund_to_transaction purpose references original purchaseNumber via refundsPurchaseUUID1 (D-32)", function() end)

  pending("refund_to_transaction name appends Rückerstattung suffix (D-32 / D-35)", function() end)

  pending("_format_amount renders 1995 minor units as 19,95 with German comma decimal (D-34)", function() end)

  pending("_format_amount renders 500 minor units as 5,00 (D-34)", function() end)

end)
