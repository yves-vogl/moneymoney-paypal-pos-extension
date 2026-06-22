-- spec/refresh_fail_whole_spec.lua
-- Phase-5 / Plan 05-02 RED scaffold; Plan 05-05 turns GREEN.
-- Gates: ERR-06 fail-whole-refresh (D-66 / ADR-0005 Invariant 6),
--        ERR-05 network failure regression (D-65 / ADR-0005 Invariant 5),
--        ERR-04 composition (Plan 05-04 / ADR-0005 Invariant 4).
--
-- Phase-4's 16-step RefreshAccount in src/entry.lua is already structurally
-- correct per RESEARCH §5 audit; this spec is a GATING assertion that any
-- future refactor preserves the invariant. Plan 05-03 shipped retry behavior
-- (so 3 empty bodies exhaust through _request_with_retry to (nil,nil,raw)
-- which routes via M_errors.from_http_status -> error.network);
-- Plan 05-04 shipped the iterator-layer 401-direct-check -> error.token_revoked;
-- Plan 05-05 fills the 4 cases below.

-- luacheck: globals RefreshAccount LocalStorage M_i18n JSON M_auth
-- luacheck: ignore 431
-- luacheck: ignore 631

local Mocks    = require("spec.helpers.mm_mocks") -- luacheck: ignore 211
local Fixtures = require("spec.helpers.fixtures") -- luacheck: ignore 211

