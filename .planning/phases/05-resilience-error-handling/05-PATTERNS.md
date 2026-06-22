# Phase 5: Resilience & Error Handling — Pattern Map

**Mapped:** 2026-06-21
**Files analyzed:** 13 (5 src modified, 7 specs new/extended, 1 tool extended)
**Analogs found:** 10 / 13 strong; 3 genuinely-new patterns flagged

> **Planner note — Mocks helper gap:** D-65 ERR-05 ("network failures") asks for `Mocks.push_response(nil, "ENETDOWN")` semantics. The current `spec/helpers/mm_mocks.lua` `push_response` API (L92-105) takes a single `opts` table with `content`, `charset`, `mime`, `filename`, `headers` — there is **no** `(nil, error_string)` pair form, and the mock `conn:request` (L115-127) always returns the 5-tuple with `r.content`. CONTEXT D-65 implicitly requires an additive extension to the mocks helper (e.g. `Mocks.push_response({ raw = nil })` so the returned `raw` is nil ⇒ `M_http.get_json` hits its existing L130-132 empty-body branch ⇒ `M_errors.from_http_status(nil, ...)` returns `error.network "—"`). Plan 05-XX must allocate ~15 minutes to extend the mock + add this to the manifest of "Reusable Assets". Alternatively, queue an empty-string `content = ""` response — this already satisfies `nil status` via the existing `#raw == 0` branch and requires NO mocks change. Recommendation: prefer the second path (zero-touch on mocks).

---

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `src/http.lua` (EXTEND `get_json` + `post_form` with retry loop) | transport | request-response + retry-loop | `src/http.lua` `get_json` body itself (L122-140); `src/pagination.lua` `repeat...until` loop | **role-match** (loop body is new pattern) |
| `src/auth.lua` (ADD `M_auth.with_retry(orgUuid, callback)`) | orchestration wrapper | request-response + silent-remint | `src/auth.lua` `cached_token` + `exchange_assertion` (same file) | **role-match** (callback-wrapper is new) |
| `src/errors.lua` (EXTEND dispatch by 4 entries) | mapper / dispatcher | transform | `src/errors.lua` lines 15-43 (same file, additive) | **exact** |
| `src/i18n.lua` (ADD `error.token_revoked`) | config/locale | transform | `src/i18n.lua` `error.network` / `error.rate_limit` entries (same file) | **exact** |
| `src/entry.lua` (WRAP RefreshAccount + InitializeSession2 HTTP calls in `with_retry`) | orchestrator | request-response | `src/entry.lua` Phase-4 16-step `RefreshAccount` body (L139-435) | **exact** |
| `spec/errors_spec.lua` (EXTEND with 4 new mappings) | spec | transform | `spec/errors_spec.lua` table-driven `it()` blocks (L44-113) | **exact** |
| `spec/auth_spec.lua` (EXTEND with D-61 + D-64 cases) | spec | request-response | `spec/auth_spec.lua` `exchange_assertion` happy-path (L57-69) | **exact** |
| `spec/http_spec.lua` (EXTEND with retry + 429 + Retry-After) | spec | request-response | `spec/http_spec.lua` `post_form` 5-tuple + rate_limit fixture (L93-189) | **exact** |
| `spec/http_retry_spec.lua` (NEW) | spec | retry-loop | `spec/http_spec.lua` whole-file shape | **exact** (scaffolding); **new pattern** for retry assertions |
| `spec/refresh_fail_whole_spec.lua` (NEW; ERR-06 gate) | spec (integration gate) | request-response | `spec/refresh_idempotency_spec.lua` `seed_token` + `refresh_with_fixture` (L55-90) | **exact** |
| `spec/refresh_log_redaction_spec.lua` (EXTEND SEC-03 to retry log lines) | spec (invariant) | static-walk | `spec/refresh_log_redaction_spec.lua` Phase-4 prefix list + walk (same file) | **exact** |
| `tools/probe.lua` (ADD Q9 `MM.os.sleep` probe) | probe / one-off | request-response | `tools/probe.lua` Q4/Q5/Q8 blocks (same file, L64-106) | **exact** |
| `spec/helpers/mm_mocks.lua` (optional: support `nil`-raw responses) | test helper | infra | `spec/helpers/mm_mocks.lua` `push_response` (L79-105) | **exact** (recommendation: no change, queue `content = ""` instead — see planner note above) |

---

## Pattern Assignments

### `src/http.lua` — extend `get_json` + `post_form` with retry-with-backoff

**Analog (scaffolding):** `src/http.lua` `get_json` body (L122-140) — keep verbatim, wrap the `conn:request` call site in a retry loop.

**Existing transport pattern to wrap** (`src/http.lua` L122-140 verbatim — the WHOLE body becomes the per-attempt block):

```lua
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
```

**New pattern — retry-with-backoff wrapping the per-attempt block** (D-62 + D-63 — no direct analog; sketch shape):

