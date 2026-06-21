-- spec/refresh_log_redaction_spec.lua
-- Phase-3-specific gating spec: after a full RefreshAccount round-trip,
-- assert no JWT-shape pattern leaks into LocalStorage, the captured print
-- stream, or the returned transactionCode strings.
--
-- Gates:
--   (A) LocalStorage walk: no value matches `eyJ[A-Za-z0-9_-]+` (JWT-shape).
--   (B) Captured print stream: no line contains "Bearer " followed by a
--       non-whitespace run that matches a JWT segment (eyJ...).
--   (C) transactionCode prefix: every code emitted by RefreshAccount starts
--       with exactly "zettle:sale:" or "zettle:refund:" -- no other prefix.
--
-- These three invariants close the SEC-03 / D-29 / D-38 loop for the Phase-3
-- purchase pipeline. The Phase-2 log_redaction_spec.lua covers the auth path;
-- this file covers the RefreshAccount path introduced in Wave 4 (Plan 03-06).
--
-- Token strategy: seed_token() writes "AT-VALID" (no dots -> not JWT-shaped)
-- into the flat-fallback LocalStorage slot (D-23c / AUTH-06). This prevents
-- false positives when the SEC-03 walk looks for eyJ patterns -- AT-VALID
-- cannot match a three-segment JWT pattern.

