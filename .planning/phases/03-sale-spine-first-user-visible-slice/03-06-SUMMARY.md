---
phase: 03-sale-spine-first-user-visible-slice
plan: "06"
subsystem: entry-integration
tags: [wave-4, entry, refresh-account, integration, sale-spine, mvp]
dependency_graph:
  requires: [03-01, 03-02, 03-03, 03-04, 03-05]
  provides: [refresh-account-pipeline, entry-phase3]
  affects: [dist/paypal-pos.lua]
tech_stack:
  added: []
  patterns:
    - "RefreshAccount orchestrates: orgUuid guard → cached_token → since clamp (NINETY_DAYS) → fetch_all → map dispatch → return"
    - "Deviation Rule 2 (cleanup): _inline_iterate dead helper removed from src/purchases.lua (optional per plan)"
key_files:
  created: []
  modified:
    - src/entry.lua
    - src/purchases.lua
    - spec/entry_spec.lua
decisions:
  - "Since clamp (D-33) placed at entry boundary (NINETY_DAYS = 90 * 86400) not inside M_purchases.fetch per RESEARCH Pitfall 5"
  - "D-41 nil-token guard returns M_i18n.t('error.network', '—') with em-dash literal matching idempotency spec Test 4"
  - "_inline_iterate dead helper removed from src/purchases.lua (parallel-plan window closed with Plan 03-04)"
  - "Two stale Phase-1 RefreshAccount fixture tests replaced with Phase-3 guard test (accountNumber missing)"
metrics:
  duration: "~15 minutes"
  completed: "2026-06-20"
  tasks_completed: 2
  files_changed: 3
---

# Phase 3 Plan 06: RefreshAccount Entry Integration — Summary

**One-liner:** RefreshAccount rewired to drive the real Phase-3 pipeline (cached_token → 90-day clamp → fetch_all → map dispatch → return), making refresh_idempotency_spec fully GREEN for the first time.

## What Was Built

### Task 1: src/entry.lua RefreshAccount Rewire

The Phase-1 fixture body (`balance=9.95`, `transactionCode="zettle:sale:fixture-0001"`, `booked=true`) was removed and replaced with the real Phase-3 pipeline:

**Module-scope constant:**
```lua
local NINETY_DAYS = 90 * 86400
```

**RefreshAccount pipeline (6 steps):**

1. **orgUuid guard (T-03-W4-02):** `account.accountNumber` must be a non-empty string; returns `M_i18n.t("error.network", "missing_account")` otherwise
2. **Since clamp at boundary (D-33):** `effective_since = math.max(since or 0, os.time() - NINETY_DAYS)` — visible at entry per RESEARCH Pitfall 5
3. **Log line (SEC-03):** `M_log.info("RefreshAccount called for org=" .. orgUuid:sub(1,8) .. " since=" .. effective_since)` — only 8-char prefix, never Bearer
4. **nil-token guard (D-41):** `M_auth.cached_token(orgUuid)` → if nil return `M_i18n.t("error.network", "—")` (em-dash literal matches idempotency spec Test 4)
5. **fetch_all (ERR-06):** `M_purchases.fetch_all(effective_since, bearer)` → if `fetch_err` return immediately (never partial transactions + error)
6. **Map dispatch (D-32/D-37):** `ipairs(purchases)` → `p.refund == true` → `refund_to_transaction`, else `purchase_to_transaction`; nil results skipped silently
7. **Return:** `{ balance = account.balance, transactions = transactions }` (balance passthrough per D-31 — Finance API is Phase 4)

**Frozen surface:** `SupportsBank`, `InitializeSession2`, `ListAccounts`, `EndSession` are byte-identical to pre-Wave-4 state. Only the `RefreshAccount` body changed (plus the `NINETY_DAYS` module-local constant added at file scope).

### Task 2: spec/entry_spec.lua Extended

**Stale tests replaced:** Two Phase-1 fixture tests (`"RefreshAccount returns one transaction with EUR + zettle:sale prefix"` and `"RefreshAccount transaction name comes from i18n"`) replaced with a single Phase-3 guard test that verifies the error.network path when `accountNumber` is absent.

**New describe block added:** `"RefreshAccount Phase-3 pipeline (SALE-01..06+08 / D-31 / D-33 / D-37 / D-41)"` with 9 integration tests covering:

| Test | Contract |
|------|----------|
| missing accountNumber | returns German error.network with "missing_account" |
| nil cached_token (D-41) | returns `M_i18n.t("error.network", "—")` exactly |
| happy-path sale | 5.00 EUR, transactionCode `zettle:sale:11111111-...`, booked=false |
| refund dispatch (D-32) | negative amount, transactionCode starts with `zettle:refund:` |
| non-EUR skip (D-37) | 0 transactions emitted |
| empty-refresh (SALE-06) | 0 transactions from empty fixture |
| since clamp epoch (D-33) | URL startDate is not "1970" (clamped to ~90 days ago) |
| since passthrough recent (D-33) | URL startDate contains year-month of recent since value |
| balance passthrough (D-31) | result.balance == 123.45 unchanged |
| HTTP error (ERR-06) | returns error string, not a table |

