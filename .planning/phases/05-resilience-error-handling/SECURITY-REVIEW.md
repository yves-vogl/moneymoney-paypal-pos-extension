---
phase: 05-resilience-error-handling
reviewed: 2026-06-22T12:00:00Z
depth: deep
reviewer: Claude (loop-security-engineer round 2)
files_reviewed: 6
files_reviewed_list:
  - src/http.lua
  - src/pagination.lua
  - src/finance.lua
  - spec/http_retry_spec.lua
  - spec/refresh_log_redaction_spec.lua
  - docs/adr/0005-resilience-invariants.md
findings:
  high: 0
  medium: 0
  low: 0
  info: 1
  total: 1
round_2_findings:
  high: 0
  medium: 0
  low: 0
  info: 1
  total: 1
status: findings_present
---

# Phase 5 — Security Review

> **Round-1 SECURITY-REVIEW.md was not written to disk during the Phase-5 cycle.** The
> findings referenced in `05-06-FIX-SUMMARY.md` (S-01 MEDIUM, S-02 MEDIUM, S-03 LOW,
> S-04 LOW, S-05 INFO, S-06 INFO, S-07 deferred-probe) were captured only in the
> fix-batch narrative. This file documents round-2 verdicts against the FIX-SUMMARY's
> S-IDs and ports the round-1 closure evidence forward. The round-1 IDs and severity
> labels are preserved verbatim from `05-06-FIX-SUMMARY.md` to keep the audit trail
> contiguous.

---

## Round 2 (2026-06-22 re-review)

**Re-review verdict:** FINDINGS_PRESENT (1 round-2 INFO; no round-1 carryover beyond the documented S-07 deferral)
**Build SHA confirmed:** `5dbcb8ea97ae2fb2b675442439ac93b342893e84b9e7849b29df07e9612b777e` (reproducible — built locally; matches FIX-SUMMARY claim)
**Test suite:** 373 / 0 / 0 / 0 (was 365 before the fix-batch; +8 new tests per FIX-SUMMARY)

### Close-verification on the round-1 findings addressed by the fix-batch

- **S-02 + S-05 (coupled, 599 sentinel emission) — CLOSED via `43ebc46`**
  - File:line evidence — `src/http.lua:165-174` extends `_infer_status` to map Zettle 5xx-shaped error bodies:
    - `server_error` / `internal_error` / `backend_error` → 500
    - `service_unavailable` / `temporarily_unavailable` → 503
    - `server_busy` → 599 (direct convergence with `_SENTINEL_5XX_EXHAUSTED`)
  - The 5xx-retry branch at `src/http.lua:271-287` is now reachable; the 599 sentinel emission is live.
  - S-05 sentinel-collision mitigation verified: an upstream `{"error":"server_busy"}` body and a 3-attempt-exhausted `{"error":"server_error"}` storm both route through `M_errors.from_http_status(599, raw)` → `M_i18n.t("error.server_busy")`. Convergence is intentional and explicit; no privilege escalation, no semantic ambiguity. Documented in ADR-0005 §"599 sentinel emission contract" (`docs/adr/0005-resilience-invariants.md:233-258`).
  - Regression tests landed at `spec/http_retry_spec.lua:204-242` (3 cases: server_error storm, service_unavailable storm, recovery on 2nd attempt). All assert `status == 599` and `M_errors.from_http_status` → `error.server_busy`.

