---
phase: 04-enrichment-refunds-fees-payouts
plan: "02"
subsystem: mapping
tags: [wave-1, pure-logic, mapping, pagination, finance, fixtures, tdd, mvp]
dependency_graph:
  requires: []
  provides:
    - M_finance.parse_transaction
    - M_pagination.offset_iterate
    - M_mapping.fee_to_transaction
    - M_mapping.fee_aggregate_to_transaction
    - M_mapping.payout_to_transaction
    - M_mapping.promote_to_booked
    - M_mapping.parse_iso8601_utc
    - M_mapping.to_berlin_local_time
    - M_mapping.berlin_local_date
    - "M_mapping.refund_to_transaction(p, opts) extended signature"
  affects: [04-03, 04-04, 04-05]
tech_stack:
  added:
    - "Finance API record-shape normaliser (M_finance.parse_transaction) — pure-logic kind dispatch + Phase-3 timestamp parser reuse"
    - "Offset-based pagination iterator (M_pagination.offset_iterate) — sibling to Phase-3 cursor iterator; D-48 / RESEARCH §1.6 termination"
    - "Pure-logic mappers for fees, payouts, fee-aggregate-fallback, and booked promotion"
  patterns:
    - "Public-wrapper pattern for cross-module helper reuse (M_mapping.parse_iso8601_utc) — preserves D-02 no-require()-of-siblings invariant"
    - "Backwards-compatible opts second-arg extension (refund_to_transaction(p, opts)) — Phase-3 callers unchanged"
    - "transactionCode prefix = stable idempotency anchor (zettle:fee:UUID, zettle:fee:aggregate:DATE, zettle:payout:UUID)"
    - "Berlin-local POSIX bookingDate convention reused byte-identically from Phase-3 D-36 (os.date('!*t', bookingDate) decomposes as wall-clock)"
key_files:
  created:
    - src/finance.lua
    - spec/finance_parse_transaction_spec.lua
    - spec/pagination_offset_spec.lua
    - spec/fixtures/finance/finance_empty.json
    - spec/fixtures/finance/finance_single_page.json
    - spec/fixtures/finance/finance_multi_page_1.json
    - spec/fixtures/finance/finance_multi_page_2.json
    - spec/fixtures/finance/finance_payment_with_fee_linkage.json
    - spec/fixtures/finance/finance_payment_fee_unlinked.json
    - spec/fixtures/finance/finance_payout.json
    - spec/fixtures/finance/finance_payment_and_payout_for_promotion.json
    - spec/fixtures/finance/finance_balance_liquid.json
    - spec/fixtures/finance/finance_balance_preliminary.json
    - spec/fixtures/purchases/purchase_vat_split_19_7.json
    - spec/fixtures/purchases/purchase_refund_with_original_in_page.json
    - spec/fixtures/purchases/purchase_page_with_payments_for_fee_join.json
  modified:
    - src/pagination.lua
    - src/mapping.lua
    - src/i18n.lua
    - src/webbanking_header.lua
    - tools/manifest.txt
    - .luacheckrc
    - spec/mapping_spec.lua
    - spec/mapping_schema_spec.lua
    - spec/i18n_spec.lua
    - spec/fixtures/purchases/purchase_with_vat_and_tip.json
  deleted:
    - src/balance.lua
    - src/payouts.lua
decisions:
  - "M_pagination.offset_iterate is a sibling — Phase-3 cursor iterator is byte-identical post-plan (D-48 enforcement)"
  - "M_mapping.parse_iso8601_utc + to_berlin_local_time + berlin_local_date exposed as public wrappers so M_finance and Plan 04-03 entry-layer can reuse without require() of siblings (D-02)"
  - "Finance records' transactionCode key for fees and payouts is `zettle:{fee,payout}:<originatingTransactionUuid>` — Finance records have no `uuid` field of their own; originatingTransactionUuid is unique per payment leg and per payout (RESEARCH §3.4)"
  - "Phase-1 stubs src/balance.lua + src/payouts.lua consolidated into src/finance.lua (RESEARCH §Pitfall 10) — manifest reordered to insert `finance` between `purchases` and `mapping`"
  - "fee_aggregate_to_transaction bookingDate is computed via _parse_iso8601_utc(date_iso .. 'T00:00:00Z') (NOT _to_berlin_local_time of that) — the Phase-3 D-36 convention represents Berlin-local clock face as POSIX-treated-as-UTC; adding the offset a second time would double-count"
  - "Regenerated spec/fixtures/purchases/purchase_with_vat_and_tip.json — groupedVatAmounts key '19' -> '19.0' per real Zettle API decimal-string format (RESEARCH §5.1 / R-5). Phase-3 specs reading vatAmount top-level unaffected"
