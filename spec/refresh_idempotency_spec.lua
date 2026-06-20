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
  -- Seeds token, queues the fixture content twice (once per RefreshAccount
  -- call), runs both calls, and returns the two result tables.
  -- The fixture is queued twice so each call can perform one HTTP fetch.
  -- -------------------------------------------------------------------------
  local function refresh_with_fixture(fixture_name, orgUuid)
    seed_token(orgUuid)
    local raw = Fixtures.load("purchases/" .. fixture_name)
    -- Queue twice: once for the first RefreshAccount call, once for the second.
    Mocks.push_response({ content = raw })
    Mocks.push_response({ content = raw })
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
