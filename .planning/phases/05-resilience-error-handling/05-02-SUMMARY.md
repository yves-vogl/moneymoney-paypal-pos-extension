---
phase: 05-resilience-error-handling
plan: 02
subsystem: errors-i18n-tdd-scaffolds
tags: [wave-1, i18n, errors, red-specs, tdd, mvp, server-busy, 599-sentinel]
requires:
  - 05-01 (ADR-0005 accepted; Invariants 1-6 published)
  - Phase 2 M_errors.from_http_status (D-24)
  - Phase 2 M_http._infer_status (Risk R-1 inference)
  - Phase 2 spec/fixtures/auth/token_invalid_grant.json
provides:
  - i18n key error.server_busy (de + en) for Plan 05-03 retry-exhausted surface
  - i18n key error.token_revoked (de + en) for Plan 05-04 caller-layer surface
  - M_errors 599 sentinel dispatch (Plan 05-03 producer / M_errors consumer)
  - spec/http_retry_spec.lua RED scaffold (Plan 05-03 turns GREEN)
  - spec/refresh_fail_whole_spec.lua RED scaffold (Plan 05-05 turns GREEN)
  - ERR-01 regression gate in spec/auth_spec.lua (frozen Phase-2 behavior)
affects:
  - src/i18n.lua (+8 LoC across both locales)
  - src/errors.lua (+15 LoC: docstring + sentinel branch)
  - spec/errors_spec.lua (+28 LoC: 599 + range + SEC-03 regression)
  - spec/auth_spec.lua (+18 LoC: ERR-01 round-trip)
tech-stack:
  added: []
  patterns:
    - "Phase-5-internal HTTP status sentinel: integer 599 signals 5xx-retry-exhausted (set by Plan 05-03 M_http retry loop, consumed by M_errors)"
    - "pending() RED scaffolds — testable shape committed alongside production-skeleton tasks; future GREEN tasks flip pending() -> it()"
    - "MM.sleep no-op stub in before_each — gating spec invariant so future GREEN flips never block on real seconds"
key-files:
  created:
    - spec/http_retry_spec.lua
    - spec/refresh_fail_whole_spec.lua
  modified:
    - src/i18n.lua
    - src/errors.lua
    - spec/errors_spec.lua
    - spec/auth_spec.lua
decisions:
  - "D-69 reconciled: '+4 entries' shrunk to '+1 dispatch branch + 2 i18n keys' per RESEARCH §6 (error.network + error.rate_limit already shipped in Phase 2)"
  - "D-64 collapse: PATTERNS.md M_auth.with_retry(orgUuid, callback) NOT implemented; 401-to-token_revoked translation deferred to Plan 05-04 caller layer (purchases + finance) per ADR-0005 Invariant 4"
  - "599 sentinel rationale: Phase-5-internal contract (NOT a real HTTP status) so callers can distinguish 'retry-exhausted unavailable' from 'generic 5xx body-shape inference'"
  - "ERR-01 verified-via-test gate: no source change — Phase-2 dispatch was already correct; spec freezes the behavior so any future refactor surfaces the regression"
  - "Fixture name correction: PLAN.md referenced auth_invalid_grant.json but repo has token_invalid_grant.json (Phase 2). Used existing fixture; no new fixture created."
metrics:
  duration_minutes: ~15
  completed_date: 2026-06-22
  commits: 3
  files_modified: 4
  files_created: 2
  loc_added: 100
  loc_removed: 6
---

# Phase 05 Plan 02: I18n keys + M_errors 599 sentinel + RED scaffolds Summary

Lands the i18n + dispatch extension + RED specs that gate Plans 05-03, 05-04, and 05-05.

## Self-Check: PASSED

- `src/i18n.lua` contains `error.server_busy` 2× and `error.token_revoked` 2× (de+en parity per I18N-02)
- `src/errors.lua` contains `status == 599` branch BEFORE `status >= 500 and status <= 598`
- `src/errors.lua` does NOT reference `error.token_revoked` (per ADR-0005 Invariant 4 — caller-layer)
- `spec/http_retry_spec.lua` exists with 1 it() + 8 pending()
- `spec/refresh_fail_whole_spec.lua` exists with 1 it() + 3 pending()
- Three GPG-signed commits exist on phase-5/resilience:
  - `273330b G feat(05-02): add error.server_busy + error.token_revoked i18n keys; extend M_errors with 599 retry-exhausted sentinel`
  - `9a30df1 G test(05-02): extend errors_spec with 599 sentinel + auth_spec with ERR-01 fixture`
  - `2b673ef G test(05-02): add http_retry_spec + refresh_fail_whole_spec RED scaffolds`