```lua
-- module-private constants near top of src/http.lua (alongside L12 _conn):
local _MAX_ATTEMPTS       = 3                       -- D-62: 1 original + 2 retries
local _BACKOFF_SECONDS    = { 1, 2, 4 }             -- D-62: exponential base 2
local _RETRY_AFTER_CAP    = 60                      -- D-63: cap honoring Retry-After
local _RATE_LIMIT_DEFAULT = 30                      -- D-63: default when header absent

-- sleep dispatch (D-67 — Q9-pending; CI tests stub MM.os.sleep to no-op):
local function _sleep(seconds)
  if type(MM) == "table" and type(MM.os) == "table" and type(MM.os.sleep) == "function" then
    MM.os.sleep(seconds)
  else
    -- busy-wait fallback (Q9-confirmed-absent path; ADR-0005)
    local target = os.time() + seconds
    while os.time() < target do end
  end
end

-- _parse_retry_after(resp_headers) -> integer|nil
-- Hardening per Phase-4 _url_encode_query S-04/S-11 style: tonumber guard + cap.
local function _parse_retry_after(resp_headers)
  if type(resp_headers) ~= "table" then return nil end
  local raw = resp_headers["Retry-After"] or resp_headers["retry-after"]
  if raw == nil then return nil end
  local n = tonumber(raw)
  if type(n) ~= "number" or n ~= n or n < 0 then return nil end  -- NaN / negative guard
  if n > _RETRY_AFTER_CAP then n = _RETRY_AFTER_CAP end
  return math.floor(n)
end
```

**Per-attempt loop body** — extends the existing L126-127 conn:request site:

```lua
-- replace the single conn:request call with a retry loop:
local raw, charset, mime, filename, resp_headers
local last_status
for attempt = 1, _MAX_ATTEMPTS do
  raw, charset, mime, filename, resp_headers = conn:request("GET", url, nil, nil, h)
  raw = raw or ""
  -- Decide retry-or-not based on parsed status (same path as L133-139):
  local parsed_for_status
  if #raw > 0 then
    local ok, p = pcall(function() return JSON(raw):dictionary() end)
    if ok and type(p) == "table" then parsed_for_status = p end
  end
  last_status = parsed_for_status and M_http._infer_status(parsed_for_status) or nil
  -- D-62: 5xx -> retry (up to _MAX_ATTEMPTS)
  -- D-63: 429 -> single retry honoring Retry-After (no more)
  if last_status and last_status >= 500 and last_status <= 599 and attempt < _MAX_ATTEMPTS then
    M_log.info(string.format("HTTP retry: attempt=%d/%d status=%d url=%s after_ms=%d",
      attempt, _MAX_ATTEMPTS, last_status, url, _BACKOFF_SECONDS[attempt] * 1000))
    _sleep(_BACKOFF_SECONDS[attempt])
  elseif last_status == 429 and attempt == 1 then
    local wait = _parse_retry_after(resp_headers) or _RATE_LIMIT_DEFAULT
    M_log.info(string.format("HTTP retry: attempt=%d/%d status=429 url=%s after_ms=%d",
      attempt, _MAX_ATTEMPTS, url, wait * 1000))
    _sleep(wait)
  else
    break
  end
end
M_log.debug("GET " .. url .. " response=" .. M_log.redact(raw))
-- ... then fall through to the existing L130-139 parse-and-return tail unchanged.
```

**Inheritance reminders:**
- Bearer never logged (`headers` is NEVER concatenated into the retry-log line — only `url`).
- The new INFO log line is the ONLY new redaction surface; SEC-03 walk must cover it (`spec/refresh_log_redaction_spec.lua` extension).
- Apply the same retry loop to `post_form` (L90-114) by symmetry — only the verb + body args differ.

---

### `src/auth.lua` — add `M_auth.with_retry(orgUuid, callback)`

**Analogs:** `src/auth.lua` `cached_token` (L162-171) + `exchange_assertion` (L71-78) — same file, callable composition.

**Existing pure-helper shape to mirror for `with_retry` declaration** (`src/auth.lua` L162-171):

```lua
function M_auth.cached_token(orgUuid)
  local entry = _cache_read(orgUuid)
  if not entry or not entry.access_token then return nil end
  local now = os.time()
  if now >= (entry.expires_at or 0) - 60 then
    M_log.info("cached_token: expired for org=" .. tostring(orgUuid):sub(1, 8))
    return nil
  end
  return entry.access_token
end
```

**New pattern — silent-remint wrapper (D-64; no analog):**

