# Phase 3: Sale Spine — Pattern Map

**Mapped:** 2026-06-20
**Files analyzed:** 11 (5 source, 6 spec)
**Analogs found:** 10 / 11 (1 no-analog: `spec/dst_table_spec` absorbed into mapping_spec)

---

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `src/purchases.lua` | data-fetcher | request-response | `src/http.lua` (transport shape) + `src/auth.lua` (orchestration) | role-match |
| `src/pagination.lua` | utility / iterator | cursor (event-driven loop) | `src/http.lua` (repeat-until pattern) | partial-match |
| `src/mapping.lua` | pure mapper | transform | `src/auth.lua` (`_decode_jwt_payload`, `_extract_client_id` pure-function shape) | role-match |
| `src/entry.lua` (RefreshAccount only) | orchestrator | request-response | `src/entry.lua` InitializeSession2 (sequential two-call probe, fail-fast) | exact |
| `src/i18n.lua` (extend, 6 new keys) | config/locale | transform | `src/i18n.lua` existing STRINGS tables | exact |
| `spec/purchases_spec.lua` | spec | request-response | `spec/http_spec.lua` (Mocks.push_response, URL capture) | exact |
| `spec/pagination_spec.lua` | spec | cursor-loop | `spec/http_spec.lua` (mock-driven, multiple push_response) | role-match |
| `spec/mapping_spec.lua` | spec | transform | `spec/auth_spec.lua` (pure-logic, fixtures, no Mocks.push_response) | exact |
| `spec/refresh_idempotency_spec.lua` | spec (integration gate) | request-response | `spec/entry_spec.lua` (multi-stage integration, LocalStorage seeding) | exact |
| `spec/mapping_schema_spec.lua` | spec (invariant gate) | transform | `spec/log_redaction_spec.lua` walk-pattern + `spec/errors_spec.lua` table-driven assertions | role-match |
| `spec/fixtures/purchases/*.json` | fixture | — | `spec/fixtures/auth/*.json` (same Fixtures.load path, same dkjson decode) | exact |

---

## Pattern Assignments

### `src/purchases.lua` — data-fetcher, request-response

**Analogs:** `src/http.lua` (transport shape) + `src/auth.lua` (fetch_profile call shape)

**Module preamble pattern** — copy from `src/http.lua` lines 1–12:

```lua
-- src/purchases.lua
-- Ownership: SALE-01, SALE-06, D-33, D-42, D-43.
-- Provides: M_purchases.fetch(account, clamped_since, bearer) — single page GET
--           M_purchases.fetch_all(account, clamped_since, bearer) — drives pagination
-- The M_purchases table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02).
```

**Single GET call pattern** — copy shape from `src/auth.lua` lines 86–92 (`fetch_profile`):

```lua
-- src/auth.lua lines 86-92 — exact shape to copy for M_purchases.fetch:
function M_auth.fetch_profile(access_token)
  return M_http.get_json(
    "https://oauth.zettle.com/users/self",
    { Authorization = "Bearer " .. access_token }
  )
end
-- Phase 3: M_purchases.fetch builds the URL with query params, passes Bearer,
-- delegates to M_http.get_json. Returns (parsed_table|nil, status, raw).
```

**Error-check-then-continue pattern** — copy from `src/entry.lua` lines 57–59:

```lua
-- src/entry.lua lines 57-59 — use for each M_http.get_json call in purchases.lua:
local token_table, status, raw_body = M_auth.exchange_assertion(api_key, client_id)
local err = M_errors.from_http_status(status, raw_body)
if err then return err end
```

**`get_json` call pattern** — copy from `src/http.lua` lines 122–139:

