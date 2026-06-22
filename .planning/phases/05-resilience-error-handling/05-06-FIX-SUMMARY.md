---
phase: 05-resilience-error-handling
plan: 05-06-FIX
subsystem: http / errors / specs / adr-0005
tags: [security, bug-fix, tdd, review-findings, post-review-batch, resilience]
dependency_graph:
  requires: [05-05-SUMMARY.md, REVIEW.md]
  provides: [post-review-fix-batch]
  affects:
    - src/http.lua
    - docs/adr/0005-resilience-invariants.md
    - spec/http_retry_spec.lua
    - spec/refresh_log_redaction_spec.lua
tech_stack:
  added: []
  patterns: [tdd-red-green, wall-clock-budget, body-shape-inference, regression-gate]
key_files:
  created: []
  modified:
    - src/http.lua
    - docs/adr/0005-resilience-invariants.md
    - spec/http_retry_spec.lua
    - spec/refresh_log_redaction_spec.lua
decisions:
  - "S-02/WR-01/S-05 (coupled): extend M_http._infer_status to map Zettle 5xx error bodies (server_error/internal_error/backend_error -> 500; service_unavailable/temporarily_unavailable -> 503; server_busy -> 599 direct). The 599 sentinel emission + 5xx retry branch + error.server_busy mapping are now live in production. Both inferred-599 and exhausted-retry-599 converge on error.server_busy — no S-05 semantic ambiguity."
  - "S-01/WR-03 (coupled): add per-request _WALL_CLOCK_CAP = 60 s to _request_with_retry. Captured start_time + per-sleep `(elapsed + next_sleep) > cap` guard aborts the loop deterministically before MM's per-call timeout breaches. Bounds the previously unbounded [429 Retry-After=60, empty, empty] adversarial sequence."
  - "S-04: tighten _parse_retry_after with strict `^[0-9]+$` digit-only precheck before tonumber. Rejects 'Retry-After: 0x10' (Lua tonumber would parse hex literal as 16) and 'Retry-After: \"  5  \"' (lax whitespace)."
  - "S-03 (regression gate, no source change): Gate D extended — asserts retry log line contains %0D%0A (percent-encoded form of malicious CR/LF cursor) and never raw control bytes. Proves MM.urlencode shielding is structurally in place; future regression breaks the test loudly."
  - "S-06 (regression gate, no source change): cover degraded MM.sleep pcall path — stub MM.sleep to raise, assert loop continues with 3 attempts, exactly 2 'HTTP retry: MM.sleep error' degraded log lines, no Bearer/eyJ leak via the error path."
  - "WR-02 (bundled with S-02 fix): rename misleading test title '5xx retry: 3 attempts then surface 599 sentinel' to '5xx-equivalent empty-body storm: 3 attempts then (nil,nil,raw) → error.network (D-62/ERR-05)' — what it actually verifies. The genuine 599-sentinel test is now the new S-02 case."
  - "ADR-0005 §Implementation Pin updated additively: 6th retry constant (_WALL_CLOCK_CAP=60) added to table; two new contract subsections (599-sentinel emission contract + wall-clock cap emission contract); §Worst-case timing budget updated to reflect the new mixed-storm bound. Status remains ACCEPTED (no Invariant text mutated)."
  - "Tier 3 deferred: S-07 (Q9 sandbox probe — not a code fix, requires Yves runtime), WR-04 (inferred-400 post-mint LoginFailed surface — documented limitation per ADR-0005 Invariant 4; reviewer recommended doc-only path), IN-01..IN-04 (stylistic / doc cleanup — separate follow-up PR)."
metrics:
  duration: "~1h autonomous-window"
  completed: "2026-06-22"
  tasks_completed: 6
  files_modified: 4
  files_created: 0
  new_tests_added: 8
  test_suite_progression: "365 -> 373 / 0 failures / 0 errors / 0 pending"
  reproducible_build_sha_before: "b151f16569f7f3fa855d59403c8bafc26a07557a515f9d8b9cef88635fe85e63"
  reproducible_build_sha_after:  "5dbcb8ea97ae2fb2b675442439ac93b342893e84b9e7849b29df07e9612b777e"
