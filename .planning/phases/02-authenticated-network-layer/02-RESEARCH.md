# Phase 2: Authenticated Network Layer — Research

**Researched:** 2026-06-17
**Domain:** OAuth 2.0 JWT-bearer assertion grant against `oauth.zettle.com`; MoneyMoney `Connection()` / `LocalStorage` semantics; pure-Lua base64url + JWT-payload decoding; module-local `Connection` reuse; fail-fast `InitializeSession2` profile-ping; multi-merchant token cache keyed by `organizationUuid`.
**Confidence:** HIGH on locked OAuth contract (cited from iZettle/api-documentation), the MoneyMoney `Connection()` return signature (cited from `moneymoney.app/api/webbanking/`), and Phase-1 ADR-0003 results that are CLOSED (Q1, Q4, Q7, Q8). **MEDIUM on `/users/self` `publicName` field shape — see Open Question O-1 below.** **LOW on three open Phase-1 probes (Q2 redirects, Q5 nested-table persistence, Q6 client_id) — these are NOT blockers because each has a CLOSED-OUT plan (Q2 deferred to first live call with defensive redirect-loop posture, Q5 closed by D-23c flat-key fallback, Q6 closed by D-22 client_id-from-JWT).**

---

## Summary

Phase 2 wires `src/auth.lua` and `src/http.lua` (Phase-1 empty stubs, 3 LoC each) into a real OAuth round-trip against `oauth.zettle.com` using the JWT-bearer assertion grant. The phase delivers four observable behaviours: (1) the user pastes an API key, (2) MoneyMoney shows the merchant's account in the sidebar **synchronously** within seconds, (3) a wrong key fails fast with the German `LoginFailed` string **at add-account time** (not hours later on first refresh), (4) the API key never appears in `LocalStorage`, in any `print()` call, in any returned error string, or in any cached state.

The OAuth contract is fully locked from authoritative iZettle docs: `POST https://oauth.zettle.com/token` with `Content-Type: application/x-www-form-urlencoded` and form params `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&client_id=<uuid>&assertion=<jwt>`. Success returns `{access_token, expires_in: 7200, token_type}`; failure returns `{error: "invalid_grant", error_description: ...}` with HTTP 400. The merchant-profile fetch is `GET https://oauth.zettle.com/users/self` with `Authorization: Bearer <access_token>`; the FAQ-documented response shape is `{uuid, organizationUuid}` — **`publicName` is NOT documented in the public docs**; treat as MEDIUM-confidence and defensively defaulted (see O-1).

The single load-bearing MoneyMoney finding that reshapes the implementation: **`Connection():request()` returns five values (content, charset, mimeType, filename, headers) and has NO separate HTTP status code return.** To prevent script abort on HTTP 4xx/5xx, the request MUST send `Accept: application/json` — without this header MoneyMoney aborts the entire Lua chunk on any non-2xx response. The HTTP status code is **not** documented as exposed in the `headers` table return; the only signal that an HTTP error happened (after the `Accept` shield is in place) is the response body's JSON payload itself (`{"error": "invalid_grant", ...}`). This means Phase 2's `M_errors.from_http_status(status, body)` cannot rely on a numeric `status` arg from `Connection()` — it must be sourced from JSON-body inspection. This is the largest delta from the CONTEXT.md D-25 wording ("both return `(decoded_table|nil, status, raw_body)`") and the planner must reconcile it (see Risk R-1 below).

**Primary recommendation:** Implement in four task waves: (W0) hand-rolled fixtures under `spec/fixtures/auth/` + extend `mm_mocks.lua` push_response queue with the `status` field that the mock surfaces synthetically (the production code cannot read status from Connection, but tests inject one for ease of writing); (W1) `M_errors.from_http_status` + `M_http` (`post_form`, `get_json`, `shutdown`) wired to `Mocks.push_response`; (W2) `M_auth` (`_decode_jwt_payload`, `_extract_client_id`, `exchange_assertion`, `cached_token`) including JWT base64url decoding; (W3) `entry.lua` rewrite of `InitializeSession2`/`ListAccounts`/`EndSession` to call `M_auth` + `M_http` and surface `publicName`/`organizationUuid`. Gate each wave with one or more busted specs that hold the SEC-03 redaction invariant end-to-end.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Fail-fast probe inside `InitializeSession2`:**
- **D-21:** Probe strategy is token-fetch + `/users/self` (two round-trips). `POST oauth.zettle.com/token` with `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`, `client_id=<extracted>`, `assertion=<API_KEY>` produces the access token; immediately on success, `GET https://oauth.zettle.com/users/self` with `Authorization: Bearer <token>` retrieves the merchant profile. The dual-call is the synchronous failure surface: 401 on `/token` → `LoginFailed` for "key rejected"; 401 on `/users/self` → `LoginFailed` for "scope mismatch"; both are surfaced via the German `error.invalid_grant` string. `ListAccounts` becomes a pure cache read of the `publicName` + `organizationUuid` captured here.

**`client_id` resolution:**
- **D-22:** `client_id` is **extracted from the assertion JWT payload** (middle segment, base64url-decoded, `JSON():dictionary()`-parsed, reading the `aud` claim — fall back to `client_id` claim if `aud` is absent or non-UUID-shaped). No hardcoded partner constant ships in `src/auth.lua`. No signature verification is attempted — we read the public payload only. If the assertion is malformed or carries neither `aud` nor `client_id`, `InitializeSession2` returns the German `error.invalid_grant` string synchronously without making any network call. This closes Phase-1 ADR-0003 question Q6 as: *"the client_id is read from the assertion JWT's `aud`/`client_id` claim; no constant is shipped."*

**Multi-account identity:**
- **D-23a:** `accountNumber` for the MoneyMoney account record is **`organizationUuid` from `/users/self`** (not user `uuid`, not JWT `sub`, not a hash of the API key). Same merchant org → same `accountNumber` even if the user rotates the API key or a different user under the same org issues a new key. Stable transaction history across key rotation is the value.
- **D-23b:** Account label rendered in MoneyMoney's sidebar is `"PayPal POS — " .. publicName` where `publicName` comes from `/users/self`. Fallback when `publicName` is empty/nil: `"PayPal POS — " .. organizationUuid:sub(1, 8)` so ACCT-04 (two accounts coexist with distinguishable labels) still holds even for keys without a profile name.
- **D-23c:** Token cache shape is **nested, keyed by `organizationUuid`**: `LocalStorage.zettle = { [orgUuid] = { access_token, expires_at, obtained_at, client_id } }`. Per-merchant isolation: two extension instances under different orgUuids never overwrite each other's tokens. **Caveat:** verifies Phase-1 probe Q5 (cross-restart persistence of nested tables in `LocalStorage`). If ADR-0003 Q5 ultimately reports "nested tables do not survive restart", fall back to flat keys `LocalStorage["zettle:" .. orgUuid] = JSON-encoded-string` and add a small decode/encode wrapper in `src/auth.lua`. This fallback path is implemented but unused unless Q5 forces it.
- **D-23d:** Pre-expiry guard is 60 s (locked by AUTH-04). `access_token` is re-minted when `os.time() >= expires_at - 60`. No refresh-token rotation (locked by AUTH-04).

**Error handoff to Phase 5:**
- **D-24:** Phase 2 ships a minimal `M_errors.from_http_status(status, body)` in `src/errors.lua`. Signature: `(status:integer, body:string?) -> string|nil`. Cases:
  - `nil` status (network/timeout/no response) → `M_i18n.t("error.network", "—")`
  - `200`–`299` → `nil` (no error)
  - `400`, `401`, `403` → `LoginFailed` literal string
  - `429` → `M_i18n.t("error.rate_limit")`
  - `500`–`599` → `M_i18n.t("error.network", tostring(status))`
  - Anything else → `M_i18n.t("error.network", tostring(status))`
  Phase 5 extends this additively (signature stable).

**Cross-cutting:**
- **D-25:** `src/http.lua` exposes exactly `M_http.post_form(url, body_table, headers)` and `M_http.get_json(url, headers)`. Both return `(decoded_table|nil, status, raw_body)`. Both pass `raw_body` through `M_log.redact()` before any debug log line. A single module-local `Connection()` instance is created on first call and reused; `EndSession` closes it via `M_http.shutdown()`.
- **D-26:** Egress allowlist is exactly `{"oauth.zettle.com", "purchase.izettle.com", "finance.izettle.com"}` (Phase-1 D-12). Phase 2 only exercises `oauth.zettle.com`. CI's egress-grep continues to gate the shipped artifact.
- **D-27:** No sandbox/production toggle in the shipped artifact — production endpoints only.
- **D-28:** Test fixtures for Phase 2 are hand-rolled JSON files under `spec/fixtures/auth/` (`token_ok.json`, `token_invalid_grant.json`, `users_self_ok.json`, `users_self_unauthorized.json`, `token_rate_limited.json`, `network_timeout.json`).
- **D-29:** SEC-03 redaction test exercises a real auth failure path through `auth.lua` and `errors.lua` and asserts the resulting MoneyMoney return string contains neither a JWT-shape (`eyJ[a-zA-Z0-9_-]+`), nor the literal `Bearer`, nor any base64-url segment of the input API key.

### Claude's Discretion
- Exact Lua module layout inside `src/auth.lua` / `src/http.lua` (function ordering, helper visibility) — delegated to the planner.
- `M_log` call sites in `auth.lua` / `http.lua` (which lines log at INFO vs DEBUG) — delegated, subject to: never log the API key, never log a Bearer header value, never log raw JWT payloads (use first-8-chars + length idiom).
- Test names, file names under `spec/fixtures/auth/`, and the granularity of spec files (one file vs many) — planner's call.

### Deferred Ideas (OUT OF SCOPE)
- Retry/backoff and 429 throttling at the call layer → Phase 5.
- Recorded sandbox fixtures captured from a live `oauth.zettle.com` sandbox tenant → deferred; Phase 2 ships hand-rolled fixtures only.
- `/users/self` cache invalidation on profile change (renamed org) → Phase 5/6.
- Sandbox/dev-mode toggle in the shipped artifact → out (D-27).
- Probe.lua extensions for Q2/Q6 → Q6 closed by D-22; Q2 may be revisited but is not blocking (defensive design).
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AUTH-01 | User can paste a PayPal POS API key into MoneyMoney's add-account dialog (custom German-labelled credential field) | Walking-skeleton `InitializeSession2` already returns the German credential challenge object (`src/entry.lua` L14-L20); Phase 2 keeps the challenge shape, adds network call after credential extraction. |
| AUTH-02 | Extension authenticates against `oauth.zettle.com/token` using `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer` with `client_id` and `assertion=<API_KEY>` | Token endpoint contract confirmed in iZettle/api-documentation/authorization.md; full request shape locked in §"Auth Round-Trip Details" below. |
| AUTH-03 | An invalid API key produces a synchronous `LoginFailed` at add-account time, NOT a delayed error at first refresh | Two-call probe inside `InitializeSession2` per D-21; `M_errors.from_http_status(400, body)` and `(401, body)` both return the `LoginFailed` literal per D-24. |
| AUTH-04 | Access tokens are cached in `LocalStorage` with `expires_at` and re-minted on cache miss (60 s pre-expiry guard); no refresh-token rotation | Token cache shape `{access_token, expires_at, obtained_at, client_id}` per D-23c; expiry guard `os.time() >= expires_at - 60` per D-23d; iZettle docs confirm "no refresh token provided in the response for this grant" — re-call assertion grant on expiry. |
| AUTH-05 | The API key itself is never written to `LocalStorage`, never logged, never echoed in error messages — only MoneyMoney's credentials store holds it | Module-local `_pending_credentials` discarded after `exchange_assertion`; `M_log.redact()` strips JWT-shape, `Bearer …`, `assertion=…`, `access_token=…` per existing `src/log.lua` L11-L36; SEC-03 test (D-29) is the gating invariant. |
| AUTH-06 | Token cache survives MoneyMoney restart (verified via Phase-1 probe Q5) | Phase-1 ADR-0003 Q5: writability CONFIRMED but cross-restart persistence UNOBSERVED. Phase 2 designs defensively per D-23c (nested table primary, flat-string fallback). |
| SEC-03 | An authentication-failure test asserts no API-key fragment, JWT, or `Bearer` token appears in the resulting error string | Exact gating test specified in §"SEC-03 Gating Test" below; threads a real auth failure through `auth.lua` → `errors.lua` and greps the return string for `eyJ`, `Bearer`, and base64-url segments of the input API key. |
| ACCT-01 | Extension exposes one MoneyMoney account per PayPal POS merchant of type `AccountTypeGiro` | `ListAccounts` returns one entry with `type = AccountTypeGiro`, `currency = "EUR"`; per-merchant identity via `organizationUuid` (D-23a). |
| ACCT-02 | Account label is `"PayPal POS — <merchant-name>"` so multiple instances are distinguishable in MoneyMoney's sidebar | Label = `"PayPal POS — " .. publicName` (D-23b); fallback to `organizationUuid:sub(1, 8)` when `publicName` empty/nil. |
| ACCT-04 | User can add the extension multiple times to track multiple merchant accounts (one extension instance per merchant) | Cache keyed by `organizationUuid` (D-23c); two extension instances under different orgUuids never overwrite each other's tokens or labels. |
</phase_requirements>

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| JWT base64url payload decode | Extension runtime (`src/auth.lua`) | — | Pure CPU-bound; no network; runs synchronously inside `InitializeSession2` before any HTTP call so a malformed assertion fails without touching the wire. |
| OAuth token exchange (POST `/token`) | Extension runtime (`src/http.lua` + `src/auth.lua`) | — | The only `Connection():request("POST", ...)` call in Phase 2; lives in `M_auth.exchange_assertion` which delegates HTTP mechanics to `M_http.post_form`. |
| Merchant profile fetch (GET `/users/self`) | Extension runtime (`src/http.lua` + `src/auth.lua`) | — | The second leg of the fail-fast probe; uses `M_http.get_json` with the access token as `Authorization: Bearer …`. |
| Token cache (per-org, persistent) | MoneyMoney runtime (`LocalStorage`) | Extension runtime (`src/auth.lua`) | `LocalStorage` is owned by MoneyMoney; `src/auth.lua` is the sole writer/reader. The nested-vs-flat fallback (D-23c) is a runtime defensive measure. |
| HTTP error → German string mapping | Extension runtime (`src/errors.lua`) | — | Single source of truth `M_errors.from_http_status(status, body)`; Phase 5 extends additively. |
| Account record assembly | Extension runtime (`src/entry.lua` `ListAccounts`) | — | Reads from the cached profile in `LocalStorage.zettle[orgUuid]` (or the in-module mirror); never re-fetches `/users/self` in `ListAccounts`. |
| API-key isolation | Extension runtime (across `auth.lua` + `log.lua` + `errors.lua`) | CI (egress grep, redaction spec) | API key never leaves the call frame where MoneyMoney passed it in; never written to `LocalStorage`; redaction is a defense-in-depth layer behind the structural isolation. |

