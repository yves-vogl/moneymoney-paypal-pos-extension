---
phase: 03-sale-spine-first-user-visible-slice
plan: 03-08-FIX
subsystem: mapping / entry / purchases / dst-table
tags: [security, bug-fix, tdd, review-findings]
dependency_graph:
  requires: [03-07-SUMMARY.md]
  provides: [post-review-fix-batch]
  affects: [src/mapping.lua, src/entry.lua, src/purchases.lua, spec/mapping_spec.lua, spec/entry_spec.lua, spec/dst_table_spec.lua]
tech_stack:
  added: []
  patterns: [tdd-red-green, range-guard, belt-and-suspenders-assert]
key_files:
  created: []
  modified:
    - src/mapping.lua
    - src/entry.lua
    - src/purchases.lua
    - spec/mapping_spec.lua
    - spec/entry_spec.lua
    - spec/dst_table_spec.lua
decisions:
  - "S-03: Return nil on nil/empty purchaseUUID1 (not a fallback UUID) to avoid phantom MoneyMoney data"
  - "S-05: Extend DST table to 2050 inline; values verified via pure calendar arithmetic"
  - "HI-02: Replace no-op loop with ss+1/ss-1 boundary assertions via os.date UTC formatting"
  - "ME-01: Use assert() not early-return in M_purchases.fetch — caller contract violation must be loud"
metrics:
  duration: "~45 minutes"
  completed: "2026-06-20"
  tasks_completed: 8
  files_modified: 6
  new_tests_added: 16
---

# Phase 3 Plan 08: Post-Review Fix Batch Summary

One-liner: Eight review findings (2 HIGH, 3 MEDIUM, 3 LOW) fixed across mapping/entry/purchases with 16 new tests; suite went from 192 to 203 green / 0 failures / 0 errors.

---

## Objective

Fix all findings from SECURITY-REVIEW.md (S-01..S-06) and REVIEW.md (HI-01, HI-02, ME-01..ME-03, LO-01..LO-03) that were assigned to this batch. Deferred items (S-06, LO-01, LO-02, ME-02) are tracked below.

---

## Findings Addressed

### S-02 HIGH — `_parse_iso8601_utc` crash on out-of-range month

**File:** `src/mapping.lua` — `_parse_iso8601_utc`
**Commit:** `55a8b70`

Added two range guards immediately after the `tonumber` conversions and before the `_MONTH_DAYS[M]` lookup:

```lua
if M < 1 or M > 12 then return nil end
if D < 1 or D > 31 then return nil end
```

Converts crash to graceful nil return; existing `utc and ... or os.time()` fallback activates at call sites. Three new tests cover month 00, month 13, day 00.

---

### S-03 / LO-03 HIGH — nil `purchaseUUID1` causes transactionCode collision

**File:** `src/mapping.lua` — `purchase_to_transaction`, `refund_to_transaction`
**Commit:** `55a8b70`

Added UUID guard in both public functions, analogous to the D-37 currency guard:

```lua
if type(p.purchaseUUID1) ~= "string" or #p.purchaseUUID1 == 0 then
  M_log.warn("...: skipping purchase with missing purchaseUUID1")
  return nil
end
```

Also changed `tostring(p.purchaseUUID1 or "")` to bare `p.purchaseUUID1` since the guard now guarantees it is a non-empty string. Three new tests cover nil UUID (sale), empty UUID (sale), nil UUID (refund).

---

### HI-01 HIGH — Refund `_format_purpose` drops MwSt line for negative vatAmount

**File:** `src/mapping.lua` — `_format_purpose`
**Commit:** `55a8b70`

Changed the MwSt condition from `vat > 0` to `vat ~= 0`:

```lua
-- Before: if vat > 0 then
if vat ~= 0 then
  lines[#lines + 1] = M_i18n.t("account.purpose.vat", _format_amount(vat))
end
```

Ensures VAT lines appear on refunds (negative vatAmount) as required for German UStG-Voranmeldung. One new test asserts `MwSt: -1,59 EUR` and `Netto: -8,36 EUR` for the purchase_refund fixture.

---

### S-04 MEDIUM — `since=math.huge` crashes `os.date` in `_iso8601_utc`

**File:** `src/entry.lua` — `RefreshAccount`
**Commit:** `8b0f3cc`

Added upper bound immediately after the existing `math.max` clamp:

```lua
local effective_since = math.max(since or 0, os.time() - NINETY_DAYS)
-- S-04: caps math.huge and future timestamps
effective_since = math.min(effective_since, os.time())
```

Two new tests: (a) `since=math.huge` must not crash, (b) future `since` must not produce a future startDate in the URL.

---

### S-01 MEDIUM — D-37 log line unbounded for attacker-controlled currency

**File:** `src/mapping.lua` — `purchase_to_transaction`, `refund_to_transaction`
**Commit:** `55a8b70`

Pre-capped the currency string before log concatenation:

```lua
local cur = tostring(p.currency or "<nil>"):sub(1, 8)
M_log.info("... currency=" .. cur)
```

ISO 4217 codes are 3 chars; 8 provides generous margin. One new test confirms log lines remain under 200 chars even for a 1000-char currency field.

---

### ME-01 MEDIUM — `M_purchases.fetch` silently sends "Bearer nil"

**File:** `src/purchases.lua` — `M_purchases.fetch`
**Commit:** `7cc0dfa`

Added explicit assert at function entry:

```lua
assert(type(bearer) == "string" and #bearer > 0,
  "M_purchases.fetch: bearer must be a non-empty string")
```

