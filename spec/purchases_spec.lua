-- spec/purchases_spec.lua
-- Unit tests for M_purchases (Phase 3, Wave 3, Plan 03-05).
-- Covers: fetch URL shape (host allowlist, startDate query param, limit,
-- descending, lastPurchaseHash), Bearer header pass-through (D-42),
-- error routing via M_errors.from_http_status (D-43), fetch_all driving
-- M_pagination.iterate (or fallback _inline_iterate in parallel-plan window).
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so each test
-- starts with a clean global environment (pattern from spec/http_spec.lua L37-44).

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

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
  -- Sanity test (non-pending) -- confirm artifact loads and M_purchases is present
  -- -------------------------------------------------------------------------

  it("M_purchases module table is exposed", function()
    assert.is_table(M_purchases)
  end)

  -- -------------------------------------------------------------------------
  -- Test 1: Host allowlist -- URL must target purchase.izettle.com
  -- -------------------------------------------------------------------------

  it("fetch GETs https://purchase.izettle.com/purchases/v2 (host allowlist)", function()
    Mocks.push_response({ content = "{}" })
    M_purchases.fetch(1700000000, "AT-VALID", nil)
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made")
    local url = Mocks._last_request.url
    -- URL must start with the Purchase API base (egress allowlist T-03-W3b-03 / D-26)
    local found = url:find("https://purchase.izettle.com/purchases/v2", 1, true)
    assert.is_not_nil(found,
      "URL must begin with https://purchase.izettle.com/purchases/v2, got: " .. url)
  end)

  -- -------------------------------------------------------------------------
  -- Test 2: Authorization header must carry Bearer token (D-42 / T-03-W3b-01)
  -- -------------------------------------------------------------------------

  it("fetch includes Authorization: Bearer <token> header (D-42)", function()
    Mocks.push_response({ content = "{}" })
    M_purchases.fetch(1700000000, "AT-VALID", nil)
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made")
    local headers = Mocks._last_request.headers
    assert.is_not_nil(headers, "expected headers table to be present")
    assert.equals("Bearer AT-VALID", headers["Authorization"],
      "Authorization header must be 'Bearer AT-VALID'")
  end)

  -- -------------------------------------------------------------------------
  -- Test 3: startDate query param -- UTC ISO-8601 of clamped_since (SALE-06 / D-33)
  -- -------------------------------------------------------------------------

  it("fetch includes startDate query param formatted as UTC ISO-8601 (SALE-06 / D-33)", function()
    -- POSIX 1700000000 = 2023-11-14T22:13:20Z (UTC)
    -- After MM.urlencode: colons become %3A -> startDate=2023-11-14T22%3A13%3A20Z
    Mocks.push_response({ content = "{}" })
    M_purchases.fetch(1700000000, "AT-VALID", nil)
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made")
    local url = Mocks._last_request.url

    -- startDate query param must be present
    assert.is_not_nil(url:find("startDate=", 1, true),
      "URL must include startDate param, got: " .. url)

    -- Year 2023 must appear in the encoded date
    assert.is_not_nil(url:find("2023", 1, true),
      "URL startDate must contain year 2023, got: " .. url)

    -- Colons must be percent-encoded (%3A) as part of the ISO-8601 time component
    -- plain=true: search for the literal string "%3A" (one percent sign + 3A)
    assert.is_not_nil(url:find("%3A", 1, true),
      "URL startDate must URL-encode colons as %3A, got: " .. url)

    -- Full encoded date must be present as a plain substring
    assert.is_not_nil(url:find("2023-11-14T22%3A13%3A20Z", 1, true),
      "URL startDate must equal encoded 2023-11-14T22%3A13%3A20Z, got: " .. url)
  end)

  -- -------------------------------------------------------------------------
  -- Test 4: limit=200 must appear in the query string (RESEARCH §1 / A1)
  -- -------------------------------------------------------------------------

  it("fetch includes limit=200 query param (RESEARCH §1 / A1)", function()
    Mocks.push_response({ content = "{}" })
    M_purchases.fetch(1700000000, "AT-VALID", nil)
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made")
    local url = Mocks._last_request.url
    assert.is_not_nil(url:find("limit=200", 1, true),
      "URL must include limit=200, got: " .. url)
  end)

  -- -------------------------------------------------------------------------
  -- Test 5: descending=false must appear in the query string (RESEARCH §1)
  -- -------------------------------------------------------------------------

  it("fetch includes descending=false query param (RESEARCH §1)", function()
    Mocks.push_response({ content = "{}" })
    M_purchases.fetch(1700000000, "AT-VALID", nil)
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made")
    local url = Mocks._last_request.url
    assert.is_not_nil(url:find("descending=false", 1, true),
      "URL must include descending=false, got: " .. url)
  end)

  -- -------------------------------------------------------------------------
  -- Test 6: lastPurchaseHash present with cursor, absent without cursor
  -- -------------------------------------------------------------------------

  it("fetch includes lastPurchaseHash query param when continuing pagination (RESEARCH §2a)", function()
    -- Sub-case A: cursor provided -> lastPurchaseHash must appear in URL
    Mocks.push_response({ content = "{}" })
    M_purchases.fetch(1700000000, "AT-VALID", "hash-from-prev-page")
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made (with cursor)")
    local url_with_cursor = Mocks._last_request.url
    -- Lua pattern: escape hyphen with %- so it matches the literal '-'
    assert.is_not_nil(url_with_cursor:find("lastPurchaseHash=hash%-from%-prev%-page", 1, false),
      "URL must contain lastPurchaseHash=hash-from-prev-page when cursor is provided, got: "
        .. url_with_cursor)

    -- Sub-case B: cursor is nil -> lastPurchaseHash must NOT appear in URL
    Mocks.push_response({ content = "{}" })
    M_purchases.fetch(1700000000, "AT-VALID", nil)
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made (without cursor)")
    local url_no_cursor = Mocks._last_request.url
    assert.is_nil(url_no_cursor:find("lastPurchaseHash", 1, true),
      "URL must NOT contain lastPurchaseHash when cursor is nil, got: " .. url_no_cursor)
  end)

  -- -------------------------------------------------------------------------
  -- Test 7: HTTP error body -> 3-tuple status reflects M_http._infer_status (D-43)
  -- -------------------------------------------------------------------------

  it("fetch routes error via M_errors.from_http_status (D-43)", function()
    -- Push a body that M_http._infer_status maps to status 400
    -- (invalid_grant -> 400 per M_http._infer_status contract)
    Mocks.push_response({ content = '{"error":"invalid_grant"}' })
    local parsed, status, raw = M_purchases.fetch(1700000000, "AT-VALID", nil) -- luacheck: ignore 211
    -- The 3-tuple is returned verbatim from M_http.get_json (D-43)
    assert.equals(400, status,
      "status must be 400 for invalid_grant error body (M_http._infer_status contract)")
    -- parsed table is still returned (the JSON body was decodable)
    assert.is_table(parsed, "parsed must be a table when JSON body is valid")
    assert.equals("invalid_grant", parsed.error,
      "parsed.error must equal 'invalid_grant'")
    -- M_errors.from_http_status(400, raw) would return LoginFailed -- verify the
    -- routing path works by calling it directly on the returned status
    local err = M_errors.from_http_status(status, raw)
    assert.equals(LoginFailed, err,
      "M_errors.from_http_status(400) must return LoginFailed")
  end)

  -- -------------------------------------------------------------------------
  -- Test 8: fetch_all drives pagination across two pages
  -- -------------------------------------------------------------------------

  it("fetch_all drives M_pagination.iterate with fetch as the fetch_page_fn", function()
    -- Queue page1 (1 purchase + lastPurchaseHash) then page2 (empty, terminal).
    -- fetch_all must accumulate all purchases across both pages.
    local raw_page1 = Fixtures.load("purchases/purchase_page1")
    local raw_page2 = Fixtures.load("purchases/purchase_page2")
    Mocks.push_response({ content = raw_page1 })
    Mocks.push_response({ content = raw_page2 })

    local all, err = M_purchases.fetch_all(1700000000, "AT-VALID")

    assert.is_nil(err,
      "fetch_all must not return an error for valid fixture pages: " .. tostring(err))
    assert.is_table(all, "fetch_all must return a purchases table")
    -- page1 has 1 purchase with lastPurchaseHash; page2 is empty (terminal) -> total = 1
    assert.equals(1, #all,
      "fetch_all must accumulate exactly 1 purchase from page1+page2 iteration")
    -- purchaseUUID1 from purchase_page1.json
    assert.equals("44444444-4444-4444-4444-444444444444", all[1].purchaseUUID1,
      "fetch_all must return the purchase from page1 with correct UUID")
    -- Both queued responses must have been consumed
    assert.equals(0, #Mocks._response_queue,
      "both queued responses must have been consumed by fetch_all iteration")
  end)

  -- -------------------------------------------------------------------------
  -- Test 9: fetch_all returns empty array on empty response (SALE-06 empty refresh)
  -- -------------------------------------------------------------------------

  it("fetch_all returns empty array on purchases_empty fixture (SALE-06 incremental empty-refresh)", function()
    local raw_empty = Fixtures.load("purchases/purchases_empty")
    Mocks.push_response({ content = raw_empty })

    local all, err = M_purchases.fetch_all(1700000000, "AT-VALID")

    assert.is_nil(err,
      "fetch_all must not return error on empty fixture: " .. tostring(err))
    assert.is_table(all,
      "fetch_all must return a table even when purchases list is empty")
    assert.equals(0, #all,
      "fetch_all must return zero purchases when response is empty")
  end)

end)
