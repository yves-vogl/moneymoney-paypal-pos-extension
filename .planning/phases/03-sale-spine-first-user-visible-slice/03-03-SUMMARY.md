---
phase: 03-sale-spine-first-user-visible-slice
plan: "03"
subsystem: mapping
tags: [wave-2, mapping, pure-logic, dst, i18n, mvp, sale-spine]
dependency_graph:
  requires: [03-01, 03-02]
  provides: [M_mapping.purchase_to_transaction, M_mapping.refund_to_transaction]
  affects: [03-04, 03-05, 03-06]
tech_stack:
  added:
    - "Pure-Lua calendar arithmetic for TZ-independent ISO-8601 UTC parsing"
    - "Inline 21-row EU DST table (2020-2040) in src/mapping.lua"
  patterns:
    - "Private helper scoping: local function inside do...end block (auth.lua pattern)"
    - "German amount formatting via string.format + gsub decimal separator"
    - "Priority-dispatch brand mapping (errors.lua dispatch pattern)"
key_files:
  created: []
  modified:
    - src/mapping.lua
    - src/i18n.lua
    - spec/mapping_spec.lua
    - spec/dst_table_spec.lua
    - spec/i18n_spec.lua
decisions:
  - "TZ-independent ISO-8601 parse: pure calendar arithmetic (not os.time) to avoid macOS/CI TZ divergence"
  - "DST table inlined in mapping.lua (not hoisted to timezone.lua) — 21 rows is compact enough"
  - "refund purpose: Phase 3 uses refundsPurchaseUUID1 as fallback (original purchaseNumber lookup is Phase 4)"
  - "serviceCharge deferred per CONTEXT Deferred + RESEARCH Open Q2"
metrics:
  duration: "~25 minutes"
  completed: "2026-06-20"
  tasks_completed: 3
  files_modified: 5
---

# Phase 03 Plan 03: Mapping Pure-Logic + DST Table + i18n Summary

Pure-logic mapping layer — `M_mapping.purchase_to_transaction` and `M_mapping.refund_to_transaction` — with inline EU-DST table (2020-2040), German amount formatting, and 7 new i18n keys, turning all Wave-0/1 pending specs GREEN.

## What Was Built

### src/mapping.lua (279 lines, from 4-line stub)

Public surface:
- `M_mapping.purchase_to_transaction(p)` — maps Zettle purchase JSON to MoneyMoney transaction table; returns nil for non-EUR (D-37)
- `M_mapping.refund_to_transaction(p)` — maps refund purchase to negative transaction with "Rückerstattung" suffix

Private helpers (all `local function` inside do...end block):
- `_parse_iso8601_utc(s)` — pure calendar arithmetic, TZ-independent (no `os.time` bias)
- `_to_berlin_local_time(utc_posix)` — linear scan of DST_TABLE, +7200 CEST or +3600 CET
- `_format_amount(minor_units)` — German comma decimal separator (e.g., 995 -> "9,95")
- `_format_label(payments)` — card brand + last-four from attributes.cardType/maskedPan (RESEARCH §1)
- `_format_purpose(p, opts)` — multi-line Brutto/MwSt/Trinkgeld/Netto/Beleg (D-34)

DST_TABLE: 21 rows covering years 2020-2040. Row 7 (2026): `{1774746000, 1792890000}`.

Verified manually:
- `POSIX(2026-06-19T23:55Z) = 1781913300` is in `[1774746000, 1792890000)` -> +7200 -> local 1781920500 -> `2026-06-20T01:55`
- `POSIX(2026-01-31T23:55Z) = 1769903700` is before 1774746000 -> +3600 -> local 1769907300 -> `2026-02-01T00:55`

### src/i18n.lua

7 new keys added to both STRINGS.de and STRINGS.en:
- `account.purpose.gross` -- "Brutto: %s €" / "Gross: %s €"
- `account.purpose.vat` -- "MwSt: %s €" / "VAT: %s €"
- `account.purpose.tip` -- "Trinkgeld: %s €" / "Tip: %s €"
- `account.purpose.net` -- "Netto: %s €" / "Net: %s €"
- `account.purpose.refund_for` -- "Rückerstattung zu Beleg #%s" / "Refund for receipt #%s"
- `account.purpose.receipt_number` -- "Beleg #%s" / "Receipt #%s"
- `account.name.card_payment` -- "Kartenzahlung" / "Card payment"

All keys use `%s` (amounts pre-formatted by `_format_amount` with comma separator).
Existing keys unchanged.

### spec/mapping_spec.lua

18 tests total, 0 pending:
- 2 sanity tests (was active in Wave 0)
- 16 Wave-0 pending tests activated with full assertions

Tests cover: SALE-01 (amount), SALE-02 (transactionCode), D-31 (booked/valueDate), SALE-04 (DST bookingDate), SALE-08 (card label), I18N-01 (German purpose), D-34 (MwSt/Trinkgeld omission), D-37 (non-EUR nil), D-32 (refund), D-38 (refund transactionCode).

### spec/dst_table_spec.lua

6 tests total, 0 pending (was 1 active + 5 pending in Wave 0):
- Summer boundary: 2026-06-19T23:55Z -> local 2026-06-20T01:55 (+7200 CEST)
- Winter boundary: 2026-01-31T23:55Z -> local 2026-02-01T00:55 (+3600 CET)
- Coverage test for years 2020-2040
- Exact start boundary: at 1774746000 picks summer offset
- Exact end boundary: at 1792890000 picks winter offset (strict less-than)

