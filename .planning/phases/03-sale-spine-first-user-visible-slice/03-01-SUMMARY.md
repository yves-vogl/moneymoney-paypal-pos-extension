---
phase: 03-sale-spine-first-user-visible-slice
plan: "01"
subsystem: test-infrastructure
tags: [wave-0, scaffold, fixtures, dst, lua, mvp]
dependency_graph:
  requires: []
  provides:
    - spec/fixtures/purchases/*.json (10 hand-rolled Zettle purchase fixtures)
    - spec/dst_table_spec.lua (pending RED scaffold for DST boundary correctness)
    - spec/mapping_spec.lua (pending scaffold for M_mapping unit tests)
    - spec/pagination_spec.lua (pending scaffold for M_pagination unit tests)
    - spec/purchases_spec.lua (pending scaffold for M_purchases unit tests)
  affects:
    - Wave 1 (Plan 03-02): gating RED specs can now reference fixtures
    - Wave 2 (Plan 03-03): mapping_spec.lua pending stubs become GREEN targets
    - Wave 3 (Plan 03-04/05): pagination_spec + purchases_spec stubs become GREEN targets
tech_stack:
  added: []
  patterns:
    - JSON fixtures follow spec/fixtures/auth/*.json layout convention (_source key first, two-space indent, LF, single trailing newline)
    - Spec scaffold pattern: Mocks.setup() + dofile in before_each; one sanity it() + N pending() stubs
key_files:
  created:
    - spec/fixtures/purchases/purchase_simple_sale.json
    - spec/fixtures/purchases/purchase_with_vat_and_tip.json
    - spec/fixtures/purchases/purchase_refund.json
    - spec/fixtures/purchases/purchase_page1.json
    - spec/fixtures/purchases/purchase_page2.json
    - spec/fixtures/purchases/purchases_empty.json
    - spec/fixtures/purchases/purchase_non_eur.json
    - spec/fixtures/purchases/purchase_dst_boundary_summer.json
    - spec/fixtures/purchases/purchase_dst_boundary_winter.json
    - spec/fixtures/purchases/purchase_with_card_metadata.json
    - spec/dst_table_spec.lua
    - spec/mapping_spec.lua
    - spec/pagination_spec.lua
    - spec/purchases_spec.lua
  modified: []
decisions:
  - "Unused Fixtures import removed from spec/dst_table_spec.lua and spec/pagination_spec.lua — DST and pagination scaffolds require no fixture loading at Wave 0"
  - "luacheck: ignore 631 added to spec/mapping_spec.lua to suppress line-too-long on mandatory exact pending test name strings (bullet characters exceed 120 chars)"
  - "purchases_spec.lua omits Fixtures import per 03-PATTERNS.md guidance (only inline strings needed for URL/header assertions at Wave 0)"
metrics:
  duration_seconds: 852
  completed: "2026-06-20"
  tasks_completed: 3
  files_created: 14
---

# Phase 03 Plan 01: Wave 0 — Purchase Fixtures + Spec Scaffolds Summary

Ten hand-rolled Zettle purchase JSON fixtures and four pending spec scaffolds installed, establishing the complete Wave 0 test infrastructure for Phase 3's sale-spine implementation.

## What Was Built

### Fixtures (10 files under spec/fixtures/purchases/)

| Fixture | Key Shape | Purpose |
|---------|-----------|---------|
| `purchase_simple_sale.json` | 1 record, EUR 5.00, no VAT, no tip, `purchaseUUID1=11111111-...` | SALE-01 baseline + TEST-04 schema gate |
| `purchase_with_vat_and_tip.json` | EUR 19.95, VAT 318, `payments[0].gratuityAmount=100` | VAT / tip / I18N-01 German purpose lines |
| `purchase_refund.json` | amount=-995, `refund=true`, `refundsPurchaseUUID1=11111111-...` | D-32 refund mapping (negative amount, Rückerstattung) |
| `purchase_page1.json` | 1 record + `lastPurchaseHash="hash-page1-to-page2"` | Cursor handoff to page 2 |
| `purchase_page2.json` | `purchases=[]`, no `lastPurchaseHash` | Terminal page (belt-and-suspenders termination) |
| `purchases_empty.json` | `purchases=[]`, no cursor, distinct `_source` comment | SALE-06 since-past-all-purchases (empty window) |
| `purchase_non_eur.json` | `currency="USD"` | D-37 silent-skip path |
| `purchase_dst_boundary_summer.json` | `timestamp="2026-06-19T23:55:00.000+0000"` | SALE-04 CEST +02:00 -> Berlin local 2026-06-20 |
| `purchase_dst_boundary_winter.json` | `timestamp="2026-01-31T23:55:00.000+0000"` | SALE-04 CET +01:00 -> Berlin local 2026-02-01 |
| `purchase_with_card_metadata.json` | `payments[0].attributes.cardType="VISA"`, `maskedPan="411111******1111"` | SALE-08 / D-35 corrected card-brand + last-four label |

All 10 fixtures carry `_source: "github.com/iZettle/api-documentation/purchase.adoc"` as the first key, use only synthetic UUIDs (11111111-... through 88888888-...), and contain no deprecated field names (`cardBrand` / `cardLastFour`).

### Card Metadata Path Confirmation

`purchase_with_card_metadata.json` uses `payments[0].attributes.cardType` and `payments[0].attributes.maskedPan` per RESEARCH §1 correction over CONTEXT D-35 wording. `maskedPan` ends in `1111` so `:sub(-4)` in Wave 2 yields `"1111"`.

### Spec Scaffolds (4 files)

| File | Active tests | Pending stubs | Wave that greens |
|------|-------------|---------------|-----------------|
| `spec/dst_table_spec.lua` | 1 (M_mapping table exposed) | 5 (DST boundary correctness) | Wave 2 / Plan 03-03 |
| `spec/mapping_spec.lua` | 2 (M_mapping exposed + Fixtures.load nested-path proof) | 16 (SALE-01/02/04/08, I18N-01, D-32/34/35/37/38) | Wave 2 / Plan 03-03 |
| `spec/pagination_spec.lua` | 1 (M_pagination exposed) | 7 (SALE-06, cursor termination, MAX_PAGES) | Wave 3 / Plan 03-04 |
| `spec/purchases_spec.lua` | 1 (M_purchases exposed) | 8 (host allowlist, Bearer header, startDate, limit, fetch_all) | Wave 3 / Plan 03-05 |

### Fixtures.load Nested-Path Verification

`spec/mapping_spec.lua` includes an active test confirming `Fixtures.load("purchases/purchase_simple_sale")` works without changes to `spec/helpers/fixtures.lua`. The helper's path concat supports subdirectories natively — no code change needed.

## Verification Results

| Check | Result |
|-------|--------|
| `ls spec/fixtures/purchases/*.json \| wc -l` | 10 |
| All 10 fixtures parse via dkjson | PASS |
| `busted spec/` (full suite) | 119 successes / 0 failures / 0 errors / 36 pending |
| `luacheck .` | 0 warnings / 0 errors in 29 files |
| `lua tools/build.lua --verify` | OK: reproducible SHA unchanged (no src/ touched) |
| `grep -rn 'cardBrand\|cardLastFour' spec/fixtures/purchases/` | empty (correct) |
| `grep -c '^  pending(' spec/mapping_spec.lua` | 16 (>=16 required) |
| `grep -c '^  pending(' spec/pagination_spec.lua` | 7 (>=7 required) |
| `grep -c '^  pending(' spec/purchases_spec.lua` | 8 (>=8 required) |
| `grep -c '^  pending(' spec/dst_table_spec.lua` | 5 (>=5 required) |
| `src/webbanking_header.lua` modified | NO |
| `tools/manifest.txt` modified | NO |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Unused Fixtures import removed from spec/dst_table_spec.lua**
- **Found during:** Task 2 — luacheck flagged `unused variable Fixtures`
- **Issue:** Plan read_first mentioned fixtures.lua but DST spec needs no fixture loading (pure POSIX math)
- **Fix:** Removed `local Fixtures = require(...)` from dst_table_spec.lua
- **Commit:** de82bea

**2. [Rule 1 - Bug] luacheck: ignore 631 added to spec/mapping_spec.lua**
- **Found during:** Task 3 — 4 lines exceeded 120 chars due to exact pending test names with bullet characters
- **Issue:** The plan mandates exact test names for `busted -t` filtering; those names contain multi-byte UTF-8 bullets and long req references
- **Fix:** Added `-- luacheck: ignore 631` in file preamble; names preserved exactly as specified
- **Commit:** e81f513

**3. [Rule 1 - Bug] Unused Fixtures import removed from spec/pagination_spec.lua**
- **Found during:** Task 3 — luacheck flagged `unused variable Fixtures`
- **Issue:** Pagination Wave 0 scaffold has no fixture loading (cursor tests use only Mocks)
- **Fix:** Removed `local Fixtures = require(...)` from pagination_spec.lua
- **Commit:** e81f513

## Threat Surface Scan

None — pure JSON content + Lua test scaffolds. No new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Known Stubs

None — this is a Wave 0 scaffold. All pending tests are intentionally deferred to Wave 2/3 per plan design. No production code was written.

## Self-Check: PASSED

All 14 created files confirmed on disk. All 3 commits (2650f0a, de82bea, e81f513) found in git log. Full busted suite: 119/0/0/36. luacheck: 0/0.
