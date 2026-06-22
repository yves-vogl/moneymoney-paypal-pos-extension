---
phase: 05-resilience-error-handling
reviewed: 2026-06-22T00:00:00Z
re_reviewed: 2026-06-22T12:00:00Z
depth: deep
files_reviewed: 19
files_reviewed_list:
  - docs/adr/0005-resilience-invariants.md
  - spec/auth_spec.lua
  - spec/entry_spec.lua
  - spec/errors_spec.lua
  - spec/finance_account_state_spec.lua
  - spec/finance_spec.lua
  - spec/http_retry_spec.lua
  - spec/http_spec.lua
  - spec/phase3_surface_preservation_spec.lua
  - spec/refresh_fail_whole_spec.lua
  - spec/refresh_idempotency_spec.lua
  - spec/refresh_log_redaction_spec.lua
  - src/errors.lua
  - src/finance.lua
  - src/http.lua
  - src/i18n.lua
  - src/pagination.lua
  - src/purchases.lua
  - tools/probe.lua
findings:
  blocker: 0
  warning: 4
  info: 4
  total: 8
round_2_findings:
  blocker: 0
  warning: 0
  info: 1
  total: 1
status: findings_present
---

# Phase 5: Code Review Report

**Reviewed:** 2026-06-22
**Depth:** deep
**Files Reviewed:** 19
**Status:** issues_found
**Build SHA:** `b151f16569f7f3fa855d59403c8bafc26a07557a515f9d8b9cef88635fe85e63` (reproduces deterministically across two builds — confirmed)
**Test suite:** 365 / 0 / 0 / 0 (pass/fail/error/pending)

## Summary

Phase 5 lands the resilience layer correctly at the structural level: ERR-01 / 04 / 05 / 06 are properly gated by tests, the retry loop is iterative (not recursive — Pitfall §2 honoured), Bearer redaction extends to the new INFO retry log lines (Gate D), and the build artefact is reproducible at the documented SHA. The 401-direct-check is correctly placed at the iterator chokepoint plus the two non-paginated `fetch_account_state` legs; abort-on-first-401 is enforced and tested.

The findings below cluster around one substantive correctness gap and three documentation / spec-tightness issues:

- The **599 sentinel cannot fire in production** because `M_http._infer_status` never returns a status in [500, 598]. The entire 5xx-retry branch of `_request_with_retry` (lines 202-210) plus the `last_attempt_was_5xx` flag are unreachable code. The 599-equivalent path real Zettle outages actually traverse is the empty-body branch, which routes to `error.network`, not `error.server_busy`. ADR-0005 Invariant 2 and the `error.server_busy` i18n key therefore have NO integration coverage.
- The `5xx retry: 3 attempts then surface 599 sentinel` test in `http_retry_spec.lua` (line 72) has a **misleading title** — it asserts `is_nil(status)` and the inline comment admits "(NOT 599)". The test would still pass even if the 599 emission code were deleted.
- Several quality / doc items: shared retry budget across 429+empty-body is undocumented; ADR-0005 Carve-out 3 is a self-described "anchor stub" rather than substantive content; the post-mint inferred-400 path is not explicitly carved out alongside the 401 path.

Build SHA `b151f16...` matches the expected value; running `lua tools/build.lua` twice yields byte-identical output. No regressions in the 365-test suite. The retry log format string is structurally Bearer-safe (Gate D verified).

## Warnings

### WR-01: 599 sentinel emission path is unreachable; ADR-0005 Invariant 2 over-promises

**File:** `src/http.lua:200-210`, `src/http.lua:123-137`
**Issue:** `_request_with_retry` contains a `status >= 500 and status <= 599` branch that returns the `_SENTINEL_5XX_EXHAUSTED` (599) on retry-exhaustion. However, `M_http._infer_status` only ever returns 200 / 400 / 401 / 429 (lines 123-137 of `src/http.lua`):

