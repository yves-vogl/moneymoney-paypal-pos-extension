---
phase: 05-resilience-error-handling
plan: "04"
subsystem: auth+resilience
tags: [wave-3, auth, token-revoked, login-failed, regression, tdd, err-04, err-01, adr-0005, d-43-exception]
dependency_graph:
  requires: [05-02]
  provides:
    - "ERR-04 token-revoked surface — post-mint 401 from any resource endpoint returns the German error.token_revoked string ('Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen.')"
    - "ERR-01 InitializeSession2 round-trip regression gate — token-mint invalid_grant returns the literal LoginFailed constant verbatim"
    - "fetch_account_state liquid-leg abort-on-401 — 401 on liquid GET skips the preliminary GET (D-66 fail-whole + saves one API call)"
  affects: [05-05]
tech_stack:
  added: []
  patterns:
    - "401-direct-check at iterator boundary (M_pagination.iterate + M_pagination.offset_iterate) — single check covers both M_purchases.fetch_all and M_finance.fetch_all paginated flows; preserves fetch's (parsed, status, raw) return contract"
    - "401-direct-check inline at non-paginated dual-GET sites (M_finance.fetch_account_state liquid + preliminary)"
    - "Justified exception to D-43 (all errors via M_errors.from_http_status): the 401 -> token_revoked mapping is semantic (we know the mint succeeded because cached_token returned a bearer), not status-code-class generic. Token-mint (M_auth.exchange_assertion) never paginates, so the iterator-level check cannot misclassify ERR-01 as ERR-04"
    - "Phase-4 contract update: the finance_account_state_spec test that asserted 401 -> LoginFailed is replaced by the ERR-04 contract (401 -> error.token_revoked); a new abort-on-liquid-401 test gates the don't-issue-preliminary path"
key_files:
  created:
    - .planning/phases/05-resilience-error-handling/05-04-SUMMARY.md
  modified:
    - src/pagination.lua
    - src/finance.lua
    - src/purchases.lua
    - spec/auth_spec.lua
    - spec/refresh_idempotency_spec.lua
    - spec/finance_account_state_spec.lua
  deleted: []
decisions:
  - "D-64 collapsed (CONTEXT correction per RESEARCH §Pattern-2): silent re-mint is INFEASIBLE under assertion-grant + SEC-03 — the api_key cannot be persisted per AUTH-05 (the only thing M_auth.exchange_assertion could use to re-mint). v1.0.0 surfaces post-mint 401 IMMEDIATELY as the German error.token_revoked string; the user re-enters the API key via MoneyMoney's normal account dialog. Phase 7 (POST-v1 OAuth Authorization-Code flow per ROADMAP) reintroduces silent refresh via refresh_token grant."
  - "ERR-04 vs ERR-01 distinction LOCKED: ERR-01 (invalid_grant at MINT time -> LoginFailed constant -> MoneyMoney's Konto-neu-hinzufügen prompt) vs ERR-04 (401 at RESOURCE call AFTER successful mint -> error.token_revoked German string -> 'Anmeldung verloren'). Both end in the user re-entering the key, but ERR-01 triggers MoneyMoney's special credential re-prompt UI while ERR-04 surfaces a normal error message. The distinction matters because a server-side token revocation mid-refresh should NOT be misclassified as a bad-API-key error (that would imply the stored credentials were wrong when they were correct at mint time)."
  - "Plan-deviation per Rule 1 (auto-fix bug): the plan instructed adding 'return nil, M_i18n.t(\"error.token_revoked\")' inside M_purchases.fetch + M_finance.fetch. That would feed (nil, \"Anmeldung...\") into M_pagination.iterate, where M_errors.from_http_status(\"Anmeldung...\", nil) crashes in Lua 5.4 (string < number comparison in the 200..299 branch). Moved the check to the iterator boundary (M_pagination.iterate + M_pagination.offset_iterate) — same net effect, preserves fetch's (parsed, status, raw) contract, and routes the German string cleanly to RefreshAccount. Cross-reference comments in src/purchases.lua and src/finance.lua direct future readers to the iterator-layer check."
  - "ABORT-on-first-401 in fetch_account_state: a 401 from the liquid leg returns immediately without issuing the preliminary GET — saves one needless API call and matches the D-66 fail-whole invariant. A 401 on the preliminary leg (after a 2xx on liquid) typically means the token was revoked between the two sequential GETs and is also surfaced as error.token_revoked."
  - "ERR-01 regression-verified — InitializeSession2 round-trip with the token_invalid_grant fixture returns the LoginFailed constant verbatim. The existing Phase-2 isolated test (M_errors.from_http_status(400, raw) -> LoginFailed) remains; the new test exercises the full InitializeSession2 entry boundary so any future refactor surfaces here. No Phase-2 regression detected."
  - "Test fixture name reconciled: the plan referenced 'auth_invalid_grant.json' but the file shipped in spec/fixtures/auth/ is named 'token_invalid_grant.json'. Used the actual file name (no rename needed)."