### Optional Cleanup: src/purchases.lua _inline_iterate Removed

The `_inline_iterate` private function (Wave-3 parallel-plan fallback, superseded by `M_pagination.iterate`) and its conditional fallback in `fetch_all` were removed. `M_purchases.fetch_all` now calls `M_pagination.iterate(fetch_page_fn, {})` directly. All 185 specs pass with the leaner implementation.

## Gating Spec Status

| Spec file | Before Plan 03-06 | After Plan 03-06 |
|-----------|-------------------|------------------|
| spec/refresh_idempotency_spec.lua | RED (Wave-1 gate) | **FULLY GREEN (4/4)** |
| spec/mapping_schema_spec.lua | GREEN | GREEN (no regression) |
| spec/mapping_spec.lua | GREEN | GREEN |
| spec/pagination_spec.lua | GREEN | GREEN |
| spec/purchases_spec.lua | GREEN | GREEN |
| spec/entry_spec.lua | 25 pass / 2 error | **36 pass / 0 failures** |
| Full suite | partial | **185 / 0 / 0 / 0** |

## Reproducible Build

```
SHA256: 2281ebc8af0b455f45fa246c4cfc3796a73d629cff6660082de4b4f13dbd600b
```

Two consecutive `lua tools/build.lua --verify` runs produce identical SHA.

## Egress Sanity

URLs present in `dist/paypal-pos.lua`:
1. `https://oauth.zettle.com/token` (Phase-2 auth)
2. `https://oauth.zettle.com/users/self` (Phase-2 profile)
3. `https://purchase.izettle.com/purchases/v2` (Phase-3 purchases)

No `finance.izettle.com` (Phase 4, ACCT-03).

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 4858267 | `feat(03-06)` | rewire RefreshAccount to drive Phase-3 pipeline |
| b2624a8 | `test(03-06)` | extend entry spec with Phase-3 RefreshAccount integration tests |
| f26277e | `refactor(03-06)` | remove _inline_iterate dead helper now that M_pagination.iterate is wired |

## Deviations from Plan

### Optional Cleanup Executed

**[Refactor - Optional] Removed _inline_iterate from src/purchases.lua**
- Found during: Task 1 review
- Issue: `_inline_iterate` was dead code (Wave-3 parallel-plan fallback never triggered once M_pagination.iterate was defined)
- Fix: Removed the function and the conditional `if type(M_pagination.iterate) == "function"` guard; `fetch_all` now calls `M_pagination.iterate` directly
- Files modified: `src/purchases.lua`
- Commit: `f26277e`

### Stale Phase-1 RefreshAccount Tests Updated

**[Rule 1 - Bug] Two Phase-1 fixture tests in spec/entry_spec.lua replaced**
- Found during: Task 2 (after Task 1 rewire)
- Issue: `RefreshAccount({}, 0)` (empty account) now returns error string instead of transaction table; the two old tests crashed with nil index errors
- Fix: Replaced both with a single guard test asserting the error.network path when accountNumber is absent; Phase-3 coverage moved to the new describe block
- Files modified: `spec/entry_spec.lua`

## Phase-3 Integration Milestone Note

With Plan 03-06 complete, a maintainer with a real PayPal POS API key can:
1. `lua tools/build.lua` to produce `dist/paypal-pos.lua`
2. Drop the file into MoneyMoney's Extensions folder
3. Enable "Inoffizielle Extensions erlauben" in MoneyMoney preferences
4. Click "Konto hinzufügen → PayPal POS" and paste the API key
5. Click "Aktualisieren" — card sales from the last 90 days appear as pending transactions
6. Click "Aktualisieren" again — zero new transactions (idempotency gate satisfied)

The balance will show as whatever `account.balance` was set to by MoneyMoney (Finance API not yet wired — Phase 4 ACCT-03). All transactions appear in "vorgemerkte Umsätze" (pending) until Phase 4 ships the `booked=true` transition with `valueDate`.

## Known Stubs

- `account.balance` in `RefreshAccount` return is passed through unchanged (Phase 4 will refresh from Finance API)
- `booked = false` on all transactions (Phase 4 wires `booked=true` + `valueDate` via Finance API payout cross-reference)

These are intentional Phase-3 constraints documented in D-31 and in CONTEXT.md.

## Threat Flags

None. The implementation follows the threat register mitigations:

| Threat | Mitigation | Status |
|--------|-----------|--------|
| T-03-W4-01 Information Disclosure (log) | orgUuid:sub(1,8) only; no Bearer in logs | Implemented |
| T-03-W4-02 Tampering (accountNumber) | Non-empty string guard before any cache lookup | Implemented |
| T-03-W4-03 Partial-transactions-with-error | ERR-06: `if fetch_err then return fetch_err end` | Implemented |
| T-03-W4-04 since clamp | math.max at entry boundary, not inside fetch | Implemented |

## Self-Check: PASSED

Files exist:
- src/entry.lua: FOUND
- src/purchases.lua: FOUND
- spec/entry_spec.lua: FOUND

Commits exist:
- 4858267: FOUND
- b2624a8: FOUND
- f26277e: FOUND
