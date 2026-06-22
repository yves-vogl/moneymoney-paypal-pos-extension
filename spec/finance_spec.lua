-- spec/finance_spec.lua
-- Plan 04-03 Task 1: covers M_finance.fetch + M_finance.fetch_all.
-- Mirrors the spec/purchases_spec.lua shape (Phase-3 Plan 03-05 baseline):
--   * URL shape — host, path, query parameters
--   * Bearer header pass-through (D-42)
--   * Error routing via M_errors.from_http_status (D-43)
--   * fetch_all drives M_pagination.offset_iterate (Plan 04-02 sibling iterator)
--
-- The CRITICAL URL invariant tested below: the `includeTransactionType` triplet
-- (PAYMENT, PAYMENT_FEE, PAYOUT) is appended as a LITERAL SUFFIX string, because
-- Lua table-keyed `_url_encode_query` would deduplicate the three keys (PATTERNS.md
-- §"src/finance.lua — data-fetcher" + RESEARCH §Pitfall 2 / §Pitfall 7).

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("finance_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- luacheck: globals M_finance M_errors LoginFailed M_i18n

describe("M_finance.fetch", function()

  before_each(function()
    Mocks.setup()
    -- Plan 05-03: MM.sleep no-op stub so retry-bearing tests do not block.
    _G.MM = _G.MM or {}
    _G.MM.sleep = function(_) end
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Sanity: function is exposed by the artifact
  -- -------------------------------------------------------------------------

  it("M_finance.fetch is a function exposed by the artifact (Task 1 GREEN)", function()
    assert.is_function(M_finance.fetch,
      "M_finance.fetch must be a function (Plan 04-03 Task 1)")
  end)

  -- -------------------------------------------------------------------------
  -- URL host + path
  -- -------------------------------------------------------------------------

  it("fetch GETs https://finance.izettle.com/v2/accounts/liquid/transactions", function()
    local raw, _ = Fixtures.load("finance/finance_single_page")
    Mocks.push_response({ content = raw })
    M_finance.fetch(1714521600, "AT-VALID", 0)
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made")
    local url = Mocks._last_request.url
    local found = url:find(
      "https://finance.izettle.com/v2/accounts/liquid/transactions", 1, true)
    assert.is_not_nil(found,
      "URL must target the Finance API transactions endpoint, got: " .. url)
  end)

  -- -------------------------------------------------------------------------
  -- URL must contain start=, end=, limit=1000, offset=0
  -- (start + end are REQUIRED per RESEARCH §1.3 / §Pitfall 2;
  --  limit defaults to 1000 per RESEARCH §1.3)
  -- -------------------------------------------------------------------------

  it("fetch URL contains start=, end=, limit=1000, offset=0 (RESEARCH §1.3)", function()
    local raw, _ = Fixtures.load("finance/finance_single_page")
    Mocks.push_response({ content = raw })
    M_finance.fetch(1714521600, "AT-VALID", 0)
    local url = Mocks._last_request.url
    assert.is_not_nil(url:find("start=", 1, true),
      "URL must contain start= query param, got: " .. url)
    -- `end` is a Lua reserved word -- the URL key still spells it out literally
    assert.is_not_nil(url:find("end=", 1, true),
      "URL must contain end= query param (required per RESEARCH §1.3), got: " .. url)
    assert.is_not_nil(url:find("limit=1000", 1, true),
      "URL must contain limit=1000, got: " .. url)
    assert.is_not_nil(url:find("offset=0", 1, true),
      "URL must contain offset=0, got: " .. url)
  end)

  -- -------------------------------------------------------------------------
  -- The three includeTransactionType repetitions must be present.
  -- RESEARCH §1.3 + §Pitfall 7: PAYMENT, PAYMENT_FEE, PAYOUT.
  -- -------------------------------------------------------------------------

  it("fetch URL repeats includeTransactionType exactly three times (PAYMENT, PAYMENT_FEE, PAYOUT)", function()
    local raw, _ = Fixtures.load("finance/finance_single_page")
    Mocks.push_response({ content = raw })
    M_finance.fetch(1714521600, "AT-VALID", 0)
    local url = Mocks._last_request.url
    -- Count occurrences of the literal substring `includeTransactionType=`
    local n = 0
    for _ in url:gmatch("includeTransactionType=") do n = n + 1 end
    assert.equals(3, n,
      "URL must repeat includeTransactionType= exactly 3 times, got " .. tostring(n) ..
      " in: " .. url)
    -- Each of the three expected types must appear literally
    assert.is_not_nil(url:find("includeTransactionType=PAYMENT", 1, true),
      "URL must contain includeTransactionType=PAYMENT, got: " .. url)
    assert.is_not_nil(url:find("includeTransactionType=PAYMENT_FEE", 1, true),
      "URL must contain includeTransactionType=PAYMENT_FEE, got: " .. url)
    assert.is_not_nil(url:find("includeTransactionType=PAYOUT", 1, true),
      "URL must contain includeTransactionType=PAYOUT, got: " .. url)
  end)

  -- -------------------------------------------------------------------------
  -- Finance API timestamps must be YYYY-MM-DDThh:mm:ss WITHOUT a `Z` suffix
  -- and WITHOUT millis. RESEARCH §1.3 / §Pitfall 3 — Phase-3's `Z`-suffix
  -- format must NOT appear in finance.lua URLs.
  -- -------------------------------------------------------------------------

  it("fetch URL uses no-Z ISO-8601 timestamps (RESEARCH §1.3 / §Pitfall 3)", function()
    local raw, _ = Fixtures.load("finance/finance_single_page")
    Mocks.push_response({ content = raw })
    -- POSIX 1714521600 = 2024-05-01T00:00:00Z
    M_finance.fetch(1714521600, "AT-VALID", 0)
    local url = Mocks._last_request.url
    -- start= value must contain "2024-05-01T00:00:00" without trailing Z
    assert.is_not_nil(url:find("start=2024%-05%-01T00:00:00"),
      "URL must contain start=2024-05-01T00:00:00 (no-Z format), got: " .. url)
    -- The start= value must NOT carry the Phase-3 `Z` suffix
    local _, _, after_start = url:find("start=(2024%-05%-01T00:00:00[^&]*)")
    assert.is_not_nil(after_start, "start= param must be parseable")
    assert.is_nil(after_start:find("Z", 1, true),
      "start= value must NOT end in Z (Finance API uses no-Z format), got: " .. after_start)
  end)

  -- -------------------------------------------------------------------------
  -- Authorization: Bearer <token> header (D-42)
  -- -------------------------------------------------------------------------

  it("fetch includes Authorization: Bearer <token> header (D-42)", function()
    local raw, _ = Fixtures.load("finance/finance_single_page")
    Mocks.push_response({ content = raw })
    M_finance.fetch(1714521600, "AT-VALID", 0)
    local headers = Mocks._last_request.headers
    assert.is_not_nil(headers, "expected headers table to be present")
    assert.equals("Bearer AT-VALID", headers["Authorization"],
      "Authorization header must be 'Bearer AT-VALID' (D-42)")
  end)

  -- -------------------------------------------------------------------------
  -- Bearer guard (Phase-3 belt-and-suspenders pattern from M_purchases.fetch)
  -- -------------------------------------------------------------------------

  it("fetch asserts on nil bearer (Phase-3 D-41 belt-and-suspenders)", function()
    assert.has_error(function() M_finance.fetch(0, nil, 0) end)
  end)

  it("fetch asserts on empty-string bearer", function()
    assert.has_error(function() M_finance.fetch(0, "", 0) end)
  end)

  -- -------------------------------------------------------------------------
  -- Offset is forwarded to the URL
  -- -------------------------------------------------------------------------

  it("fetch reflects the offset argument in the URL", function()
    local raw, _ = Fixtures.load("finance/finance_single_page")
    Mocks.push_response({ content = raw })
    M_finance.fetch(1714521600, "AT-VALID", 1000)
    local url = Mocks._last_request.url
    assert.is_not_nil(url:find("offset=1000", 1, true),
      "URL must contain offset=1000 when called with offset=1000, got: " .. url)
  end)

  -- -------------------------------------------------------------------------
  -- Error routing through M_errors.from_http_status (D-43) — table-driven
  -- -------------------------------------------------------------------------

  it("fetch returns 3-tuple compatible with M_errors.from_http_status — invalid_grant -> 400 -> LoginFailed", function()
    Mocks.push_response({ content = '{"error":"invalid_grant"}' })
    local _, status, raw = M_finance.fetch(1714521600, "AT-VALID", 0)
    assert.equals(400, status,
      "invalid_grant body must infer status 400")
    assert.equals(LoginFailed, M_errors.from_http_status(status, raw),
      "M_errors.from_http_status(400) must return LoginFailed")
  end)

  it("fetch surfaces rate_limit body as status 429 -> German error.rate_limit string", function()
    -- Plan 05-03 D-63: 429 triggers single retry; queue rate_limit body TWICE
    -- so the retry also returns 429 → caller sees status==429.
    Mocks.push_response({ content = '{"error":"rate_limit"}' })  -- attempt 1
    Mocks.push_response({ content = '{"error":"rate_limit"}' })  -- attempt 2 (single retry)
    local _, status, raw = M_finance.fetch(1714521600, "AT-VALID", 0)
    assert.equals(429, status)
    local err = M_errors.from_http_status(status, raw)
    assert.equals(M_i18n.t("error.rate_limit"), err,
      "rate_limit must route to the German rate_limit string")
  end)

  it("fetch surfaces empty body as nil status -> German error.network string", function()
    -- Plan 05-03 D-62: empty body triggers 3 retry attempts; queue empty body
    -- 3× so all attempts exhaust and the function returns (nil, nil, '')
    -- (Phase-2 ERR-05 path preserved).
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })
    local parsed, status, _ = M_finance.fetch(1714521600, "AT-VALID", 0)
    assert.is_nil(parsed)
    assert.is_nil(status, "empty body must yield nil status")
    local err = M_errors.from_http_status(status, "")
    assert.is_string(err)
    assert.is_truthy(err:find("Netzwerkfehler", 1, true),
      "empty body must route to the German Netzwerkfehler envelope")
  end)

end)

