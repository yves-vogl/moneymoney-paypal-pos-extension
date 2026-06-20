-- spec/pagination_spec.lua
-- Pending scaffold for M_pagination (Phase 3, Wave 3, Plan 03-04).
-- Covers: iterate cursor termination (SALE-06), MAX_PAGES guard, empty-array
-- and missing-hash termination paths (RESEARCH §2a Pitfall 1), error routing.
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so each test
-- starts with a clean global environment (pattern from spec/http_spec.lua L37-44).

local Mocks = require("spec.helpers.mm_mocks")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("pagination_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("M_pagination", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Sanity test (non-pending) — confirm artifact loads and M_pagination is present
  -- -------------------------------------------------------------------------

  it("M_pagination module table is exposed", function()
    assert.is_table(M_pagination)
  end)

  -- -------------------------------------------------------------------------
  -- Pending tests — Wave 3 (Plan 03-04) fills these bodies
  -- -------------------------------------------------------------------------

  pending("iterate accumulates purchases across two pages until empty (SALE-06)", function() end)

  pending("iterate terminates immediately on empty purchases[] array (RESEARCH §2a Pitfall 1)", function() end)

  pending("iterate terminates when lastPurchaseHash is absent on a non-empty page (defensive)", function() end)

  pending("iterate updates params.lastPurchaseHash between pages (cursor handoff)", function() end)

  pending("iterate aborts on MAX_PAGES guard and logs a warning", function() end)

  pending("iterate routes HTTP error via M_errors.from_http_status", function() end)

  pending("iterate returns error string when page shape is invalid", function() end)

end)