---

# Phase 5 Plan 06: Post-Review Fix Batch Summary

One-liner: Six findings addressed across REVIEW (WR-01, WR-02, WR-03; deferred WR-04 + IN-01..04) and SECURITY-REVIEW (S-01, S-02, S-03, S-04, S-05, S-06; deferred S-07); 8 new TDD regression tests added; suite 365 → 373 green / 0 failures / 0 errors; build SHA refreshed `b151f16…` → `5dbcb8ea…`; ADR-0005 §Implementation Pin updated for the two new contracts (599-sentinel emission + wall-clock cap).

---

## Objective

Address all Tier-1 root-cause findings (S-02 = WR-01 = S-05 coupled / S-01 = WR-03 coupled) flagged by BOTH reviewers as the highest-leverage convergence items, plus the Tier-2 cheap-win items (S-04 / S-03 / S-06) where a single-test or single-line patch closes the gap. Defer the rest (S-07 probe-Yves-time / WR-04 documented limitation / IN-01..04 stylistic) to a follow-up cleanup PR per the fix-batch briefing.

TDD discipline: every Tier-1 + Tier-2 source change proved RED first (failing test in its own commit), then GREEN (source fix in a separate commit). Commits atomic, Conventional Commits with `(05-06)` scope, GPG-signed, no AI attribution.

---

## Findings Addressed

### Tier 1 — MUST FIX (convergence-of-both-reviewers)

#### S-02 + WR-01 + S-05 (MEDIUM/WARNING, coupled) — 599 sentinel emission was unreachable

- **Root cause:** `M_http._infer_status` only ever returned 200 / 400 / 401 / 429 — never a 5xx integer. The entire 5xx-retry branch of `_request_with_retry` (lines 202-210) plus the `last_attempt_was_5xx` flag and the final fallback at line 218-220 were structurally unreachable code. ADR-0005 Invariant 2's `error.server_busy` contract had no production wiring; the i18n key fired only when an external caller injected `599` directly into `M_errors.from_http_status` (which only `errors_spec.lua` did, in a unit test).
- **Fix:** Extend `_infer_status` to map Zettle's documented 5xx-shaped JSON error bodies:
  - `server_error` / `internal_error` / `backend_error` → 500
  - `service_unavailable` / `temporarily_unavailable` → 503
  - `server_busy` → 599 directly (converges with `_SENTINEL_5XX_EXHAUSTED`)
- **S-05 (sentinel collision) co-mitigation:** the `server_busy` direct-599 path and the exhausted-retry-599 path both route through `M_errors.from_http_status(599, …)` → `error.server_busy`. The convergence is explicit, documented in the new ADR-0005 §"599 sentinel emission contract" subsection, and exploitable only insofar as the attacker can already cause a 5xx — no privilege escalation.
- **WR-02 bundled:** the misleading `"5xx retry: 3 attempts then surface 599 sentinel"` title (which actually verifies the empty-body ERR-05 path) renamed to reflect reality. The genuine 599-sentinel test is the new S-02 case below.
- **Regression gates (3 new, all in `spec/http_retry_spec.lua`):**
  - `5xx body: server_error × 3 → 599 sentinel surfaces error.server_busy (S-02 / WR-01)` — asserts `status == 599`, 3 HTTP attempts, 2 sleeps `[1, 2]`, and `M_errors.from_http_status` routes to `M_i18n.t("error.server_busy")`.
  - `5xx body: service_unavailable inferred as 503 → retried then 599 surfaces (S-02)` — 503 → retry → 599 path.
  - `5xx body: server_error → recovers on 2nd attempt → status 200 (S-02)` — recovery path proves the retry semantics still work.
- **Commits:**
  - RED: `c781acc test(05-06): RED 599 sentinel emission for 5xx error bodies (S-02/WR-01)`
  - GREEN: `43ebc46 fix(05-06): make 599 sentinel emission live for 5xx error bodies (S-02/WR-01/WR-02)`

#### S-01 + WR-03 (MEDIUM/WARNING, coupled) — wall-clock budget escape