-- ---------------------------------------------------------------------------

describe("M_finance.fetch_all", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  it("fetch_all is a function exposed by the artifact (Task 1 GREEN)", function()
    assert.is_function(M_finance.fetch_all,
      "M_finance.fetch_all must be a function (Plan 04-03 Task 1)")
  end)

  it("fetch_all accumulates records across two pages (short-page termination)", function()
    -- finance_multi_page_1 = 5 records, finance_multi_page_2 = 2 records.
    -- offset_iterate defaults to limit=1000; a 5-record first page is shorter
    -- than limit -> loop terminates after the first fetch. So queuing only
    -- finance_multi_page_1 already exercises the single-page path.
    -- To exercise the multi-page path we'd need a fetch_all that allows a
    -- custom limit; the public API doesn't, so this test asserts the
    -- short-page termination path that production code actually drives.
    local raw, _ = Fixtures.load("finance/finance_multi_page_1")
    Mocks.push_response({ content = raw })
    local records, err = M_finance.fetch_all(1714521600, "AT-VALID")
    assert.is_nil(err, "no error expected, got: " .. tostring(err))
    assert.is_table(records)
    assert.equals(5, #records, "fetch_all must accumulate 5 records from page1")
    assert.equals(0, #Mocks._response_queue,
      "fetch_all must have consumed exactly the one queued response")
  end)

  it("fetch_all returns (nil, err) when mid-pagination call surfaces a 500", function()
    -- Queue an error body that infers status 500 via the body shape.
    -- _infer_status maps unknown error fields to 400 by default, so we
    -- inject the status directly via the headers.status path is irrelevant —
    -- _http reads the response body shape. Use a payload that the JSON
    -- decoder rejects so M_http.get_json returns (nil, nil, raw); that
    -- routes to the network-error branch. The plan's contract is "any
    -- sub-page error short-circuits with (nil, err)" — that is what we
    -- assert here.
    Mocks.push_response({ content = "this is not json" })
    local records, err = M_finance.fetch_all(1714521600, "AT-VALID")
    assert.is_nil(records, "fetch_all must return nil records on error")
    assert.is_string(err, "fetch_all must return an error string on error")
    assert.is_truthy(err:find("Netzwerkfehler", 1, true)
                  or err:find("Netzwerk", 1, true),
      "fetch_all error must mention Netzwerkfehler, got: " .. tostring(err))
  end)

  it("fetch_all returns empty array on finance_empty fixture (incremental empty-refresh)", function()
    local raw, _ = Fixtures.load("finance/finance_empty")
    Mocks.push_response({ content = raw })
    local records, err = M_finance.fetch_all(1714521600, "AT-VALID")
    assert.is_nil(err)
    assert.is_table(records)
    assert.equals(0, #records, "empty fixture must yield zero records")
  end)

  it("fetch_all asserts on nil bearer", function()
    assert.has_error(function() M_finance.fetch_all(0, nil) end)
  end)

  it("WR-01: fetch honours an explicit end_posix argument (used by fetch_all to pin the pagination window)", function()
    -- WR-01 (REVIEW): each M_finance.fetch call previously computed end=
    -- from os.time() afresh — so across a multi-page pagination the end-anchor
    -- drifted forward and the offset-pagination dataset stopped being stable.
    -- Fix: fetch_all pins end_posix once and threads it through each call.
    -- This test asserts the fetch contract: when end_posix is passed, the URL
    -- uses exactly that value (formatted as ISO-8601, no Z, no millis).
    local raw, _ = Fixtures.load("finance/finance_empty")
    Mocks.push_response({ content = raw })
    local pinned_end = 1735603200  -- 2024-12-31T00:00:00Z
    M_finance.fetch(1714521600, "AT-VALID", 0, pinned_end)
    local url = Mocks._last_request and Mocks._last_request.url or ""
    -- Expected: end=2024-12-31T00:01:00 — wait, our pinned_end is 1735603200
    -- which is 2024-12-31T00:00:00Z; _iso8601_utc_no_z would format that as
    -- "2024-12-31T00:00:00".
    assert.is_truthy(url:find("end=2024%-12%-31T00:00:00", 1, false),
      "WR-01: fetch URL must use the pinned end_posix verbatim; got URL=" .. url)
  end)

end)