```lua
-- src/http.lua lines 122-139 — the exact function Phase 3 calls for each page:
function M_http.get_json(url, headers)
  local conn = _get_connection()
  local h = _merge_headers(headers)
  M_log.debug("GET " .. url)  -- headers intentionally absent from log (Bearer safety)
  local raw, charset, mime, filename, resp_headers = -- luacheck: ignore 211
    conn:request("GET", url, nil, nil, h)
  raw = raw or ""
  M_log.debug("GET " .. url .. " response=" .. M_log.redact(raw))
  if #raw == 0 then
    return nil, nil, raw
  end
  local ok, parsed = pcall(function()
    return JSON(raw):dictionary()
  end)
  if not ok or type(parsed) ~= "table" then
    return nil, nil, raw
  end
  return parsed, M_http._infer_status(parsed), raw
end
-- Phase 3: M_purchases.fetch calls M_http.get_json — does NOT re-implement this.
-- pcall around JSON parse is inside get_json; purchases.lua never adds another.
```

---

### `src/pagination.lua` — utility, cursor loop

**No direct analog in codebase.** The nearest structural pattern is the sequential
multi-call flow in `src/entry.lua` InitializeSession2, but pagination uses a loop.
The RESEARCH.md Section 2a provides the recommended `repeat...until` shape.

**Loop-with-guard pattern** — draw from the multi-step sequencing in `src/entry.lua`
lines 57–88, adapted for a loop:

```lua
-- src/entry.lua lines 57-74 — sequential error-fail-fast, which the
-- pagination loop extends: each iteration checks err before continuing:
local token_table, status, raw_body = M_auth.exchange_assertion(api_key, client_id)
local err = M_errors.from_http_status(status, raw_body)
if err then return err end
-- ... guard against bad shape:
if type(token_table) ~= "table"
    or type(token_table.access_token) ~= "string"
    or #token_table.access_token == 0 then
  return M_i18n.t("error.invalid_grant")
end
-- Phase 3: each pagination iteration mirrors this: call fetch_page_fn,
-- check M_errors.from_http_status, check type(page.purchases) == "table",
-- then accumulate.
```

**Module-level constant pattern** — copy from `src/http.lua` line 12 (module-local state):

```lua
-- src/http.lua line 12 — module-local constant for MAX_PAGES guard:
local _conn = nil
-- Phase 3 analog:
local MAX_PAGES = 50
-- Declared at module scope (inside the do...end block), not inside the function.
```

**i18n error string pattern** — copy from `src/errors.lua` lines 17–19:

```lua
-- src/errors.lua lines 17-19 — use this exact call shape for bad-page error:
if status == nil then
  return M_i18n.t("error.network", "—")
end
-- Phase 3: if page shape is wrong: return nil, M_i18n.t("error.network", "bad_page")
```

---

### `src/mapping.lua` — pure mapper, transform

**Analog:** `src/auth.lua` pure-function helpers `_decode_jwt_payload` / `_extract_client_id`

**Pure-function shape** — copy from `src/auth.lua` lines 23–43:

```lua
-- src/auth.lua lines 23-43 — pure-function shape with nil-guard + pcall:
function M_auth._decode_jwt_payload(jwt)
  if type(jwt) ~= "string" or #jwt == 0 then return nil end
  local h, p, sig = jwt:match("^([^.]+)%.([^.]+)%.([^.]+)$")
  if not h or not p or not sig then return nil end
  local raw = _b64url_decode(p)
  if not raw or type(raw) ~= "string" or #raw == 0 then return nil end
  local ok, parsed = pcall(function()
    return JSON(raw):dictionary()
  end)
  if not ok or type(parsed) ~= "table" then return nil end
  return parsed
end
-- Phase 3 analog in mapping.lua:
-- M_mapping.purchase_to_transaction(p) is a pure function: takes p (table),
-- returns txn (table). Nil-guard every field access. No pcall needed
-- (JSON already decoded by M_http.get_json before this function is called).
```

**Priority-dispatch pattern** — copy from `src/auth.lua` lines 50–60 (`_extract_client_id`):

