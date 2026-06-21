-- spec/entry_spec.lua
-- Tests for the five MoneyMoney callbacks in src/entry.lua.
-- Coverage: walking-skeleton gate (SupportsBank, InitializeSession2,
--           ListAccounts, RefreshAccount, EndSession) + Phase-2 integration
--           (D-21 two-call probe, D-22 client_id extraction, D-23a/b cache
--           read, D-25 EndSession shutdown, AUTH-06 cache survival).
--
-- Loading strategy (Wave 3 upgrade):
--   before_each — rebuild artifact + dofile + reset mocks so each test gets
--                 a fresh module-local _conn and clean LocalStorage.
--   after_each  — teardown mocks.
--
-- JWT used in credential tests: hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig
--   Middle segment base64url-decodes to {"aud":"client-x"} (no padding needed).

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Precomputed base64url JWT whose payload yields aud="client-x".
-- Verified: base64url("eyJhdWQiOiJjbGllbnQteCJ9") -> {"aud":"client-x"}
local VALID_JWT = "hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig"

-- ---------------------------------------------------------------------------
describe("entry.lua callbacks", function()

  local function load_artifact()
    local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
    if not ok or code ~= 0 then
      error("entry_spec: failed to build dist/paypal-pos.lua before suite")
    end
    dofile("dist/paypal-pos.lua")
  end

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- SupportsBank
  -- -------------------------------------------------------------------------

  it("SupportsBank true for ProtocolWebBanking + 'PayPal POS'", function()
    assert.is_true(SupportsBank(ProtocolWebBanking, "PayPal POS"))
  end)

  it("SupportsBank false for ProtocolFinTS + 'PayPal POS'", function()
    assert.is_false(SupportsBank(ProtocolFinTS, "PayPal POS"))
  end)

  it("SupportsBank false for ProtocolWebBanking + 'Other Bank'", function()
    assert.is_false(SupportsBank(ProtocolWebBanking, "Other Bank"))
  end)

  -- -------------------------------------------------------------------------
  -- InitializeSession2 — Phase-1 challenge (preserved verbatim per D-10)
  -- -------------------------------------------------------------------------

  it("InitializeSession2 returns an API-Key challenge object on nil credentials", function()
    local challenge = InitializeSession2(ProtocolWebBanking, "PayPal POS", 1, nil, false)
    assert.is_table(challenge)
    assert.equals(M_i18n.t("credential.api_key.label"), challenge.label)
    assert.equals(M_i18n.t("credential.api_key.label"), challenge.title)
    assert.equals(M_i18n.t("credential.api_key.label"), challenge.challenge)
  end)

  it("InitializeSession2 returns German error string on empty challenge credential", function()
    local err = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                   { { value = "" } }, false)
    assert.equals(M_i18n.t("error.invalid_grant"), err)
  end)

  -- -------------------------------------------------------------------------
  -- InitializeSession2 — D-22 malformed JWT (no network call)
  -- -------------------------------------------------------------------------

  it("InitializeSession2 with malformed JWT returns error.invalid_grant without any network call", function()
    -- No response queued: any HTTP call would error via mm_mocks.
    -- Mocks._last_request must stay nil (zero network calls per D-22 / Pattern 4).
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = "not-a-jwt" } }, false)
    assert.equals(M_i18n.t("error.invalid_grant"), result)
    assert.is_nil(Mocks._last_request)
  end)

  it("InitializeSession2 string credential with malformed JWT returns error.invalid_grant", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      "any-non-empty-but-not-a-jwt", false)
    assert.equals(M_i18n.t("error.invalid_grant"), result)
    assert.is_nil(Mocks._last_request)
  end)

  it("InitializeSession2 with positional-array malformed JWT returns error.invalid_grant", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { "any-non-empty-but-not-a-jwt" }, false)
    assert.equals(M_i18n.t("error.invalid_grant"), result)
    assert.is_nil(Mocks._last_request)
  end)

  it("InitializeSession2 with hash-table password malformed JWT returns error.invalid_grant", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { username = "foo", password = "any-non-empty-but-not-a-jwt" }, false)
    assert.equals(M_i18n.t("error.invalid_grant"), result)
    assert.is_nil(Mocks._last_request)
  end)

  it("InitializeSession2 with hash-table username-only malformed JWT returns error.invalid_grant", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { username = "any-non-empty-but-not-a-jwt" }, false)
    assert.equals(M_i18n.t("error.invalid_grant"), result)
    assert.is_nil(Mocks._last_request)
  end)

  -- -------------------------------------------------------------------------
  -- InitializeSession2 — D-21 two-call probe with valid JWT credentials
  -- -------------------------------------------------------------------------

  it("InitializeSession2 with valid credentials populates LocalStorage", function()
    local tok_raw = Fixtures.load("auth/token_ok")
    local usr_raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = tok_raw, mime = "application/json" })
    Mocks.push_response({ content = usr_raw, mime = "application/json" })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = VALID_JWT } }, false)
    assert.is_nil(result)
    -- Cache must be populated under the org UUID from users_self_ok.json
    assert.is_table(LocalStorage.zettle)
    local org = "b2c3d4e5-f6a7-8901-bcde-f12345678901"
    assert.is_not_nil(LocalStorage.zettle[org])
    -- Flat-key fallback must also be written (D-23c double-write)
    assert.is_string(LocalStorage["zettle:" .. org])
    assert.is_truthy(#LocalStorage["zettle:" .. org] > 0)
  end)

  it("InitializeSession2 with invalid_grant returns LoginFailed and does not populate LocalStorage", function()
    local tok_raw = Fixtures.load("auth/token_invalid_grant")
    Mocks.push_response({ content = tok_raw, mime = "application/json" })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = VALID_JWT } }, false)
    assert.equals(LoginFailed, result)
    -- persist_session must NOT have been called
    assert.is_nil(LocalStorage.zettle)
  end)

  it("InitializeSession2 with /users/self scope failure returns LoginFailed; LocalStorage stays empty", function()
    local tok_raw = Fixtures.load("auth/token_ok")
    local usr_raw = Fixtures.load("auth/users_self_unauthorized")
    Mocks.push_response({ content = tok_raw, mime = "application/json" })
    Mocks.push_response({ content = usr_raw, mime = "application/json" })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = VALID_JWT } }, false)
    assert.equals(LoginFailed, result)
    assert.is_nil(LocalStorage.zettle)
  end)

  -- -------------------------------------------------------------------------
  -- B-01 / M-01: /token 200 with missing access_token must not crash
  -- -------------------------------------------------------------------------

  it("InitializeSession2 returns error.invalid_grant when /token 200 has no access_token (B-01)", function()
    -- Push a 200-shaped response body that omits the access_token field.
    -- Without the B-01 guard this reaches fetch_profile(nil) which throws
    -- "attempt to concatenate a nil value" at src/auth.lua:88.
    Mocks.push_response({ content = '{"token_type":"Bearer","expires_in":7200}',
                          mime    = "application/json" })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = VALID_JWT } }, false)

    assert.equals(M_i18n.t("error.invalid_grant"), result)
    -- Only one network call must have been made (the /token call); /users/self
    -- must NOT have been attempted.
    assert.equals("https://oauth.zettle.com/token", Mocks._last_request.url)
    -- LocalStorage must remain untouched.
    assert.is_nil(LocalStorage.zettle)
  end)

  -- -------------------------------------------------------------------------
  -- B-02 / M-01: /users/self 200 with missing organizationUuid must not crash
  -- -------------------------------------------------------------------------

  it("InitializeSession2 returns error.invalid_grant when /users/self 200 has no organizationUuid (B-02)", function()
    -- Push a valid /token response followed by a /users/self response that
    -- omits organizationUuid. Without the B-02 guard, persist_session calls
    -- _cache_write(nil, entry) which throws "table index is nil".
    local tok_raw = Fixtures.load("auth/token_ok")
    Mocks.push_response({ content = tok_raw, mime = "application/json" })
    Mocks.push_response({ content = '{}', mime = "application/json" })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = VALID_JWT } }, false)

    -- Must return a German error string (not crash)
    assert.is_string(result)
    assert.is_truthy(#result > 0)
    -- LocalStorage must NOT have been written
    assert.is_nil(LocalStorage.zettle)
  end)

  -- -------------------------------------------------------------------------
  -- M-02: rate_limit fixture must surface error.rate_limit (not LoginFailed)
  -- -------------------------------------------------------------------------

  it("InitializeSession2 returns error.rate_limit when /token returns rate_limit body (M-02)", function()
    -- Load the recorded rate-limit fixture ({"error":"rate_limit",...}).
    -- Without the H-01 fix, _infer_status returns 400 -> from_http_status(400)
    -- -> LoginFailed. With the fix it returns 429 -> error.rate_limit.
    local rl_raw = Fixtures.load("auth/token_rate_limited")
    Mocks.push_response({ content = rl_raw, mime = "application/json" })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = VALID_JWT } }, false)

    assert.equals(M_i18n.t("error.rate_limit"), result)
    -- Only /token must have been called; no /users/self call on rate limit.
    assert.equals("https://oauth.zettle.com/token", Mocks._last_request.url)
    assert.is_nil(LocalStorage.zettle)
  end)

  -- -------------------------------------------------------------------------
  -- ListAccounts
  -- -------------------------------------------------------------------------

  it("ListAccounts returns Phase-1 fixture when cache is empty", function()
    -- Explicitly confirm LocalStorage.zettle is nil (empty-cache path)
    assert.is_nil(LocalStorage.zettle)
    local accs = ListAccounts({})
    assert.equals(1, #accs)
    assert.equals(AccountTypeGiro, accs[1].type)
    assert.equals("EUR", accs[1].currency)
    assert.equals("paypal-pos-fixture-001", accs[1].accountNumber)
  end)

  it("ListAccounts returns AccountTypeGiro for each cached merchant", function()
    -- Populate cache via full InitializeSession2 probe
    local tok_raw = Fixtures.load("auth/token_ok")
    local usr_raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = tok_raw })
    Mocks.push_response({ content = usr_raw })
    InitializeSession2(ProtocolWebBanking, "PayPal POS", 2, { { value = VALID_JWT } }, false)

    local accs = ListAccounts({})
    assert.equals(1, #accs)
    assert.equals(AccountTypeGiro, accs[1].type)
    assert.equals("EUR", accs[1].currency)
  end)

  it("ListAccounts label uses publicName when cache populated", function()
    local tok_raw = Fixtures.load("auth/token_ok")
    local usr_raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = tok_raw })
    Mocks.push_response({ content = usr_raw })
    InitializeSession2(ProtocolWebBanking, "PayPal POS", 2, { { value = VALID_JWT } }, false)

    local accs = ListAccounts({})
    -- users_self_ok.json has publicName = "Beispiel Cafe GmbH" (UTF-8 content)
    assert.equals(1, #accs)
    assert.is_truthy(accs[1].name:find("Beispiel", 1, true))
    assert.equals("b2c3d4e5-f6a7-8901-bcde-f12345678901", accs[1].accountNumber)
  end)

  it("ListAccounts label falls back to orgUuid prefix when publicName empty", function()
    local org = "deadbeef-1234-5678-abcd-ef0123456789"
    LocalStorage.zettle = {
      [org] = {
        access_token = "tok",
        obtained_at  = os.time(),
        expires_at   = os.time() + 7200,
        client_id    = "c-x",
        uuid         = "u-1",
        publicName   = "",
      },
    }

    local accs = ListAccounts({})
    assert.equals(1, #accs)
    assert.is_truthy(accs[1].name:find(org:sub(1, 8), 1, true))
    assert.equals(org, accs[1].accountNumber)
    assert.equals(AccountTypeGiro, accs[1].type)
    assert.equals("EUR", accs[1].currency)
  end)

  it("ListAccounts returns two records for two merchants (ACCT-04)", function()
    local org1 = "aaaaaaaa-0001-0001-0001-000000000001"
    local org2 = "bbbbbbbb-0002-0002-0002-000000000002"
    LocalStorage.zettle = {
      [org1] = {
        access_token = "tok1", obtained_at = os.time(), expires_at = os.time() + 7200,
        client_id = "c1", uuid = "u1", publicName = "Haendler A",
      },
      [org2] = {
        access_token = "tok2", obtained_at = os.time(), expires_at = os.time() + 7200,
        client_id = "c2", uuid = "u2", publicName = "Haendler B",
      },
    }

    local accs = ListAccounts({})
    assert.equals(2, #accs)

    local nums = {}
    for _, a in ipairs(accs) do
      nums[a.accountNumber] = a
      assert.equals(AccountTypeGiro, a.type)
      assert.equals("EUR", a.currency)
    end
    assert.is_not_nil(nums[org1])
    assert.is_not_nil(nums[org2])
    assert.is_truthy(nums[org1].name:find("Haendler A", 1, true))
    assert.is_truthy(nums[org2].name:find("Haendler B", 1, true))
  end)

  -- -------------------------------------------------------------------------
  -- RefreshAccount — Phase-1 guard (Phase-3 pipeline replaces the fixture body)
  -- -------------------------------------------------------------------------

  it("RefreshAccount returns a German error string when accountNumber is missing (Phase-3 guard)", function()
    -- Phase-3 rewire: RefreshAccount({}, 0) has no accountNumber so it returns
    -- error.network instead of a transaction table. The Phase-1 fixture body is gone.
    local r = RefreshAccount({}, 0)
    assert.is_string(r, "RefreshAccount must return a string error when accountNumber is absent")
    assert.truthy(
      r:find("missing_account", 1, true) or r:find("Netzwerkfehler", 1, true),
      "expected German error.network envelope, got: " .. tostring(r)
    )
  end)

  -- -------------------------------------------------------------------------
  -- EndSession — D-25 + AUTH-06
  -- -------------------------------------------------------------------------

  it("EndSession returns nil", function()
    assert.is_nil(EndSession())
  end)

  it("EndSession does NOT clear LocalStorage cache (AUTH-06)", function()
    local tok_raw = Fixtures.load("auth/token_ok")
    local usr_raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = tok_raw })
    Mocks.push_response({ content = usr_raw })
    InitializeSession2(ProtocolWebBanking, "PayPal POS", 2, { { value = VALID_JWT } }, false)

    local org = "b2c3d4e5-f6a7-8901-bcde-f12345678901"
    assert.is_not_nil(LocalStorage.zettle[org])
    local flat_before = LocalStorage["zettle:" .. org]

    EndSession()

    -- Cache must survive EndSession (AUTH-06: NEVER clear LocalStorage in EndSession)
    assert.is_not_nil(LocalStorage.zettle)
    assert.is_not_nil(LocalStorage.zettle[org])
    assert.equals(flat_before, LocalStorage["zettle:" .. org])
  end)

  it("EndSession calls M_http.shutdown (connection released)", function()
    local conn_calls = 0
    local orig_connection = _G.Connection
    _G.Connection = function()
      conn_calls = conn_calls + 1
      return orig_connection()
    end

    -- First exchange: creates the module-local _conn (1 Connection call)
    local tok_raw = Fixtures.load("auth/token_ok")
    local usr_raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = tok_raw })
    Mocks.push_response({ content = usr_raw })
    InitializeSession2(ProtocolWebBanking, "PayPal POS", 2, { { value = VALID_JWT } }, false)
    assert.equals(1, conn_calls)

    -- EndSession shuts down _conn (nils the module-local cache)
    EndSession()

    -- Second exchange must create a fresh Connection (conn_calls becomes 2)
    local tok_raw2 = Fixtures.load("auth/token_ok")
    local usr_raw2 = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = tok_raw2 })
    Mocks.push_response({ content = usr_raw2 })
    InitializeSession2(ProtocolWebBanking, "PayPal POS", 2, { { value = VALID_JWT } }, false)
    assert.equals(2, conn_calls)
  end)

  it("cache survives EndSession + simulated restart via flat fallback (AUTH-06)", function()
    -- Phase 1: populate cache via two-call probe
    local tok_raw = Fixtures.load("auth/token_ok")
    local usr_raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = tok_raw })
    Mocks.push_response({ content = usr_raw })
    InitializeSession2(ProtocolWebBanking, "PayPal POS", 2, { { value = VALID_JWT } }, false)

    local org = "b2c3d4e5-f6a7-8901-bcde-f12345678901"

    -- Phase 2: EndSession closes connection but leaves LocalStorage intact
    EndSession()

    -- Phase 3: simulate restart — nested table lost (Q5 worst-case)
    LocalStorage.zettle = nil

    -- Phase 4: flat-fallback path still returns the access_token
    local token = M_auth.cached_token(org)
    assert.is_string(token)
    assert.is_truthy(#token > 0)
  end)

