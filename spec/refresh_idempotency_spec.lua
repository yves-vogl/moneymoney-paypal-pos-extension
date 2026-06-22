-- spec/refresh_idempotency_spec.lua
-- Gating spec for TEST-03 / SALE-02 / SALE-05 / D-38 / D-39 / D-41.
--
-- RED in Wave 1: RefreshAccount still returns the Phase-2 fixture transaction
-- (transactionCode "zettle:sale:fixture-0001"), which does not satisfy the
-- D-38 pattern "zettle:sale:<purchaseUUID1>" from a real fixture, and the
-- D-41 nil-token test passes a missing cache entry that entry.lua does not
-- yet guard against.  Both failure classes produce assertion errors, not
-- Lua errors — proving the spec exercises real code paths.
--
-- Partial GREEN in Wave 2: once src/mapping.lua returns correct transactionCodes
-- (tests 1-3 gain correct codes from the mapping layer).
-- Full GREEN in Wave 4: entry.lua RefreshAccount drives the real pipeline
-- (tests 1-3 fully green) and wires the D-41 nil-token guard (test 4).

-- luacheck: globals RefreshAccount LocalStorage M_i18n JSON
-- luacheck: ignore 431
-- luacheck: ignore 631

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Build a fresh artifact once before the suite runs.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("refresh_idempotency_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("RefreshAccount idempotency (TEST-03 / SALE-02 / SALE-05 / D-39)", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- seed_token(orgUuid) — write a valid flat-cache entry so that
  -- M_auth.cached_token(orgUuid) returns "AT-VALID" without re-auth.
  -- D-23c / D-41: uses the flat LocalStorage["zettle:<orgUuid>"] path that
  -- survives across MoneyMoney session restarts (AUTH-06).
  -- Bearer placeholder AT-VALID is NOT JWT-shaped (no two dots) so that
  -- future SEC-03 walk-pattern runs do not flag it as a leaked API key.
  -- -------------------------------------------------------------------------
  local function seed_token(orgUuid)
    LocalStorage["zettle:" .. orgUuid] = JSON():set({
      access_token = "AT-VALID",
      expires_at   = os.time() + 7200,
      obtained_at  = os.time(),
      client_id    = "client-x",
      uuid         = "u-1",
      publicName   = "Beispiel Caf\195\169",
    }):json()
  end

  -- -------------------------------------------------------------------------
  -- refresh_with_fixture(fixture_name, orgUuid)
  -- Seeds token, queues the Phase-4 four-response set TWICE (once per
  -- RefreshAccount call), runs both calls, and returns the two result tables.
  --
  -- Plan 04-03 expansion: each RefreshAccount now consumes FOUR sequential
  -- mock responses:
  --   1) purchase fixture
  --   2) /v2/accounts/liquid/balance       (finance_balance_liquid.json)
  --   3) /v2/accounts/preliminary/balance  (finance_balance_preliminary.json)
  --   4) /v2/accounts/liquid/transactions  (finance_empty.json by default)
  -- So a double-refresh queues 8 responses total. Plan 04-05 adds the actual
  -- D-58 idempotency assertions on top of this queueing infrastructure.
  -- -------------------------------------------------------------------------
  local function refresh_with_fixture(fixture_name, orgUuid)
    seed_token(orgUuid)
    local purchase_raw     = Fixtures.load("purchases/" .. fixture_name)
    local liquid_raw       = Fixtures.load("finance/finance_balance_liquid")
    local preliminary_raw  = Fixtures.load("finance/finance_balance_preliminary")
    local finance_raw      = Fixtures.load("finance/finance_empty")
    -- Queue the full 4-response tuple twice (once per RefreshAccount call).
    for _ = 1, 2 do
      Mocks.push_response({ content = purchase_raw })
      Mocks.push_response({ content = liquid_raw })
      Mocks.push_response({ content = preliminary_raw })
      Mocks.push_response({ content = finance_raw })
    end
    local account = { accountNumber = orgUuid, currency = "EUR", balance = 0 }
    local result1 = RefreshAccount(account, 0)
    local result2 = RefreshAccount(account, 0)
    return result1, result2
  end

  -- -------------------------------------------------------------------------

  it("double-refresh of purchase_simple_sale produces no new transactionCodes on second call", function()
    local result1, result2 = refresh_with_fixture("purchase_simple_sale", "org-1")

    assert.is_table(result1, "first RefreshAccount must return a table")
    assert.is_table(result2, "second RefreshAccount must return a table")
    assert.is_table(result1.transactions, "result1.transactions must be a table")
    assert.is_table(result2.transactions, "result2.transactions must be a table")
    assert.is_true(#result1.transactions >= 1,
      "first refresh must return at least one transaction")

    -- Every transactionCode in result1 must match the zettle:sale: schema (D-38).
    for _, t in ipairs(result1.transactions) do
      assert.is_string(t.transactionCode,
        "transactionCode must be a string, got: " .. tostring(t.transactionCode))
      assert.is_truthy(t.transactionCode:find("^zettle:sale:", 1, false),
        "transactionCode must match ^zettle:sale:, got: " .. tostring(t.transactionCode))
    end

    -- Build seen-set from first run.
    local seen = {}
    for _, t in ipairs(result1.transactions) do
      seen[t.transactionCode] = true
    end

    -- Second run: every transactionCode must already be in seen (D-39).
    for _, t in ipairs(result2.transactions) do
      assert.is_true(seen[t.transactionCode] ~= nil,
        "NEW transactionCode on second refresh: " .. tostring(t.transactionCode))
    end
  end)

  it("double-refresh of purchase_with_vat_and_tip preserves transactionCode stability", function()
    local result1, result2 = refresh_with_fixture("purchase_with_vat_and_tip", "org-2")

    assert.is_table(result1, "first RefreshAccount must return a table")
    assert.is_table(result2, "second RefreshAccount must return a table")
    assert.is_table(result1.transactions, "result1.transactions must be a table")
    assert.is_table(result2.transactions, "result2.transactions must be a table")
    assert.is_true(#result1.transactions >= 1,
      "first refresh must return at least one transaction")

    local seen = {}
    for _, t in ipairs(result1.transactions) do
      seen[t.transactionCode] = true
    end

    for _, t in ipairs(result2.transactions) do
      assert.is_true(seen[t.transactionCode] ~= nil,
        "NEW transactionCode on second refresh: " .. tostring(t.transactionCode))
    end
  end)

  it("double-refresh of purchase_refund preserves transactionCode stability (D-32 / D-38)", function()
    local result1, result2 = refresh_with_fixture("purchase_refund", "org-3")

    assert.is_table(result1, "first RefreshAccount must return a table")
    assert.is_table(result2, "second RefreshAccount must return a table")
    assert.is_table(result1.transactions, "result1.transactions must be a table")
    assert.is_table(result2.transactions, "result2.transactions must be a table")
    assert.is_true(#result1.transactions >= 1,
      "first refresh must return at least one transaction")

    -- At least one transactionCode in result1 must match ^zettle:refund: (D-32 / D-38).
    local found_refund_code = false
    for _, t in ipairs(result1.transactions) do
      if type(t.transactionCode) == "string"
          and t.transactionCode:find("^zettle:refund:", 1, false) then
        found_refund_code = true
      end
    end
    assert.is_true(found_refund_code,
      "result1 must contain at least one zettle:refund: transactionCode (D-32 / D-38)")

    local seen = {}
    for _, t in ipairs(result1.transactions) do
      seen[t.transactionCode] = true
    end

    for _, t in ipairs(result2.transactions) do
      assert.is_true(seen[t.transactionCode] ~= nil,
        "NEW transactionCode on second refresh: " .. tostring(t.transactionCode))
    end
  end)

  -- -------------------------------------------------------------------------
  -- Plan 05-04 / ERR-04 retry: idempotency across a token-revoked failure.
  -- Refresh N fails with `error.token_revoked` (no transactions emitted);
  -- refresh N+1 (after user re-enters API key → fresh cached bearer) succeeds
  -- and emits the SAME transactionCodes that would have appeared had refresh
  -- N succeeded. Asserts:
  --   (a) `since` parameter unchanged across the failed + retry refresh
  --       (MoneyMoney passes the same value byte-identically until a
  --       successful refresh advances its high-water mark)
  --   (b) no orphan transactionCodes from refresh N pollute refresh N+1
  --   (c) German error string format matches Plan 05-02 i18n value exactly
  -- -------------------------------------------------------------------------
  it("ERR-04 + retry: refresh N fails with token_revoked, refresh N+1 with fresh bearer succeeds without orphans (ERR-04 retry)", function()
    local orgUuid = "org-err04-retry"
    local since   = 0   -- byte-identical across both refresh calls (point (a))
    local account = { accountNumber = orgUuid, currency = "EUR", balance = 0 }

    -- ----- Refresh N: cached bearer was revoked mid-session -----
    seed_token(orgUuid)
    -- The first resource call (M_purchases.fetch page 1) gets a 401.
    -- _infer_status maps {"error":"invalid_client"} → 401, which the
    -- 401-direct-check converts to M_i18n.t("error.token_revoked").
    Mocks.push_response({ content = '{"error":"invalid_client"}' })
    local r_fail = RefreshAccount(account, since)

    assert.is_string(r_fail,
      "ERR-04 retry / refresh N: expected error string, got: " .. type(r_fail))
    assert.equals(M_i18n.t("error.token_revoked"), r_fail,
      "ERR-04 retry / refresh N: error string must equal Plan-05-02 i18n value exactly")

    -- Reset the request log so refresh N+1 starts from a clean slate; the
    -- token_revoked path emitted NO transactions (point (b) precondition).
    Mocks._captured_requests = {}

    -- ----- Refresh N+1: user re-entered API key → fresh bearer cached -----
    -- Overwrite the cached token (simulating a successful re-auth via
    -- InitializeSession2 between refreshes). New bearer NAME ensures the
    -- mock-recorded Authorization header DIFFERS from the failed refresh's.
    LocalStorage["zettle:" .. orgUuid] = JSON():set({
      access_token = "AT-FRESH-AFTER-REAUTH",
      expires_at   = os.time() + 7200,
      obtained_at  = os.time(),
      client_id    = "client-x",
      uuid         = "u-1",
      publicName   = "Beispiel Caf\195\169",
    }):json()
    -- Queue the full Plan-04-03 four-response set for the successful retry.
    local purchase_raw    = Fixtures.load("purchases/purchase_simple_sale")
    local liquid_raw      = Fixtures.load("finance/finance_balance_liquid")
    local preliminary_raw = Fixtures.load("finance/finance_balance_preliminary")
    local finance_raw     = Fixtures.load("finance/finance_empty")
    Mocks.push_response({ content = purchase_raw })
    Mocks.push_response({ content = liquid_raw })
    Mocks.push_response({ content = preliminary_raw })
    Mocks.push_response({ content = finance_raw })

    local r_ok = RefreshAccount(account, since)

    assert.is_table(r_ok,
      "ERR-04 retry / refresh N+1: expected result table, got: " .. type(r_ok))
    assert.is_table(r_ok.transactions,
      "ERR-04 retry / refresh N+1: result.transactions must be a table")
    assert.is_true(#r_ok.transactions >= 1,
      "ERR-04 retry / refresh N+1: must return at least one transaction "
      .. "(purchase_simple_sale fixture contains one sale)")

    -- Point (b): every transactionCode emerged from refresh N+1 only — refresh
    -- N produced none, so there are no orphans to dedupe against. Assert the
    -- shape matches the standard sale schema (any future code that emits a
    -- stale code from refresh N would surface here as an unexpected prefix).
    for _, t in ipairs(r_ok.transactions) do
      assert.is_string(t.transactionCode,
        "transactionCode must be a string, got: " .. tostring(t.transactionCode))
      assert.is_truthy(t.transactionCode:find("^zettle:sale:", 1, false),
        "ERR-04 retry: transactionCode must match ^zettle:sale:, got: "
        .. tostring(t.transactionCode))
    end

    -- Point (a) reaffirmed via the request log: the `since` value passed into
    -- RefreshAccount was byte-identical across both calls (the test passes the
    -- SAME `since` local to both invocations). entry.lua then clamps to
    -- max(since, now-90d) per D-33, so the wire-level startDate is the
    -- 90-day-floor (NOT 1970), but the MoneyMoney → extension boundary
    -- contract (which is what idempotency cares about) is the `since` we
    -- passed in. Verify the purchases URL exists and carries a startDate
    -- in the expected 90-day window (anything OLDER than now would violate
    -- the clamp; anything NEWER would indicate state pollution from refresh N).
    local found_purchase_url = false
    local ninety_days_ago_iso = os.date("!%Y-%m-%dT", os.time() - 90 * 86400)
    for _, req in ipairs(Mocks._captured_requests) do
      if type(req.url) == "string"
          and req.url:find("purchase.izettle.com/purchases/v2", 1, true) then
        found_purchase_url = true
        assert.is_not_nil(req.url:find("startDate=" .. ninety_days_ago_iso, 1, true),
          "ERR-04 retry: refresh N+1 must reuse the SAME clamped `since` "
          .. "(expected startDate prefix " .. ninety_days_ago_iso .. " "
          .. "from D-33 90-day clamp on since=0), got: " .. req.url)
      end
    end
    assert.is_true(found_purchase_url,
      "ERR-04 retry / refresh N+1: at least one purchase.izettle.com request expected")
  end)

  it("RefreshAccount returns German error.network string when cached_token is nil (D-41)", function()
    -- Deliberately do NOT call seed_token — LocalStorage has no entry for org-no-token.
    -- Queue a fixture defensively in case the implementation tries a fetch anyway.
    local raw = Fixtures.load("purchases/purchase_simple_sale")
    Mocks.push_response({ content = raw })

    local account = { accountNumber = "org-no-token", currency = "EUR", balance = 0 }
    local result = RefreshAccount(account, 0)

    local expected = M_i18n.t("error.network", "—")
    assert.equals(expected, result,
      "RefreshAccount must return the German error.network string when token is nil (D-41)")
  end)

