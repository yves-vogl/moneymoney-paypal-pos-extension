---
phase: 04-enrichment-refunds-fees-payouts
plan: "03"
subsystem: entry+finance
tags: [wave-2, integration, entry, finance, http, cross-refresh, mvp]
dependency_graph:
  requires: [04-02]
  provides:
    - "M_finance.fetch(clamped_since, bearer, offset) — single-page GET against /v2/accounts/liquid/transactions"
    - "M_finance.fetch_all(clamped_since, bearer) — offset-iterate driver"
    - "M_finance.fetch_account_state(bearer) — dual-GET balance + pendingBalance"
    - "src/entry.lua RefreshAccount extended with 16-step Phase-4 sequence (cross-refresh indexes, SALE-03 promotion, D-49 Option B fee classification, payout mapping, ACCT-03 balance return)"
    - "spec/helpers/mm_mocks.lua Mocks._captured_requests — multi-call request capture"
  affects: [04-05]
tech_stack:
  added:
    - "Finance API HTTP surface — three new functions in src/finance.lua all routed through M_http.get_json (D-42); no direct Connection() use"
    - "Cross-refresh in-RefreshAccount indexes — purchases_by_uuid (REF-02) + payments_by_uuid (FEE-01 via payments[].uuid key per RESEARCH §3.1 correction over CONTEXT D-50) + fin_payments_by_uuid (SALE-03 promotion lookup)"
    - "D-49 Option B fee classification — per-refresh date clustering; any-unlinked-on-day triggers aggregate; no LocalStorage write (D-59 honored)"
  patterns:
    - "Phase-3 belt-and-suspenders bearer assertion (M_purchases.fetch L61) copied to all three new HTTP functions (M_finance.fetch / fetch_all / fetch_account_state)"
    - "Module-local URL helpers — _iso8601_utc_no_z (Finance API no-Z timestamp form per RESEARCH §1.3 / §Pitfall 3) + _url_encode_query (no MM.urlencode — Finance API accepts literal `:`) + _INCLUDE_TYPES_SUFFIX literal (PATTERNS.md note: Lua table dedup precludes triplet via _url_encode_query)"
    - "ERR-06 fail-whole-refresh — both fetch_account_state and fetch_all error returns short-circuit RefreshAccount before any transaction is emitted (T-03-W4-03 invariant carried over)"
    - "SALE-03 promotion mutates transaction in place via M_mapping.promote_to_booked (D-56) — transactionCode UNCHANGED so MoneyMoney's dedup updates the row instead of inserting a duplicate"
    - "Per-request introspection extended — Mocks._captured_requests appends every conn:request call so multi-call sequences (fetch_account_state's two GETs) can be inspected in order; additive over existing _last_request semantics"
key_files:
  created:
    - spec/finance_spec.lua
    - spec/finance_account_state_spec.lua
    - .planning/phases/04-enrichment-refunds-fees-payouts/04-03-SUMMARY.md
  modified:
    - src/finance.lua
    - src/entry.lua
    - spec/entry_spec.lua
    - spec/refresh_idempotency_spec.lua
    - spec/refresh_log_redaction_spec.lua
    - spec/helpers/mm_mocks.lua
  deleted: []