metrics:
  duration: "~25 minutes"
  completed: "2026-06-22"
  tasks_completed: 3
  files_created: 1
  files_modified: 6
  files_deleted: 0
  commits: 4
  busted_baseline: "352 successes / 0 failures / 3 pending"
  busted_final: "356 successes / 0 failures / 3 pending"
  busted_delta: "+4 successes (ERR-01 round-trip + ERR-04 token-revoked auth_spec + ERR-04 retry refresh_idempotency + liquid-401-abort finance_account_state)"
  luacheck: "0 warnings / 0 errors across src/ + spec/ (pre-existing tools/probe.lua shadowing warnings untouched)"
  reproducible_sha: "b151f16569f7f3fa855d59403c8bafc26a07557a515f9d8b9cef88635fe85e63"
  reproducible_verified: "two consecutive `lua tools/build.lua --verify` runs returned identical SHA"
  gpg_signed: "100% — every Plan 05-04 commit verified G via `git log -1 --format='%G?'`"
---

# Phase 05 Plan 04: ERR-04 Token-Revoked + ERR-01 Regression Summary

Closes the ERR-04 post-mint-401 contract by collapsing CONTEXT D-64 (silent re-mint) per RESEARCH §Pattern-2: assertion-grant + SEC-03 forbid persisting the api_key (the only thing M_auth.exchange_assertion can use to re-mint), so v1.0.0 surfaces a revoked-mid-session bearer immediately as the German `error.token_revoked` string. The user re-enters the API key via MoneyMoney's normal account dialog. Phase 7 (POST-v1 OAuth Authorization-Code flow) will reintroduce silent refresh via refresh_token grant.