```lua
-- src/auth.lua lines 50-60 — priority-order dispatch (no else-if chain):
function M_auth._extract_client_id(jwt)
  local payload = M_auth._decode_jwt_payload(jwt)
  if not payload then return nil end
  local aud = payload.aud
  if type(aud) == "string" and #aud > 0 then return aud end
  if type(aud) == "table" and type(aud[1]) == "string" and #aud[1] > 0 then
    return aud[1]
  end
  local cid = payload.client_id
  if type(cid) == "string" and #cid > 0 then return cid end
  return nil
end
-- Phase 3 analog for _format_label (D-35):
-- priority 1: payments[1] and payments[1].attributes and attributes.cardType
-- priority 2: default "Kartenzahlung"
-- No else-if chain — same return-early style.
```

**Error-dispatch pattern** — copy from `src/errors.lua` lines 15–43:

```lua
-- src/errors.lua lines 15-43 — dispatch-on-value, return early, no else:
M_errors.from_http_status = function(status, body) -- luacheck: ignore body
  if status == nil then
    return M_i18n.t("error.network", "—")
  end
  if status >= 200 and status <= 299 then
    return nil
  end
  if status == 400 or status == 401 or status == 403 then
    return LoginFailed
  end
  if status == 429 then
    return M_i18n.t("error.rate_limit")
  end
  if status >= 500 and status <= 599 then
    return M_i18n.t("error.network", tostring(status))
  end
  return M_i18n.t("error.network", tostring(status))
end
-- Phase 3 analog for cardType brand-map dispatch in _format_label:
-- each recognized brand string is a separate if-return. Unknown falls through.
```

**Private helper scoping pattern** — copy from `src/auth.lua` lines 11–21 (`_b64url_decode`):

```lua
-- src/auth.lua lines 11-21 — module-private function, local to do...end block:
local function _b64url_decode(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("-", "+"):gsub("_", "/")
  local pad = (4 - (#s % 4)) % 4
  s = s .. string.rep("=", pad)
  return MM.base64decode(s)
end
-- Phase 3: _format_amount, _format_purpose, _format_label, _to_berlin_local_time
-- are ALL declared as `local function` inside the do...end block — never on M_mapping.
-- Only M_mapping.purchase_to_transaction and M_mapping.refund_to_transaction are public.
```

---

### `src/entry.lua` — RefreshAccount rewire only

**Analog:** `src/entry.lua` InitializeSession2 sequential probe (same file, lines 56–88)

**Sequential orchestration pattern** — copy from `src/entry.lua` lines 56–88:

```lua
-- src/entry.lua lines 56-88 — sequential fail-fast orchestration to copy:
-- Step 4 (D-21 leg 1): POST /token
local token_table, status, raw_body = M_auth.exchange_assertion(api_key, client_id)
local err = M_errors.from_http_status(status, raw_body)
if err then return err end

if type(token_table) ~= "table"
    or type(token_table.access_token) ~= "string"
    or #token_table.access_token == 0 then
  return M_i18n.t("error.invalid_grant")
end

-- Step 5 (D-21 leg 2): GET /users/self
local profile, p_status, p_raw = M_auth.fetch_profile(token_table.access_token)
local p_err = M_errors.from_http_status(p_status, p_raw)
if p_err then return p_err end
-- Phase 3 RefreshAccount analog (D-41 flow):
--   step 1: orgUuid = account.accountNumber
--   step 2: bearer = M_auth.cached_token(orgUuid) → nil check → error.network
--   step 3: effective_since = math.max(since, os.time() - 90*86400)  [D-33]
--   step 4: purchases, err = M_purchases.fetch_all(account, effective_since, bearer)
--           if err then return err end
--   step 5: map each purchase → transaction via M_mapping.*
--   step 6: return { balance = account.balance, transactions = txns }
```

**luacheck ignore 431 pattern** — copy from `src/entry.lua` line 129:

```lua
-- src/entry.lua line 129 — callback arg shadowing annotation:
function RefreshAccount(account, since) -- luacheck: ignore 431
-- Phase 3 keeps this exact annotation on RefreshAccount.
```

