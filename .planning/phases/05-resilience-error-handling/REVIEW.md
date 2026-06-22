---
phase: 05-resilience-error-handling
reviewed: 2026-06-22T00:00:00Z
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
status: issues_found
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