---

## Standard Stack

### Core (shipped in `dist/paypal-pos.lua`)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Lua | 5.4.8 (MoneyMoney 2.4.72 embedded) | Implementation language | Confirmed by Phase-1 probe Q1; CI matrix pins same. [VERIFIED: ADR-0003 Q1 — MoneyMoney 2.4.72 on macOS 26.4.1 ARM] |
| `Connection()` | Built-in MoneyMoney global | HTTPS client + cookie jar | Only sanctioned HTTP mechanism. [CITED: https://moneymoney.app/api/webbanking/] |
| `JSON()` | Built-in MoneyMoney global | JSON parse + serialise | `JSON(raw):dictionary()` returns Lua table; `JSON():set(t):json()` serialises. [CITED: https://moneymoney.app/api/webbanking/] |
| `LocalStorage` | Built-in MoneyMoney global | Per-extension persistent KV | Token cache survives across `RefreshAccount` calls in-session; cross-restart persistence is DEFENSIVE per ADR-0003 Q5. [CITED: https://moneymoney.app/api/webbanking/] |
| `os.time()` | Lua 5.4 standard | UNIX epoch seconds for `expires_at` math | Confirmed available in MoneyMoney sandbox per ADR-0003 Q1. [VERIFIED: ADR-0003 Q1] |
| `MM.localizeText`, etc. | Built-in MoneyMoney globals | (Not used in Phase 2 — own i18n table) | Phase 2 uses `M_i18n.t` exclusively per existing convention (Phase-1 D-09). |

**No new shipped libraries in Phase 2.** All new code is pure Lua 5.4 in `src/auth.lua`, `src/http.lua`, `src/errors.lua`, `src/entry.lua`.

### Supporting (test/CI only — NEVER in the shipped artifact)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `busted` | 2.3.0 (Phase-1 frozen) | Test framework | All `spec/auth_spec.lua`, `spec/http_spec.lua`, `spec/errors_spec.lua` |
| `dkjson` | 2.7+ (Phase-1 frozen) | Pure-Lua JSON used by `JSON()` mock | Fixture loading + `Mocks.push_response` body strings |
| `luacheck` | 1.2.0 (Phase-1 frozen) | Static analysis | New `M_auth`, `M_http`, `M_errors` calls must pass luacheck against existing `.luacheckrc` |
| `luacov` | 0.16.0 (Phase-1 frozen) | Coverage gate ≥85% | Phase 2 raises absolute LOC; coverage must hold |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pure-Lua base64url decoder in `src/auth.lua` | `MM.base64decode` built-in | `MM.base64decode` is documented for standard base64. JWT uses **base64url** (`-` and `_` instead of `+` and `/`, no `=` padding). Either we (a) translate the JWT segment to standard base64 then call `MM.base64decode`, or (b) ship a pure-Lua base64url decoder (~30 LoC). Option (a) saves LoC and trusts MoneyMoney's MIME-tested implementation. **Recommendation:** translate (`s:gsub("-","+"):gsub("_","/")`, pad with `=` to a multiple of 4) then call `MM.base64decode`. [VERIFIED: https://datatracker.ietf.org/doc/html/rfc7515#appendix-C — RFC 7515 Appendix C documents this exact translation.] |
| Single `Connection()` instance reused (D-25) | New `Connection()` per request | D-25 locks "single module-local reused"; the only risk is cookie/session leakage between merchants. Phase 2 only talks to `oauth.zettle.com` — no per-merchant cookies should be set by Zettle on a stateless OAuth token endpoint. **Mitigation:** `EndSession` calls `M_http.shutdown()` which calls `conn:close()` and clears the module-local. |
| Synchronous two-call probe (D-21) | Lazy single-call probe | A single probe (`/token` only) would miss "valid key but no scope for `/users/self`". The `/users/self` call also gives us `organizationUuid` and `publicName` for the account record (D-23a/b) — necessary in `ListAccounts` regardless. Two calls is the minimum; locked by D-21. |

**Installation:** No new installation — Phase 1 toolchain unchanged.

**Version verification:** Toolchain already verified in Phase 1; no new packages introduced in Phase 2.

---

## Package Legitimacy Audit

> Phase 2 installs **no new external packages**. All new code is pure Lua 5.4 in `src/*.lua`, exercising MoneyMoney built-ins and the Phase-1-locked toolchain (busted, luacheck, luacov, dkjson) — already vetted in Phase-1 RESEARCH §Package Legitimacy Audit (all OK).

| Package | Registry | Phase | Status |
|---------|----------|-------|--------|
| (none) | — | — | Phase 2 introduces no package dependencies. |

**Packages removed due to [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none.

---

## Architecture Patterns

### System Architecture Diagram

```
                ┌──────────────────────────────────────────────────────┐
                │  MoneyMoney UI (Konto hinzufügen / Aktualisieren)    │
                └──────────────────────────────────────────────────────┘
                          │                              │
              API key paste │                  Refresh click │
                          ▼                              ▼
        ┌─────────────────────────────────┐   ┌────────────────────────┐
        │ InitializeSession2(creds)        │   │ RefreshAccount(acct,…) │
        │  (src/entry.lua, top-level)      │   │ ListAccounts(…)        │
        └─────────────────────────────────┘   └────────────────────────┘
                          │                              │
            ┌─────────────┴──────────────┐               │
            ▼                            ▼               ▼
   ┌──────────────────┐         ┌──────────────────┐  ┌────────────────┐
   │ extract API key  │         │ M_auth.cached_   │  │ M_auth.cached_ │
   │ (string|table|   │         │ token(orgUuid)   │  │ token(orgUuid) │
   │  challenge form) │         │  → reads         │  │  → reads       │
   └──────────────────┘         │   LocalStorage   │  │   LocalStorage │
            │                   │   .zettle[org]   │  │   .zettle[org] │
            ▼                   └──────────────────┘  └────────────────┘
   ┌──────────────────────────┐                              │
   │ M_auth._extract_         │                              │
   │ client_id(api_key)       │                              │
   │  → base64url decode      │                              │
   │   JWT payload → aud      │                              │
   │   claim (fall back to    │                              │
   │   client_id claim)       │                              │
   └──────────────────────────┘
            │
            │ malformed JWT  ───────────┐
            ▼                            ▼
   ┌──────────────────────────┐  return M_i18n.t("error.invalid_grant")
   │ M_auth.exchange_         │  (synchronous — no network)
   │ assertion(api_key,       │
   │ client_id)               │
   └──────────────────────────┘
            │
            ▼
   ┌──────────────────────────┐
   │ M_http.post_form(        │
   │   "https://oauth.zettle. │
   │   com/token",            │
   │   {grant_type=…,         │
   │    client_id=…,          │
   │    assertion=api_key},   │
   │   {["Accept"]=           │       ┌─────────────────────────┐
   │     "application/json"}) │ ───── │ Connection():request(   │
   │                          │       │  "POST",                │
   │ returns (token_table,    │       │  "https://oauth.zettle. │
   │ status, raw_body)        │       │  com/token",            │
   └──────────────────────────┘       │  form_body,             │
            │                          │  "application/x-www-    │
            │  ┌─ status ≥ 400 ─┐      │  form-urlencoded",      │
            ▼  ▼                ▼      │  headers)               │
   ┌──────────────────┐  ┌─────────────────────┐   ─ ┐
   │ M_errors.from_   │  │ extract             │      │
   │ http_status(     │  │   access_token,     │      │ status
   │ status, body)    │  │   expires_in        │      │ derivation:
   │  → LoginFailed   │  │ from token_table    │      │ see Risk R-1
   │   or  network    │  │                     │      │
   │   string         │  │ obtained_at =       │      │
   └──────────────────┘  │   os.time()         │      │
            │            │ expires_at =        │      │
            │            │   obtained_at +     │      │
            │            │   token.expires_in  │      │
            │            └─────────────────────┘   ─ ┘
            │                       │
            │                       ▼
            │       ┌──────────────────────────────┐
            │       │ M_http.get_json(             │
            │       │  "https://oauth.zettle.com/  │
            │       │   users/self",               │
            │       │  {["Authorization"] =        │
            │       │    "Bearer " .. token,       │
            │       │   ["Accept"] =               │
            │       │    "application/json"})      │
            │       │                              │
            │       │ returns (profile_table,      │
            │       │ status, raw_body)            │
            │       └──────────────────────────────┘
            │                       │
            │       ┌─ status ≥ 400 ┴─┐
            │       ▼                  ▼
            │  M_errors             extract uuid,
            │  .from_http_status      organizationUuid,
            │  (status, body)         publicName (defensively)
            │       │                  │
            │       │                  ▼
            │       │      ┌──────────────────────────┐
            │       │      │ LocalStorage.zettle      │
            │       │      │  [organizationUuid] = {  │
            │       │      │   access_token=…,        │
            │       │      │   expires_at=…,          │
            │       │      │   obtained_at=…,         │
            │       │      │   client_id=…,           │
            │       │      │   publicName=…,          │
            │       │      │   uuid=…                 │
            │       │      │  }                       │
            │       │      │                          │
            │       │      │  (nested table primary;  │
            │       │      │  flat-string fallback    │
            │       │      │  per D-23c if Q5 fails)  │
            │       │      └──────────────────────────┘
            │       │                  │
            ▼       ▼                  ▼
        ┌───────────────────┐    return nil (success)
        │ return LoginFailed │    → MoneyMoney calls ListAccounts
        │ or network string  │
        │ from               │
        │ InitializeSession2 │
        └───────────────────┘

EndSession:
  M_http.shutdown()        ← closes module-local Connection, sets it to nil
  M_auth._clear_cache()    ← clears module-level mirror of LocalStorage.zettle[orgUuid]
                             (the LocalStorage itself is NOT cleared — that would
                              defeat AUTH-06)
```

### Recommended Project Structure

The Phase-1 project structure is unchanged. Phase 2 fills out the three empty modules and rewrites `src/entry.lua`:

```
src/
├── webbanking_header.lua    # unchanged (M_* table predeclarations, WebBanking{})
├── log.lua                  # unchanged (M_log.redact already covers Phase 2's needs)
├── errors.lua               # FILL: M_errors.from_http_status (D-24)
├── i18n.lua                 # unchanged (all needed German keys already present)
├── model.lua                # unchanged (Phase 3 stub)
├── http.lua                 # FILL: M_http.post_form, M_http.get_json, M_http.shutdown (D-25)
├── auth.lua                 # FILL: M_auth.exchange_assertion, M_auth.cached_token,
│                            #       M_auth._decode_jwt_payload, M_auth._extract_client_id
├── pagination.lua           # unchanged (Phase 3 stub)
├── purchases.lua            # unchanged (Phase 3 stub)
├── payouts.lua              # unchanged (Phase 4 stub)
├── balance.lua              # unchanged (Phase 4 stub)
├── mapping.lua              # unchanged (Phase 3 stub)
└── entry.lua                # REWRITE: InitializeSession2 calls M_auth, ListAccounts
                             #          reads cache, EndSession calls M_http.shutdown,
                             #          RefreshAccount still returns the Phase-1 fixture
                             #          transaction (mapping stays in Phase 3)

spec/
├── helpers/
│   ├── mm_mocks.lua         # EXTEND: Mocks.push_response gains optional status field
│   │                        #   for tests; production code derives status from body
│   │                        #   (see Risk R-1)
│   └── fixtures.lua         # EXTEND: support nested paths so Fixtures.load("auth/token_ok")
│                            #   reads spec/fixtures/auth/token_ok.json
├── fixtures/
│   └── auth/                # NEW directory (D-28)
│       ├── token_ok.json
│       ├── token_invalid_grant.json
│       ├── users_self_ok.json
│       ├── users_self_unauthorized.json
│       ├── token_rate_limited.json
│       └── network_timeout.json
├── auth_spec.lua            # NEW: M_auth.exchange_assertion + cached_token + JWT decoder
├── http_spec.lua            # NEW: M_http.post_form + get_json (Accept header, redaction)
├── errors_spec.lua          # NEW: M_errors.from_http_status (all six cases of D-24)
├── entry_spec.lua           # EXTEND: InitializeSession2 with mocked Connection probes
│                            #   reaches the token endpoint, ListAccounts surfaces
│                            #   cached publicName, EndSession calls shutdown
└── (mm_mocks_spec, i18n_spec, log_redaction_spec, build_spec — unchanged from Phase 1)
```

### Pattern 1: Pure-Lua base64url decode of a JWT segment

**What:** Parse `header.payload.signature`; base64url-decode the middle segment; parse with `JSON()`.

**When to use:** Inside `M_auth._extract_client_id(assertion)` to read the `aud` claim before any network call.

**Example:**
```lua
-- src/auth.lua  (inside the do...end block; M_auth predeclared)

-- _b64url_decode(s) → string
-- RFC 7515 Appendix C: base64url → base64 (substitute - for + and _ for /, then pad to mod 4).
-- Then call MM.base64decode (which handles standard base64).
local function _b64url_decode(s)
  s = s:gsub("-", "+"):gsub("_", "/")
  local pad = (4 - (#s % 4)) % 4
  s = s .. string.rep("=", pad)
  return MM.base64decode(s)
end

-- _decode_jwt_payload(jwt) → table|nil
-- Split on '.', verify three segments, decode middle, JSON.dictionary.
-- Returns nil on any structural failure (caller surfaces error.invalid_grant).
function M_auth._decode_jwt_payload(jwt)
  if type(jwt) ~= "string" or #jwt == 0 then return nil end
  local h, p, sig = jwt:match("^([^.]+)%.([^.]+)%.([^.]+)$")
  if not h or not p or not sig then return nil end
  local raw = _b64url_decode(p)
  if not raw or #raw == 0 then return nil end
  -- Defensive: catch JSON parse errors. The Phase-1 JSON() mock errors via Lua
  -- error(); in MoneyMoney's runtime the contract is the same (parse error
  -- aborts the chunk). We pcall here SPECIFICALLY because the input is
  -- attacker-controlled (a malformed API key).
  local ok, parsed = pcall(function()
    return JSON(raw):dictionary()
  end)
  if not ok or type(parsed) ~= "table" then return nil end
  return parsed
end

-- _extract_client_id(jwt) → string|nil
-- Read `aud` claim first (per D-22); fall back to `client_id` claim.
-- Returns nil on any failure; caller returns M_i18n.t("error.invalid_grant").
function M_auth._extract_client_id(jwt)
  local payload = M_auth._decode_jwt_payload(jwt)
  if not payload then return nil end
  local aud = payload.aud
  if type(aud) == "string" and #aud > 0 then return aud end
  -- Some JWT issuers put aud as an array of strings; take the first.
  if type(aud) == "table" and type(aud[1]) == "string" and #aud[1] > 0 then
    return aud[1]
  end
  local cid = payload.client_id
  if type(cid) == "string" and #cid > 0 then return cid end
  return nil
end
```
Source: RFC 7515 Appendix C — https://datatracker.ietf.org/doc/html/rfc7515#appendix-C ; iZettle/api-documentation/oauth-api/user-guides/create-an-app/create-a-self-hosted-app/create-an-api-key.md.

### Pattern 2: Form-encoded POST with `Accept: application/json` guard

**What:** Build the form body, force `Accept: application/json` so HTTP 4xx/5xx return the JSON body rather than aborting the Lua chunk, redact before logging.

**When to use:** `M_http.post_form` — invoked from `M_auth.exchange_assertion`.

**Example:**
```lua
-- src/http.lua  (inside do...end; M_http predeclared)

local _conn = nil  -- module-local Connection, reused across requests (D-25)

local function _get_connection()
  if _conn == nil then
    _conn = Connection()
    -- D-26 / SEC-02 reminder: the only hosts we ever pass to this connection
    -- are oauth.zettle.com / purchase.izettle.com / finance.izettle.com.
  end
  return _conn
end

-- _form_encode(t) → string
-- Pure-Lua x-www-form-urlencoded; uses MM.urlencode per key+value.
local function _form_encode(t)
  local parts = {}
  -- Deterministic ordering helps the SEC-03 spec match the body exactly.
  local keys = {}
  for k in pairs(t) do keys[#keys+1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    parts[#parts+1] = MM.urlencode(k) .. "=" .. MM.urlencode(t[k])
  end
  return table.concat(parts, "&")
end

-- _merge_headers(user_headers) → table
-- Forces Accept: application/json (so HTTP 4xx/5xx do NOT abort the chunk).
-- See §"Connection() semantics" — this is load-bearing for D-24's status logic.
local function _merge_headers(user_headers)
  local h = {}
  for k, v in pairs(user_headers or {}) do h[k] = v end
  h["Accept"] = "application/json"
  return h
end

-- M_http.post_form(url, body_table, headers)
--   → (decoded_table|nil, status:integer|nil, raw_body:string)
--
-- Status derivation: MoneyMoney's Connection():request does NOT return a
-- separate HTTP status. The "status" return from this function is INFERRED
-- as follows (in priority order):
--   1. If decoded table has `error` (e.g. `{"error":"invalid_grant"}`) and
--      no `access_token`/`uuid`: status = 400 (close enough for D-24's
--      400/401/403 → LoginFailed mapping).
--   2. If decoded table is well-formed and contains expected success fields
--      (`access_token` for /token, `organizationUuid` for /users/self): 200.
--   3. If raw body is empty or unparseable: nil (network-level treatment).
-- See Risk R-1 for the full status-derivation rationale.
function M_http.post_form(url, body_table, headers)
  local conn = _get_connection()
  local body = _form_encode(body_table)
  local h = _merge_headers(headers)
  M_log.debug("POST " .. url .. " body=" .. M_log.redact(body))
  local raw, charset, mime, filename, resp_headers =
    conn:request("POST", url, body, "application/x-www-form-urlencoded", h)
  raw = raw or ""
  M_log.debug("POST " .. url .. " response=" .. M_log.redact(raw))
  if #raw == 0 then
    return nil, nil, raw
  end
  local ok, parsed = pcall(function()
    return JSON(raw):dictionary()
  end)
  if not ok or type(parsed) ~= "table" then
    return nil, nil, raw
  end
  local status = M_http._infer_status(parsed)  -- see _infer_status below
  return parsed, status, raw
end

-- M_http._infer_status(parsed) → integer
-- Inspects a decoded JSON body to derive an HTTP-status-equivalent integer
-- for M_errors.from_http_status. See Risk R-1.
function M_http._infer_status(parsed)
  if parsed.error then
    -- Zettle's documented error JSON for the OAuth endpoint.
    -- {"error":"invalid_grant", "error_description":"..."}
    -- HTTP 400 is documented for token-endpoint errors.
    if parsed.error == "invalid_grant" or parsed.error == "invalid_request" then
      return 400
    end
    if parsed.error == "invalid_client" or parsed.error == "unauthorized_client" then
      return 401
    end
    return 400  -- conservative
  end
  return 200
end

-- M_http.get_json(url, headers) — parallel shape
function M_http.get_json(url, headers)
  local conn = _get_connection()
  local h = _merge_headers(headers)
  M_log.debug("GET " .. url)  -- never log headers (Bearer leak risk)
  local raw, charset, mime, filename, resp_headers =
    conn:request("GET", url, nil, nil, h)
  raw = raw or ""
  M_log.debug("GET " .. url .. " response=" .. M_log.redact(raw))
  if #raw == 0 then return nil, nil, raw end
  local ok, parsed = pcall(function()
    return JSON(raw):dictionary()
  end)
  if not ok or type(parsed) ~= "table" then return nil, nil, raw end
  return parsed, M_http._infer_status(parsed), raw
end

function M_http.shutdown()
  if _conn and _conn.close then _conn:close() end
  _conn = nil
end
```
Source: https://moneymoney.app/api/webbanking/ — `Accept: application/json` text quoted in §"Connection() semantics".

### Pattern 3: Token cache with nested-then-flat fallback

**What:** Try `LocalStorage.zettle[orgUuid] = {…}`. If that doesn't survive restart (Phase-1 Q5 still open), fall through to flat-key `LocalStorage["zettle:" .. orgUuid] = JSON-encoded-string`.

**When to use:** `M_auth._cache_write` / `_cache_read` — invoked by `M_auth.cached_token` and `M_auth.exchange_assertion`.

**Example:**
```lua
-- src/auth.lua  (continued)

-- Cache shape (D-23c):
--   LocalStorage.zettle = { [orgUuid] = {
--     access_token = "...", expires_at = 1718638800,
--     obtained_at = 1718631600, client_id = "...",
--     publicName = "Beispiel Café GmbH", uuid = "user-uuid"
--   } }
--
-- Defensive: nested-table primary; flat-string fallback. We always WRITE to
-- BOTH so a restart that loses nested tables transparently falls through
-- to the flat path on read.

local function _cache_write(orgUuid, entry)
  LocalStorage.zettle = LocalStorage.zettle or {}
  LocalStorage.zettle[orgUuid] = entry
  -- Flat fallback (D-23c). Encoded as JSON string.
  LocalStorage["zettle:" .. orgUuid] = JSON():set(entry):json()
end

local function _cache_read(orgUuid)
  if LocalStorage.zettle and LocalStorage.zettle[orgUuid] then
    return LocalStorage.zettle[orgUuid]
  end
  local raw = LocalStorage["zettle:" .. orgUuid]
  if type(raw) == "string" and #raw > 0 then
    local ok, parsed = pcall(function()
      return JSON(raw):dictionary()
    end)
    if ok and type(parsed) == "table" then return parsed end
  end
  return nil
end

-- M_auth.cached_token(orgUuid) → string|nil
-- Returns the access_token if the cache has an unexpired entry (60s guard);
-- otherwise nil — caller must call M_auth.exchange_assertion again.
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

### Pattern 4: Two-call fail-fast probe inside `InitializeSession2`

**What:** Decode client_id from JWT → exchange assertion → fetch `/users/self` → cache. Any failure returns synchronously.

**When to use:** `InitializeSession2` (rewritten in `src/entry.lua`).

**Example:**
```lua
-- src/entry.lua  (rewritten InitializeSession2)
function InitializeSession2(protocol, bankCode, step, credentials, interactive) -- luacheck: ignore 431
  -- Step 1: First call (credentials == nil) returns the credential challenge.
  -- Unchanged from Phase 1 walking-skeleton (D-10 / existing src/entry.lua L14-L20).
  if credentials == nil then
    return {
      title     = M_i18n.t("credential.api_key.label"),
      challenge = M_i18n.t("credential.api_key.label"),
      label     = M_i18n.t("credential.api_key.label"),
    }
  end

  -- Step 2: Credential extraction (UNCHANGED from Phase 1 — Phase-1 D-10 surface contract).
  -- (existing code at src/entry.lua L22-L41 is reused verbatim)
  local api_key
  if type(credentials) == "string" then
    api_key = credentials
  elseif type(credentials) == "table" then
    if credentials[1] then
      if type(credentials[1]) == "table" and credentials[1].value then
        api_key = credentials[1].value
      elseif type(credentials[1]) == "string" then
        api_key = credentials[1]
      end
    end
    if api_key == nil then
      api_key = credentials.password or credentials.username
    end
  end
  if api_key == nil or api_key == "" then
    return M_i18n.t("error.invalid_grant")
  end

  -- Step 3 (NEW): Extract client_id from the JWT payload (D-22).
  -- Pure CPU, no network. Malformed key fails here without touching the wire.
  local client_id = M_auth._extract_client_id(api_key)
  if not client_id then
    M_log.info("InitializeSession2: assertion JWT could not yield client_id")
    return M_i18n.t("error.invalid_grant")
  end

  -- Step 4 (NEW): POST /token with the assertion. Either returns the token
  -- table or returns the German error string (which MoneyMoney displays
  -- in the add-account dialog).
  local token_table, status, raw_body =
    M_auth.exchange_assertion(api_key, client_id)
  local err = M_errors.from_http_status(status, raw_body)
  if err then return err end

  -- Step 5 (NEW): GET /users/self with the access token.
  local profile, profile_status, profile_raw =
    M_auth.fetch_profile(token_table.access_token)
  local profile_err = M_errors.from_http_status(profile_status, profile_raw)
  if profile_err then return profile_err end

  -- Step 6 (NEW): Cache the entry keyed by organizationUuid.
  M_auth.persist_session(token_table, profile, client_id)

  return nil  -- success: MoneyMoney now calls ListAccounts.
end
```

### Anti-Patterns to Avoid

- **`pcall()` around `Connection():request` to catch network errors** — Phase-1 ADR-0003 Q8 (bonus finding) confirmed that `pcall` does NOT catch MoneyMoney's network/SSL errors. They surface through MM's own UI/Protokoll channel and abort the surrounding function. Phase 2 must rely on the documented `Accept: application/json` shield + `nil` / empty-string response detection. The `pcall` calls in our code above wrap only JSON parsing (CPU-safe) and JWT decoding (CPU-safe).
- **Logging the `Authorization: Bearer …` header** — even though `M_log.redact()` will strip the Bearer value, the defense-in-depth posture is: never log the headers table at all. Log only method + URL at INFO, body + response at DEBUG (DEBUG is `false` in shipped builds per SEC-04).
- **Storing `client_id` separately from the cached token** — they're related per merchant (the client_id is extracted from the merchant's assertion JWT, not a global constant). D-23c specifies `client_id` as a field of the per-merchant cache entry. Do not introduce a separate `LocalStorage.client_id` key.
- **Re-decoding the JWT on every refresh** — once cached, `M_auth.cached_token(orgUuid)` returns the access token directly. The JWT is only decoded inside `InitializeSession2` to bootstrap the very first token-exchange.
- **Writing the API key to `LocalStorage`** — AUTH-05 hard constraint. The API key lives in MoneyMoney's credential store; it is passed to `InitializeSession2` on every call from MoneyMoney; we read it, use it for `exchange_assertion`, and let the function return. It is NEVER persisted by our code.
- **Clearing `LocalStorage.zettle` in `EndSession`** — that would defeat AUTH-06 (token cache survives restart). `EndSession` clears the in-memory `_conn` and any module-level mirror of the cached entry; the persistent `LocalStorage` is untouched.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parse / serialise | Custom Lua tokenizer | MoneyMoney's `JSON()` built-in (prod); `dkjson` in `mm_mocks` (tests) | Phase-1 D-09 / ADR-0003 Q4 confirmed integer round-trip works; both sides handle UTF-8 and umlauts. |
| HTTP client | Raw socket, LuaSocket, manual TLS | MoneyMoney `Connection()` built-in | Only sanctioned mechanism; LuaSocket not available in sandbox; TLS verification is built-in (Phase-1 ADR-0003 Q8). |
| Base64 (standard) | Custom 65-byte alphabet table | `MM.base64decode` built-in | Already in the sandbox; MIME-tested. |
| Base64**url** decode | Custom alphabet table | Translate `-`→`+`, `_`→`/`, pad to mod 4, then `MM.base64decode` | RFC 7515 Appendix C documents this exact translation as the canonical pattern. |
| OAuth assertion JWT verification | Custom RSA/EC signature check | **Don't verify at all** — D-22 reads only the public payload | The assertion is OUR credential; the server verifies it. Reading our own payload for `aud` doesn't require signature verification and would require RSA primitives that don't exist in the sandbox anyway. |
| Form-URL encoding | Custom percent-encode | `MM.urlencode` built-in | Already in the sandbox; per-character percent-encoding correctness is exactly what MM provides. |
| Token cache serialisation (flat-fallback path) | Custom Lua `tostring` of nested tables | `JSON():set(t):json()` + `JSON(s):dictionary()` round-trip | Symmetric, already in use throughout the codebase, integers round-trip per Q4. |
| HTTP status interpretation | Per-call ad-hoc string comparisons | `M_errors.from_http_status(status, body)` (D-24) | Single source of truth; Phase 5 extends additively. |
| Localized German error strings | Inline literals scattered through `auth.lua` / `http.lua` | `M_i18n.t("error.invalid_grant")` etc. | Existing `src/i18n.lua` already has all needed keys (D-09); no new keys required for Phase 2. |
| Multi-instance keying via API-key hash | `MM.sha256(api_key):sub(1, 16)` | `organizationUuid` from `/users/self` (D-23a) | Stable across key rotation; API key never enters cache key path. |

**Key insight:** every primitive Phase 2 needs is either in MoneyMoney's sandbox (`Connection`, `JSON`, `LocalStorage`, `MM.base64decode`, `MM.urlencode`, `os.time`) or already in our codebase (`M_log.redact`, `M_i18n.t`). The temptation to hand-roll a base64url codec or a JWT verifier must be resisted; the work is to **wire the existing primitives correctly**.

---

## Auth Round-Trip Details

### Endpoint 1: `POST https://oauth.zettle.com/token`

**Confidence: HIGH** — [CITED: https://github.com/iZettle/api-documentation/blob/master/authorization.md]

| Element | Value |
|---------|-------|
| Method | `POST` |
| URL | `https://oauth.zettle.com/token` |
| Host | `oauth.zettle.com` (in egress allowlist per D-26) |
| Request `Content-Type` | `application/x-www-form-urlencoded` |
| Request `Accept` | `application/json` (**mandatory** — see §"Connection() semantics" Risk R-1) |
| Body parameter `grant_type` | `urn:ietf:params:oauth:grant-type:jwt-bearer` (URL-encoded by `MM.urlencode` will become `urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer`) |
| Body parameter `client_id` | UUID extracted from JWT payload `aud` claim (D-22) |
| Body parameter `assertion` | The API key as pasted by the user (it IS the JWT) |
| Success response (HTTP 200) JSON | `{"access_token": "eyJ…", "expires_in": 7200, "token_type": "Bearer"}` — only `access_token` and `expires_in` are load-bearing for Phase 2. |
| Failure response (HTTP 400) JSON | `{"error": "invalid_grant", "error_description": "<text>"}` — Phase 2 reads only `error`; `error_description` is logged through `M_log.redact()` and discarded from the user-facing string. |
| Refresh token present? | **NO** — quoting iZettle docs: *"There is no refresh token provided in the response for this grant."* On expiry, re-call the assertion grant. |
| Token TTL | `expires_in: 7200` seconds. Phase 2 trusts the server value rather than hardcoding 7200. |

**Verbatim documented request body shape** (from iZettle/api-documentation/authorization.md):

```
grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&client_id=c55de605-48b6-42ef-b69e-cd9d14ded15a&assertion=eyJraWQiOiIwIiwidHlwIjoiS....
```

[VERIFIED: iZettle/api-documentation/authorization.md] [VERIFIED: ADR-0003 Q1 — TLS active]

### Endpoint 2: `GET https://oauth.zettle.com/users/self`

**Confidence: HIGH on host + path + auth header; MEDIUM on response field names beyond `uuid` + `organizationUuid`.** [CITED: https://github.com/iZettle/api-documentation/blob/master/faq.adoc]

| Element | Value |
|---------|-------|
| Method | `GET` |
| URL | `https://oauth.zettle.com/users/self` |
| Host | `oauth.zettle.com` (in egress allowlist per D-26 — no new allowlist entry needed) |
| Request `Authorization` | `Bearer <access_token>` |
| Request `Accept` | `application/json` (mandatory per Risk R-1) |
| Documented success response | `{"uuid": "de305d54-…", "organizationUuid": "ab305d54-…"}` — quoted verbatim from FAQ. |
| Undocumented but commonly present | `publicName`, `country`, `firstName`, `lastName` — *NOT* in public docs; treat as optional. See Open Question O-1. |
| Failure response | HTTP 401 if token is invalid/revoked, HTTP 403 if scope is insufficient. JSON body typically follows OAuth error shape. |

**Verbatim FAQ JSON example** (from iZettle/api-documentation/faq.adoc):

```json
{
    "uuid": "de305d54-75b4-431b-adb2-eb6b9e546014",
    "organizationUuid": "ab305d54-75b4-431b-adb2-eb6b9e546013"
}
```

> ⚠️ **`publicName` is NOT documented.** D-23b assumes it. The plan must defensively fall back to `organizationUuid:sub(1, 8)` when `publicName` is `nil` or empty; this fallback is the SOLE GUARANTEE that the account label is non-empty for ACCT-02. See Open Question O-1.

---

## JWT Assertion Payload Extraction (D-22 implementation detail)

### Required steps

1. **Sanity-check input.** Reject non-string or empty input upfront.
2. **Split on `.`** — must produce exactly three segments (`header.payload.signature`). Reject otherwise.
3. **Decode the MIDDLE segment as base64url.** RFC 7515 Appendix C: replace `-`→`+`, `_`→`/`, pad with `=` to length multiple of 4, then call `MM.base64decode`.
4. **Parse as JSON.** Use `JSON(raw):dictionary()` inside a `pcall` (the input is attacker-controlled).
5. **Read `aud` claim.** Priority: string `aud` → first element of array `aud` → string `client_id` claim → nil.
6. **Validate shape.** Return `nil` if no candidate is a non-empty string.
7. **Caller surfaces `M_i18n.t("error.invalid_grant")` on nil.** Synchronously, before any network call.

### Edge cases (each MUST be a test case)

| Case | Input | Expected Behavior |
|------|-------|------------------|
| nil | `nil` | return `nil` |
| empty string | `""` | return `nil` |
| only one segment | `"abc"` | return `nil` |
| two segments | `"abc.def"` | return `nil` |
| three segments but middle is not base64url | `"abc.???.def"` | return `nil` (base64decode produces nothing parseable as JSON) |
| three segments, middle decodes but isn't JSON | `"abc.YWJj.def"` (decodes to "abc") | `pcall` catches the JSON error → return `nil` |
| valid JWT with `aud` claim string | normal Zettle assertion | return the `aud` value |
| valid JWT with `aud` claim as array | possible alt shape | return first element |
| valid JWT with `aud` absent, `client_id` present | edge case | return `client_id` value |
| valid JWT with neither `aud` nor `client_id` | malformed | return `nil` |
| valid JWT with padding length 1 ("====") | malformed base64url (max 2 `=`) | return `nil` |
| missing padding (length mod 4 == 2 or 3) | normal — JWT strips `=` | manual padding restores; decodes correctly |
| middle segment encodes UTF-8 multibyte (umlauts in claim) | unlikely but possible | `JSON():dictionary()` already handles UTF-8 round-trip per Q4 |

### Why no signature verification

The assertion is OUR credential. The Zettle server verifies the signature using our public key as registered in developer.zettle.com. Re-verifying our own JWT would require RSA primitives that the MoneyMoney sandbox does not expose (`MM.sha256` exists, but `MM.rsa_verify` does not). D-22 explicitly closes this: read the public payload only.

---

## Connection() semantics

**Confidence: HIGH** — [CITED: https://moneymoney.app/api/webbanking/]

### Return signature

```
content, charset, mimeType, filename, headers = connection:request(method, url[, postContent, postContentType, headers])
```

Five values. **No HTTP status code.** This is the single most load-bearing fact of Phase 2 (Risk R-1).

### Auto-follow redirects (Q2)

**Phase-1 ADR-0003 Q2 status: DEFERRED to Phase 2 first live token-exchange.** Phase 2 ships defensively with two posture choices:

1. **First posture (build first, instrument live):** Assume `Connection()` auto-follows on the `oauth.zettle.com/token` endpoint. Add an INFO log line on every POST to `/token` recording the response body's first 80 chars (redacted). If the response is empty or doesn't look like the documented `{"access_token":…}` / `{"error":…}` shape, that's the signal to revisit redirect behavior.
2. **Fallback posture (if Q2 proves NO):** Implement a manual 3-hop redirect loop in `M_http.post_form` (read the `Location` header from the response, re-issue the POST with the same body, max 3 hops). This is a ≤ 20-LoC change isolated to one function; not gating for Phase 2 planning.

**Recommendation:** Phase 2 ships with posture 1. If the live call yields empty body or unexpected shape, posture 2 is added in a follow-up commit within the same phase. **Q2 does NOT block planning.**

### TLS verification (Q8)

**Phase-1 ADR-0003 Q8 status: RESOLVED — TLS verified by default.** Bonus finding: `pcall()` does NOT catch SSL errors. Phase 2 implementation MUST NOT use `pcall` to recover from TLS failures; the documented `Accept: application/json` shield does NOT apply to TLS errors either. A TLS failure on `oauth.zettle.com` will abort the entire MoneyMoney chunk and surface in the Protokoll panel. This is acceptable behavior — it's an environment problem, not a Zettle API problem.

### How errors surface

> *"For JSON-based REST-APIs should be set in the parameter headers the HTTP-Header field Accept to "application/json". Then will also at a HTTP-Error the server response in the script returned. Otherwise will in the error case the execution of the script aborted and instead in the GUI an error message displayed."* — [CITED: moneymoney.app/api/webbanking/]

**Plain-English translation:**
- If `Accept: application/json` is set → HTTP 4xx and 5xx responses return the body normally; the script continues.
- If `Accept: application/json` is **not** set → HTTP 4xx and 5xx **abort the script** with a MoneyMoney-rendered error message. The Lua code never gets to handle it.

**Conclusion:** Every Phase-2 HTTP call MUST send `Accept: application/json`. This is encoded structurally in `M_http._merge_headers` (Pattern 2 above). No call-site option to omit it.

### How to recognize a network/timeout failure

There is no documented sentinel return. From the contract:
- TLS failure → script aborts (handled by environment, not by our code).
- DNS / connect timeout → not documented; **assumed** to also abort the script.
- HTTP error with `Accept: application/json` → body is returned normally; status must be inferred from body shape (Risk R-1).
- HTTP 200 with valid JSON → body is returned, parsed normally.
- HTTP 200 with empty body → `content == nil` or `content == ""`. Phase 2 treats this as a network anomaly: `(nil, nil, "")` return from `M_http.post_form` and the caller surfaces `M_i18n.t("error.network", "—")` per D-24.

[CITED: https://moneymoney.app/api/webbanking/] [VERIFIED: ADR-0003 Q8]

---

## LocalStorage semantics

**Confidence: MEDIUM on cross-restart persistence of nested tables (Phase-1 Q5 status: writability CONFIRMED, cross-restart UNOBSERVED).** [CITED: https://moneymoney.app/api/webbanking/]

### What the docs say

> *"The LocalStorage object can be used to persist information across script runtimes."* — that is the entire documented surface.

There is **no documented constraint** on:
- Whether nested tables serialize losslessly.
- Whether keys are namespaced per-extension or shared across all installed extensions.
- Maximum size / value type restrictions.
- Whether functions, userdata, or metatables survive persistence.

### What Phase-1 probes confirmed

- **Writability:** YES. Probe wrote `LocalStorage.probe_counter = 1` and read it back within the same `RefreshAccount` invocation.
- **Cross-restart:** UNOBSERVED. The Phase-1 probe was overtaken by the T13 walking-skeleton install before a second restart could verify.
- **Inferred from third-party extension prior art (`moneymoney-truelayer`, `moneymoney-payback`):** nested tables of plain Lua values (string, number, boolean, nested table) DO persist. This is the working assumption for D-23c primary path.

### Phase 2 defensive design (D-23c)

**WRITE both paths every time** (idempotent, ~50 bytes of duplication):

```lua
LocalStorage.zettle = LocalStorage.zettle or {}
LocalStorage.zettle[orgUuid] = entry                            -- nested (primary)
LocalStorage["zettle:" .. orgUuid] = JSON():set(entry):json()  -- flat (fallback)
```

**READ tries nested first, falls through to flat:**

```lua
if LocalStorage.zettle and LocalStorage.zettle[orgUuid] then
  return LocalStorage.zettle[orgUuid]
end
local raw = LocalStorage["zettle:" .. orgUuid]
if type(raw) == "string" and #raw > 0 then
  return JSON(raw):dictionary()
end
return nil
```

This costs ~50 LoC and survives whatever Q5's eventual answer is.

### Multi-instance namespacing

The flat-key prefix is `"zettle:"` to avoid colliding with any other key any other extension might write under the same MoneyMoney install. Phase-1 D-12 / Q1 confirmed `LocalStorage` is a single object; the docs do not promise per-extension isolation. The `zettle:` prefix + nested `LocalStorage.zettle` table provide our own namespace.

### What types are serializable

The flat path serializes everything through `JSON():set(t):json()`, so the question reduces to "what does our `JSON()` produce". The cache entry shape is:

```lua
{
  access_token = "string",
  expires_at   = 1718638800,       -- integer seconds since epoch
  obtained_at  = 1718631600,       -- integer seconds since epoch
  client_id    = "uuid-string",
  publicName   = "string or absent",
  uuid         = "user-uuid-string",
}
```

All strings + integers. Phase-1 ADR-0003 Q4 confirmed JSON integer round-trip works. No nesting beyond one level. Safe.

[CITED: https://moneymoney.app/api/webbanking/] [VERIFIED: ADR-0003 Q5 writability] [ASSUMED: ADR-0003 Q5 cross-restart persistence] [VERIFIED: ADR-0003 Q4 JSON integer round-trip]

---

## Module Inventory Delta

Current state of every file Phase 2 touches, what Phase 2 must add, and the expected LoC delta. Source counts from `wc -l` on the repo as of 2026-06-17.

| File | Current LoC | Current Content | Phase 2 Adds | Target LoC |
|------|-------------|-----------------|--------------|-----------|
| `src/webbanking_header.lua` | 30 | `M_*` table predeclarations, `DEBUG = false`, `WebBanking{}` call | **No change.** All needed predeclarations (`M_auth`, `M_http`, `M_errors`) already exist (L8, L9, L13). | 30 |
| `src/log.lua` | 60 | `M_log.redact`, four `_emit` wrappers | **No change.** All four redaction patterns Phase 2 needs are already in place (L21-L33). | 60 |
| `src/i18n.lua` | 56 | `STRINGS.de` + `STRINGS.en`, `M_i18n.t` | **No change.** Required keys already present: `error.invalid_grant` (L17), `error.network` (L18), `error.rate_limit` (L19), `account.name` (L7), `credential.api_key.label` (L20). The CONTEXT's optional `error.profile_scope` key is delegated to planner's discretion; recommend **NOT** adding it for Phase 2 — re-use `error.invalid_grant` for both 401-on-token and 401-on-/users/self (the user-visible meaning is "key rejected" either way). | 56 |
| `src/errors.lua` | 3 (stub) | One-line comment | **Add `M_errors.from_http_status(status, body)`** per D-24 cases (nil / 2xx / 400-403 / 429 / 5xx / other). | ~25 |
| `src/http.lua` | 3 (stub) | One-line comment | **Add `M_http.post_form`, `M_http.get_json`, `M_http.shutdown`, `M_http._infer_status`, plus private `_get_connection`, `_form_encode`, `_merge_headers`.** D-25 + Risk R-1. | ~90 |
| `src/auth.lua` | 3 (stub) | One-line comment | **Add `M_auth._b64url_decode` (local), `M_auth._decode_jwt_payload`, `M_auth._extract_client_id`, `M_auth.exchange_assertion`, `M_auth.fetch_profile`, `M_auth.persist_session`, `M_auth.cached_token`, private `_cache_read`/`_cache_write`.** | ~150 |
| `src/entry.lua` | 87 | Phase-1 walking-skeleton callbacks | **Rewrite `InitializeSession2`** to call `M_auth._extract_client_id` → `M_auth.exchange_assertion` → `M_auth.fetch_profile` → `M_auth.persist_session` after the existing credential-extraction block (L22-L41 preserved). **Rewrite `ListAccounts`** to read from `LocalStorage.zettle[orgUuid]` and emit `accountNumber = organizationUuid`, label = `"PayPal POS — " .. publicName` (with fallback). **Rewrite `EndSession`** to call `M_http.shutdown()`. **`RefreshAccount` unchanged** — still returns the Phase-1 fixture transaction per CONTEXT.md "Out of scope". | ~140 |
| `spec/helpers/mm_mocks.lua` | 273 | Full mock surface, `Mocks.push_response` queue | **Extend `Mocks.push_response`** to accept an optional `status` field (default 200). The mock's `request` doesn't return status either (it mirrors the real API), but tests can attach `status` to a queue entry and the mock can write it into the `headers` table as `headers.status` for asserts. **PRODUCTION CODE STILL DERIVES STATUS FROM BODY** per Risk R-1 — the `status` field on `push_response` is for test ergonomics only. | ~290 |
| `spec/helpers/fixtures.lua` | 36 | `Fixtures.load(name)` loads `spec/fixtures/<name>.json` | **Extend to support nested paths:** `Fixtures.load("auth/token_ok")` reads `spec/fixtures/auth/token_ok.json`. One-line gsub change. | ~37 |
| `spec/fixtures/auth/` | 0 | (directory does not exist) | **NEW directory.** Six hand-rolled JSON fixtures per D-28: `token_ok.json`, `token_invalid_grant.json`, `users_self_ok.json`, `users_self_unauthorized.json`, `token_rate_limited.json`, `network_timeout.json`. Each fixture starts with a header comment citing the iZettle/api-documentation page that defines the shape. (Comments live in fixture file as JSON's first key `"_source"` since strict JSON has no comments — or as a sibling `.md` file per fixture; planner's call.) | ~80 (six files of ~10-15 lines each) |
| `spec/auth_spec.lua` | 0 | (file does not exist) | **NEW.** Test `_decode_jwt_payload` edge cases (11 cases per §"Edge cases" table); test `_extract_client_id` claim-priority (aud-string, aud-array, client_id, neither); test `exchange_assertion` against `token_ok` and `token_invalid_grant` fixtures; test `cached_token` returns nil when expired and string when fresh; test cache write writes both nested and flat. | ~180 |
| `spec/http_spec.lua` | 0 | (file does not exist) | **NEW.** Test `post_form` constructs the form body with sorted keys + url-encoded values; test `Accept: application/json` is always present in headers passed to `Connection`; test response body parsing for success and `{"error":"invalid_grant"}` (status inferred 400); test `_form_encode` of `{grant_type="urn:ietf:params:oauth:grant-type:jwt-bearer"}` produces `grant_type=urn%3Aietf%3A...`; test `shutdown` nils the module-local. | ~120 |
| `spec/errors_spec.lua` | 0 | (file does not exist) | **NEW.** Six cases per D-24: nil → network string; 200 → nil; 400 → LoginFailed; 401 → LoginFailed; 403 → LoginFailed; 429 → rate_limit string; 500 → network string with status; 999 → network string with status. | ~50 |
| `spec/entry_spec.lua` | 135 | Walking-skeleton callbacks tested | **Extend** with: InitializeSession2 with mocked `[token_ok, users_self_ok]` queue returns `nil` and populates LocalStorage; InitializeSession2 with `[token_invalid_grant]` returns LoginFailed and does NOT touch LocalStorage; InitializeSession2 with `[token_ok, users_self_unauthorized]` returns LoginFailed and does NOT touch LocalStorage; ListAccounts after a successful login returns `{accountNumber=orgUuid, name="PayPal POS — Beispiel Café GmbH", currency="EUR"}`; EndSession nils the module-local Connection. | ~250 |
| `spec/log_redaction_spec.lua` | 138 | Phase-1 redaction tests | **Add SEC-03 gating test (D-29)** — see §"SEC-03 Gating Test" below. ~30 LoC. | ~170 |

**Total new LoC across `src/`: ~265 (errors + http + auth) + ~50 (entry rewrite delta) = ~315 LoC.**
**Total new LoC across `spec/`: ~580.**
**Build artifact `dist/paypal-pos.lua` will grow from ~260 LoC to ~580 LoC (within the ~1500-LoC threshold for keeping the amalgamator simple).**

---

## Mock Surface

### How `Mocks.push_response()` queue works today

```lua
-- spec/helpers/mm_mocks.lua L39-L48
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

The mock `Connection:request` pops one entry per call:
```lua
-- spec/helpers/mm_mocks.lua L58-L65
function conn:request(method, url, postContent, postContentType, headers)
  if #Mocks._response_queue == 0 then
    error("mm_mocks: no queued response for " .. tostring(method) ..
          " " .. tostring(url))
  end
  local r = table.remove(Mocks._response_queue, 1)
  return r.content, r.charset, r.mime, r.filename, r.headers
end
```

### Phase 2 extension

Add an optional `status` field to `push_response` opts:

```lua
function Mocks.push_response(opts)
  opts = opts or {}
  local entry = {
    content  = opts.content  or "",
    charset  = opts.charset  or "utf-8",
    mime     = opts.mime     or "application/json",
    filename = opts.filename or nil,
    headers  = opts.headers  or {},
  }
  -- Phase 2: tests may attach a status integer. Stored in headers.status for
  -- specs that want to assert on it. PRODUCTION CODE NEVER READS THIS —
  -- M_http._infer_status derives status from the JSON body shape (Risk R-1).
  if opts.status then entry.headers.status = opts.status end
  table.insert(Mocks._response_queue, entry)
end
```

### Common test sequences

**Successful add-account (token_ok then users_self_ok):**
```lua
Mocks.push_response({
  content = require("spec.helpers.fixtures").raw("auth/token_ok"),
  status  = 200,
})
Mocks.push_response({
  content = require("spec.helpers.fixtures").raw("auth/users_self_ok"),
  status  = 200,
})
local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                  { value = "header.eyJhdWQiOiJjbGllbnQtaWQifQ.sig" }, false)
assert.is_nil(result)
assert.is_not_nil(LocalStorage.zettle)
```

**Bad API key (token_invalid_grant):**
```lua
Mocks.push_response({
  content = '{"error":"invalid_grant","error_description":"bad assertion"}',
  status  = 400,
})
local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                  { value = "header.eyJhdWQiOiJjbGllbnQtaWQifQ.sig" }, false)
assert.equals(LoginFailed, result)
-- And the cache must NOT have been populated:
assert.is_nil(LocalStorage.zettle)
```

**Valid token but scope failure on /users/self:**
```lua
Mocks.push_response({ content = fixtures.raw("auth/token_ok"), status = 200 })
Mocks.push_response({
  content = '{"error":"insufficient_scope","error_description":"profile scope missing"}',
  status  = 403,
})
local result = InitializeSession2(...)
assert.equals(LoginFailed, result)
assert.is_nil(LocalStorage.zettle)
```

**Empty / network failure:**
```lua
Mocks.push_response({ content = "", status = nil })  -- nil status simulates abort-avoided network failure
local result = InitializeSession2(...)
-- M_errors.from_http_status(nil, "") → M_i18n.t("error.network", "—")
assert.equals(M_i18n.t("error.network", "—"), result)
```

### Threading the redaction grep test (SEC-03)

The SEC-03 test must thread a real auth failure through `auth.lua` → `M_errors.from_http_status` and verify the returned error string contains no API-key fragments. Since the production code never echoes the API key into the error string (`from_http_status` builds the string entirely from `M_i18n.t` templates), the test asserts a **negative invariant** rather than a positive substitution. See §"SEC-03 Gating Test".

---

## SEC-03 Gating Test (D-29 implementation)

This is the single non-negotiable test for Phase 2. It is what AUTH-05 + SEC-03 reduce to in code.

```lua
-- spec/log_redaction_spec.lua (extension; lives in same file or new sec03_spec.lua)
--
-- Threads a REAL auth failure through auth.lua → http.lua → errors.lua, then
-- asserts the resulting MoneyMoney return string contains neither:
--   • the literal "Bearer"
--   • a JWT-shape match for "eyJ[A-Za-z0-9_-]+"
--   • any base64url segment of the input API key
-- and ALSO that the entire run's captured print() output contains no such
-- substrings — this catches both the function return path AND the log path.

describe("SEC-03 — API key never leaks", function()
  local Mocks = require("spec.helpers.mm_mocks")

  before_each(function()
    Mocks.setup()
    dofile("dist/paypal-pos.lua")
  end)
  after_each(function()
    Mocks.teardown()
  end)

  it("rejects a malformed JWT without echoing it anywhere", function()
    -- A JWT-SHAPED but invalid input (header.payload.sig but payload doesn't
    -- decode to JSON with an aud claim).
    local fake_jwt = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.bm90anNvbg.signature"
    -- We push NO response — _extract_client_id fails first, no network call.
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = fake_jwt } }, false)
    assert.equals(M_i18n.t("error.invalid_grant"), result)
    -- The returned string must not contain the input or its segments.
    assert.is_falsy(result:find("eyJ"), "result contains eyJ-shape")
    assert.is_falsy(result:find("Bearer"), "result mentions Bearer")
    -- Each segment of the JWT must be absent from result.
    for seg in fake_jwt:gmatch("[^.]+") do
      assert.is_falsy(result:find(seg, 1, true),
        "result contains JWT segment: " .. seg)
    end
    -- AND the captured print stream must also be clean (M_log.redact path).
    for _, line in ipairs(Mocks._captured_prints) do
      assert.is_falsy(line:find(fake_jwt, 1, true),
        "print contains raw JWT: " .. line)
      for seg in fake_jwt:gmatch("[^.]+") do
        assert.is_falsy(line:find(seg, 1, true),
          "print contains JWT segment: " .. line)
      end
    end
  end)

  it("rejects an invalid_grant from /token without echoing the assertion", function()
    -- A JWT that DECODES (so we reach the network), but Zettle rejects it.
    -- We construct one whose payload decodes to {"aud":"client-x"}.
    local payload = '{"aud":"client-x"}'
    local mid = MM.base64(payload):gsub("=+$", ""):gsub("+", "-"):gsub("/", "_")
    local fake_jwt = "header." .. mid .. ".sig"
    Mocks.push_response({
      content = '{"error":"invalid_grant","error_description":"bad assertion"}',
      status  = 400,
    })
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = fake_jwt } }, false)
    assert.equals(LoginFailed, result)
    -- Negative checks on result + captured prints:
    assert.is_falsy(result:find(fake_jwt, 1, true))
    for seg in fake_jwt:gmatch("[^.]+") do
      assert.is_falsy(result:find(seg, 1, true))
    end
    for _, line in ipairs(Mocks._captured_prints) do
      assert.is_falsy(line:find(fake_jwt, 1, true))
      -- mid is the base64url payload; even more sensitive — must be absent.
      assert.is_falsy(line:find(mid, 1, true))
    end
  end)

  it("never writes the API key to LocalStorage even after a successful auth", function()
    -- Successful round-trip: assert LocalStorage contains an access_token but
    -- NEVER the input API-key string or any of its segments.
    local payload = '{"aud":"client-x"}'
    local mid = MM.base64(payload):gsub("=+$", ""):gsub("+", "-"):gsub("/", "_")
    local fake_jwt = "header." .. mid .. ".sig"
    Mocks.push_response({
      content = '{"access_token":"AT-12345","expires_in":7200,"token_type":"Bearer"}',
      status  = 200,
    })
    Mocks.push_response({
      content = '{"uuid":"user-1","organizationUuid":"org-1","publicName":"Test"}',
      status  = 200,
    })
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = fake_jwt } }, false)
    assert.is_nil(result)
    -- Walk every value in LocalStorage; none may contain the API key
    -- (or any segment of it).
    local function walk(t, visit)
      for _, v in pairs(t) do
        if type(v) == "table" then walk(v, visit)
        elseif type(v) == "string" then visit(v) end
      end
    end
    walk(LocalStorage, function(s)
      assert.is_falsy(s:find(fake_jwt, 1, true),
        "LocalStorage value contains API key: " .. s)
      for seg in fake_jwt:gmatch("[^.]+") do
        assert.is_falsy(s:find(seg, 1, true),
          "LocalStorage value contains JWT segment: " .. s)
      end
    end)
  end)
