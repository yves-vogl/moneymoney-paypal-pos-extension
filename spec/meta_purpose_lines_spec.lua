-- spec/meta_purpose_lines_spec.lua
-- META-02 + META-01 zero-edge gating spec — promoted to its own file per
-- CONTEXT D-54 so the zero-suppression invariant is greppable in isolation
-- from the broader mapping_spec suite.
--
-- Gates:
--   META-02: Trinkgeld line absent when sum of payments[].gratuityAmount == 0
--            (includes empty payments table). Present and rendered when > 0.
--   META-01: zero-rate edge cases per RESEARCH §5.3.
--            (a) Sole 0% entry with value 0  -> MwSt line suppressed entirely
--            (b) 0% alongside 19%            -> both per-rate lines rendered;
--                                              19% sorted before 0% (descending)
--
-- The Phase-3 mapping_spec.lua already exercises these invariants implicitly;
-- this file is the dedicated regression gate per D-54 (mapping_spec retains
-- its own copies — no test removed).

-- luacheck: globals M_mapping

local Mocks = require("spec.helpers.mm_mocks")

-- Build a fresh artifact once before the suite runs.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("meta_purpose_lines_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("META-02: Trinkgeld zero-suppression (D-54 promotion)", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  it("META-02: Trinkgeld line absent when sum of gratuityAmount is 0", function()
    local p = {
      purchaseUUID1  = "meta02-zero-sum-uuid",
      amount         = 500,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-05-15T10:30:00Z",
      purchaseNumber = 1001,
      payments       = {
        { gratuityAmount = 0 },
        { gratuityAmount = 0 },
      },
      groupedVatAmounts = {},
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_string(txn.purpose, "purpose must be a string")
    assert.is_nil(txn.purpose:find("Trinkgeld", 1, true),
      "Trinkgeld line must be absent when sum gratuityAmount==0, got:\n" .. txn.purpose)
  end)

  it("META-02: Trinkgeld line absent when payments table is empty", function()
    local p = {
      purchaseUUID1  = "meta02-empty-payments-uuid",
      amount         = 700,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-05-15T10:30:00Z",
      purchaseNumber = 1002,
      payments       = {},
      groupedVatAmounts = {},
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_nil(txn.purpose:find("Trinkgeld", 1, true),
      "Trinkgeld line must be absent when payments={}, got:\n" .. txn.purpose)
  end)

  it("META-02: Trinkgeld line present and renders gratuityAmount sum when > 0", function()
    local p = {
      purchaseUUID1  = "meta02-tip-present-uuid",
      amount         = 800,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-05-15T10:30:00Z",
      purchaseNumber = 1003,
      payments       = {
        { gratuityAmount = 100 },
        { gratuityAmount = 50 },
      },
      groupedVatAmounts = {},
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    -- 100 + 50 = 150 minor units = 1,50 €. Phase-3 uses the € symbol (UTF-8 \xe2\x82\xac).
    assert.is_truthy(txn.purpose:find("Trinkgeld: 1,50 \xe2\x82\xac", 1, true),
      "Trinkgeld line must render sum 1,50 €, got:\n" .. txn.purpose)
  end)

end)

-- ---------------------------------------------------------------------------
describe("META-01: zero-rate edge cases (RESEARCH §5.3)", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  it("META-01: single 0% rate in groupedVatAmounts with value 0 — suppress (no MwSt line)", function()
    local p = {
      purchaseUUID1  = "meta01-zero-only-uuid",
      amount         = 500,
      vatAmount      = 0,
      currency       = "EUR",
      timestamp      = "2026-05-15T10:30:00Z",
      purchaseNumber = 2001,
      payments       = {},
      groupedVatAmounts = { ["0.0"] = 0 },
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    assert.is_nil(txn.purpose:find("MwSt", 1, true),
      "MwSt line must be suppressed when sole entry is 0% with value 0, got:\n" .. txn.purpose)
  end)

  it("META-01: 0% rate alongside 19% — show both per-rate lines including zero, 19 before 0", function()
    local p = {
      purchaseUUID1  = "meta01-zero-plus-19-uuid",
      amount         = 1995,
      vatAmount      = 318,
      currency       = "EUR",
      timestamp      = "2026-05-15T10:30:00Z",
      purchaseNumber = 2002,
      payments       = {},
      groupedVatAmounts = { ["0.0"] = 0, ["19.0"] = 318 },
    }
    local txn = M_mapping.purchase_to_transaction(p)
    assert.is_table(txn, "purchase_to_transaction must return a table")
    local pos19  = txn.purpose:find("19% MwSt: 3,18 EUR", 1, true)
    local pos0   = txn.purpose:find("0% MwSt: 0,00 EUR",  1, true)
    assert.is_truthy(pos19, "missing '19% MwSt: 3,18 EUR' in purpose:\n" .. txn.purpose)
    assert.is_truthy(pos0,  "missing '0% MwSt: 0,00 EUR' in purpose:\n"  .. txn.purpose)
    assert.is_true(pos19 < pos0,
      "19% MwSt line must precede 0% MwSt line (descending sort), got:\n" .. txn.purpose)
  end)

end)
