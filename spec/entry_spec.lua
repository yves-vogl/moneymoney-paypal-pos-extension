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
    RefreshAccount({ accountNumber = "org-5", currency = "EUR", balance = 0 }, 0)
    local url = Mocks._last_request.url
    assert.truthy(url:find("startDate=", 1, true),
      "URL must include startDate query param, got: " .. tostring(url))
    -- The startDate must NOT be the epoch (1970-01-01); it must reflect the 90-day clamp.
    local ok = not url:find("startDate=1970", 1, true)
    assert.is_true(ok,
      "startDate must be clamped to ~90 days ago, not the epoch 1970: " .. url)
  end)

  it("RefreshAccount passes through recent since unchanged when newer than 90-day window (D-33)", function()
    seed_token("org-6")
    local raw = Fixtures.load("purchases/purchases_empty")
    Mocks.push_response({ content = raw })
    local recent = os.time() - 3600  -- 1 hour ago — well within 90 days
    RefreshAccount({ accountNumber = "org-6", currency = "EUR", balance = 0 }, recent)
    local url = Mocks._last_request.url
    assert.truthy(url:find("startDate=", 1, true),
      "URL must include startDate query param, got: " .. tostring(url))
    -- The year-month substring of the recent timestamp should appear in the URL.
    local recent_iso = os.date("!%Y-%m", recent)
    assert.truthy(url:find(recent_iso, 1, true),
      "URL must contain year-month " .. recent_iso .. " for recent since, got: " .. url)
  end)

  it("RefreshAccount preserves account.balance in return value (Phase 3 ACCT-03 not-yet-wired)", function()
    seed_token("org-7")
    local raw = Fixtures.load("purchases/purchases_empty")
    Mocks.push_response({ content = raw })
    local result = RefreshAccount({ accountNumber = "org-7", currency = "EUR", balance = 123.45 }, os.time() - 60)
    assert.is_table(result, "result must be a table")
    assert.equals(123.45, result.balance,
      "balance must be passed through unchanged (D-31: Finance API is Phase 4)")
  end)

  it("RefreshAccount returns string error on HTTP failure (ERR-06 fail-whole-refresh)", function()
    seed_token("org-8")
    -- Push a 429 response body so M_errors.from_http_status returns the German rate_limit string.
    Mocks.push_response({ content = '{"errorType":"RATE_LIMIT"}', status = 429 })
    local result = RefreshAccount({ accountNumber = "org-8", currency = "EUR", balance = 0 }, 0)
    -- The result must be an error string (not a table) — ERR-06 fail-whole-refresh.
    assert.is_string(result, "RefreshAccount must return an error string on HTTP failure (ERR-06)")
    assert.truthy(#result > 0, "error string must be non-empty")
  end)

end)