**Return shape pattern** — copy from `src/entry.lua` lines 130–148 (existing fixture shape):

```lua
-- src/entry.lua lines 130-148 — return shape to replace with real pipeline:
function RefreshAccount(account, since) -- luacheck: ignore 431
  M_log.info("RefreshAccount called, since=" .. tostring(since))
  return {
    balance = 9.95,
    transactions = {
      {
        name           = M_i18n.t("transaction.name.sale"),
        amount         = 9.95,
        currency       = "EUR",
        bookingDate    = os.time(),
        valueDate      = os.time(),
        purpose        = M_i18n.t("purpose.gross", 9.95) ..  ...,
        bookingText    = M_i18n.t("transaction.name.sale"),
        booked         = true,
        transactionCode = "zettle:sale:fixture-0001",
      },
    },
  }
end
-- Phase 3 replaces the fixture body. The outer shape
-- { balance = ..., transactions = {...} } is the MoneyMoney contract — keep it.
-- D-31: every Phase-3 transaction uses booked = false, no valueDate.
```

---

### `src/i18n.lua` — extend STRINGS tables (6 new keys)

**Analog:** `src/i18n.lua` existing STRINGS tables (same file, lines 5–38)

**Key addition pattern** — copy from `src/i18n.lua` lines 5–38:

```lua
-- src/i18n.lua lines 5-38 — add new keys alongside existing ones, same format:
local STRINGS = {
  de = {
    ["account.name"]              = "PayPal POS — %s",
    ["transaction.name.sale"]     = "Kartenzahlung",
    -- ... existing keys ...
    ["purpose.gross"]             = "Brutto %.2f EUR",  -- EXISTING (%.2f, float)
    ["purpose.vat_line"]          = "USt %d%%: %.2f EUR",
    ["purpose.tip"]               = "Trinkgeld: %.2f EUR",
    -- Phase 3 additions use %s (pre-formatted by _format_amount helper):
    -- ["account.purpose.gross"]         = "Brutto: %s €",
    -- ["account.purpose.vat"]           = "MwSt: %s €",
    -- ["account.purpose.tip"]           = "Trinkgeld: %s €",
    -- ["account.purpose.net"]           = "Netto: %s €",
    -- ["account.purpose.refund_for"]    = "Rückerstattung zu Beleg #%s",
    -- ["account.purpose.receipt_number"]= "Beleg #%s",
    -- ["account.name.card_payment"]     = "Kartenzahlung",
  },
  en = {
    -- same keys in English (technical-contributor fallback)
  },
}
-- IMPORTANT: existing keys ("purpose.gross" etc.) use %.2f for floats.
-- Phase 3 keys use %s because _format_amount pre-formats with comma separator.
-- Do NOT change existing key formats — only add the new "account.purpose.*" keys.
```

**`M_i18n.t` call pattern** — copy from `src/i18n.lua` lines 44–52:

```lua
-- src/i18n.lua lines 44-52 — the only public surface; mapping.lua calls it like this:
M_i18n.t = function(key, ...)
  local template = (STRINGS[LOCALE] and STRINGS[LOCALE][key])
               or STRINGS.en[key]
               or key
  if select("#", ...) > 0 then
    return string.format(template, ...)
  end
  return template
end
-- Phase 3 usage in mapping.lua:
--   M_i18n.t("account.purpose.gross", _format_amount(purchase.amount))
--   M_i18n.t("account.name.card_payment")
```

---

### `spec/purchases_spec.lua` — HTTP mock spec

**Analog:** `spec/http_spec.lua` — Mocks.push_response, URL capture via Mocks._last_request

**Suite preamble pattern** — copy from `spec/http_spec.lua` lines 1–44:

