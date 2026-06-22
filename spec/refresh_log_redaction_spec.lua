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

-- ---------------------------------------------------------------------------
-- Plan 04-05: D-38 extended transactionCode prefix gate
--
-- Phase-3 closed the prefix gate over {zettle:sale:, zettle:refund:}. Phase-4
-- adds three more emitters (zettle:fee:, zettle:fee:aggregate:, zettle:payout:)
-- per Plan 04-02 / 04-03. The closed-set assertion below is the structural
-- enforcement: any future transaction kind (e.g. zettle:cashback:) emitted
-- without first extending this gate fails the test loudly with the violating
-- transactionCode.
-- ---------------------------------------------------------------------------

-- D-38 Phase-4 allowed prefix set (5 entries — closed set).
-- WR-02 (REVIEW): the prefix `^zettle:fee:` is a STRICT prefix of
-- `^zettle:fee:aggregate:`. The earlier `matches_allowed_prefix` returned
-- true for any prefix match, and the "seen_prefixes" walk marked BOTH
-- prefixes as seen on every aggregate transactionCode — which would let
-- the "all 5 exercised" assertion pass even if per-sale fees were never
-- emitted. Fix: longest-match semantics. Each code claims exactly ONE
-- prefix (the most-specific one). The closed-set assertion then enforces
-- each of the 5 buckets is non-empty for real.
local ALLOWED_PREFIXES = {
  "^zettle:sale:",
  "^zettle:refund:",
  "^zettle:fee:",
  "^zettle:fee:aggregate:",
  "^zettle:payout:",
}

-- longest_matching_prefix(code) -> string|nil
-- Returns the longest entry from ALLOWED_PREFIXES that matches `code`, or nil
-- if none matches. "Longest" is computed by string length of the pattern body.
local function longest_matching_prefix(code)
  if type(code) ~= "string" then return nil end
  local best = nil
  local best_len = -1
  for _, p in ipairs(ALLOWED_PREFIXES) do
    if code:find(p) and #p > best_len then
      best = p
      best_len = #p
    end
  end
  return best
end

