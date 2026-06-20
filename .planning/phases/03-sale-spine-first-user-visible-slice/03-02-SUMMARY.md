---
phase: 03-sale-spine-first-user-visible-slice
plan: "02"
subsystem: spec
tags: [wave-1, red-spec, idempotency, schema-gate, mvp, test]
dependency_graph:
  requires: [03-01]
  provides: [spec/refresh_idempotency_spec.lua, spec/mapping_schema_spec.lua]
  affects: [src/mapping.lua, src/entry.lua, src/purchases.lua]
tech_stack:
  added: []
  patterns:
    - assert_callable guard converts nil-function Lua errors into assertion failures
    - flat LocalStorage["zettle:<orgUuid>"] seeding for D-23c cross-restart cache path
    - AT-VALID non-JWT Bearer placeholder for SEC-03 walk-pattern noise avoidance
key_files:
  created:
    - spec/refresh_idempotency_spec.lua
    - spec/mapping_schema_spec.lua
  modified: []
decisions:
  - "assert_callable(fn, name) helper added to mapping_schema_spec.lua to convert nil-call
     Lua errors into assertion failures — required because Wave-1 src/mapping.lua is a
     completely empty table (no stub functions), unlike what the plan assumed (stub functions
     returning nil). This is a spec-plumbing adaptation, not a blacklist violation."
metrics:
  duration: "~10 minutes"
  completed: "2026-06-20"
  tasks: 2
  files: 2
---

# Phase 03 Plan 02: RED Gating Specs (Wave 1) Summary

Two gating specs authored and committed in RED state. Both produce assertion failures (not Lua errors) against the current Phase-2/Wave-0 codebase. Full suite exits non-zero only due to these two new files — no Phase-1/2 regression.

## Gating Spec: spec/refresh_idempotency_spec.lua (TEST-03)

**Purpose:** D-39 idempotency contract — double RefreshAccount call on same backend state must produce zero new transactionCodes on second call.

**Test count:** 4 `it()` blocks

| Test | Fixture | OrgUuid | What it asserts |
|------|---------|---------|----------------|
| 1 | purchase_simple_sale | org-1 | r2 transactionCodes ⊆ r1 set; r1 codes match `^zettle:sale:` |
| 2 | purchase_with_vat_and_tip | org-2 | r2 transactionCodes ⊆ r1 set |
| 3 | purchase_refund | org-3 | r2 ⊆ r1; r1 contains at least one `^zettle:refund:` code (D-32/D-38) |
| 4 | n/a (no token seeded) | org-no-token | Returns `M_i18n.t("error.network", "—")` when cached_token is nil (D-41) |

**LocalStorage seeding:** Flat path `LocalStorage["zettle:<orgUuid>"]` per D-23c double-write contract. Bearer placeholder `AT-VALID` is non-JWT-shaped (no two dots) per 02-07-SUMMARY Test-3 convention.

**RED state:** Tests 3 and 4 fail with assertion errors. Tests 1 and 2 pass because the Phase-2 fixture RefreshAccount returns a deterministic hardcoded transaction (`zettle:sale:fixture-0001`) regardless of mocked HTTP content — the dedup assertion trivially holds for identical codes from the same hardcoded stub. Tests 1+2 will become properly meaningful and fully gate Wave 4 when entry.lua drives the real pipeline.

**Wave green path:**
- Wave 2 partial: mapping.lua produces real transactionCodes from fixtures
- Wave 4 full: entry.lua RefreshAccount drives real pipeline + D-41 nil-token guard

## Gating Spec: spec/mapping_schema_spec.lua (TEST-04)

**Purpose:** Golden-file schema gate — every transaction must carry the 7 mandatory MoneyMoney fields; D-31/D-32/D-37/D-38 invariants enforced across fixture types.

**Test count:** 8 `it()` blocks