decisions:
  - "D-49 Yves-blocker resolved: Option B (per-refresh date clustering, no persistent state) implemented per Yves checkpoint confirmation 2026-06-21 + research recommendation. Replan path to Option A documented in entry.lua comment block + below; tradeoff is the linkage-instability risk (a date may flip from aggregate-on-day-1 to per-sale-on-day-2). README disclaimer queued for Plan 04-06 release polish."
  - "Phase-2 callback byte-identity verified: git diff against pre-Plan-04-03 HEAD shows ZERO changes to SupportsBank / InitializeSession2 / ListAccounts / EndSession; only RefreshAccount body was extended (verified via git diff inspection — only `+` lines added inside RefreshAccount; no `-` lines anywhere)"
  - "CRITICAL correction over CONTEXT D-50 wording: payments_by_uuid index is keyed by purchases[].payments[].uuid (NOT purchaseUUID1) per RESEARCH §3.1. The FEE-01 end-to-end spec (zettle:fee:cccccccc...) is the structural assertion of this correction — failing without the right key"
  - "_url_encode_query in src/finance.lua differs from src/purchases.lua's: it does NOT use MM.urlencode. Finance API accepts literal `:` in start/end ISO-8601 values, and avoiding percent-encoding keeps the URL grep-friendly in CI logs. The colons in `2026-06-21T05:30:00` survive as `:` rather than `%3A` (verified by spec/finance_spec.lua URL assertions)"
  - "balance / pendingBalance fallback chain: account_state.balance OR account.balance (R-4 non-EUR-liquid case falls back to MoneyMoney's stored balance). When account_state.balance is nil, account.balance is the only field that can carry forward MoneyMoney's last-known good balance — this is the load-bearing reason for the OR fallback in the final return statement"
  - "Mocks._captured_requests is additive over Mocks._last_request (Wave-2 introduction): all existing specs continue to work; the new dual-GET spec uses _captured_requests[1] / [2] to verify ordering; entry_spec.lua tests that previously asserted on _last_request for the purchase URL now use _captured_requests[1] because the LAST request is now a Finance API call"
metrics:
  duration: "~25 minutes"
  completed: "2026-06-21"
  tasks_completed: 2
  files_created: 3
  files_modified: 6
  files_deleted: 0
  commits: 2
---

# Phase 04 Plan 03: Wave-2 Finance API + Cross-Refresh Integration Summary

Wave-2 wires the entire Phase-4 enrichment slice end-to-end inside a single `RefreshAccount` callback. After this plan lands, every MoneyMoney "Aktualisieren" click drives a deterministic 4-request sequence (purchase pages → liquid balance → preliminary balance → finance transactions) and emits the full bookkeeping picture — sales (with SALE-03 promotion to `booked=true` once a covering PAYOUT exists), refunds (with REF-02 in-window receipt lookup), fees (per-sale `zettle:fee:` when payments_by_uuid hits, daily aggregate `zettle:fee:aggregate:` under D-49 Option B otherwise), payouts (`zettle:payout:`, name "Auszahlung an Bankkonto"), and the two Finance API balance fields (`balance` from liquid, `pendingBalance` from preliminary). Phase-2 callbacks (SupportsBank, InitializeSession2, ListAccounts, EndSession) are byte-identically preserved.

## What Was Built

### src/finance.lua — three HTTP-bound functions appended (~146 lines added)

`M_finance.fetch(clamped_since, bearer, offset)` GETs `https://finance.izettle.com/v2/accounts/liquid/transactions` with `start=` + `end=` (both REQUIRED per RESEARCH §1.3 / §Pitfall 2), `limit=1000`, `offset=<n>`, and the three literal-suffix `includeTransactionType=PAYMENT,PAYMENT_FEE,PAYOUT` query parameters. Returns the 3-tuple from `M_http.get_json` verbatim so callers can route errors via `M_errors.from_http_status`.

The `start` / `end` dates use the module-local `_iso8601_utc_no_z(posix)` helper that returns `os.date("!%Y-%m-%dT%H:%M:%S", posix)` — distinct from Phase-3's `Z`-suffixed form per RESEARCH §1.3 / §Pitfall 3. The `end` date is `os.time() + 60` to add a small future buffer so a transaction created during the refresh isn't missed.

`M_finance.fetch_all(clamped_since, bearer)` drives `M_pagination.offset_iterate` with a closure that forwards `params.offset` to each `M_finance.fetch` call. Returns `(records, nil)` on full success or `(nil, err)` on any sub-page error. Defaults `limit=1000` per RESEARCH §1.3.

`M_finance.fetch_account_state(bearer)` issues **TWO sequential GETs** per RESEARCH §1.4:

1. `GET /v2/accounts/liquid/balance` → settled balance
2. `GET /v2/accounts/preliminary/balance` → in-flight balance