Also gates the ERR-01 round-trip regression: token-mint `invalid_grant` returns the literal `LoginFailed` constant from `InitializeSession2`, so MoneyMoney renders its special credential re-prompt UI (distinct from ERR-04's normal error message).

## What Was Built

### 1. Iterator-layer 401-direct-check (justified exception to D-43)

`src/pagination.lua` — both `M_pagination.iterate` (cursor-pagination, drives `M_purchases.fetch_all`) and `M_pagination.offset_iterate` (offset-pagination, drives `M_finance.fetch_all`) gained a single-line 401-direct-check BEFORE the existing `M_errors.from_http_status` dispatch:

```lua
if status == 401 then return nil, M_i18n.t("error.token_revoked") end
```

A 401 from any paginated resource endpoint now routes to the German `error.token_revoked` string instead of `LoginFailed` (which D-24 case 3 would otherwise produce). Token-mint (`M_auth.exchange_assertion`) does NOT paginate, so the iterator-level check cannot misclassify ERR-01 as ERR-04.

### 2. Non-paginated 401-direct-check at fetch_account_state's dual-GET

`src/finance.lua` — `M_finance.fetch_account_state` issues TWO sequential GETs (`/v2/accounts/liquid/balance` + `/v2/accounts/preliminary/balance`). Each leg gained an inline 401-direct-check:

- 401 on the liquid leg → return `(nil, error.token_revoked)` IMMEDIATELY; the preliminary GET is NOT issued (D-66 fail-whole + saves one API call).
- 401 on the preliminary leg (after a 2xx on liquid) → return `(nil, error.token_revoked)`. Token was revoked between the two sequential GETs.

### 3. Cross-reference comments at the call sites

`src/purchases.lua` and `src/finance.lua.fetch` gained comment blocks pointing future readers to the iterator-layer check (so the contract is discoverable from either layer).

### 4. Phase-4 contract update at finance_account_state_spec

The Phase-4 test asserting `401 → LoginFailed` was replaced by the ERR-04 contract (`401 → error.token_revoked`). A NEW abort-on-liquid-401 test gates the don't-issue-preliminary path. Both tests use `{"error":"invalid_client"}` as the mock body (which `M_http._infer_status` maps to 401 per src/http.lua:128-129).

### 5. ERR-01 round-trip regression gate

`spec/auth_spec.lua` gained a new `describe("ERR-01 (Phase-5 regression) LoginFailed on invalid_grant")` block. One test queues the `token_invalid_grant` fixture and asserts `InitializeSession2(..., api_key, ...)` returns the literal `LoginFailed` constant verbatim (not a German string — so MoneyMoney shows its credential re-prompt UI). Passes against the unchanged Phase-2 baseline → no Phase-2 regression detected.

### 6. ERR-04 retry idempotency gate

`spec/refresh_idempotency_spec.lua` gained one new test: refresh N fails with `error.token_revoked` (no transactions emitted); refresh N+1 with a fresh bearer (simulating the user re-entered the API key via InitializeSession2) succeeds with the standard sale schema (`^zettle:sale:`). Asserts (a) `since` parameter byte-identical across both refresh calls (MoneyMoney's idempotent contract holds across the ERR-04 failure), (b) no transactionCodes from refresh N pollute refresh N+1 (refresh N emits zero, so the precondition is trivially satisfied — the test enumerates the cleanup case for future regressions), and (c) the German error string equals the Plan-05-02 i18n value verbatim (`M_i18n.t("error.token_revoked")`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's literal 401-check placement would crash in Lua 5.4**

- **Found during:** Task 2 (GREEN) implementation planning, before any code change
- **Issue:** The plan instructed adding `if status == 401 then return nil, M_i18n.t("error.token_revoked") end` inside `M_purchases.fetch` (returning a 2-tuple). The iterator (`M_pagination.iterate`) destructures the return value as `local page, status, raw = fetch_page_fn(params)`, so `status` would become the German string `"Anmeldung verloren — ..."`. The next line `local err = M_errors.from_http_status(status, raw)` then evaluates `if status >= 200 and status <= 299` — Lua 5.4 raises `attempt to compare string with number`, aborting the chunk.
- **Fix:** Moved the 401-direct-check to the iterator boundary (`M_pagination.iterate` + `M_pagination.offset_iterate`). Same net effect (intercept BEFORE D-43 dispatch with the token_revoked message), preserves `fetch`'s `(parsed, status, raw)` return contract, and routes the German string cleanly to `RefreshAccount`. Cross-reference comments added to `src/purchases.lua` and `src/finance.lua.fetch` documentation blocks.
- **Files modified:** `src/pagination.lua` (2 sites), `src/finance.lua` (2 sites in fetch_account_state + comment block in fetch), `src/purchases.lua` (comment block in fetch)
- **Commit:** `74e5216`

**2. [Rule 1 - Test contract update] Phase-4 finance_account_state_spec test asserted obsolete contract**

- **Found during:** Task 2 (GREEN) full-suite run after the iterator-layer fix landed
- **Issue:** `spec/finance_account_state_spec.lua` carried a Phase-4 test asserting `fetch_account_state returns (nil, err = LoginFailed) when preliminary 401s`. This was correct under the Phase-4 D-43 contract but is obsolete under Plan 05-04's ERR-04 collapse (the whole point of this plan is to replace `LoginFailed` with `error.token_revoked` for post-mint 401s).
- **Fix:** Replaced the assertion to expect `M_i18n.t("error.token_revoked")` per the new contract. Added a second test asserting the abort-on-liquid-401 behavior (preliminary GET NOT issued after liquid 401 — only 1 captured request).
- **Files modified:** `spec/finance_account_state_spec.lua`
- **Commit:** `74e5216`

**3. [Rule 1 - Test correctness] refresh_idempotency_spec assertion misread D-33 clamp**

- **Found during:** Task 2 (GREEN) full-suite run after the iterator-layer fix landed
- **Issue:** The ERR-04 retry test asserted `startDate=1970-01-01T00:00:00Z` for `since=0`, but `entry.lua` clamps `effective_since = math.max(since, os.time() - 90 days)` per D-33. Wire-level startDate is the 90-day-floor (~`2026-03-24T...`), not 1970.
- **Fix:** Replaced the literal startDate assertion with a derived 90-day-ago ISO-8601 prefix computed at test run time. The MoneyMoney → extension boundary contract (which is what idempotency cares about) is byte-identical `since` between both calls; the wire-level startDate is the same clamped value across both refreshes (point (a) intent preserved).
- **Files modified:** `spec/refresh_idempotency_spec.lua`
- **Commit:** `74e5216`

### Fixture-name reconciliation (not a deviation, just a note)

The plan referenced `spec/fixtures/auth/auth_invalid_grant.json` but the file shipped in Phase 2 is named `token_invalid_grant.json`. Used the actual file name — no rename, no fixture change needed.

## ERR-01 Regression Result

**PASS.** `InitializeSession2(..., api_key, ...)` returns the literal `LoginFailed` constant verbatim when queued with the Phase-2 `token_invalid_grant` fixture (which carries `{"error":"invalid_grant"}` → `_infer_status` returns 400 → `M_errors.from_http_status` returns `LoginFailed` → `InitializeSession2` returns it). No Phase-2 regression detected. The new round-trip test will catch any future refactor to either `_infer_status`, `M_errors.from_http_status`, or `InitializeSession2`'s error routing.

## Metrics

| Metric                  | Value                                                                  |
| ----------------------- | ---------------------------------------------------------------------- |
| busted baseline         | 352 successes / 0 failures / 3 pending                                 |
| busted final            | 356 successes / 0 failures / 3 pending                                 |
| busted delta            | +4 successes (ERR-01 round-trip + ERR-04 auth + ERR-04 retry + liquid-401-abort) |
| luacheck (src/ + spec/) | 0 warnings / 0 errors (38 files)                                       |
| reproducible build SHA  | `b151f16569f7f3fa855d59403c8bafc26a07557a515f9d8b9cef88635fe85e63`     |
| reproducible verified   | two consecutive `lua tools/build.lua --verify` runs returned identical SHA |
| GPG-signed commits      | 100% — `test(05-04):` + `feat(05-04):` both verified `G` via `git log --format='%G?'` |
| commits added           | 4 (RED + GREEN + docs + chore lint) — all GPG-signed                   |
| coverage delta          | src/pagination.lua + src/finance.lua + src/purchases.lua: new 401 branches gated by tests; src/auth.lua unchanged (no Phase-5 source change; regression-only) |

## Hand-off to Plan 05-05

- **ERR-04 path LOCKED** at the i18n value `"Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen."` (`M_i18n.t("error.token_revoked")`). Plan 05-05's fail-whole-refresh gating spec can compose the ERR-04 path with the 5xx and network fail-whole paths — the German string format will not drift.
- **Iterator-layer 401-check** is the single chokepoint for ERR-04 from any paginated resource endpoint. New paginated callers added in future phases (Phase 6 catalog / Phase 7 OAuth) get the check automatically.
- **fetch_account_state inline checks** are the chokepoint for non-paginated dual-GET. Future non-paginated resource calls must replicate this inline pattern (the iterator-layer check does NOT cover them).
- **ERR-01 round-trip regression gate** in place — any future refactor to `_infer_status`, `M_errors.from_http_status`, or `InitializeSession2`'s error routing that breaks the `invalid_grant → LoginFailed` round-trip will surface here loudly.
- **Reproducible build baseline for Plan 05-05:** `b151f16569f7f3fa855d59403c8bafc26a07557a515f9d8b9cef88635fe85e63`.
- **No new Yves-blockers surfaced.** The D-64 collapse was already authorized via Yves' 48h autonomous-work window + the RESEARCH §Pattern-2 mandate.

## Self-Check: PASSED

- [x] `src/pagination.lua` — 401-direct-check present in both `iterate` and `offset_iterate` (`grep -c 'error.token_revoked' src/pagination.lua` = 2)
- [x] `src/finance.lua` — 401-direct-check present in both `fetch_account_state` legs (`grep -c 'error.token_revoked' src/finance.lua` = 2)
- [x] `src/purchases.lua` — cross-reference comment to iterator-layer check
- [x] `spec/auth_spec.lua` — ERR-01 round-trip + ERR-04 token-revoked tests present
- [x] `spec/refresh_idempotency_spec.lua` — ERR-04 + retry test present
- [x] `spec/finance_account_state_spec.lua` — Phase-4 contract updated + new liquid-401-abort test
- [x] Both Plan 05-04 commits found in `git log`: `3159411` (RED) + `74e5216` (GREEN), both GPG-signed (`G`)
- [x] busted: 356/0/3 (baseline 352/0/3 + 4 new)
- [x] luacheck src/ + spec/: 0 warnings / 0 errors
- [x] Reproducible build: two `lua tools/build.lua --verify` runs returned identical SHA `b151f16569f7f3fa855d59403c8bafc26a07557a515f9d8b9cef88635fe85e63`