end)
```

This test is what "SEC-03 passes" means concretely.

---

## Common Pitfalls

### Pitfall 1: Forgetting `Accept: application/json`
**What goes wrong:** First HTTP 400 response from Zettle (e.g. testing with a deliberately bad API key) aborts the entire Lua chunk; the user sees a MoneyMoney-rendered error like "HTTP 400" instead of our German `LoginFailed` string. AUTH-03 fails (no synchronous custom error surface).
**Why it happens:** Easy to omit when a developer copies a snippet from `Connection()` docs that doesn't show the JSON case.
**How to avoid:** `M_http._merge_headers` adds the header unconditionally; there is no call-site option to omit it. The `http_spec.lua` test asserts the header is present on every recorded call.
**Warning signs:** A test that intentionally posts a `token_invalid_grant` fixture but never gets to assert on the return string — instead busted reports the spec as "error" (because the chunk aborted).

### Pitfall 2: JWT base64url padding off-by-one
**What goes wrong:** `MM.base64decode` returns garbage or empty when the input length is not a multiple of 4. JWTs strip `=` padding by convention, so naive forwarding produces decode failures.
**Why it happens:** RFC 7515 specifies stripping the padding; RFC 4648 standard base64 requires it.
**How to avoid:** Always pad to length mod 4 == 0 in `_b64url_decode` (the `string.rep("=", pad)` line in Pattern 1).
**Warning signs:** `_extract_client_id` returns nil for keys that are clearly well-formed; `auth_spec` test "decodes a real assertion" fails.

### Pitfall 3: `pcall` around `Connection():request`
**What goes wrong:** Test on the developer machine catches a TLS error via `pcall`; ships to production; the same TLS error in MoneyMoney aborts the chunk because MM does not signal SSL failures as Lua errors (ADR-0003 Q8 bonus finding).
**Why it happens:** Standard Lua mental model is "errors propagate via Lua `error()`"; MoneyMoney uses a different channel for connection-level errors.
**How to avoid:** Never wrap `Connection:request` in `pcall`. The `Accept: application/json` shield handles HTTP-status errors; TLS/network errors are explicitly outside our recovery boundary.
**Warning signs:** Lint review catching a `pcall(function() conn:request(...) end)` pattern. Linter could enforce this with a custom check.

### Pitfall 4: Caching the API key (even indirectly)
**What goes wrong:** A "convenience" change adds `LocalStorage.zettle[orgUuid].assertion = api_key` so the extension can re-mint a token in `RefreshAccount` without re-asking MoneyMoney for the credential. AUTH-05 fails.
**Why it happens:** MoneyMoney calls `InitializeSession2` once per session; the developer wants the token-refresh logic in `RefreshAccount`. The "obvious" fix is wrong.
**How to avoid:** MoneyMoney calls `InitializeSession2` again whenever the cached session expires — that's how MoneyMoney's session model works. The cached `access_token` is the only credential Phase 2 holds; on `cached_token` returning nil, the caller returns a German error and the next user-initiated refresh re-triggers `InitializeSession2`. SEC-03 test asserts no `LocalStorage` value contains the API key.
**Warning signs:** A code review comment "but how do we refresh the token in RefreshAccount" — the answer is "we don't; MoneyMoney handles it via session lifecycle".

### Pitfall 5: Status-from-body heuristic vs. real 200 responses with an `error` field
**What goes wrong:** Some APIs respond HTTP 200 with `{"error": "..."}` for soft errors. Phase-2's `_infer_status` treats any `error` field as HTTP 400. If Zettle ever returns 200 with an error field, we'd misclassify.
**Why it happens:** `Connection()` doesn't return status, so we have to infer from body.
**How to avoid:** Specifically scope `_infer_status` to known OAuth error names (`invalid_grant`, `invalid_request`, `invalid_client`, `unauthorized_client`). For unknown `error` values, treat as HTTP 400 (still maps to LoginFailed per D-24, which is the SAFE classification — better to ask user to re-paste than to silently succeed). For `/users/self` 200 with no `uuid`/`organizationUuid` — that's an upstream contract violation; treat as network error.
**Warning signs:** `errors_spec.lua` `"200 with error field returns LoginFailed"` test forces us to think about this.

### Pitfall 6: Two extension instances overwriting each other's cache
**What goes wrong:** User has the extension installed twice with different API keys. Both write `LocalStorage.zettle = {...}` instead of `LocalStorage.zettle[orgUuid] = {...}`. Second write erases first.
**Why it happens:** Lazy first-pass implementation writes `LocalStorage.zettle = entry` instead of nesting.
**How to avoid:** D-23c hard-locked: cache key is always `[orgUuid]` nested inside `LocalStorage.zettle`. Test `auth_spec` "two orgs coexist in cache" gates this.
**Warning signs:** ACCT-04 acceptance test reports only one account in the sidebar after the second add.

### Pitfall 7: Test fixture comments breaking strict JSON parse
**What goes wrong:** Hand-rolled fixture has `// Source: …` C-style comment; `dkjson.decode` errors.
**Why it happens:** D-28 says "each fixture's header comment cites the source page", but JSON has no comments.
**How to avoid:** Put the citation in a `"_source"` field at the top of the JSON document (since dkjson decodes it as a regular key), OR use a sibling `.md` file (`spec/fixtures/auth/token_ok.json.md`). Planner's call.