```lua
-- spec/http_spec.lua lines 1-44 — exact preamble to replicate:
local Mocks = require("spec.helpers.mm_mocks")

do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("http_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

describe("M_http", function()
  before_each(function()
    Mocks.setup()
    load_artifact()
  end)
  after_each(function()
    Mocks.teardown()
  end)
  -- ...
end)
-- Phase 3: purchases_spec.lua uses identical preamble; error message changes
-- to "purchases_spec: failed to build..." and describe block to "M_purchases".
```

**URL + param capture assertion pattern** — copy from `spec/http_spec.lua` lines 58–84:

```lua
-- spec/http_spec.lua lines 58-84 — URL and body capture:
Mocks.push_response({ content = '{"purchases":[...],"lastPurchaseHash":null}' })
M_purchases.fetch(account, since, bearer)
assert.is_not_nil(Mocks._last_request, "expected a request to have been made")
assert.equals("https://purchase.izettle.com/purchases/v2", ...)
-- Phase 3 asserts startDate query param is present in the URL:
local url = Mocks._last_request.url
assert.is_not_nil(url:find("startDate=", 1, true),
  "URL must include startDate param")
```

**Fixture loading pattern** — copy from `spec/auth_spec.lua` lines 57–62:

```lua
-- spec/auth_spec.lua lines 57-62 — load fixture, push response:
local raw = Fixtures.load("auth/token_ok")
Mocks.push_response({ content = raw })
M_auth.exchange_assertion("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig", "client-x")
-- Phase 3 analog:
local raw = Fixtures.load("purchases/purchase_simple_sale")
Mocks.push_response({ content = raw })
local result, err = M_purchases.fetch(account, since, bearer)
```

---

### `spec/pagination_spec.lua` — cursor-loop mock spec

**Analog:** `spec/http_spec.lua` (multiple push_response in sequence)

**Multi-response queue pattern** — copy from `spec/entry_spec.lua` lines 122–128:

```lua
-- spec/entry_spec.lua lines 122-128 — queue two responses for one test:
local tok_raw = Fixtures.load("auth/token_ok")
local usr_raw = Fixtures.load("auth/users_self_ok")
Mocks.push_response({ content = tok_raw, mime = "application/json" })
Mocks.push_response({ content = usr_raw, mime = "application/json" })
local result = InitializeSession2(...)
-- Phase 3: pagination_spec queues page1 + page2 responses for a two-page fetch:
Mocks.push_response({ content = Fixtures.load("purchases/purchase_page1") })
Mocks.push_response({ content = Fixtures.load("purchases/purchase_page2") })
local all, err = M_pagination.iterate(fetch_fn, params)
assert.is_nil(err)
assert.equals(expected_count, #all)
```

**Empty response termination pattern** — copy from `spec/http_spec.lua` lines 138–143:

```lua
-- spec/http_spec.lua lines 138-143 — empty body → nil status:
Mocks.push_response({ content = "" })
local decoded, status, raw = M_http.post_form(...)
assert.is_nil(decoded)
assert.is_nil(status)
-- Phase 3 analog for pagination terminal:
Mocks.push_response({ content = Fixtures.load("purchases/purchases_empty") })
local all, err = M_pagination.iterate(fetch_fn, params)
assert.is_nil(err)
assert.equals(0, #all)  -- empty page terminates loop
```

---

### `spec/mapping_spec.lua` — pure-logic spec with fixtures

**Analog:** `spec/auth_spec.lua` — pure-function tests, no Mocks.push_response needed

**Pure-logic test pattern** — copy from `spec/auth_spec.lua` lines 175–196:

```lua
-- spec/auth_spec.lua lines 175-196 — pure-logic tests that call the function
-- directly with controlled input, no queued HTTP responses:
it("_decode_jwt_payload returns nil for nil input", function()
  assert.is_nil(M_auth._decode_jwt_payload(nil))
end)

it("_decode_jwt_payload returns table for valid JWT with aud claim", function()
  local result = M_auth._decode_jwt_payload("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig")
  assert.is_table(result)
  assert.equals("client-x", result.aud)
end)
-- Phase 3 analog in mapping_spec.lua:
it("purchase_to_transaction maps amount to EUR float", function()
  local _, fixture = Fixtures.load("purchases/purchase_simple_sale")
  local txn = M_mapping.purchase_to_transaction(fixture.purchases[1])
  assert.equals(fixture.purchases[1].amount / 100, txn.amount)
end)
```