```lua
-- M_auth.with_retry(orgUuid, callback)
--   orgUuid  : string — the merchant identifier used for cache lookup
--   callback : function(bearer) -> (result, status, raw)
--   returns  : (result, status, raw, err)
--
-- D-64 ERR-04 contract:
--   1. Resolve bearer via cached_token(orgUuid).
--   2. Invoke callback(bearer); inspect status.
--   3. If status == 401, perform ONE silent re-mint via exchange_assertion using
--      the cached client_id (read via _cache_read so the api_key is NOT required —
--      Phase 5 cannot recover the JWT assertion from cache per AUTH-05).
--      → Re-mint path: only feasible if LocalStorage holds api_key, which it
--        does NOT (SEC-03). Therefore the "silent re-mint" must come from a
--        cached refresh credential — but assertion grant has NO refresh token
--        (CLAUDE.md "Token TTL = 7200 s; no refresh token for assertion grant").
--   ⚠ PLANNER MUST RECONCILE: D-64 as written assumes a re-mint primitive that
--     the assertion-grant model cannot satisfy without re-prompting the user
--     for the API key. Options:
--     (a) Demote D-64 to "second-401 → error.token_revoked immediately, no
--         silent re-mint" (matches AUTH-05 / SEC-03 / CLAUDE.md assertion-grant
--         constraint). RECOMMENDED.
--     (b) Persist the api_key in LocalStorage (BREAKS SEC-03 — REJECT).
--     (c) Accept that ERR-04 always surfaces as error.token_revoked on the
--         FIRST 401 after token-cache hit (no retry possible). RECOMMENDED.
--   4. If recommendation (a)+(c) chosen: signature simplifies to a single
--      pass-through plus 401 → error.token_revoked mapping. Then `with_retry`
--      is really `with_401_remap`. The name in CONTEXT D-64 ("with_retry") is
--      misleading in that case; planner picks a clearer name.
function M_auth.with_retry(orgUuid, callback)
  local bearer = M_auth.cached_token(orgUuid)
  if not bearer then
    return nil, nil, nil, M_i18n.t("error.network", "\xe2\x80\x94")
  end
  local result, status, raw = callback(bearer)
  if status == 401 then
    -- Per reconciliation note above: no silent re-mint feasible under
    -- assertion-grant + SEC-03. Surface token_revoked immediately.
    M_log.info("with_retry: 401 after cached token for org=" ..
      tostring(orgUuid):sub(1, 8) .. " — surfacing error.token_revoked")
    return nil, status, raw, M_i18n.t("error.token_revoked")
  end
  return result, status, raw, nil
end
```

**Pattern inheritances** from `src/auth.lua` (same file):
- orgUuid privacy: log only first 8 chars (L167 `:sub(1, 8)`) — applies to the new INFO line.
- Module-local helper scoping: NEW `with_retry` is on the `M_auth` public table (parallel to `cached_token`); any sub-helpers are `local function` inside the do…end block (parallel to `_b64url_decode` L15-21).

---

### `src/errors.lua` — extend dispatch with 4 entries

**Analog:** `src/errors.lua` lines 15-43 (same file — additive extension).

**Existing dispatch to extend verbatim** (`src/errors.lua` L15-43):

```lua
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
```

**Phase-5 extensions (D-69)** — the existing dispatch already covers 429 (`error.rate_limit`), 5xx (`error.network`), nil (`error.network`), and 401 (`LoginFailed`). What Phase 5 actually adds is:

1. A NEW i18n key `error.token_revoked` (the other three — `error.rate_limit`, `error.server_busy`, `error.network` — need verification: only `error.rate_limit` + `error.network` exist in `src/i18n.lua` L41-42; `error.server_busy` is NOT present and CONTEXT D-62 says "error.server_busy" but the existing 5xx branch already routes to `error.network(<status>)`).

2. A reconciliation decision: either (a) introduce `error.server_busy` as a NEW key and split the 5xx branch ("after all retries exhausted → error.server_busy"; sub-budget 5xx without retry → error.network), OR (b) keep using `error.network(<status>)` for 5xx and skip the new key. **Recommendation: (b) — single source of truth, no behaviour change required at this layer.** The retry exhaustion happens INSIDE `M_http.get_json`; from `M_errors`' perspective the final 503 maps to `error.network "503"` unchanged.

3. A NEW dispatch branch for the post-mint 401 case — but per the reconciliation in `M_auth.with_retry` above, the 401-to-token_revoked translation happens at the `with_retry` layer, NOT inside `from_http_status` (because `from_http_status` cannot distinguish "401 from token mint" vs "401 from resource call"). So `M_errors.from_http_status` STAYS UNCHANGED at the 401 branch (still returns `LoginFailed`), and `with_retry` overrides to `error.token_revoked` at the resource-call layer.

**Net `M_errors` change:** ZERO new branches under recommendations (a)+(b)+(c) above. **D-69's "+4 entries" target shrinks to 0-1 entries.** Planner must adjudicate.

If the planner insists on D-69 verbatim, the new branches would be:

```lua
-- NEW (only if planner overrides recommendation):
if status == 503 then
  return M_i18n.t("error.server_busy")  -- distinct from generic 5xx
end
-- (rate_limit and network already covered; token_revoked is auth-layer)
```

---

### `src/i18n.lua` — extend STRINGS tables

**Analog:** `src/i18n.lua` `error.network` / `error.rate_limit` entries (L41-42 `de`, L79-80 `en`).

**Existing key shape to mirror** (`src/i18n.lua` L40-44):

```lua
["error.invalid_grant"]       = "Anmeldung fehlgeschlagen: API-Key wurde abgelehnt.",
["error.network"]             = "Netzwerkfehler: %s",
["error.rate_limit"]          = "Anfragelimit erreicht — bitte später erneut versuchen.",
["credential.api_key.label"]  = "API-Key",
```

**Phase-5 additions** — exactly mirror the format (German primary, English fallback). UTF-8 byte-escapes per Phase-3 convention (`src/i18n.lua` L25-31):