metrics:
  duration: "~40 minutes"
  completed: "2026-06-21"
  tasks_completed: 3
  files_created: 16
  files_modified: 10
  files_deleted: 2
  commits: 3
---

# Phase 04 Plan 02: Wave-1 Pure-Logic Surface Summary

Wave-1 deposits the entire pure-logic Phase-4 surface — `M_finance.parse_transaction`, `M_pagination.offset_iterate`, four new `M_mapping` mappers (`fee_to_transaction`, `fee_aggregate_to_transaction`, `payout_to_transaction`, `promote_to_booked`) plus the backwards-compatible `refund_to_transaction(p, opts)` extension, 12 new i18n keys (de + en parity), and the full Phase-4 fixture set (10 finance + 2 new purchase + 1 regenerated purchase) — so Plan 04-03 can drop straight into HTTP wiring + cross-refresh indexes without a fixture-creation context switch.

## What Was Built

### src/finance.lua (NEW — 57 lines)

`M_finance.parse_transaction(raw)` — normalises one Zettle Finance API record into a typed Lua table `{ kind, amount, timestamp_iso, timestamp_posix, originatingTransactionUuid }`. Returns nil on non-table input, out-of-filter `originatorTransactionType` (only `PAYMENT` / `PAYMENT_FEE` / `PAYOUT` pass per RESEARCH §1.3 — `ADJUSTMENT`, `CASHBACK`, `FROZEN_FUNDS`, `INVOICE_*`, `PAYMENT_PAYOUT`, `FAILED_PAYOUT`, `ADVANCE*` all silently filtered), missing `originatingTransactionUuid` / `timestamp` / `amount`, or unparseable timestamp.

Reuses Phase-3's `_parse_iso8601_utc` via the new `M_mapping.parse_iso8601_utc` public wrapper — preserves the D-02 no-require()-of-siblings invariant.

Module-local constant `PHASE4_FILTER_TYPES` is the canonical whitelist; mitigates T-04-W1-01 (Tampering — unknown types silently passing through).

`M_finance.fetch / fetch_all / fetch_account_state` are deferred to Plan 04-03 (HTTP-bound functions arrive with the Q3 probe close-out).

### src/pagination.lua extension