**Fixture-driven table test pattern** — copy from `spec/auth_spec.lua` lines 243–261:

```lua
-- spec/auth_spec.lua lines 243-261 — fixture-driven field assertions:
it("persist_session writes both nested and flat cache entries", function()
  M_auth.persist_session(
    { access_token = "AT-1", expires_in = 7200 },
    { uuid = "user-1", organizationUuid = "org-1", publicName = "Beispiel Café" },
    "client-x"
  )
  assert.is_table(LocalStorage.zettle, "LocalStorage.zettle must be a table")
  assert.equals("AT-1", LocalStorage.zettle["org-1"].access_token)
end)
-- Phase 3: mapping_spec uses the same inline-table style for purchase inputs
-- when not using fixtures (e.g., for nil-guard tests).
```

**Fixtures.load two-return pattern** — copy from `spec/helpers/fixtures.lua` lines 19–34:

```lua
-- spec/helpers/fixtures.lua lines 19-34 — Fixtures.load returns (raw, decoded):
function Fixtures.load(name)
  local path = "spec/fixtures/" .. name .. ".json"
  local f, err = io.open(path, "r")
  if not f then
    error("fixtures.load: cannot open '" .. path .. "': " .. tostring(err))
  end
  local raw = f:read("*a")
  f:close()
  local decoded, _, decode_err = dkjson.decode(raw)
  if decode_err then
    error("fixtures.load: JSON decode error in '" .. path .. "': " .. tostring(decode_err))
  end
  return raw, decoded
end
-- Phase 3: spec callers use the two-return form:
--   local raw, fixture = Fixtures.load("purchases/purchase_simple_sale")
--   local p = fixture.purchases[1]   -- the first purchase object
-- The root fixture object wraps purchases in {"purchases": [...]} per D-44.
```

---

### `spec/refresh_idempotency_spec.lua` — integration gate spec

**Analog:** `spec/entry_spec.lua` — multi-stage integration, LocalStorage seeding

**LocalStorage-seeding pattern** — copy from `spec/entry_spec.lua` lines 270–288:

```lua
-- spec/entry_spec.lua lines 270-288 — seed LocalStorage directly for integration tests:
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
  -- ... then call the callback under test ...
end)
-- Phase 3 idempotency spec uses the FLAT cache path (D-23c) because
-- cached_token reads flat first in cross-restart scenario; seed as:
LocalStorage["zettle:org-1"] = JSON():set({
  access_token = "AT-VALID",
  expires_at   = os.time() + 7200,
  obtained_at  = os.time(),
  client_id    = "client-x",
}):json()
local account = { accountNumber = "org-1", currency = "EUR", balance = 0 }
```

**Double-call result comparison pattern** — copy from `spec/entry_spec.lua` lines 361–410 (EndSession + re-init pattern):

```lua
-- spec/entry_spec.lua lines 374-410 — two sequential calls to same callback:
InitializeSession2(..., VALID_JWT, ...)  -- first call
-- ... EndSession and restart simulation ...
local token = M_auth.cached_token(org)  -- second access of same data
assert.is_string(token)
-- Phase 3 idempotency spec analog:
local result1 = RefreshAccount(account, 0)
local result2 = RefreshAccount(account, 0)
assert.is_table(result1)
assert.is_table(result2)
-- Build set of codes from first run, assert all second-run codes are in set.
local seen = {}
for _, t in ipairs(result1.transactions) do seen[t.transactionCode] = true end
for _, t in ipairs(result2.transactions) do
  assert.is_true(seen[t.transactionCode] ~= nil,
    "NEW transactionCode on second refresh: " .. tostring(t.transactionCode))
end
```

