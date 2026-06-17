# Phase 2: Authenticated Network Layer — Pattern Map

**Mapped:** 2026-06-17
**Files analyzed:** 13 (5 source modules, 6 fixtures, 4 spec files, 2 helpers)
**Analogs found:** 13/13 (all in-repo from Phase 1)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/auth.lua` (fill) | service (auth orchestration) | request-response | `src/log.lua` (module attaching to `M_log`) | role-match (closest module-attachment pattern in repo) |
| `src/http.lua` (fill) | service (HTTP transport) | request-response | `spec/helpers/mm_mocks.lua` `_make_connection` L53–80 (Connection signature); `src/log.lua` (module-table attachment) | role-match |
| `src/errors.lua` (fill) | utility (status→string mapper) | transform | `src/log.lua` L39–41 (single `M_*` function attachment) | role-match |
| `src/entry.lua` (modify) | controller (MoneyMoney callbacks) | request-response | `src/entry.lua` itself (Phase-1 walking-skeleton, L1–88) | exact (in-place edit) |
| `src/webbanking_header.lua` | config | n/a | unchanged in Phase 2 — already pre-declares `M_auth`, `M_http`, `M_errors` (L9, L12, L13) | exact (no change) |
| `spec/fixtures/auth/*.json` (×6) | test fixture | file I/O | no prior `spec/fixtures/*.json` exists — Phase 2 introduces the directory | no analog (greenfield) |
| `spec/auth_spec.lua` (new) | test | request-response | `spec/entry_spec.lua` L11–135 (setup/dofile pattern); `spec/log_redaction_spec.lua` L41–48 (before_each Mocks.setup + load_artifact) | role-match |
| `spec/http_spec.lua` (new) | test | request-response | `spec/log_redaction_spec.lua` L41–48; `spec/entry_spec.lua` L17–34 | role-match |
| `spec/errors_spec.lua` (new) | test | transform | `spec/log_redaction_spec.lua` (pure-function busted style); `spec/entry_spec.lua` | role-match |
| `spec/entry_spec.lua` (extend) | test | request-response | itself (existing file, L40–134) | exact |
| `spec/log_redaction_spec.lua` (extend SEC-03) | test | request-response | itself, especially L67–98 (redaction assertions) | exact |
| `spec/helpers/mm_mocks.lua` (Wave 0 extend) | test helper | request-response | itself L39–48 (`push_response`) and L144–146 (identity base64 stubs) | exact (in-place edit) |
| `spec/helpers/fixtures.lua` (Wave 0 extend) | test helper | file I/O | itself L19–34 | exact (in-place edit) |
| `tools/manifest.txt` | config | n/a | unchanged — `auth`, `http`, `errors` already listed (L7, L10, L11) | exact (no change) |

---

## Pattern Assignments

### `src/auth.lua` (service / request-response)

**Analog:** `src/log.lua` (module-attachment idiom), plus the inline patterns sketched in RESEARCH.md §"Pattern 1/3/4".

**Module-attachment pattern** (copy from `src/log.lua` L7, L11, L39–41, L57–60):

```lua
-- src/log.lua L7
local _LEVEL = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
-- L11-36: private local function _redact(s) ... end
-- L39-41: public attachment
M_log.redact = function(s)
  return _redact(tostring(s))
end
-- L57-60: thin wrappers
M_log.debug = function(...) _emit("DEBUG", ...) end
```

Apply to `auth.lua` as: `local _b64url_decode = function(s) … end` (private), then `function M_auth._decode_jwt_payload(jwt) … end` (public-but-underscored, mirroring `M_log.redact`), then `function M_auth.exchange_assertion(api_key, client_id) … end`.

**Cross-module call pattern** (per CONTEXT.md `<code_context>` "Established Patterns"): no `require()`; reach other modules via the pre-declared global tables — `M_log.info(...)`, `M_errors.from_http_status(...)`, `M_i18n.t(...)`, `M_http.post_form(...)`. The build wraps every `src/*.lua` (except `webbanking_header` and `entry`) in a `do … end` block — confirm with `tools/build.lua` L162–167.

**LocalStorage usage**: no existing analog (Phase 1 does not touch `LocalStorage`). Mock contract from `spec/helpers/mm_mocks.lua` L202–203 (`_G.LocalStorage = {}`, reset per test).

---

### `src/http.lua` (service / request-response)

**Analog A — module-table attachment + private locals:** `src/log.lua` L7–11 (private `local _LEVEL`, `local function _redact`).

**Analog B — Connection signature:** `spec/helpers/mm_mocks.lua` L58–65 — the mock surfaces the exact 5-tuple the production code must consume:

```lua
-- spec/helpers/mm_mocks.lua L58-65
function conn:request(method, url, postContent, postContentType, headers)
  if #Mocks._response_queue == 0 then
    error("mm_mocks: no queued response for " .. tostring(method) ..
          " " .. tostring(url))
  end
  local r = table.remove(Mocks._response_queue, 1)
  return r.content, r.charset, r.mime, r.filename, r.headers
end
```

Production `M_http.post_form` MUST destructure exactly these five returns (per RESEARCH §"Pattern 2" L448–449), and MUST NOT expect an HTTP status code from Connection (it isn't in the tuple). Status is inferred from the parsed body — see Risk R-1 and `M_http._infer_status` in RESEARCH §"Pattern 2" L466–482.

**Analog C — redaction-before-log:** `src/log.lua` L11–36 (`_redact`) is the established passthrough. `M_http.post_form`/`get_json` MUST call `M_log.debug("POST " .. url .. " body=" .. M_log.redact(body))` (per RESEARCH §"Pattern 2" L447, L451, L488, L492) — never log raw headers.

**Module-local Connection reuse** (D-25): no existing analog; new pattern, but cleanup hook `M_http.shutdown()` is invoked from `EndSession` (mirrors the `EndSession` existing no-op at `src/entry.lua` L84–87).

---

### `src/errors.lua` (utility / transform)

**Analog:** `src/log.lua` L39–41 — single-function attachment to module table, no external dependencies beyond `M_i18n`.

```lua
-- src/log.lua L39-41 (pattern to mirror)
M_log.redact = function(s)
  return _redact(tostring(s))
end
```

Apply as:

```lua
-- src/errors.lua (Phase 2 target shape, per D-24)
M_errors.from_http_status = function(status, body)
  if status == nil then return M_i18n.t("error.network", "—") end
  if status >= 200 and status <= 299 then return nil end
  if status == 400 or status == 401 or status == 403 then return LoginFailed end
  if status == 429 then return M_i18n.t("error.rate_limit") end
  return M_i18n.t("error.network", tostring(status))
end
```

`LoginFailed` is a MoneyMoney built-in global; the mock declares it at `spec/helpers/mm_mocks.lua` L224 (`_G.LoginFailed = "LoginFailed"`).

i18n keys already present in `src/i18n.lua` (verified):
- L17 `error.invalid_grant` → `"Anmeldung fehlgeschlagen: API-Key wurde abgelehnt."`
- L18 `error.network` → `"Netzwerkfehler: %s"` (note `%s` formatter, takes one arg)
- L19 `error.rate_limit` → `"Anfragelimit erreicht — bitte später erneut versuchen."`
- L20 `credential.api_key.label` → `"API-Key"`

---

### `src/entry.lua` (controller, modify)

**Analog:** itself — Phase-1 walking-skeleton at L1–88. Phase 2 surgery is **localized**:

**Preserve verbatim** (D-10 surface contract from Phase-1 CONTEXT.md):
- L5–7 `SupportsBank` — unchanged
- L9–20 `InitializeSession2` first-call challenge block — unchanged
- L22–41 credential extraction block — unchanged
- L43–45 empty-key guard — unchanged

**Insert after L45, before L46–47 `M_log.info … return nil`:**

```lua
-- NEW Step 3 (D-22): extract client_id from JWT payload (pure CPU, no network)
local client_id = M_auth._extract_client_id(api_key)
if not client_id then
  M_log.info("InitializeSession2: assertion JWT could not yield client_id")
  return M_i18n.t("error.invalid_grant")
end

-- NEW Step 4 (D-21 leg 1): POST /token
local token_table, status, raw_body = M_auth.exchange_assertion(api_key, client_id)
local err = M_errors.from_http_status(status, raw_body)
if err then return err end

-- NEW Step 5 (D-21 leg 2): GET /users/self
local profile, p_status, p_raw = M_auth.fetch_profile(token_table.access_token)
local p_err = M_errors.from_http_status(p_status, p_raw)
if p_err then return p_err end

-- NEW Step 6 (D-23c): persist cache keyed by organizationUuid
M_auth.persist_session(token_table, profile, client_id)
```

(Full sketch in RESEARCH §"Pattern 4" L573–633.)

**Rewrite `ListAccounts` (L50–60):** replace the Phase-1 fixture with a cache read.

Current (to be replaced):
```lua
-- src/entry.lua L50-60 (current Phase-1 fixture)
function ListAccounts(knownAccounts) -- luacheck: ignore 431
  return {
    {
      accountNumber = "paypal-pos-fixture-001",
      name          = M_i18n.t("account.name", "Test-Händler"),
      currency      = "EUR",
      portfolio     = false,
      type          = AccountTypeGiro,
    },
  }
end
```

Target shape per D-23a/b: iterate `LocalStorage.zettle` entries (or flat-key fallback), assemble one record per `orgUuid` with `accountNumber = orgUuid` and `name = M_i18n.t("account.name", publicName or orgUuid:sub(1,8))`. Keep `currency = "EUR"`, `portfolio = false`, `type = AccountTypeGiro` verbatim.

**Modify `EndSession` (L84–87):** add `M_http.shutdown()` and clear in-memory cache mirror (not LocalStorage — see D-29 anti-pattern note).

**Preserve `RefreshAccount` (L62–82)** verbatim — Phase 3/4 owns real refresh.

**`-- luacheck: ignore 431` idiom** applies to every new closure too (already used at L9, L50, L62 — match style).

---

### `spec/fixtures/auth/*.json` (test fixtures / file I/O)

**No existing analog in repo.** Phase 2 introduces `spec/fixtures/auth/` (D-28). Six files:

- `token_ok.json` — `{"access_token": "<jwt-shaped string>", "expires_in": 7200, "token_type": "Bearer"}`
- `token_invalid_grant.json` — `{"error": "invalid_grant", "error_description": "..."}`
- `users_self_ok.json` — `{"uuid": "<uuid>", "organizationUuid": "<uuid>", "publicName": "Beispiel Café GmbH"}`
- `users_self_unauthorized.json` — `{"error": "unauthorized", "error_description": "..."}`
- `token_rate_limited.json` — `{"error": "rate_limit"}` (or empty — see D-24 status synthesis)
- `network_timeout.json` — empty string / fixture indicating empty body

Each file's first line should be a `// source: …` comment cited from iZettle docs per D-28 — but standard JSON forbids comments; RESEARCH §"Pattern 2" shape implies a sidecar `.md` may be needed, OR the citation lives at the head of the spec that loads it. Planner's call (Claude's Discretion per CONTEXT.md L52).

**Citation shape comes from RESEARCH §"Auth Round-Trip Details" L686–716** (verbatim docs JSON examples).

---

### `spec/auth_spec.lua`, `spec/http_spec.lua`, `spec/errors_spec.lua` (test / request-response)

**Analog A — busted describe/it style with artifact load:** `spec/log_redaction_spec.lua` L18–48.

```lua
-- spec/log_redaction_spec.lua L14-48 (template for new spec files)
local Mocks = require("spec.helpers.mm_mocks")

do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("log_redaction_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

describe("M_log redaction", function()
  before_each(function()
    Mocks.setup()
    load_artifact()
  end)
  after_each(function()
    Mocks.teardown()
  end)
  -- it("...", function() … end)
end)
```

**Analog B — queue + assert pattern using mocked Connection:** `spec/entry_spec.lua` L11–34 uses `setup()`-once + `dofile`; `spec/log_redaction_spec.lua` uses `before_each` re-load. For specs that queue HTTP responses, use `before_each` re-load to reset module-local `_conn` cleanly.

Pattern for queuing token responses:
```lua
local raw, _ = require("spec.helpers.fixtures").load("auth/token_ok")
Mocks.push_response({ content = raw, mime = "application/json" })
-- now call M_auth.exchange_assertion("eyJ…", "client-uuid")
```

**Analog C — redaction assertion idiom (for SEC-03 in `log_redaction_spec.lua` extension):** `spec/log_redaction_spec.lua` L61–76 — `assert.is_truthy(line:find("<redacted>"))` + `assert.is_falsy(line:find("eyJSECRET"))` pair. SEC-03 (D-29) requires this same pair against the return string from `InitializeSession2` for `eyJ`, `Bearer`, and any base64-url segment of the API key.

---

### `spec/helpers/mm_mocks.lua` (Wave 0 extension)

**Self-analog (in-place extend):** L39–48 `Mocks.push_response`, L58–65 mock `conn:request`, L144–146 identity `MM.base64`/`base64decode`.

**Change 1 — `push_response` gains optional `status` field** (per RESEARCH "W0" and Risk R-1). The production code can't read status from Connection, but the spec can synthesize one. Existing:

```lua
-- spec/helpers/mm_mocks.lua L39-48 (current)
function Mocks.push_response(opts)
  opts = opts or {}
  table.insert(Mocks._response_queue, {
    content  = opts.content  or "",
    charset  = opts.charset  or "utf-8",
    mime     = opts.mime     or "application/json",
    filename = opts.filename or nil,
    headers  = opts.headers  or {},
  })
end
```

Add `status` field to the queued row (note: NOT returned by `conn:request` — kept only for the body-shape mapping in `_infer_status` to remain testable; or, simpler, kept as documentation for the test author and inspected nowhere). Recommended: do NOT add `status` to the 5-tuple return — instead, have fixtures carry the `{"error":...}` body that the production `_infer_status` derives from. See Risk R-1 in RESEARCH §1 (line 15).

**Change 2 — replace identity `MM.base64decode` stub at L144–146.** Current:
```lua
-- spec/helpers/mm_mocks.lua L144-146
base64       = function(s) return s end,
base64decode = function(s) return s end,
```

Replace with a real base64 decoder (~25 LoC of pure Lua, standard-alphabet). `MM.base64` may stay identity since Phase 2 doesn't encode. Required because `M_auth._decode_jwt_payload` calls `MM.base64decode` on a real JWT payload segment and expects raw JSON bytes back.

**Change 3 — `LocalStorage` semantics:** L203 `_G.LocalStorage = {}` is fine for the nested-table path. For the flat-key fallback test, the spec writes `LocalStorage["zettle:" .. orgUuid] = JSON-string` and the production code's `_cache_read` retrieves it.

---

### `spec/helpers/fixtures.lua` (Wave 0 extension)

**Self-analog:** L19–34 — existing single-segment `name` resolution.

```lua
-- spec/helpers/fixtures.lua L19-34 (current)
function Fixtures.load(name)
  local path = "spec/fixtures/" .. name .. ".json"
  local f, err = io.open(path, "r")
  ...
end
```

No change needed — `name` is concatenated as-is. `Fixtures.load("auth/token_ok")` already resolves to `spec/fixtures/auth/token_ok.json`. Confirm in the planner that this works on macOS (it does — POSIX path separator). Wave 0 verifies via a spec call but NO code edit to `fixtures.lua` is necessary.

---

## Shared Patterns

### `do … end` block wrap (build-time concatenation)

**Source:** `tools/build.lua` L162–167

```lua
-- tools/build.lua L162-167
parts[#parts + 1] = "-- === MODULE: " .. mod .. " ===\n"
parts[#parts + 1] = "do\n"
parts[#parts + 1] = ensure_trailing_newline(content)
parts[#parts + 1] = "end\n"
```

**Apply to:** all Phase 2 source modules (`auth.lua`, `http.lua`, `errors.lua`). Implication for source authors:
- All non-attached locals (e.g. `local _conn`, `local _LEVEL`) are scoped to the `do … end` block — perfect for module-private state.
- Public functions MUST attach to `M_auth.foo = …` or `function M_auth.foo(...)` because `M_auth` is the only cross-block-visible handle.
- No top-level statements that run at load time other than attachments (see `src/log.lua` L7 `local _LEVEL = …` for the precedent).

### Egress allowlist (CI-gated)

**Source:** Phase-1 D-12, CI grep. Hosts: `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`.

**Apply to:** `src/auth.lua` (uses `oauth.zettle.com/token` and `oauth.zettle.com/users/self` — no new host); `src/http.lua` (host-agnostic, just transports URLs). Do not introduce string literals for any other domain — the CI grep on `dist/paypal-pos.lua` will fail the build.

### Redaction before log

**Source:** `src/log.lua` L11–36 (`_redact`) + L52 `parts[i] = _redact(tostring(select(i, ...)))`.

**Apply to:** every `M_http.{post_form,get_json}` debug-log line; every `M_auth.*` info/debug line that includes a body, URL with query, or JWT. The 4-pass redactor already strips JWT-shape, `Bearer …`, `assertion=…`, `access_token=…` — no new patterns needed for Phase 2.

### `-- luacheck: ignore 431` for callback args

**Source:** `src/entry.lua` L9, L50, L62; `spec/helpers/mm_mocks.lua` L58, L101, L123, L130, etc.

**Apply to:** any new closure inside `entry.lua` or any new function in `http.lua` / `auth.lua` whose signature shadows a built-in (e.g. `function M_http.post_form(url, body_table, headers)` — `headers` may shadow nothing today but mock `conn:request` carries `headers` and `mm_mocks.lua` L58 already uses the idiom).

### Spec setup/teardown lifecycle

**Source:** `spec/log_redaction_spec.lua` L18–48 (before_each rebuild via `dofile`); `spec/entry_spec.lua` L17–34 (setup-once rebuild via `dofile`).

**Apply to:** new `auth_spec.lua`, `http_spec.lua`, `errors_spec.lua`. Prefer the `before_each` variant from `log_redaction_spec.lua` (L41–48) because Phase 2 specs queue per-test responses and want module-local `_conn` reset between tests.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `spec/fixtures/auth/*.json` | fixture | file I/O | No prior fixture files exist; directory created by Phase 2 (D-28). Shape comes verbatim from iZettle docs in RESEARCH §"Auth Round-Trip Details" L686–716, not from a local analog. |
| `LocalStorage` read/write code in `src/auth.lua` | persistence | KV-store | Phase 1 explicitly excludes `LocalStorage` (CONTEXT.md L32 "out of scope"). RESEARCH §"Pattern 3" L516–562 is the only template — use it. |
| JWT base64url decoder | utility | transform | No prior crypto code in `src/`. Use the inline sketch in RESEARCH §"Pattern 1" L339–344 (RFC 7515 Appendix C translation + `MM.base64decode`). |

---

## Metadata

**Analog search scope:** `src/`, `spec/`, `spec/helpers/`, `tools/`, `tools/manifest.txt`, `.planning/phases/01-foundations-sandbox-probes/CONTEXT.md`.
**Files scanned:** 16.
**Pattern extraction date:** 2026-06-17.

---

## PATTERN MAPPING COMPLETE
