-- spec/mapping_schema_spec.lua
-- Gating spec for TEST-04 / SALE-01 / SALE-03 / SALE-08 / D-31 / D-32 / D-37 / D-38.
--
-- RED in Wave 1: src/mapping.lua is an empty stub — M_mapping.purchase_to_transaction
-- and M_mapping.refund_to_transaction do not exist.  Every call returns nil, causing
-- assert_schema to fail on the very first REQUIRED_FIELDS check.  Assertion errors
-- (not Lua errors) prove the spec exercises real code paths.
--
-- Wave 2 (src/mapping.lua) greens Tests 1-4 and 7-8.
-- Tests 5 + 6 additionally require the DST table inside _to_berlin_local_time
-- (also Wave 2) — both wave ticks are expected before these two are green.
--
-- Card metadata path: payments[1].attributes.cardType + maskedPan per RESEARCH §1
-- correction over CONTEXT D-35 wording (which named cardBrand / cardLastFour).

-- luacheck: globals M_mapping LocalStorage
-- luacheck: ignore 431

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Build a fresh artifact once before the suite runs.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("mapping_schema_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("transaction schema gate (TEST-04)", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- REQUIRED_FIELDS: the seven mandatory MoneyMoney transaction fields.
  -- Single source of truth — if mapping.lua ever drops or renames a field,
  -- every test using assert_schema breaks simultaneously (T-03-W1-02).
  -- -------------------------------------------------------------------------
  local REQUIRED_FIELDS = {
    "name", "amount", "currency", "bookingDate",
    "purpose", "transactionCode", "booked",
  }

  -- -------------------------------------------------------------------------
  -- assert_schema(txn, label)
  -- Walk REQUIRED_FIELDS and fail with a descriptive message on first miss.
  -- Pattern from spec/log_redaction_spec.lua L327-344 (invariant-walk helper).
  -- -------------------------------------------------------------------------
  local function assert_schema(txn, label)
    assert.is_table(txn, label .. ": purchase_to_transaction must return a table, got: " .. tostring(txn))
    for _, field in ipairs(REQUIRED_FIELDS) do
      assert.is_not_nil(txn[field],
        label .. ": missing required field '" .. field .. "'")
    end
  end

  -- -------------------------------------------------------------------------
  -- assert_callable(fn, name)
  -- Fail fast with an assertion error (not a Lua error) if the mapping function
  -- is not yet implemented (Wave-1 stubs leave M_mapping as an empty table).
  -- This converts the nil-call Lua error into a proper assertion failure so the
  -- spec produces "assertion failures, not Lua errors" per the plan's RED contract.
  -- -------------------------------------------------------------------------
  local function assert_callable(fn, name)
    assert.is_function(fn,
      "M_mapping." .. name .. " must be a function — stub not yet implemented (Wave 1 RED)")
  end

  -- -------------------------------------------------------------------------
  -- load_record(name)
  -- Load a purchase fixture, verify shape, and return the first purchase object.
  -- -------------------------------------------------------------------------
  local function load_record(name)
    local _, decoded = Fixtures.load("purchases/" .. name)
    assert.is_table(decoded, "fixture '" .. name .. "' must decode to a table")
    assert.is_table(decoded.purchases,
      "fixture '" .. name .. "' must have a 'purchases' array")
    return decoded.purchases[1]
  end

  -- -------------------------------------------------------------------------

  it("purchase_simple_sale maps to a valid transaction schema (D-31)", function()
    assert_callable(M_mapping.purchase_to_transaction, "purchase_to_transaction")
    local p = load_record("purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(p)
    assert_schema(txn, "simple_sale")
    assert.is_false(txn.booked, "Phase 3: booked must be false (D-31)")
    assert.is_nil(txn.valueDate, "Phase 3: valueDate must be absent (D-31)")
    assert.equals("EUR", txn.currency, "currency must be EUR")
  end)

  it("purchase_with_vat_and_tip maps gross amount = purchase.amount / 100 (SALE-01)", function()
    assert_callable(M_mapping.purchase_to_transaction, "purchase_to_transaction")
    local p = load_record("purchase_with_vat_and_tip")
    local txn = M_mapping.purchase_to_transaction(p)
    assert_schema(txn, "vat_and_tip")
    -- SALE-01: gross amount is purchase.amount (minor units) divided by 100.
    assert.are.equal(p.amount / 100, txn.amount,
      "transaction amount must equal purchase.amount / 100 (SALE-01)")
  end)

  it("purchase_with_card_metadata upgrades name to <Brand> dot-dot-dot <last4> (SALE-08 / D-35 via attributes path)", function() -- luacheck: ignore 631
    -- Card metadata lives in payments[].attributes.cardType + maskedPan per RESEARCH §1.
    -- Fixture purchase_with_card_metadata.json has VISA / maskedPan "411111******1111".
    assert_callable(M_mapping.purchase_to_transaction, "purchase_to_transaction")
    local p = load_record("purchase_with_card_metadata")
    local txn = M_mapping.purchase_to_transaction(p)
    assert_schema(txn, "card_metadata")
    assert.is_string(txn.name, "name must be a string")
    assert.is_truthy(txn.name:find("Visa", 1, true),
      "name must contain the brand 'Visa', got: " .. tostring(txn.name))
    assert.is_truthy(txn.name:find("1111", 1, true),
      "name must contain the last-four '1111', got: " .. tostring(txn.name))
  end)

  it("purchase_refund maps via refund_to_transaction with negative amount and zettle:refund: prefix (D-32 / D-38)", function() -- luacheck: ignore 631
    assert_callable(M_mapping.refund_to_transaction, "refund_to_transaction")
    local p = load_record("purchase_refund")
    local txn = M_mapping.refund_to_transaction(p)
    assert_schema(txn, "refund")
    assert.is_true(txn.amount < 0,
      "refund amount must be negative (D-32), got: " .. tostring(txn.amount))
    assert.is_truthy(txn.transactionCode:find("^zettle:refund:", 1, false),
      "transactionCode must start with 'zettle:refund:' (D-38), got: " ..
      tostring(txn.transactionCode))
    assert.is_false(txn.booked, "refund booked must be false (D-31)")
  end)

  it("purchase_dst_boundary_summer maps bookingDate to Berlin local day 2026-06-20 (SALE-04 / D-36 CEST)", function()
    -- Fixture timestamp: 2026-06-19T23:55:00.000+0000 (UTC).
    -- In Berlin (CEST = UTC+2) this is 01:55 on 2026-06-20.
    -- bookingDate must represent local-day 2026-06-20, not 2026-06-19.
    assert_callable(M_mapping.purchase_to_transaction, "purchase_to_transaction")
    local p = load_record("purchase_dst_boundary_summer")
    local txn = M_mapping.purchase_to_transaction(p)
    assert_schema(txn, "dst_summer")
    -- Decompose POSIX timestamp under UTC to recover the Berlin-local date components.
    -- bookingDate encodes the Berlin midnight of the local day, so os.date("!*t")
    -- on a bookingDate that represents 2026-06-20 00:00 Berlin yields year=2026 month=6 day=20.
    local t = os.date("!*t", txn.bookingDate)
    assert.equals(2026, t.year, "summer DST: year must be 2026")
    assert.equals(6,    t.month, "summer DST: month must be 6")
    assert.equals(20,   t.day,   "summer DST: local day must be 20 (CEST +2h)")
  end)

  it("purchase_dst_boundary_winter maps bookingDate to Berlin local day 2026-02-01 (SALE-04 / D-36 CET)", function()
    -- Fixture timestamp: 2026-01-31T23:55:00.000+0000 (UTC).
    -- In Berlin (CET = UTC+1) this is 00:55 on 2026-02-01.
    -- bookingDate must represent local-day 2026-02-01, not 2026-01-31.
    assert_callable(M_mapping.purchase_to_transaction, "purchase_to_transaction")
    local p = load_record("purchase_dst_boundary_winter")
    local txn = M_mapping.purchase_to_transaction(p)
    assert_schema(txn, "dst_winter")
    local t = os.date("!*t", txn.bookingDate)
    assert.equals(2026, t.year,  "winter CET: year must be 2026")
    assert.equals(2,    t.month, "winter CET: month must be 2")
    assert.equals(1,    t.day,   "winter CET: local day must be 1 (CET +1h)")
  end)

  it("purchase_non_eur returns nil (D-37 silent skip)", function()
    assert_callable(M_mapping.purchase_to_transaction, "purchase_to_transaction")
    local p = load_record("purchase_non_eur")
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_nil(txn,
      "non-EUR purchase must return nil (D-37 silent skip), got: " .. tostring(txn))
  end)

  -- -------------------------------------------------------------------------
  -- Plan 04-02: schema-walk extension for the new Phase-4 mappers.
  -- -------------------------------------------------------------------------

  it("fee_to_transaction output satisfies the 7-field REQUIRED_FIELDS contract", function()
    assert_callable(M_mapping.fee_to_transaction, "fee_to_transaction")
    local _, fin_decoded = Fixtures.load("finance/finance_payment_with_fee_linkage")
    local fee = M_finance.parse_transaction(fin_decoded.data[2])
    assert.is_table(fee, "parse_transaction must yield a fee table")
    local _, purch_decoded = Fixtures.load("purchases/purchase_page_with_payments_for_fee_join")
    local purchase = purch_decoded.purchases[1]
    local txn = M_mapping.fee_to_transaction(fee, purchase)
    assert_schema(txn, "fee_to_transaction")
  end)

  it("fee_aggregate_to_transaction output satisfies the 7-field REQUIRED_FIELDS contract", function()
    assert_callable(M_mapping.fee_aggregate_to_transaction, "fee_aggregate_to_transaction")
    local fees = { { amount = -100 }, { amount = -50 } }
    local txn = M_mapping.fee_aggregate_to_transaction(fees, "2026-06-15", 2)
    assert_schema(txn, "fee_aggregate_to_transaction")
  end)

  it("payout_to_transaction output satisfies the 7-field REQUIRED_FIELDS contract", function()
    assert_callable(M_mapping.payout_to_transaction, "payout_to_transaction")
    local _, fin_decoded = Fixtures.load("finance/finance_payout")
    local payout = M_finance.parse_transaction(fin_decoded.data[1])
    local txn = M_mapping.payout_to_transaction(payout)
    assert_schema(txn, "payout_to_transaction")
  end)

  it("every mapped transaction across fixtures sets currency = EUR (Phase 2 D-23a invariant)", function()
    assert_callable(M_mapping.purchase_to_transaction, "purchase_to_transaction")
    -- Iterate the five EUR sale fixtures and assert each produces currency = "EUR".
    local eur_fixtures = {
      "purchase_simple_sale",
      "purchase_with_vat_and_tip",
      "purchase_with_card_metadata",
      "purchase_dst_boundary_summer",
      "purchase_dst_boundary_winter",
    }
    for _, name in ipairs(eur_fixtures) do
      local p = load_record(name)
      local txn = M_mapping.purchase_to_transaction(p)
      assert.is_table(txn,
        "fixture '" .. name .. "' must map to a table, got nil or non-table")
      assert.equals("EUR", txn.currency,
        "fixture '" .. name .. "' currency must be EUR, got: " .. tostring(txn.currency))
    end
  end)

end)