```lua
-- de table additions:
["error.token_revoked"]       = "Anmeldung verloren \xe2\x80\x94 bitte API-Key in MoneyMoney neu eintragen.",
-- optional (only if planner overrides M_errors recommendation):
-- ["error.server_busy"]         = "Server \xc3\xbcberlastet \xe2\x80\x94 bitte sp\xc3\xa4ter erneut versuchen.",

-- en table additions:
["error.token_revoked"]       = "Session lost \xe2\x80\x94 please re-enter your API key in MoneyMoney.",
-- optional:
-- ["error.server_busy"]         = "Server busy \xe2\x80\x94 please retry later.",
```

**Verification action for planner:** confirm in `src/i18n.lua` L41-42 + L79-80 that `error.rate_limit` + `error.network` exist (they do — verified). Only `error.token_revoked` is genuinely new; `error.server_busy` is conditional on D-69 reconciliation.

---

### `src/entry.lua` — wrap HTTP calls in `M_auth.with_retry`

**Analog:** `src/entry.lua` Phase-4 RefreshAccount body (L139-435) — same file; the existing fail-fast idiom is the wrap-target.

**Existing fail-fast call sites to wrap** (`src/entry.lua` L174-244):

```lua
-- Phase-4 sequential pattern — each fetch is bare; ERR-06 fail-whole already implicit:
local purchases, fetch_err = M_purchases.fetch_all(effective_since, bearer)
if fetch_err then return fetch_err end
-- ...
local account_state, state_err = M_finance.fetch_account_state(bearer)
if state_err then return state_err end
-- ...
local fin_records_raw, fin_err = M_finance.fetch_all(effective_since, bearer)
if fin_err then return fin_err end
```

**Phase-5 wrap pattern** — replace `bearer = M_auth.cached_token(orgUuid)` + bare fetches with `M_auth.with_retry`:

```lua
-- Step 2 (REPLACED): instead of cached_token + bare fetches, drive each fetch
-- through with_retry so a single post-mint 401 surfaces error.token_revoked
-- (D-64) without further code in the entry layer.
local purchases, _, _, fetch_err = M_auth.with_retry(orgUuid, function(bearer)
  return M_purchases.fetch_all(effective_since, bearer)
end)
if fetch_err then return fetch_err end

local account_state, _, _, state_err = M_auth.with_retry(orgUuid, function(bearer)
  return M_finance.fetch_account_state(bearer)
end)
if state_err then return state_err end

local fin_records_raw, _, _, fin_err = M_auth.with_retry(orgUuid, function(bearer)
  return M_finance.fetch_all(effective_since, bearer)
end)
if fin_err then return fin_err end
```

**InitializeSession2 wrap site** — `src/entry.lua` L62-79 (token mint + profile fetch). The token-mint itself CANNOT use `with_retry` (no cached token at mint time). The profile-ping (L77) is the candidate — but at that point the freshly-minted token IS the bearer, and there is no cache to consult yet. **Recommendation: do NOT wrap InitializeSession2 in with_retry; instead, rely on the M_http.get_json retry-with-backoff for the 5xx case (D-62 propagates transparently to the profile-ping).** CONTEXT bullet "InitializeSession2: the profile-ping uses the same retry semantics" is satisfied by the M_http extension alone — no entry.lua change.

**Inheritances** (`src/entry.lua` L139):
- Keep `-- luacheck: ignore 431` on the RefreshAccount signature.
- Keep all post-fetch logic (Steps 5-16) unchanged.
- Keep `M_log.info` orgUuid:sub(1,8) discipline (L159) — applies to any new log line in entry.lua.

---

### `spec/errors_spec.lua` — extend with new status-code mappings

**Analog:** `spec/errors_spec.lua` table-driven `it()` blocks (L44-113) — same file.

**Existing test shape to mirror** (`spec/errors_spec.lua` L86-90):

```lua
it("429 returns rate_limit string", function()
  local result = M_errors.from_http_status(429, "")
  assert.equals(M_i18n.t("error.rate_limit"), result)
end)
```

**Phase-5 additions** — for each new dispatch branch (per D-69 reconciliation above):

```lua
-- Only if error.server_busy branch is added per planner override of recommendation:
it("503 returns server_busy string", function()
  local result = M_errors.from_http_status(503, "")
  assert.equals(M_i18n.t("error.server_busy"), result)
end)
-- D-64 token_revoked: NOT tested here (it's surfaced by M_auth.with_retry, not from_http_status).
```

**Inheritances:**
- SEC-03 body-never-echoed invariant test (L119-127) MUST be re-run with any new branches (body parameter check applies to all branches uniformly).

---

### `spec/auth_spec.lua` — extend with D-61 + D-64 cases

**Analog:** `spec/auth_spec.lua` `exchange_assertion` happy-path (L57-69) — same file.

**Existing happy-path shape to mirror** (`spec/auth_spec.lua` L57-69):

```lua
it("exchange_assertion posts grant_type", function()
  local raw = Fixtures.load("auth/token_ok")
  Mocks.push_response({ content = raw })
  M_auth.exchange_assertion("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig", "client-x")
  -- ... assertions on Mocks._last_request ...
end)
```

**D-61 ERR-01 invalid_grant → LoginFailed** (verify Phase-2 already gates; if missing, add):