- **S-01 (wall-clock escape) — CLOSED via `bdb78cd`**
  - File:line evidence — `src/http.lua:37` declares `_WALL_CLOCK_CAP = 60`; `:210` captures `_start_time = os.time()`; `:215-217` defines `_budget_would_breach`. The guard fires before all three sleep call-sites:
    - Empty-body retry: `src/http.lua:229-236` aborts with `(nil, nil, raw)` → `error.network`.
    - 429 Retry-After: `src/http.lua:258-264` aborts with `(parsed, 429, raw)` → `error.rate_limit`.
    - 5xx body: `src/http.lua:275-281` aborts with `(parsed, 599, raw)` → `error.server_busy`.
  - Regression test at `spec/http_retry_spec.lua:255-302` exercises the exact adversarial sequence `[429 Retry-After=60, empty, empty]`:
    - Stubs `os.time` to advance with `MM.sleep` so the elapsed-budget check is deterministic.
    - Asserts exactly **1** MM.sleep call (60 s for the 429); the second sleep MUST NOT fire because `60 + 2 > 60`.
    - Asserts total sleep `<= 60 s` wall-clock cap.
    - Asserts exactly **2** HTTP attempts (3rd request never issued — cap aborts before attempt 3's sleep).
  - Budget-non-interference companion at `spec/http_retry_spec.lua:373-396` verifies a normal 5xx storm (1 s + 2 s = 3 s elapsed) does NOT trip the cap; 599 still emitted after the documented 3 attempts.

- **S-03 (log-injection via attacker-controlled cursor) — CLOSED via `51e09e1`** (regression gate, no source change)
  - Today's defence remains structural: `M_purchases.fetch` (src/purchases.lua) calls `MM.urlencode` on every query-string value before the URL ever reaches `_sleep_with_log`. Gate D extended in `spec/refresh_log_redaction_spec.lua:444-495` proves the property:
    - Asserts the retry log line contains percent-encoded `%0D%0A` (the encoded form of the malicious CR/LF cursor).
    - Asserts the line contains NO raw `\r` or `\n` bytes.
  - Future regression (e.g., a refactor that drops `MM.urlencode`) breaks the test loudly. Defensive framing: no exploit walkthrough; the test asserts the structural invariant.

- **S-04 (Retry-After hex/whitespace acceptance) — CLOSED via `301e157`**
  - File:line evidence — `src/http.lua:96-97` adds a strict digit-only precheck `tostring(raw):match("^[0-9]+$")` BEFORE `tonumber`. Lua's `tonumber("0x10")` would return 16; `tonumber("  5  ")` would return 5. Both now rejected, falling through to the documented 30 s default per Carve-out 2.
  - Regression test at `spec/http_retry_spec.lua:310-321` asserts `Retry-After: 0x10` produces `MM.sleep(30)` (default), not `MM.sleep(16)` (the hex interpretation).
  - The companion `n < 0` guard at `src/http.lua:100` plus the NaN guard remain intact.

- **S-06 (degraded MM.sleep pcall path coverage) — CLOSED via `9efab5b`** (regression gate, no source change)
  - The Pitfall §10 defence at `src/http.lua:119-126` pcall-wraps `MM.sleep`; previously untested because `mm_mocks.lua` never errors.
  - New spec at `spec/http_retry_spec.lua:334-371` stubs `_G.MM.sleep = function() error("simulated MM.sleep failure") end` and asserts:
    - (a) The loop continues — all 3 HTTP attempts run (no Lua error escapes the pcall guard).
    - (b) Exactly 2 `"HTTP retry: MM.sleep error"` degraded log lines (one per attempted sleep).
    - (c) Defence-in-depth: no `Bearer` literal and no `eyJ` JWT-shape fragment in any captured line. The degraded log line builds from `tostring(err)` (the pcall error string) — never from headers.

### Deferred from round 1 (per FIX-SUMMARY Tier 3) — confirmed still open, not regressed

- **S-07 (Q9 MM.sleep sandbox probe)** — Not a code fix; requires Yves to run `tools/probe.lua` inside MoneyMoney. ADR-0005 §"Sleep mechanism" already documents this as OPTIONAL confirmation. Status: AWAITING-YVES-RUNTIME. No security exposure (the pcall guard at `src/http.lua:119-126` provides defence-in-depth regardless of probe outcome).

### New-finding scan — round 2

Audited the +93 LoC fix-batch surface in `src/http.lua` plus the 6 new regression test cases for new security-relevant exposures:

1. **`_infer_status` 5xx body detection misfire on legitimate 200 responses with `"error"` keys** — `src/http.lua:155` (`if parsed.error then`) treats any truthy `error` field as an error response. **Pre-existing behaviour**, but the fix-batch *widens* the consequence: a 200 response with `error = "server_error"` now triggers a 3-attempt retry storm and `error.server_busy`. Real-world risk is LOW because Zettle Purchase/Finance success bodies do not use a top-level `error` field (per `05-RESEARCH.md`). **Not a security finding** — no data exfiltration, no auth bypass, no DOS — but worth flagging as a hardening item.
2. **`_WALL_CLOCK_CAP` boundary** — `_budget_would_breach` uses strict `>`, allowing `elapsed + next_sleep == 60` exactly. Correct semantics for "≤ cap" guarantee; not a hole.
3. **`os.time()` clock manipulation** — `_start_time = os.time()` and the budget check use real-clock seconds. A clock skew (system clock jump backwards mid-loop) could push `elapsed` negative, defeating the cap. Lua's `os.time()` returns an integer; system clock changes are extremely rare in a MoneyMoney session lifetime (`RefreshAccount` runs in tens of seconds). **Theoretical only, not exploitable** — the adversary would need to compromise the user's system clock, which is out of scope for an extension-level threat model.
4. **`MM.sleep(0)` on `Retry-After: 0`** — `_parse_retry_after` rejects `n < 0` but allows `n == 0`. A `Retry-After: 0` produces `MM.sleep(0)` + a `_sleep_with_log` line with `after_ms=0`. RFC 7231 §7.1.3 allows this; behaviour is technically correct. Pre-existing; not introduced by the fix-batch. **Not a security finding** but logged as a round-2 cosmetic INFO (see S-08 below).
5. **SEC-03 redaction regression** — Gate D + Gate D extended + S-06 cover all three new log surfaces (`_sleep_with_log` line, `MM.sleep error` line, `wall-clock cap reached` line). No Bearer / no eyJ / no raw CR-LF in any captured line. No regression.
6. **Pagination 401-direct-check non-interference** — The new 500/503/599 statuses cleanly bypass the `status == 401` chokepoints at `src/pagination.lua:65` and `src/finance.lua:152` and route through `M_errors.from_http_status`. No path collision; no LoginFailed mis-trigger on 5xx.

### Round-2 finding (new)

#### S-08 (INFO, TRIVIAL): `_parse_retry_after` accepts `Retry-After: 0`

**File:** `src/http.lua:100`
**Issue:** The S-04 tightening rejected hex literals and whitespace but kept the existing `n < 0` guard (strict less-than). `Retry-After: 0` from Zettle therefore produces `MM.sleep(0)` and a degenerate INFO log line with `after_ms=0`. RFC 7231 §7.1.3 permits 0 (meaning "retry immediately"), so behaviour is technically conformant — but the no-op sleep on a 429 is semantically suspect (the server asked us to retry; we did, instantly, which is not what a polite client should do).
**Severity:** INFO (TRIVIAL). No exploit, no auth/secret exposure, no DOS amplification (the wall-clock cap still bounds total time at 60 s).
**Fix (optional):** Change the guard to `n <= 0` to fall through to the documented 30 s default per Carve-out 2. One-character source change.
**Status:** Defer to the IN-cleanup PR; not blocking.

### Pay/Compliance status (per `feedback-pay-compliance-explicit-status`)

- **D-49** (Phase 4 inherited — Finance balance dual-GET surface): STILL-OK. Untouched by fix-batch; surface-preservation specs green.
- **D-55** (Phase 4 inherited — fee/payout emitter prefix contract): STILL-OK. Untouched by fix-batch; D-38 5-prefix closed-set gate green.
- **D-64 collapse** (`error.token_revoked` vs `LoginFailed`, Plan 05-04): STILL-OK. The 401-direct-check is the only path that intercepts pre-`from_http_status`; the new 500/503/599 statuses route through the normal dispatch to `error.server_busy`. Verified by reading `src/pagination.lua:50-69` and `src/finance.lua:140-160`.
- **D-67 sleep mechanism**: NOW TIMING-BUDGET-BOUNDED. `MM.sleep` primitive unchanged; pcall guard unchanged; the new `_WALL_CLOCK_CAP = 60` enforces the previously-unbounded total-wait invariant promised by ADR-0005. ADR-0005 §"Worst-case timing budget" updated to mark this as ✅ Applied (`docs/adr/0005-resilience-invariants.md:417`).

### Round-2 Verdict

**FINDINGS_PRESENT** — 1 new INFO (S-08, trivial). All round-1 MEDIUM / LOW / INFO items addressed by the fix-batch confirm CLOSED with file:line evidence and regression-test gates. S-07 remains deferred-awaiting-Yves-runtime per FIX-SUMMARY (no security exposure; pcall defence-in-depth in place).

No new MEDIUM or HIGH security findings. No regression in SEC-03 Bearer redaction. No regression in Phase-4 surface preservation. The new wall-clock cap is correctly bounded and tested. The new 599 sentinel emission contract converges on a single user-facing string (S-05 mitigation explicit and tested).

**Phase 5 is security-clear for ship pending the cosmetic S-08 + IN-cleanup PR.**

_Re-reviewed: 2026-06-22_
_Reviewer: Claude (loop-security-engineer round 2)_
_Depth: deep_
_Scope: Phase-5 changeset 74f644c..6b0e41e (HEAD)_