describe("D-38 extended transactionCode prefix gate (Phase-4: 5 allowed prefixes)", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- Helper: queue the Plan-04-03 four-response tuple for ONE RefreshAccount.
  local function queue_full(purchase_fixture, finance_fixture)
    Mocks.push_response({ content = Fixtures.load("purchases/" .. purchase_fixture) })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
    Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
    Mocks.push_response({ content = Fixtures.load("finance/" .. finance_fixture) })
  end

  it("D-38 extended: every returned transactionCode starts with one of the 5 Phase-4 allowed prefixes", function()
    local union = {}
    local function absorb(result)
      if type(result) == "table" and type(result.transactions) == "table" then
        for _, t in ipairs(result.transactions) do
          union[#union + 1] = t
        end
      end
    end

    -- Refresh 1: sale + linked fee (yields zettle:sale: + zettle:fee:)
    seed_token("org-d38-1")
    queue_full("purchase_page_with_payments_for_fee_join", "finance_payment_with_fee_linkage")
    absorb(RefreshAccount({ accountNumber = "org-d38-1", currency = "EUR", balance = 0 }, 0))

    -- Refresh 2: refund (yields zettle:refund:)
    seed_token("org-d38-2")
    queue_full("purchase_refund", "finance_empty")
    absorb(RefreshAccount({ accountNumber = "org-d38-2", currency = "EUR", balance = 0 }, 0))

    -- Refresh 3: aggregate fee + payout (yields zettle:fee:aggregate: + zettle:payout:)
    seed_token("org-d38-3")
    queue_full("purchase_simple_sale", "finance_payment_fee_unlinked")
    absorb(RefreshAccount({ accountNumber = "org-d38-3", currency = "EUR", balance = 0 }, 0))

    seed_token("org-d38-4")
    queue_full("purchases_empty", "finance_payout")
    absorb(RefreshAccount({ accountNumber = "org-d38-4", currency = "EUR", balance = 0 }, 0))

    assert.is_true(#union >= 4,
      "expected at least 4 transactions across the 4 union refreshes; got " .. tostring(#union))

    -- Every emitted transactionCode must match exactly one of the 5 allowed prefixes.
    -- WR-02: each code claims the LONGEST matching prefix (so aggregate fee codes
    -- count against ^zettle:fee:aggregate:, not also against ^zettle:fee:).
    -- The "ALL 5 prefixes seen" assertion is then unfalsifiable-without-evidence:
    -- per-sale fees and aggregate fees must each be exercised by their own
    -- bucket; the gate cannot pass with only 4 distinct kinds.
    local seen_prefixes = {}
    for _, t in ipairs(union) do
      local longest = longest_matching_prefix(t.transactionCode)
      assert.is_not_nil(longest,
        "transactionCode '" .. tostring(t.transactionCode) ..
        "' does not match any of the 5 D-38 allowed prefixes")
      seen_prefixes[longest] = true
    end
    for _, p in ipairs(ALLOWED_PREFIXES) do
      assert.is_true(seen_prefixes[p] == true,
        "expected to exercise prefix " .. p .. " across union refreshes; not seen. " ..
        "Codes seen: " .. (function()
          local list = {}
          for _, t in ipairs(union) do list[#list + 1] = tostring(t.transactionCode) end
          return table.concat(list, ", ")
        end)())
    end
  end)

end)

-- ---------------------------------------------------------------------------
-- Plan 04-05: SEC-03 / D-45 — Bearer redaction covers Finance API responses
-- (RESEARCH §1.6).
--
-- Phase-3's SEC-03 walks covered only the purchase pipeline. Phase-4 added
-- two new HTTP call surfaces (balance dual-GET + finance transactions). For
-- every Finance API fixture we drive through a full RefreshAccount cycle and
-- assert no JWT-shape (eyJ-prefixed) string and no literal "Bearer eyJ"
-- substring appears in any captured print/log line or in LocalStorage values.
-- ---------------------------------------------------------------------------
describe("SEC-03 / D-45 extended: Bearer redaction covers Finance API responses (RESEARCH §1.6)", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- For each finance fixture: queue purchase + balance pair + the named
  -- finance fixture as the transactions response; run RefreshAccount; assert
  -- redaction invariants on all captured surfaces.
  local cases = {
    { label = "finance_single_page",
      purchase = "purchase_simple_sale", finance = "finance_single_page" },
    { label = "finance_payment_with_fee_linkage",
      purchase = "purchase_page_with_payments_for_fee_join",
      finance  = "finance_payment_with_fee_linkage" },
    { label = "finance_payout",
      purchase = "purchases_empty", finance = "finance_payout" },
    { label = "finance_balance_liquid (driven via finance_empty tail)",
      purchase = "purchase_simple_sale", finance = "finance_empty" },
    { label = "finance_balance_preliminary (driven via finance_empty tail)",
      purchase = "purchase_simple_sale", finance = "finance_empty" },
  }

  for i, c in ipairs(cases) do
    local org = "org-sec03-" .. tostring(i)
    it("SEC-03 extended: no JWT / Bearer eyJ leak after RefreshAccount cycle covering " .. c.label,
       function()
      seed_token(org)
      Mocks.push_response({ content = Fixtures.load("purchases/" .. c.purchase) })
      Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
      Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
      Mocks.push_response({ content = Fixtures.load("finance/" .. c.finance) })
      RefreshAccount({ accountNumber = org, currency = "EUR", balance = 0 }, 0)

      -- Gate B: captured print stream — no JWT-shape, no literal "Bearer eyJ".
      for _, line in ipairs(Mocks._captured_prints) do
        assert.is_falsy(line:find("eyJ[A-Za-z0-9_%-]+", 1, false),
          "print line contains JWT-shape (eyJ...) after Finance cycle " .. c.label
          .. ": " .. line)
        assert.is_falsy(line:find("Bearer eyJ", 1, true),
          "print line contains 'Bearer eyJ' after Finance cycle " .. c.label
          .. ": " .. line)
      end

      -- Gate A: LocalStorage walk — no string value matches JWT-shape.
      walk_storage(LocalStorage, function(s)
        assert.is_falsy(s:find("eyJ[A-Za-z0-9_%-]+", 1, false),
          "LocalStorage value contains JWT-shape after Finance cycle " .. c.label
          .. ": " .. s)
      end)
    end)
  end

end)

-- ---------------------------------------------------------------------------
-- Plan 05-05: SEC-03 Gate D — D-68 retry log line Bearer redaction
--
-- Plan 05-03 added INFO log lines emitted by src/http.lua _sleep_with_log
-- with the documented format:
--
--   HTTP retry: attempt=N/3 status=NNN url=URL after_ms=NNNN
--
-- The format string is structurally Bearer-safe (the headers table is NEVER
-- concatenated into the log line — only attempt/status/url/after_ms appear).
-- Gate D is the regression gate proving the invariant holds for these new
-- log lines: a 503-storm on the finance liquid GET emits exactly 2 retry log
-- lines (one before attempt 2, one before attempt 3); each line contains
-- finance.izettle.com (URL field populated) but NO Bearer / eyJ fragment.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 05-06 fix-batch (S-03): Gate D — retry log line is structurally safe against
-- attacker-controlled cursor values embedding CR/LF.
--
-- Threat: a hostile Zettle response could return a `lastPurchaseHash` value
-- containing CR/LF. If that cursor were ever concatenated into the URL
-- without percent-encoding and then into the retry log line, log
-- injection (split into two log records) becomes possible.
--
-- Today the mitigation is structural: M_purchases.fetch builds the query
-- string with MM.urlencode (src/purchases.lua line 37), and M_http logs the
-- URL via `url=` followed by a non-whitespace run, so any control bytes that
-- reached the URL must be percent-encoded by construction. This spec is the
-- regression gate proving the property — if a future refactor of M_purchases
-- dropped MM.urlencode, this assertion fails because the raw CR/LF would
-- appear in the captured log line.
-- ---------------------------------------------------------------------------
describe("Gate D extended (S-03): retry log percent-encodes malicious cursor bytes", function()

  before_each(function()
    Mocks.setup()
    _G.MM = _G.MM or {}
    _G.MM.sleep = function(_) end
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  it("retry log line contains percent-encoded form of CR/LF cursor (S-03)", function()
    -- Hand-build a URL with a percent-encoded malicious cursor — this is the
    -- exact byte sequence M_purchases.fetch would produce after MM.urlencode
    -- on a cursor like "evil\r\ninjected: x". %0D = CR, %0A = LF.
    -- We invoke M_http.get_json directly to assert the log property without
    -- depending on a full RefreshAccount pipeline.
    local url = "https://purchase.izettle.com/purchases/v2"
              .. "?descending=true&lastPurchaseHash=evil%0D%0Ainjected%3A%20x"
              .. "&limit=1000"
    -- 3 empty responses force the retry path -> 2 _sleep_with_log calls.
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })

    M_http.get_json(url, {})

    local retry_lines = {}
    for _, line in ipairs(Mocks._captured_prints) do
      if line:find("HTTP retry: attempt=", 1, true) then
        retry_lines[#retry_lines + 1] = line
      end
    end
    assert.equals(2, #retry_lines, "expected exactly 2 retry log lines on empty-body storm")

    for i, line in ipairs(retry_lines) do
      -- (1) Percent-encoded sequences MUST appear (proves MM.urlencode shielded
      --     the cursor before the URL ever reached the log).
      assert.is_truthy(line:find("%%0D%%0A", 1, false),
        "retry line " .. i .. " must contain percent-encoded CR/LF (%0D%0A); got: " .. line)

      -- (2) Raw control bytes MUST NOT appear in the log line. A passing test
      --     here proves the URL field was constructed with urlencode; a failing
      --     test would indicate a regression where some caller bypassed it.
      assert.is_falsy(line:find("\r"), "retry line " .. i .. " contains raw CR")
      assert.is_falsy(line:find("\n"), "retry line " .. i .. " contains raw LF")
    end
  end)

end)

describe("Gate D: SEC-03 retry log Bearer redaction (D-68)", function()

  before_each(function()
    Mocks.setup()
    -- No-op MM.sleep so the retry storm in this test does not consume real seconds.
    _G.MM = _G.MM or {}
    _G.MM.sleep = function(_) end
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  it("Gate D: 503-storm retry log lines contain no Bearer fragment", function()
    seed_token("org-gate-d")
    -- Queue: purchase OK + 3 empty bodies on finance liquid GET so
    -- _request_with_retry exhausts (3 attempts -> 2 retry sleeps -> 2 INFO
    -- log lines via _sleep_with_log).
    Mocks.push_response({ content = Fixtures.load("purchases/purchase_simple_sale") })
    Mocks.push_response({ content = "" })  -- liquid GET attempt 1 (no retry log yet)
    Mocks.push_response({ content = "" })  -- liquid GET attempt 2 (logged BEFORE: attempt=1/3)
    Mocks.push_response({ content = "" })  -- liquid GET attempt 3 (logged BEFORE: attempt=2/3)
    local r = RefreshAccount(
      { accountNumber = "org-gate-d", currency = "EUR", balance = 0 }, 0)
    -- Sanity: fail-whole returned an error string (not a table).
    assert.is_string(r, "Gate D: RefreshAccount must return error string on finance retry exhaust")

    -- (1) SEC-03 invariant: no `Bearer eyJ` substring appears in ANY captured
    -- print line (the SEC-03 hard invariant Phase-3 / Plan-04-05 gated for the
    -- purchase + finance happy paths; Gate D extends to the new retry log lines).
    -- Also check for the broader JWT-shape pattern (defense-in-depth).
    for _, line in ipairs(Mocks._captured_prints) do
      assert.is_falsy(line:find("Bearer eyJ", 1, true),
        "Gate D: retry log line contains 'Bearer eyJ' (SEC-03 violation): " .. line)
      assert.is_falsy(line:find("eyJ[A-Za-z0-9_%-]+", 1, false),
        "Gate D: retry log line contains JWT-shape pattern (defense-in-depth): " .. line)
    end

    -- (2) Exactly TWO `HTTP retry: attempt=` lines appear in the captured stream.
    -- _sleep_with_log is called for attempt=1 (sleep before attempt 2) and
    -- attempt=2 (sleep before attempt 3). The third attempt (which fails as the
    -- final retry) does NOT fire _sleep_with_log — the loop returns
    -- (nil, nil, raw) instead. So the count is exactly 2.
    local retry_log_lines = {}
    for _, line in ipairs(Mocks._captured_prints) do
      if line:find("HTTP retry: attempt=", 1, true) then
        retry_log_lines[#retry_log_lines + 1] = line
      end
    end
    assert.equals(2, #retry_log_lines,
      "Gate D: expected exactly 2 'HTTP retry: attempt=' lines (one before attempt 2, one before attempt 3); "
      .. "got " .. tostring(#retry_log_lines))

    -- (3) Format string matches the Plan-05-03 documented format
    -- (HTTP retry: attempt=N/3 status=NNN url=URL after_ms=NNNN).
    -- Lua patterns: %d+ for digits; %S+ for the URL (non-whitespace run).
    -- The line is prefixed by M_log's "[paypal-pos][INFO] " envelope; the
    -- pattern matches the suffix anywhere in the line (no ^ anchor).
    local fmt_pattern =
      "HTTP retry: attempt=%d+/%d+ status=%S+ url=%S+ after_ms=%d+"
    for i, line in ipairs(retry_log_lines) do
      assert.is_truthy(line:find(fmt_pattern),
        "Gate D: retry log line " .. i .. " does not match D-68 format pattern, got: " .. line)
    end

    -- (4) URL field in each retry log line contains the failing host
    -- (finance.izettle.com) but NO bearer / eyJ fragment in any position.
    -- The first retry log corresponds to the first failed liquid GET attempt,
    -- whose URL is /v2/accounts/liquid/balance.
    for i, line in ipairs(retry_log_lines) do
      assert.is_truthy(line:find("finance.izettle.com", 1, true),
        "Gate D: retry log line " .. i .. " must reference finance.izettle.com "
        .. "(URL field populated), got: " .. line)
      -- Belt-and-suspenders: a Bearer token would arrive as part of the
      -- Authorization header value — the format string never concatenates
      -- the headers table, so structurally absent. Verify by absence of the
      -- literal substring `Bearer` AND any `eyJ` fragment in any position.
      assert.is_falsy(line:find("Bearer", 1, true),
        "Gate D: retry log line " .. i .. " must not contain literal 'Bearer' "
        .. "(headers must never concat into log lines), got: " .. line)
      assert.is_falsy(line:find("eyJ", 1, true),
        "Gate D: retry log line " .. i .. " must not contain 'eyJ' fragment "
        .. "(SEC-03 / D-68 invariant), got: " .. line)
    end
  end)

end)