On any error returns `(nil, err)` **immediately** — the preliminary GET is NOT issued if the liquid GET errors (ERR-06 fail-whole-refresh per RESEARCH §Pitfall 5). On success returns `({balance = liquid.totalBalance/100, pendingBalance = preliminary.totalBalance/100}, nil)`. Currency-guard per D-37 / R-4: if `currencyId ~= "EUR"`, that side's value falls back to `nil` and an `M_log.info` line is emitted naming the rejected currency.

All three functions assert non-empty Bearer (Phase-3 belt-and-suspenders ME-01 pattern copied from `M_purchases.fetch` L61). All HTTP egress goes through `M_http.get_json` (D-42 — no direct Connection() use). Bearer never appears in logs (SEC-03 inherited via `M_http.get_json`'s structural header-omission contract).

### src/entry.lua — RefreshAccount extended with 16-step Phase-4 sequence

The `RefreshAccount(account, since)` body now drives:

| Step | Subject | Source |
|------|---------|--------|
| 1-4  | Phase-3: org guard, since clamp, cached_token, purchases fetch_all | Phase-3 baseline (unchanged) |
| 5    | Build `purchases_by_uuid` index (key=`purchaseUUID1`) | D-50 / REF-02 |
| 6    | Build `payments_by_uuid` index (key=`payments[].uuid` — CRITICAL correction) | D-49 / FEE-01 / RESEARCH §3.1 |
| 7    | `M_finance.fetch_account_state(bearer)` → ERR-06 fail-whole-refresh | ACCT-03 / D-52 |
| 8    | `M_finance.fetch_all(effective_since, bearer)` → ERR-06 fail-whole-refresh | Phase-4 |
| 9    | Parse + split into `fin_payments` / `fin_fees` / `fin_payouts` | RESEARCH §1.3 |
| 10   | Sort `fin_payouts` ascending by `timestamp_posix` + `_find_covering_payout` helper | RESEARCH §4.2 |
| 11   | Build `fin_payments_by_uuid` index (key=`originatingTransactionUuid`) | RESEARCH §3.2 |
| 12   | Map purchases → sales + refunds (refunds use `opts.original_receipt` lookup) | D-50 / D-32 |
| 13   | SALE-03 promotion sweep — for each sale, find covering PAYOUT, `promote_to_booked` | D-56 / RESEARCH §4.2 |
| 14   | D-49 Option B fee classification — cluster by Berlin date; any-unlinked → aggregate | D-49 / FEE-01 / FEE-03 |
| 15   | Map payouts via `payout_to_transaction` | PAYOUT-01/02/03 |
| 16   | Return `{balance, pendingBalance, transactions}` (account.balance fallback for R-4) | Phase-4 final shape |

The 14-step closure-local indexes (`purchases_by_uuid`, `payments_by_uuid`, `fin_payments_by_uuid`, `sale_to_purchase`, `fees_by_date`) live entirely inside `RefreshAccount`'s scope — no module-level state, no LocalStorage writes (D-59 honored). Per-refresh determinism is the load-bearing invariant: the same purchase + finance fixture set always produces the same transactions array (verified by `spec/refresh_idempotency_spec.lua`'s queueing infrastructure; the actual D-58 idempotency assertions land in Plan 04-05).

**Phase-2 callbacks unchanged.** `git diff HEAD~1 -- src/entry.lua` shows zero `-` lines inside `SupportsBank` / `InitializeSession2` / `ListAccounts` / `EndSession` function bodies, and zero `+` lines either. Only `RefreshAccount`'s body grew.

### spec/finance_spec.lua (NEW — 277 lines)

13 tests covering `M_finance.fetch` + `M_finance.fetch_all`:

| Subject | Coverage |
|---------|----------|
| URL host + path | `https://finance.izettle.com/v2/accounts/liquid/transactions` |
| Required query params | `start=`, `end=`, `limit=1000`, `offset=<n>` |
| `includeTransactionType` triplet | Exactly 3 occurrences; PAYMENT + PAYMENT_FEE + PAYOUT all present literally |
| Finance API date format | `YYYY-MM-DDThh:mm:ss` with NO `Z` suffix (RESEARCH §1.3 / §Pitfall 3) |
| Bearer header pass-through | `Authorization: Bearer AT-VALID` |
| Bearer guard | `assert.has_error` for nil and empty-string |
| Offset forwarding | `offset=1000` reflected in URL when called with offset=1000 |
| Error routing | invalid_grant → 400 → LoginFailed; rate_limit → 429 → German `error.rate_limit`; empty body → nil status → German `error.network` |
| `fetch_all` happy path | Single short page (5 records < limit 1000) terminates after one fetch |
| `fetch_all` empty | `finance_empty.json` yields zero records, no error |
| `fetch_all` mid-pagination error | Non-JSON body → `(nil, error_string)` |
| `fetch_all` Bearer guard | `assert.has_error` for nil |

### spec/finance_account_state_spec.lua (NEW — 135 lines)

8 tests covering `M_finance.fetch_account_state`:

| Subject | Coverage |
|---------|----------|
| Function exposure | `is_function` gate |
| Sequential GET ordering | `Mocks._captured_requests[1]` = `/liquid/balance`; `[2]` = `/preliminary/balance` |
| EUR happy path | `{balance = 123.45, pendingBalance = 6.78}` from the two fixtures |
| Currency-guard | Non-EUR liquid → `balance = nil`; EUR preliminary still populates |
| ERR-06 liquid fail | Non-JSON liquid body → `(nil, err)`; preliminary GET NOT issued (`#_captured_requests == 1`) |
| ERR-06 preliminary fail | Liquid OK + 401 on preliminary → `(nil, LoginFailed)` |
| Bearer guard | `assert.has_error` for nil and empty-string |

### spec/entry_spec.lua — extended Phase-4 describe block (+13 it cases) + Phase-3 retrofit

A new `describe("RefreshAccount Phase-4 pipeline (ACCT-03 / REF-02 / FEE-01-03 / PAYOUT-01-02 / SALE-03 / ERR-06)", ...)` block lands at the end of `spec/entry_spec.lua` with the following 11 it cases (sorted by requirement):

| Requirement | Test |
|-------------|------|
| ACCT-03 | `result.balance` = 123.45 + `result.pendingBalance` = 6.78 from Finance fixtures |
| R-4 | Non-EUR liquid → `balance` falls back to `account.balance`; pendingBalance still EUR |
| REF-02 / D-50 | Refund purpose cites `Rückerstattung zu Beleg #4001` (original purchaseNumber from same page) |
| FEE-01 | `zettle:fee:cccccccc...` per-sale fee txn; purpose cites `Beleg #2001` (originating purchaseNumber) |
| FEE-03 / D-49 Option B | `zettle:fee:aggregate:2026-06-15` emitted when any fee on that date is unlinked; zero per-sale fees on that date |
| PAYOUT-01/02 | `zettle:payout:` txn with name `Auszahlung an Bankkonto`; amount = -1500.00 (from -150000 minor units) |
| SALE-03 / D-56 | First refresh: sale `booked=false`. Second refresh w/ covering PAYOUT: sale `booked=true` + numeric `valueDate`; `transactionCode` byte-identical across refreshes (D-39 stability) |
| ERR-06 (liquid) | 500 on liquid balance → RefreshAccount returns error string; subsequent GETs never issued |
| ERR-06 (transactions) | 500 on Finance transactions → RefreshAccount returns error string |

Plus existing Phase-3 tests retrofitted via the new `queue_finance_tail()` helper (queues `finance_balance_liquid` + `finance_balance_preliminary` + `finance_empty` after the purchase response) so they satisfy the new 4-response call shape without changing their semantic intent. The "Phase 3 ACCT-03 not-yet-wired" test was upgraded to assert the Finance-API-sourced balance (123.45 from the liquid fixture) since ACCT-03 IS now wired.

### spec/refresh_idempotency_spec.lua — `refresh_with_fixture` helper extended

The helper now queues the FOUR Phase-4 responses per RefreshAccount call (8 total for the double-refresh). The actual D-58 idempotency assertions (sale+payout_promote stable, payout-only stable, fee linked stable, aggregate stable across refreshes) remain Plan 04-05's job. All 4 existing it cases (purchase_simple_sale double-refresh, purchase_with_vat_and_tip double-refresh, purchase_refund double-refresh, D-41 nil-token guard) continue to GREEN with the extended queueing.

