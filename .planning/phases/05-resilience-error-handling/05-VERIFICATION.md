---
phase: 05-resilience-error-handling
verified: 2026-06-22T00:00:00Z
status: passed
score: 6/6 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
  gaps_closed: []
  gaps_remaining: []
  regressions: []
---

# Phase 5: Resilience & Error Handling — Verification Report

**Phase Goal:** Every adversarial network condition produces a clear German message and never silently advances the `since` watermark past undelivered data.
**Verified:** 2026-06-22
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | Token-mint `invalid_grant` returns `LoginFailed` constant (string-return, not `error()`), prompting re-entry (`ERR-01`) | ✓ VERIFIED | `src/errors.lua:36-38` (D-24 case 3: status 400 → `LoginFailed`); `src/http.lua:124-127` (`_infer_status` maps `{"error":"invalid_grant"}` → 400); regression gates: `spec/auth_spec.lua:112-119` (mapping isolation) + `spec/auth_spec.lua:350-363` (full `InitializeSession2` round-trip returning `LoginFailed` verbatim) |
| 2 | Transient 5xx triggers retry-with-backoff up to 3 attempts before failing with localized German string (`ERR-02`) | ✓ VERIFIED | `src/http.lua:23-25,161-222` (`_MAX_ATTEMPTS=3`, `_BACKOFF_SECONDS={1,2,4}`, iterative retry loop); `src/errors.lua:52-54` (599 sentinel → `error.server_busy`); `src/i18n.lua:44-45` (German string `"PayPal-POS-Server zurzeit nicht erreichbar — bitte später erneut versuchen."`); test gates: `spec/http_retry_spec.lua:72-103` (3-attempt exhaust + 2nd-attempt success + retry log assertions) + `spec/errors_spec.lua:109-118` (599 → `error.server_busy`) |
| 3 | 429 honors `Retry-After` header up to cap; without it, returns German rate-limit string (`ERR-03`) | ✓ VERIFIED | `src/http.lua:26-27,69-84,192-201` (`_RETRY_AFTER_CAP=60`, `_RATE_LIMIT_DEFAULT=30`, `_parse_retry_after` w/ negative + NaN + cap guards + dual-case header lookup); test gates: `spec/http_retry_spec.lua:105-189` (integer honor, default fallback, cap, negative reject, non-numeric reject, retry-exhaust, lower-case header per Pitfall §6) |
| 4 | Post-mint 401 (token revoked mid-refresh) — refresh fails with German `error.token_revoked` (NOT `LoginFailed`) per ADR-0005 D-64 collapse (`ERR-04`) | ✓ VERIFIED | `src/pagination.lua:54-65` (iterator-layer 401 → `error.token_revoked`); `src/pagination.lua:147-152` (offset iterator mirror); `src/finance.lua:189-197` (liquid balance inline check, aborts dual-fetch); `src/finance.lua:221-224` (preliminary balance inline check); `src/i18n.lua:46-47` (`"Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen."`); test gates: `spec/auth_spec.lua:372-405` (full RefreshAccount returns German string verbatim on 401) + `spec/refresh_fail_whole_spec.lua:178-230` (ERR-06 case 2 composition). D-64 collapse documented in ADR-0005 Invariant 4 as a carve-out, not a gap. |
| 5 | Network failure (DNS/TLS/connect timeout) produces German error returned from `RefreshAccount`, never Lua error or partial result; same path exercised at `InitializeSession2` profile-ping (`ERR-05`) | ✓ VERIFIED | `src/http.lua:161-179` (`_request_with_retry` empty-body path returns `(nil, nil, raw)` after exhaust); `src/errors.lua:25-28` (nil status → `error.network`); NO `pcall` around `conn:request` per ADR-0003 Q8 + ADR-0005 Carve-out 1 (intentional); `src/entry.lua:62-64,77-79` (`InitializeSession2` routes `M_errors.from_http_status` same path); test gates: `spec/refresh_fail_whole_spec.lua:240-308` (case 3 network-failure 3-attempt exhaust + `since` byte-identical preservation across refreshes). SSL handshake bypass documented in ADR-0005 Carve-out 1 (intentional). |
| 6 | Any failure inside `RefreshAccount` aborts the entire refresh; fixture confirms Step-3 failure after Step-2 success returns error string and next refresh re-runs from same `since` (`ERR-06`) | ✓ VERIFIED | `src/entry.lua:174-244` (fail-whole early returns at Steps 4, 7, 8 — Lua lexical scoping discards in-flight `purchases_by_uuid`, `payments_by_uuid`, `fees_by_date`, `transactions` locals); 16-step pipeline (4 in `InitializeSession2` + 16 in `RefreshAccount` = 20 step markers — `grep -cE "^  -- Step [0-9]+" src/entry.lua` returns 20); test gates: `spec/refresh_fail_whole_spec.lua:101-358` (4 cases: 5xx-on-finance, 401-on-finance, network-on-finance, 5xx-on-purchases — each asserts error string returned, no partial transactions leaked, captured URLs prove fail-whole abort point, refresh #2 with SAME `since` succeeds when API recovers) |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/http.lua` | Retry-with-backoff, 429 Retry-After honor, 599 sentinel, empty-body ERR-05 path | ✓ VERIFIED | 264 lines; 5 retry constants (L23-28); `_request_with_retry` shared loop body (L161-222); `_parse_retry_after` (L75-84); `_sleep_with_log` with pcall guard (L92-108); WIRED — used by `M_purchases`, `M_finance`, `M_auth` |
| `src/errors.lua` | 599 sentinel branch added; ERR-04 deliberately NOT here | ✓ VERIFIED | 62 lines; 599 → `error.server_busy` (L52-54); 500-598 → generic `error.network` (L55-57); preserves Phase-2 LoginFailed path for 400/401/403 |
| `src/i18n.lua` | 2 new German keys (`error.server_busy`, `error.token_revoked`) + English parity | ✓ VERIFIED | DE+EN both present (L44-47 DE, L87-90 EN); UTF-8 byte-escape (`\xe2\x80\x94` em-dash, `\xc3\xa4` umlaut) per Phase-4 convention |
| `src/purchases.lua` | Documented exception for ERR-04 routing through `M_pagination.iterate` | ✓ VERIFIED | L58-63 comment block; `fetch` returns raw 3-tuple; ERR-04 intercept lives in iterator |
| `src/finance.lua` | ERR-04 inline 401-direct-check at both `fetch_account_state` GETs | ✓ VERIFIED | L189-197 (liquid 401 abort-dual-fetch); L221-224 (preliminary 401 mirror); D-66 fail-whole preserved (no preliminary issued after liquid 401) |
| `src/pagination.lua` | ERR-04 401-direct-check in `iterate` + `offset_iterate` | ✓ VERIFIED | L54-65 (cursor iterator); L147-152 (offset iterator); 401 check BEFORE `M_errors.from_http_status` per Plan 05-04 |
| `src/entry.lua` | Phase-4 16-step pipeline preserved (no source changes for ERR-06) | ✓ VERIFIED | 442 lines; 20 step markers (4 InitializeSession2 + 16 RefreshAccount); fail-whole structurally enforced by lexical locals |
| `docs/adr/0005-resilience-invariants.md` | ACCEPTED ADR with pinned implementation values | ✓ VERIFIED | 439 lines; Status ACCEPTED 2026-06-22; 6 invariants documented; 3 carve-outs (SSL bypass, HTTP-date Retry-After, SSL re-anchor); Implementation Pin section freezes Plan 05-02..05-04 landed values |
| `tools/probe.lua` | Q9 MM.sleep probe block added | ✓ VERIFIED | Q9 block at L109-127 (probe.lua); classifies as PASS / PRESENT-BUT-NOOP / ABSENT / FAIL; optional per ADR-0005 |
| `spec/http_retry_spec.lua` | 10 GREEN retry tests | ✓ VERIFIED | 191 lines; 10 `it()` blocks covering 200-baseline, 5xx 3-attempts, 5xx-2nd-success, 429 Retry-After honor/default/cap/negative/non-numeric/exhaust/lower-case |
| `spec/refresh_fail_whole_spec.lua` | 4 ERR-06 cases + Gate D | ✓ VERIFIED | 360 lines; 5 `it()` blocks: seed_token sanity + 4 ERR-06 cases (5xx-finance, 401-finance, network-finance, 5xx-purchases) |
| `spec/refresh_log_redaction_spec.lua` | Extended with Gate D (D-68 retry log Bearer redaction) | ✓ VERIFIED | Gate D describe block at L427-514 — exactly 2 retry log lines on 503-storm, format-string match, URL field populated, NO Bearer/eyJ in any retry line |
| `spec/phase3_surface_preservation_spec.lua` | Extended with Phase-4 surface preservation + Plan 05-04 non-interference | ✓ VERIFIED | Phase-4 surface describe block at L183-305: M_finance signature, M_mapping byte-identity, step-count = 20, happy-path non-interference (balance 123.45, pendingBalance 6.78, D-38 closed-set) |
| `spec/auth_spec.lua` | ERR-01 round-trip regression + ERR-04 token-revoked test | ✓ VERIFIED | ERR-01 at L350-363 (InitializeSession2 returns LoginFailed verbatim); ERR-04 at L372-405 (German string match + `M_i18n.t("error.token_revoked")` verbatim equality) |
| `spec/errors_spec.lua` | 599 sentinel mapping + SEC-03 body-redaction proof | ✓ VERIFIED | L109-118 (599 → server_busy); L114-120 (SEC-03 SECRET_MARKER_599 not echoed into result) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `_request_with_retry` (http.lua) | `M_log.info` (log.lua) | `_sleep_with_log` | ✓ WIRED | http.lua:93-96 — format `HTTP retry: attempt=N/3 status=NNN url=URL after_ms=NNNN`; emitted via `M_log.info` |
| `_request_with_retry` (http.lua) | `MM.sleep` (sandbox) | `_sleep_with_log` w/ pcall guard | ✓ WIRED | http.lua:100-107 — pcall-wrapped; type-checked; degraded fallback on error per Pitfall §10 |
| `M_pagination.iterate` (pagination.lua) | `M_i18n.t("error.token_revoked")` | direct return | ✓ WIRED | pagination.lua:65 — 401 BEFORE `M_errors.from_http_status` |
| `M_pagination.offset_iterate` (pagination.lua) | `M_i18n.t("error.token_revoked")` | direct return | ✓ WIRED | pagination.lua:152 — mirror of cursor iterator |
| `M_finance.fetch_account_state` (finance.lua) | `M_i18n.t("error.token_revoked")` | inline 401 check (2 sites) | ✓ WIRED | finance.lua:197 (liquid) + finance.lua:224 (preliminary); preliminary skipped on liquid 401 per D-66 |
| `M_errors.from_http_status` | `M_i18n.t("error.server_busy")` | 599 branch | ✓ WIRED | errors.lua:52-54 |
| `M_errors.from_http_status` | `LoginFailed` constant | 400/401/403 branch | ✓ WIRED | errors.lua:36-38 — Phase-2 path preserved for token-mint failures |
| `RefreshAccount` (entry.lua) | Early-return fail-whole | `if err then return err end` × 4 | ✓ WIRED | entry.lua:175 (purchases), L240 (state), L244 (finance) — lexical locals discarded automatically |
| `InitializeSession2` (entry.lua) | `M_errors.from_http_status` profile-ping | shared http path | ✓ WIRED | entry.lua:62-64,77-79 — same nil-status → error.network path as RefreshAccount |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `_request_with_retry` retry loop | `parsed`, `status`, `raw` | `conn:request` 5-tuple → JSON parse | Yes — test queues exercise empty-body, 200, 429, 5xx body branches | ✓ FLOWING |
| `_parse_retry_after` | `raw` Retry-After header | `resp_headers` table from `conn:request` | Yes — test queues exercise integer, missing, lower-case, capped, negative, non-numeric | ✓ FLOWING |
| `error.token_revoked` i18n key | German string | STRINGS.de table | Yes — `spec/auth_spec.lua:401` asserts `M_i18n.t("error.token_revoked")` equality verbatim | ✓ FLOWING |
| `error.server_busy` i18n key | German string | STRINGS.de table | Yes — `spec/errors_spec.lua:110-111` asserts mapping | ✓ FLOWING |
| RefreshAccount fail-whole | early-return error string | propagated from `fetch_all`/`fetch_account_state`/etc | Yes — `spec/refresh_fail_whole_spec.lua` 4 cases prove `result` is string + no transactions leak | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Reproducible build produces deterministic artifact | `lua tools/build.lua && lua tools/build.lua --verify` | `OK: reproducible (sha256: b151f16569f7f3fa855d59403c8bafc26a07557a515f9d8b9cef88635fe85e63)` | ✓ PASS |
| Full busted suite passes | `busted spec/` | `365 successes / 0 failures / 0 errors / 0 pending : 4.96 seconds` | ✓ PASS |
| Phase-5 entry step count preserved | `grep -cE "^  -- Step [0-9]+" src/entry.lua` | `20` (4 InitializeSession2 + 16 RefreshAccount) | ✓ PASS |
| Artifact line count sanity | `wc -l dist/paypal-pos.lua` | `2285` lines (single-file artifact) | ✓ PASS |
| luacheck lint on src/spec | `luacheck src/ spec/ tools/` | ? SKIPPED — local environment has Lua 5.5 / luacheck 1.2.0 incompatibility (`/opt/homebrew/share/lua/5.5/luacheck/standards.lua:134: attempt to assign to const variable 'field_name'`). CI runs Lua 5.4 (`.github/workflows/ci.yml:30 luaVersion: "5.4"`) where luacheck works. Not a Phase 5 regression. | ? SKIP |

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| Q9 MM.sleep sandbox probe (tools/probe.lua block) | `MoneyMoney → Extensions → probe.lua` (manual, requires MoneyMoney runtime) | Not executable headlessly (probe runs inside MoneyMoney sandbox where `MM.*` globals exist) | ? OPTIONAL — per ADR-0005 line 335-348 marked OPTIONAL; Q9 row added to ADR-0003 by Yves after running probe. Plan 05-01 explicitly does NOT pre-add the row. This is a Yves-time confirmation, not a verifier gate. |

### Requirements Coverage (ERR-01..ERR-06)

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ERR-01 | 05-02 spec ext | Token-mint `invalid_grant` → `LoginFailed` | ✓ SATISFIED | `src/errors.lua:36-38` (path) + `spec/auth_spec.lua:112-119, 350-363` (mapping + round-trip gates); Phase-2 path re-asserted in ADR-0005 Invariant 1 |
| ERR-02 | 05-03 | 5xx retry-with-backoff up to 3 attempts then localized German | ✓ SATISFIED | `src/http.lua:23-25, 161-222`; `src/errors.lua:52-54`; `src/i18n.lua:44-45`; `spec/http_retry_spec.lua:72-103` (3 tests) |
| ERR-03 | 05-03 | 429 honors Retry-After with cap, German on fallback | ✓ SATISFIED | `src/http.lua:26-27, 69-84, 192-201`; `spec/http_retry_spec.lua:105-189` (7 tests covering integer/default/cap/negative/non-numeric/exhaust/lowercase) |
| ERR-04 | 05-04 | Post-mint 401 → `error.token_revoked` (collapsed from "single silent re-mint" per D-64 collapse / ADR-0005 Invariant 4) | ✓ SATISFIED | 4 call sites per ADR-0005 Implementation Pin: `src/pagination.lua:65,152`, `src/finance.lua:197,224`; `spec/auth_spec.lua:372-405`. Collapse documented; LoginFailed reserved for ERR-01 |
| ERR-05 | 05-02 spec | Network failure → German `error.network`, never partial | ✓ SATISFIED | `src/http.lua:161-179` (empty-body exhaust); `src/errors.lua:25-28` (nil-status path); `spec/refresh_fail_whole_spec.lua:240-308` (case 3). SSL handshake bypass documented as Carve-out 1 in ADR-0005 |
| ERR-06 | 05-05 spec | Fail-whole-refresh: any failure aborts entire refresh; next refresh re-runs from same `since` | ✓ SATISFIED | `src/entry.lua:174-244` (early returns + lexical scoping); `spec/refresh_fail_whole_spec.lua:101-358` (4 cases, each verifying `since` byte-identical re-use across refresh 1 → refresh 2) |

**Cross-reference:** `.planning/REQUIREMENTS.md` still shows ERR-04..ERR-06 as `[ ]` (unchecked) on L72-74. This is a documentation lag — implementation evidence shows all three SATISFIED. Recommend ticking the boxes during merge-prep (not a blocker; the cross-reference table at L201-206 already shows Phase 5 as the home, just with `Pending` status).

### Invariant Verification (D-61..D-69)

| Invariant | ADR Anchor | Status | Evidence |
|-----------|-----------|--------|----------|
| D-61 (Inv 1) — ERR-01 token-mint invalid_grant → LoginFailed | ADR-0005 §Invariant 1 | ✓ VERIFIED | `spec/auth_spec.lua:112-119` (mapping) + L350-363 (round-trip) |
| D-62 (Inv 2) — ERR-02 5xx retry {1,2,4}s × 3 attempts | ADR-0005 §Invariant 2 | ✓ VERIFIED | `src/http.lua:25` (constants), `spec/http_retry_spec.lua:72-103` (test asserts captured_sleeps = {1,2}) |
| D-63 (Inv 3) — ERR-03 429 Retry-After integer w/ 60s cap, 30s default, lowercase support | ADR-0005 §Invariant 3 | ✓ VERIFIED | `src/http.lua:69-84` + `spec/http_retry_spec.lua:105-189` (7 tests) |
| D-64 COLLAPSED (Inv 4) — ERR-04 immediate `error.token_revoked` (no silent re-mint under assertion-grant) | ADR-0005 §Invariant 4 | ✓ VERIFIED | 4 call sites; `spec/auth_spec.lua:372-405`. Collapse rationale recorded in ADR-0005 §Invariant 4 + RESEARCH §Pattern-2; preserves SEC-03/AUTH-05 |
| D-65 (Inv 5) — ERR-05 network failure → `error.network`; no `pcall` around `conn:request` | ADR-0005 §Invariant 5 | ✓ VERIFIED | `src/http.lua:161-179` (NO pcall around `conn:request`); `spec/refresh_fail_whole_spec.lua:240-308`. SSL handshake bypass documented as Carve-out 1 (intentional) |
| D-66 (Inv 6) — ERR-06 fail-whole-refresh | ADR-0005 §Invariant 6 | ✓ VERIFIED | `src/entry.lua:174-244`; `spec/refresh_fail_whole_spec.lua` 4 cases. `spec/phase3_surface_preservation_spec.lua:228-252` enforces step count = 20 |
| D-67 — MM.sleep sandbox primitive (CONTEXT mistakenly wrote `MM.os`) | ADR-0005 §Sleep mechanism | ✓ VERIFIED | `src/http.lua:101-104` uses `MM.sleep`; Q9 probe block at `tools/probe.lua:109-127` for OPTIONAL Yves-time confirmation; CI harness stubs at `spec/helpers/mm_mocks.lua` |
| D-68 — ONE INFO retry log line, Bearer-safe (headers structurally absent from log) | ADR-0005 §Invariant 2 | ✓ VERIFIED | `src/http.lua:93-96` (format string); `spec/refresh_log_redaction_spec.lua:441-512` Gate D (exactly 2 lines on 503-storm, format-pattern match, NO Bearer/eyJ anywhere) |
| D-69 — i18n key set shrunk to 2 new keys (server_busy + token_revoked) | ADR-0005 §i18n keys actually added | ✓ VERIFIED | `src/i18n.lua:44-47` DE + L87-90 EN; UTF-8 byte-escape per Phase-4 convention |

### Phase-3/4 Surface Preservation

| Surface | Status | Evidence |
|---------|--------|----------|
| `SupportsBank` byte-identity | ✓ VERIFIED | `spec/phase3_surface_preservation_spec.lua:315-319` (verbatim string match) |
| `InitializeSession2` signature + credential prompt | ✓ VERIFIED | `spec/phase3_surface_preservation_spec.lua:323-329` |
| `M_finance.fetch / fetch_all / fetch_account_state / parse_transaction` function-type signatures | ✓ VERIFIED | `spec/phase3_surface_preservation_spec.lua:185-194` |
| `M_mapping.purchase_to_transaction` byte-identity for purchase_simple_sale | ✓ VERIFIED | `spec/phase3_surface_preservation_spec.lua:196-226` (name + transactionCode prefix + currency + booked=false) |
| `entry.lua` step count = 20 | ✓ VERIFIED | `spec/phase3_surface_preservation_spec.lua:228-252` |
| D-38 closed-prefix set (5 entries: sale/refund/fee/fee:aggregate/payout) | ✓ VERIFIED | `spec/refresh_log_redaction_spec.lua:264-338` (longest-match per WR-02; all 5 buckets non-empty) |
| Plan 05-04 non-interference: happy-path balance/pendingBalance/transactions unchanged | ✓ VERIFIED | `spec/phase3_surface_preservation_spec.lua:254-303` (balance=123.45, pendingBalance=6.78) |
| SEC-03 redaction extended to Finance API responses | ✓ VERIFIED | `spec/refresh_log_redaction_spec.lua:352-410` (5 cases) |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers in any of `src/errors.lua`, `src/finance.lua`, `src/http.lua`, `src/i18n.lua`, `src/pagination.lua`, `src/purchases.lua`, `docs/adr/0005-resilience-invariants.md`, `tools/probe.lua`, or any Phase-5 spec file | — | Clean — no debt markers in modified files |

### Carve-outs (documented in ADR-0005 — NOT gaps)

| Carve-out | Why It's NOT a Gap |
|-----------|--------------------|
| D-64 collapse (ERR-04 immediate `error.token_revoked` instead of silent re-mint) | Documented in ADR-0005 §Invariant 4 + RESEARCH §Pattern-2. Silent re-mint is INFEASIBLE under assertion-grant (no refresh token; SEC-03/AUTH-05 forbid persisting API key beyond `InitializeSession2`). User remediation path preserves ERR-04 intent ("don't return LoginFailed; session was revoked, not credentials bad"). Phase 7 (OAuth Authorization-Code) revisits if/when it ships. |
| Carve-out 1 — SSL handshake failures bypass ERR-05 | ADR-0003 Q8 bonus finding: `pcall` does NOT catch SSL handshake failures — MoneyMoney aborts the chunk regardless. Documented as intentional with mitigation strategy (TLS 1.2+ enforced by MoneyMoney; OS-level cert verification; user-facing remediation via Protokoll panel). Future phases SHOULD NOT attempt to "fix" — root cause is in MM, not user code. |
| Carve-out 2 — HTTP-date `Retry-After` silently degrades to 30s default | Integer-only parsing is RFC-conformant; HTTP-date never observed in Zettle fixtures; ~80 lines of unneeded Lua avoided. Safe degradation (30s well within MM per-call timeout). |
| Carve-out 3 — re-anchor of Carve-out 1 | Plan 05-05 acceptance-criteria anchor (stable `grep -c 'Carve-out 3'` target); substantive content in Carve-out 1. |

## Aggregate Verdict

**READY-TO-MERGE.**

All 6 ROADMAP success criteria and all 6 ERR-* requirements (ERR-01..ERR-06) have verified production code, wired test gates, and explicit assertion-driven evidence in the codebase. ADR-0005 captures all design decisions including the D-64 collapse (semantically equivalent ERR-04 path, not a scope reduction) and the SSL-handshake carve-out (out of Lua's reach by sandbox design). The 365-test busted suite passes; the build is reproducible (sha256 `b151f16569f7f3fa855d59403c8bafc26a07557a515f9d8b9cef88635fe85e63`); no debt markers in any modified file.

**Phase-3/4 surface preservation is intact:** byte-identical SupportsBank/InitializeSession2; M_finance + M_mapping signatures unchanged; entry.lua 20 step-markers (4+16) preserved; happy-path balance/pendingBalance/transactions byte-stable (123.45 / 6.78 / D-38 closed-set).

**Optional follow-up (NOT a gate):**
- Q9 MM.sleep sandbox probe is OPTIONAL per ADR-0005 §Sleep mechanism. Yves runs the probe inside MoneyMoney when convenient and appends the Q9 row to `docs/adr/0003-sandbox-probe-results.md`. The codebase already defensively pcall-wraps `MM.sleep` so an ABSENT outcome would degrade rather than abort.
- `.planning/REQUIREMENTS.md` checkboxes for ERR-04..ERR-06 still show `[ ]` on L72-74. Implementation evidence is complete; recommend ticking during merge-prep.

**Local environment caveat:** luacheck failed locally due to Lua 5.5 / luacheck 1.2.0 incompatibility (`standards.lua:134: attempt to assign to const variable`). CI workflow pins Lua 5.4 (`.github/workflows/ci.yml:30`) where luacheck is known-good. Not a Phase 5 regression.

---

_Verified: 2026-06-22_
_Verifier: Claude (gsd-verifier)_