end)

-- ---------------------------------------------------------------------------
-- Phase-3 RefreshAccount integration tests (SALE-01..06+08 / D-31 / D-33 / D-37 / D-41)
-- ---------------------------------------------------------------------------
-- luacheck: globals RefreshAccount LocalStorage M_i18n JSON M_auth
describe("RefreshAccount Phase-3 pipeline (SALE-01..06+08 / D-31 / D-33 / D-37 / D-41)", function()

  local function load_artifact()
    local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
    if not ok or code ~= 0 then
      error("entry_spec phase-3: failed to build dist/paypal-pos.lua")
    end
    dofile("dist/paypal-pos.lua")
  end

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- Seed a valid token into the flat-fallback cache so M_auth.cached_token
  -- returns "AT-VALID" without re-auth. Uses the D-23c flat path that survives
  -- cross-restart scenarios (AUTH-06). AT-VALID has no two dots so it is NOT
  -- JWT-shaped and SEC-03 walks will not flag it as a leaked API key.
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

  -- Plan 04-03: a successful RefreshAccount now issues FOUR sequential GETs:
  --   1) purchase pages (Phase 3)
  --   2) /v2/accounts/liquid/balance       (ACCT-03 — Plan 04-03)
  --   3) /v2/accounts/preliminary/balance  (ACCT-03 — Plan 04-03)
  --   4) Finance API transactions pages    (Phase 4 — Plan 04-03)
  -- Phase-3 tests that only care about the purchase pipeline queue empty
  -- balance + finance fixtures via this helper to satisfy the new call shape.
  -- Tests that exercise an HTTP failure on the purchase fetch (ERR-06) leave
  -- the trailing 3 responses queued harmlessly — they are never consumed
  -- because the purchase fetch short-circuits the refresh.
  local function queue_finance_tail()
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_empty") })
  end

  -- -------------------------------------------------------------------------

  it("RefreshAccount returns error string when accountNumber is missing (guard)", function()
    local result = RefreshAccount({ balance = 0 }, 0)
    assert.is_string(result, "expected error string when accountNumber is absent")
    assert.truthy(
      result:find("missing_account", 1, true) or result:find("Netzwerkfehler", 1, true),
      "expected German error.network envelope, got: " .. tostring(result)
    )
  end)

  it("RefreshAccount returns error.network when cached_token is nil (D-41)", function()
    -- Deliberately do NOT call seed_token — LocalStorage has no entry for org-no-token.
    local result = RefreshAccount({ accountNumber = "org-no-token", currency = "EUR", balance = 0 }, 0)
    assert.is_string(result, "expected error string when no token in cache")
    assert.equals(M_i18n.t("error.network", "\xe2\x80\x94"), result,
      "D-41: result must be German error.network with em-dash suffix")
  end)

  it("RefreshAccount returns transactions for purchase_simple_sale fixture (happy path)", function()
    seed_token("org-1")
    local raw = Fixtures.load("purchases/purchase_simple_sale")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local result = RefreshAccount({ accountNumber = "org-1", currency = "EUR", balance = 0 }, 0)
    assert.is_table(result, "result must be a table on success")
    assert.is_table(result.transactions, "result.transactions must be a table")
    assert.equals(1, #result.transactions, "expected 1 transaction from purchase_simple_sale")
    -- purchase_simple_sale has amount=500 minor units -> 5.00 EUR
    assert.equals(5.00, result.transactions[1].amount,
      "amount must be 5.00 EUR (500 minor units / 100)")
    assert.equals("zettle:sale:11111111-1111-1111-1111-111111111111",
      result.transactions[1].transactionCode,
      "transactionCode must follow zettle:sale:<purchaseUUID1> pattern (D-38)")
    assert.is_false(result.transactions[1].booked,
      "booked must be false in Phase 3 (D-31)")
  end)

  it("RefreshAccount dispatches refund_to_transaction for refund records (D-32)", function()
    seed_token("org-2")
    local raw = Fixtures.load("purchases/purchase_refund")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local result = RefreshAccount({ accountNumber = "org-2", currency = "EUR", balance = 0 }, 0)
    assert.is_table(result, "result must be a table for refund fixture")
    assert.equals(1, #result.transactions, "expected 1 transaction from purchase_refund")
    assert.is_true(result.transactions[1].amount < 0,
      "refund transaction amount must be negative (D-32)")
    assert.truthy(result.transactions[1].transactionCode:find("^zettle:refund:", 1, false),
      "refund transactionCode must start with zettle:refund: (D-38), got: " ..
      tostring(result.transactions[1].transactionCode))
  end)

  it("RefreshAccount silently skips non-EUR purchases (D-37)", function()
    seed_token("org-3")
    local raw = Fixtures.load("purchases/purchase_non_eur")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local result = RefreshAccount({ accountNumber = "org-3", currency = "EUR", balance = 0 }, 0)
    assert.is_table(result, "result must be a table even when all purchases are skipped")
    assert.is_table(result.transactions, "result.transactions must be a table")
    assert.equals(0, #result.transactions,
      "non-EUR purchases must be silently skipped — expected 0 transactions")
  end)

  it("RefreshAccount returns empty transactions for empty fixture (SALE-06 incremental empty-refresh)", function()
    seed_token("org-4")
    local raw = Fixtures.load("purchases/purchases_empty")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local result = RefreshAccount({ accountNumber = "org-4", currency = "EUR", balance = 0 }, os.time() - 60)
    assert.is_table(result, "result must be a table for empty purchase page")
    assert.is_table(result.transactions, "result.transactions must be a table")
    assert.equals(0, #result.transactions,
      "empty purchase page must yield 0 transactions (SALE-06)")
  end)

  it("RefreshAccount clamps since to 90 days back when caller passes 0 (D-33)", function()
    seed_token("org-5")
    local raw = Fixtures.load("purchases/purchases_empty")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    RefreshAccount({ accountNumber = "org-5", currency = "EUR", balance = 0 }, 0)
    -- _last_request is now the final Finance API call; assert on the purchase
    -- URL via _captured_requests[1] which is the Phase-3 purchase fetch.
    local url = Mocks._captured_requests[1] and Mocks._captured_requests[1].url or ""
    assert.truthy(url:find("startDate=", 1, true),
      "purchase URL must include startDate query param, got: " .. tostring(url))
    -- The startDate must NOT be the epoch (1970-01-01); it must reflect the 90-day clamp.
    local ok = not url:find("startDate=1970", 1, true)
    assert.is_true(ok,
      "startDate must be clamped to ~90 days ago, not the epoch 1970: " .. url)
  end)

  it("RefreshAccount passes through recent since unchanged when newer than 90-day window (D-33)", function()
    seed_token("org-6")
    local raw = Fixtures.load("purchases/purchases_empty")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local recent = os.time() - 3600  -- 1 hour ago — well within 90 days
    RefreshAccount({ accountNumber = "org-6", currency = "EUR", balance = 0 }, recent)
    -- Inspect the purchase URL (first captured request) — D-33 is about
    -- the purchase fetch's startDate, not the Finance API's start= param.
    local url = Mocks._captured_requests[1] and Mocks._captured_requests[1].url or ""
    assert.truthy(url:find("startDate=", 1, true),
      "purchase URL must include startDate query param, got: " .. tostring(url))
    -- The year-month substring of the recent timestamp should appear in the URL.
    local recent_iso = os.date("!%Y-%m", recent)
    assert.truthy(url:find(recent_iso, 1, true),
      "purchase URL must contain year-month " .. recent_iso .. " for recent since, got: " .. url)
  end)

  it("RefreshAccount returns Finance-API balance when liquid call succeeds (ACCT-03)", function()
    -- Phase-4 ACCT-03 wired: balance now comes from /v2/accounts/liquid/balance
    -- (= 12345 / 100 = 123.45 EUR per finance_balance_liquid fixture), NOT
    -- account.balance pass-through. The fallback to account.balance fires only
    -- when account_state.balance is nil (e.g. non-EUR liquid per R-4).
    seed_token("org-7")
    local raw = Fixtures.load("purchases/purchases_empty")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local result = RefreshAccount({ accountNumber = "org-7", currency = "EUR", balance = 999.99 }, os.time() - 60)
    assert.is_table(result, "result must be a table")
    assert.equals(123.45, result.balance,
      "balance must come from finance_balance_liquid fixture (12345 / 100)")
    assert.equals(6.78, result.pendingBalance,
      "pendingBalance must come from finance_balance_preliminary fixture (678 / 100)")
  end)

  it("RefreshAccount returns string error on purchase-fetch HTTP failure (ERR-06 fail-whole-refresh)", function()
    seed_token("org-8")
    -- Use a rate_limit body so M_http._infer_status -> 429 -> German rate_limit
    -- string. The purchase fetch errors first; the Finance API tail GETs are
    -- never issued so no further responses need to be queued.
    Mocks.push_response({ content = '{"error":"rate_limit"}' })
    local result = RefreshAccount({ accountNumber = "org-8", currency = "EUR", balance = 0 }, 0)
    -- The result must be an error string (not a table) — ERR-06 fail-whole-refresh.
    assert.is_string(result, "RefreshAccount must return an error string on HTTP failure (ERR-06)")
    assert.truthy(#result > 0, "error string must be non-empty")
  end)

  -- -------------------------------------------------------------------------
  -- S-04: since=math.huge must not crash os.date() in effective_since path
  -- -------------------------------------------------------------------------

  it("RefreshAccount does not crash when since=math.huge (S-04)", function()
    -- math.max(math.huge, now-90d) = math.huge; os.date(..., math.huge) raises
    -- "number has no integer representation" without a cap guard.
    -- After fix: effective_since = math.min(effective_since, os.time()) caps Inf.
    seed_token("org-s04")
    local raw = Fixtures.load("purchases/purchases_empty")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local ok, result = pcall(RefreshAccount,
      { accountNumber = "org-s04", currency = "EUR", balance = 0 },
      math.huge)
    assert.is_true(ok,
      "RefreshAccount must not crash when since=math.huge (S-04), error: " .. tostring(result))
    -- Result may be a table or an error string; either is acceptable as long as it doesn't raise.
    assert.is_true(type(result) == "table" or type(result) == "string",
      "RefreshAccount must return table or string when since=math.huge (S-04), got: " ..
      tostring(result))
  end)

  it("RefreshAccount clamps future since to at most os.time() (S-04)", function()
    -- since > os.time() should not produce a future startDate in the query.
    -- After fix: effective_since is upper-bounded at os.time().
    seed_token("org-s04b")
    local raw = Fixtures.load("purchases/purchases_empty")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local future_since = os.time() + 86400 * 365  -- 1 year in the future
    local ok = pcall(RefreshAccount,
      { accountNumber = "org-s04b", currency = "EUR", balance = 0 },
      future_since)
    assert.is_true(ok,
      "RefreshAccount must not crash when since is in the future (S-04)")
    -- With the cap, the purchase URL (first captured request) should NOT
    -- contain a future year. The Finance API end= param naturally contains
    -- the current year so we must inspect the purchase URL specifically.
    local url = Mocks._captured_requests[1] and Mocks._captured_requests[1].url or ""
    local future_year = tostring(os.date("!%Y", future_since))
    assert.is_falsy(url:find(future_year, 1, true),
      "purchase startDate must not be a future date when since is in the future (S-04), url: " .. url)
  end)

end)

-- ---------------------------------------------------------------------------
-- Phase-4 RefreshAccount integration tests (Plan 04-03)
-- Covers: ACCT-03 (balance + pendingBalance), REF-02 (refund in-window lookup
-- via purchases_by_uuid), FEE-01 (per-sale fee linkage via payments_by_uuid),
-- FEE-03 (D-49 Option B aggregate fallback), PAYOUT-01/02 (payout mapping),
-- SALE-03 (D-56 promotion via temporal-inference covering payout), ERR-06
-- (fail-whole-refresh on either Finance API leg error).
-- ---------------------------------------------------------------------------
-- luacheck: globals RefreshAccount LocalStorage M_i18n JSON M_auth
describe("RefreshAccount Phase-4 pipeline (ACCT-03 / REF-02 / FEE-01-03 / PAYOUT-01-02 / SALE-03 / ERR-06)", function()

  local function load_artifact()
    local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
    if not ok or code ~= 0 then
      error("entry_spec phase-4: failed to build dist/paypal-pos.lua")
    end
    dofile("dist/paypal-pos.lua")
  end

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

  -- queue_refresh(purchase_fixture, finance_fixture, opts)
  -- Queues the FOUR responses a Phase-4 RefreshAccount consumes:
  --   1) purchase fixture
  --   2) liquid balance fixture (default: finance_balance_liquid)
  --   3) preliminary balance fixture (default: finance_balance_preliminary)
  --   4) finance transactions fixture
  local function queue_refresh(purchase_fixture, finance_fixture, opts)
    opts = opts or {}
    Mocks.push_response({ content = Fixtures.load("purchases/" .. purchase_fixture) })
    Mocks.push_response({
      content = opts.liquid_raw or Fixtures.load("finance/finance_balance_liquid"),
    })
    Mocks.push_response({
      content = opts.preliminary_raw or Fixtures.load("finance/finance_balance_preliminary"),
    })
    Mocks.push_response({ content = Fixtures.load("finance/" .. finance_fixture) })
  end

  -- -------------------------------------------------------------------------
  -- ACCT-03 — balance + pendingBalance populated from Finance API
  -- -------------------------------------------------------------------------

  it("ACCT-03: result.balance and result.pendingBalance populate from Finance API balance fixtures", function()
    seed_token("org-acct03")
    queue_refresh("purchase_simple_sale", "finance_empty")
    local result = RefreshAccount(
      { accountNumber = "org-acct03", currency = "EUR", balance = 0 }, 0)
    assert.is_table(result)
    assert.equals(123.45, result.balance,
      "result.balance must come from finance_balance_liquid (12345 / 100)")
    assert.equals(6.78, result.pendingBalance,
      "result.pendingBalance must come from finance_balance_preliminary (678 / 100)")
  end)

  it("R-4: balance = nil fallback when liquid currency non-EUR; pendingBalance still EUR", function()
    seed_token("org-r4")
    -- Override liquid with GBP so the currency-guard fires and balance = nil.
    -- The fallback rule in entry.lua returns account.balance when account_state.balance is nil.
    queue_refresh("purchase_simple_sale", "finance_empty", {
      liquid_raw = '{"data": {"totalBalance": 9999, "currencyId": "GBP"}}',
    })
    local result = RefreshAccount(
      { accountNumber = "org-r4", currency = "EUR", balance = 42.00 }, 0)
    assert.is_table(result)
    assert.equals(42.00, result.balance,
      "non-EUR liquid -> fallback to account.balance (42.00)")
    assert.equals(6.78, result.pendingBalance,
      "EUR preliminary still populates when liquid is skipped")
  end)

  -- -------------------------------------------------------------------------
  -- REF-02 / D-50 — refund cites original purchaseNumber when both in window
  -- -------------------------------------------------------------------------

  it("REF-02: refund purpose cites original purchaseNumber when both in same purchases page (D-50)", function()
    seed_token("org-ref02")
    queue_refresh("purchase_refund_with_original_in_page", "finance_empty")
    local result = RefreshAccount(
      { accountNumber = "org-ref02", currency = "EUR", balance = 0 }, 0)
    assert.is_table(result)
    -- Two transactions expected: sale (purchaseNumber=4001) + refund (purchaseNumber=4002)
    assert.equals(2, #result.transactions,
      "expected 2 transactions (1 sale + 1 refund), got " .. tostring(#result.transactions))
    local refund_txn
    for _, t in ipairs(result.transactions) do
      if t.transactionCode:find("^zettle:refund:", 1, false) then
        refund_txn = t
      end
    end
    assert.is_not_nil(refund_txn, "refund transaction must be present")
    -- D-50: refund purpose must cite "Beleg #4001" (the ORIGINAL sale's purchaseNumber)
    assert.is_truthy(refund_txn.purpose:find("R\xc3\xbcckerstattung zu Beleg #4001", 1, true),
      "refund purpose must cite original sale purchaseNumber #4001, got: " .. refund_txn.purpose)
  end)

  -- -------------------------------------------------------------------------
  -- FEE-01 — per-sale fee linkage via payments_by_uuid
  -- -------------------------------------------------------------------------

  it("FEE-01: fee linked via payments_by_uuid emits zettle:fee:<uuid> with originating receipt #", function()
    seed_token("org-fee01")
    queue_refresh("purchase_page_with_payments_for_fee_join", "finance_payment_with_fee_linkage")
    local result = RefreshAccount(
      { accountNumber = "org-fee01", currency = "EUR", balance = 0 }, 0)
    assert.is_table(result)
    -- Find the fee transaction by transactionCode prefix.
    local fee_txn
    for _, t in ipairs(result.transactions) do
      if type(t.transactionCode) == "string"
          and t.transactionCode:find("^zettle:fee:[^a]", 1, false)
          and not t.transactionCode:find("^zettle:fee:aggregate:", 1, false) then
        fee_txn = t
      end
    end
    assert.is_not_nil(fee_txn,
      "expected a per-sale zettle:fee:<uuid> transaction; got transactions: " ..
      table.concat((function()
        local codes = {}
        for _, t in ipairs(result.transactions) do
          codes[#codes + 1] = tostring(t.transactionCode)
        end
        return codes
      end)(), ", "))
    -- transactionCode = "zettle:fee:" .. originatingTransactionUuid
    assert.is_truthy(fee_txn.transactionCode:find("zettle:fee:cccccccc", 1, true),
      "fee transactionCode must use the originatingTransactionUuid cccccccc-..., got: " ..
      fee_txn.transactionCode)
    -- Purpose must cite originating sale's purchaseNumber 2001
    assert.is_truthy(fee_txn.purpose:find("Beleg #2001", 1, true),
      "fee purpose must cite originating purchaseNumber #2001, got: " .. fee_txn.purpose)
  end)

  -- -------------------------------------------------------------------------
  -- FEE-03 / D-49 Option B — date-aggregate fallback when any unlinked fee
  -- -------------------------------------------------------------------------

  it("FEE-03: D-49 Option B emits zettle:fee:aggregate:<date> when ANY fee on that date is unlinked", function()
    seed_token("org-fee03")
    -- The unlinked fee fixture has a single PAYMENT_FEE with no matching
    -- payments_by_uuid entry, so the whole date clusters into an aggregate.
    queue_refresh("purchase_simple_sale", "finance_payment_fee_unlinked")
    local result = RefreshAccount(
      { accountNumber = "org-fee03", currency = "EUR", balance = 0 }, 0)
    assert.is_table(result)
    -- Find the aggregate transaction
    local agg_txn
    local per_sale_fees = 0
    for _, t in ipairs(result.transactions) do
      if type(t.transactionCode) == "string" then
        if t.transactionCode:find("^zettle:fee:aggregate:", 1, false) then
          agg_txn = t
        elseif t.transactionCode:find("^zettle:fee:", 1, false) then
          per_sale_fees = per_sale_fees + 1
        end
      end
    end
    assert.is_not_nil(agg_txn,
      "expected a zettle:fee:aggregate:<date> transaction for the unlinked-fee date")
    assert.equals(0, per_sale_fees,
      "no per-sale zettle:fee:<uuid> transactions expected on a day that aggregates")
    -- The aggregate transactionCode anchors on the Berlin-local date
    -- (fixture timestamp 2026-06-15T14:00:00 UTC = 2026-06-15 Berlin local).
    assert.is_truthy(agg_txn.transactionCode:find("zettle:fee:aggregate:2026%-06%-15"),
      "aggregate transactionCode must anchor on 2026-06-15 (Berlin local), got: " ..
      agg_txn.transactionCode)
  end)

  -- -------------------------------------------------------------------------
  -- PAYOUT-01 / PAYOUT-02 — payout transaction mapped from finance_payout
  -- -------------------------------------------------------------------------

  it("PAYOUT-01/02: payout emits zettle:payout:<uuid> with name 'Auszahlung an Bankkonto', negative amount", function()
    seed_token("org-po")
    queue_refresh("purchase_simple_sale", "finance_payout")
    local result = RefreshAccount(
      { accountNumber = "org-po", currency = "EUR", balance = 0 }, 0)
    assert.is_table(result)
    local payout_txn
    for _, t in ipairs(result.transactions) do
      if type(t.transactionCode) == "string"
          and t.transactionCode:find("^zettle:payout:", 1, false) then
        payout_txn = t
      end
    end
    assert.is_not_nil(payout_txn, "expected a zettle:payout: transaction")
    assert.equals("Auszahlung an Bankkonto", payout_txn.name,
      "payout name must be 'Auszahlung an Bankkonto' (PAYOUT-02)")
    assert.is_true(payout_txn.amount < 0,
      "payout amount must be negative (PAYOUT-01: -150000 / 100 = -1500.00)")
    assert.equals(-1500.00, payout_txn.amount,
      "payout amount must be -1500.00 EUR from fixture")
  end)

  -- -------------------------------------------------------------------------
  -- SALE-03 / D-56 — sale promoted to booked=true on second refresh once a
  -- covering PAYOUT exists in the Finance API records
  -- -------------------------------------------------------------------------

  it("SALE-03 D-56: first refresh sale booked=false; second refresh w/ covering PAYOUT promotes booked=true", function()
    seed_token("org-sale03")
    -- Phase 1: queue purchase + balances + EMPTY finance.
    -- Sale must be booked=false (no Finance PAYMENT / PAYOUT linkage).
    -- The purchase_page_with_payments_for_fee_join fixture has
    -- payments[1].uuid = cccccccc-... which matches the finance fixture below.
    queue_refresh("purchase_page_with_payments_for_fee_join", "finance_empty")
    local r1 = RefreshAccount(
      { accountNumber = "org-sale03", currency = "EUR", balance = 0 }, 0)
    assert.is_table(r1)
    local sale1
    for _, t in ipairs(r1.transactions) do
      if t.transactionCode:find("^zettle:sale:", 1, false) then sale1 = t end
    end
    assert.is_not_nil(sale1, "first refresh must emit a sale transaction")
    assert.is_false(sale1.booked,
      "first refresh sale must be booked=false (no covering PAYOUT yet)")
    assert.is_nil(sale1.valueDate,
      "first refresh sale must have no valueDate (D-31 carry-over)")

    -- Phase 2: queue a second refresh whose finance fixture pairs the matching
    -- PAYMENT (originatingTransactionUuid = cccccccc-...) with a later PAYOUT.
    -- The temporal-inference rule (RESEARCH §4.2) promotes the sale.
    local finance_promotion_raw = [[{
      "data": [
        {
          "timestamp": "2026-06-04T12:00:00.000+0000",
          "amount": 479300,
          "originatorTransactionType": "PAYMENT",
          "originatingTransactionUuid": "cccccccc-cccc-cccc-cccc-cccccccccccc"
        },
        {
          "timestamp": "2026-06-06T08:00:00.000+0000",
          "amount": -479300,
          "originatorTransactionType": "PAYOUT",
          "originatingTransactionUuid": "ffffffff-ffff-ffff-ffff-fffffffffff2"
        }
      ]
    }]]
    Mocks.push_response({ content = Fixtures.load("purchases/purchase_page_with_payments_for_fee_join") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
    Mocks.push_response({ content = finance_promotion_raw })
    local r2 = RefreshAccount(
      { accountNumber = "org-sale03", currency = "EUR", balance = 0 }, 0)
    assert.is_table(r2)
    local sale2
    for _, t in ipairs(r2.transactions) do
      if t.transactionCode:find("^zettle:sale:", 1, false) then sale2 = t end
    end
    assert.is_not_nil(sale2, "second refresh must emit a sale transaction")
    assert.is_true(sale2.booked,
      "second refresh sale must be booked=true after promote_to_booked (D-56)")
    assert.is_number(sale2.valueDate,
      "second refresh sale must have a numeric valueDate after promotion")
    -- transactionCode must be byte-identical (idempotency anchor; D-39)
    assert.equals(sale1.transactionCode, sale2.transactionCode,
      "transactionCode must remain byte-identical across promotion (D-39 stability)")
  end)

  -- -------------------------------------------------------------------------
  -- BL-01 (REVIEW): SALE-03 promotion must convert Finance payment UTC
  -- timestamp to Berlin-local POSIX before passing as valueDate. Both
  -- bookingDate and valueDate on the promoted sale must use the SAME
  -- Berlin-local POSIX convention (D-36) — otherwise users see the value
  -- date displayed 1-2 hours earlier than the booking date (DST-dependent),
  -- and at 23:00 UTC during CEST the two fields fall on different calendar
  -- days. payout_to_transaction uses Berlin-local; promote_to_booked must match.
  -- -------------------------------------------------------------------------

  it("BL-01: promoted sale.valueDate uses Berlin-local POSIX (matches bookingDate convention)", function()
    seed_token("org-bl01")
    -- Phase 1 — empty finance, sale stays booked=false.
    queue_refresh("purchase_page_with_payments_for_fee_join", "finance_empty")
    RefreshAccount({ accountNumber = "org-bl01", currency = "EUR", balance = 0 }, 0)

    -- Phase 2 — finance fixture pairs PAYMENT + a single covering PAYOUT.
    -- The PAYMENT timestamp 2026-06-04T12:00:00Z is during CEST (+7200);
    -- Berlin-local POSIX should equal UTC+7200.
    local payment_utc_iso = "2026-06-04T12:00:00.000+0000"
    local payout_utc_iso  = "2026-06-06T08:00:00.000+0000"
    local finance_promotion_raw = [[{
      "data": [
        {
          "timestamp": "]] .. payment_utc_iso .. [[",
          "amount": 479300,
          "originatorTransactionType": "PAYMENT",
          "originatingTransactionUuid": "cccccccc-cccc-cccc-cccc-cccccccccccc"
        },
        {
          "timestamp": "]] .. payout_utc_iso .. [[",
          "amount": -479300,
          "originatorTransactionType": "PAYOUT",
          "originatingTransactionUuid": "ffffffff-ffff-ffff-ffff-fffffffffff2"
        }
      ]
    }]]
    Mocks.push_response({ content = Fixtures.load("purchases/purchase_page_with_payments_for_fee_join") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
    Mocks.push_response({ content = finance_promotion_raw })
    local r2 = RefreshAccount({ accountNumber = "org-bl01", currency = "EUR", balance = 0 }, 0)

    local sale2, payout2
    for _, t in ipairs(r2.transactions) do
      if t.transactionCode:find("^zettle:sale:", 1, false) then sale2 = t end
      if t.transactionCode:find("^zettle:payout:", 1, false) then payout2 = t end
    end
    assert.is_not_nil(sale2, "promoted sale must be present")
    assert.is_not_nil(payout2, "covering payout txn must be present")
    assert.is_true(sale2.booked, "sale must be promoted to booked=true")

    -- The covering PAYOUT timestamp is 2026-06-06T08:00:00Z.
    -- promote_to_booked should pass the PAYMENT's posix (timestamp_posix of
    -- PAYMENT, per entry.lua step 13: `covering.timestamp_posix`) — but actually
    -- entry.lua passes covering.timestamp_posix where `covering` IS the payout.
    -- So sale.valueDate should equal the Berlin-local POSIX of the PAYOUT timestamp.
    local payout_utc = M_mapping.parse_iso8601_utc(payout_utc_iso)
    assert.is_number(payout_utc, "payout UTC parse must succeed")
    local expected_valueDate = M_mapping.to_berlin_local_time(payout_utc)
    assert.equals(expected_valueDate, sale2.valueDate,
      "BL-01: sale.valueDate must be Berlin-local POSIX (UTC+offset); got "
      .. tostring(sale2.valueDate) .. " expected " .. tostring(expected_valueDate)
      .. " (diff seconds = " .. tostring((sale2.valueDate or 0) - expected_valueDate) .. ")")

    -- Defensive: bookingDate and valueDate must share the same time convention.
    -- payout_to_transaction sets valueDate=bookingDate (Berlin-local), so the
    -- sale's promoted valueDate should equal the payout txn's bookingDate too.
    assert.equals(payout2.bookingDate, sale2.valueDate,
      "BL-01: sale.valueDate must equal payout.bookingDate (both Berlin-local POSIX)")
  end)

  -- -------------------------------------------------------------------------
  -- S-06 (SEC MEDIUM): duplicate purchaseUUID1 on the same page must not
  -- silently overwrite the cross-refresh index. First-write-wins policy
  -- with a German WARN log so the user-trust failure (refund pointing at the
  -- wrong original sale) becomes observable in the log stream.
  -- -------------------------------------------------------------------------

  it("S-06: duplicate purchaseUUID1 logs a German WARN and applies first-write-wins", function()
    seed_token("org-s06a")
    -- Two purchases share purchaseUUID1; first has purchaseNumber 8001, second 8002.
    -- The third record is a refund pointing at the shared UUID — under first-write-wins,
    -- the refund must cite Beleg #8001 (the first-seen sale), not 8002.
    local purchases_raw = [[{
      "purchases": [
        {
          "purchaseUUID1": "dddddddd-dddd-dddd-dddd-dddddddddddd",
          "amount": 1000, "vatAmount": 0, "currency": "EUR",
          "timestamp": "2026-06-15T10:00:00.000+0000",
          "purchaseNumber": 8001, "refund": false, "refunded": false,
          "products": [], "payments": [], "groupedVatAmounts": {}
        },
        {
          "purchaseUUID1": "dddddddd-dddd-dddd-dddd-dddddddddddd",
          "amount": 2000, "vatAmount": 0, "currency": "EUR",
          "timestamp": "2026-06-15T11:00:00.000+0000",
          "purchaseNumber": 8002, "refund": false, "refunded": false,
          "products": [], "payments": [], "groupedVatAmounts": {}
        },
        {
          "purchaseUUID1": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
          "amount": -1000, "vatAmount": 0, "currency": "EUR",
          "timestamp": "2026-06-15T12:00:00.000+0000",
          "purchaseNumber": 8003, "refund": true, "refunded": false,
          "refundsPurchaseUUID1": "dddddddd-dddd-dddd-dddd-dddddddddddd",
          "products": [], "payments": [], "groupedVatAmounts": {}
        }
      ],
      "lastPurchaseHash": ""
    }]]
    Mocks.push_response({ content = purchases_raw })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_empty") })

    local result = RefreshAccount(
      { accountNumber = "org-s06a", currency = "EUR", balance = 0 }, 0)
    assert.is_table(result, "RefreshAccount must succeed despite duplicate UUID")

    -- WARN log must have been emitted for the duplicate.
    local saw_warn = false
    for _, line in ipairs(Mocks._captured_prints or {}) do
      if type(line) == "string"
          and line:find("WARN", 1, true)
          and line:find("purchaseUUID1", 1, true)
          and line:find("dddddddd", 1, true) then
        saw_warn = true
      end
    end
    assert.is_true(saw_warn,
      "S-06: must log a German WARN on duplicate purchaseUUID1; captured prints: "
      .. table.concat(Mocks._captured_prints or {}, " || "))

    -- First-write-wins: the refund's purpose must cite Beleg #8001, NOT #8002.
    local refund_txn
    for _, t in ipairs(result.transactions) do
      if type(t.transactionCode) == "string"
          and t.transactionCode:find("^zettle:refund:", 1, false) then
        refund_txn = t
      end
    end
    assert.is_not_nil(refund_txn, "refund txn must be emitted")
    assert.is_truthy(refund_txn.purpose:find("Beleg #8001", 1, true),
      "S-06 first-write-wins: refund must cite first-seen purchaseNumber 8001, got: "
      .. refund_txn.purpose)
    assert.is_falsy(refund_txn.purpose:find("Beleg #8002", 1, true),
      "S-06: refund must NOT cite the overwritten purchaseNumber 8002")
  end)

  -- -------------------------------------------------------------------------
  -- ERR-06 — fail-whole-refresh on Finance API leg errors
  -- -------------------------------------------------------------------------

  it("ERR-06: 500 on liquid balance call -> RefreshAccount returns error string (fail-whole-refresh)", function()
    seed_token("org-err06a")
    -- Queue purchase OK + non-JSON liquid (forces (nil, nil, raw) -> network err).
    -- Preliminary and finance transactions are NOT queued; they must never be called.
    Mocks.push_response({ content = Fixtures.load("purchases/purchase_simple_sale") })
    Mocks.push_response({ content = "this is not json" })
    local result = RefreshAccount(
      { accountNumber = "org-err06a", currency = "EUR", balance = 0 }, 0)
    assert.is_string(result, "must return error string on liquid balance failure")
    assert.is_truthy(#result > 0, "error string must be non-empty")
  end)

  it("ERR-06: 500 on Finance transactions call -> RefreshAccount returns error string", function()
    seed_token("org-err06b")
    Mocks.push_response({ content = Fixtures.load("purchases/purchase_simple_sale") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
    Mocks.push_response({ content = "this is not json either" })
    local result = RefreshAccount(
      { accountNumber = "org-err06b", currency = "EUR", balance = 0 }, 0)
    assert.is_string(result, "must return error string on Finance transactions failure")
    assert.is_truthy(#result > 0, "error string must be non-empty")
  end)

end)