---

### `spec/mapping_schema_spec.lua` — invariant gate spec

**Analogs:** `spec/log_redaction_spec.lua` walk-pattern + `spec/errors_spec.lua` table-driven

**Invariant walk pattern** — copy from `spec/log_redaction_spec.lua` lines 327–344:

```lua
-- spec/log_redaction_spec.lua lines 327-344 — walk every value asserting invariant:
local function walk(t, visit)
  for _, v in pairs(t) do
    if type(v) == "table" then
      walk(v, visit)
    elseif type(v) == "string" then
      visit(v)
    end
  end
end
walk(LocalStorage, function(s)
  assert.is_falsy(s:find(fake_jwt, 1, true), ...)
end)
-- Phase 3 analog in mapping_schema_spec:
local REQUIRED_FIELDS = {
  "name", "amount", "currency", "bookingDate",
  "purpose", "transactionCode", "booked"
}
local function assert_schema(txn, label)
  for _, field in ipairs(REQUIRED_FIELDS) do
    assert.is_not_nil(txn[field],
      label .. ": missing required field '" .. field .. "'")
  end
end
```

**Table-driven assertion pattern** — copy from `spec/errors_spec.lua` lines 44–113:

```lua
-- spec/errors_spec.lua lines 44-113 — one it() per case, same assertion shape:
it("nil status returns network string with dash placeholder", function()
  local result = M_errors.from_http_status(nil, "")
  assert.equals(M_i18n.t("error.network", "—"), result)
end)
it("200 returns nil", function()
  local result = M_errors.from_http_status(200, '{"access_token":"AT"}')
  assert.is_nil(result)
end)
-- Phase 3 analog in mapping_schema_spec: one it() per fixture type,
-- each calling assert_schema(txn, "<fixture_name>") + specific field checks:
it("purchase_simple_sale maps to a valid transaction schema", function()
  local _, fixture = Fixtures.load("purchases/purchase_simple_sale")
  local txn = M_mapping.purchase_to_transaction(fixture.purchases[1])
  assert_schema(txn, "simple_sale")
  assert.is_false(txn.booked, "Phase 3: booked must be false")
  assert.is_nil(txn.valueDate, "Phase 3: valueDate must be absent")
end)
```

---

### `spec/fixtures/purchases/*.json` — JSON fixtures

**Analog:** `spec/fixtures/auth/*.json` — same Fixtures.load path convention

**Fixture path convention** — from `spec/helpers/fixtures.lua` lines 19–23:

```lua
-- spec/helpers/fixtures.lua lines 19-23 — path interpolation:
local path = "spec/fixtures/" .. name .. ".json"
-- Phase 3 callers use:
--   Fixtures.load("purchases/purchase_simple_sale")
--   Fixtures.load("purchases/purchases_empty")
-- File lives at: spec/fixtures/purchases/purchase_simple_sale.json
```

**Root object shape** (from D-44 + RESEARCH Section 4):

```json
{
  "_source": "github.com/iZettle/api-documentation/purchase.adoc",
  "purchases": [ ... ],
  "lastPurchaseHash": "hash-abc"
}
```

All fixtures wrap purchases in `{"purchases": [...]}` matching actual API response shape.
`lastPurchaseHash` is present on page-1 fixtures, absent on terminal-page fixtures.
`purchases_empty.json` has `"purchases": []`.

---

## Shared Patterns

### Module preamble (applies to all three new `src/*.lua` files)

**Source:** `src/http.lua` lines 1–12 and `src/auth.lua` lines 1–9

```lua
-- src/http.lua lines 1-9:
-- src/http.lua
-- AUTH-02 / AUTH-05 / D-25 / Risk R-1 / Pitfall 1 ownership.
-- Provides: M_http.post_form, M_http.get_json, M_http.shutdown, ...
-- The M_http table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02: amalgamator resolves cross-module
-- refs at build time via the shared module-table globals).
```