```lua
function M_http._infer_status(parsed)
  if parsed.error then
    if parsed.error == "invalid_grant" or parsed.error == "invalid_request" then
      return 400
    end
    if parsed.error == "invalid_client" or parsed.error == "unauthorized_client" then
      return 401
    end
    if parsed.error == "rate_limit" then
      return 429
    end
    return 400  -- conservative: unknown -> 400 (Pitfall 5)
  end
  return 200
end
```

There is no body shape that maps to 5xx. Real Zettle 5xx responses that arrive with a JSON envelope (`{"error":"server_error"}`, `{"error":"internal_error"}`, etc.) are silently mis-classified as 400 by the conservative fallback at line 134, and 5xx-without-body responses fall through the empty-body branch (line 171) which never emits the 599 sentinel. **Net effect:** the entire 5xx-retry branch (lines 202-210) plus the `last_attempt_was_5xx` flag and the final fallback at line 218-220 are unreachable; the `error.server_busy` German string can only be triggered if some external caller passes `599` directly into `M_errors.from_http_status` (which only `errors_spec.lua` does, in a unit test).

ADR-0005 Invariant 2 documents the 599 path as live; the corresponding integration test (`spec/http_retry_spec.lua:72-86`) is the misleading test from WR-02. The shipped artefact is correct under the empty-body model but the architecture overshoots the actual `_infer_status` contract.

**Fix:** Two acceptable paths — pick one:

1. **Remove the dead branch** and document that 5xx-with-body silently degrades to the unknown-error→400 path. Reduces source by ~15 lines and removes the 599 i18n key.

2. **Make the branch live** by extending `_infer_status` to map known 5xx-shaped error strings (`server_error`, `temporarily_unavailable`, `internal_error`, etc.) to 5xx integers. Add an integration test in `spec/http_retry_spec.lua` that queues `{"error":"server_error"}` × 3 and asserts `status == 599` and `M_errors.from_http_status(status, raw) == M_i18n.t("error.server_busy")`.

Recommend (2) — the ADR has already shipped the contract; the implementation should match.

### WR-02: `http_retry_spec.lua:72` test title claims to verify 599 sentinel but actually verifies the empty-body path

**File:** `spec/http_retry_spec.lua:72-86`
**Issue:** The test `it("5xx retry: 3 attempts then surface 599 sentinel (D-62 / ADR-0005 Invariant 2)", function() ...)` queues three empty-body responses and asserts `assert.is_nil(status)`. The inline comment (lines 73-76) acknowledges:

> Empty body × 3 → Phase-2 ERR-05 path: returns (nil, nil, "") (NOT 599).
> The 599 sentinel is for non-empty body-shape 5xx (covered separately when
> _infer_status grows a 5xx body branch; for now empty-body is the only
> 5xx-equivalent we recognise per RESEARCH §4.b heuristic).

The test would still pass if the entire 5xx branch in `_request_with_retry` were deleted. Adversarial readers will assume the test guards the 599 path; it does not.

**Fix:** Either rename the test to reflect what it actually verifies (`5xx-equivalent empty-body storm exhausts to (nil,nil,raw) → error.network`) and add a separate `pending()` for the genuine 599 path, or — if WR-01 is fixed by extending `_infer_status` — replace the body with a fixture that triggers `_infer_status >= 500` and assert `status == 599`.

### WR-03: Retry budget is shared across empty-body and 429 without being documented

**File:** `src/http.lua:161-216`
**Issue:** The loop uses a single `attempt` counter for both the 5xx/empty-body retry budget (3 attempts) and the 429 single-retry budget. If an empty-body response on attempt 1 triggers a sleep + continue, then a 429 arrives on attempt 2, the code takes the `else` branch (`attempt != 1`) and returns 429 **without honoring Retry-After** — the 429 single-retry budget was already consumed by the empty-body retry. This deviates from Plan 05-03 D-63's "single retry honoring Retry-After" wording (which implies the 429 retry is independent of other retry budgets).

Behaviour is defensible (bounds total wait time) but undocumented. ADR-0005 Invariant 3 says nothing about budget sharing.

**Fix:** Either (a) add a separate `_429_attempts` counter so the 429 retry is independent, or (b) add a sentence to ADR-0005 Invariant 3: "The 429 single-retry budget is shared with the 5xx/empty-body retry budget. A 429 on the second attempt or later is returned without honoring Retry-After, even if the prior retries were not 429-triggered." Recommend (b) since (a) widens worst-case timing.

