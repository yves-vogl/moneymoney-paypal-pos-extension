---
phase: 04-enrichment-refunds-fees-payouts
plan: "05"
subsystem: spec-gates
tags: [wave-4, invariant-gates, idempotency, log-redaction, meta-03, sec-03, mvp]
dependency_graph:
  requires: [04-02, 04-03, 04-04]
  provides:
    - "META-03 forbidden-strings invariant gate (13 phrases, D-55 LOCKED)"
    - "META-02 zero-suppression dedicated regression gate (D-54 promotion)"
    - "META-01 zero-rate edge-case gate (RESEARCH §5.3)"
    - "D-58 idempotency contract: SALE-03 promotion / payout-only / per-sale fee / aggregate fee — all byte-identical across refreshes"
    - "D-38 extended prefix gate: closed set of 5 allowed transactionCode prefixes (zettle:sale:, zettle:refund:, zettle:fee:, zettle:fee:aggregate:, zettle:payout:)"
    - "SEC-03 / D-45 Bearer redaction extended to cover Finance API responses (5 fixture cycles)"
  affects: [04-06]
tech_stack:
  added: []
  patterns:
    - "Plain-text find with 4th arg true (RESEARCH §7.2) for forbidden-phrase scanning — avoids Lua-pattern escape complications with hyphens and accented characters (DATEV-fähig)"
    - "io.popen('ls src/*.lua') + io.open:read('*a') walk pattern for source-tree byte scanning"
    - "Closed-set prefix-gate assertion: ALLOWED_PREFIXES table iterated against every emitted transactionCode; failure surfaces the violating code in the error message"
    - "Union-of-refreshes pattern for exercising all 5 allowed prefixes across a single test (4 refresh cycles aggregated into a single transactions array)"
    - "Spec-only `queue_full_response_set(purchase, finance)` helper mirroring the Plan-04-03 four-response RefreshAccount queueing infrastructure — local to each describe so cross-spec coupling stays zero"
key_files:
  created:
    - spec/meta_no_tax_classification_spec.lua
    - spec/meta_purpose_lines_spec.lua
  modified:
    - spec/refresh_idempotency_spec.lua
    - spec/refresh_log_redaction_spec.lua
    - spec/fixtures/finance/finance_payment_and_payout_for_promotion.json
decisions:
  - "META-03 forbidden phrases LOCKED at the 13-entry D-55 list verbatim; any future amendment requires reopening D-55 explicitly (not a silent override in a downstream plan)"
  - "META-03 spec scans BOTH src/*.lua AND the built dist/paypal-pos.lua artifact — the artifact is the authoritative shipped surface, so any build-time injection (e.g., a future preamble change) is also gated"
  - "META-02 / META-01 zero-edge tests live in their own spec file (spec/meta_purpose_lines_spec.lua) per CONTEXT D-54, but the equivalent assertions in spec/mapping_spec.lua are RETAINED — duplication is intentional for regression-gating clarity, not eliminated"
  - "Plan-04-02's finance_payment_and_payout_for_promotion.json fixture regenerated in this plan to use originatingTransactionUuid=cccccccc-...-cccccccccccc (matching payments[0].uuid in purchase_page_with_payments_for_fee_join.json) instead of the unused eeeeeeee-... UUID — chosen over creating a sibling _via_cccc.json variant because the original fixture had no other consumers (grep src/ spec/ confirmed zero references)"
  - "D-38 prefix gate is the structural enforcement against silent prefix-set growth: any future emitter (zettle:cashback:, zettle:fxAdjustment:, …) must explicitly extend ALLOWED_PREFIXES with a paired test update — the test asserts ALL 5 known prefixes appear at least once in the union of test refreshes (not just that emitted codes match SOME prefix)"
  - "SEC-03 extension walks LocalStorage AND captured prints for every Finance fixture (5 cycles) — defense-in-depth even though the redaction primitive is shared with the auth path; a Finance-only regression in M_log filtering would surface here"
  - "META-01 zero-rate suppression (sole 0% entry, value 0 → no MwSt line) PASSED on the first run against Plan 04-04's existing _format_purpose implementation; no mapping.lua patch was needed — the Phase-3 `vat ~= 0` fallback + the Plan-04-04 `#rate_entries >= 2` multi-rate gate compose correctly to suppress the line"
  - "Long-line lint: added `-- luacheck: ignore 631` to spec/refresh_idempotency_spec.lua mirroring spec/mapping_spec.lua's convention — long it() titles are intentional (they double as documentation in the failure output)"
