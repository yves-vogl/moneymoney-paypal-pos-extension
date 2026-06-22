---
phase: 05-resilience-error-handling
plan: 03
subsystem: http-retry-with-backoff
tags: [wave-2, http, retry, backoff, rate-limit, tdd, mvp, server-busy]
requires:
  - 05-02 (i18n keys + 599 sentinel dispatch + RED scaffolds)
  - Phase 2 M_http.get_json / post_form / _infer_status
provides:
  - 5xx retry-with-backoff (3 attempts, {1, 2, 4}s sleeps; ADR-0005 Invariant 2)
  - 429 single-retry honoring Retry-After (integer-only, 60s cap, 30s default; ADR-0005 Invariant 3)
  - 599 sentinel on 5xx exhaustion → consumed by M_errors (Plan 05-02)
  - Empty-body Phase-2 ERR-05 path preserved (3-attempt exhaust → nil status)
  - INFO log per retry attempt with Bearer-safe format string (D-68)
  - 10 GREEN it() blocks in spec/http_retry_spec.lua (1 sanity + 8 Plan-05-02 pending now passing + 1 lowercase-header Pitfall §6)
  - 4 new/adjusted tests in spec/http_spec.lua (2 new post_form retry tests + 2 adjusted for retry semantics)
  - 4 adjusted tests in spec/finance_spec.lua + spec/entry_spec.lua (Rule-1 scope fixes — retry semantics break baselines)
affects:
  - src/http.lua (+116 LoC: 5 constants, 3 private helpers, get_json + post_form refactored)
  - spec/http_retry_spec.lua (+78 LoC: 8 pending→it flips + 1 new lowercase test + capturing MM.sleep stub)
  - spec/http_spec.lua (+40 LoC: 2 new tests + 2 adjusted + before_each MM.sleep stub)
  - spec/finance_spec.lua (+7 LoC: 2 tests adjusted + MM.sleep stub)
  - spec/entry_spec.lua (+12 LoC: 2 tests adjusted + 3 before_each MM.sleep stubs)
tech-stack:
  added: []
  patterns:
    - "Shared retry loop helper (_request_with_retry) backing both GET and POST verbs — DRY single source of retry semantics"
    - "5-tuple resp_headers capture in retry loop — Risk R-1 inheritance (MoneyMoney's conn:request 5th return value)"
    - "pcall-wrapped MM.sleep — Pitfall §10 defensive guard for future MM versions"
    - "Capturing MM.sleep stub in tests (_captured_sleeps table) — assert exact backoff durations per retry decision"
    - "Bearer-safe INFO log format string (structural absence — headers table NEVER concatenated)"
key-files:
  modified:
    - src/http.lua
    - spec/http_retry_spec.lua
    - spec/http_spec.lua
    - spec/finance_spec.lua
    - spec/entry_spec.lua
decisions:
  - "D-62 + D-63 + ADR-0005 Invariants 2+3 land — retry semantics enforced by 10 GREEN tests with capturing MM.sleep stub"
  - "Empty-body remains the only 5xx-equivalent signal (RESEARCH §4.b heuristic); body-shape 5xx (e.g. {error:server_error}) NOT added — _infer_status still returns 400 conservative for unknown error names per Phase-2 Pitfall 5. The 599 sentinel ships ready for the day _infer_status grows a 5xx branch; today no test triggers it (the 5xx-retry test exhausts empty bodies through nil-status path)"
  - "POST retry parity with GET justified by RESEARCH §10.b: OAuth2 jwt-bearer assertion is idempotent per RFC 7521 §4.1 within TTL window — same assertion → same access_token; safe to retry"
  - "Caller layer (M_auth, M_purchases, M_finance, entry.lua) needed ZERO source code change. Only 5 caller-layer tests required adjustment because the OLD tests assumed exactly 1 HTTP call per scenario; the NEW semantics consume 2 (429) or 3 (empty) per scenario. The adjustment is purely additional Mocks.push_response() calls + MM.sleep stub"
  - "Reproducible build SHA changed: 79f46d13... (Plan 05-02 baseline) → cabf9f9d... (Plan 05-03 baseline for Plan 05-04)"
metrics:
  duration_minutes: ~12
  completed_date: 2026-06-22
  commits: 3
  files_modified: 5
  files_created: 0
  loc_added: 253
  loc_removed: 50
  reproducible_sha: cabf9f9d74cb8b1619aa8c16ab3b0ae17c4f7b660a28f23eacc8ee78f8bbd32d