end)

-- ---------------------------------------------------------------------------
-- Plan 04-05: Phase-4 D-58 idempotency extensions
-- (CONTEXT D-58 / RESEARCH §10.3)
--
-- These four cases gate the load-bearing Phase-4 invariants:
--   1. SALE-03 promotion (sale txn re-emitted with SAME transactionCode but
--      booked=true once a covering PAYOUT arrives in a later refresh).
--   2. Payout-only refresh produces a stable zettle:payout:<uuid>.
--   3. Per-sale fee linked via payments[].uuid produces a stable
--      zettle:fee:<originatingTransactionUuid>.
--   4. Aggregate fee fallback (D-49 Option B) produces a stable
--      zettle:fee:aggregate:<YYYY-MM-DD> across refreshes when the same
--      finance fixture is re-queued — the once-aggregated-always-aggregated
--      contract for a fixed input.
-- ---------------------------------------------------------------------------
describe("Phase-4 D-58 idempotency extensions (CONTEXT D-58 / RESEARCH §10.3)", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  local function seed_token(orgUuid)
    LocalStorage["zettle:" .. orgUuid] = JSON():set({
      access_token = "AT-VALID",
      expires_at   = os.time() + 7200,
      obtained_at  = os.time(),
      client_id    = "client-x",
      uuid         = "u-1",
      publicName   = "Beispiel Caf\195\169",
    }):json()
  end

  -- Queue the Plan-04-03 four-response tuple for ONE RefreshAccount call:
  --   1) purchase fixture
  --   2) /v2/accounts/liquid/balance       (finance_balance_liquid)
  --   3) /v2/accounts/preliminary/balance  (finance_balance_preliminary)
  --   4) /v2/accounts/liquid/transactions  (the named finance fixture)
  local function queue_full_response_set(purchase_fixture, finance_fixture)
    Mocks.push_response({ content = Fixtures.load("purchases/" .. purchase_fixture) })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
    Mocks.push_response({ content = Fixtures.load("finance/" .. finance_fixture) })
  end

  -- Collect every transactionCode from a result table into a set.
  local function codes_of(result)
    local s = {}
    if type(result) == "table" and type(result.transactions) == "table" then
      for _, t in ipairs(result.transactions) do
        if type(t.transactionCode) == "string" then s[t.transactionCode] = true end
      end
    end
    return s
  end

  -- Find a transaction by exact transactionCode in a result.
  local function find_txn(result, code)
    if type(result) ~= "table" or type(result.transactions) ~= "table" then return nil end
    for _, t in ipairs(result.transactions) do
      if t.transactionCode == code then return t end
    end
    return nil
  end

  -- -------------------------------------------------------------------------
  -- D-58 case 1: sale + payout_promote
  -- First refresh emits the sale with booked=false (no covering PAYOUT yet);
  -- second refresh adds the PAYOUT fixture so SALE-03 promotion flips booked
  -- to true + sets valueDate. transactionCode MUST be byte-identical across
  -- the two refreshes (MoneyMoney dedup updates the row in place).
  -- -------------------------------------------------------------------------
  it("D-58 case 1: sale+payout_promote — first refresh booked=false; second refresh promotes SAME transactionCode to booked=true + valueDate", function()
    seed_token("org-d58-1")
    local account = { accountNumber = "org-d58-1", currency = "EUR", balance = 0 }

    -- First refresh: payment fixture has NO covering PAYOUT yet.
    queue_full_response_set("purchase_page_with_payments_for_fee_join", "finance_empty")
    local r1 = RefreshAccount(account, 0)
    assert.is_table(r1, "first refresh must return a table")
    local sale_code = "zettle:sale:20202020-2020-2020-2020-202020202020"
    local sale1 = find_txn(r1, sale_code)
    assert.is_table(sale1, "first refresh must contain the sale txn " .. sale_code)
    assert.is_false(sale1.booked, "D-58 first refresh: booked must be false (no covering PAYOUT)")
    assert.is_nil(sale1.valueDate, "D-58 first refresh: valueDate must be nil")

    -- Second refresh: same purchase + finance fixture now contains the PAYMENT
    -- + covering PAYOUT — SALE-03 promotion should flip the sale to booked.
    queue_full_response_set("purchase_page_with_payments_for_fee_join",
                            "finance_payment_and_payout_for_promotion")
    local r2 = RefreshAccount(account, 0)
    assert.is_table(r2, "second refresh must return a table")
    local sale2 = find_txn(r2, sale_code)
    assert.is_table(sale2, "second refresh must contain the SAME sale transactionCode " .. sale_code)
    assert.equals(sale_code, sale2.transactionCode,
      "D-58 promotion: transactionCode must be byte-identical across refreshes")
    assert.is_true(sale2.booked,
      "D-58 promotion: booked must flip to true once a covering PAYOUT exists")
    assert.is_number(sale2.valueDate, "D-58 promotion: valueDate must be a number after promotion")
    assert.is_true(sale2.valueDate > 0, "D-58 promotion: valueDate must be > 0 after promotion")
  end)

  -- -------------------------------------------------------------------------
  -- D-58 case 2: payout-only refresh
  -- finance_payout drives a single zettle:payout:<uuid>; a second identical
  -- refresh must emit no NEW transactionCodes (the same payout transactionCode
  -- is re-emitted so MoneyMoney's dedup has something to match on).
  -- -------------------------------------------------------------------------
  it("D-58 case 2: payout-only refresh produces zettle:payout:<uuid> on first refresh; ZERO new transactionCodes on second refresh", function()
    seed_token("org-d58-2")
    local account = { accountNumber = "org-d58-2", currency = "EUR", balance = 0 }

    queue_full_response_set("purchases_empty", "finance_payout")
    local r1 = RefreshAccount(account, 0)
    assert.is_table(r1, "first refresh must return a table")
    local codes1 = codes_of(r1)
    local found_payout = false
    for code in pairs(codes1) do
      if code:find("^zettle:payout:", 1, false) then found_payout = true end
    end
    assert.is_true(found_payout,
      "first refresh must contain at least one zettle:payout: transactionCode")

    queue_full_response_set("purchases_empty", "finance_payout")
    local r2 = RefreshAccount(account, 0)
    assert.is_table(r2, "second refresh must return a table")
    for _, t in ipairs(r2.transactions or {}) do
      assert.is_true(codes1[t.transactionCode] ~= nil,
        "D-58 case 2: NEW transactionCode on second refresh: " .. tostring(t.transactionCode))
    end
  end)

  -- -------------------------------------------------------------------------
  -- D-58 case 3: per-sale fee linked emits zettle:fee:<originatingTransactionUuid>
  -- stable across refreshes. The PAYMENT_FEE in finance_payment_with_fee_linkage
  -- carries originatingTransactionUuid=cccccccc-... which matches payments[0].uuid
  -- in purchase_page_with_payments_for_fee_join (FEE-01 join).
  -- -------------------------------------------------------------------------
  it("D-58 case 3: per-sale fee linked emits zettle:fee:<originatingTransactionUuid> stable across refreshes", function()
    seed_token("org-d58-3")
    local account = { accountNumber = "org-d58-3", currency = "EUR", balance = 0 }

    queue_full_response_set("purchase_page_with_payments_for_fee_join",
                            "finance_payment_with_fee_linkage")
    local r1 = RefreshAccount(account, 0)
    assert.is_table(r1, "first refresh must return a table")
    local fee_code_expected = "zettle:fee:cccccccc-cccc-cccc-cccc-cccccccccccc"
    local fee1 = find_txn(r1, fee_code_expected)
    assert.is_table(fee1,
      "first refresh must contain fee txn with transactionCode " .. fee_code_expected)
    assert.is_truthy(fee1.transactionCode:find("^zettle:fee:cccccccc", 1, false),
      "fee transactionCode must start with zettle:fee:cccccccc, got: " .. tostring(fee1.transactionCode))

    queue_full_response_set("purchase_page_with_payments_for_fee_join",
                            "finance_payment_with_fee_linkage")
    local r2 = RefreshAccount(account, 0)
    assert.is_table(r2, "second refresh must return a table")
    local fee2 = find_txn(r2, fee_code_expected)
    assert.is_table(fee2,
      "second refresh must contain SAME fee transactionCode " .. fee_code_expected)
    assert.equals(fee1.transactionCode, fee2.transactionCode,
      "D-58 case 3: per-sale fee transactionCode must be byte-identical across refreshes")
  end)

  -- -------------------------------------------------------------------------
  -- D-58 case 4 (revised per BL-03): D-49 Option B WITHIN-refresh stability
  -- PLUS explicit enumeration of the known cross-refresh limitation.
  --
  -- The Yves-signed-off contract for v0.2.0 is:
  --   (a) Within a single refresh, the aggregate transactionCode is
  --       deterministic for stable inputs (sub-case 4a).
  --   (b) Across refreshes, if Zettle UPGRADES a previously-unlinked fee's
  --       linkage (back-fills the originatingTransactionUuid → payments[].uuid
  --       resolution) the per-refresh decision flips: refresh N saw "any
  --       unlinked → aggregate", refresh N+1 sees "all linked → per-sale".
  --       MoneyMoney's dedup updates rows in place per transactionCode, so the
  --       aggregate row from refresh N STAYS, and a NEW zettle:fee:<uuid> row
  --       appears in refresh N+1 — both coexist (sub-case 4b). This is the
  --       documented Option-B limitation; ADR-0004 "Known Limitation:
  --       cross-refresh fee re-classification" + README "Bekannte Grenzen"
  --       instruct the user to manually delete the stale aggregate row.
  --
  -- The test PASSES as long as the system behaves as documented. It does NOT
  -- prevent the double-booking — preventing it requires Option A (LocalStorage-
  -- persistent aggregated-date set), which v0.2.0 deliberately defers.
  -- -------------------------------------------------------------------------
  it("D-58 case 4a: aggregate fee transactionCode is byte-stable across refreshes when fixtures are stable (within-refresh contract)", function()
    seed_token("org-d58-4a")
    local account = { accountNumber = "org-d58-4a", currency = "EUR", balance = 0 }

    queue_full_response_set("purchase_simple_sale", "finance_payment_fee_unlinked")
    local r1 = RefreshAccount(account, 0)
    assert.is_table(r1, "first refresh must return a table")
    local agg_code_expected = "zettle:fee:aggregate:2026-06-15"
    local agg1 = find_txn(r1, agg_code_expected)
    assert.is_table(agg1,
      "first refresh must contain aggregate fee txn " .. agg_code_expected
      .. " (D-49 Option B fallback)")

    queue_full_response_set("purchase_simple_sale", "finance_payment_fee_unlinked")
    local r2 = RefreshAccount(account, 0)
    assert.is_table(r2, "second refresh must return a table")
    local codes1 = codes_of(r1)
    for _, t in ipairs(r2.transactions or {}) do
      assert.is_true(codes1[t.transactionCode] ~= nil,
        "D-58 case 4a: NEW transactionCode on second refresh: " .. tostring(t.transactionCode))
    end
    local agg2 = find_txn(r2, agg_code_expected)
    assert.is_table(agg2,
      "second refresh must contain SAME aggregate transactionCode " .. agg_code_expected)
    assert.equals(agg1.transactionCode, agg2.transactionCode,
      "D-58 case 4a: aggregate transactionCode must be byte-identical across refreshes")
  end)

  it("D-58 case 4b: BL-03 documented limitation — when Zettle back-fills fee linkage between refreshes, per-sale row appears alongside surviving aggregate row (NOT prevented in v0.2.0; ADR-0004 known-limitation contract)", function()
    seed_token("org-d58-4b")
    local account = { accountNumber = "org-d58-4b", currency = "EUR", balance = 0 }

    -- Refresh 1: the fee's originatingTransactionUuid (aaaaaaaa-...) does NOT
    -- match any payments[].uuid in purchase_simple_sale (which has no payments).
    -- D-49 Option B clusters it into zettle:fee:aggregate:2026-06-15.
    queue_full_response_set("purchase_simple_sale", "finance_payment_fee_unlinked")
    -- Override the fee fixture in slot 4 with the "linked-uuid" variant so
    -- refresh 2 below can re-use the same fee under upgraded linkage.
    -- (queue_full_response_set has already queued the unlinked variant; we
    -- want refresh 1 to use unlinked, so the default is correct here.)
    local r1 = RefreshAccount(account, 0)
    assert.is_table(r1, "first refresh must return a table")
    local agg_code = "zettle:fee:aggregate:2026-06-15"
    local agg1 = find_txn(r1, agg_code)
    assert.is_table(agg1,
      "BL-03 sub-case 4b refresh 1: must contain aggregate row " .. agg_code
      .. " (fee UUID unlinked in this refresh)")

    -- Refresh 2: same fee UUID (aaaaaaaa-...), same amount, same timestamp,
    -- but now the purchase fixture carries payments[0].uuid = aaaaaaaa-...
    -- so the entry layer's payments_by_uuid lookup SUCCEEDS and the fee
    -- emits as zettle:fee:aaaaaaaa-... (per-sale path).
    queue_full_response_set("purchase_for_double_book_test",
                            "finance_payment_fee_LINKED_for_double_book_test")
    local r2 = RefreshAccount(account, 0)
    assert.is_table(r2, "second refresh must return a table")

    -- DOCUMENTED LIMITATION (BL-03 / ADR-0004 cross-refresh re-classification):
    --   - refresh 2 emits NO aggregate row (no fees are unlinked in this refresh).
    --   - refresh 2 emits a NEW per-sale zettle:fee:aaaaaaaa-... row.
    --   - the aggregate row from refresh 1 stays in MoneyMoney (no delete signal).
    -- This is what the user manually cleans up; the test enumerates the case.
    local per_sale_code = "zettle:fee:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    local per_sale2 = find_txn(r2, per_sale_code)
    assert.is_table(per_sale2,
      "BL-03 sub-case 4b refresh 2: per-sale row " .. per_sale_code
      .. " must appear when linkage resolves (Option B per-refresh decision)")
    local agg2 = find_txn(r2, agg_code)
    assert.is_nil(agg2,
      "BL-03 sub-case 4b refresh 2: aggregate row " .. agg_code
      .. " is NOT re-emitted (no unlinked fee in this refresh) — the "
      .. "row from refresh 1 survives in MoneyMoney as the documented "
      .. "double-book artefact the user manually deletes (ADR-0004).")

    -- The transactionCode set DIVERGES across refreshes — this is the
    -- documented contract. The per-sale code in refresh 2 is NEW relative
    -- to refresh 1 (which had only the aggregate code). Assert the
    -- divergence so a future change that "fixes" Option B without updating
    -- ADR-0004 + README has to revisit this test.
    local codes1 = codes_of(r1)
    assert.is_nil(codes1[per_sale_code],
      "BL-03 sub-case 4b: per-sale code must NOT have existed in refresh 1 "
      .. "(refresh 1 emitted aggregate only) — enumerating cross-refresh divergence.")
  end)

end)