metrics:
  duration: "~25 minutes"
  completed: "2026-06-21"
  tasks_completed: 3
  files_created: 2
  files_modified: 3
  files_deleted: 0
  commits: 3
---

# Phase 04 Plan 05: Wave-4 Invariant Gates Summary

Wave-4 lands the three load-bearing Phase-4 invariant gates that turn the implementation work from Waves 1-3 into a release-grade contract. Two new spec files (`meta_no_tax_classification_spec.lua` and `meta_purpose_lines_spec.lua`) and two extended specs (`refresh_idempotency_spec.lua` and `refresh_log_redaction_spec.lua`) bring the total Phase-4 test count to 317 successes / 0 failures / 0 errors (Phase-3 baseline 300; Wave-4 added 17 new assertions across 4 spec files). All commits GPG-signed; `lua tools/build.lua --verify` reports `OK: reproducible (sha256: d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712)`.

## What Was Built

### META-03 forbidden-strings invariant (NEW spec file)

`spec/meta_no_tax_classification_spec.lua` (99 LOC, 2 it() blocks):

- Module-local `FORBIDDEN` array holds the 13 D-55 phrases verbatim: `USt-frei`, `USt frei`, `steuerfrei`, `steuerlich`, `GoBD-konform`, `GoBD konform`, `DATEV-fähig` (UTF-8 `\xc3\xa4`), `DATEV fähig`, `VAT-exempt`, `VAT exempt`, `tax-free`, `tax exempt`, `non-taxable`.
- `scan_file(path)` opens via `io.open(_, "rb")`, reads `*a`, iterates the 13 phrases calling `content:find(phrase, 1, true)` (plain-text find per RESEARCH §7.2). Returns hit list with `(phrase, byte-offset)` — error messages cite exactly which file and which byte position contains the violation.
- it("none of src/*.lua contains a forbidden phrase") — walks `io.popen("ls src/*.lua")`, scans each file.
- it("dist/paypal-pos.lua contains no forbidden phrase (built artifact gate)") — re-invokes `lua tools/build.lua` (no-op when already built; deterministic), scans the artifact.

**Pre-flight scan outcome:** 0 violations. The Phase-3 + Plan-04-02 + Plan-04-04 i18n additions (Brutto / Netto / MwSt / Trinkgeld / Beleg / Gebühr / Auszahlung / Rückerstattung / Kartenzahlung / etc.) contain no terms from the D-55 list. No `fix(04-05):` source-side commit was needed.

### META-02 + META-01 zero-edge gates (NEW spec file)

`spec/meta_purpose_lines_spec.lua` (157 LOC, 5 it() blocks across 2 describe blocks):

| Describe | Test | Assertion |
|---|---|---|
| META-02 zero-suppression (D-54 promotion) | sum gratuityAmount==0 | `Trinkgeld` line absent in purpose |
| META-02 | payments={} | `Trinkgeld` line absent in purpose |
| META-02 | sum gratuityAmount > 0 | `Trinkgeld: 1,50 €` line present |
| META-01 zero-rate edge (RESEARCH §5.3) | sole 0% entry value 0 | no `MwSt` line at all |
| META-01 | 0% alongside 19% | both per-rate lines present, 19% before 0% (descending) |