```lua
it("exchange_assertion 400 invalid_grant body surfaces LoginFailed via M_errors", function()
  local raw = Fixtures.load("auth/auth_invalid_grant")
  Mocks.push_response({ content = raw })
  local _, status, raw_body = M_auth.exchange_assertion("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig", "client-x")
  assert.equals(400, status)
  assert.equals(LoginFailed, M_errors.from_http_status(status, raw_body))
end)
```

**D-64 silent-401 path** (per reconciliation: 401 → error.token_revoked, no silent re-mint):

```lua
it("with_retry surfaces error.token_revoked on 401 from cached-token callback", function()
  -- Seed a valid cached bearer (no JWT shape, per refresh_log_redaction_spec pattern):
  LocalStorage["zettle:org-1"] = JSON():set({
    access_token = "AT-VALID", expires_at = os.time() + 7200,
    obtained_at  = os.time(), client_id = "client-x", uuid = "u-1",
  }):json()
  -- Callback returns 401 (status inferred from body shape per _infer_status):
  local result, status, _, err = M_auth.with_retry("org-1", function(bearer)
    return nil, 401, '{"error":"invalid_client"}'
  end)
  assert.is_nil(result)
  assert.equals(401, status)
  assert.equals(M_i18n.t("error.token_revoked"), err)
  -- And: error is NOT LoginFailed (the constant reserved for ERR-01 mint-time).
  assert.not_equals(LoginFailed, err)
end)
```

---

### `spec/http_spec.lua` — extend with retry + Retry-After fixtures

**Analog:** `spec/http_spec.lua` rate-limited fixture test (L177-189) — same file.

**Existing rate-limit pattern to extend** (`spec/http_spec.lua` L177-189):

```lua
it("post_form with rate_limited fixture returns 429 status (M-02)", function()
  local Fixtures = require("spec.helpers.fixtures")
  local raw = Fixtures.load("auth/token_rate_limited")
  Mocks.push_response({ content = raw, mime = "application/json" })
  local decoded, status, _ = M_http.post_form("https://oauth.zettle.com/token", { grant_type = "x" }, {})
  assert.is_table(decoded)
  assert.equals("rate_limit", decoded.error)
  assert.equals(429, status)
end)
```

**Phase-5 extensions** — queue multiple sequential responses, assert retry call count via `Mocks._captured_requests`:

```lua
it("get_json retries up to 3 times on 5xx then surfaces final status", function()
  -- Queue THREE 5xx responses (1 original + 2 retries) using body-shape inference.
  -- Risk R-1: status is inferred from body — push a body that _infer_status maps to 500-ish.
  -- The cleanest test signal: push three EMPTY bodies (#raw == 0 → nil status → network error).
  -- Then assert exactly 3 calls were made.
  Mocks.push_response({ content = "" })
  Mocks.push_response({ content = "" })
  Mocks.push_response({ content = "" })
  local _, status, _ = M_http.get_json("https://finance.izettle.com/test", {})
  assert.is_nil(status)
  -- WAIT: with empty body, _infer_status path is not reached (early return at L130-132).
  -- The retry logic must inspect the parsed status BEFORE the early return; planner verifies.
  assert.equals(3, #Mocks._captured_requests, "expected 3 HTTP attempts (1 + 2 retries)")
end)
```

> **Planner caveat:** Risk R-1 (`_infer_status` lives in body shape, not response headers) makes 5xx-fixture construction non-trivial. Three options:
> 1. Add a sentinel error body that `_infer_status` recognises as 5xx (extend the function — additive).
> 2. Use the empty-body branch as the retry trigger (interpret "nil status" as "retry candidate").
> 3. Stub `MM.os.sleep` so the test runs in zero wall time, and queue 3 empty bodies (option 2 implicitly).
>
> Recommendation: **option 1** — extend `_infer_status` to recognise `{"error":"server_busy"}` → 503 and add a fixture `spec/fixtures/auth/server_busy.json`. Cleanest contract.

**Retry-After parse hardening** — test pattern per `_url_encode_query` adversarial S-04/S-11 style (analogous to Phase-4 hardening in `src/purchases.lua` per 04-PATTERNS):

```lua
it("_parse_retry_after caps absurdly-large values at 60s", function()
  -- direct call to the module-private helper would require exposing it on M_http.
  -- Alternative: queue a 429 with Retry-After=99999 and assert sleep was called with 60.
  -- (Requires _sleep to be a module-private spy-able function — see Plan 05-XX.)
end)
```

---

### `spec/http_retry_spec.lua` (NEW) — dedicated retry semantics spec

**Analog (scaffolding):** `spec/http_spec.lua` whole-file shape (L1-44 preamble; L37-44 describe block; before_each/after_each pattern).

**Preamble verbatim** (copy from `spec/http_spec.lua` L1-44; substitute file name):

```lua
local Mocks = require("spec.helpers.mm_mocks")
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("http_retry_spec: failed to build dist/paypal-pos.lua before suite")
  end
end
local function load_artifact()
  dofile("dist/paypal-pos.lua")
end
describe("M_http retry-with-backoff (Phase 5 / D-62 / D-63)", function()
  before_each(function()
    Mocks.setup()
    -- IMPORTANT: stub MM.os.sleep to no-op so tests don't wait for real seconds.
    _G.MM.os = _G.MM.os or {}
    _G.MM.os.sleep = function(_) end
    load_artifact()
  end)
  after_each(function()
    Mocks.teardown()
  end)
  -- it() blocks ...
end)
```