`M_pagination.offset_iterate(fetch_page_fn, initial_params)` — sibling iterator for the Finance API. The Phase-3 cursor iterator `M_pagination.iterate` is **byte-identical** (D-48 enforcement: only additions, no edits inside the cursor iterator's body).

Termination per RESEARCH §1.6: loop ends when `#page.data == 0` OR `#page.data < params.limit`. Reuses the module-level `MAX_PAGES = 50` guard, the caller-table-copy invariant, `M_errors.from_http_status` routing (D-43), and the German `error.network` strings — all byte-identical to the cursor iterator. Defensive defaults: missing `offset` -> 0, missing `limit` -> 1000 (RESEARCH §1.3).

### src/mapping.lua extension — 4 new mappers + 3 public wrappers + opts extension

**Public wrappers** (so M_finance + Plan-04-03 entry-layer can reuse without require()-of-siblings):
- `M_mapping.parse_iso8601_utc(s)` — exposes the private `_parse_iso8601_utc`
- `M_mapping.to_berlin_local_time(utc_posix)` — exposes the private DST converter
- `M_mapping.berlin_local_date(iso_ts)` — Pitfall-4 helper: Berlin-local YYYY-MM-DD string of a UTC timestamp (clusters fees correctly across UTC midnight)

**New public mappers** (all pure-logic, no I/O):
- `M_mapping.fee_to_transaction(fee_record, originating_purchase)` (FEE-01) — `transactionCode = "zettle:fee:" .. originatingTransactionUuid`; purpose cites originating purchaseNumber via German "Gebühr für Beleg #N" line; falls back to "Beleg #?" when purchase nil; booked=true.
- `M_mapping.fee_aggregate_to_transaction(fees_for_date, date_iso, count)` (FEE-03 / D-49) — `transactionCode = "zettle:fee:aggregate:" .. YYYY-MM-DD` (the stable daily-aggregate idempotency anchor per D-49 once-aggregated-always-aggregated invariant); German purpose text "Tagesaggregat — N Einzelgebühren — Detail-Verknüpfung nicht verfügbar"; nil on malformed `date_iso`.
- `M_mapping.payout_to_transaction(payout_record)` (PAYOUT-01/02/03) — `transactionCode = "zettle:payout:" .. originatingTransactionUuid` (PAYOUT records carry their own UUID as `originatingTransactionUuid` per RESEARCH §3.4); name = "Auszahlung an Bankkonto" (PAYOUT-02); bookingDate = Berlin local of `payout.timestamp` (PAYOUT-03); `valueDate = bookingDate` (the PAYOUT IS the settlement event — RESEARCH §3.4); booked=true.
- `M_mapping.promote_to_booked(txn, valueDate_posix_local)` (D-56) — pure mutator that sets `booked=true` + `valueDate`; `transactionCode` UNCHANGED so MoneyMoney's dedup updates the existing row in place. Idempotent. No-op on non-table input.

**Backwards-compatible extension**:
- `M_mapping.refund_to_transaction(p, opts)` — when `opts.original_receipt` is non-nil truthy, refund purpose cites that receipt number ("Rückerstattung zu Beleg #4001"). When `opts` is nil OR `opts.original_receipt` is nil, falls through to the Phase-3 D-32 UUID fallback (cites `refundsPurchaseUUID1`). Existing Phase-3 callers passing only `p` continue to work byte-identically — verified by the existing Phase-3 specs which all pass after this plan.

### src/i18n.lua — 12 new keys (de + en parity)

German strings are normative; English is the technical fallback per I18N-03.

| Key | German | English |
|---|---|---|
| `account.name.fee` | "Gebühr" | "Fee" |
| `account.name.fee_aggregate` | "PayPal POS Transaktionsgebühren" | "PayPal POS Transaction Fees" |
| `account.name.payout` | "Auszahlung an Bankkonto" | "Payout to Bank Account" |
| `account.purpose.fee_label` | "Gebühr" | "Fee" |
| `account.purpose.fee_for_receipt` | "Gebühr für Beleg #%s" | "Fee for receipt #%s" |
| `account.purpose.fee_aggregate` | "Tagesaggregat — %d Einzelgebühren — Detail-Verknüpfung nicht verfügbar" | "Daily aggregate — %d individual fees — per-sale linkage unavailable" |
| `account.purpose.payment_method.kontaktlos` | "kontaktlos" | "contactless" |
| `account.purpose.payment_method.chip` | "Chip" | "Chip" |
| `account.purpose.payment_method.swipe` | "Magnetstreifen" | "Magstripe" |
| `account.purpose.payment_method.ecommerce` | "Online" | "Online" |
| `account.purpose.payment_method.manual` | "Manuell" | "Manual" |
| `account.purpose.payment_method.unknown` | "unbekannt" | "unknown" |

UTF-8 byte escapes used for umlauts and the em-dash (U+2014) per Phase-3 convention. Existing Phase-3 keys are byte-identical.

### Manifest consolidation

- `tools/manifest.txt` — inserted `finance` between `purchases` and `mapping`; removed `payouts` + `balance` (the Phase-1 stub modules — both were 4-line empty-table assignments with no external references).
- `src/webbanking_header.lua` — added `M_finance = {}`; removed `M_payouts = {}` + `M_balance = {}`.
- `src/balance.lua` + `src/payouts.lua` — DELETED (consolidated into `src/finance.lua` per RESEARCH §Pitfall 10).
- `.luacheckrc` globals updated: + `M_finance`, − `M_payouts`, − `M_balance`.

### Fixtures (13 new/regenerated)

Under `spec/fixtures/finance/` (10 NEW):
- `finance_empty.json` — empty `data: []`
- `finance_single_page.json` — 1 PAYMENT + 1 PAYMENT_FEE (shared originatingTransactionUuid) + 1 PAYOUT
- `finance_multi_page_1.json` — 5 deterministic records (exactly `limit=5` in the offset_iterate Test 2)
- `finance_multi_page_2.json` — 2 records (short page; terminates the loop)
- `finance_payment_with_fee_linkage.json` — PAYMENT + PAYMENT_FEE sharing `originatingTransactionUuid = cccccccc-cccc-cccc-cccc-cccccccccccc` (joins to `payments[1].uuid` in the matching purchase fixture)
- `finance_payment_fee_unlinked.json` — orphan PAYMENT_FEE for D-49 aggregate fallback
- `finance_payout.json` — single PAYOUT, negative amount
- `finance_payment_and_payout_for_promotion.json` — PAYMENT + later PAYOUT (D-56 promotion to-be-tested in Plan 04-03)
- `finance_balance_liquid.json` — `{ data: { totalBalance: 12345, currencyId: "EUR" } }`
- `finance_balance_preliminary.json` — `{ data: { totalBalance: 678, currencyId: "EUR" } }`

Under `spec/fixtures/purchases/` (2 NEW + 1 regenerated):
- `purchase_vat_split_19_7.json` — `groupedVatAmounts: { "19.0": 318, "7.0": 140 }` (decimal-string keys per RESEARCH §5.1)
- `purchase_refund_with_original_in_page.json` — TWO entries: original sale (purchaseNumber=4001) + its refund on the same `purchases[]` array (REF-02 in-window lookup)
- `purchase_page_with_payments_for_fee_join.json` — purchase with `payments[1].uuid = cccccccc-cccc-cccc-cccc-cccccccccccc` (matches `finance_payment_with_fee_linkage.json` for the FEE-01 end-to-end join)
- `purchase_with_vat_and_tip.json` (REGENERATED) — `groupedVatAmounts` key changed from `"19"` (integer-string, fixture bug per R-5) to `"19.0"` (decimal-string per real Zettle API). Phase-3 specs reading `vatAmount` top-level continue to pass byte-identically (all 26 mapping_spec Phase-3 tests confirmed GREEN post-regen).

Every finance fixture has a root `_source` field citing the canonical Zettle doc URL; deterministic synthetic UUIDs from the `11111111-...` family; explicit `currency = "EUR"` / `currencyId = "EUR"`; no PII.

### Spec coverage

| Spec file | Phase-3 pre | Plan 04-02 post | Δ |
|---|---|---|---|
| `spec/finance_parse_transaction_spec.lua` (NEW) | — | 6 | +6 |
| `spec/pagination_offset_spec.lua` (NEW) | — | 5 | +5 |
| `spec/mapping_spec.lua` | 26 | 40 | +14 |
| `spec/mapping_schema_spec.lua` | 8 | 11 | +3 |
| `spec/i18n_spec.lua` | 13 | 37 | +24 |
| **Full suite** | **203** | **255** | **+52** |

All 255 tests GREEN. Phase-3 surface preservation confirmed: 0 regressions across every Phase-3 spec (auth, build, dst_table, entry, errors, http, log_redaction, mm_mocks, pagination [Phase-3 cursor iterator], purchases, refresh_idempotency, refresh_log_redaction).

## Decisions Made

- **Sibling iterator, not modification (D-48 enforcement).** `M_pagination.iterate` (Phase-3 cursor) is byte-identical after this plan — only additions to `src/pagination.lua` (the new `offset_iterate` sibling is appended below the existing function). Verified by `git diff HEAD~3 src/pagination.lua` showing no `-` lines inside the cursor iterator body.

- **Public wrappers for cross-module helper reuse.** `M_mapping.parse_iso8601_utc`, `M_mapping.to_berlin_local_time`, and `M_mapping.berlin_local_date` exposed so `M_finance.parse_transaction` and the Plan-04-03 entry-layer can reuse Phase-3's parsers + DST converter without violating the D-02 no-require()-of-siblings invariant. The smaller-change alternative (duplicating the parser inside `src/finance.lua`) was rejected because it would break idempotency across phases — any future fix to `_parse_iso8601_utc` would need to be applied twice.

- **transactionCode for fees and payouts derived from `originatingTransactionUuid`.** Finance API records have no `uuid` field of their own — only `originatingTransactionUuid` (RESEARCH §1.6). For PAYMENT_FEE this is the `payments[].uuid` of the originating payment leg (one-to-one cardinality per RESEARCH §3.2, so it's unique per fee). For PAYOUT it's the payout's own UUID (RESEARCH §3.4). Both yield stable, collision-free transactionCode prefixes.

- **fee_aggregate_to_transaction bookingDate uses `_parse_iso8601_utc(date_iso .. "T00:00:00Z")` directly — no extra DST offset addition.** The Phase-3 D-36 convention encodes "Berlin wall-clock seconds as if UTC" in a POSIX integer; parsing the date string as if UTC midnight gives exactly that value. Adding `_to_berlin_local_time` on top would double-count the offset and yield day=15 hour=2 instead of day=15 hour=0. Verified by the bookingDate-decomposition spec (it 16 in the new mapping_spec block).

- **Phase-1 stub consolidation.** `src/balance.lua` and `src/payouts.lua` were 4-line stubs from Phase 1 with empty module-table assignments and no external references. RESEARCH §Pitfall 10 recommends consolidating them into `src/finance.lua` (the natural home for both surfaces). Deletion + manifest + webbanking_header all changed in ONE commit (Task 2) so the build never breaks mid-step.

- **Fixture regeneration: `groupedVatAmounts` key "19" -> "19.0".** Existing Phase-3 fixture used the integer-string key form which differs from the real Zettle API (decimal-string per RESEARCH §5.1). The fixture is regenerated in this plan so Plan-04-04's META-01 VAT-line implementation tests against the real shape. Phase-3 specs are unaffected because they read `vatAmount` top-level rather than the `groupedVatAmounts` map.

## Metrics

| Metric | Value |
|---|---|
| Tasks completed | 3 / 3 |
| Files created | 16 (1 source + 2 specs + 13 fixtures) |
| Files modified | 10 (4 source + 1 build config + 1 luacheckrc + 4 spec + the regenerated fixture, counted under modified) |
| Files deleted | 2 (Phase-1 stubs) |
| Commits | 3 (all GPG-signed by FDE07046A6178E89ADB57FD3DE300C53D8E18642) |
| Spec suite | 203 -> 255 successes (+52); 0 failures; 0 errors; 0 pending |
| Luacheck | 0 warnings / 0 errors across 33 files |
| Reproducible-build SHA | `6bc796e66d5af246e891308c793e73eb690d42250f8a7dc8844812275062970a` (verified across two consecutive builds) |
| Coverage on dist/paypal-pos.lua | 100.00% across the Plan-04-02 spec set |
| Duration | ~40 minutes (single autonomous execution session) |

## Commit Log

| # | SHA | Type | Message |
|---|---|---|---|
| 1 | `24990d9` | test | `test(04-02): add Phase-4 fixtures + RED scaffolds for finance/pagination_offset specs` |
| 2 | `a75f6d7` | feat | `feat(04-02): add M_pagination.offset_iterate + consolidate manifest` |
| 3 | `c4ed80e` | feat | `feat(04-02): add M_finance.parse_transaction + 4 mapping mappers + 12 i18n keys` |

All three commits GPG-signed. No AI / Claude / Anthropic attribution anywhere in commit messages, code, comments, fixtures, or i18n strings (verified via `git log -3 --format='%B' | grep -iE 'claude|anthropic'` returning empty).

## Hand-off Notes for Plan 04-03

Plan 04-03 (Wave 2 — Finance API HTTP + cross-refresh indexes + SALE-03 promotion) inherits the following landed surfaces and can rely on them being stable:

### Available pure-logic primitives (use directly, do NOT re-implement)

- `M_finance.parse_transaction(raw)` — call on every Finance API record before consuming `kind / amount / timestamp_posix / originatingTransactionUuid`.
- `M_pagination.offset_iterate(fetch_page_fn, initial_params)` — drive the Finance API multi-page fetch from `M_finance.fetch_all`. Default `limit=1000` per RESEARCH §1.3.
- `M_mapping.fee_to_transaction(fee, originating_purchase)` — call per linked fee.
- `M_mapping.fee_aggregate_to_transaction(fees, date_iso, count)` — call per unlinked-fee daily aggregate.
- `M_mapping.payout_to_transaction(payout_record)` — call per PAYOUT.
- `M_mapping.promote_to_booked(sale_txn, payout_timestamp_posix)` — call after the cross-refresh lookup matches a sale's payment leg to a covered PAYOUT.
- `M_mapping.refund_to_transaction(refund_purchase, { original_receipt = N })` — call with the lookup result from the `purchases_by_uuid` index.
- `M_mapping.berlin_local_date(iso_ts)` — call to compute the clustering key for the D-49 fee aggregate-fallback.
- `M_mapping.parse_iso8601_utc(s)` + `M_mapping.to_berlin_local_time(utc)` — Phase-3 helpers exposed for entry-layer use.

### Fixtures already on disk (Plan 04-03 specs consume them directly)

- All 10 finance fixtures + 3 new purchase fixtures land in this plan. Plan 04-03 does NOT need to author any new fixture beyond possibly a small `purchase_page_with_payments_for_fee_join` extension if entry-layer integration discovers a missing edge case.

### Still-RED specs that Plan 04-03 / 04-04 / 04-05 close

The full `busted spec/` is currently 255/0/0/0 — there are no still-RED specs as of this plan's close. The Plans listed below are net-new code, not unblocking-of-existing-RED:

- Plan 04-03 will author `spec/finance_fetch_spec.lua`, `spec/finance_fetch_all_spec.lua`, `spec/finance_fetch_account_state_spec.lua` (M_finance HTTP layer), and extend `spec/entry_spec.lua` + `spec/refresh_idempotency_spec.lua` for D-58 (promote-to-booked across refreshes) + D-50 (refund-in-window lookup) + D-49 (fee linkage + aggregate fallback).
- Plan 04-04 will extend `_format_purpose` for META-01 (per-rate VAT) + SALE-07 (card-tail), consuming the 12 new i18n keys this plan landed.
- Plan 04-05 will add `spec/meta_no_tax_classification_spec.lua` (META-03 forbidden-strings invariant).

### Things to NOT redo in Plan 04-03

- Do not modify `M_pagination.iterate` (Phase-3 cursor iterator — locked under D-48).
- Do not duplicate the ISO-8601 parser inside src/finance.lua — call `M_mapping.parse_iso8601_utc` (the canonical Phase-3 parser is shared via the public wrapper).
- Do not introduce a `LocalStorage` write for D-49 fee-aggregate dedup unless Yves explicitly approves Option A (CONTEXT D-49). The recommended Option B (cluster-by-date per refresh) is already supported by `fee_aggregate_to_transaction`'s deterministic `transactionCode = "zettle:fee:aggregate:" .. YYYY-MM-DD` anchor — no persistent state needed unless Zettle linkage starts flipping per-day (Phase-5 measurement task).
- Do not author additional finance fixtures unless integration discovers a real gap — the 10 landed here cover empty / single-page / multi-page / payment+fee linkage / unlinked fee / payout / payment+payout-for-promotion / balance-liquid / balance-preliminary, which is the full RESEARCH §8.2 inventory.

### Open Yves-blockers (carried from Phase-04 CONTEXT)

- **Q3** Finance API host live verification — Plan 04-01 probe still pending Yves' execution against sandbox. The recommendation locked in CONTEXT D-46 (`finance.izettle.com`) is independently confirmed in RESEARCH §1.1 from the official OpenAPI spec, so the probe is a confirmation step rather than an exploratory one. If Q3 fails (different host / different path), Plan 04-03 replans before HTTP wiring.
- **D-49** Fee-fallback contract (Option A vs Option B; Pay/Compliance) — Plan 04-02 ships the pure-logic surface that supports either option. The entry-layer wiring in Plan 04-03 picks one. Research recommendation: Option B for v0.2.0; revisit in Phase 5 if real users see linkage flipping.
- **D-55** META-03 forbidden-strings list completeness (Pay/Compliance) — does not affect Plan 04-02 (no new META-03-relevant strings were added; the 12 new i18n strings are bookkeeping-language only: "Gebühr", "Auszahlung an Bankkonto", "Tagesaggregat", etc.). Plan 04-05 adds the gating spec once Yves locks the list.

## Self-Check: PASSED

- All claimed files exist on disk (verified via `ls` of each path in the frontmatter `key_files`).
- All 3 commit SHAs (`24990d9`, `a75f6d7`, `c4ed80e`) found in `git log --oneline --all` and each carries `%G? = G` (GPG-signed by maintainer's key).
- Full `busted spec/` reports `255 successes / 0 failures / 0 errors / 0 pending`.
- `./.luarocks/bin/luacheck .` reports `Total: 0 warnings / 0 errors in 33 files`.
- `lua tools/build.lua --verify` reports `OK: reproducible (sha256: 6bc796e66d5af246e891308c793e73eb690d42250f8a7dc8844812275062970a)` across two consecutive runs.
- `git log -3 --format='%B' | grep -iE 'claude|anthropic'` returns empty (no AI attribution).
- Phase-3 surface byte-identically preserved: existing Phase-3 specs (mapping_spec Phase-3 portion, refresh_idempotency_spec, refresh_log_redaction_spec, etc.) all GREEN.