**META-01 zero-rate suppression behavior on first run:** Plan 04-04's `_format_purpose` already satisfies the suppression contract — the `#rate_entries >= 2` guard skips the per-rate branch when only `{["0.0"]=0}` is present, and the Phase-3 fallback `if vat ~= 0` then skips emission. No `src/mapping.lua` patch was needed.

### D-58 idempotency extensions (EXTENDED `refresh_idempotency_spec.lua`)

New describe block "Phase-4 D-58 idempotency extensions" with 4 it() blocks (the Phase-3 + Plan-04-03 baseline 4 tests are unchanged):

| Case | Purchase fixture | Finance R1 | Finance R2 | Assertion |
|---|---|---|---|---|
| 1 (sale+payout_promote) | purchase_page_with_payments_for_fee_join | finance_empty | finance_payment_and_payout_for_promotion | `zettle:sale:20202020-...` byte-identical R1→R2; R1 booked=false; R2 booked=true + valueDate present |
| 2 (payout-only) | purchases_empty | finance_payout | finance_payout | `zettle:payout:dddddddd-...` stable; zero new transactionCodes R2 |
| 3 (per-sale fee linked) | purchase_page_with_payments_for_fee_join | finance_payment_with_fee_linkage | (same) | `zettle:fee:cccccccc-...` byte-identical R1→R2 |
| 4 (aggregate fee / D-49 Option B) | purchase_simple_sale | finance_payment_fee_unlinked | (same) | `zettle:fee:aggregate:2026-06-15` byte-identical R1→R2 |

**Specific transactionCodes asserted byte-identical:** `zettle:sale:20202020-2020-2020-2020-202020202020`, `zettle:payout:dddddddd-dddd-dddd-dddd-dddddddddddd`, `zettle:fee:cccccccc-cccc-cccc-cccc-cccccccccccc`, `zettle:fee:aggregate:2026-06-15`.

**Fixture regeneration:** `spec/fixtures/finance/finance_payment_and_payout_for_promotion.json` updated in place per Plan 04-05 recommendation. The Plan-04-02 fixture used `originatingTransactionUuid=eeeeeeee-...` for the PAYMENT, but no purchase fixture's payments[].uuid matched that value, making SALE-03 promotion untestable end-to-end. Regenerated to `cccccccc-...` so the existing `purchase_page_with_payments_for_fee_join.json` purchase (payments[0].uuid=`cccccccc-...`) drives the promotion lookup. Amounts adjusted to match: PAYMENT=479300 (=purchase.amount), PAYOUT=-470433 (plausible net after ~8867 fee). The PAYOUT timestamp was moved from 2026-06-03 to 2026-06-06 so it remains after the PAYMENT (2026-06-04). Zero callers of the old fixture were found via `grep -rn` across `src/` and `spec/`.

### D-38 extended prefix gate (EXTENDED `refresh_log_redaction_spec.lua`)

New describe block "D-38 extended transactionCode prefix gate (Phase-4: 5 allowed prefixes)":

- Module-local `ALLOWED_PREFIXES = { "^zettle:sale:", "^zettle:refund:", "^zettle:fee:", "^zettle:fee:aggregate:", "^zettle:payout:" }`.
- `matches_allowed_prefix(code)` returns true iff the code matches at least one prefix.
- The single it() block drives 4 sequential RefreshAccount cycles across 4 org UUIDs (linked fee, refund, aggregate fee, payout) and aggregates the result transactions into a `union` table.
- Assertion A: every transactionCode in the union matches at least one of the 5 allowed prefixes — fails with the violating code in the error message.
- Assertion B: every one of the 5 allowed prefixes appears AT LEAST ONCE in the union — guards against the closed set silently shrinking (e.g., a regression where fees stop being emitted but the test still passes because only `^zettle:sale:` codes exist).

No prefix discovered in the entry-layer output was outside the allowed set — Plan 04-03's emitters all conform to D-38.