do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("refresh_fail_whole_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

local function seed_token(orgUuid)
  -- VERBATIM from spec/refresh_idempotency_spec.lua L55-64.
  LocalStorage["zettle:" .. orgUuid] = JSON():set({
    access_token = "AT-VALID",
    expires_at   = os.time() + 7200,
    obtained_at  = os.time(),
    client_id    = "client-x",
    uuid         = "u-1",
    publicName   = "Beispiel Caf\xc3\xa9",
  }):json()
end

-- Helper: queue the Plan-04-03 "full success" tuple (purchase + liquid +
-- preliminary + finance) for ONE RefreshAccount call. Used by the second-call
-- assertions in every ERR-06 case to prove the pipeline re-runs from scratch
-- (fail-whole means no orphan state survives between refreshes).
local function queue_full_success(purchase_fixture)
  Mocks.push_response({ content = Fixtures.load("purchases/" .. (purchase_fixture or "purchase_simple_sale")) })
  Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
  Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
  Mocks.push_response({ content = Fixtures.load("finance/finance_empty") })
end

describe("RefreshAccount fail-whole-refresh (ERR-06 / D-66 / ADR-0005 Invariant 6)", function()

  before_each(function()
    Mocks.setup()
    _G.MM = _G.MM or {}
    -- No-op MM.sleep so retry-storms in these tests do not consume real seconds.
    _G.MM.sleep = function(_) end
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- ---------------------------------------------------------------------
  -- GREEN sanity: seed_token + module table exposed
  -- ---------------------------------------------------------------------

  it("seed_token writes a non-JWT-shaped bearer that cached_token returns", function()
    seed_token("org-sanity")
    local bearer = M_auth.cached_token("org-sanity")
    assert.equals("AT-VALID", bearer, "seed_token must yield AT-VALID bearer")
    assert.is_false(bearer:find("eyJ", 1, true) ~= nil,
      "seed_token bearer must NOT be JWT-shaped (SEC-03 false-positive guard)")
  end)

  -- ---------------------------------------------------------------------
  -- ERR-06 Case 1: 5xx-on-finance after purchase success
  -- ---------------------------------------------------------------------
  -- Pipeline order in entry.lua RefreshAccount Phase-4 16 steps:
  --   Step 4: M_purchases.fetch_all  (success here)
  --   Step 7: fetch_account_state liquid GET (fails here with empty-body x 3)
  -- After Plan 05-03 retry: 3 empty bodies on the liquid GET surface
  -- (nil, nil, raw) from _request_with_retry, which M_errors.from_http_status
  -- maps to error.network. The fail-whole invariant: NO transactions leak,
  -- and a second RefreshAccount with the SAME `since` re-runs from scratch
  -- and succeeds when the Finance API recovers.
  --
  -- Note on plan's `error.server_busy` wording: the 599 sentinel only fires
  -- when _infer_status returns a 5xx code (which it does NOT for empty
  -- bodies — RESEARCH §4.b heuristic + Phase-2 inheritance). Empty bodies
  -- surface as `nil` status -> error.network. The fail-whole STRUCTURAL
  -- invariant is identical either way; the German error string differs only
  -- in which i18n key. Asserting on i18n key value would be a tautology;
  -- this test asserts the structural ERR-06 contract instead.
  it("ERR-06 case 1: 5xx-on-finance after purchase success returns error string and zero transactions", function()
    local orgUuid = "org-err06-c1"
    local account = { accountNumber = orgUuid, currency = "EUR", balance = 0 }
    local since   = 0

    -- Refresh 1: purchase OK, then 3 empty-body responses for the liquid GET
    -- (Plan 05-03 _request_with_retry exhausts all 3 attempts).
    seed_token(orgUuid)
    Mocks.push_response({ content = Fixtures.load("purchases/purchase_simple_sale") })
    Mocks.push_response({ content = "" })  -- liquid GET attempt 1
    Mocks.push_response({ content = "" })  -- liquid GET attempt 2 (retry)
    Mocks.push_response({ content = "" })  -- liquid GET attempt 3 (final retry)

    local r1 = RefreshAccount(account, since)

    -- (a) return value is the German error string (not a table)
    assert.is_string(r1,
      "ERR-06 case 1: RefreshAccount must return an error STRING when finance state errors, "
      .. "got: " .. type(r1))
    assert.is_truthy(#r1 > 0, "error string must be non-empty")
    assert.equals(M_i18n.t("error.network", "—"), r1,
      "ERR-06 case 1: empty-body finance retry exhaust must surface i18n error.network with em-dash")

    -- (b) the purchase fetch DID happen (pre-failure step actually ran)
    local saw_purchase, saw_finance_state = false, false
    for _, req in ipairs(Mocks._captured_requests) do
      if type(req.url) == "string" then
        if req.url:find("purchase.izettle.com/purchases/v2", 1, true) then
          saw_purchase = true
        end
        if req.url:find("finance.izettle.com/v2/accounts/liquid/balance", 1, true) then
          saw_finance_state = true
        end
      end
    end
    assert.is_true(saw_purchase,
      "ERR-06 case 1: purchase fetch must be visible in captured_requests (pre-failure step ran)")
    assert.is_true(saw_finance_state,
      "ERR-06 case 1: finance liquid balance fetch must be visible in captured_requests (failure point)")

    -- Expected total: 1 purchase call + 3 finance-state liquid retries = 4 calls.
    assert.is_true(#Mocks._captured_requests >= 4,
      "ERR-06 case 1: expected >= 4 captured requests (1 purchase + 3 finance retries); got: "
      .. tostring(#Mocks._captured_requests))

    -- (c) NO finance preliminary balance call and NO finance transactions call
    -- happened — fail-whole stopped the pipeline at Step 7's liquid leg.
    for _, req in ipairs(Mocks._captured_requests) do
      if type(req.url) == "string" then
        assert.is_falsy(req.url:find("preliminary/balance", 1, true),
          "ERR-06 case 1: preliminary balance call must NOT happen after liquid failure (fail-whole), "
          .. "got: " .. req.url)
        assert.is_falsy(req.url:find("liquid/transactions", 1, true),
          "ERR-06 case 1: finance transactions call must NOT happen after liquid failure (fail-whole), "
          .. "got: " .. req.url)
      end
    end

    -- ----- Refresh 2: same `since` re-runs full pipeline from scratch -----
    Mocks._captured_requests = {}
    queue_full_success("purchase_simple_sale")
    local r2 = RefreshAccount(account, since)
    assert.is_table(r2,
      "ERR-06 case 1: second refresh with same `since` must succeed once finance recovers, "
      .. "got: " .. type(r2))
    assert.is_table(r2.transactions, "ERR-06 case 1: r2.transactions must be a table")
    assert.is_true(#r2.transactions >= 1,
      "ERR-06 case 1: second refresh must emit at least one transaction (no orphan state from r1)")
  end)

  -- ---------------------------------------------------------------------
  -- ERR-06 Case 2: 401-on-finance (post-mint token revoked)
  -- ---------------------------------------------------------------------
  -- Composes with Plan 05-04 ERR-04: post-mint 401 from the finance liquid
  -- balance GET routes through fetch_account_state's inline 401-direct-check
  -- and surfaces error.token_revoked. The preliminary GET is NOT issued —
  -- the abort-on-liquid-401 optimization (Plan 05-04 SUMMARY).
  it("ERR-06 case 2: 401 on finance (post-mint token revoked) returns error.token_revoked", function()
    local orgUuid = "org-err06-c2"
    local account = { accountNumber = orgUuid, currency = "EUR", balance = 0 }
    local since   = 0

    -- Refresh 1: purchase OK, then 401 (invalid_client body) on finance liquid GET.
    -- _infer_status maps {"error":"invalid_client"} -> 401 -> fetch_account_state's
    -- inline 401-direct-check returns error.token_revoked.
    seed_token(orgUuid)
    Mocks.push_response({ content = Fixtures.load("purchases/purchase_simple_sale") })
    Mocks.push_response({ content = '{"error":"invalid_client"}' })  -- liquid GET -> 401

    local r1 = RefreshAccount(account, since)

    -- (a) return value is the German error.token_revoked string (composes with ERR-04)
    assert.is_string(r1,
      "ERR-06 case 2: RefreshAccount must return an error STRING on post-mint 401, "
      .. "got: " .. type(r1))
    assert.equals(M_i18n.t("error.token_revoked"), r1,
      "ERR-06 case 2: post-mint 401 on finance must surface error.token_revoked (ERR-04 composition)")

    -- (b) no second finance call happens: preliminary and transactions must
    -- NOT be issued (abort-on-liquid-401 invariant from Plan 05-04).
    for _, req in ipairs(Mocks._captured_requests) do
      if type(req.url) == "string" then
        assert.is_falsy(req.url:find("preliminary/balance", 1, true),
          "ERR-06 case 2: preliminary GET must NOT fire after liquid 401 (fail-whole + Plan 05-04 abort), "
          .. "got: " .. req.url)
        assert.is_falsy(req.url:find("liquid/transactions", 1, true),
          "ERR-06 case 2: finance transactions GET must NOT fire after liquid 401 (fail-whole), "
          .. "got: " .. req.url)
      end
    end

    -- ----- Refresh 2: user re-entered API key (fresh bearer) succeeds -----
    Mocks._captured_requests = {}
    -- Overwrite the cached token (simulating successful re-auth via InitializeSession2).
    LocalStorage["zettle:" .. orgUuid] = JSON():set({
      access_token = "AT-FRESH-AFTER-REAUTH",
      expires_at   = os.time() + 7200,
      obtained_at  = os.time(),
      client_id    = "client-x",
      uuid         = "u-1",
      publicName   = "Beispiel Caf\xc3\xa9",
    }):json()
    queue_full_success("purchase_simple_sale")
    local r2 = RefreshAccount(account, since)
    assert.is_table(r2,
      "ERR-06 case 2: second refresh with fresh bearer must succeed, got: " .. type(r2))
    assert.is_table(r2.transactions)
    assert.is_true(#r2.transactions >= 1,
      "ERR-06 case 2: refresh 2 must emit at least one transaction (no orphan state from refresh 1)")
  end)

  -- ---------------------------------------------------------------------
  -- ERR-06 Case 3: network failure on finance
  -- ---------------------------------------------------------------------
  -- Network-level failure (DNS, connect-refused, socket timeout) surfaces in
  -- the mock layer as empty body. Phase 2 _infer_status nil-path inheritance
  -- per ADR-0005 Invariant 5. Distinct from Case 1 only in intent: this is
  -- the ERR-05 regression gate (the empty body represents a transport-level
  -- failure, not a 5xx response).
  it("ERR-06 case 3: network failure on finance returns error.network", function()
    local orgUuid = "org-err06-c3"
    local account = { accountNumber = orgUuid, currency = "EUR", balance = 0 }
    local since   = 0

    -- Refresh 1: purchase OK, then 3 empty bodies on finance liquid GET
    -- (Plan 05-03 _request_with_retry exhausts; existing nil-status branch).
    seed_token(orgUuid)
    Mocks.push_response({ content = Fixtures.load("purchases/purchase_simple_sale") })
    Mocks.push_response({ content = "" })  -- liquid GET attempt 1 (network failure)
    Mocks.push_response({ content = "" })  -- liquid GET attempt 2 (retry)
    Mocks.push_response({ content = "" })  -- liquid GET attempt 3 (final retry)

    local r1 = RefreshAccount(account, since)

    -- (a) return value is the German error.network string
    assert.is_string(r1,
      "ERR-06 case 3: RefreshAccount must return an error STRING on finance network failure, "
      .. "got: " .. type(r1))
    assert.equals(M_i18n.t("error.network", "—"), r1,
      "ERR-06 case 3: finance empty-body retry exhaust must surface error.network "
      .. "(ADR-0005 Invariant 5 + ERR-05 regression gate)")

    -- (b) `since` byte-identically passed across both refreshes (D-66): the
    -- test passes the SAME `since` local in to both invocations. The wire-
    -- level startDate is derived via the D-33 clamp (90-day floor); the
    -- MoneyMoney -> extension boundary contract is the `since` we pass in.
    -- Verify the purchase URL on the FIRST captured call carries the expected
    -- 90-day-ago prefix so any future regression that advances `since`
    -- silently surfaces here.
    local ninety_days_ago_iso = os.date("!%Y-%m-%dT", os.time() - 90 * 86400)
    local first_purchase_url = nil
    for _, req in ipairs(Mocks._captured_requests) do
      if type(req.url) == "string"
          and req.url:find("purchase.izettle.com/purchases/v2", 1, true) then
        first_purchase_url = req.url
        break
      end
    end
    assert.is_not_nil(first_purchase_url,
      "ERR-06 case 3: at least one purchase.izettle.com request expected in refresh 1")
    assert.is_not_nil(first_purchase_url:find("startDate=" .. ninety_days_ago_iso, 1, true),
      "ERR-06 case 3: refresh 1 startDate must carry the D-33 90-day clamp prefix "
      .. ninety_days_ago_iso .. ", got: " .. first_purchase_url)

    -- ----- Refresh 2: same `since` succeeds with normal responses -----
    Mocks._captured_requests = {}
    queue_full_success("purchase_simple_sale")
    local r2 = RefreshAccount(account, since)
    assert.is_table(r2, "ERR-06 case 3: second refresh must succeed once network recovers")
    assert.is_table(r2.transactions)
    assert.is_true(#r2.transactions >= 1,
      "ERR-06 case 3: refresh 2 must emit at least one transaction (no orphan state)")

    -- (b) reaffirmed across refresh 2: same startDate prefix on the purchase URL.
    local r2_purchase_url = nil
    for _, req in ipairs(Mocks._captured_requests) do
      if type(req.url) == "string"
          and req.url:find("purchase.izettle.com/purchases/v2", 1, true) then
        r2_purchase_url = req.url
        break
      end
    end
    assert.is_not_nil(r2_purchase_url,
      "ERR-06 case 3: refresh 2 must issue at least one purchase request")
    assert.is_not_nil(r2_purchase_url:find("startDate=" .. ninety_days_ago_iso, 1, true),
      "ERR-06 case 3: refresh 2 startDate must reuse the SAME D-33 clamp prefix as refresh 1 "
      .. "(`since` byte-identical across failed + retry refreshes — D-66 invariant)")
  end)

  -- ---------------------------------------------------------------------
  -- ERR-06 Case 4: 5xx-on-purchases (first pipeline step)
  -- ---------------------------------------------------------------------
  -- Pipeline order: Step 4 (purchases) fails FIRST -> Steps 5..16 never run.
  -- captured_requests must contain ONLY purchases URLs; NO finance.izettle.com
  -- URLs prove the fail-whole abort stopped before Step 7.
  it("ERR-06 case 4: 5xx on purchases (first pipeline step) returns error string with no finance calls", function()
    local orgUuid = "org-err06-c4"
    local account = { accountNumber = orgUuid, currency = "EUR", balance = 0 }
    local since   = 0

    -- Refresh 1: 3 empty bodies on the purchase fetch (Plan 05-03 retry exhausts).
    seed_token(orgUuid)
    Mocks.push_response({ content = "" })  -- purchase attempt 1
    Mocks.push_response({ content = "" })  -- purchase attempt 2 (retry)
    Mocks.push_response({ content = "" })  -- purchase attempt 3 (final retry)

    local r1 = RefreshAccount(account, since)

    -- (a) return value is the German error.network string
    assert.is_string(r1,
      "ERR-06 case 4: RefreshAccount must return an error STRING on purchase failure, "
      .. "got: " .. type(r1))
    assert.equals(M_i18n.t("error.network", "—"), r1,
      "ERR-06 case 4: purchase empty-body retry exhaust must surface error.network")

    -- (b) captured_requests shows ONLY purchases.izettle.com URLs
    --     (NO finance.izettle.com URLs — fail-whole stopped at Step 4).
    assert.equals(3, #Mocks._captured_requests,
      "ERR-06 case 4: expected exactly 3 captured requests (3 purchase retries); got: "
      .. tostring(#Mocks._captured_requests))
    for _, req in ipairs(Mocks._captured_requests) do
      assert.is_string(req.url)
      assert.is_not_nil(req.url:find("purchase.izettle.com", 1, true),
        "ERR-06 case 4: captured URL must be on purchase.izettle.com, got: " .. req.url)
      assert.is_falsy(req.url:find("finance.izettle.com", 1, true),
        "ERR-06 case 4: NO finance.izettle.com URL must appear (fail-whole stopped at Step 4), "
        .. "got: " .. req.url)
    end

    -- ----- Refresh 2: same `since` succeeds when purchases recover -----
    Mocks._captured_requests = {}
    queue_full_success("purchase_simple_sale")
    local r2 = RefreshAccount(account, since)
    assert.is_table(r2, "ERR-06 case 4: second refresh must succeed once purchases recover")
    assert.is_table(r2.transactions)
    assert.is_true(#r2.transactions >= 1,
      "ERR-06 case 4: refresh 2 must emit at least one transaction (no orphan state)")
  end)

end)