---

# Phase 05 Plan 03: HTTP Retry-With-Backoff Summary

Lands the production retry semantics that flip Plan 05-02's 8 pending() scaffolds to GREEN it() blocks and propagate transparently to every M_http caller.

## One-Liner

5xx retry (3 attempts, {1,2,4}s) + 429 single-retry honoring Retry-After (integer-only, 60s cap, 30s default) + 599 sentinel for 5xx exhaustion + INFO log per retry attempt with Bearer-safe format — all inside a shared `_request_with_retry` helper that drives both `M_http.get_json` and `M_http.post_form` without touching their public signatures.

## Self-Check: PASSED

- `src/http.lua` contains all 5 retry constants (`_MAX_ATTEMPTS`, `_BACKOFF_SECONDS`, `_RETRY_AFTER_CAP`, `_RATE_LIMIT_DEFAULT`, `_SENTINEL_5XX_EXHAUSTED`)
- `src/http.lua` contains all 3 module-private helpers (`_parse_retry_after`, `_sleep_with_log`, `_request_with_retry`)
- `src/http.lua` does NOT contain `pcall(function() return conn:request` — ADR-0003 Q8 / Pitfall §10 invariant preserved
- `src/http.lua` contains `HTTP retry: attempt=` INFO log format string
- `src/http.lua` final size: 264 LoC (vs 149 LoC Phase-2 baseline → +116 LoC delta)
- 3 GPG-signed commits on `phase-5/resilience`:
  - `be4c026 G feat(05-03): add retry-with-backoff to M_http (5xx 3-attempts {1,2,4}s; 429 single-retry Retry-After integer-only; 599 sentinel; ADR-0005 Invariants 2+3)`
  - `7ffc41f G test(05-03): turn http_retry_spec.lua RED scaffolds GREEN (D-62 + D-63 + Pitfall §6 lowercase header)`
  - `67f63b5 G test(05-03): extend http_spec for post_form retry symmetry + adjust rate_limit / empty-body / finance / entry specs for single-retry + 3-attempt semantics`
