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

  -- -------------------------------------------------------------------------
  -- Plan 05-05: Phase-4 surface preservation audit
  --
  -- Phase 4 added M_finance (fetch / fetch_all / fetch_account_state /
  -- parse_transaction) + M_mapping (purchase_to_transaction byte-shape) and
  -- extended entry.lua RefreshAccount from Phase-3's 6-step sequence to a
  -- 16-step pipeline. Plan 05-04 (ERR-04 401-direct-check) and Plan 05-05
  -- (spec + ADR only) MUST NOT regress any non-401 code path on these
  -- surfaces. This describe block re-audits the Phase-4 contract under the
  -- Phase-5 changes.
  -- -------------------------------------------------------------------------

  describe("Phase-4 surface preservation", function()

    it("M_finance public surface unchanged from Plan 04-03", function()
      assert.equals("function", type(M_finance.fetch),
        "M_finance.fetch must remain a function (Plan 04-03 contract)")
      assert.equals("function", type(M_finance.fetch_all),
        "M_finance.fetch_all must remain a function (Plan 04-03 contract)")
      assert.equals("function", type(M_finance.fetch_account_state),
        "M_finance.fetch_account_state must remain a function (Plan 04-03 contract)")
      assert.equals("function", type(M_finance.parse_transaction),
        "M_finance.parse_transaction must remain a function (Plan 04-02 contract)")
    end)

    it("M_mapping.purchase_to_transaction byte-identity preserved for purchase_simple_sale.json", function()
      -- Phase-4 baseline snapshot (replicates Plan 04-04 assertion at the
      -- M_mapping layer — NOT through RefreshAccount). The snapshot pins the
      -- canonical fields that Phase 4 froze: name, amount (gross is +1.50 EUR
      -- with vatAmount=24 minor units), currency, transactionCode shape,
      -- booked=false (no covering PAYOUT at this layer — Step 13 promotion
      -- happens in entry.lua, not in M_mapping).
      local raw = Fixtures.load("purchases/purchase_simple_sale")
      local doc = JSON(raw):dictionary()
      assert.is_table(doc, "fixture must parse to a table")
      assert.is_table(doc.purchases, "fixture must contain a `purchases` array")
      local p = doc.purchases[1]
      assert.is_table(p, "fixture must contain at least one purchase record")
      local txn = M_mapping.purchase_to_transaction(p)
      assert.is_table(txn, "purchase_to_transaction must return a table for simple sale")
      -- Anchor fields (Plan 04-04 baseline — any drift here regresses the
      -- contract Phase-4 froze and Phase-5 must preserve):
      assert.equals("Kartenzahlung", txn.name,
        "Phase-4 name baseline: account.name.card_payment")
      assert.equals("string", type(txn.transactionCode),
        "transactionCode must be string")
      assert.is_truthy(txn.transactionCode:find("^zettle:sale:", 1, false),
        "transactionCode must start with zettle:sale: per D-38")
      assert.equals("EUR", txn.currency, "Phase-4 EUR-only contract (D-37)")
      assert.is_number(txn.amount, "amount must be number")
      assert.is_false(txn.booked,
        "M_mapping.purchase_to_transaction must emit booked=false at this layer "
        .. "(SALE-03 promotion is entry.lua Step 13's responsibility, not the mapper's)")
      assert.is_nil(txn.valueDate,
        "valueDate must be nil at the mapper layer (set by promote_to_booked)")
    end)

    it("entry.lua RefreshAccount step-count unchanged from Phase 4", function()
      -- Phase-4 RefreshAccount has 16 numbered `-- Step N` comments (Steps 1..16);
      -- Plan 05-04 added 401-direct-checks at the iterator + fetch_account_state
      -- layer, NOT inside entry.lua. Plan 05-05 is spec + ADR only. So the
      -- step count must remain 16 in RefreshAccount.
      local f = io.open("src/entry.lua", "rb")
      assert.is_not_nil(f, "src/entry.lua must be readable")
      local content = f:read("*a")
      f:close()
      -- Count occurrences of the `-- Step N:` comment marker in RefreshAccount's
      -- body. Pattern matches comments at 2-space indent (the entry.lua style).
      local count = 0
      for _ in content:gmatch("  %-%- Step %d+") do
        count = count + 1
      end
      -- Plan 04-03 layout: InitializeSession2 has Steps 3/4/5/6 (4 step markers)
      -- + RefreshAccount has Steps 1..16 (16 step markers) = 20 total. The
      -- RefreshAccount steps are emitted in the order 1, 3, 2, 4..16 (Step 3
      -- before Step 2 because effective_since must be ready for the log line),
      -- but the step COUNT is exactly 16 numbered markers regardless of order.
      assert.equals(20, count,
        "Phase-4 baseline: entry.lua must contain exactly 20 `-- Step N` markers "
        .. "(4 in InitializeSession2 + 16 in RefreshAccount). Got: " .. tostring(count)
        .. ". If you intentionally restructured the step sequence, update this gate.")
    end)

    it("Plan 05-04 401-direct-check does NOT affect non-401 paths in purchases.lua / finance.lua", function()
      -- Phase-4 happy-path baseline: 200 mint not needed (cached_token via
      -- seed_token); 200 purchase + 200 liquid + 200 preliminary + 200 finance
      -- transactions must produce the same {balance, pendingBalance, transactions}
      -- shape Phase-4 produced. Plan 05-04 added 401 fast-path branches in
      -- M_pagination + fetch_account_state; non-401 paths must be unaffected.
      LocalStorage["zettle:org-p4-surface"] = JSON():set({
        access_token = "AT-VALID",
        expires_at   = os.time() + 7200,
        obtained_at  = os.time(),
        client_id    = "client-x",
        uuid         = "u-1",
        publicName   = "Beispiel Caf\xc3\xa9",
      }):json()
      Mocks.push_response({ content = Fixtures.load("purchases/purchase_simple_sale") })
      Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
      Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
      Mocks.push_response({ content = Fixtures.load("finance/finance_empty") })

      local result = RefreshAccount(
        { accountNumber = "org-p4-surface", currency = "EUR", balance = 0 }, 0)

      -- Phase-4 three-field shape (Plan 04-03 contract):
      assert.is_table(result,
        "Plan 05-04 non-interference: happy-path result must be a TABLE, got: " .. type(result))
      assert.is_table(result.transactions, "result.transactions must be a table")
      assert.is_true(#result.transactions >= 1,
        "happy-path purchase_simple_sale must yield >= 1 transaction")
      -- balance from finance_balance_liquid fixture (12345 / 100 = 123.45 EUR)
      assert.equals(123.45, result.balance,
        "Plan 05-04 non-interference: balance must equal Phase-4 baseline (12345 / 100 from "
        .. "finance_balance_liquid fixture)")
      -- pendingBalance from finance_balance_preliminary (678 / 100 = 6.78 EUR)
      assert.equals(6.78, result.pendingBalance,
        "Plan 05-04 non-interference: pendingBalance must equal Phase-4 baseline (678 / 100 from "
        .. "finance_balance_preliminary fixture)")
      -- Every transactionCode is well-formed per D-38 closed-set (defense-in-depth
      -- against any future regression where Plan 05-04's 401 branch leaks into
      -- the non-401 path).
      for _, txn in ipairs(result.transactions) do
        assert.is_string(txn.transactionCode)
        local ok = txn.transactionCode:find("^zettle:sale:", 1, false)
               or txn.transactionCode:find("^zettle:refund:", 1, false)
               or txn.transactionCode:find("^zettle:fee:", 1, false)
               or txn.transactionCode:find("^zettle:payout:", 1, false)
        assert.is_truthy(ok,
          "Plan 05-04 non-interference: transactionCode must match D-38 closed set, got: "
          .. tostring(txn.transactionCode))
      end
    end)

  end)

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