Apply to `purchases.lua`, `pagination.lua`, `mapping.lua`:
- Line 1: `-- src/<module>.lua`
- Lines 2–5: ownership comment citing D-* decisions covered
- Line 6: "Provides: M_<name>.<function>(...)" for each public function
- Line 7: "The M_<name> table is predeclared in src/webbanking_header.lua."
- Line 8: "NO require() of sibling modules (D-02)."

### Error routing (applies to `purchases.lua` and `pagination.lua`)

**Source:** `src/errors.lua` lines 15–43 and `src/entry.lua` lines 57–59

```lua
-- src/entry.lua lines 57-59 — error routing idiom:
local token_table, status, raw_body = M_auth.exchange_assertion(api_key, client_id)
local err = M_errors.from_http_status(status, raw_body)
if err then return err end
```

Pattern: every M_http.get_json call returns `(parsed, status, raw)`. Always route
through `M_errors.from_http_status(status, raw)` before touching `parsed`. If
`err` is non-nil, return `nil, err` immediately.

### Log redaction (applies to `purchases.lua` and `entry.lua` RefreshAccount)

**Source:** `src/http.lua` lines 125–130

```lua
-- src/http.lua lines 125-130 — Bearer never in logs:
M_log.debug("GET " .. url)  -- headers intentionally absent from log (Bearer safety)
-- ...
M_log.debug("GET " .. url .. " response=" .. M_log.redact(raw))
```

Pattern: log the URL only (no headers). Pass raw body through `M_log.redact(raw)` before any DEBUG log. This is enforced by `M_http.get_json` itself — Phase 3 code in `purchases.lua` that calls `get_json` does not need to re-redact; only any additional log lines added at the purchases layer must use `M_log.redact`.

### luacheck annotations (applies to all `src/*.lua` modified files)

**Source:** `src/http.lua` line 98, `src/entry.lua` line 9

```lua
-- src/http.lua line 98 — ignore unused 5-tuple return values:
local raw, charset, mime, filename, resp_headers = -- luacheck: ignore 211
  conn:request(...)
-- src/entry.lua line 9 — callback arg shadowing:
function InitializeSession2(protocol, bankCode, step, credentials, interactive) -- luacheck: ignore 431
```

Apply `-- luacheck: ignore 431` to all MoneyMoney callback functions and any
inner functions that shadow outer variable names. Apply `-- luacheck: ignore 211`
to any 5-tuple destructuring where trailing values are unused.

### Spec preamble (applies to all new `spec/*.lua` files)

**Source:** `spec/http_spec.lua` lines 1–44

```lua
-- spec/http_spec.lua lines 11-44:
local Mocks = require("spec.helpers.mm_mocks")

do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("<spec_name>: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

describe("<subject>", function()
  before_each(function()
    Mocks.setup()
    load_artifact()
  end)
  after_each(function()
    Mocks.teardown()
  end)
end)
```

Specs that also use fixtures add: `local Fixtures = require("spec.helpers.fixtures")`
after the Mocks require. See `spec/auth_spec.lua` lines 13–14.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `src/pagination.lua` (cursor-loop body) | utility / iterator | cursor loop | No existing loop-driven iterator in codebase; closest structural analog is the sequential two-call probe in InitializeSession2, extended to a `repeat...until` |

For this file, use the RESEARCH.md Section 2a pseudocode as the implementation
reference. The surrounding module scaffolding (preamble, error routing, luacheck
annotations) copies directly from existing analogs as noted above.

---

## Metadata

**Analog search scope:** `src/*.lua`, `spec/*.lua`, `spec/helpers/*.lua`
**Files read:** 13 source/spec files + 1 helper
**Pattern extraction date:** 2026-06-20
**Manifest order (do not change):** `webbanking_header → log → errors → i18n → model → http → auth → pagination → purchases → payouts → balance → mapping → entry`
If `src/timezone.lua` is added, insert it between `balance` and `mapping`.