### WR-04: Inferred-400 from unknown error fields silently maps to LoginFailed post-mint

**File:** `src/http.lua:134`, `src/errors.lua:36-38`, `src/pagination.lua:65`
**Issue:** `_infer_status` returns 400 for any unknown error field (`parsed.error == "some_new_error"` → 400 — line 134 "conservative"). Post-mint, this 400 is NOT intercepted by the iterator-layer 401-direct-check (which only fires for `status == 401`), so it flows through `M_errors.from_http_status(400, ...)` → `LoginFailed` (D-24 case 3). This means a Zettle outage that returns an unexpected JSON error shape after a successful mint will cause MoneyMoney to **prompt the user for a new API key** when the cached key is in fact still valid.

ADR-0005 Invariant 4 carves out only the 401 case. The behaviour for inferred-400 post-mint is consistent with the Phase-2 contract but contradicts the spirit of ERR-04 ("the credentials are not bad — something else broke").

**Fix:** Either extend the iterator-layer chokepoint to translate inferred-400 post-mint to `error.network` (preserves the user's API key) or document explicitly in ADR-0005 Invariant 4 that "post-mint 400 (from unknown-shape error bodies, per `_infer_status` conservative default at `src/http.lua:134`) WILL still surface as `LoginFailed`, even though the cached bearer is still valid — this is a known Phase-5 limitation; consider tightening in Phase 6 once we have data on real-world unknown-error frequency." Recommend documenting the limitation rather than expanding the carve-out; the Phase-2 LoginFailed-on-400 contract has shipped through three phases.

## Info

### IN-01: ADR-0005 "Carve-out 3" is a self-described stub anchor for `grep`

**File:** `docs/adr/0005-resilience-invariants.md:303-312`
**Issue:** Carve-out 3 exists only to provide a deterministic `grep -c "Carve-out 3"` target for Plan 05-05's acceptance criteria:

> This stub exists so the gating grep (`grep -c 'Carve-out 3'`) in Plan 05-05's
> acceptance criteria has a deterministic target without duplicating the carve-out prose.

This is a brittle pattern: future ADR readers see "Carve-out 3" in the TOC and expect substantive content. Using markdown comments as CI grep anchors couples the document structure to the workflow tooling.

**Fix:** Replace the grep gate with one that checks for a structural anchor (e.g., `grep -q "## Carve-outs" docs/adr/0005-resilience-invariants.md`) and delete the stub. Or, if the gate must count carve-outs by number, rename Carve-out 3 to "(reserved)" and put the rationale in a separate sentence.

### IN-02: `tools/probe.lua` Q9 reuses `ok, err` variable names from Q8 (shadowing)

**File:** `tools/probe.lua:97`, `tools/probe.lua:117`
**Issue:** Both Q8 (line 97) and Q9 (line 117) declare `local ok, err = pcall(...)` inside the same `RefreshAccount` function. Q9's binding shadows Q8's. No correctness impact (each `ok/err` is consumed locally before the next is declared), but a future reader may misread the scoping.

**Fix:** Rename Q9's locals to `ok9, err9` for clarity, or wrap each Q block in a `do ... end` to make the scoping explicit.

### IN-03: `src/http.lua:99` defensive `pcall` around `MM.sleep` is silently no-op on success

**File:** `src/http.lua:100-108`
**Issue:** The Pitfall §10 defence pcall-wraps `MM.sleep` so a runtime error degrades to no-backoff rather than aborting `RefreshAccount`. The fallback log line `"HTTP retry: MM.sleep error (degraded; continuing): ..."` only fires on `pcall` failure. There is no test exercising the degraded path — `mm_mocks.lua` injects a no-op `MM.sleep` that never errors. If a future MM update changes `MM.sleep` semantics, the degraded path is uncovered.

**Fix:** Add a small spec that stubs `_G.MM.sleep = function() error("boom") end` before invoking a retry-bearing path and asserts (a) `RefreshAccount` still returns normally (no Lua error escapes), (b) one `"MM.sleep error"` line is captured in `Mocks._captured_prints`.

### IN-04: ADR-0005 has 2 sources sections / inconsistent reference style

**File:** `docs/adr/0005-resilience-invariants.md:421-438`
**Issue:** The "Sources" section at line 421 duplicates references already cited in the body ("References:" section at line 43-56). The two lists are not identical (the body cites ADR-0003 / 0004 by short name; the Sources section spells out URLs for the WebBanking API and RFC 7231 but omits ADR-0003 / 0004). A reader looking for "what should I read next" has two starting points.

**Fix:** Merge into a single "Sources" section at the bottom (the conventional MADR placement); delete the duplicate "References:" block at line 43-56. Low priority.

---

## Structural Findings (fallow)

No structural pre-pass was provided in the prompt. Cross-module references verified by reading `src/entry.lua`, `src/http.lua`, `src/errors.lua`, `src/pagination.lua`, `src/purchases.lua`, `src/finance.lua` end-to-end. No circular dependencies, no unused exports, no duplicate blocks observed across the Phase-5 diff. The Plan 05-04 401-direct-check call-site table in ADR-0005 (line 237-243) reconciles with the actual code: 4 call sites total (2 in `src/pagination.lua`, 2 in `src/finance.lua`), confirmed by `grep -n "status == 401" src/`.

---

_Reviewed: 2026-06-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_

---

## Round 2 (2026-06-22 re-review)

**Re-review verdict:** FINDINGS_PRESENT (1 INFO carryover, no new blockers)
**Build SHA confirmed:** `5dbcb8ea97ae2fb2b675442439ac93b342893e84b9e7849b29df07e9612b777e` (reproducible — built once locally, matches `05-06-FIX-SUMMARY.md` claim).
**Test suite:** 373 / 0 / 0 / 0 (was 365 before the fix-batch; +8 new tests as claimed).
**Commits audited (fix-batch):** 9 SHAs from FIX-SUMMARY all present in `git log` between `74f644c` and `HEAD = 6b0e41e`:

| Claimed SHA | Subject prefix                                                  | Verified |
|-------------|-----------------------------------------------------------------|----------|
| c781acc     | test(05-06) RED 599 sentinel emission for 5xx error bodies      | ✅        |
| 43ebc46     | fix(05-06) make 599 sentinel emission live for 5xx error bodies | ✅        |
| cf1f23b     | test(05-06) RED wall-clock budget abort                         | ✅        |
| bdb78cd     | fix(05-06) add _WALL_CLOCK_CAP=60s budget                       | ✅        |
| f119f02     | test(05-06) RED Retry-After=0x10 must reject                    | ✅        |
| 301e157     | fix(05-06) tighten _parse_retry_after                           | ✅        |
| 51e09e1     | test(05-06) Gate D extended (S-03)                              | ✅        |
| 9efab5b     | test(05-06) cover degraded MM.sleep pcall path                  | ✅        |
| 714ff3e     | docs(05-06) update ADR-0005 Implementation Pin                  | ✅        |

### Close-verification on Round-1 findings

- **WR-01 — CLOSED via `43ebc46`** (file:line evidence: `src/http.lua:165-174` adds the 5xx body→500/503/599 branches in `_infer_status`; `_request_with_retry` at `src/http.lua:271-287` reaches the 599-emission branch on real 5xx bodies). The unreachable-dead-code condition is resolved. Confirmed live by `spec/http_retry_spec.lua:204-221` (`server_error × 3 → 599`), `:223-232` (`service_unavailable → 503 → 599`), `:234-242` (5xx recovery on attempt 2).
- **WR-02 — CLOSED via `43ebc46`** (renamed `spec/http_retry_spec.lua:72` to `"5xx-equivalent empty-body storm: 3 attempts then (nil,nil,raw) → error.network (D-62 / ERR-05)"` — title now matches what the assertions actually verify). Genuine 599-sentinel coverage is the new test at `:204-221`.
- **WR-03 — CLOSED via `bdb78cd`** (file:line evidence: `src/http.lua:37` declares `_WALL_CLOCK_CAP = 60`; `:210` captures `_start_time = os.time()`; `:215-217` defines `_budget_would_breach`; the guard fires before all three sleep call-sites: `:229-236` (empty-body), `:258-264` (429 Retry-After), `:275-281` (5xx body)). Regression test at `spec/http_retry_spec.lua:255-302` asserts the adversarial `[429 Retry-After=60, empty, empty]` sequence produces exactly 1 sleep (60 s for the 429), exactly 2 HTTP attempts, and total sleep ≤ 60 s. Budget-non-interference companion at `:373-396` proves a normal 5xx storm still emits the 599 sentinel.

### Deferred findings (per FIX-SUMMARY Tier 3 — confirmed still open, not regressed)

- **WR-04** — Inferred-400 post-mint LoginFailed surface — DEFERRED-DOCUMENTED. No source change. Note: the **same class of issue** now exists for any new Zettle 5xx-shape that is NOT in the whitelist (`server_error`/`internal_error`/`backend_error`/`service_unavailable`/`temporarily_unavailable`/`server_busy`): an unknown 5xx-shaped error name falls into the `return 400` conservative branch at `src/http.lua:175` and still surfaces as LoginFailed. Same shipped-contract argument applies; flagged here for ADR-0005 footnote in the cleanup PR.
- **IN-01 / IN-02 / IN-04** — Cosmetic, still open per FIX-SUMMARY Tier 3.
- **IN-03** — **CLOSED** by S-06 (`spec/http_retry_spec.lua:334-371` covers the degraded MM.sleep pcall path; the prior INFO finding is now structurally gated).

### New-finding scan on the +93 LoC + 6 new test cases

Audited the fix-batch surface for regressions and edge cases the prompt asked about:

1. **`_infer_status` 5xx body detection misfiring on legitimate 200 responses with `"error"` keys** — `src/http.lua:155` (`if parsed.error then`) treats ANY truthy `error` field as an error response. **Pre-existing behaviour** (Phase-5 base; not introduced by the fix-batch). The fix-batch *widens the surface*: where a stray `error="server_error"` field on an otherwise-200 response would previously have been mis-classified as 400, it is now mis-classified as 500 and triggers a 3-attempt retry storm + 599 sentinel + `error.server_busy`. **Real-world likelihood is low** — Zettle's Purchase/Finance API success bodies use `purchases[]` / `data[]` / scalar fields, not a top-level `error` key (per `05-RESEARCH.md` §"Purchase JSON top-level fields"). **Severity: INFO** — pre-existing structural sharp-edge; documenting as carryover, not introduced by the fix-batch.
2. **`os.time()` mocked to return 0** — `_start_time = os.time()` captures the mock value (0); `_budget_would_breach(s)` becomes `(0 - 0) + s > 60` → fires only when `s > 60`. With normal sleeps {1,2,4} and `Retry-After ≤ _RETRY_AFTER_CAP (60)`, no spurious abort. **No bug.** The 05-06 wall-clock test stubs `os.time` deterministically (`spec/http_retry_spec.lua:267, 383`) and the assertions hold.
3. **`sleep_seconds == 0`** — `_parse_retry_after` rejects `n < 0` only (not `n == 0`). A response of `Retry-After: 0` produces `MM.sleep(0)` and a `_sleep_with_log` line with `after_ms=0`. RFC 7231 §7.1.3 allows this; behaviour is harmless but logs a degenerate retry. **Pre-existing**, not introduced by the fix-batch. **Severity: TRIVIAL** — left noted, no source change recommended.
4. **`_WALL_CLOCK_CAP` boundary edge case** — `_budget_would_breach` uses strict `>` so `elapsed + next_sleep == cap` (exactly 60 s total) is *allowed*. Worst case: 60 s sleep + 1 s sleep = 61 s ≯ 60 → guard fires on the second sleep. Correct boundary semantics for "≤ cap" guarantee. **No bug.**
5. **SEC-03 redaction regression scan** — Gate D and Gate D extended (`spec/refresh_log_redaction_spec.lua:444-495` and `:497-584`) confirm: the new `_sleep_with_log` lines never carry Bearer, eyJ, or raw CR/LF. The new `"HTTP retry: MM.sleep error"` log line at `src/http.lua:125` builds from `tostring(err)`, which is the pcall error string from `MM.sleep`, not from headers — explicitly asserted by S-06 (`spec/http_retry_spec.lua:362-370`). The new `"HTTP retry: wall-clock cap reached"` log lines at `src/http.lua:233, 261, 278` interpolate only the integer cap + URL (URL is already MM.urlencode-shielded by `M_purchases.fetch` per S-03 gate). **No regression.**
6. **Phase-4 surface preservation regression scan** — Plan 05-05 surface-preservation tests at `spec/phase3_surface_preservation_spec.lua` cover the new 401 chokepoint, fee/payout emitter prefixes, and balance dual-GET. The fix-batch added nothing that touches `RefreshAccount`'s response shape — only the internal retry-loop semantics changed. Suite passes 373/0/0/0; no surface-shape spec broke.

### Pay/Compliance status (per `feedback-pay-compliance-explicit-status`)

- **D-49** (Phase 4 inherited — Finance balance dual-GET): STILL-OK. Untouched by fix-batch; surface-preservation specs green.
- **D-55** (Phase 4 inherited — fee/payout emitter contract): STILL-OK. Untouched by fix-batch; D-38 5-prefix closed-set gate green.
- **D-64 collapse** (`error.token_revoked` vs `LoginFailed` per Plan 05-04): STILL-OK. The 401-direct-check at `src/pagination.lua:65` and `src/finance.lua:152` is the only path; the fix-batch's new 500/503/599 statuses cleanly fall through to `M_errors.from_http_status` and route to `error.server_busy` (NOT `LoginFailed`). Verified by reading the pagination flow — no path collision.
- **D-67 sleep mechanism**: NOW TIMING-BUDGET-BOUNDED. The sleep primitive is unchanged (`MM.sleep` via `_sleep_with_log` pcall guard), but the bounded-time invariant promised by ADR-0005 is finally enforced via `_WALL_CLOCK_CAP`. ADR-0005 §Implementation Pin documents the contract; the ADR's "Worst-case timing budget" table is updated to mark `_WALL_CLOCK_CAP` as ✅ Applied.

### Round-2 INFO finding (new)

#### IN-05: `_parse_retry_after` accepts `Retry-After: 0`; produces a no-op `MM.sleep(0)` + degenerate INFO log line

**File:** `src/http.lua:100`
**Issue:** The S-04 tightening rejects non-integer / hex / whitespace / negative values but allows `n == 0` (the existing `n < 0` guard is strictly less-than). A `Retry-After: 0` from Zettle produces `_sleep_with_log(0, url, attempt, 429)` → `MM.sleep(0)` + an INFO log line with `after_ms=0`. RFC 7231 §7.1.3 permits this value (meaning "retry now"), so behaviour is technically correct, but the degenerate log line is noisy and the no-op sleep on a 429 is semantically suspect (the server explicitly asked us to retry — we did, instantly).
**Severity:** INFO (TRIVIAL). Pre-existing; not introduced by the fix-batch. No exploit, no data corruption.
**Fix (optional):** Tighten the guard to `n <= 0` to fall through to the documented 30 s default per Carve-out 2 — matches the developer's mental model "a bounded honoring window, not instant retry". Single-character change. Defer to the IN-cleanup PR.

### Round-2 Verdict

**FINDINGS_PRESENT** — 1 new INFO (IN-05); all 4 WARNING items from round 1 are confirmed closed (WR-01 + WR-02 + WR-03 via the fix-batch; WR-04 documented-deferred per round-1's own recommendation). Of the 4 round-1 INFO items, IN-03 is closed by S-06; IN-01, IN-02, IN-04, and the new IN-05 remain for the cleanup PR.

No blocker, no warning, no regression — phase is ship-ready pending the cosmetic cleanup PR.

_Re-reviewed: 2026-06-22_
_Reviewer: Claude (gsd-code-reviewer round 2)_
_Depth: deep_
