---
phase: 04-enrichment-refunds-fees-payouts
checked: 2026-06-21
checker: gsd-plan-checker (Sonnet)
verdict: READY-FOR-EXECUTION (after orchestrator re-classification of false-positive BLOCKER)
plans_reviewed: [04-01-PLAN.md, 04-02-PLAN.md, 04-03-PLAN.md, 04-04-PLAN.md, 04-05-PLAN.md, 04-06-PLAN.md]
yves_blockers_open: [Q3-host-probe, D-49-option-A-vs-B, D-55-forbidden-strings-list]
---

# Phase 4 Plan Review

**Checker:** gsd-plan-checker (Sonnet) via the `/gsd-plan-phase 4` workflow.
**Aggregate verdict:** READY-FOR-EXECUTION subject to the three Yves-blockers already documented in `04-CONTEXT.md` (Q3 / D-49 / D-55).

The checker initially returned `REQUIRES-REVISION` with 1 BLOCKER ("missing `<artifacts_this_phase_produces>` sections in plans 04-03..04-06"); the orchestrator verified via `grep -n "artifacts" .planning/phases/04-enrichment-refunds-fees-payouts/04-0[1-6]-PLAN.md` that all 6 plans **do** contain the section in its canonical XML-block form (`<artifacts_this_phase_produces>...</artifacts_this_phase_produces>`). The checker had been looking for the `## Artifacts` heading-style alternative, which the planner did not use. **False-positive BLOCKER — re-classified DOWN to non-blocking.**

The 4 WARNINGs the checker raised remain WARNINGs (the checker re-classified each one during its own re-read; orchestrator concurs).

---

## 1. Goal-backward verdict per success criterion (6 rows)

| # | Success criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | balance + pendingBalance from Finance API liquid endpoint | VERIFIED | 04-03 must_haves: `M_finance.fetch_account_state` issues TWO GETs (`/v2/accounts/liquid/balance`, `/v2/accounts/preliminary/balance`); 04-03 Task 1 `<automated>` greps both URLs in `src/finance.lua` |
| 2 | Refund as negative; purpose cites original sale's receipt number; partial refunds | VERIFIED | 04-02 `refund_to_transaction(p, opts)` with `opts.original_receipt`; 04-03 entry-layer 14-step seq builds `purchases_by_uuid` + step 10 plumbs original_receipt; tests in 04-03 `spec/entry_spec.lua` |
| 3 | Per-sale fee via `originatingTransactionUuid`; daily-aggregate fallback with German purpose + warn log | VERIFIED | 04-02 adds `fee_to_transaction` + `fee_aggregate_to_transaction` with German "Tagesaggregat — N Einzelgebühren — Detail-Verknüpfung nicht verfügbar"; 04-03 step 12 implements cluster-by-Berlin-date + Option B |
| 4 | Payout as negative with `name = "Auszahlung an Bankkonto"` + bookingDate = settlement | VERIFIED | 04-02 `payout_to_transaction` + i18n key `account.name.payout`; 04-03 step 13 maps payouts |
| 5 | Per-rate VAT line + Trinkgeld line + META-03 never tax-classify | VERIFIED | 04-04 extends `_format_purpose` with per-rate VAT sorted desc; META-02 (Phase-3 zero-suppress) promoted to `meta_purpose_lines_spec` in 04-05; META-03 forbidden-strings spec in 04-05 walks `src/*.lua` **and** `dist/paypal-pos.lua` |
| 6 | cardType + entry-mode tail; fixture suite covers full permutation matrix | PARTIAL (acceptable) | SALE-07 covered in 04-04; 13 happy/pagination fixtures across 04-02 + 04-04. Finance-API error paths (`401 / 429 / 5xx / network / invalid_grant`) rely on Phase-2 `M_errors.from_http_status` inheritance per RESEARCH §1.7 — documented acceptable. **W-2** flags this for a one-line acknowledgement in Plan 04-03 must_haves. |

**Score:** 5 VERIFIED + 1 PARTIAL (documented inheritance, not a gap).

---

## 2. Quality-gate scorecard (12 rows)