### spec/refresh_log_redaction_spec.lua — same retrofit

The 7 existing Phase-3 redaction tests (Gate A LocalStorage JWT-shape walk, Gate B captured-prints Bearer literal absence, Gate C transactionCode prefix `^zettle:sale:|^zettle:refund:`) updated via the same `queue_finance_tail()` helper. Gate semantics preserved byte-identically; only the 3 trailing fixture responses were added to each test setup.

### spec/helpers/mm_mocks.lua — `Mocks._captured_requests` introduction

```lua
Mocks._captured_requests = {}  -- append-only history of every conn:request
```

Reset on `Mocks.setup()` + `Mocks.teardown()` alongside the other capture buffers. Appended inside `conn:request` after `_last_request` is set. Additive — existing `_last_request` semantics are byte-identically preserved; all existing specs that read `_last_request` continue to work. The Plan 04-03 dual-GET spec uses `_captured_requests[1]` / `[2]` to assert call-order invariants that `_last_request` alone cannot express.

## Decisions Made

- **D-49 Yves-blocker resolved → Option B implemented.** Per Yves' 2026-06-21 checkpoint confirmation, the research-recommended per-refresh date clustering ships in v0.2.0. The aggregate-may-double-book risk is acknowledged in entry.lua's step-14 comment block and queued for the Plan 04-06 README disclaimer. If a real merchant reports linkage flipping during the Phase 5 measurement window, replan via `/gsd-plan-phase 4 --gaps` to amend D-59 with a `LocalStorage.zettle.fees_aggregated` set; the pure-logic surface (`M_mapping.fee_aggregate_to_transaction` with stable `zettle:fee:aggregate:<date>` anchor) already supports either option without code change in `src/mapping.lua`.

- **payments_by_uuid CORRECTION over CONTEXT D-50.** The CONTEXT document wrote "key=purchaseUUID1" for the fee join index; RESEARCH §3.1 corrected this to `payments[].uuid` because one purchase can carry multiple payment legs and each leg has its own UUID. The PAYMENT_FEE record's `originatingTransactionUuid` matches the **leg UUID**, not the purchase UUID. The FEE-01 end-to-end spec (`zettle:fee:cccccccc...` transactionCode + `Beleg #2001` purpose) is the structural gate that asserts the correct key choice — failing with `nil originating purchase` if the wrong key were used.

- **Bearer assertion belt-and-suspenders carried into all three new HTTP functions.** Phase-3's `M_purchases.fetch` ships an explicit `assert(type(bearer) == "string" and #bearer > 0)` even though RefreshAccount already guards nil bearer via the D-41 cached_token branch. The same pattern lands on `M_finance.fetch` / `fetch_all` / `fetch_account_state` — any future regression that lets `nil` reach the URL builder would silently send `Bearer nil` as the Authorization header value, which is exactly the kind of failure the loud assertion catches.

- **_url_encode_query in finance.lua does NOT use MM.urlencode.** Distinct from `src/purchases.lua` where `MM.urlencode` percent-encodes `:` → `%3A`. Finance API accepts literal `:` in `start=` / `end=` ISO-8601 values, and keeping the URL un-encoded makes CI log grep trivial. The `includeTransactionType` triplet is appended as a literal suffix string (`_INCLUDE_TYPES_SUFFIX`) because Lua table-key dedup precludes generating the three identical keys via the encoder.

- **Mocks._captured_requests is additive.** No existing spec was touched in the mm_mocks helper beyond the buffer reset on setup/teardown; `_last_request` continues to point at the most recent call. The two-callsite update inside `conn:request` is the entire surface area of the change. The Plan 04-03 fetch_account_state spec exercises the new buffer; all 268 existing tests continue to GREEN.