**Test cases** (per D-62/D-63):
- 5xx → 5xx → 200 → returns the 200 result (2 retries succeeded).
- 5xx → 5xx → 5xx → returns the final error (3 attempts exhausted; `error.network "<status>"`).
- 429 with `Retry-After: 5` → retried once after 5s sleep (`MM.os.sleep` stub captures arg).
- 429 with no `Retry-After` → retried once after 30s default.
- 429 with `Retry-After: 9999` → capped at 60s.
- 429 with `Retry-After: "abc"` → tonumber returns nil → fallback to 30s default.
- 429 twice in a row → single retry only (no infinite backoff per D-63).
- 200 first attempt → no sleep, no retry log line.

---

### `spec/refresh_fail_whole_spec.lua` (NEW) — ERR-06 gating spec

**Analog:** `spec/refresh_idempotency_spec.lua` `seed_token` (L55-64) + `refresh_with_fixture` (L80-90) + double-call pattern (entire file). Same-file pattern; copy-and-adapt.

**Preamble verbatim** (copy `spec/refresh_idempotency_spec.lua` L1-45 substituting file name and describe label):

```lua
local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("refresh_fail_whole_spec: failed to build dist/paypal-pos.lua before suite")
  end
end
local function load_artifact() dofile("dist/paypal-pos.lua") end

describe("RefreshAccount fail-whole-refresh (ERR-06 / D-66)", function()
  before_each(function()
    Mocks.setup()
    _G.MM.os = _G.MM.os or {}; _G.MM.os.sleep = function(_) end
    load_artifact()
  end)
  after_each(function() Mocks.teardown() end)

  local function seed_token(orgUuid)
    -- VERBATIM from spec/refresh_idempotency_spec.lua L55-64.
    LocalStorage["zettle:" .. orgUuid] = JSON():set({
      access_token = "AT-VALID", expires_at = os.time() + 7200,
      obtained_at  = os.time(), client_id = "client-x", uuid = "u-1",
      publicName   = "Beispiel Caf\195\169",
    }):json()
  end
  -- it() blocks ...
end)
```

**D-66 gating test shape:**

```lua
it("ERR-06: 500 mid-pipeline → error returned, since untouched, no partial txns", function()
  local orgUuid = "org-1"
  seed_token(orgUuid)
  -- Queue: successful purchase fetch + failing balance fetch (after 3 retries = 3 empty bodies).
  local purchase_raw = Fixtures.load("purchases/purchase_simple_sale")
  Mocks.push_response({ content = purchase_raw })           -- purchases OK
  Mocks.push_response({ content = "" })                     -- balance: empty (nil status) ×3 retries
  Mocks.push_response({ content = "" })
  Mocks.push_response({ content = "" })
  local since_in = 1700000000
  local account = { accountNumber = orgUuid, currency = "EUR", balance = 0 }
  local result = RefreshAccount(account, since_in)
  -- (a) Error string returned:
  assert.is_string(result)
  -- (b) Purchase call DID happen (captured):
  local found_purchases_call = false
  for _, req in ipairs(Mocks._captured_requests) do
    if req.url:find("purchase.izettle.com", 1, true) then found_purchases_call = true end
  end
  assert.is_true(found_purchases_call)
  -- (c) No transactions leaked (result is the error string, not a table):
  assert.is_not.equal("table", type(result))
  -- (d) Second RefreshAccount call with SAME since re-runs from scratch:
  Mocks._captured_requests = {}
  -- Now queue full successful 4-response set (per refresh_idempotency_spec pattern):
  Mocks.push_response({ content = purchase_raw })
  Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
  Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
  Mocks.push_response({ content = Fixtures.load("finance/finance_empty") })
  local result2 = RefreshAccount(account, since_in)  -- SAME since_in
  assert.is_table(result2)
  assert.is_true(#result2.transactions >= 1, "transactions emitted on retry")
end)
```

**Inheritance:**
- Same `seed_token` (verbatim copy) for token cache priming.
- Same `Mocks.push_response` sequencing pattern as refresh_idempotency_spec L86-90.
- The `since_in` byte-identical assertion satisfies D-66's "since is byte-identically passed" — RefreshAccount does NOT mutate `since` (it computes `effective_since` as a local). The spec demonstrates this by passing the same `since` twice and observing the second run also re-fetches from the same window.

---

### `spec/refresh_log_redaction_spec.lua` — EXTEND SEC-03 to retry log lines (D-68)

**Analog:** `spec/refresh_log_redaction_spec.lua` Phase-4 prefix list + LocalStorage walk (same file, Phase-4 extension already in repo).

**Existing pattern to extend** — the existing Gate B (captured-prints walk for `Bearer ` literal) already covers all log lines emitted during a RefreshAccount run, INCLUDING any new retry-log lines emitted by `M_http.get_json`. The only addition Phase 5 needs:

```lua
-- New it() block in the same describe:
it("Gate B+: retry-log INFO line never contains Bearer or eyJ JWT segment", function()
  seed_token("org-1")
  -- Queue: 1 successful purchase + 3 empty bodies for balance (forces retry logs) + ...
  Mocks.push_response({ content = Fixtures.load("purchases/purchase_simple_sale") })
  Mocks.push_response({ content = "" })  -- balance attempt 1
  Mocks.push_response({ content = "" })  -- balance attempt 2
  Mocks.push_response({ content = "" })  -- balance attempt 3
  local account = { accountNumber = "org-1", currency = "EUR", balance = 0 }
  RefreshAccount(account, 0)
  -- Walk captured prints; assert at least one "HTTP retry:" line exists AND none leaks secrets:
  local found_retry_log = false
  for _, line in ipairs(Mocks._captured_prints) do
    if line:find("HTTP retry:", 1, true) then
      found_retry_log = true
      assert.is_falsy(line:find("Bearer", 1, true), "retry log must not contain Bearer literal")
      assert.is_falsy(line:find("eyJ", 1, true), "retry log must not contain JWT segment")
      assert.is_falsy(line:find("AT-VALID", 1, true), "retry log must not contain bearer value")
    end
  end
  assert.is_true(found_retry_log, "expected at least one HTTP retry log line")
end)
```

---

### `tools/probe.lua` — add Q9 probe block

**Analog:** `tools/probe.lua` Q4 JSON-round-trip block (L65-75) — same file; same `print "  Qn: " .. ...` pattern.

**Existing Q4 shape to mirror** (`tools/probe.lua` L65-75):

```lua
-- Q4: JSON integer round-trip on amount = 995
print("--- Q4: JSON integer round-trip (amount=995) ---")
local encoded = JSON():set({amount = 995}):json()
print("  Q4: encoded = " .. encoded)
local decoded = JSON(encoded):dictionary()
print(string.format("  Q4: decoded.amount = %s (type=%s)", tostring(decoded.amount), type(decoded.amount)))
if decoded.amount == 995 then
  print("  Q4: RESULT = PASS (integer preserved)")
else
  print(string.format("  Q4: RESULT = FAIL (decoded=%s, expected 995)", tostring(decoded.amount)))
end
```

**Phase-5 Q9 block** (insert between Q8 and the closing print):

```lua
-- Q9: MM.os.sleep availability + behaviour (Phase 5 / D-67)
print("--- Q9: MM.os.sleep availability ---")
if type(MM) ~= "table" then
  print("  Q9: RESULT = FAIL (MM is not a table; sandbox surface differs from expectation)")
elseif type(MM.os) ~= "table" then
  print("  Q9: RESULT = ABSENT (MM.os is nil — falls back to busy-wait per ADR-0005)")
elseif type(MM.os.sleep) ~= "function" then
  print("  Q9: RESULT = ABSENT (MM.os.sleep is not a function — falls back to busy-wait per ADR-0005)")
else
  local t0 = os.time()
  local ok, err = pcall(function() MM.os.sleep(1) end)
  local elapsed = os.time() - t0
  if not ok then
    print("  Q9: RESULT = FAIL (MM.os.sleep(1) errored: " .. tostring(err) .. ")")
  elseif elapsed < 1 then
    print(string.format("  Q9: RESULT = PRESENT-BUT-NOOP (elapsed=%ds, expected >=1s)", elapsed))
  else
    print(string.format("  Q9: RESULT = PASS (MM.os.sleep blocks; elapsed=%ds)", elapsed))
  end
end
print("  Q9: ACTION = record outcome in ADR-0003 row Q9, then in ADR-0005 sleep-mechanism decision")
```

**Inheritances:**
- Print prefix discipline (`  Q9: ...` matching Q1-Q8 lines).
- `pcall` guard around the suspect call (mirrors Q8 L96-99 for expired.badssl.com).
- ACTION line for the maintainer to record (mirrors Q5 L83, Q7 L88).

---

## Shared Patterns

### Mocks no-op `MM.os.sleep` stub (applies to ALL new/extended specs that touch retry code)

**Source:** New convention (no Phase 1-4 analog). Insert in `before_each` of every spec that drives `M_http.get_json` through retry paths.

```lua
before_each(function()
  Mocks.setup()
  _G.MM.os = _G.MM.os or {}
  _G.MM.os.sleep = function(_) end  -- no-op: tests don't wait for real seconds
  load_artifact()
end)
```

Applies to: `spec/http_retry_spec.lua` (new), `spec/refresh_fail_whole_spec.lua` (new), the Gate B+ extension in `spec/refresh_log_redaction_spec.lua`, and any extension to `spec/http_spec.lua` that exercises retry.

Plan 05-XX may alternatively register a one-line helper in `spec/helpers/mm_mocks.lua` (e.g. `Mocks.setup({ noop_sleep = true })`) to DRY this — recommendation.

### Module preamble (applies to extended `src/http.lua`, `src/auth.lua`, `src/errors.lua`)

**Source:** `src/http.lua` L1-8 (already present). Add to the existing preamble:

```
-- Phase 5 (Resilience): retry-with-backoff for 5xx (D-62); rate-limit honoring
-- with Retry-After cap (D-63); sleep mechanism via MM.os.sleep with busy-wait
-- fallback (D-67, Q9-pending in ADR-0003).
```