-- luacheck: globals RefreshAccount LocalStorage M_i18n JSON
-- luacheck: ignore 431

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Build a fresh artifact once before the suite runs.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("refresh_log_redaction_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- Seed a valid non-JWT-shaped access token so M_auth.cached_token returns
-- "AT-VALID" without triggering the SEC-03 JWT pattern check.
local function seed_token(orgUuid)
  LocalStorage["zettle:" .. orgUuid] = JSON():set({
    access_token = "AT-VALID",
    expires_at   = os.time() + 7200,
    obtained_at  = os.time(),
    client_id    = "client-x",
    uuid         = "u-1",
    publicName   = "Test Haendler",
  }):json()
end

-- Recursive LocalStorage walker: calls visit(v) for every string value in t.
local function walk_storage(t, visit)
  for _, v in pairs(t) do
    if type(v) == "table" then
      walk_storage(v, visit)
    elseif type(v) == "string" then
      visit(v)
    end
  end
end

-- Plan 04-03: each RefreshAccount now consumes FOUR sequential responses
-- (purchase + liquid balance + preliminary balance + finance transactions).
-- Phase-3 redaction tests only care about the purchase pipeline; queue the
-- 3 trailing Finance API responses with empty/EUR fixtures so the new call
-- shape is satisfied without changing the gate semantics.
local function queue_finance_tail()
  Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
  Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
  Mocks.push_response({ content = Fixtures.load("finance/finance_empty") })
end

-- ---------------------------------------------------------------------------
describe("Phase-3 RefreshAccount: no JWT/Bearer leak and transactionCode prefix gate", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Gate A + B + C on the simple-sale happy path.
  -- -------------------------------------------------------------------------

  it("no JWT-shape in LocalStorage after RefreshAccount with purchase_simple_sale", function()
    seed_token("org-rs1")
    local raw = Fixtures.load("purchases/purchase_simple_sale")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    RefreshAccount({ accountNumber = "org-rs1", currency = "EUR", balance = 0 }, 0)

    -- Gate A: walk LocalStorage; no value may match the JWT-head pattern.
    walk_storage(LocalStorage, function(s)
      assert.is_falsy(s:find("eyJ[A-Za-z0-9_%-]+", 1, false),
        "LocalStorage value contains JWT-shape (eyJ...) after RefreshAccount: " .. s)
    end)
  end)

  it("no Bearer literal in captured prints after RefreshAccount with purchase_simple_sale", function()
    seed_token("org-rs2")
    local raw = Fixtures.load("purchases/purchase_simple_sale")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    RefreshAccount({ accountNumber = "org-rs2", currency = "EUR", balance = 0 }, 0)

    -- Gate B: captured print stream must never contain "Bearer eyJ..." pattern.
    for _, line in ipairs(Mocks._captured_prints) do
      -- The redactor should have already stripped any real token, but assert
      -- explicitly that no raw Bearer + JWT-shape substring survives.
      assert.is_falsy(line:find("Bearer eyJ", 1, true),
        "print line contains Bearer eyJ (unredacted Bearer + JWT): " .. line)
    end
  end)

  it("all transactionCodes start with zettle:sale: or zettle:refund: after purchase_simple_sale", function()
    seed_token("org-rs3")
    local raw = Fixtures.load("purchases/purchase_simple_sale")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local result = RefreshAccount({ accountNumber = "org-rs3", currency = "EUR", balance = 0 }, 0)

    assert.is_table(result, "result must be a table")
    assert.is_table(result.transactions, "result.transactions must be a table")
    assert.is_true(#result.transactions >= 1, "expected at least one transaction")

    -- Gate C: every transactionCode must have the correct prefix.
    for _, txn in ipairs(result.transactions) do
      local code = txn.transactionCode
      assert.is_string(code, "transactionCode must be a string, got: " .. tostring(code))
      local ok = code:find("^zettle:sale:", 1, false)
             or  code:find("^zettle:refund:", 1, false)
      assert.is_truthy(ok,
        "transactionCode must start with zettle:sale: or zettle:refund:, got: " .. tostring(code))
    end
  end)

  -- -------------------------------------------------------------------------
  -- Gate A + C on the refund path (D-32 / D-38).
  -- -------------------------------------------------------------------------

  it("no JWT-shape in LocalStorage after RefreshAccount with purchase_refund", function()
    seed_token("org-rs4")
    local raw = Fixtures.load("purchases/purchase_refund")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    RefreshAccount({ accountNumber = "org-rs4", currency = "EUR", balance = 0 }, 0)

    walk_storage(LocalStorage, function(s)
      assert.is_falsy(s:find("eyJ[A-Za-z0-9_%-]+", 1, false),
        "LocalStorage value contains JWT-shape after refund RefreshAccount: " .. s)
    end)
  end)

  it("refund transactionCodes start with zettle:refund: (D-32 / D-38)", function()
    seed_token("org-rs5")
    local raw = Fixtures.load("purchases/purchase_refund")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    local result = RefreshAccount({ accountNumber = "org-rs5", currency = "EUR", balance = 0 }, 0)

    assert.is_table(result, "result must be a table for refund fixture")
    assert.is_table(result.transactions, "result.transactions must be a table")
    assert.is_true(#result.transactions >= 1, "expected at least one refund transaction")

    -- Gate C: every code must have a valid prefix.
    local found_refund_prefix = false
    for _, txn in ipairs(result.transactions) do
      local code = txn.transactionCode
      assert.is_string(code)
      local ok = code:find("^zettle:sale:", 1, false)
             or  code:find("^zettle:refund:", 1, false)
      assert.is_truthy(ok,
        "transactionCode must start with zettle:sale: or zettle:refund:, got: " .. tostring(code))
      if code:find("^zettle:refund:", 1, false) then
        found_refund_prefix = true
      end
    end
    assert.is_true(found_refund_prefix,
      "expected at least one zettle:refund: code in refund fixture results")
  end)

  -- -------------------------------------------------------------------------
  -- Gate A + B on the VAT-and-tip path (covers purpose-field content for leaks).
  -- -------------------------------------------------------------------------

  it("no JWT-shape in LocalStorage after RefreshAccount with purchase_with_vat_and_tip", function()
    seed_token("org-rs6")
    local raw = Fixtures.load("purchases/purchase_with_vat_and_tip")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    RefreshAccount({ accountNumber = "org-rs6", currency = "EUR", balance = 0 }, 0)

    walk_storage(LocalStorage, function(s)
      assert.is_falsy(s:find("eyJ[A-Za-z0-9_%-]+", 1, false),
        "LocalStorage value contains JWT-shape after VAT/tip RefreshAccount: " .. s)
    end)
  end)

  it("no Bearer literal in captured prints after RefreshAccount with purchase_with_vat_and_tip", function()
    seed_token("org-rs7")
    local raw = Fixtures.load("purchases/purchase_with_vat_and_tip")
    Mocks.push_response({ content = raw })
    queue_finance_tail()
    RefreshAccount({ accountNumber = "org-rs7", currency = "EUR", balance = 0 }, 0)

    for _, line in ipairs(Mocks._captured_prints) do
      assert.is_falsy(line:find("Bearer eyJ", 1, true),
        "print line contains unredacted Bearer + JWT: " .. line)
    end
  end)

end)