### SEC-03 / D-45 extended Finance API redaction (EXTENDED `refresh_log_redaction_spec.lua`)

New describe block "SEC-03 / D-45 extended: Bearer redaction covers Finance API responses (RESEARCH §1.6)": 5 it() blocks, one per Finance fixture cycle (`finance_single_page`, `finance_payment_with_fee_linkage`, `finance_payout`, two cycles driven via `finance_empty` tail to exercise `finance_balance_liquid` and `finance_balance_preliminary` independently). Each cycle:

1. Seeds the non-JWT token AT-VALID.
2. Queues the full Plan-04-03 four-response tuple including the named Finance fixture.
3. Runs `RefreshAccount`.
4. Walks `Mocks._captured_prints` and asserts no `eyJ[A-Za-z0-9_-]+` JWT-shape and no literal `Bearer eyJ` substring.
5. Walks LocalStorage recursively via the existing `walk_storage` helper and asserts no JWT-shape value anywhere.

**Outcome:** all 5 cycles GREEN — no eyJ and no `Bearer eyJ` in any captured surface across any Finance fixture. The Phase-3 redaction primitives in `src/log.lua` carry over correctly to the Phase-4 Finance call paths added by Plan 04-03.

## Tasks Completed

| # | Task | Commit | Files |
|---|---|---|---|
| 1 | META-03 forbidden-strings invariant spec | `8f3455c` | spec/meta_no_tax_classification_spec.lua (NEW) |
| 2 | META-02 zero-suppression + META-01 zero-rate edge spec | `d52e8df` | spec/meta_purpose_lines_spec.lua (NEW) |
| 3 | Extend idempotency (D-58 4 cases) + log-redaction (D-38 prefix gate + SEC-03 Finance API) | `0803ed2` | spec/refresh_idempotency_spec.lua, spec/refresh_log_redaction_spec.lua, spec/fixtures/finance/finance_payment_and_payout_for_promotion.json |

## Test Count

| Phase | Suite count |
|---|---|
| Phase-3 baseline (entry of Phase 4) | 300 / 0 / 0 / 0 |
| Plan 04-05 additions | +17 (META-03: 2, META-02+01: 5, D-58: 4, D-38: 1, SEC-03: 5) |
| **Phase-4 cumulative after Plan 04-05** | **317 / 0 / 0 / 0** |

`./.luarocks/bin/busted spec/` → `317 successes / 0 failures / 0 errors / 0 pending`. Runtime ~6s on the maintainer's machine.

## Coverage (src/)

Coverage measurement against the unconcatenated `src/` modules per the project test convention. Phase-3 landed 99.23%; Phase 4 target was ≥95% on new code. Spec-only plan (no src/ additions), so coverage delta is zero on net new code. Full coverage run not re-executed this plan — coverage will be re-measured in Plan 04-06 when ROADMAP / STATE updates land.

## Reproducible Build

`lua tools/build.lua --verify` reports `OK: reproducible (sha256: d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712)`. SHA unchanged from Plan 04-04 (this plan is spec-only — no src/ surface changed).

## Deviations from Plan

None on automation. One source-line note worth recording explicitly:

- **luacheck 631 (line too long)** surfaced 3 warnings on spec/refresh_idempotency_spec.lua's new it() titles. Fixed by adding `-- luacheck: ignore 631` mirroring spec/mapping_spec.lua's convention. Long it() titles double as failure-output documentation; shortening them would degrade error legibility. Not tracked as a Rule-1/2/3 deviation — pure style enforcement.

## Authentication Gates

None. All work is local spec-side; no network / no MoneyMoney credential UI / no Zettle API interaction.

## Known Stubs

None. This plan adds gating tests against existing implementation; no placeholder UI or stub data flows introduced.

## Threat Surface Scan

No new attack surface. The threat register entries T-04-W4-01 / T-04-W4-02 / T-04-W4-03 / T-04-W4-04 / T-04-W4-05 from PLAN.md are all `mitigate` or `accept` and all corresponding spec assertions GREEN.