| Test | Fixture | Invariants asserted |
|------|---------|---------------------|
| 1 | purchase_simple_sale | 7-field schema; booked=false (D-31); valueDate=nil (D-31); currency=EUR |
| 2 | purchase_with_vat_and_tip | schema; txn.amount == purchase.amount/100 (SALE-01) |
| 3 | purchase_with_card_metadata | schema; name contains "Visa" and "1111" (SALE-08 / D-35 via attributes path) |
| 4 | purchase_refund | schema; amount<0 (D-32); transactionCode `^zettle:refund:` (D-38); booked=false |
| 5 | purchase_dst_boundary_summer | schema; os.date("!*t") yields y=2026 m=6 d=20 (CEST +2h, D-36) |
| 6 | purchase_dst_boundary_winter | schema; os.date("!*t") yields y=2026 m=2 d=1 (CET +1h, D-36) |
| 7 | purchase_non_eur | M_mapping.purchase_to_transaction returns nil (D-37 silent skip) |
| 8 | 5 EUR fixtures | cross-fixture EUR currency invariant (D-23a) |

**REQUIRED_FIELDS:** `{"name","amount","currency","bookingDate","purpose","transactionCode","booked"}` — single source of truth per T-03-W1-02.

**RED state:** All 8 tests fail with assertion errors (not Lua errors). The `assert_callable(fn, name)` guard converts the nil-call Lua error into a proper assertion failure before each mapping function call. This was necessary because `src/mapping.lua` is a completely empty stub (empty table `M_mapping = {}`, no functions at all), not a stub with functions returning nil as the plan assumed.

**Card metadata path:** Tests use `payments[].attributes.cardType` and `payments[].attributes.maskedPan` per RESEARCH §1 correction over CONTEXT D-35 wording.

**Wave green path:**
- Wave 2: src/mapping.lua implements `purchase_to_transaction` and `refund_to_transaction` — greens tests 1–4, 7–8
- Wave 2 also: `_to_berlin_local_time` DST table — greens tests 5–6

## Verification Results

| Check | Result |
|-------|--------|
| `busted spec/refresh_idempotency_spec.lua` | NON-ZERO exit — 2 failures, 0 errors (RED) |
| `busted spec/mapping_schema_spec.lua` | NON-ZERO exit — 8 failures, 0 errors (RED) |
| Full suite `busted spec/` | 121 successes / 10 failures / 0 errors / 36 pending |
| Pre-existing Phase-1/2 specs | 114 successes / 0 failures / 0 errors — no regression |
| Wave-0 pending scaffolds | 5 successes / 0 failures / 36 pending — unchanged |
| `lua tools/build.lua --verify` | OK — SHA256 b260991a unchanged from Wave 0 |
| `luacheck` on new spec files | 0 warnings / 0 errors |
| `luacheck .` (full project) | 6 warnings / 0 errors — all 6 pre-existing in dist/paypal-pos.lua (empty do...end blocks from Phase-3 stubs; worktree dist/ path not matched by .luacheckrc exclude pattern) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] assert_callable guard added to mapping_schema_spec.lua**

- **Found during:** Task 2 execution — mapping_schema_spec produced Lua errors (not assertion failures) because `M_mapping.purchase_to_transaction` is nil (calling a nil value in Lua raises an error, not a nil return)
- **Root cause:** Plan assumed `src/mapping.lua` stub would contain stub functions returning nil. Actual stub is an empty file — `M_mapping` is predeclared in `webbanking_header.lua` as an empty table `{}` with no functions added by the stub.
- **Fix:** Added `local function assert_callable(fn, name)` helper that uses `assert.is_function()` to gate each test. This produces an assertion failure (plan's required RED state) instead of a nil-call Lua error. The helper is NOT a monkey-patch — it does not modify `M_mapping` in any way. No pcall wrappers added.
- **Files modified:** `spec/mapping_schema_spec.lua`
- **Commit:** `1854580`

### Luacheck Line-Length Annotations

Two `it()` test description strings in `mapping_schema_spec.lua` exceed 120 characters. These are plan-specified verbatim test names. Added `-- luacheck: ignore 631` inline annotations on those two lines to suppress the warning without shortening the names.

## Known Stubs

None in the new spec files. The specs call into stubs (`M_mapping.*`) but the specs themselves are complete and contain no placeholder logic.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Spec files only — no production code modified.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| spec/refresh_idempotency_spec.lua exists | FOUND |
| spec/mapping_schema_spec.lua exists | FOUND |
| commit 1f0bbcd exists | FOUND |
| commit 1854580 exists | FOUND |