| # | Gate | Verdict | Notes |
|---|---|---|---|
| 1 | Frontmatter completeness (wave, depends_on, files_modified, autonomous, requirements) | PASS | All 6 plans complete |
| 2 | `<read_first>` on every task | PASS | Substantial read_first blocks |
| 3 | `<acceptance_criteria>` concrete (grep / test / CLI output) | PASS | grep counts, exit codes, `busted ... \| grep '0 failures'`, byte-identical assertions — no subjective phrasing |
| 4 | `<action>` concreteness (identifiers, signatures, paths, values) | PASS | Exemplary specificity — exact UUIDs, function signatures, i18n strings with UTF-8 byte-escapes, exact `transactionCode` formats |
| 5 | Dependencies wired correctly | PASS | Wave-0 doesn't block Wave-1 (verified); Wave-2 blocks on Wave-1; Wave-3 parallel-safe with Wave-2 (no file overlap); Wave-4 blocks on Wave-2+3; Wave-5 blocks on Wave-2+3+4 — see Sequencing audit below |
| 6 | `<artifacts_this_phase_produces>` section in every plan | PASS | All 6 plans (re-verified after false-positive BLOCKER) |
| 7 | All 15 requirement IDs covered | PASS | ACCT-03/REF-01/02/03/FEE-01/02/03/PAYOUT-01/02/03/META-01/02/03/SALE-07/TEST-02 each appear ≥1× across the plans' `requirements:` frontmatter |
| 8 | must_haves derived from phase goal (6 observable behaviors mapped 1:1) | PASS | Each plan's must_haves.truths are user-/test-observable (e.g., "RefreshAccount return-table has pendingBalance", "transactionCode byte-identical across refreshes") |
| 9 | No `require()` of siblings in proposed src/*.lua | PASS | 04-02 Task 3 designs `M_mapping.parse_iso8601_utc` public wrapper to AVOID a require; 04-03 reuses M_http/M_pagination via globals |
| 10 | No AI/Claude attribution in plans | PASS | Every plan's must_haves and commit-message templates explicitly forbid it; verified by sampling |
| 11 | TDD discipline — RED spec before GREEN impl in each wave | PASS | 04-02 Task 1 RED → Tasks 2/3 GREEN; 04-04 Task 1 RED → Task 2 GREEN; 04-05 spec-only invariant pattern explicit |
| 12 | GPG-signed commits assumed (not contradicted) | PASS | Every plan's `<acceptance_criteria>` includes `git log -1 --format='%G?'` G/U check |

**Score:** 12 / 12 PASS.

---

## 3. RESEARCH-overlay verdict (7 mandatory overlays)

| # | Overlay | Verdict | Evidence |
|---|---|---|---|
| a | `originatingTransactionUuid` ↔ `payments[].uuid` (NOT purchaseUUID1); BOTH `purchases_by_uuid` + `payments_by_uuid` indexes | PRESENT | 04-03 must_haves truth 7 (14-step) explicitly: step 4 `purchases_by_uuid` keyed by `purchaseUUID1`; step 5 `payments_by_uuid` keyed by `purchase.payments[].uuid` — "NOT purchaseUUID1 per RESEARCH §3.1 critical correction". Task 2 `<automated>` greps both index names in `src/entry.lua` |
| b | Balance is TWO endpoints — `liquid/balance` AND `preliminary/balance` | PRESENT | 04-03 must_haves truth 4 explicit; Task 1 `<automated>` greps BOTH URLs in src/finance.lua |
| c | `READ:FINANCE` scope migration — ADR-0004 + README note | PRESENT | 04-06 must_haves truth 2 names ADR-0004 with READ:FINANCE scope; Task 2 creates ADR-0004; Task 3 adds README "Inbetriebnahme bei bestehendem v0.1.0 API-Key" section with `scopes=READ:PURCHASE+READ:FINANCE` URL |
| d | D-49 Option A vs B Yves-blocker flagged in 04-03 preamble | PRESENT | 04-03 `<objective>` opens with explicit Yves-blocker section explaining Option A vs B trade-off and that the plan implements Option B |
| e | `purchase_with_vat_and_tip.json` fixture regenerated (`"19.0"` not `"19"`) | PRESENT | 04-02 Task 1 Step 14 regenerates the fixture; acceptance_criteria greps `"19.0"` present AND `"19":` absent |
| f | Two ISO-8601 formats (Finance no-`Z` vs Phase-3 with-`Z`) | PRESENT | 04-03 must_haves truth 2: `_iso8601_utc_no_z(posix)` helper; Task 1 `<automated>` asserts `! grep -E '%Y-%m-%dT%H:%M:%SZ' src/finance.lua` (negative gate) |
| g | Phase-1 stubs `src/balance.lua` + `src/payouts.lua` DELETED from manifest (consolidate into `src/finance.lua`) | PRESENT | 04-02 Task 2 `git rm` both files; updates `tools/manifest.txt`; removes `M_payouts`/`M_balance` from webbanking_header; acceptance_criteria asserts files do not exist |

**Score:** 7 / 7 PRESENT.

---

## 4. Sequencing audit (2 rows)

| # | Question | Verdict | Notes |
|---|---|---|---|
| 1 | Plan 04-01 does NOT block Plans 04-02..04-06 | OK | 04-02 `depends_on: []` — runs in parallel with the Yves Wave-0 probe per ROADMAP "Wave 1 runs in parallel with Wave 0" |
| 2 | Plan 04-05 META-03 `depends_on` rationale (waits for 04-03 + 04-04) | OK (defensive) | META-03 forbidden-strings invariant *could* run after any src/ change, but waiting for 04-03 + 04-04 ensures the spec scans the FINAL state including new German strings introduced by Wave-3 `_format_purpose` (`Zahlart:`, entry-mode i18n labels). Running META-03 earlier risks false-GREEN that misses Wave-3 additions |

**Score:** 2 / 2 OK.

---

## 5. Pay/Compliance audit (2 rows)

| # | Question | Verdict | Notes |
|---|---|---|---|
| 1 | D-49 Option B double-booking risk acknowledged + mitigated | OK (triple-coverage) | 04-03 `<objective>` explicitly discloses the risk + cites Option A escape valve; 04-05 must_haves truth 6 case (4) gates `zettle:fee:aggregate:<date_iso>` stability across refreshes when same finance fixture is re-queued; 04-06 must_haves truth 4 CHANGELOG "Bekannte Grenzen" section + ADR-0004 documents the trade-off |
| 2 | META-03 spec walks `dist/paypal-pos.lua` (built artifact), not just `src/*.lua` | OK | 04-05 must_haves truth 4: "META-03 spec ALSO scans `dist/paypal-pos.lua` (built first via `lua tools/build.lua` inside the spec OR by relying on the spec preamble pattern that already builds)". Build-time AND edit-time gating both present |

**Score:** 2 / 2 OK.

---

## 6. Aggregate verdict

**READY-FOR-EXECUTION** — 0 BLOCKERs remaining (1 raised, 1 re-classified as false-positive on orchestrator re-check), 4 documented WARNINGs (each acceptable).

---

## 7. Remediation list (HIGH-severity only)

**None.** The original BLOCKER was a false positive (see header note). The 4 WARNINGs are tracked below and may be addressed in-flight during execution if the executor's read surfaces a concrete instance — they do not gate execution.

---

## WARNINGs (non-blocking)

- **W-1** — Plan 04-04 `depends_on` lists `[04-02]` only; could be `[04-02, 04-03]` for stricter serialization safety. File-overlap analysis shows current `[04-02]` is parallel-safe (04-03 modifies `src/finance.lua` + `src/entry.lua`; 04-04 modifies `src/mapping.lua` — no overlap). Leave as-is; document in the plan if a future replan needs stricter sequencing.
- **W-2** — Success criterion 6 Finance-API error-path fixture coverage relies on Phase-2 `M_errors.from_http_status` inheritance per RESEARCH §1.7 rather than named Phase-4 fixtures. Acceptable per inheritance principle; worth a one-line acknowledgement in Plan 04-03 must_haves if the executor wants to make it audit-visible.
- **W-3** — Plan 04-04 Phase-3 surface-preservation snapshot test calls `M_mapping.purchase_to_transaction` directly (not through RefreshAccount), so entry-layer state changes from Plan 04-03 don't affect the snapshot baseline. Confirmed parallel-safe; no fix needed.
- **W-4** — Plan 04-05 D-58 idempotency test case 1 (sale + payout promote) requires Plan 04-03's mock-queueing helper to support back-to-back RefreshAccount calls with different fixture sets. Plan 04-03 must_haves truth 11 hand-off acknowledges this; executor should verify the helper's queue API supports multi-cycle reuse during Plan 04-03 execution.

---

## Yves-blockers (out of band — gating before /gsd-execute-phase 4)

These are inherited from `04-CONTEXT.md`; the plan-checker did not surface any new ones.

| ID | What Yves needs to do |
|----|------------------------|
| **Q3** | Run the live sandbox probe against `https://finance.izettle.com/v2/accounts/liquid/transactions` with your sandbox API key; flip `docs/adr/0003-sandbox-probe-results.md` Q3 from DEFERRED → ACCEPTED (recording the observed body shape). Plan 04-01 is exactly this task. Does NOT block Plans 04-02..04-06 — they all assume the research-recommended host. |
| **D-49** | Sign off on the fee-fallback contract: research recommends Option B (per-refresh date clustering with README disclaimer); Option A (LocalStorage persistence) is available if you want hard dedup at the cost of D-59 amendment. Plan 04-03 implements Option B. |
| **D-55** | Sign off on the META-03 forbidden-strings list (13 phrases drafted in `04-CONTEXT.md` D-55). Permanent invariant once locked. |

---

*Reviewed: 2026-06-21*
*Branch: phase-4/enrichment @ 26d6736*