- Full `busted spec/` GREEN: 341 ok / 0 not ok / 11 pending (336 baseline + 5 new passing)
- `lua tools/build.lua --verify` reproducible — SHA `79f46d13506cde5022409bbf5c7911f7d2c3b47871980ce3dbc70536b112a2e6`
- `luacheck src/ spec/` clean (0 warnings / 0 errors)

## Deltas

### src/i18n.lua (+8 LoC)

Two new keys added to both `STRINGS.de` and `STRINGS.en` between the existing `error.rate_limit` and `credential.api_key.label`:

| Key | German (primary) | English (fallback) |
|-----|------------------|--------------------|
| `error.server_busy` | "PayPal-POS-Server zurzeit nicht erreichbar — bitte später erneut versuchen." | "PayPal POS server unavailable — please retry later." |
| `error.token_revoked` | "Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen." | "Session lost — please re-enter the API key in MoneyMoney." |

UTF-8 byte-escape style (`\xe2\x80\x94` em-dash; `\xc3\xa4` umlaut) matches Phase-4 convention. Existing keys unchanged.

### src/errors.lua (+15 LoC)

The existing `D-24 case 5` branch (`status >= 500 and status <= 599 → error.network`) split into:

```lua
if status == 599 then
  return M_i18n.t("error.server_busy")
end
if status >= 500 and status <= 598 then
  return M_i18n.t("error.network", tostring(status))
end
```

Docstring header expanded to document the 599 sentinel contract (set by M_http retry exhaustion, Plan 05-03). `error.token_revoked` intentionally NOT referenced per ADR-0005 Invariant 4 — the 401-after-mint translation is the caller's responsibility because `from_http_status` cannot distinguish "401 at token mint" (LoginFailed) vs "401 after mint" (session lost) without additional context.

Backward compat preserved:
- `from_http_status(nil, ...)` → `error.network` (D-24 case 1)
- `from_http_status(200..299, ...)` → `nil` (D-24 case 2)
- `from_http_status(400|401|403, ...)` → `LoginFailed` (D-24 case 3)
- `from_http_status(429, ...)` → `error.rate_limit` (D-24 case 4)
- `from_http_status(500..598, ...)` → `error.network` with status (D-24 case 5 preserved)
- `from_http_status(999, ...)` → `error.network` catch-all (D-24 case 6)

### spec/errors_spec.lua (+28 LoC, -4 LoC)

Removed: legacy `it("599 returns network string with status", ...)` (now contradicts the sentinel).
Added:
1. `it("500/501/502/503/598 still return network string with status (D-24 case 5 backward compat)", ...)` — table-driven over five codes
2. `it("599 returns server_busy string (Phase 5 / D-62 retry-exhausted sentinel; ADR-0005 Invariant 2)", ...)`
3. `it("599 sentinel SEC-03: body never echoed into server_busy result", ...)` — body-redaction regression on the new branch

### spec/auth_spec.lua (+18 LoC)

Added `it("ERR-01 / D-61: exchange_assertion 400 invalid_grant maps to LoginFailed via M_errors", ...)` — full round-trip test using existing Phase-2 fixture `spec/fixtures/auth/token_invalid_grant.json`. The Phase-2 `_infer_status` branch maps `{"error":"invalid_grant"}` → 400, which `M_errors.from_http_status` then routes to `LoginFailed`. No source change required; the test is a regression gate per ADR-0005 Invariant 1.

### spec/http_retry_spec.lua (NEW, 113 LoC)

1 GREEN sanity test (200 first-attempt no retry, no sleep log) + 8 `pending()` RED scaffolds for Plan 05-03 GREEN:

| # | Behavior | Plan 05-03 Source |
|---|----------|--------------------|
| 1 | 5xx retry: 3 attempts → 599 sentinel | M_http retry loop with `{1,2,4}s` backoff (final attempt elided) |
| 2 | 5xx retry: 2nd-attempt success | Same loop; first 5xx body triggers single retry |
| 3 | 429 retry: Retry-After integer honored | `_parse_retry_after` header parser |
| 4 | 429 retry: no Retry-After → 30s default | Default fallback |
| 5 | 429 retry: Retry-After=9999 capped at 60s | 60s cap |
| 6 | 429 retry: Retry-After=-5 → 30s | Negative-value guard |
| 7 | 429 retry: Retry-After="abc" → 30s | tonumber() guard |
| 8 | 429 retry exhausted on 2nd attempt → rate_limit | Single-retry-per-refresh |

MM.sleep stubbed in before_each so future GREEN flips never block on real seconds.

### spec/refresh_fail_whole_spec.lua (NEW, 98 LoC)

1 GREEN sanity test (seed_token bearer round-trip via cached_token + JWT-shape false-positive guard) + 3 `pending()` RED scaffolds for Plan 05-05 GREEN:

| # | Behavior | Plan 05-05 Source |
|---|----------|--------------------|
| 1 | ERR-06: mid-pipeline 500 → German error returned, no partial txns, since untouched | RefreshAccount fail-whole-refresh assertion |
| 2 | ERR-06: since parameter byte-identical across failed refresh + retry | URL-capture comparison across two RefreshAccount calls |
| 3 | ERR-05: network failure (empty body × retries) → error.server_busy from RefreshAccount | retry exhaustion → sentinel round-trip |

`seed_token` helper copied verbatim from `spec/refresh_idempotency_spec.lua` L55-64.

## Test Suite Delta

| Metric | Before Plan 05-02 | After Plan 05-02 | Delta |
|--------|--------------------|-------------------|-------|
| Total it() passing | 336 | 341 | +5 |
| Pending | 0 | 11 | +11 |
| Failures | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| TAP `1..N` | 1..336 | 1..352 | +16 |

The +5 passing breakdown:
- errors_spec.lua: +3 (500/501/502/503/598 range; 599 server_busy; 599 SEC-03 regression); -1 (legacy 599 network); net +2
- auth_spec.lua: +1 (ERR-01 fixture round-trip)
- http_retry_spec.lua: +1 (200 first-attempt sanity)
- refresh_fail_whole_spec.lua: +1 (seed_token bearer round-trip)

Total passing: 336 - 1 (legacy 599) + 3 + 1 + 1 + 1 = 341. ✅

## Build Reproducibility

| Phase | dist/paypal-pos.lua SHA-256 |
|-------|-------------------------------|
| Plan 05-01 baseline | (Plan 05-01 SUMMARY) |
| **Plan 05-02 after Task 1 (src changes)** | `79f46d13506cde5022409bbf5c7911f7d2c3b47871980ce3dbc70536b112a2e6` |
| Plan 05-02 after Tasks 2+3 (spec-only) | `79f46d13506cde5022409bbf5c7911f7d2c3b47871980ce3dbc70536b112a2e6` (unchanged — specs outside dist/ manifest) |

Plan 05-03 baseline: `79f46d13506cde5022409bbf5c7911f7d2c3b47871980ce3dbc70536b112a2e6`.

## Deviations from Plan

### Fixture name correction

**1. [Rule 3 - Blocking] Fixture name auth_invalid_grant.json does not exist; existing fixture is token_invalid_grant.json**
- **Found during:** Task 2 read_first
- **Issue:** PLAN.md references `spec/fixtures/auth/auth_invalid_grant.json` 4 times. Actual Phase-2 fixture is `spec/fixtures/auth/token_invalid_grant.json` (same content shape; renamed during Phase-2 review).
- **Fix:** Used `Fixtures.load("auth/token_invalid_grant")` in the new ERR-01 test. No new fixture file created — the existing one has the required `{"error":"invalid_grant","error_description":"..."}` shape.
- **Files modified:** spec/auth_spec.lua (single reference)
- **Commit:** 9a30df1

### Line-length wrap on new i18n entries