Mirror equivalent additions in `src/auth.lua` preamble for `with_retry` (D-64 ownership) and `src/errors.lua` preamble for any new dispatch branches (D-69 ownership).

### Error routing (UNCHANGED inheritance from D-43)

**Source:** `src/entry.lua` L62-64 + `src/pagination.lua` L54-56 (per 03-PATTERNS and 04-PATTERNS).

```lua
local err = M_errors.from_http_status(status, raw)
if err then return err end
```

Phase 5 preserves this. `M_auth.with_retry` returns `(result, status, raw, err)` — entry.lua callers route through `err` first, exactly like the existing `fetch_err` pattern.

### Log redaction discipline (D-45 + D-68 extension)

**Source:** `src/http.lua` L125-130 (Bearer never in logs). Phase 5 adds ONE new log surface:

```lua
M_log.info(string.format("HTTP retry: attempt=%d/%d status=%d url=%s after_ms=%d",
  attempt, _MAX_ATTEMPTS, status, url, sleep_seconds * 1000))
```

NEVER includes `h` (headers), NEVER includes `bearer`. The retry log is gated by the Phase-5 extension of `spec/refresh_log_redaction_spec.lua` Gate B+.

### luacheck annotations

**Source:** `src/entry.lua` L139 `-- luacheck: ignore 431`. The wrap-pattern introduces closures (`function(bearer) return ... end`) — these capture `effective_since` from enclosing scope and may trigger 431 (variable shadowing). Add `-- luacheck: ignore 431` to the closure's `function(bearer)` declaration if the linter flags it; the cleaner alternative is renaming the closure arg (`function(b) return M_purchases.fetch_all(effective_since, b) end`).

### Spec preamble (applies to `spec/http_retry_spec.lua` + `spec/refresh_fail_whole_spec.lua`)

**Source:** `spec/http_spec.lua` L1-44 + `spec/refresh_idempotency_spec.lua` L1-45. Verbatim with file-name substitution. See per-file sections above.

---

## No Analog Found (genuinely new patterns)

| File / Capability | Role | Data Flow | Reason |
|---|---|---|---|
| `M_http` retry-with-backoff loop body | transport | retry-loop | No existing retry loop in codebase; closest structural reference is `src/pagination.lua` `repeat...until` (L30-88 per 04-PATTERNS) — borrow MAX_PAGES-style counter + early-break shape, but the retry-decision logic (5xx vs 429 vs success) is new. RESEARCH §"Existing extensions inspected" + CLAUDE.md "Rate limits — back off on HTTP 429, retry with jitter" is the implementation reference. |
| `M_auth.with_retry(orgUuid, callback)` higher-order wrapper | orchestration | callback + 401 remap | No existing higher-order function in `src/auth.lua` or anywhere else in the codebase. Construction is novel; the scaffolding (orgUuid resolution, `cached_token` call, `M_log.info` orgUuid:sub(1,8)) all copies from `cached_token` L162-171 verbatim. |
| Q9 `MM.os.sleep` sandbox probe | probe | request-response | Q1-Q8 cover globals/JSON/LocalStorage/services/TLS. Q9 is the first probe targeting a NESTED global (`MM.os.sleep`). Q4/Q5/Q8 are the shape references; the existence-check chain (`type(MM)` → `type(MM.os)` → `type(MM.os.sleep)`) is new structure. |

For these three, the planner uses CONTEXT D-62/D-63/D-64/D-67 + CLAUDE.md "Rate limits" guidance + RESEARCH §Token TTL as implementation reference; scaffolding (preamble, error routing, luacheck annotations, spec preamble, no-op sleep stub) copies directly from the analogs above.

---

## Metadata

**Analog search scope:** `src/*.lua`, `spec/*.lua`, `spec/helpers/*.lua`, `tools/*.lua`, `04-PATTERNS.md`, `03-PATTERNS.md`
**Files read:** 7 src + 4 spec + 1 helper + 1 tool + 2 prior PATTERNS.md
**Pattern extraction date:** 2026-06-21
**Manifest order (unchanged from Phase 4):** `webbanking_header → log → errors → i18n → model → http → auth → pagination → purchases → finance → mapping → entry`
**Open reconciliations the planner must adjudicate:**
1. **D-64 silent re-mint feasibility** — under assertion-grant + SEC-03, no refresh token exists. Recommendation: collapse "silent re-mint" to "401 → error.token_revoked immediately". See `M_auth.with_retry` section above.
2. **D-69 "+4 entries" in `M_errors.from_http_status`** — three of the four already exist (`error.network`, `error.rate_limit`, `LoginFailed` covers 401). Only `error.token_revoked` is new, and it lives in `M_auth.with_retry`, not `M_errors`. Recommendation: shrink D-69 to "+0 or +1 entries"; add `error.server_busy` only if 503 is split from generic 5xx.
3. **`spec/http_retry_spec.lua` 5xx fixture construction** — Risk R-1 means status is body-derived. Recommendation: extend `_infer_status` to recognise `{"error":"server_busy"}` → 503 and add a fixture. Cleanest contract.
4. **Mocks helper `(nil, error_string)` queueing for D-65 ERR-05** — current mocks don't support it. Recommendation: queue `content = ""` and rely on the existing `#raw == 0 → nil status` branch. Zero-touch on mocks.