No `threat_flag:` entries to surface.

## Yves-Blocker Status

| Blocker | Source | Surfaced in | Resolution |
|---|---|---|---|
| Q3 (PRD-vs-CONTEXT scope drift) | Phase-4 kickoff | Plan 04-01 | Surfaced for review (recommendation: reject scope) |
| D-49 Option A vs B (per-refresh aggregate fee dedup) | RESEARCH §3.5 | Plan 04-03 | Yves confirmed Option B 2026-06-21 (per-refresh date clustering, no persistent state); IMPLEMENTED and GATED by D-58 case 4 in this plan |
| D-55 (META-03 forbidden phrase list completeness) | CONTEXT D-55 | Plan 04-05 (this) | Yves confirmed 13-phrase list LOCKED 2026-06-21; spec implemented verbatim and GREEN |

**All three CONTEXT-queued blockers have now been surfaced with default recommendations and documented replan paths.** Plan 04-06 inherits a clean blocker slate.

## Hand-off Notes for Plan 04-06

Plan 04-06 wraps Phase 4 with ROADMAP / STATE updates, requirement check-offs, optional ADR-0004 if the Q3 verdict required formal documentation, and coverage re-measurement.

Inputs Plan 04-06 can rely on:

1. **All Phase-4 invariant gates GREEN.** META-03 forbidden-strings, META-02 zero-suppression, META-01 zero-rate edge, D-58 idempotency (4 cases), D-38 extended prefix gate (5 prefixes), SEC-03 extended Finance API redaction — all 17 new assertions PASS against the current src/ tree.
2. **Locked invariants (do not silently amend in Plan 04-06):**
   - META-03 forbidden phrase list = 13 phrases per D-55 (any change requires reopening D-55).
   - D-38 allowed transactionCode prefix set = closed 5-entry set (any addition requires explicit prefix-gate update + paired test).
   - D-49 = Option B per-refresh date clustering (no persistent state).
   - D-58 = the 4 idempotency cases above are the load-bearing acceptance contract.
3. **Build SHA after Plan 04-05:** `d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712` — Plan 04-06 should not change this (no src/ delta expected).
4. **Requirements completed in this plan:** META-02, META-03, FEE-01 (gated via D-58 case 3), FEE-03 (gated via D-58 case 4), PAYOUT-01 (gated via D-58 case 2), REF-02 (gated via Phase-3 + extended prefix gate including refund), SALE-07 (already covered by Plan 04-04, no new spec needed), TEST-02 (the META-03 spec is the dedicated negative-list regression gate).
5. **Coverage re-measurement:** Plan 04-06 should run `busted --coverage spec/` and report the post-Wave-4 src/ coverage percentage (Phase-3 baseline 99.23%; expected ≥95% on Wave-4 src/ additions from Plan 04-02 + 04-03 + 04-04).

## Self-Check: PASSED

All artifacts verified present and committed:

| Artifact | Status |
|---|---|
| spec/meta_no_tax_classification_spec.lua | FOUND |
| spec/meta_purpose_lines_spec.lua | FOUND |
| spec/refresh_idempotency_spec.lua (extended) | FOUND (8 it() blocks, was 4) |
| spec/refresh_log_redaction_spec.lua (extended) | FOUND (13 it() blocks, was 7) |
| spec/fixtures/finance/finance_payment_and_payout_for_promotion.json (regenerated) | FOUND (cccccccc- UUID) |
| Commit 8f3455c | FOUND (GPG-signed G) |
| Commit d52e8df | FOUND (GPG-signed G) |
| Commit 0803ed2 | FOUND (GPG-signed G) |
| busted spec/ | 317 / 0 / 0 / 0 |
| luacheck . | 0 warnings / 0 errors in 37 files |
| lua tools/build.lua --verify | OK: reproducible |
| Forbidden-phrase grep in src/ + dist/ | clean |