### spec/i18n_spec.lua

7 new tests covering all Phase 3 keys (total 13 tests, 0 failures).

## Test Results

| Spec | Before | After |
|------|--------|-------|
| spec/mapping_spec.lua | 2 active, 16 pending | 18 active, 0 pending |
| spec/dst_table_spec.lua | 1 active, 5 pending | 6 active, 0 pending |
| spec/mapping_schema_spec.lua | 0/8 (RED) | 8/8 (GREEN) |
| spec/i18n_spec.lua | 6 active | 13 active, 0 failures |
| spec/refresh_idempotency_spec.lua | 2 failures | 2 failures (Wave 4 closer -- expected) |
| spec/pagination_spec.lua | 8 pending | 8 pending (Wave 3 closer -- expected) |
| spec/purchases_spec.lua | 8 pending | 8 pending (Wave 3 closer -- expected) |

Full suite: **157 successes / 2 failures / 0 errors / 15 pending**

The 2 failures are in `spec/refresh_idempotency_spec.lua` and require Wave 4 (entry.lua rewire). Expected per plan.

## Acceptance Criteria Verification

- [x] DST_TABLE has all 21 rows for 2020-2040; row 7 = `{1774746000, 1792890000}`
- [x] Card metadata uses `payments[1].attributes.cardType` + `maskedPan` (not cardBrand/cardLastFour)
- [x] `valueDate` key is NOT written to any transaction (D-31)
- [x] `booked = false` on every Phase-3 transaction (lines 249 + 279 in mapping.lua)
- [x] `transactionCode` = `zettle:sale:<uuid>` / `zettle:refund:<uuid>` (D-38)
- [x] 7 new i18n keys in both STRINGS.de and STRINGS.en
- [x] spec/mapping_spec.lua: 18 tests, 0 pending
- [x] spec/dst_table_spec.lua: 6 tests, 0 pending
- [x] spec/mapping_schema_spec.lua: 8/8 GREEN
- [x] `lua tools/build.lua --verify` reproducible (sha256: 2d88bf132ff4968d0976659d5a3f6d18d03f2f21bbe66af55a55e80de3acb489)
- [x] `luacheck .` -- 0 warnings / 0 errors in 31 files
- [x] No `require()` in mapping.lua (D-02)
- [x] No `pcall` in mapping.lua
- [x] Existing Phase-1/2 specs unchanged

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] TZ-independent ISO-8601 parsing (macOS/CI TZ divergence)**

- **Found during:** Task 2 verification -- `mapping_schema_spec.lua` winter DST test failed with month=1 instead of month=2
- **Issue:** `os.time({year=Y, month=M, ...})` interprets components as LOCAL time on macOS (Europe/Berlin = UTC+1 in winter). This caused an off-by-3600 error for the winter fixture timestamp. The plan's RESEARCH §2b noted this risk under "ADR-0003 Q1 carryover" but assumed UTC behavior.
- **Fix:** Replaced `os.time()` with pure calendar arithmetic (days-since-epoch) that is completely TZ-independent. The algorithm computes Gregorian POSIX seconds from Y/M/D/H/Mi/S without any system call.
- **Verification:** Both summer (1781913300) and winter (1769903700) POSIX values match expected values exactly on macOS and would match on Linux CI.
- **Files modified:** `src/mapping.lua` (private `_parse_iso8601_utc` function)
- **Commit:** 8c1e681

## Known Stubs

None. All public functions produce real output from fixture data. The refund purpose uses `refundsPurchaseUUID1` UUID as fallback when the original receipt number is not pre-resolved -- this is explicitly documented in D-32 and deferred to Phase 4 (not a stub, it's intentional Phase 3 behavior).

## Threat Flags

No new security-relevant surface introduced. All threat mitigations in T-03-W2-* are addressed:
- T-03-W2-01 (DST table correctness): verified by spec/dst_table_spec.lua
- T-03-W2-02 (brand-map injection): mitigated by upper/lower Lua string operations (no gsub patterns)
- T-03-W2-03 (purpose content): only purchaseNumber integer and amount integer appear -- no API key or UUID-with-PII
- T-03-W2-04 (malformed timestamp): nil return from _parse_iso8601_utc -> fallback to os.time() -> no crash

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 (i18n) | a4f5e52 | feat(03-03): add German i18n keys for Phase 3 mapping |
| Task 2 (mapping) | 8c1e681 | feat(03-03): implement purchase/refund mapping with inline DST table |
| Task 3 (specs) | 2f63ece | test(03-03): fill mapping unit specs |

## Self-Check: PASSED

- src/mapping.lua exists: FOUND (279 lines)
- src/i18n.lua modified: FOUND (7 new keys in de + en)
- spec/mapping_spec.lua filled: FOUND (18 tests, 0 pending)
- spec/dst_table_spec.lua filled: FOUND (6 tests, 0 pending)
- spec/i18n_spec.lua extended: FOUND (13 tests total)
- All commits exist: a4f5e52, 8c1e681, 2f63ece
- Reproducible build: OK (sha256 stable across two builds)
- luacheck: 0 warnings / 0 errors in 31 files
- mapping_schema_spec.lua: 8/8 GREEN
