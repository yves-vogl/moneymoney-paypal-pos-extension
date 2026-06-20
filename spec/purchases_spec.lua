-- spec/purchases_spec.lua
-- Pending scaffold for M_purchases (Phase 3, Wave 3, Plan 03-05).
-- Covers: fetch URL shape (host allowlist, startDate query param, limit,
-- descending, lastPurchaseHash), Bearer header pass-through (D-42),
-- error routing via M_errors.from_http_status (D-43), fetch_all driving
-- M_pagination.iterate.
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so each test
-- starts with a clean global environment (pattern from spec/http_spec.lua L37-44).

local Mocks = require("spec.helpers.mm_mocks")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("purchases_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("M_purchases", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Sanity test (non-pending) — confirm artifact loads and M_purchases is present
  -- -------------------------------------------------------------------------

  it("M_purchases module table is exposed", function()
    assert.is_table(M_purchases)
  end)

  -- -------------------------------------------------------------------------
  -- Pending tests — Wave 3 (Plan 03-05) fills these bodies
  -- -------------------------------------------------------------------------

  pending("fetch GETs https://purchase.izettle.com/purchases/v2 (host allowlist)", function() end)

  pending("fetch includes Authorization: Bearer <token> header (D-42)", function() end)

  pending("fetch includes startDate query param formatted as UTC ISO-8601 (SALE-06 / D-33)", function() end)

  pending("fetch includes limit=200 query param (RESEARCH §1 / A1)", function() end)

  pending("fetch includes descending=false query param (RESEARCH §1)", function() end)

  pending("fetch includes lastPurchaseHash query param when continuing pagination (RESEARCH §2a)", function() end)

  pending("fetch routes error via M_errors.from_http_status (D-43)", function() end)

  pending("fetch_all drives M_pagination.iterate with fetch as the fetch_page_fn", function() end)

end)
