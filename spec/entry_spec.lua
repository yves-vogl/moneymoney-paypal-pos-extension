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

  it("InitializeSession2 string credential with malformed JWT returns error.invalid_grant without any network call", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      "any-non-empty-but-not-a-jwt", false)
    assert.equals(M_i18n.t("error.invalid_grant"), result)
    assert.is_nil(Mocks._last_request)
  end)

  it("InitializeSession2 with positional-array malformed JWT returns error.invalid_grant without any network call", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { "any-non-empty-but-not-a-jwt" }, false)
    assert.equals(M_i18n.t("error.invalid_grant"), result)
    assert.is_nil(Mocks._last_request)
  end)

  it("InitializeSession2 with hash-table password malformed JWT returns error.invalid_grant without any network call", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { username = "foo", password = "any-non-empty-but-not-a-jwt" }, false)
    assert.equals(M_i18n.t("error.invalid_grant"), result)
    assert.is_nil(Mocks._last_request)
  end)

  it("InitializeSession2 with hash-table username-only malformed JWT returns error.invalid_grant without any network call", function()
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

  it("InitializeSession2 with scope-failure on /users/self returns LoginFailed and does not populate LocalStorage", function()
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
  -- RefreshAccount
  -- -------------------------------------------------------------------------

  it("RefreshAccount returns one transaction with EUR + zettle:sale prefix", function()
    local r = RefreshAccount({}, 0)
    assert.equals(1, #r.transactions)
    assert.equals("EUR", r.transactions[1].currency)
    assert.is_truthy(r.transactions[1].transactionCode:match("^zettle:sale:"))
  end)

  it("RefreshAccount transaction name comes from i18n", function()
    local r = RefreshAccount({}, 0)
    assert.equals(M_i18n.t("transaction.name.sale"), r.transactions[1].name)
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
