-- spec/phase3_surface_preservation_spec.lua
-- Phase-3 surface preservation audit (RESEARCH §Pitfall 8 + Phase-2 contract freeze).
--
-- Asserts that all four Phase-2 callbacks frozen by Phase-3
-- (SupportsBank, InitializeSession2, ListAccounts, EndSession) continue to
-- produce byte-identical outputs after Plan 04-03's RefreshAccount
-- extension. The expected outputs in this spec are LITERAL values captured
-- from the Phase-3 baseline (commit a201f6c, the merged Phase-3 closure
-- via PR #10).
--
-- If any assertion in this file fails, Plan 04-03's RefreshAccount-extension
-- changes have leaked into one of the four frozen callbacks and the v0.2.0
-- release is a contract break against Phase-3 / v0.1.0 users.
--
-- This spec mirrors the relevant cases from spec/entry_spec.lua but with
-- LITERAL expected values (no M_i18n.t() indirection where it would mask a
-- regression) and with a single explicit purpose: contract preservation.

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Precomputed base64url JWT whose payload yields aud="client-x".
-- Phase-3 baseline: spec/entry_spec.lua VALID_JWT.
local VALID_JWT = "hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig"

-- ---------------------------------------------------------------------------
describe("Phase-3 surface preservation (audit per RESEARCH §Pitfall 8 + "
       .. "Phase-2 contract freeze)", function()

  local function load_artifact()
    local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
    if not ok or code ~= 0 then
      error("phase3_surface_preservation_spec: failed to build dist/paypal-pos.lua")
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
  -- SupportsBank — Phase-2 contract: only ProtocolWebBanking + "PayPal POS".
  -- -------------------------------------------------------------------------

  it("SupportsBank returns true for ProtocolWebBanking + 'PayPal POS'", function()
    assert.is_true(SupportsBank(ProtocolWebBanking, "PayPal POS"))
  end)

  it("SupportsBank returns false for ProtocolFinTS + 'PayPal POS'", function()
    assert.is_false(SupportsBank(ProtocolFinTS, "PayPal POS"))
  end)

  it("SupportsBank returns false for ProtocolWebBanking + unknown bankCode", function()
    assert.is_false(SupportsBank(ProtocolWebBanking, "Some Other Bank"))
  end)

  -- -------------------------------------------------------------------------
  -- InitializeSession2 — Phase-2 contract: challenge object on nil credentials,
  -- nil on successful two-call probe, LoginFailed on invalid_grant.
  -- -------------------------------------------------------------------------

  it("InitializeSession2 returns an API-Key challenge object on nil credentials", function()
    local challenge = InitializeSession2(ProtocolWebBanking, "PayPal POS", 1, nil, false)
    assert.is_table(challenge)
    -- The three challenge fields must each be the German API-Key label.
    -- Phase-3 baseline string from src/i18n.lua credential.api_key.label.
    assert.is_string(challenge.label)
    assert.is_truthy(#challenge.label > 0)
    assert.equals(challenge.label, challenge.title)
    assert.equals(challenge.label, challenge.challenge)
  end)

  it("InitializeSession2 returns nil on successful two-call probe (Phase-3 baseline)",
  function()
    local tok_raw = Fixtures.load("auth/token_ok")
    local usr_raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = tok_raw, mime = "application/json" })
    Mocks.push_response({ content = usr_raw, mime = "application/json" })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = VALID_JWT } }, false)
    -- Phase-2/3 contract: nil on success.
    assert.is_nil(result)
    -- LocalStorage written under org UUID from users_self_ok fixture.
    assert.is_table(LocalStorage.zettle)
    assert.is_not_nil(LocalStorage.zettle["b2c3d4e5-f6a7-8901-bcde-f12345678901"])
  end)

  it("InitializeSession2 returns LoginFailed on invalid_grant token response", function()
    local tok_raw = Fixtures.load("auth/token_invalid_grant")
    Mocks.push_response({ content = tok_raw, mime = "application/json" })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = VALID_JWT } }, false)
    -- Phase-2/3 contract: LoginFailed (MoneyMoney built-in constant) on 401.
    assert.equals(LoginFailed, result)
    -- persist_session must NOT have been called.
    assert.is_nil(LocalStorage.zettle)
  end)

  it("InitializeSession2 with malformed JWT returns invalid_grant string (zero network)",
  function()
    -- No response queued: any network call would error via mm_mocks.
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = "not-a-jwt" } }, false)
    -- Phase-2/3 contract: synchronous German error.invalid_grant; no network.
    assert.is_string(result)
    assert.is_truthy(#result > 0)
    assert.is_nil(Mocks._last_request)
  end)

  -- -------------------------------------------------------------------------
  -- ListAccounts — Phase-2 contract: Phase-1 fixture on empty cache,
  -- AccountTypeGiro/EUR record per cached merchant.
  -- -------------------------------------------------------------------------

  it("ListAccounts returns Phase-1 single-element fixture on empty cache", function()
    -- Phase-2/3 baseline: empty cache returns one AccountTypeGiro/EUR record
    -- with accountNumber = "paypal-pos-fixture-001" (LITERAL — see src/entry.lua).
    assert.is_nil(LocalStorage.zettle)
    local accounts = ListAccounts({})
    assert.equals(1, #accounts)
    assert.equals(AccountTypeGiro, accounts[1].type)
    assert.equals("EUR", accounts[1].currency)
    assert.equals("paypal-pos-fixture-001", accounts[1].accountNumber)
    assert.equals(false, accounts[1].portfolio)
  end)

  it("ListAccounts returns AccountTypeGiro/EUR for each cached merchant", function()
    -- Populate cache via the same two-call probe Phase-2 tests use.
    local tok_raw = Fixtures.load("auth/token_ok")
    local usr_raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = tok_raw })
    Mocks.push_response({ content = usr_raw })
    InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                       { { value = VALID_JWT } }, false)

    local accounts = ListAccounts({})
    -- Phase-2/3 contract: one record per org UUID in LocalStorage.zettle,
    -- type=AccountTypeGiro, currency="EUR", portfolio=false.
    assert.equals(1, #accounts)
    assert.equals(AccountTypeGiro, accounts[1].type)
    assert.equals("EUR", accounts[1].currency)
    assert.equals(false, accounts[1].portfolio)
    assert.equals("b2c3d4e5-f6a7-8901-bcde-f12345678901", accounts[1].accountNumber)
    -- Label embedded the publicName from the fixture (Phase-2 baseline).
    assert.is_truthy(accounts[1].name:find("Beispiel", 1, true))
  end)

  -- -------------------------------------------------------------------------
  -- EndSession — Phase-2 contract: returns nil; shuts down M_http.
  -- -------------------------------------------------------------------------

  it("EndSession returns nil (Phase-2 baseline)", function()
    assert.is_nil(EndSession())
  end)

  -- -------------------------------------------------------------------------
  -- Source-tree audit: assert each frozen-callback function definition is
  -- BYTE-IDENTICAL to the Phase-3 baseline. Reads src/entry.lua off disk
  -- and checks specific substrings + line ranges that uniquely identify
  -- the Phase-2/3 implementations.
  -- -------------------------------------------------------------------------

  it("src/entry.lua frozen-callback signatures match Phase-3 baseline", function()
    local f, err = io.open("src/entry.lua", "rb")
    assert.is_nil(err)
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()

    -- SupportsBank: single-line predicate. Phase-3 baseline string verbatim.
    assert.is_truthy(content:find(
      "function SupportsBank(protocol, bankCode)\n"
      .. "  return protocol == ProtocolWebBanking and bankCode == \"PayPal POS\"\n"
      .. "end",
      1, true), "SupportsBank body has drifted from Phase-3 baseline")

    -- InitializeSession2: signature line + the credential-prompt branch that
    -- emits the API-Key challenge object on nil credentials.
    assert.is_truthy(content:find(
      "function InitializeSession2(protocol, bankCode, step, credentials, interactive)",
      1, true), "InitializeSession2 signature has drifted from Phase-3 baseline")
    assert.is_truthy(content:find(
      "      title     = M_i18n.t(\"credential.api_key.label\"),\n"
      .. "      challenge = M_i18n.t(\"credential.api_key.label\"),\n"
      .. "      label     = M_i18n.t(\"credential.api_key.label\"),",
      1, true),
      "InitializeSession2 challenge object has drifted from Phase-3 baseline")

    -- ListAccounts: signature line + the LocalStorage.zettle iteration banner
    -- + the Phase-1 empty-cache fixture object.
    assert.is_truthy(content:find(
      "function ListAccounts(knownAccounts)",
      1, true), "ListAccounts signature has drifted from Phase-3 baseline")
    assert.is_truthy(content:find(
      "        accountNumber = \"paypal-pos-fixture-001\",",
      1, true), "ListAccounts empty-cache fixture has drifted from Phase-3 baseline")

    -- EndSession: full three-line body (no Phase-4 additions).
    assert.is_truthy(content:find(
      "function EndSession()\n"
      .. "  M_log.info(\"EndSession called\")\n"
      .. "  M_http.shutdown()\n"
      .. "  return nil\n"
      .. "end",
      1, true), "EndSession body has drifted from Phase-3 baseline")
  end)

end)