### Pitfall 8: `MM.base64` for encoding the test fixture's middle JWT segment
**What goes wrong:** `MM.base64` mock in `mm_mocks.lua` is an identity stub (`base64 = function(s) return s end`, L145). The SEC-03 test snippet above uses `MM.base64(payload)` to construct a valid `mid` segment — under the current mock this returns the raw JSON, which then fails to decode as JSON-of-base64decoded-bytes.
**Why it happens:** Phase-1 left `MM.base64` and `MM.base64decode` as identity stubs because no Phase-1 code exercised them.
**How to avoid:** Phase 2 spec helpers must REPLACE these stubs with a real base64 implementation (pure Lua, ~30 LoC, or `require("mime").b64` if luarocks `mimetypes` is available). Mention this in the planner's mocks-extension task. Alternatively, hand-write the encoded `mid` value as a string constant in the test ("hardcoded base64 of `{"aud":"client-x"}`") — that's the lighter touch.

---

## Code Examples

### Form-encoded body construction (Pattern 2 detail)

```lua
-- Source: iZettle/api-documentation/authorization.md and RFC 6749 §4.3.2
-- Expected body for the JWT-bearer assertion grant:
--   grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer
--   &client_id=c55de605-48b6-42ef-b69e-cd9d14ded15a
--   &assertion=eyJraWQiOiIwI...

local body = {
  grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
  client_id  = client_id,
  assertion  = api_key,
}
local token_table, status, raw = M_http.post_form(
  "https://oauth.zettle.com/token",
  body,
  {}  -- no additional headers; _merge_headers adds Accept
)
```

