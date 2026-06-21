---
phase: 04-enrichment-refunds-fees-payouts
plan: "04"
subsystem: mapping
tags: [wave-3, pure-logic, mapping, vat, card-tail, i18n, mvp]
dependency_graph:
  requires: [04-02]
  provides:
    - "M_mapping._format_purpose extended: per-rate German VAT block (D-53)"
    - "M_mapping._format_purpose extended: card-brand + entry-mode tail line (D-57)"
    - "Phase-3 surface preservation snapshot gate (purchase_simple_sale byte-identical)"
  affects: [04-05]
tech_stack:
  added:
    - "Module-local ENTRY_MODE_MAP table in src/mapping.lua — API cardPaymentEntryMode enum -> i18n key suffix (CONTACTLESS_EMV/ICC/MSR/ECOMMERCE/MANUAL; unknown -> 'unknown' fallback)"
    - "Per-rate VAT emission pattern in _format_purpose — pairs() walk of groupedVatAmounts -> typed accumulator -> table.sort descending -> '<rate>% MwSt: <amount_de> EUR' per rate"
  patterns:
    - "Defensive tonumber on JSON object keys — accepts both '19.0' decimal-string AND '19' integer-string forms (R-5 mitigation against the Phase-3 fixture-bug that wrote integer-string keys)"
    - "Whole-number-rate detection via `e.rate == math.floor(e.rate)` to drop the `.0` suffix in display (19% not 19.0%) while preserving fractional rates (7.5%)"
    - "Additive _format_purpose extension preserving Phase-3 byte-identity for no-multi-rate + no-card-metadata fixtures (snapshot test in spec/mapping_spec.lua is the gate)"
    - "Card-tail block placed between Netto and Beleg lines per Claude's-Discretion / RESEARCH §6.3 (separate line, greppable, no Schema schema/Mojibake risk)"
key_files:
  created:
    - spec/fixtures/purchases/purchase_with_card_metadata_kontaktlos.json
    - spec/fixtures/purchases/purchase_umlauts_purpose.json
  modified:
    - src/mapping.lua
    - spec/mapping_spec.lua
decisions:
  - "Per-rate VAT lines use literal `EUR` suffix (not `€`) to differentiate the per-rate path visually from the Phase-3 single-line `MwSt: <amount> €` fallback — also makes grepping CI logs trivial without UTF-8 escape juggling"
  - "ENTRY_MODE_MAP unknown-value fallback returns the literal string `'unknown'` keyed into `account.purpose.payment_method.unknown` (DE='unbekannt', EN='unknown') — locked at planner level to avoid silent locale drift if a new entry mode appears in Zettle"
  - "Card-tail block reads payments[1] only (single-payment-per-purchase invariant from Phase 3 — split tenders not yet supported); when payments empty or attributes absent, the line is omitted ENTIRELY rather than emitting `Zahlart: unbekannt (unbekannt)` noise (RESEARCH §6.3)"
  - "Phase-3 surface preservation locked at planner level via byte-identical snapshot assertion for purchase_simple_sale — expected literal: `Brutto: 5,00 €\\nNetto: 5,00 €\\nBeleg #1001` — any regression here fails the gate"
  - "Integer-string key defense (R-5): tonumber('19') and tonumber('19.0') both return 19, so the per-rate branch accepts both forms; mitigates Plan-04-02's fixture-bump moving keys from '19' to '19.0' without breaking any legacy fixture or test asserting on integer keys"
metrics:
  duration: "~12 minutes"
  completed: "2026-06-21"
  tasks_completed: 2
  files_created: 2
  files_modified: 2
  files_deleted: 0
  commits: 2
---

# Phase 04 Plan 04: Wave-3 Mapping Enrichment Summary