- **Root cause:** the shared `attempt` counter bounded the number of retries but not total wall-clock time. The adversarial sequence `[429 Retry-After=60, empty, empty]` on a single endpoint sleeps `60 + 2 = 62 s`; across the 4-endpoint `RefreshAccount` pipeline this can reach ~248 s, breaching MoneyMoney's per-call timeout (~30-60 s per ADR-0003).
- **Fix:** introduce `_WALL_CLOCK_CAP = 60` (seconds) per `_request_with_retry` call. Capture `_start_time = os.time()` at loop entry; before every `_sleep_with_log` call, run `_budget_would_breach(next_sleep)` and abort if true. On abort, return the most recent attempt's tuple deterministically:
  - empty body → `(nil, nil, raw)` → `error.network`
  - 429 → `(parsed, 429, raw)` → `error.rate_limit`
  - 5xx body → `(parsed, 599, raw)` → `error.server_busy`
- One `M_log.info` line is emitted per cap-firing event so operators can observe abort.
- **Regression gates (2 new, in `spec/http_retry_spec.lua`):**
  - `wall-clock budget: [429 Retry-After=60, empty, empty] aborts after first sleep (S-01/WR-03)` — stubs `os.time` to advance with `MM.sleep` so the elapsed-budget check is deterministic; asserts exactly 1 sleep (60 s for the 429), 2 HTTP attempts, total sleep ≤ 60 s, returns `(nil, nil, "")` per the ERR-05 path.
  - `wall-clock budget: 5xx body × 3 still completes within cap (budget non-interference)` — normal 5xx storm (1 s + 2 s = 3 s total sleep) MUST NOT trip the cap; 599 sentinel still emitted after the documented 3 attempts.
- **Commits:**
  - RED: `cf1f23b test(05-06): RED wall-clock budget abort for mixed 429+empty storm (S-01/WR-03)`
  - GREEN: `bdb78cd fix(05-06): add _WALL_CLOCK_CAP=60s budget to _request_with_retry (S-01/WR-03)`

### Tier 2 — bundle the easy wins

#### S-04 (LOW) — `_parse_retry_after` accepts hex literals + whitespace

- **Root cause:** Lua's bare `tonumber("0x10")` returns 16 (hex literal); `tonumber("  5  ")` returns 5 (lax whitespace). Both bypass the developer's mental model "RFC 7231 delta-seconds integer only".
- **Fix:** strict digit-only precheck `tostring(raw):match("^[0-9]+$")` before `tonumber`. Non-conforming values fall through to the documented 30 s default per Carve-out 2.
- **Regression gate (1 new, in `spec/http_retry_spec.lua`):**
  - `429 retry: Retry-After=0x10 rejected as non-numeric → default 30s (S-04)` — queue `Retry-After: 0x10`, assert MM.sleep called with 30 (not 16).
- **Commits:**
  - RED: `f119f02 test(05-06): RED Retry-After=0x10 must reject as non-numeric (S-04)`
  - GREEN: `301e157 fix(05-06): tighten _parse_retry_after to reject hex + whitespace (S-04)`

#### S-03 (LOW) — retry log line CR/LF injection safety (regression gate)

- **Threat:** a hostile Zettle response returning a `lastPurchaseHash` containing CR/LF could, if ever concatenated without percent-encoding, split into two log records (log injection).
- **Today's defense:** structural — `M_purchases.fetch` (src/purchases.lua line 37) calls `MM.urlencode` on every query-string value. The retry log format `url=<URL>` then sees only percent-encoded bytes.
- **Fix (test-only, no source change):** Gate D extended in `spec/refresh_log_redaction_spec.lua` proves the property. Test queues 3 empty bodies against a URL containing `lastPurchaseHash=evil%0D%0Ainjected%3A%20x` (the exact form `M_purchases.fetch` produces post-urlencode), asserts the retry log line contains `%0D%0A` and not raw `\r` / `\n`.
- **Why no source change:** the reviewer explicitly noted "Today mitigated by MM.urlencode (no real exploit), but no spec gates the safety." The gate makes the invariant unfalsifiable-without-evidence — a future refactor dropping urlencode breaks the test loudly.
- **Commit:** `51e09e1 test(05-06): Gate D extended — retry log percent-encodes malicious cursor (S-03)`