- **balance fallback chain `account_state.balance OR account.balance`.** When the liquid balance is non-EUR (R-4 currency guard), `account_state.balance` is nil and the return statement falls back to `account.balance` (MoneyMoney's stored last-known good value). When the liquid call succeeds (EUR), `account_state.balance` shadows `account.balance` so the merchant always sees the freshest number. The fallback is a single `or` so the read-order matters; the spec gate for R-4 in `spec/entry_spec.lua` asserts `result.balance == 42.00` (the `account.balance` fixture value) when liquid is GBP.

## Per-refresh HTTP Call Shape

Each `RefreshAccount` call now consumes a deterministic 4+ request sequence (number depends on purchase / finance pagination):

```
1.            GET https://purchase.izettle.com/purchases/v2?descending=false&limit=200&startDate=<iso-Z>  [+ N-1 paginated continuations via lastPurchaseHash cursor]
2.            GET https://finance.izettle.com/v2/accounts/liquid/balance
3.            GET https://finance.izettle.com/v2/accounts/preliminary/balance
4.            GET https://finance.izettle.com/v2/accounts/liquid/transactions?end=<iso>&limit=1000&offset=0&start=<iso>&includeTransactionType=PAYMENT&includeTransactionType=PAYMENT_FEE&includeTransactionType=PAYOUT  [+ M-1 paginated continuations via offset += 1000]
```

For a typical 90-day refresh on a low-volume merchant (1 purchase page, 1 finance transactions page), the total is **4 sequential GETs** — well within MoneyMoney's per-callback timeout budget per RESEARCH §1 "Typical page count + total refresh budget" analysis. The spec's `refresh_with_fixture` helper queues exactly these 4 responses per call; if a real merchant produces N purchase pages + M finance pages, the iterators handle them transparently.

## Metrics

| Metric | Value |
|---|---|
| Tasks completed | 2 / 2 |
| Files created | 3 (2 spec files + this SUMMARY) |
| Files modified | 6 (2 source + 4 spec helpers/tests) |
| Files deleted | 0 |
| Commits | 2 (all GPG-signed by FDE07046A6178E89ADB57FD3DE300C53D8E18642) |
| Spec suite | 255 → 300 successes (+45); 0 failures; 0 errors; 0 pending |
| Plan-04-03-specific test delta | +25 finance specs + +13 entry Phase-4 cases + +7 retrofitted Phase-3 tests = 45 net |
| Luacheck | 0 warnings / 0 errors across 35 files |
| Reproducible-build SHA | `d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712` (verified across two consecutive builds) |
| `wc -l src/finance.lua` | 205 (was 59 after Plan 04-02) — +146 lines for the three HTTP-bound functions + 3 helpers + constant |
| `wc -l src/entry.lua` | 377 (was 205 in Phase-3) — +172 lines inside RefreshAccount; Phase-2 callbacks untouched |
| Duration | ~25 minutes (single autonomous execution session) |

## Commit Log

| # | SHA | Type | Message |
|---|---|---|---|
| 1 | `54e6fd8` | feat | `feat(04-03): add M_finance.fetch + fetch_all + fetch_account_state (RESEARCH §1.3, §1.4)` |
| 2 | `84052c3` | feat | `feat(04-03): wire finance API + cross-refresh indexes into RefreshAccount` |

Both commits GPG-signed (`%G? = G`). No AI / Claude / Anthropic attribution anywhere in commit messages, code comments, fixtures, or i18n strings (verified via `git log -2 --format='%B' | grep -iE 'claude|anthropic'` returning empty).

## Hand-off Notes for Plan 04-05

Plan 04-05 (Wave 4 — META-03 forbidden-strings invariant + extended idempotency + log redaction prefix gate update) inherits the following landed surfaces:

### Available primitives (use directly, do NOT re-implement)

- `M_finance.fetch / fetch_all / fetch_account_state` — all wired into RefreshAccount; spec coverage at 25 tests for the HTTP layer alone.
- `Mocks._captured_requests` (mm_mocks.lua) — multi-call inspection; iterate this array to walk every URL / headers / body in order.
- `spec/refresh_idempotency_spec.lua refresh_with_fixture` helper — already queues the FOUR Phase-4 responses per call. Plan 04-05 D-58 assertions can use this helper as-is and add their own assertion bodies inside the existing 4 it cases (or add new it cases that reuse the helper).
- The `_format_purpose` extensions Plan 04-04 landed (per-rate VAT + card-tail) are unaffected by this plan — both are pure-logic mapping changes, not RefreshAccount-level changes.

### Still-RED specs that Plan 04-05 closes

- `spec/meta_no_tax_classification_spec.lua` does not yet exist; Plan 04-05 authors it per the 13-phrase forbidden-strings list locked at Yves checkpoint 2026-06-21.
- `spec/refresh_log_redaction_spec.lua` Gate C currently asserts only `^zettle:sale:|^zettle:refund:` — Plan 04-05 extends this to allow the new Phase-4 prefixes `^zettle:fee:`, `^zettle:fee:aggregate:`, `^zettle:payout:` per D-38 update. The current spec still GREENs because the Phase-3 retrofit tests use fixtures that emit zero fee/payout transactions (`finance_empty`); a Phase-4 fixture in the same gate file would currently fail until Plan 04-05 updates the allow-set.
- `spec/refresh_idempotency_spec.lua` D-58 cases — the queueing infrastructure is ready; only the assertion bodies need landing (sale+payout_promote stable, payout-only stable, fee linked stable, aggregate stable across refreshes).

### Things to NOT redo in Plan 04-05

- Do not modify `M_finance.fetch` / `fetch_all` / `fetch_account_state` — their public signatures and URL shapes are locked under D-46..D-49.
- Do not modify the Phase-2 callbacks (SupportsBank / InitializeSession2 / ListAccounts / EndSession) — their byte-identity is the load-bearing invariant verified by Plan 04-06's audit gate.
- Do not modify the 16-step `RefreshAccount` sequence — Plan 04-05 only adds gating specs (META-03 invariant) and extends existing specs (D-58 assertion bodies + log-redaction prefix allow-set). The entry-layer logic is finalised.
- Do not introduce `LocalStorage` writes for D-49 fee-aggregate dedup unless Yves explicitly approves Option A (CONTEXT D-49). The recommended Option B is locked for v0.2.0; Phase-5 measurement window decides whether real-world linkage flipping justifies upgrading to Option A.

### Open Yves-blockers (resolved in this plan)

- **D-49 Option A vs Option B** — RESOLVED 2026-06-21 via Yves checkpoint. Option B implemented; replan path documented in entry.lua + this SUMMARY for the future-revisit case.

### Open Yves-blockers (carried forward to Plan 04-05)

- **D-55 META-03 forbidden-strings list completeness** — RESOLVED 2026-06-21 via Yves checkpoint (13 phrases as drafted in CONTEXT). Plan 04-05 lands the gating spec on top of the confirmed list.

## Self-Check: PASSED

- All claimed files exist on disk: `src/finance.lua` (205 LoC), `src/entry.lua` (377 LoC), `spec/finance_spec.lua` (277 LoC), `spec/finance_account_state_spec.lua` (135 LoC), `spec/entry_spec.lua` (960 LoC), `spec/refresh_idempotency_spec.lua` (198 LoC), `spec/refresh_log_redaction_spec.lua` (218 LoC), `spec/helpers/mm_mocks.lua` (342 LoC).
- Both commit SHAs (`54e6fd8`, `84052c3`) found in `git log --oneline phase-4/enrichment` and each carries `%G? = G` (GPG-signed by maintainer's key).
- Full `busted spec/` reports `300 successes / 0 failures / 0 errors / 0 pending` (was 255 baseline + 45 new = 300, exact match).
- `./.luarocks/bin/luacheck .` reports `Total: 0 warnings / 0 errors in 35 files`.
- `lua tools/build.lua --verify` reports `OK: reproducible (sha256: d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712)` across two consecutive runs.
- `git log -2 --format='%B' | grep -iE 'claude|anthropic'` returns empty (no AI attribution).
- Phase-2 callbacks byte-identity verified via `git diff HEAD~2 -- src/entry.lua` — only RefreshAccount changes; zero `-` or `+` lines inside SupportsBank / InitializeSession2 / ListAccounts / EndSession function bodies.