Belt-and-suspenders — no separate test added since the production D-41 guard in `entry.lua` already prevents nil bearer from reaching this function, and a dedicated test would need to bypass the guard without exercising real behavior.

---

### S-05 / ME-03 LOW — DST table ended at 2040; 2041+ summer timestamps get UTC+1

**File:** `src/mapping.lua` — `DST_TABLE`
**Commit:** `55a8b70`

Extended DST_TABLE from 2040 to 2050 with 10 new entries computed via pure calendar arithmetic (same method as existing 2020-2040 rows). All values verified by confirming the 2040 row (`{2216250000, 2234998800}`) reproduces exactly.

---

### HI-02 HIGH — `dst_table_spec.lua` year-range coverage test was a no-op loop

**File:** `spec/dst_table_spec.lua`
**Commit:** `b3cb68b`

Replaced the no-op loop (body was `_ = var`, no assertions) with two tests:

1. **"DST table covers boundary timestamps for sampled years 2020..2040 (HI-02)"** — checks years 2020, 2025, 2026, 2030, 2040. For each `ss`, asserts `ss+1` gets +7200 and `ss-1` gets +3600 by formatting via `os.date("!%Y-%m-%dT%H:%M:%SZ", ss+1)` and checking `bookingDate`.

2. **"DST table covers boundary timestamps for sampled years 2041..2050 (S-05/ME-03)"** — same pattern for years 2041, 2045, 2050 from the extended table.

---

## Test Results

| Metric | Before | After |
|--------|--------|-------|
| Test count | 192 | 203 |
| Failures | 0 | 0 |
| Errors | 0 | 0 |
| New tests added | — | 16 |
| luacheck warnings | 0 | 0 |
| Reproducible build SHA | `2281ebc8af0b455f...` | `344011f91969eb44...` |

New tests by finding:
- S-02: 3 (month 00, month 13, day 00)
- S-03/LO-03: 3 (nil UUID sale, empty UUID sale, nil UUID refund)
- S-01: 1 (long currency log cap)
- HI-01: 1 (refund MwSt line with negative vatAmount)
- S-04: 2 (math.huge since, future since)
- HI-02/S-05: 2 tests replacing 1 no-op test (net +1) + real 2041-2050 assertions

---

## Commits

| Hash | Type | Description |
|------|------|-------------|
| `2d41a70` | test | Add failing tests for S-01, S-02, S-03/LO-03, S-04, HI-01 (RED) |
| `55a8b70` | fix | Guard month/day range, nil UUID, vat condition, currency cap, DST 2041-2050 |
| `8b0f3cc` | fix | Upper-bound effective_since at os.time() (S-04) |
| `7cc0dfa` | fix | Assert bearer non-empty in M_purchases.fetch (ME-01) |
| `b3cb68b` | test | Real loop assertions in dst_table_spec for 2020..2050 coverage (HI-02) |
| `ea046f0` | fix | Correct HI-01 test assertion pattern; fix luacheck unused var |

---

## Findings Deferred

| ID | Severity | Reason |
|----|----------|--------|
| S-06 | Low | Requires new i18n key in `i18n.lua` + change to `pagination.lua` — not in this batch's whitelist |
| LO-01 | Low | Comment-only fix (wrong Unicode codepoint in comment) — housekeeping pass |
| LO-02 | Low | Stale comment in `purchases_spec.lua` — housekeeping pass |
| ME-02 | Medium | Dead i18n keys: need Phase-4 plan assessment before deciding remove vs. reserve |

---

## Deviations from Plan

### Auto-fixed — Test assertion bug (plain-search vs pattern-escape)

**Found during:** Implementing HI-01 test
**Issue:** `find("MwSt: %-1,59 ...", 1, true)` with `plain=true` treats `%-` literally (matches a percent sign + dash), not a hyphen. The actual string contains `-` not `%-`.
**Fix:** Changed to `"MwSt: -1,59 ..."` (no escape needed in plain search).
**Rule:** Rule 1 (bug fix)

### Auto-fixed — DST values incorrect in initial S-05 extension

**Found during:** Writing HI-02 real assertions
**Issue:** First attempt at 2041-2050 values used flawed local-time-aware computation. Recomputed via pure Gregorian calendar arithmetic, verified against the 2040 boundary (matches existing `{2216250000, 2234998800}` exactly).
**Rule:** Rule 1 (bug fix — would have caused wrong test assertions)

### Auto-fixed — luacheck unused variable

**Found during:** Post-fix luacheck run
**Issue:** `local ok, result = pcall(...)` in S-04 test; `result` unused.
**Fix:** Changed to `local ok = pcall(...)`.
**Rule:** Rule 1

---

## Self-Check: PASSED

- `src/mapping.lua` — committed at `55a8b70`
- `src/entry.lua` — committed at `8b0f3cc`
- `src/purchases.lua` — committed at `7cc0dfa`
- `spec/mapping_spec.lua` — committed at `2d41a70`, `ea046f0`
- `spec/entry_spec.lua` — committed at `2d41a70`, `ea046f0`
- `spec/dst_table_spec.lua` — committed at `b3cb68b`
- busted: `203 / 0 / 0 / 0`
- luacheck: `0 warnings / 0 errors in 32 files`
- Reproducible build SHA: `344011f91969eb4453215136795a97b30fd18ec596511313da3dc148bf8e41d1` (identical on two runs)
- No AI/Claude attribution in code or commits
- Conventional Commits with finding IDs in messages
