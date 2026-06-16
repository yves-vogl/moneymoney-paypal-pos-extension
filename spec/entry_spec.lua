-- spec/entry_spec.lua
-- Tests for the five MoneyMoney callbacks in src/entry.lua.
-- Coverage: walking-skeleton gate (SupportsBank, InitializeSession2,
--           ListAccounts, RefreshAccount, EndSession).
--
-- Loading strategy:
--   setup()      — rebuild the artifact once, dofile it (with mocks in place).
--   before_each  — reset mock capture buffers (no rebuild needed per test).
--   after_each   — teardown mocks.

local Mocks = require("spec.helpers.mm_mocks")

-- ---------------------------------------------------------------------------
describe("entry.lua callbacks", function()

  -- Build artifact and load it once for the whole suite.
  setup(function()
    local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
    if not ok or code ~= 0 then
      error("entry_spec: failed to build dist/paypal-pos.lua before suite")
    end
    Mocks.setup()
    dofile("dist/paypal-pos.lua")
  end)

  teardown(function()
    Mocks.teardown()
  end)

  before_each(function()
    -- Reset capture buffers without re-loading the artifact.
    Mocks._captured_prints = {}
    Mocks._captured_status = {}
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
  -- InitializeSession2
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

  it("InitializeSession2 returns nil on non-empty challenge credential (array form)", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = "any-non-empty" } }, false)
    assert.is_nil(result)
  end)

  it("InitializeSession2 accepts a string credential as well", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      "any-non-empty", false)
    assert.is_nil(result)
  end)

  it("InitializeSession2 accepts a positional array of strings", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { "any-non-empty" }, false)
    assert.is_nil(result)
  end)

  it("InitializeSession2 accepts a hash table with password key (default UI fallback)", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { username = "foo", password = "any-non-empty" }, false)
    assert.is_nil(result)
  end)

  it("InitializeSession2 accepts a hash table with only username (default UI fallback)", function()
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { username = "any-non-empty" }, false)
    assert.is_nil(result)
  end)

  -- -------------------------------------------------------------------------
  -- ListAccounts
  -- -------------------------------------------------------------------------

  it("ListAccounts returns one AccountTypeGiro with EUR", function()
    local accs = ListAccounts({})
    assert.equals(1, #accs)
    assert.equals(AccountTypeGiro, accs[1].type)
    assert.equals("EUR", accs[1].currency)
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
  -- EndSession
  -- -------------------------------------------------------------------------

  it("EndSession returns nil", function()
    assert.is_nil(EndSession())
  end)

end)
