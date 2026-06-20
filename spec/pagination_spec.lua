-- spec/pagination_spec.lua
-- Covers: M_pagination.iterate cursor termination (SALE-06), MAX_PAGES guard,
-- empty-array and missing-hash termination paths (RESEARCH §2a Pitfall 1),
-- error routing, cursor handoff, and a fixture-driven smoke test.
--
-- All tests use inline fetch_fn closures — M_pagination.iterate is pure
-- orchestration with no HTTP surface, so no Mocks.push_response is needed.
-- The smoke test (Test 8) loads real JSON fixtures via Fixtures.load to verify
-- the cursor loop threads real page data correctly.
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so each test
-- starts with a clean global environment (pattern from spec/http_spec.lua L37-44).

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

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
  -- Test 1: Two-page accumulation — primary SALE-06 scenario
  -- -------------------------------------------------------------------------

  it("iterate accumulates purchases across two pages until empty (SALE-06)", function()
    local pages = {
      { purchases = { { purchaseUUID1 = "aaa" } }, lastPurchaseHash = "hash-1" },
      { purchases = { { purchaseUUID1 = "bbb" } }, lastPurchaseHash = "hash-2" },
      { purchases = {} },
    }
    local call_index = 0
    local function fetch_fn(_params) -- luacheck: ignore 431
      call_index = call_index + 1
      return pages[call_index], 200, "{}"
    end

    local all, err = M_pagination.iterate(fetch_fn, { limit = 200 })

    assert.is_nil(err, "expected no error from two-page accumulation")
    assert.equals(2, #all, "expected 2 purchases accumulated across two pages")
    assert.equals("aaa", all[1].purchaseUUID1, "first purchase UUID mismatch")
    assert.equals("bbb", all[2].purchaseUUID1, "second purchase UUID mismatch")
  end)

  -- -------------------------------------------------------------------------
  -- Test 2: Empty array terminates even when cursor is present (RESEARCH §2a Pitfall 1)
  -- -------------------------------------------------------------------------

  it("iterate terminates immediately on empty purchases[] array (RESEARCH §2a Pitfall 1)", function()
    -- Cursor is present but purchases array is empty — empty array wins (Anti-Pattern #1).
    local pages = {
      { purchases = {}, lastPurchaseHash = "hash-x" },
    }
    local call_index = 0
    local function fetch_fn(_params) -- luacheck: ignore 431
      call_index = call_index + 1
      return pages[call_index], 200, "{}"
    end

    local all, err = M_pagination.iterate(fetch_fn, {})

    assert.is_nil(err, "expected no error when terminating on empty array")
    assert.equals(0, #all, "expected zero purchases when first page is empty")
    assert.equals(1, call_index, "expected exactly one fetch call")
  end)

  -- -------------------------------------------------------------------------
  -- Test 3: Missing lastPurchaseHash on non-empty page terminates (defensive)
  -- -------------------------------------------------------------------------

  it("iterate terminates when lastPurchaseHash is absent on a non-empty page (defensive)", function()
    -- Page has purchases but no cursor — belt-and-suspenders termination.
    local pages = {
      { purchases = { { purchaseUUID1 = "cc" } } },
    }
    local call_index = 0
    local function fetch_fn(_params) -- luacheck: ignore 431
      call_index = call_index + 1
      return pages[call_index], 200, "{}"
    end

    local all, err = M_pagination.iterate(fetch_fn, {})

    assert.is_nil(err, "expected no error when cursor is absent on non-empty page")
    assert.equals(1, #all, "expected 1 purchase from the single non-empty page")
    assert.equals("cc", all[1].purchaseUUID1, "purchase UUID mismatch")
    assert.equals(1, call_index, "expected exactly one fetch call")
  end)

  -- -------------------------------------------------------------------------
  -- Test 4: Cursor is forwarded to next page correctly
  -- -------------------------------------------------------------------------

  it("iterate updates params.lastPurchaseHash between pages (cursor handoff)", function()
    -- Record the lastPurchaseHash seen by each call BEFORE returning the page.
    local seen_params = {}
    local pages = {
      { purchases = { { purchaseUUID1 = "aa" } }, lastPurchaseHash = "hash-1" },
      { purchases = { { purchaseUUID1 = "bb" } }, lastPurchaseHash = "hash-2" },
      { purchases = {} },
    }
    local call_index = 0
    local function fetch_fn(params)
      call_index = call_index + 1
      seen_params[call_index] = params.lastPurchaseHash
      return pages[call_index], 200, "{}"
    end

    local all, err = M_pagination.iterate(fetch_fn, { limit = 200 })

    assert.is_nil(err, "expected no error in cursor handoff test")
    assert.equals(2, #all, "expected 2 purchases accumulated")
    -- First call receives no cursor (fresh start — initial_params has no lastPurchaseHash)
    assert.is_nil(seen_params[1], "first call must receive nil cursor")
    -- Second call receives the cursor from page 1
    assert.equals("hash-1", seen_params[2], "second call must receive cursor from page 1")
  end)

  -- -------------------------------------------------------------------------
  -- Test 5: MAX_PAGES guard aborts and returns error
  -- -------------------------------------------------------------------------

  it("iterate aborts on MAX_PAGES guard and logs a warning", function()
    -- Infinite-loop simulation: every page returns a record + cursor that never ends.
    local function fetch_fn(_params) -- luacheck: ignore 431
      return { purchases = { { purchaseUUID1 = "x" } }, lastPurchaseHash = "never-stops" }, 200, "{}"
    end

    local all, err = M_pagination.iterate(fetch_fn, {})

    assert.is_nil(all, "expected nil purchases on MAX_PAGES abort")
    assert.is_string(err, "expected an error string on MAX_PAGES abort")
    assert.truthy(err:find("max_pages", 1, true),
      "error string must contain 'max_pages' placeholder, got: " .. tostring(err))
  end)

  -- -------------------------------------------------------------------------
  -- Test 6: HTTP error is routed through M_errors.from_http_status
  -- -------------------------------------------------------------------------

  it("iterate routes HTTP error via M_errors.from_http_status", function()
    -- nil status simulates a network failure; from_http_status returns error.network.
    local function fetch_fn(_params) -- luacheck: ignore 431
      return nil, nil, ""
    end

    local all, err = M_pagination.iterate(fetch_fn, {})

    assert.is_nil(all, "expected nil purchases on HTTP error")
    assert.is_string(err, "expected an error string on HTTP error")
    -- Matches the exact error.network output for nil status ("—" placeholder).
    assert.equals(M_i18n.t("error.network", "—"), err,
      "error string must match M_i18n.t('error.network', '—')")
  end)

  -- -------------------------------------------------------------------------
  -- Test 7: Invalid page shape returns error.network bad_page
  -- -------------------------------------------------------------------------

  it("iterate returns error string when page shape is invalid", function()
    -- Page table exists but has no 'purchases' field — invalid shape.
    local function fetch_fn(_params) -- luacheck: ignore 431
      return {}, 200, "{}"
    end

    local all, err = M_pagination.iterate(fetch_fn, {})

    assert.is_nil(all, "expected nil purchases on invalid page shape")
    assert.is_string(err, "expected an error string on invalid page shape")
    assert.truthy(err:find("bad_page", 1, true),
      "error string must contain 'bad_page' placeholder, got: " .. tostring(err))
  end)

  -- -------------------------------------------------------------------------
  -- Test 8 (Smoke): Fixture-driven two-page traversal
  -- -------------------------------------------------------------------------

  it("iterate accumulates fixture-driven pages from purchase_page1 + purchase_page2", function()
    -- purchase_page1.json: 1 purchase + lastPurchaseHash present
    -- purchase_page2.json: empty purchases array (terminal)
    local _, page1 = Fixtures.load("purchases/purchase_page1")
    local _, page2 = Fixtures.load("purchases/purchase_page2")

    local fixture_pages = { page1, page2 }
    local call_index = 0
    local function fetch_fn(_params) -- luacheck: ignore 431
      call_index = call_index + 1
      return fixture_pages[call_index], 200, "{}"
    end

    local all, err = M_pagination.iterate(fetch_fn, { limit = 200 })

    assert.is_nil(err, "expected no error from fixture-driven two-page traversal")
    assert.equals(1, #all,
      "expected 1 purchase total (page1 has 1 record, page2 is empty/terminal)")
    assert.equals("44444444-4444-4444-4444-444444444444", all[1].purchaseUUID1,
      "purchase UUID from page1 fixture must be preserved")
    assert.equals(2, call_index, "expected exactly two fetch calls (page1 + page2)")
  end)

end)