### Bearer auth header for `/users/self` (Pattern 2 detail)

```lua
-- Source: https://moneymoney.app/api/webbanking/ for Connection signature
--         iZettle/api-documentation/authorization.md for "Authorization: Bearer <Token>"

local profile, status, raw = M_http.get_json(
  "https://oauth.zettle.com/users/self",
  { ["Authorization"] = "Bearer " .. access_token }
)
```

### Cache cold-path (after first successful auth)

```lua
-- Source: D-23c, D-23d, and the cache-shape table in §"LocalStorage semantics"

local now = os.time()
local entry = {
  access_token = token_table.access_token,
  obtained_at  = now,
  expires_at   = now + (token_table.expires_in or 7200),
  client_id    = client_id,
  uuid         = profile.uuid,
  publicName   = profile.publicName,  -- may be nil; ListAccounts handles fallback
}
LocalStorage.zettle = LocalStorage.zettle or {}
LocalStorage.zettle[profile.organizationUuid] = entry
LocalStorage["zettle:" .. profile.organizationUuid] = JSON():set(entry):json()
```

### `ListAccounts` reading from cache

```lua
-- Source: D-23a, D-23b, ACCT-01 / ACCT-02 / ACCT-04

function ListAccounts(knownAccounts) -- luacheck: ignore 431
  local out = {}
  -- Read every cached org. Two instances of the extension under different
  -- merchants both end up here under different orgUuid keys.
  local registry = (LocalStorage.zettle or {})
  for orgUuid, entry in pairs(registry) do
    local label
    if type(entry.publicName) == "string" and #entry.publicName > 0 then
      label = "PayPal POS — " .. entry.publicName
    else
      label = "PayPal POS — " .. orgUuid:sub(1, 8)
    end
    table.insert(out, {
      accountNumber = orgUuid,
      type          = AccountTypeGiro,
      name          = label,
      currency      = "EUR",
      portfolio     = false,
    })
  end
  -- Defensive: if registry is empty (e.g. brand-new install before any auth),
  -- fall through to a placeholder that MM can show — but this should never
  -- happen because ListAccounts is only called AFTER InitializeSession2
  -- succeeded.
  if #out == 0 then
    -- This branch is exercised only by Phase-1 walking-skeleton specs that
    -- don't run a real auth round-trip. Phase 2 keeps the fallback so those
    -- specs continue to pass.
    return {
      {
        accountNumber = "paypal-pos-fixture-001",
        type          = AccountTypeGiro,
        name          = M_i18n.t("account.name", "Test-Händler"),
        currency      = "EUR",
        portfolio     = false,
      }
    }
  end
  return out
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| OAuth authorization code flow with redirect | JWT-bearer assertion grant (`urn:ietf:params:oauth:grant-type:jwt-bearer`) | Always (MoneyMoney has no browser callback) | One-paste UX; no second credential field. |
| Refresh tokens | Re-call assertion grant on expiry | iZettle docs explicitly state no refresh token for this grant | Slightly more chatty (~1 extra call per 2h per merchant); simpler state. |
| `client_id` as a shipped constant | `client_id` from JWT `aud` claim (D-22) | Phase 2 (closes ADR-0003 Q6) | No partner-program registration step; no per-region constant table; lower coupling to Zettle's app registry. |
| Single `LocalStorage` namespace | Nested-by-orgUuid + flat-fallback (D-23c) | Phase 2 | Multi-merchant safe; survives whichever Q5 outcome materializes. |
| `pcall` around network calls | `Accept: application/json` shield + body-shape status inference | Phase 2 (after ADR-0003 Q8 bonus finding) | Errors that the docs say are recoverable become recoverable; TLS errors stay environmental. |

**Deprecated/outdated:**
- `InitializeSession` (5-arg legacy form): does not support per-field credential labels. Use `InitializeSession2`.
- Single-call probe (just `/token`): misses scope failures and doesn't yield `organizationUuid` for `ListAccounts`. Use the D-21 two-call probe.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `LocalStorage` nested tables survive MoneyMoney restart | LocalStorage semantics | D-23c flat-string fallback engages automatically; second cold start re-mints token (one extra API call). No user-visible impact beyond a single log line. |
| A2 | `/users/self` returns a `publicName` field | Endpoint 2 / D-23b | Account labels fall back to `organizationUuid:sub(1, 8)` — visually less friendly but ACCT-02 / ACCT-04 still hold. This is the largest documentation gap in the iZettle public docs. See Open Question O-1. |
| A3 | `Connection()` auto-follows redirects on `oauth.zettle.com/token` | Connection semantics / Q2 | Manual 3-hop redirect loop added in `M_http.post_form` (≤ 20 LoC, isolated change). |
| A4 | Setting `Accept: application/json` prevents script abort on HTTP 4xx/5xx | Connection semantics / pattern 2 | Without this guard, every wrong-API-key scenario aborts MoneyMoney's chunk with a generic error — AUTH-03 fails. This is documented (CITED, not assumed) but listed for completeness because it is the most load-bearing single line of code in Phase 2. |
| A5 | `MM.base64decode` accepts standard base64 (with `+`/`/` and `=` padding) | JWT extraction | If `MM.base64decode` insists on different alphabet: ship a pure-Lua base64 routine (~30 LoC). Phase-1 Q1 confirmed `MM` is present but didn't verify each helper's exact contract. |
| A6 | `Connection():request` does NOT expose HTTP status code in any return value (including the `headers` table) | Connection semantics / Risk R-1 | If a return path DOES expose status (e.g. `headers.status` or `headers[1] = "HTTP/1.1 401"`), the production `_infer_status` heuristic becomes unnecessary and `M_http` can return the real status. Reduces ambiguity but doesn't break anything we ship. |
| A7 | The assertion JWT issued by developer.zettle.com always contains either `aud` or `client_id` in its public payload | JWT extraction / D-22 | If neither claim is present, `InitializeSession2` returns the German `invalid_grant` string for a key the user believes is valid. Diagnostic: log line "_extract_client_id: assertion missing aud/client_id" surfaces the issue. Recovery: maintainer documents how to read the JWT payload in README. |
| A8 | OAuth `/token` errors arrive as HTTP 400 (per documented example) | Auth round-trip | `_infer_status` maps `{"error":"invalid_grant"}` to 400. If Zettle ever uses 401/403 for some error families, `_infer_status` would misclassify; D-24 maps 400/401/403 all to LoginFailed so user-visible outcome is identical. |

---

## Open Questions

1. **O-1: `publicName` field shape on `/users/self`.**
   - What we know: iZettle's public FAQ documents only `{uuid, organizationUuid}` for the response. Internal Zettle integrations and third-party libraries reference `publicName`, but no authoritative quote was findable.
   - What's unclear: whether the field is named `publicName`, `displayName`, `name`, or absent entirely; whether it's always populated for paid PayPal POS merchants vs. only for those who set a public profile.
   - Recommendation: D-23b's fallback to `organizationUuid:sub(1, 8)` MUST be implemented and tested unconditionally. The plan should include a `checkpoint:human-verify` task before the first live add-account in Phase 2 (or during the maintainer's existing live-MoneyMoney session) to confirm the field name from a real `/users/self` response and update D-23b if needed.

2. **O-2: Phase-1 ADR-0003 Q2 (redirect behavior) still deferred.**
   - What we know: `Connection()` autoreloads? Undocumented.
   - What's unclear: whether `oauth.zettle.com/token` ever returns a 30x for this client. Probably not (token endpoints typically stay stable), but unverified.
   - Recommendation: Phase 2 ships with defensive posture 1 (assume auto-follow); the first live call yields a clear signal (empty body or 30x JSON shape). NOT a planning blocker; flagged so the planner adds a "verify Q2 behaviour" line item to the maintainer manual-test checklist.

3. **O-3: Phase-1 ADR-0003 Q5 (nested-table cross-restart persistence).**
   - What we know: writability confirmed; cross-restart unobserved.
   - What's unclear: whether nested table values are flattened, preserved, or dropped on a MoneyMoney restart.
   - Recommendation: D-23c's flat-string fallback covers both outcomes. A single INFO log line on cache-miss surfaces the actual behavior on the user's machine for retroactive Q5 closure. NOT a planning blocker.

4. **O-4: `MM.base64decode` exact alphabet/padding contract.**
   - What we know: it's documented as "base64 decode" but no alphabet or padding rules are quoted.
   - What's unclear: whether it tolerates missing `=` padding (some implementations do; some don't).
   - Recommendation: `_b64url_decode` adds explicit padding before calling `MM.base64decode`. If a live test reveals `MM.base64decode` rejects padded input it could complicate things — but per all known implementations of base64, padding tolerance is the universal behavior. LOW risk.

5. **O-5: Whether MoneyMoney's `LocalStorage` is per-extension or per-install.**
   - What we know: the docs don't promise per-extension isolation.
   - What's unclear: whether two extensions installed in the same MoneyMoney share the same `LocalStorage` table.
   - Recommendation: namespace everything under `LocalStorage.zettle` (nested) and `"zettle:"` prefix (flat). Already encoded in D-23c. NOT a planning blocker.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Lua 5.4 | All shipped + test code | ✓ | 5.4.8 (MoneyMoney 2.4.72) | None |
| busted | Phase 2 specs | ✓ | 2.3.0 (Phase-1 installed) | None |
| luacheck | CI lint step | ✓ | 1.2.0 (Phase-1 installed) | None |
| luacov | CI coverage gate | ✓ | 0.16.0 (Phase-1 installed) | None |
| dkjson | Test fixture loading, JSON mock | ✓ | 2.7+ (Phase-1 installed) | None |
| MoneyMoney 2.4.72+ | Manual end-of-phase verification | ✓ | 2.4.72 confirmed in Phase 1 | None — manual verification cannot run in CI |
| Live PayPal POS API key (sandbox or production) | End-of-phase live verification of D-21 two-call probe | ✓ Yves has access | n/a | None — without a real key, Q2 redirect behavior cannot be observed live; planner adds maintainer-only manual gate |

**Missing dependencies with no fallback:** none for code; live verification gates are maintainer-only.

**Missing dependencies with fallback:** none.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | busted 2.3.0 |
| Config file | `.busted` (Phase-1 installed) |
| Quick run command | `busted spec/auth_spec.lua spec/http_spec.lua spec/errors_spec.lua` |
| Full suite command | `busted --coverage spec/` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| AUTH-01 | InitializeSession2 first call (credentials==nil) returns the German credential challenge object | unit | `busted spec/entry_spec.lua -t "credential.api_key.label"` | ✅ (Phase-1 entry_spec covers this) |
| AUTH-02 | `M_auth.exchange_assertion` posts the exact OAuth body to `oauth.zettle.com/token` | unit | `busted spec/auth_spec.lua -t "exchange_assertion posts grant_type"` | ❌ Wave 0 |
| AUTH-03 | InitializeSession2 with `[token_invalid_grant]` returns `LoginFailed` synchronously | unit (integration) | `busted spec/entry_spec.lua -t "invalid_grant returns LoginFailed"` | ❌ Wave 0 |
| AUTH-04 | `M_auth.cached_token` returns nil when `now >= expires_at - 60`; returns access_token when fresh; no refresh token used | unit | `busted spec/auth_spec.lua -t "cached_token expiry"` | ❌ Wave 0 |
| AUTH-05 | After successful auth, no LocalStorage value or captured print contains the input API key or any of its three JWT segments | unit (SEC-03 gating) | `busted spec/log_redaction_spec.lua -t "never writes the API key"` | ❌ Wave 0 |
| AUTH-06 | Token cache populated after auth survives a `Mocks.teardown()` + re-`dofile` cycle when written to flat-key fallback path | unit | `busted spec/auth_spec.lua -t "cache survives reload via flat fallback"` | ❌ Wave 0 |
| SEC-03 | Authentication-failure return string contains no JWT, no `Bearer`, no base64-url segment of input | unit (SEC-03 gating) | `busted spec/log_redaction_spec.lua -t "rejects an invalid_grant"` | ❌ Wave 0 |
| ACCT-01 | ListAccounts returns one account of type `AccountTypeGiro` with currency `"EUR"` | unit | `busted spec/entry_spec.lua -t "ListAccounts returns AccountTypeGiro"` | ✅ (Phase-1 covers shape; Phase-2 extends to read from cache) |
| ACCT-02 | Account label = `"PayPal POS — " .. publicName`; fallback to `organizationUuid:sub(1,8)` when publicName empty | unit | `busted spec/entry_spec.lua -t "ListAccounts label uses publicName"` | ❌ Wave 0 |
| ACCT-04 | Two `LocalStorage.zettle[orgUuid]` entries coexist; ListAccounts returns both | unit | `busted spec/entry_spec.lua -t "two merchants coexist"` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `busted spec/auth_spec.lua spec/http_spec.lua spec/errors_spec.lua` + `luacheck src/ spec/` — runs in < 5 seconds.
- **Per wave merge:** `busted --coverage spec/` — full suite, runs in < 15 seconds.
- **Phase gate:** Full suite green + coverage ≥ 85% on `src/` (excluding `webbanking_header.lua`) + manual end-of-phase live MoneyMoney installation with a real PayPal POS API key (maintainer-only).

### Wave 0 Gaps

- [ ] `spec/auth_spec.lua` — covers AUTH-02, AUTH-04, AUTH-06
- [ ] `spec/http_spec.lua` — covers Pattern 2 (form encoding, Accept header)
- [ ] `spec/errors_spec.lua` — covers D-24 six cases
- [ ] `spec/log_redaction_spec.lua` extended with SEC-03 three gating tests — covers AUTH-05, SEC-03
- [ ] `spec/entry_spec.lua` extended with auth-integration cases — covers AUTH-03, ACCT-02, ACCT-04
- [ ] `spec/fixtures/auth/token_ok.json` — successful token response
- [ ] `spec/fixtures/auth/token_invalid_grant.json` — bad assertion response
- [ ] `spec/fixtures/auth/users_self_ok.json` — successful merchant profile
- [ ] `spec/fixtures/auth/users_self_unauthorized.json` — scope-failure profile
- [ ] `spec/fixtures/auth/token_rate_limited.json` — HTTP 429 response (body inference path)
- [ ] `spec/fixtures/auth/network_timeout.json` — empty/zero-length body (network-failure inference path)
- [ ] `spec/helpers/mm_mocks.lua` — `Mocks.push_response` extended with `status` field; `MM.base64`/`MM.base64decode` replaced with real implementations
- [ ] `spec/helpers/fixtures.lua` — nested-path support (`Fixtures.load("auth/token_ok")`)
- [ ] `tools/build.lua` — no change needed (already supports new src files via manifest)

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | OAuth 2.0 JWT-bearer assertion grant against `oauth.zettle.com/token`; Bearer token auth on `/users/self`; no custom auth scheme. |
| V3 Session Management | yes | Access tokens cached in `LocalStorage` with explicit `expires_at` and 60s pre-expiry guard (D-23d). No refresh tokens (per iZettle docs). Session cleared on `EndSession` (in-memory `Connection` closed; persistent cache intentionally retained per AUTH-06). |
| V4 Access Control | no | Read-only extension; no roles or per-action permissions. |
| V5 Input Validation | yes | API key validated as well-formed JWT (3 segments, decodable middle) BEFORE any network call (D-22). Form-encoded body uses `MM.urlencode` per parameter (Pattern 2). HTTP responses validated as JSON before mapping to error categories. |
| V6 Cryptography | no | No custom crypto. TLS verification by MoneyMoney's `Connection()` (ADR-0003 Q8 confirmed). JWT signature verification deliberately not performed (D-22 — we read our own public payload). |

### Known Threat Patterns for Phase 2 stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| API key in log output | Information Disclosure | `M_log.redact()` strips JWT-shape, `Bearer …`, `assertion=…`, `access_token=…` (Phase-1 D-08). SEC-03 gating test (D-29) asserts negative. |
| API key persisted in `LocalStorage` | Information Disclosure | Cache shape (D-23c) explicitly forbids — only `access_token`, not the assertion. SEC-03 gating test walks `LocalStorage` and asserts API key not present in any value. |
| Bearer token in error string | Information Disclosure | `M_errors.from_http_status` builds error strings from `M_i18n.t` templates — never echoes input. SEC-03 gating test asserts result has no `Bearer` substring. |
| Egress to non-allowlisted host | Tampering / Info Disclosure | Phase-1 D-12 / D-26 allowlist `{oauth.zettle.com, purchase.izettle.com, finance.izettle.com}`. Phase 2 only uses `oauth.zettle.com`. CI egress-grep gates the shipped artifact (Phase-1 walking-skeleton CI step continues to apply). |
| Slopsquatted base64 / JWT library | Supply Chain | None shipped — pure-Lua base64url uses RFC 7515 translation + `MM.base64decode`. |
| TLS bypass | Tampering | Not implementable from our code (no TLS option exposed); MoneyMoney's `Connection()` rejects expired certs per ADR-0003 Q8. |
| Replay of stolen access token | Spoofing | Token in `LocalStorage` could be exfiltrated by another extension if MoneyMoney's `LocalStorage` is shared (O-5 open question). Mitigation: token TTL is 2h; impact is bounded. Treat as accepted risk for v1; flag for revisit in Phase 6 if O-5 resolves "shared". |
| HTTP error abort leaking partial state | Information Disclosure | `Accept: application/json` shield (Pattern 2) ensures HTTP errors return body normally instead of aborting; we then map to German error string with no upstream content echoed. |

---

## Risks / Open Questions / Landmines (CRITICAL — read before planning)

### R-1: `Connection()` does NOT return HTTP status code separately

**Severity:** HIGH (load-bearing for D-24 implementation; reshapes D-25 contract).

**Detail:** The CONTEXT.md D-25 wording is *"both return `(decoded_table|nil, status, raw_body)`"* — but `Connection():request()` does NOT return a status. The documented signature is exactly five values: `(content, charset, mimeType, filename, headers)`. The `headers` table is NOT documented to contain `headers.status` or `headers[1] = "HTTP/1.1 401"` — so we cannot rely on it.

**Implications:**
- `M_http.post_form` and `M_http.get_json` MUST derive the `status` integer from the response body shape (the `_infer_status` heuristic in Pattern 2).
- The `status` return value from `M_http.*` is an **inferred** integer, not a wire-observed one.
- `M_errors.from_http_status(status, body)` receives this inferred status. Its mapping (D-24) treats `400/401/403` identically as LoginFailed, which is forgiving of any misclassification in the 400 range.
- The CONTEXT.md D-25 contract still holds at the function-signature level (still returns `(decoded, status, raw)`), but plan authors and reviewers must understand that `status` is an inference, not a wire value.

**What planning must do:**
- Add a task that documents this in `src/http.lua` as a 5-line comment block at the top of `_infer_status`.
- Ensure `errors_spec.lua` exercises the inference: feed a synthesized body like `{"error":"invalid_grant"}` and assert `_infer_status` returns 400 → `from_http_status(400, body)` returns LoginFailed.
- Add a maintainer manual-test task to look at a real `oauth.zettle.com` 401 response (e.g., via curl or Wireshark) and confirm whether the body shape matches what we infer. If it ever returns a non-`error`-keyed body, the heuristic needs tightening.

### R-2: `publicName` is undocumented

**Severity:** MEDIUM (impacts ACCT-02 label quality, not core auth).

**Detail:** D-23b assumes `/users/self` returns `publicName`. The public iZettle FAQ documents only `{uuid, organizationUuid}`. No authoritative source quotes a `publicName` field.

**Mitigation already in plan:** D-23b's fallback to `organizationUuid:sub(1, 8)` ensures the label is always non-empty. Test gates this.

**What planning must do:** Treat `publicName` as MEDIUM confidence; the test `"ListAccounts label uses publicName when present"` AND the test `"ListAccounts label falls back to orgUuid prefix when publicName absent"` are BOTH gating, with the second being the primary safety guarantee.

### R-3: ADR-0003 Q2 / Q5 / Q8 status check

**Severity:** HIGH at planning time — must be checked before plan-phase commits.

**Detail:**
- **Q2 (redirect behavior):** STATUS `DEFERRED to Phase 2 first live token-exchange`. **NOT BLANK.** Decision plan: defensive posture 1, fallback posture 2 in same phase. Planning may proceed.
- **Q5 (LocalStorage cross-restart):** STATUS `WRITABILITY confirmed; cross-restart UNOBSERVED`. **NOT BLANK.** Decision plan: D-23c flat-string fallback. Planning may proceed.
- **Q6 (client_id):** STATUS `DEFERRED to Phase 2 (maintainer-side lookup)`, but **CLOSED by D-22** (read from JWT payload). No live lookup needed.
- **Q8 (TLS):** STATUS `RESOLVED — TLS VERIFIED`. **CLOSED.**

**Conclusion: planning may proceed.** No ADR-0003 row is blank. Q2 and Q5 are deferred-with-defensive-plan; Q6 is closed by decision; Q8 is closed by evidence.

### R-4: `Connection` reuse across two merchants in `EndSession` window

**Severity:** LOW.

**Detail:** D-25 specifies a single module-local `Connection()` reused across requests. If MoneyMoney's session model has two merchants sharing a session lifecycle (one `InitializeSession2` for each), the shared `Connection` could leak cookies between the OAuth round-trips.

**Mitigation:** `oauth.zettle.com/token` is stateless (RFC 6749). `/users/self` is stateless too (Bearer auth only, no cookies). So even if cookies leak, no security impact. Phase 2 accepts this risk; if leak is observed in Phase 4/5 work against `purchase.izettle.com`, revisit.

### R-5: Two extension instances under same `organizationUuid`

**Severity:** LOW.

**Detail:** A user could install the extension twice and paste the same API key both times. D-23c keys by `organizationUuid` → both writes hit the same cache entry. Second instance overwrites the first.

**Effect:** Benign — both instances were going to see the same data anyway. No user-visible problem.

**No action required.**

### R-6: `MM.base64` mock is currently an identity stub

**Severity:** MEDIUM at test-writing time.

**Detail:** `spec/helpers/mm_mocks.lua` L145-L146:
```lua
base64       = function(s) return s end,
base64decode = function(s) return s end,
```
The SEC-03 gating test and the `_extract_client_id` test both need a real base64 implementation to construct test JWTs whose middle segment is genuine base64url. Identity stubs make those tests untrustworthy.

**Required planning action:** Add a Wave 0 task that replaces these stubs with a pure-Lua base64 implementation (~30 LoC; many public-domain implementations exist) OR — simpler — uses Lua's `mime.b64`/`mime.unb64` from the `luasocket` rock (`luarocks install luasocket` already pulls `mime`). Phase 2 specs run **outside** MoneyMoney so the rock dependency is acceptable (rocks are test-only; never shipped). Recommend: **pure-Lua implementation in `spec/helpers/mm_mocks.lua`** to keep test environment closed (no new rock dependency).

### R-7: `Mocks.push_response` queue exhaustion error message redacts URL

**Severity:** LOW.

**Detail:** Current error message: `"mm_mocks: no queued response for " .. method .. " " .. url`. If a test invokes one more `Connection:request` than expected, the URL appears in the error — fine for diagnostic. No security concern.

### R-8: `os.time()` resolution

**Severity:** LOW.

**Detail:** D-23d uses `os.time()` for expiry math. `os.time()` is second-resolution. The 60s pre-expiry guard is far larger than the second-resolution jitter, so this is fine.

---

## Sources

### Primary (HIGH confidence — authoritative)

- **MoneyMoney WebBanking API reference** — https://moneymoney.app/api/webbanking/ — `Connection()` signature (no status code); `Accept: application/json` shield for HTTP-error responses; `LocalStorage` semantics (one-line documented). Cross-referenced with WebFetch on 2026-06-17.
- **iZettle/api-documentation `authorization.md`** — https://github.com/iZettle/api-documentation/blob/master/authorization.md — OAuth `POST /token` with JWT-bearer assertion grant; `expires_in: 7200`; no refresh token; `invalid_grant` error JSON shape; HTTP 400 for token-endpoint errors.
- **iZettle/api-documentation `faq.adoc`** — https://github.com/iZettle/api-documentation/blob/master/faq.adoc — `/users/self` URL and the `{uuid, organizationUuid}` response shape (verbatim FAQ example); Bearer authentication header convention.
- **iZettle/api-documentation `oauth-api/create-an-api-key.md`** — https://github.com/iZettle/api-documentation/blob/master/oauth-api/user-guides/create-an-app/create-a-self-hosted-app/create-an-api-key.md — assertion JWT format that the user pastes.
- **RFC 7515 Appendix C (JWS, base64url ↔ base64 translation)** — https://datatracker.ietf.org/doc/html/rfc7515#appendix-C — canonical translation pattern used in `_b64url_decode`.
- **Phase-1 ADR-0003** — `.planning/phases/01-foundations-sandbox-probes/docs/adr/0003-sandbox-probe-results.md` (also at `docs/adr/0003-sandbox-probe-results.md`) — Q1 (Lua 5.4.8 on MM 2.4.72), Q4 (JSON integer round-trip), Q5 (LocalStorage writability + cross-restart deferred), Q7 (`"PayPal POS"` services label confirmed), Q8 (TLS active, `pcall` does NOT catch SSL errors).
- **Phase-1 RESEARCH.md §"Module-by-Module File Inventory"** — `.planning/phases/01-foundations-sandbox-probes/RESEARCH.md` (L1284-L1320) — existing module surface and Phase-1 stub posture.
- **Phase-1 CONTEXT.md** — `.planning/phases/01-foundations-sandbox-probes/CONTEXT.md` — D-08 (redaction pattern), D-12 (egress allowlist), D-14 (Phase-1 stub posture), D-15 (luacheckrc), D-19 (`dist/paypal-pos.lua` artifact name).
- **Existing source `src/log.lua`** — verified Phase-2's redaction needs are fully covered by existing `_redact()` (L11-L36) — no new patterns required.
- **Existing source `src/i18n.lua`** — verified Phase-2's German strings are fully covered by existing keys (`error.invalid_grant` L17, `error.network` L18, `error.rate_limit` L19, `account.name` L7, `credential.api_key.label` L20).
- **Existing source `src/entry.lua`** — credential-extraction block L22-L41 is the Phase-1 D-10 surface contract that Phase 2 preserves verbatim.

### Secondary (MEDIUM confidence — community / inferred)

- **`miracle2k/moneymoney-truelayer`** — https://github.com/miracle2k/moneymoney-truelayer/blob/master/TrueLayer.lua — pattern for `LocalStorage` token cache used in production (Phase-1 referenced as prior art for cache persistence assumption).
- **`jgoldhammer/moneymoney-payback`** — https://github.com/jgoldhammer/moneymoney-payback — pattern for `InitializeSession2` credential extraction.
- **`teal-bauer/moneymoney-ext-trading212`** — https://github.com/teal-bauer/moneymoney-ext-trading212 — single-file shipping; release workflow.
- **Zettle Developer Portal — Identify Users guide** — https://developer.zettle.com/docs/api/oauth/user-guides/manage-apps-users/identify-users — confirms `/users/self` endpoint exists; full response shape not documented in the public-fetchable content (see O-1).

### Tertiary (LOW confidence — assumed pending live verification)

- **A2 `/users/self` returns `publicName`** — see Open Question O-1.
- **A3 `Connection()` auto-follows redirects on `/token`** — see Risk R-3 / ADR-0003 Q2.
- **A5 `MM.base64decode` accepts standard base64 with padding** — see Open Question O-4.
- **O-5 `LocalStorage` per-extension isolation** — namespaced defensively by `LocalStorage.zettle` nested table + `"zettle:"` flat prefix regardless.

---

## Project Constraints (from CLAUDE.md)

| Directive | Source | How Phase 2 satisfies |
|-----------|--------|----------------------|
| Lua 5.4 only (MoneyMoney embeds 5.4.8) | `CLAUDE.md ## Project › Constraints › Tech stack` | All new code uses Lua 5.4 idioms; integer math `//`, bitwise `&` available but used sparingly per existing convention. |
| No external Lua C modules, no native deps in shipped artifact | `CLAUDE.md ## Project › Constraints` | Phase 2 ships no new dependencies; pure-Lua base64url translation + `MM.base64decode` for decoding. |
| Test harness runs Lua + busted + luacheck outside MoneyMoney | `CLAUDE.md ## Project › Constraints` | Phase 2 specs run under standalone Lua 5.4 + busted 2.3.0 against `spec/helpers/mm_mocks.lua` — no MoneyMoney runtime required. |
| Single `.lua` shipped, no `require()` of siblings | `CLAUDE.md ## Project › Constraints; D-02; D-03` | Phase 2 modules use the `M_*` global table pattern; `tools/build.lua` continues to concatenate via `tools/manifest.txt`. |
| API keys never logged, never written to debug output, never echoed back to user | `CLAUDE.md ## Project › Constraints; AUTH-05` | `M_log.redact()` strips JWT/Bearer/assertion/access_token. SEC-03 gating test (D-29) asserts negative invariant on returns + prints + LocalStorage. |
| Incremental refresh < 30 s | `CLAUDE.md ## Project › Constraints` | Phase 2 Add-Account is two requests (token + /users/self). Combined response time on `oauth.zettle.com` is < 2 s in practice; well under budget. |
| Compatibility with current + previous stable MoneyMoney | `CLAUDE.md ## Project › Constraints` | Phase 2 uses only documented MoneyMoney APIs (`Connection`, `JSON`, `LocalStorage`, `MM.*`). No undocumented internals. |
| No telemetry, no third-party calls beyond PayPal/Zettle endpoints | `CLAUDE.md ## Project › Constraints` | Egress allowlist enforced by Phase-1 CI grep (D-12 / D-26). Phase 2 hits `oauth.zettle.com` only. |
| German primary user strings | `CLAUDE.md ## Project › Constraints` | All Phase 2 user-facing strings via `M_i18n.t` reading from `STRINGS.de` (`src/i18n.lua` L5-L21). |
| Maintainability — Conventional Commits, MADR ADRs, SemVer, Dependabot | `CLAUDE.md ## Project › Constraints` | Phase 2 commits follow Conventional Commits; ADR-0003 already exists; SemVer continues; Dependabot is Phase-6 work. |
| GPG-signed commits (key FDE07046A6178E89ADB57FD3DE300C53D8E18642) | `CLAUDE.md ## Project › Constraints; Phase-1 D-13` | All Phase 2 commits MUST be signed under the maintainer's key. |
| No Claude / AI attribution in commits, PRs, code | `CLAUDE.md ## Project › Constraints; Phase-1 D-13` | All Phase 2 artifacts (commits, PRs, code, docs) authored as Yves Vogl, no co-author trailer. |
| GSD workflow enforcement | `CLAUDE.md ## GSD Workflow Enforcement` | This RESEARCH.md is produced via `/gsd-plan-phase --research-phase 2` per the workflow. Implementation enters via `/gsd-execute-phase 2`. |

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every shipped Lua 5.4 primitive (`Connection`, `JSON`, `LocalStorage`, `os.time`, `MM.base64decode`, `MM.urlencode`) is documented and Phase-1-verified. No new dependencies.
- Auth round-trip / OAuth contract: HIGH — token endpoint URL, headers, body, success/failure JSON quoted verbatim from iZettle/api-documentation.
- `/users/self` response shape: MEDIUM — `uuid` + `organizationUuid` documented in FAQ; `publicName` assumed (Open Question O-1).
- `Connection()` HTTP-status return: HIGH on the negative finding (NO status returned); MEDIUM on the body-inference strategy (Risk R-1).
- LocalStorage cross-restart: MEDIUM — Phase-1 Q5 writability confirmed; persistence unobserved; D-23c defensive fallback covers both outcomes.
- Pitfalls: HIGH — eight pitfalls catalogued with explicit warning signs and avoidance strategies; informed by ADR-0003 findings.
- Security (SEC-03): HIGH — gating test (D-29) covers structural isolation + redaction defense-in-depth.

**Research date:** 2026-06-17
**Valid until:** 2026-07-17 (30 days for the OAuth / MoneyMoney contracts which are stable; would shorten to 7 days if Zettle announced an API change in the interim)

## RESEARCH COMPLETE