**2. [Rule 1 - Bug] Initial i18n.lua edit exceeded 120-char line limit**
- **Found during:** Task 1 luacheck
- **Issue:** Single-line `["error.server_busy"] = "PayPal-POS-Server ..."` reached 126 cols.
- **Fix:** Continuation-line style `["error.server_busy"]         =\n      "..."` matching the Phase-4 `account.purpose.fee_aggregate` pattern.
- **Commit:** 273330b (caught + fixed before commit)

### Errors.lua docstring did not reference token_revoked symbol

**3. [Rule 3 - Blocking] Initial errors.lua docstring mentioned `error.token_revoked` literal — fails the `! grep -q 'error.token_revoked' src/errors.lua` acceptance gate**
- **Found during:** Task 1 verification
- **Issue:** Docstring originally read "...vs 'error.token_revoked'..." which would make `grep -L 'error.token_revoked' src/errors.lua` fail.
- **Fix:** Rephrased docstring to "...vs '401 from resource call after successful mint'... The corresponding i18n key is intentionally NOT referenced here." — semantically equivalent, gate-compliant.
- **Commit:** 273330b (caught + fixed before commit)

### Long pending() description in refresh_fail_whole_spec

**4. [Rule 3 - Blocking] Pending test name "ERR-05: network failure (empty body throughout retries) → error.network from RefreshAccount (D-65 / ADR-0005 Invariant 5)" is 145 chars**
- **Found during:** Task 3 luacheck
- **Fix:** Added `-- luacheck: ignore 631` directive matching the precedent in `spec/refresh_idempotency_spec.lua`.
- **Commit:** 2b673ef

## ADR Compliance

| ADR-0005 Invariant | Surface in Plan 05-02 |
|---------------------|------------------------|
| 1 — token mint failure → LoginFailed | ✅ Frozen by `spec/auth_spec.lua` ERR-01 round-trip |
| 2 — 5xx retry exhaustion → server_busy | ✅ M_errors 599 sentinel branch + RED scaffolds 1,2 |
| 3 — 429 Retry-After integer + cap | (RED scaffolds 3-8 → Plan 05-03 GREEN) |
| 4 — 401-after-mint → caller-layer | ✅ token_revoked key shipped; intentionally NOT in M_errors |
| 5 — ERR-05 network failure | (RED scaffold 3 in refresh_fail_whole_spec → Plan 05-05 GREEN) |
| 6 — ERR-06 fail-whole, since untouched | (RED scaffolds 1+2 in refresh_fail_whole_spec → Plan 05-05 GREEN) |

## Threat Model Compliance

All four threats from the plan's `<threat_model>` block were respected:
- T-05-02-01 (Information Disclosure / 599 branch): SEC-03 regression test added (mitigated)
- T-05-02-02 (Tampering / new i18n strings): static byte-escape literals, no format-string injection (accepted as planned)
- T-05-02-03 (Tampering / ERR-01 fixture): static JSON file, no PII, no real keys (accepted as planned)
- T-05-02-04 (DoS-self / pending tests): MM.sleep stub in before_each — no real seconds consumed even if pending bodies executed (mitigated)

No new threat surface introduced beyond the plan's register.

## Commits

| Hash | Type | Description |
|------|------|-------------|
| `273330b` | feat | i18n.lua +2 keys × 2 locales; errors.lua 599 sentinel branch |
| `9a30df1` | test | errors_spec +3 cases; auth_spec ERR-01 round-trip |
| `2b673ef` | test | http_retry_spec + refresh_fail_whole_spec RED scaffolds |

All three GPG-signed by FDE07046A6178E89ADB57FD3DE300C53D8E18642. No AI attribution.

## Unblocks

- **Plan 05-03** — can implement M_http retry loop against passing GREEN scaffolds (8 pending tests in http_retry_spec become it()).
- **Plan 05-04** — can implement caller-layer 401→error.token_revoked translation in src/purchases.lua + src/finance.lua (i18n key already shipped).
- **Plan 05-05** — depends on 05-03 retry shipping; then turns 3 refresh_fail_whole_spec pending tests into it().

## Open Items

- None — plan executed as written (with documented deviations).
- Plan 05-03 will record its own reproducible SHA delta vs the Plan 05-02 baseline above.