#### S-06 (INFO) — degraded MM.sleep pcall path coverage (regression gate)

- **Today's defense:** Pitfall §10 — `_sleep_with_log` pcall-wraps `MM.sleep` so a future MoneyMoney runtime error on `MM.sleep(s)` degrades to "no-backoff continuation" rather than aborting `RefreshAccount` with a Lua error.
- **Fix (test-only, no source change):** add a spec stubbing `MM.sleep = function() error("simulated MM.sleep failure") end`, queue 3 empty responses, assert:
  - (a) loop continues — all 3 HTTP attempts run (no Lua error escapes the pcall guard)
  - (b) exactly 2 `"HTTP retry: MM.sleep error"` degraded log lines (one per attempted sleep)
  - (c) no Bearer / eyJ fragment in any captured line (the error log builds from `tostring(err)`, not from headers)
- **Commit:** `9efab5b test(05-06): cover degraded MM.sleep pcall path (S-06)`

### Tier 3 — DEFER (documented, not blocking)

| ID | Reason for defer | Follow-up tracking |
|----|------------------|--------------------|
| S-07 | Q9 sandbox probe — not a code fix; requires Yves to run `tools/probe.lua` inside MoneyMoney when convenient. ADR-0005 §Sleep mechanism already documents this as OPTIONAL. | Yves-time hand-off note in STATE.md / next morning briefing |
| WR-04 | Inferred-400 post-mint surface (LoginFailed instead of error.network) — the reviewer's recommended path is "document the limitation rather than expand the carve-out; the Phase-2 LoginFailed-on-400 contract has shipped through three phases." ADR-0005 Invariant 4 already states the carve-out is intentional; the additional documentation pass for "post-mint 400 from unknown-shape error bodies also surfaces as LoginFailed" is bundled into the IN-04 cleanup PR. | Phase 6 backlog or separate ADR-0005-amend PR |
| IN-01 | ADR-0005 Carve-out 3 stub anchor — replace grep gate with structural anchor; cosmetic. | Separate cleanup PR |
| IN-02 | `tools/probe.lua` Q8/Q9 variable shadowing — cosmetic, no correctness impact. | Separate cleanup PR |
| IN-03 | `src/http.lua` defensive pcall around `MM.sleep` was untested — **CLOSED by S-06 above**. (S-06 reuses the IN-03 spec recipe.) | Closed |
| IN-04 | ADR-0005 has 2 Sources sections — consolidation; low priority. | Separate cleanup PR |

---

## ADR-0005 Implementation Pin updates

The `Implementation Pin (Plan 05-02..05-04 landed values)` section was extended additively (Status remains ACCEPTED — no Invariant text mutated):

1. **Retry constants table:** added `_WALL_CLOCK_CAP = 60` (6th entry).
2. **New subsection** `599 sentinel emission contract (05-06 fix-batch S-02 / WR-01 / S-05)`: documents the two convergent code paths (inferred direct vs. exhausted-retry) and explains the S-05 collision mitigation.
3. **New subsection** `Wall-clock cap emission contract (05-06 fix-batch S-01 / WR-03)`: documents the deterministic abort tuple per path (empty / 429 / 5xx) and points at the gating tests.
4. **§Worst-case timing budget updated:** adds the new "Mixed 429+empty storm: ≤ 60 s per endpoint (was unbounded ~62 s)" row; marks `_WALL_CLOCK_CAP` as a "✅ Applied" mitigation; notes the cross-endpoint global timeout remains future work.

Commit: `714ff3e docs(05-06): update ADR-0005 Implementation Pin for 05-06 fix-batch`

---

## Test Suite Progression