- Full `busted spec/` GREEN: 352 successes / 0 failures / 0 errors / 3 pending (Plan 05-05's refresh_fail_whole still pending)
- `lua tools/build.lua --verify` reproducible — SHA `cabf9f9d74cb8b1619aa8c16ab3b0ae17c4f7b660a28f23eacc8ee78f8bbd32d` (baseline for Plan 05-04)
- `luacheck src/ spec/` clean (0 warnings / 0 errors across 38 files)

## Deltas

### src/http.lua (149 → 264 LoC; +116 LoC)

| Section | Change |
|---------|--------|
| Module header docstring | +5 lines noting Phase 5 retry additions (ADR-0005 Invariants 2+3 + Carve-out 2) |
| Module-private constants | +5 constants: `_MAX_ATTEMPTS=3`, `_BACKOFF_SECONDS={1,2,4}`, `_RETRY_AFTER_CAP=60`, `_RATE_LIMIT_DEFAULT=30`, `_SENTINEL_5XX_EXHAUSTED=599` |
| `_parse_retry_after(resp_headers)` | NEW. Integer-only parse with 3 guards (NaN, negative, non-numeric) + cap clamp + both casing variants ("Retry-After" + "retry-after") |
| `_sleep_with_log(seconds, url, attempt, status)` | NEW. Emits ONE INFO log line with Bearer-safe format string; pcall-wraps MM.sleep (Pitfall §10 defensive) |
| `_request_with_retry(method, url, body, contentType, h)` | NEW. Shared retry loop: empty-body retry → ERR-05 path; 429 single-retry honoring Retry-After; 5xx 3-attempt retry → 599 sentinel; 200/other → immediate return |
| `M_http.post_form` | Refactored from 32 LoC inline to 9 LoC delegating to `_request_with_retry`. Public signature unchanged |
| `M_http.get_json` | Refactored from 24 LoC inline to 7 LoC delegating to `_request_with_retry`. Public signature unchanged |
| `M_http.shutdown` | Unchanged |
| `M_http._infer_status` | Unchanged |

### spec/http_retry_spec.lua (113 → 191 LoC; +78 LoC)

| Test | Before (Plan 05-02) | After (Plan 05-03) |
|------|---------------------|---------------------|
| 200-first-attempt sanity | `it()` GREEN | `it()` GREEN (extended with `#_captured_sleeps == 0` assert) |
| 5xx retry: 3 attempts → 599 sentinel | `pending()` | `it()` GREEN (uses empty-body path → nil status, 3 captured_requests, sleeps `{1, 2}`) |
| 5xx retry: succeeds on 2nd attempt | `pending()` | `it()` GREEN (2 captured_requests, 1 sleep, 1 "HTTP retry:" log) |
| 429 Retry-After=5 honored | `pending()` | `it()` GREEN (`MM.sleep(5)` captured) |
| 429 no Retry-After → 30s default | `pending()` | `it()` GREEN (`MM.sleep(30)` captured) |
| 429 Retry-After=9999 capped at 60 | `pending()` | `it()` GREEN (`MM.sleep(60)` captured) |
| 429 Retry-After=-5 rejected → 30s | `pending()` | `it()` GREEN (`MM.sleep(30)` captured) |
| 429 Retry-After="abc" rejected → 30s | `pending()` | `it()` GREEN (`MM.sleep(30)` captured) |
| 429 exhausted → 429 + error.rate_limit | `pending()` | `it()` GREEN (asserts via M_errors.from_http_status) |
| 429 lowercase retry-after (Pitfall §6) | — | `it()` GREEN (NEW; asserts `MM.sleep(7)`) |

**Final spec count: 10 it() blocks, 0 pending(), all GREEN.**

### spec/http_spec.lua (250 → 290 LoC; +40 LoC)

| Test | Change |
|------|--------|
| `before_each` | Added MM.sleep no-op stub (so retry-bearing tests do not block) |
| `post_form returns nil status for empty body` | Adjusted: queue 3 empty bodies (3-attempt exhaustion); assert 3 captured_requests |
| `post_form rate_limited fixture returns 429 (M-02)` | Adjusted: queue 2 rate_limit responses (single retry consumes both); assert 2 captured_requests |
| `post_form: 5xx-equivalent empty body exhausts after 3 attempts` | NEW |
| `post_form: succeeds on 2nd attempt after one empty-body retry` | NEW |

### spec/finance_spec.lua (Rule-1 scope adjustment)

| Test | Change |
|------|--------|
| `before_each` | Added MM.sleep no-op stub |
| `fetch surfaces rate_limit body as status 429` | Queue 2 responses (single-retry consumes both) |
| `fetch surfaces empty body as nil status` | Queue 3 responses (3-attempt exhaustion) |

### spec/entry_spec.lua (Rule-1 scope adjustment)

| Test | Change |
|------|--------|
| All 3 `before_each` blocks | Added MM.sleep no-op stub |
| `InitializeSession2 returns error.rate_limit (M-02)` | Queue 2 responses (single retry) |
| `RefreshAccount returns string error on purchase-fetch HTTP failure (ERR-06)` | Queue 2 responses (single retry) |

## Deviations from Plan

### Rule 1 (Auto-fixed scope-adjacent failures)

**1. [Rule 1 - Bug] Adjusted spec/finance_spec.lua + spec/entry_spec.lua for new retry semantics**
- **Found during:** Task 3 (full-suite `busted spec/`)
- **Issue:** 4 pre-existing tests in finance_spec + entry_spec assumed exactly 1 HTTP call per scenario (rate_limit / empty body). Plan 05-03's retry loop fires 2× on 429 and 3× on empty bodies; the second/third call has no queued response → `mm_mocks: no queued response for ...` error.
- **Fix:** Added `MM.sleep = function(_) end` stub to before_each blocks (3 in entry_spec, 1 in finance_spec); added 1 extra `Mocks.push_response()` for 429 tests; added 2 extra `Mocks.push_response()` for empty-body test
- **Files modified:** spec/finance_spec.lua, spec/entry_spec.lua
- **Commit:** `67f63b5`
- **Scope justification:** DIRECTLY caused by Plan 05-03's retry change to src/http.lua. Per `<scope_boundary>` rule: "auto-fix issues DIRECTLY caused by the current task's changes."

### No other deviations

- No architectural changes (Rule 4 untouched)
- No new dependencies
- No new public API surface (`M_http.get_json` / `post_form` / `shutdown` / `_infer_status` signatures unchanged)
- No `require()` of sibling modules added
- No CLAUDE.md directives breached (Lua 5.4, no external Lua modules in shipped file, English commits/code)

## Pitfalls Covered (Plan 05-03)

| Pitfall | Coverage |
|---------|----------|
| §1 Retry-After: -5 | `_parse_retry_after` returns nil on negative → default 30s. Tested in spec/http_retry_spec.lua |
| §2 Iterative not recursive | `for attempt = 1, _MAX_ATTEMPTS do` in `_request_with_retry`. No recursion exists |
| §3 Bearer-safe log format | INFO log format string has NO `h` (headers) reference; only url/attempt/status/after_ms. Verified by absence in source AND existing get_json Bearer-non-leakage test |
| §6 Lowercase retry-after header | `_parse_retry_after` checks BOTH `["Retry-After"]` AND `["retry-after"]`. Tested in spec/http_retry_spec.lua |
| §10 No pcall around conn:request | `_request_with_retry` calls `conn:request` directly; pcall is ONLY around `JSON(raw):dictionary()`. Verified by `! grep pcall(function() return conn:request` |
| §10 (defensive) Future MM.sleep error | `_sleep_with_log` pcall-wraps `MM.sleep`; falls through to no-backoff continuation on error |

## Caller-Layer Impact

Per ADR-0005 Invariants 2+3: retry semantics propagate TRANSPARENTLY through M_http to its callers.

| Caller | Code change required | Reason |
|--------|---------------------|--------|
| `src/auth.lua` (M_auth.exchange_assertion / fetch_profile) | NONE | Still receives `(parsed, status, raw)` 3-tuple. Status may now be 599 (Plan 05-02 M_errors maps to error.server_busy). The retry happened transparently inside `_request_with_retry` |
| `src/purchases.lua` (M_purchases.fetch) | NONE | Same |
| `src/finance.lua` (M_finance.fetch / fetch_account_state) | NONE | Same |
| `src/entry.lua` (InitializeSession2 / RefreshAccount) | NONE | Inherits retry transparently through M_auth + M_purchases + M_finance call chain |

Only test code in spec/finance_spec.lua + spec/entry_spec.lua needed adjustment — for the mock harness reason described in Deviations §1.

## Threat Model Compliance (Plan 05-03 register)

| Threat ID | Status |
|-----------|--------|
| T-05-03-01 Information Disclosure (INFO log Bearer leak) | MITIGATED. Structural absence (format string has no headers reference); defense-in-depth via M_log.redact |
| T-05-03-02 Tampering (Retry-After) | MITIGATED. Three guards (NaN/negative/non-numeric) + cap; both casings checked |
| T-05-03-03 Denial of Service (self-DoS via retry storm) | MITIGATED. Iterative `for attempt = 1, 3 do`; 429 single-retry; hard cap on backoff |
| T-05-03-04 Denial of Service (MM.sleep runtime error) | MITIGATED. pcall-wrapped; 60s cap |
| T-05-03-05 Tampering (test-only MM.sleep stub) | ACCEPTED (test mechanism; no production attack surface) |
| T-05-03-06 Repudiation (OAuth retry replay) | ACCEPTED (RFC 7521 §4.1 assertion-grant is idempotent within TTL) |
| T-05-03-SC Supply chain | ACCEPTED (zero installs, pure Lua source + spec edits) |

## Reproducible Build Trail

| Plan | SHA-256 of dist/paypal-pos.lua |
|------|-------------------------------|
| Plan 05-01 baseline | `f54a239...` (ADR only; src unchanged) |
| Plan 05-02 baseline | `79f46d13506cde5022409bbf5c7911f7d2c3b47871980ce3dbc70536b112a2e6` |
| **Plan 05-03 baseline** | **`cabf9f9d74cb8b1619aa8c16ab3b0ae17c4f7b660a28f23eacc8ee78f8bbd32d`** |

Plan 05-04 (caller-layer error mapping) and Plan 05-05 (fail-whole gating) consume this baseline.

## Plan 05-04 / 05-05 Unblocked

- **Plan 05-04** can now wire `M_purchases.fetch` + `M_finance.fetch` to translate 401-after-mint → `error.token_revoked` per ADR-0005 Invariant 4 caller-layer dispatch.
- **Plan 05-05** can now flip the 3 pending() tests in spec/refresh_fail_whole_spec.lua to GREEN because RefreshAccount inherits the full retry stack: a mid-pipeline 5xx now exhausts to 599 and surfaces error.server_busy without partial transactions being committed.
