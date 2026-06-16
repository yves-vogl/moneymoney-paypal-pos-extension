# Phase 2: Authenticated Network Layer - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire `src/auth.lua` and `src/http.lua` (Phase-1 empty stubs) into a real OAuth round-trip against `oauth.zettle.com`, cache the access token in `LocalStorage.zettle` so it survives MoneyMoney restart, and surface a synchronous `LoginFailed` from `InitializeSession2` when the API key is rejected — without ever writing the API key to `LocalStorage`, log output, or any returned error string.

**In scope:** `M_auth.exchange_assertion()`, `M_auth.cached_token()`, `M_http.get_json()` / `M_http.post_form()`, JWT-payload decoder for `client_id` extraction, minimal `M_errors.from_http_status(status, body)`, multi-merchant cache keyed by `organizationUuid`, ListAccounts wired to the cached `publicName` + `organizationUuid` instead of the Phase-1 fixture, RefreshAccount still returning a fixture transaction (real transaction mapping is Phase 3/4).

**Out of scope:** Retry/backoff, 5xx classification beyond a single bucket, refund-specific error handling (Phase 5); purchases / payouts / finance endpoints (Phase 3/4); per-sale fee, VAT, tip rendering (Phase 4); release pipeline hardening (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### Fail-fast probe inside `InitializeSession2` (Area A)
- **D-21:** Probe strategy is **token-fetch + `/users/self`** (two round-trips). `POST oauth.zettle.com/token` with `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`, `client_id=<extracted>`, `assertion=<API_KEY>` produces the access token; immediately on success, `GET https://oauth.zettle.com/users/self` with `Authorization: Bearer <token>` retrieves the merchant profile. The dual-call is the synchronous failure surface: 401 on `/token` → `LoginFailed` for "key rejected"; 401 on `/users/self` → `LoginFailed` for "scope mismatch"; both are surfaced via the German `error.invalid_grant` string. `ListAccounts` becomes a pure cache read of the `publicName` + `organizationUuid` captured here.

### `client_id` resolution (Area B)
- **D-22:** `client_id` is **extracted from the assertion JWT payload** (middle segment, base64url-decoded, `JSON():dictionary()`-parsed, reading the `aud` claim — fall back to `client_id` claim if `aud` is absent or non-UUID-shaped). No hardcoded partner constant ships in `src/auth.lua`. No signature verification is attempted — we read the public payload only. If the assertion is malformed or carries neither `aud` nor `client_id`, `InitializeSession2` returns the German `error.invalid_grant` string synchronously without making any network call. This closes Phase-1 ADR-0003 question Q6 ("PayPal POS first-party `client_id`") as: *"the client_id is read from the assertion JWT's `aud`/`client_id` claim; no constant is shipped."*

### Multi-account identity (Area C)
- **D-23a:** `accountNumber` for the MoneyMoney account record is **`organizationUuid` from `/users/self`** (not user `uuid`, not JWT `sub`, not a hash of the API key). Same merchant org → same `accountNumber` even if the user rotates the API key or a different user under the same org issues a new key. Stable transaction history across key rotation is the value.
- **D-23b:** Account label rendered in MoneyMoney's sidebar is `"PayPal POS — " .. publicName` where `publicName` comes from `/users/self`. Fallback when `publicName` is empty/nil: `"PayPal POS — " .. organizationUuid:sub(1, 8)` so ACCT-04 (two accounts coexist with distinguishable labels) still holds even for keys without a profile name.
- **D-23c:** Token cache shape is **nested, keyed by `organizationUuid`**: `LocalStorage.zettle = { [orgUuid] = { access_token, expires_at, obtained_at, client_id } }`. Per-merchant isolation: two extension instances under different orgUuids never overwrite each other's tokens. **Caveat:** verifies Phase-1 probe Q5 (cross-restart persistence of nested tables in `LocalStorage`). If ADR-0003 Q5 ultimately reports "nested tables do not survive restart", fall back to flat keys `LocalStorage["zettle:" .. orgUuid] = JSON-encoded-string` and add a small decode/encode wrapper in `src/auth.lua`. This fallback path is implemented but unused unless Q5 forces it.
- **D-23d:** Pre-expiry guard is 60 s (locked by AUTH-04). `access_token` is re-minted when `os.time() >= expires_at - 60`. No refresh-token rotation (locked by AUTH-04).

### Error handoff to Phase 5 (Area D)
- **D-24:** Phase 2 ships a **minimal `M_errors.from_http_status(status, body)`** in `src/errors.lua` (no longer a Phase-1 `M_errors = {}` stub). Signature: `(status:integer, body:string?) -> string|nil`. Cases owned by Phase 2:
  - `nil` status (network/timeout/no response) → `M_i18n.t("error.network", "—")`
  - `200`–`299` → `nil` (signals "no error")
  - `400`, `401`, `403` → `LoginFailed` literal string
  - `429` → `M_i18n.t("error.rate_limit")`
  - `500`–`599` → `M_i18n.t("error.network", tostring(status))`
  - Anything else → `M_i18n.t("error.network", tostring(status))`
  Phase 5 extends this function additively (retry/backoff hints, 5xx body parsing, refund-specific cases) — the signature is stable and additive. Single source of truth for HTTP error mapping from day one.

### Cross-cutting decisions tied to the four areas
- **D-25:** `src/http.lua` exposes exactly two functions in Phase 2: `M_http.post_form(url, body_table, headers)` and `M_http.get_json(url, headers)`. Both return `(decoded_table|nil, status, raw_body)` and both pass `raw_body` through `M_log.redact()` before any debug log line. A single module-local `Connection()` instance is created on first call and reused; `EndSession` closes it via `M_http.shutdown()`.
- **D-26:** The egress allowlist remains exactly `{"oauth.zettle.com", "purchase.izettle.com", "finance.izettle.com"}` (Phase-1 D-12). Phase 2 only exercises `oauth.zettle.com`. CI's egress-grep continues to gate the shipped artifact.
- **D-27:** No sandbox/production toggle in the shipped artifact — production endpoints only. Sandbox testing happens via recorded fixtures under `spec/fixtures/auth/` and (for live exploration) the Phase-1 `tools/probe.lua` extension, which is **not** part of the amalgamation.
- **D-28:** Test fixtures for Phase 2 are **hand-rolled JSON files** under `spec/fixtures/auth/` (`token_ok.json`, `token_invalid_grant.json`, `users_self_ok.json`, `users_self_unauthorized.json`, `token_rate_limited.json`, `network_timeout.json`). Each fixture's header comment cites the iZettle/api-documentation page the shape was derived from. Recorded fixtures from a live sandbox call are welcome later but not gating.
- **D-29:** SEC-03 redaction test exercises a real auth failure path through `auth.lua` and `errors.lua` and asserts the resulting MoneyMoney return string contains neither a JWT-shape (`eyJ[a-zA-Z0-9_-]+`), nor the literal `Bearer`, nor any base64-url segment of the input API key.

### Claude's Discretion
- Exact Lua module layout inside `src/auth.lua` / `src/http.lua` (function ordering, helper visibility) is delegated to the planner — the constraints above pin the contract surface, not the internal structure.
- `M_log` call sites in `auth.lua` / `http.lua` (which lines log at INFO vs DEBUG) are delegated to the planner, subject to: never log the API key, never log a `Bearer` header value, never log raw JWT payloads (use first-8-chars + length idiom).
- Test names, file names under `spec/fixtures/auth/`, and the granularity of spec files (one file vs many) — planner's call.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project decisions and prior phase context
- `.planning/PROJECT.md` — paste-once UX, no telemetry, egress allowlist, API key never written to LocalStorage/logs/errors
- `.planning/REQUIREMENTS.md` §§ AUTH-01 … AUTH-06, SEC-03, ACCT-01, ACCT-02, ACCT-04 — verbatim requirement text
- `.planning/ROADMAP.md` — Phase 2 section (goal, success criteria, dependency on Phase-1 probes Q2/Q5/Q6/Q8)
- `.planning/phases/01-foundations-sandbox-probes/CONTEXT.md` — Phase-1 locked decisions D-01…D-20 (especially D-08 redaction, D-12 egress allowlist, D-14 module-stub posture, D-15 luacheckrc, D-19 build artifact name)
- `.planning/phases/01-foundations-sandbox-probes/RESEARCH.md` — RQ-1 (module inventory), RQ-2 (mock surface and Connection signature), RQ-4 (redaction patterns), RQ-7 (CI egress grep), and §"Module-by-Module File Inventory" for the existing surface of `src/auth.lua` / `src/http.lua` / `src/errors.lua`

### Architecture decision records (live + to-be-filled)
- `docs/adr/0001-amalgamator-design.md` — single-file build constraint; Phase 2 must produce code that survives `tools/build.lua` concatenation (no `require()` of siblings)
- `docs/adr/0003-sandbox-probe-results.md` — Q2 (redirect behavior of `Connection():request` on the token endpoint), Q5 (LocalStorage nested-table persistence across restart), Q6 (PayPal POS first-party client_id), Q8 (TLS default verification). Phase 2 must **read** the maintainer's Q2/Q5/Q8 answers before planning (Q6 is closed by D-22) and the planner should error out if any of Q2/Q5/Q8 remain blank at plan time.

### iZettle / Zettle / PayPal POS API references
- `iZettle/api-documentation/authorization.md` (GitHub) — `POST oauth.zettle.com/token`, `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`, `expires_in: 7200`, no refresh token for assertion grant
- `iZettle/api-documentation/oauth-api/user-guides/create-an-app/create-a-self-hosted-app/create-an-api-key.md` (GitHub) — assertion JWT shape (the input format for our JWT-payload decoder, D-22)
- `developer.zettle.com/docs/api/finance/overview` and `purchase.adoc` — used here only to confirm the **post-auth** host names (`purchase.izettle.com`, `finance.izettle.com`) so Phase 2's egress allowlist matches what later phases actually call

### MoneyMoney WebBanking API
- `moneymoney.app/api/webbanking/` — `InitializeSession2` signature and return conventions (`nil` = success, `LoginFailed` literal = auth fail, free-string = other error); `Connection()` request signature; `LocalStorage` semantics; `MM.printStatus`. Planner and executor agents must verify any new return shape against this page.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`M_log.redact(s)` (`src/log.lua` L11–L36)** — already strips JWT-shape tokens, `Bearer …`, `assertion=…`, `access_token=…`. Phase 2 calls this on every body before any DEBUG log line; no new redaction patterns needed.
- **`M_i18n.t(key, ...)` (`src/i18n.lua` L44–L52)** — `error.invalid_grant`, `error.network`, `error.rate_limit`, `credential.api_key.label` are already declared in `STRINGS.de`. Phase 2 adds at most a single new key (`error.profile_scope`, optional) and mirrors it in `STRINGS.en`.
- **`spec/helpers/mm_mocks.lua` `Mocks.push_response()` queue** — Phase 2 specs queue token-endpoint and `/users/self` responses in this order; the mock `Connection():request` already returns the tuple in the MoneyMoney shape.
- **`tools/probe.lua`** — already covers Q1/Q4/Q5/Q8 and emits to MoneyMoney's Protokoll panel. Phase 2 may extend it locally (uncommitted) for live Q2/Q6 verification, but the probe is **not** part of the amalgamation and stays out of `dist/paypal-pos.lua`.

### Established Patterns
- **`do … end` block wrap** — every `src/*.lua` is wrapped in `do … end` by `tools/build.lua`, attaching public functions to its pre-declared `M_*` table. Phase 2 code must follow this; no top-level globals other than the `M_*` table attachments.
- **No `require()` of siblings** (D-02) — cross-module access goes through the global `M_*` tables (`M_log.info(...)`, `M_errors.from_http_status(...)`, `M_i18n.t(...)`).
- **`-- luacheck: ignore 431` for callback args** — entry-point callbacks (`InitializeSession2`, `ListAccounts`, `RefreshAccount`) shadow `LocalStorage` and other built-ins; the pattern is already used in `src/entry.lua` and `spec/helpers/mm_mocks.lua`. Phase 2 maintains it.

### Integration Points
- **`src/entry.lua` `InitializeSession2`** — current Phase-1 walking-skeleton implementation extracts the API key from every observed credential shape (string / positional array / challenge-style table / `{username,password}` fallback). Phase 2 inserts the new auth call **after** that extraction and **before** the existing `return nil` — without touching the extraction block (Phase-1 D-10 surface contract).
- **`src/entry.lua` `ListAccounts`** — currently returns the Phase-1 fixture `{accountNumber="paypal-pos-fixture-001", name=M_i18n.t("account.name","Test-Händler"), …}`. Phase 2 swaps the fixture for the cached merchant profile (D-23a/b). `RefreshAccount` continues returning the Phase-1 fixture transaction until Phase 3/4 wire the purchase mapping.
- **`src/entry.lua` `EndSession`** — currently a no-op. Phase 2 hooks `M_http.shutdown()` here (closes the cached `Connection`) and clears module-level cached state (the in-memory mirror of `LocalStorage.zettle[orgUuid]`, never the API key — the key was never held in module state to begin with).
- **`src/webbanking_header.lua`** — `M_auth = {}`, `M_http = {}`, `M_errors = {}` are pre-declared. Phase 2 attaches functions to them in-place; no new module-table declarations.

</code_context>

<specifics>
## Specific Ideas

- PROJECT.md's product promise is *"paste your API key once"* — Decision D-22 (extract `client_id` from the JWT payload) is the load-bearing decision that lets us honor that promise without a second credential field.
- `/users/self` is the explicit choice for the merchant profile fetch, not a guess. The path comes from the iZettle `oauth-api` docs and is reachable on the `oauth.zettle.com` host that's already in the egress allowlist. No new allowlist entry.
- The token cache shape `{access_token, expires_at, obtained_at, client_id}` (from the Phase 2 goal in ROADMAP.md) is preserved as-is; D-23c adds the `[orgUuid]` outer keying without changing the inner shape.
- `obtained_at` is `os.time()` at the moment of token fetch; `expires_at` is `obtained_at + tonumber(response.expires_in)` (Zettle returns `7200`). Decision: trust the server-returned `expires_in`, not a hardcoded `7200` constant, so any future Zettle TTL change is automatically respected.

</specifics>

<deferred>
## Deferred Ideas

- **Retry/backoff and 429 throttling honoured at the call layer** — Phase 5 (errors.lua expansion). Phase 2's `M_errors.from_http_status` already maps 429 to the German rate-limit string, but no automatic retry is wired in. Caller (auth.lua) returns the error to MoneyMoney; the next manual refresh re-tries.
- **Recorded sandbox fixtures** — capturing real `oauth.zettle.com` responses against the maintainer's sandbox tenant and committing them under `spec/fixtures/auth/recorded/` is deferred. Phase 2 ships with hand-rolled fixtures only (D-28).
- **`/users/self` cache invalidation on profile change** — if a merchant renames their org, the Phase-2 cache holds the old `publicName` until token expiry forces a `/users/self` refetch. Refining this (e.g., re-fetching profile on every restart) is deferred to Phase 5/6 if real users hit it.
- **Sandbox/dev-mode toggle in the shipped artifact** — explicitly out (D-27). Reconsider if Zettle ever publishes a stable sandbox URL the partner program endorses.
- **Probe.lua Q2/Q6 extensions** — Q6 is now closed by D-22 without a probe; Q2 (redirect behavior on the token endpoint) may benefit from a one-shot probe-lua extension before plan-phase commits. The planner agent should call out whether Q2's blank state in ADR-0003 blocks planning.

</deferred>

---

*Phase: 02-authenticated-network-layer*
*Context gathered: 2026-06-17*