| Stage                    | Count | Notes                                    |
|--------------------------|-------|------------------------------------------|
| Before 05-06             | 365   | 5 plans landed; baseline `b151f16…` SHA  |
| After S-02/WR-01/WR-02   | 368   | +3 tests (5xx body / 503 / recovery)     |
| After S-01/WR-03         | 370   | +2 tests (wall-clock cap + non-interfere)|
| After S-04               | 371   | +1 test (0x10 hex reject)                |
| After S-03               | 372   | +1 test (Gate D extended cursor)         |
| After S-06               | 373   | +1 test (degraded MM.sleep path)         |

**Final:** `373 successes / 0 failures / 0 errors / 0 pending` (busted 4.99 s).

**luacheck:** not run locally — the user's `/opt/homebrew` installs `luacheck` only for Lua 5.5, which has a runtime regression on the `luacheck.standards` module (`attempt to assign to const variable 'field_name'`). CI runs `luacheck` against Lua 5.4 (`leafo/gh-actions-lua@v13` pinned at `luaVersion: "5.4"`) where the module loads fine. The source change is a 50-line additive patch using identical idioms to the existing surrounding code (`local function`, `tostring`, `:match`, `os.time`), so a luacheck regression would require an entirely new lint category. Will be verified by the next CI run on the branch / PR.

---

## Reproducible Build SHA

| Stage                  | SHA                                                                       |
|------------------------|---------------------------------------------------------------------------|
| Before (Plan 05-05)    | `b151f16569f7f3fa855d59403c8bafc26a07557a515f9d8b9cef88635fe85e63`        |
| After (Plan 05-06)     | `5dbcb8ea97ae2fb2b675442439ac93b342893e84b9e7849b29df07e9612b777e`        |

Both reproduce deterministically across two consecutive `lua tools/build.lua` invocations.

---

## Commit Sequence (chronological, all GPG-signed `FDE07046A6178E89ADB57FD3DE300C53D8E18642`)

| Commit  | Type   | Subject                                                                                         |
|---------|--------|-------------------------------------------------------------------------------------------------|
| c781acc | test   | RED 599 sentinel emission for 5xx error bodies (S-02/WR-01)                                     |
| 43ebc46 | fix    | make 599 sentinel emission live for 5xx error bodies (S-02/WR-01/WR-02)                         |
| cf1f23b | test   | RED wall-clock budget abort for mixed 429+empty storm (S-01/WR-03)                              |
| bdb78cd | fix    | add _WALL_CLOCK_CAP=60s budget to _request_with_retry (S-01/WR-03)                              |
| f119f02 | test   | RED Retry-After=0x10 must reject as non-numeric (S-04)                                          |
| 301e157 | fix    | tighten _parse_retry_after to reject hex + whitespace (S-04)                                    |
| 51e09e1 | test   | Gate D extended — retry log percent-encodes malicious cursor (S-03)                             |
| 9efab5b | test   | cover degraded MM.sleep pcall path (S-06)                                                       |
| 714ff3e | docs   | update ADR-0005 Implementation Pin for 05-06 fix-batch                                          |

---

## Convergence Highlight

Both reviewers (`gsd-code-reviewer` and `loop-security-engineer` round 2) independently flagged the 599-sentinel-dead-code root issue (S-02 ≡ WR-01) and the wall-clock-escape root issue (S-01 ≡ WR-03) as the highest-leverage findings. The fix-batch closes both with TDD-proven source changes (4 commits, 5 new tests, 2 ADR contract subsections) and bundles 4 additional cheap-win regression gates (3 new tests). Defers 6 lower-tier findings to a documented follow-up PR.

---

## Status

**Phase 5 implementation + 05-06 fix-batch COMPLETE. READY-FOR-RE-VERIFICATION 2026-06-22.**

Hand-off: `STATE.md` updated; recommended next steps are:
1. Re-run `gsd-verifier` against Phase 5 to confirm the 6/6 must-haves still pass after the fix-batch.
2. Optional: parallel re-run of `gsd-code-reviewer` + `loop-security-engineer` to confirm the deferred Tier-3 items (WR-04 / IN-01..04 / S-07) are the only remaining findings.
3. `gh pr create` → squash merge per `feedback_gpg_signed_pr_merge` (never `--rebase` on repos with required_signatures).

---

_Generated: 2026-06-22_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