Wave-3 extends `src/mapping.lua _format_purpose` with two additive enrichments that round out the bookkeeping picture for a German PayPal POS merchant: per-rate German VAT lines (D-53 / META-01) for mixed-rate baskets, and the card-brand + entry-mode tail line (D-57 / SALE-07) so the merchant can see at a glance whether the card was tapped, dipped, or swiped. Both extensions are pure-logic edits to the existing formatter — no new public API surface — and the wave ran in parallel-safe isolation from Plan 04-03 (the only shared dependency is Plan 04-02's i18n key additions, which were already on disk).

## What Was Built

### src/mapping.lua — _format_purpose extended ADDITIVELY (+ ENTRY_MODE_MAP)

**Module-local `ENTRY_MODE_MAP`** (above `_format_purpose`): maps API `cardPaymentEntryMode` enum to i18n key suffix:

| API enum value     | i18n key suffix | DE display     | EN display     |
| ------------------ | --------------- | -------------- | -------------- |
| `CONTACTLESS_EMV`  | `kontaktlos`    | `kontaktlos`   | `contactless`  |
| `ICC`              | `chip`          | `Chip`         | `Chip`         |
| `MSR`              | `swipe`         | `Magnetstreifen` | `Magstripe`  |
| `ECOMMERCE`        | `ecommerce`     | `Online`       | `Online`       |
| `MANUAL`           | `manual`        | `Manuell`      | `Manual`       |
| _(anything else)_  | `unknown`       | `unbekannt`    | `unknown`      |

**Per-rate VAT block** (replaces the Phase-3 single-MwSt branch when `groupedVatAmounts` has 2+ entries):

```text
Brutto: 20,00 €
19% MwSt: 3,18 EUR        <- new: per-rate, sorted descending
7% MwSt: 1,40 EUR         <- new: per-rate, sorted descending
Netto: 15,42 €
Beleg #3001
```

When `groupedVatAmounts` has 0 or 1 entries, the block falls through to Phase-3's existing single MwSt line (HI-01 `~= 0` check preserved so negative refund VAT still renders). The `tonumber(k)` parse accepts both `"19.0"` decimal-string (real API form per RESEARCH §5.1) AND `"19"` integer-string (R-5 defensive against legacy fixture form). Whole-number rates drop the `.0` (`19%` not `19.0%`) via `e.rate == math.floor(e.rate)`; fractional rates preserved (`7.5%` via `string.format("%g")`).

**Card-brand + entry-mode tail line** (inserted between Netto and Beleg per RESEARCH §6.3):

| `payments[1].attributes` shape           | Tail line emitted                          |
| ---------------------------------------- | ------------------------------------------ |
| `cardType=VISA` + `entryMode=CONTACTLESS_EMV` | `Zahlart: Visa (kontaktlos)`          |
| `cardType=VISA` only                     | `Zahlart: Visa`                            |
| `entryMode=ICC` only                     | `Zahlart: Kartenzahlung (Chip)`            |
| neither present                          | _(line OMITTED — no noise)_                |
| `cardType=DISCOVER` (unknown brand)      | `Zahlart: Discover (...)` _(Phase-3 BRAND_MAP fallback: capitalize literal)_ |
| `entryMode=SOMETHING_NEW` (unknown mode) | `Zahlart: Visa (unbekannt)` _(ENTRY_MODE_MAP fallback to 'unknown' i18n key)_ |

Brand display reuses the existing Phase-3 `BRAND_MAP` (`VISA→Visa`, `MASTERCARD→Mastercard`, etc.) byte-identically — no code duplication. The chained-access guards (`type(p.payments) == "table"` → `type(first_payment) == "table"` → `type(attrs) == "table"` → string + non-empty check) are defensive against all the shapes Zettle has been observed to emit on edge cases.

### spec/fixtures/purchases/purchase_with_card_metadata_kontaktlos.json (NEW)

Single purchase with `cardType=VISA`, `cardPaymentEntryMode=CONTACTLESS_EMV`, `maskedPan=411111******1111`, `amount=995`, `vatAmount=159`, deterministic UUID `40404040-...-404040404040`, purchaseNumber 5001, timestamp `2026-06-15T11:00:00.000+0000`, empty `groupedVatAmounts`. The Plan 04-04 SALE-07 happy-path spec consumes this fixture and asserts `_format_purpose` emits `Zahlart: Visa (kontaktlos)` between Netto and Beleg.

### spec/fixtures/purchases/purchase_umlauts_purpose.json (NEW)

Single purchase with `userDisplayName="Beispiel-Café"` (UTF-8 `é = \xc3\xa9`), empty payments, empty `groupedVatAmounts`. Purpose-of-fixture: gate UTF-8 round-trip through dkjson — the Plan 04-04 META-01 round-trip spec decodes the fixture and asserts `Café` survives byte-identically. Defensive against future locale/encoding regressions in any of: dkjson, the build amalgamator, or the test harness's file-reading path.

### spec/mapping_spec.lua — 11 new it() cases

All 11 cases live under the existing top-level `describe("M_mapping", ...)` block. Count: was 40 (Phase-3 + Plan 04-02), now 51.

**META-01 (5 cases — per-rate VAT):**
1. Multi-rate (19%+7%) sorted descending — uses `purchase_vat_split_19_7.json`
2. Single-rate fallback to Phase-3 line — uses `purchase_with_vat_and_tip.json`
3. Empty-map fallback to Phase-3 line — inline record with `vatAmount=159` + `groupedVatAmounts={}`
4. Integer-string key defense (`"19"` accepted equivalently to `"19.0"`) — inline record per R-5
5. Negative VAT on refund record (`-0,57 EUR`) — inline refund record with negative `groupedVatAmounts`

**SALE-07 (4 cases — card-brand + entry-mode tail):**
6. Both present → `Zahlart: Visa (kontaktlos)` — uses `purchase_with_card_metadata_kontaktlos.json`
7. Only `cardType` present → `Zahlart: Visa` (no parens) — inline record
8. Both absent → line OMITTED — uses `purchase_simple_sale.json`
9. Unknown `cardPaymentEntryMode` → `Zahlart: Visa (unbekannt)` — inline record

**Phase-3 surface preservation + UTF-8 (2 cases):**
10. `purchase_simple_sale` byte-identical to Phase-3 expected string `"Brutto: 5,00 €\nNetto: 5,00 €\nBeleg #1001"` — RESEARCH §Pitfall 8
11. UTF-8 round-trip — `Beispiel-Café` survives dkjson decode + `_format_purpose` formats successfully

## Verification

### Reproducible build

```text
$ lua tools/build.lua && lua tools/build.lua --verify
Built dist/paypal-pos.lua
OK: reproducible (sha256: b26bcda7c32d2718ead9113a47646015c81f863ba6488b0efce3e763b2135b93)
```

### Plan-scoped spec suite (Plan 04-04 verification allow-list)

```text
$ ./.luarocks/bin/busted spec/mapping_spec.lua spec/mapping_schema_spec.lua \
    spec/dst_table_spec.lua spec/i18n_spec.lua spec/finance_parse_transaction_spec.lua \
    spec/pagination_offset_spec.lua spec/pagination_spec.lua spec/purchases_spec.lua \
    spec/entry_spec.lua spec/refresh_log_redaction_spec.lua spec/auth_spec.lua \
    spec/http_spec.lua spec/errors_spec.lua spec/mm_mocks_spec.lua spec/build_spec.lua
248 successes / 0 failures / 0 errors / 0 pending
```

### luacheck

```text
$ ./.luarocks/bin/luacheck src/mapping.lua spec/mapping_spec.lua
Checking src/mapping.lua                          OK
Checking spec/mapping_spec.lua                    OK
Total: 0 warnings / 0 errors in 2 files
```

### Phase-3 surface preservation gate

Snapshot test `M_mapping Phase-3 surface preservation: purchase_simple_sale produces byte-identical purpose to Phase 3` is GREEN. The expected literal is `Brutto: 5,00 €\nNetto: 5,00 €\nBeleg #1001` (3 lines). Any future edit to `_format_purpose` that perturbs this fixture's output will trip the snapshot — locked at planner level.

### Eyeball confirmation (manual smoke)

```text
===== simple_sale (Phase-3 baseline) =====
Brutto: 5,00 €
Netto: 5,00 €
Beleg #1001
===== vat_split_19_7 (per-rate sorted descending) =====
Brutto: 20,00 €
19% MwSt: 3,18 EUR
7% MwSt: 1,40 EUR
Netto: 15,42 €
Beleg #3001
===== with_card_metadata_kontaktlos (card tail) =====
Brutto: 9,95 €
MwSt: 1,59 €
Netto: 8,36 €
Zahlart: Visa (kontaktlos)
Beleg #5001
```

## Out-of-Scope Pre-Existing Failures

`spec/finance_spec.lua` (8 failures, 17 errors) and `spec/finance_account_state_spec.lua` (3 failures, 5 errors) call `M_finance.fetch_all` and `M_finance.fetch_account_state` — both still RED on this branch because Plan 04-03 has not yet landed (Plan 04-03 is the parallel-wave HTTP wiring). Per the Plan 04-04 success criteria these belong to Plan 04-03 and are explicitly out of scope. `spec/mapping_spec.lua` itself is 100% GREEN (51/51); the failing finance specs do not transitively load `src/mapping.lua`'s mutated surface.

`spec/finance_account_state_spec.lua` carries 1 pre-existing luacheck warning (also Plan 04-03 territory). `src/mapping.lua` and `spec/mapping_spec.lua` are luacheck-clean.

## Hand-off to Plan 04-05

Plan 04-05 (META-03 forbidden-strings invariant + extended idempotency D-58 + extended log-redaction prefix gate) is the next wave. Its META-03 spec walks `src/*.lua` for forbidden English-only strings; the Plan 04-04 additions follow the locked-i18n-key convention (`account.purpose.payment_method.*`) so the META-03 spec should not flag them. The new `Zahlart:` literal is German; the `EUR` literal is currency-neutral. No new English-only strings landed in src/mapping.lua.

Plan 04-05's extended-idempotency spec will assert that `transactionCode` prefixes are unique across `zettle:sale:`, `zettle:refund:`, `zettle:fee:`, `zettle:fee:aggregate:`, and `zettle:payout:` — Plan 04-04 did NOT add any new transactionCode prefix (the _format_purpose extensions are purpose-text-only, no transactionCode change), so the idempotency gate remains a Plan 04-02/04-03 surface gate.

## Files Touched

- **Created:** `spec/fixtures/purchases/purchase_with_card_metadata_kontaktlos.json`, `spec/fixtures/purchases/purchase_umlauts_purpose.json`
- **Modified:** `src/mapping.lua` (+80 lines / −5 lines additive — ENTRY_MODE_MAP table + per-rate VAT branch + card-tail block), `spec/mapping_spec.lua` (+11 it() cases at end of describe block, no Phase-3 / Plan 04-02 tests altered)
- **Untouched (per scope):** `src/finance.lua`, `src/entry.lua`, `src/pagination.lua`, `src/purchases.lua`, `src/i18n.lua`, `src/webbanking_header.lua`, `tools/manifest.txt`, `CHANGELOG.md`, `README.md`, `docs/adr/*`

## Commits

- `d3d1311` — `test(04-04): add fixtures + RED scaffolds for META-01 per-rate VAT + SALE-07 card tail + Phase-3 snapshot`
- `08207a4` — `feat(04-04): per-rate VAT lines + card-brand+entry-mode tail in _format_purpose (META-01, SALE-07, D-53, D-57)`

Both commits GPG-signed by `FDE07046A6178E89ADB57FD3DE300C53D8E18642`; no AI/Claude attribution; Conventional Commits prefix `(04-04)`.

## Self-Check: PASSED

- Fixtures exist: `spec/fixtures/purchases/purchase_with_card_metadata_kontaktlos.json` ✓, `spec/fixtures/purchases/purchase_umlauts_purpose.json` ✓
- Commits exist: `d3d1311` ✓, `08207a4` ✓
- `lua tools/build.lua --verify` reports reproducible ✓ (sha256: `b26bcda7c32d2718ead9113a47646015c81f863ba6488b0efce3e763b2135b93`)
- `spec/mapping_spec.lua` 51/51 GREEN ✓
- Plan-scoped allow-list 248/248 GREEN ✓
- `src/mapping.lua` + `spec/mapping_spec.lua` luacheck-clean ✓
- Phase-3 surface preservation snapshot GREEN ✓
- Both commits GPG-signed; no AI attribution ✓
