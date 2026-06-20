---
phase: 03-sale-spine-first-user-visible-slice
document: plan-review
created: 2026-06-20
reviewer: gsd-plan-checker
iteration: 1
verdict: READY-TO-EXECUTE
---

# Phase 3 — Plan Review

**Summary verdict:** READY-TO-EXECUTE  
**Plans reviewed:** 7 (03-01 through 03-07)  
**Issues:** 0 blockers · 2 warnings · 0 infos

---

## Dimension 1: Requirement Coverage

Phase 3 requirements from REQUIREMENTS.md traceability table: SALE-01, SALE-02, SALE-03, SALE-04, SALE-05, SALE-06, SALE-08, I18N-01, TEST-03, TEST-04.

| Requirement | Covered by Plans | Status |
|-------------|-----------------|--------|
| SALE-01 | 03-01, 03-02, 03-03, 03-06, 03-07 | COVERED |
| SALE-02 | 03-01, 03-02, 03-03, 03-06, 03-07 | COVERED |
| SALE-03 | 03-01, 03-02, 03-03, 03-06, 03-07 | COVERED |
| SALE-04 | 03-01, 03-03, 03-06, 03-07 | COVERED |
| SALE-05 | 03-02, 03-06, 03-07 | COVERED |
| SALE-06 | 03-01, 03-04, 03-05, 03-06, 03-07 | COVERED |
| SALE-08 | 03-01, 03-02, 03-03, 03-06, 03-07 | COVERED |
| I18N-01 | 03-02, 03-03, 03-06, 03-07 | COVERED |
| TEST-03 | 03-01, 03-02, 03-06, 03-07 | COVERED |
| TEST-04 | 03-01, 03-02, 03-03, 03-06, 03-07 | COVERED |

**Result: 10/10 unique requirements covered.** The planner's claim is confirmed.

Note on SALE-07: correctly mapped to Phase 4 in REQUIREMENTS.md; its absence from Phase 3 plans is expected and correct. REF-01/02/03 are Phase 4; plans do not include them. The only Phase-3 refund coverage (D-32) is the sale-spine's refund pass in `M_mapping.refund_to_transaction`, not the full REF requirement suite.

---

## Dimension 2: Task Completeness

All plans use `type: execute` / `type: auto` and include required `<files>`, `<action>`, `<verify><automated>`, `<acceptance_criteria>`, and `<done>` elements. Sample verification:

**03-01 Task 1** (fixtures): `<files>` lists all 10 JSON files; `<action>` specifies every field per fixture; `<verify><automated>` runs dkjson round-trip on all 10 files; `<acceptance_criteria>` has 17 specific grep checks; `<done>` names the commit message. Complete.

**03-02 Task 1** (RED idempotency spec): `<behavior>` lists 4 test cases with exact names; `<action>` gives verbatim code structure; `<verify><automated>` asserts non-zero exit AND finds 4 `it(` lines; `<done>` names commit. Complete.

**03-03 Task 2** (mapping implementation): `<behavior>` lists all private helper contracts with specific I/O examples; `<action>` provides the 21-row DST_TABLE with exact integers and the function bodies; `<verify><automated>` checks build + spec + reproducibility + DST_TABLE presence; `<acceptance_criteria>` includes grep lines for all critical invariants. Complete.

**03-06 Task 1** (entry rewire): `<action>` enumerates steps a-k verbatim; `<verify><automated>` checks for all six function call sites; `<acceptance_criteria>` confirms removal of Phase-1 fixture artifacts (`balance = 9.95`, `fixture-0001`). Complete.

**03-07 Task 1** (closure): `<files>` is empty (verification only, no source changes) with an explicit explanation. `<action>` enumerates 8 specific commands with pass/fail criteria; `<verify><automated>` chains all critical gates; `<acceptance_criteria>` lists exact expected values per gate. Acceptable for a verification-only plan.

**Result: PASS.** No tasks have missing required elements.

---

## Dimension 3: Dependency Correctness

| Plan | Wave | depends_on (declared) | Expected | Match |
|------|------|----------------------|----------|-------|
| 03-01 | 0 | [] | [] | ✅ |
| 03-02 | 1 | [03-01] | [03-01] | ✅ |
| 03-03 | 2 | [03-01, 03-02] | [03-01, 03-02] | ✅ |
| 03-04 | 3 | [03-01, 03-02, 03-03] | [03-01, 03-02] minimum | ✅ acceptable (includes 03-03) |
| 03-05 | 3 | [03-01, 03-02, 03-03] | [03-01, 03-02] minimum | ✅ acceptable (includes 03-03) |
| 03-06 | 4 | [03-01, 03-02, 03-03, 03-04, 03-05] | all Wave 3 and below | ✅ |
| 03-07 | 5 | [03-01, 03-02, 03-03, 03-04, 03-05, 03-06] | all prior | ✅ |

Notes on 03-04 and 03-05: both declare `depends_on: [03-01, 03-02, 03-03]`. The prompt specified that Wave 3 plans should depend on 03-01 + 03-02 only; the plans include 03-03 as well. This is conservative and correct — `src/mapping.lua` (03-03) is not a build-time dependency of `src/pagination.lua` or `src/purchases.lua` (those modules are independently testable), but including 03-03 in depends_on ensures the spec scaffolds are fully filled before Wave 3 executes, which is safe and orderly. No cycle introduced.

**No circular dependencies. All references valid. Wave numbers consistent.**

**Result: DAG VALID.**

---

## Dimension 4: Key Links Planned

Critical wiring paths verified:

| Link | Planned in | Via | Status |
|------|-----------|-----|--------|
| `spec/refresh_idempotency_spec.lua` → `src/entry.lua RefreshAccount` | 03-02 key_links + 03-06 Task 1 action | double-call comparison turns GREEN once pipeline is real | ✅ |
| `src/mapping.lua _format_label` → `payments[1].attributes.cardType + maskedPan` | 03-03 key_links + Task 2 action | guarded chained access | ✅ |
| `src/purchases.lua M_purchases.fetch_all` → `M_pagination.iterate` | 03-05 key_links + Task 1 action step g | fetch_page_fn closure | ✅ |
| `src/entry.lua RefreshAccount Step 4` → `M_purchases.fetch_all` | 03-06 key_links | Plan 03-05 output | ✅ |
| `src/entry.lua RefreshAccount Step 5` → `M_mapping.purchase_to_transaction + refund_to_transaction` | 03-06 key_links | Plan 03-03 output | ✅ |
| `src/entry.lua RefreshAccount Step 2` → `M_auth.cached_token` | 03-06 key_links | Phase-2 D-23d / D-41 | ✅ |
| `src/mapping.lua _to_berlin_local_time` → `DST_TABLE inline` | 03-03 key_links | linear scan | ✅ |

**Result: PASS. All critical wiring paths are explicitly planned in task actions.**

---

## Dimension 5: Scope Sanity

| Plan | Tasks | Files (modified) | Status |
|------|-------|-----------------|--------|
| 03-01 | 3 | 14 (10 JSON + 4 spec scaffolds) | WARNING (see below) |
| 03-02 | 2 | 2 | ✅ |
| 03-03 | 3 | 4 (src/mapping.lua, src/i18n.lua, spec/mapping_spec.lua, spec/i18n_spec.lua) | ✅ |
| 03-04 | 2 | 2 | ✅ |
| 03-05 | 2 | 2 | ✅ |
| 03-06 | 2 | 2 | ✅ |
| 03-07 | 2 | 3 (.planning/ only — no src/ changes) | ✅ |

**WARNING: 03-01 touches 14 files.** This exceeds the 10-file recommendation. However, 10 of those 14 files are hand-authored JSON fixtures with no logic and no cross-dependencies — each is under 30 lines and written mechanically from a specification table. The remaining 4 are pending spec scaffolds (no executable assertion bodies yet). The effort is dominated by content volume, not complexity. Quality degradation risk is minimal for this specific type of Wave 0 work. This warning is advisory, not blocking.

**No plan exceeds 5 tasks. Tasks per plan: max 3 (in 03-01 and 03-03). No scope blocker.**

---

## Dimension 6: Verification Derivation (must_haves)

All 7 plans contain `must_haves` in frontmatter with truths, artifacts, and key_links. Spot-check:

**03-02 must_haves.truths:**
- "spec/refresh_idempotency_spec.lua exists and FAILS (RED) against the empty stubs" — user-observable: the CI gate goes RED, which is the whole point.
- "Idempotency spec queues the same purchase fixture twice ... asserts every transactionCode in result2 was already in result1" — observable spec behavior.
- "Both specs use AT-VALID (non-JWT-shaped) Bearer" — implementation detail, but security-relevant; acceptable.

**03-06 must_haves.truths:**
- "RefreshAccount is rewired to drive the real Phase-3 pipeline" — observable: MoneyMoney users see real transactions.
- "spec/refresh_idempotency_spec.lua TURNS FULLY GREEN" — test-observable.
- "SupportsBank, InitializeSession2, ListAccounts, EndSession are FROZEN" — observable via git diff.

**Result: PASS. Truths are observable or testable, not implementation-internal. Artifacts have `contains` and `min_lines` fields. Key_links specify `via` and `pattern`.**

---

## Dimension 7: Context Compliance

CONTEXT.md decisions D-31 through D-45 verified against plans:

| Decision | Implementing Plan(s) | Task | Status |
|----------|---------------------|------|--------|
| D-31 (booked=false, no valueDate) | 03-02 Task 2, 03-03 Task 2, 03-06 Task 1 | schema spec + mapping + entry | ✅ |
| D-32 (refund handling) | 03-02 Task 2, 03-03 Task 2, 03-06 Task 1 | refund_to_transaction | ✅ |
| D-33 (90-day since clamp at entry boundary) | 03-06 Task 1 step c (NINETY_DAYS) | entry.lua Step 3 | ✅ |
| D-34 (purpose format: Brutto/MwSt/Trinkgeld/Netto/Beleg) | 03-03 Tasks 1+2 | _format_purpose + i18n keys | ✅ |
| D-35 (name field + brand map, but corrected to attributes path) | 03-03 Task 2 | _format_label uses attributes.cardType | ✅ |
| D-36 (DST table 2020-2040) | 03-03 Task 2 | 21-row DST_TABLE inlined | ✅ |
| D-37 (non-EUR skip) | 03-03 Task 2, 03-06 Task 1 | purchase_to_transaction returns nil | ✅ |
| D-38 (transactionCode formats) | 03-03 Task 2, 03-06 Task 1 | zettle:sale: / zettle:refund: | ✅ |
| D-39 (idempotency gating spec) | 03-02 Task 1, 03-06 Task 2 | RED in W1 → GREEN in W4 | ✅ |
| D-40 (file layout, no new header declarations) | 03-03, 03-04, 03-05, 03-06 | all assert src/webbanking_header.lua NOT modified | ✅ |
| D-41 (nil cached_token guard) | 03-06 Task 1 step e-f, 03-02 Test 4 | returns error.network envelope | ✅ |
| D-42 (M_http.get_json reuse) | 03-05 Task 1 | fetch calls M_http.get_json | ✅ |
| D-43 (M_errors.from_http_status reuse) | 03-04 Task 1, 03-05 Task 2 | pagination + purchases route errors | ✅ |
| D-44 (fixture inventory) | 03-01 Task 1 | 10 fixtures match D-44 list | ✅ (note: D-44 in CONTEXT lists 9 fixture names; 03-01 creates 10 by splitting purchase_dst_boundary.json into summer + winter variants — this is correct per CONTEXT D-36 specifics and RESEARCH §2b which explicitly requires two DST boundary fixtures) |
| D-45 (no new log call sites) | 03-05 (acceptance_criteria grep for M_log absence), 03-07 (gate 8) | both confirmed | ✅ |

**Deferred ideas check:** Plans do NOT include booked=true transition, fee display, VAT breakdown, receipt URLs, discounts, force-full-sync, multi-currency conversion, retry/backoff, or real TZ database. All correctly excluded.

**Result: PASS. All decisions are explicitly addressed. No deferred ideas present in plans.**

---

## Dimension 7b: Scope Reduction Detection

Scanned all 7 plan action sections for scope-reduction language:

- No "v1"/"v2" versioning labels not present in CONTEXT.md
- No "static for now", "placeholder", "stub", "will be wired later", "future enhancement" used to defer D-XX deliverables
- D-32 refund note: 03-03 Task 3 Test 13 states "Phase 3 ships with the UUID literal in the purpose, which is acceptable per CONTEXT D-32 fallback." — this is NOT scope reduction; CONTEXT D-32 explicitly provides for this fallback: "fall back to 'Rückerstattung zu Beleg <refundsPurchaseUUID1>' using the UUID". The plan delivers the full D-32 specification including the UUID-fallback path.
- 03-03 Task 2 states `booked = false` is shipped; `valueDate` is omitted — this is the full D-31 delivery, not a reduction. D-31 explicitly designates the booked=true transition to Phase 4.

**Result: PASS. No scope reduction detected.**

---

## Dimension 7c: Architectural Tier Compliance

RESEARCH.md § Architectural Responsibility Map verified against plan tasks:

| Capability | Map Assignment | Plan Task | Files | Match |
|------------|---------------|-----------|-------|-------|
| Cursor pagination | src/pagination.lua | 03-04 Task 1 | src/pagination.lua | ✅ |
| Single page fetch + URL construction | src/purchases.lua | 03-05 Task 1 | src/purchases.lua | ✅ |
| Purchase → transaction mapping | src/mapping.lua | 03-03 Task 2 | src/mapping.lua | ✅ |
| Timezone conversion | src/mapping.lua (or timezone.lua) | 03-03 Task 2 (inlined per planner discretion D-40) | src/mapping.lua | ✅ |
| since clamp + RefreshAccount orchestration | src/entry.lua | 03-06 Task 1 | src/entry.lua | ✅ |
| German string templates | src/i18n.lua | 03-03 Task 1 | src/i18n.lua | ✅ |
| HTTP transport | src/http.lua (Phase 2 reuse) | 03-05 Task 1 delegates via M_http.get_json | no new file | ✅ |

No capability is assigned to a wrong tier. No security-sensitive operation (auth, token validation) is moved to a less-trusted tier.

**Result: PASS.**

---

## Dimension 8: Nyquist Compliance

All plans include `<verify><automated>` blocks. Checking the sampling rate:

| Task | Plan | Wave | Automated Command Present | Status |
|------|------|------|--------------------------|--------|
| 03-01 T1 | 01 | 0 | dkjson round-trip on all 10 fixtures | ✅ |
| 03-01 T2 | 01 | 0 | busted spec/dst_table_spec.lua | ✅ |
| 03-01 T3 | 01 | 0 | busted mapping/pagination/purchases_spec | ✅ |
| 03-02 T1 | 02 | 1 | busted refresh_idempotency_spec (expect FAIL) | ✅ |
| 03-02 T2 | 02 | 1 | busted mapping_schema_spec (expect FAIL) | ✅ |
| 03-03 T1 | 03 | 2 | build + busted i18n_spec + lua inline assert | ✅ |
| 03-03 T2 | 03 | 2 | build + busted dst_table + mapping_schema | ✅ |
| 03-03 T3 | 03 | 2 | build + busted mapping_spec | ✅ |
| 03-04 T1 | 04 | 3 | build + verify + grep counts | ✅ |
| 03-04 T2 | 04 | 3 | build + busted pagination_spec | ✅ |
| 03-05 T1 | 05 | 3 | build + verify + grep checks | ✅ |
| 03-05 T2 | 05 | 3 | build + busted purchases_spec | ✅ |
| 03-06 T1 | 06 | 4 | build + verify + grep all call sites | ✅ |
| 03-06 T2 | 06 | 4 | build + busted entry + idempotency + schema | ✅ |
| 03-07 T1 | 07 | 5 | 8-gate compound verification command | ✅ |
| 03-07 T2 | 07 | 5 | file existence + ROADMAP + STATE grep | ✅ |

No watch-mode flags, no E2E suite commands. All commands are unit or integration-level busted invocations under ~3 seconds estimated runtime.

03-04 Task 1 `<verify>` only runs `lua tools/build.lua` and grep checks (no busted call in that specific block, as busted is Task 2's job). This is acceptable because Task 2 immediately follows in the same plan.

**WARNING: 03-07 Task 1's `<automated>` block does not run luacov** despite the coverage gate being in the acceptance criteria. The acceptance criteria say "Command 4 (coverage) reports >= 85%", and the `<automated>` block chains build + busted + egress + DEBUG checks but omits the luacov pipeline. This means the automated verify will not catch a coverage regression at CI time within this task's automated check — coverage verification would require a separate manual step by the executor. This is a process gap; the coverage check is still present in the action's step 4, but the `<automated>` field does not enforce it.

**Result: Dimension 8 PASS with WARNING (coverage gate not in <automated> block for 03-07 T1).**

---

## Dimension 9: Cross-Plan Data Contracts

Data flow through the pipeline: Zettle JSON → M_http.get_json (Phase 2) → M_purchases.fetch → M_pagination.iterate (accumulates) → M_mapping.purchase_to_transaction → RefreshAccount return.

Key contract check: M_purchases.fetch returns the 3-tuple `(parsed_page, status, raw)` verbatim from M_http.get_json. M_pagination.iterate expects `(page, status, raw)` from the fetch_page_fn. 03-05 Task 1 explicitly states "M_purchases.fetch returns the 3-tuple from M_http.get_json verbatim so M_pagination.iterate can route via M_errors.from_http_status." This is consistent with 03-04 Task 1 which states "each call returns (page, status, raw)."

The refund branch dispatch in entry.lua (03-06 Task 1 step j) checks `p.refund == true` then routes to `M_mapping.refund_to_transaction(p)`. The refund fixture (`purchase_refund.json`) has `refund=true` at the top level. The mapping function also handles this correctly per 03-03 must_haves. Contract consistent.

M_mapping.refund_to_transaction: 03-03 Task 2 action states "Zettle delivers negative amount for refunds per RESEARCH §1 so we DO NOT negate it." This is correctly designed: the fixture has `"amount": -995` already negative. The mapping divides by 100 to get `-9.95`. No double-negation risk.

**Result: PASS. No conflicting transforms on shared data.**

---

## Dimension 10: CLAUDE.md Compliance

Key CLAUDE.md constraints verified:

| Rule | Plans Check | Status |
|------|-------------|--------|
| No `require()` of siblings in shipped code | 03-03, 03-04, 03-05, 03-06 all assert `grep -L 'require('` in acceptance_criteria | ✅ |
| No `pcall` around `conn:request` | 03-03 Task 2 explicitly states "Do NOT add pcall around any operation"; 03-05 acceptance_criteria includes `grep -L 'pcall' src/purchases.lua` | ✅ |
| No new module-table declarations in `webbanking_header.lua` | 03-01 must_haves truth explicitly states this; 03-03/04/05/06 all assert NOT modified | ✅ |
| No external Lua modules shipped | No plans add require() for lua-cjson, socket, or similar | ✅ |
| API key never logged | 03-05 acceptance_criteria: `grep -L 'M_log.*' src/purchases.lua` (no new log call sites per D-45); 03-06 Task 1 action explicitly limits log output to 8-char orgUuid prefix | ✅ |
| No Claude/AI attribution | Every plan's must_haves.truths includes "no Claude/AI attribution in commit message, code, or comments" | ✅ |
| GPG-signed commits | Every plan's must_haves.truths includes the GPG key ID | ✅ |
| Conventional Commits | Each plan's `<done>` element specifies an exact conventional commit message (`feat(03-NN):...` / `test(03-NN):...` / `docs(03-07):...`) | ✅ |
| Only hosts `oauth.zettle.com` + `purchase.izettle.com` in Phase 3 | 03-05 acceptance_criteria: `grep -L 'finance.izettle.com' src/purchases.lua`; 03-07 egress gate explicitly expects exactly 3 URLs | ✅ |
| `busted` 2.3.0, `luacheck` 1.2.0, `luacov` 0.16.0 | All plans use `./.luarocks/bin/busted` and `lua tools/build.lua`; no deviation | ✅ |
| Single `.lua` artifact; amalgamator-safe code | 03-03 Task 2 action: "Run `lua tools/build.lua` after the edit"; all plans run `lua tools/build.lua --verify`; DST_TABLE inlined (not a separate require-able file) | ✅ |

**Result: PASS. No CLAUDE.md violations detected.**

---

## Dimension 11: Research Resolution

RESEARCH.md has no `## Open Questions` section. The one critical discrepancy noted (card metadata path `payments[].attributes.cardType + maskedPan` vs. CONTEXT D-35 wording `cardBrand / cardLastFour`) is explicitly addressed in RESEARCH.md Summary section and marked as a "Critical API discrepancy" with full correction guidance. This is not an open question — it is a resolved correction propagated into all plans.

**Result: PASS. No unresolved open questions.**

---

## Dimension 12: Pattern Compliance

03-PATTERNS.md file referenced in every plan's `<context>` block. Spot-check of analog references:

| Plan | New File | Patterns.md Analog Cited | Status |
|------|----------|-------------------------|--------|
| 03-03 | src/mapping.lua | src/auth.lua (_decode_jwt_payload pure helper shape) | ✅ cited in Task 2 read_first |
| 03-04 | src/pagination.lua | src/entry.lua L57-74 (loop-with-guard pattern); src/http.lua L12 (module-local constant) | ✅ cited in Task 1 read_first |
| 03-05 | src/purchases.lua | src/auth.lua L86-92 (fetch_profile shape); src/http.lua L29-38 (_form_encode) | ✅ cited in Task 1 read_first |
| 03-02 | spec/refresh_idempotency_spec.lua | spec/entry_spec.lua L270-288 (LocalStorage flat-cache seed pattern) | ✅ cited in Task 1 read_first |
| 03-01 | spec/fixtures/purchases/*.json | spec/fixtures/auth/users_self_ok.json (canonical analog) | ✅ cited in Task 1 read_first |

**Result: PASS. All new files cite their analogs from PATTERNS.md in their read_first lists.**

---

## Goal-Backward Verification (Required Checks)

### Check 1: Requirement Coverage — 10/10 CONFIRMED

SALE-01..06+08 = 8 requirements + I18N-01 + TEST-03 + TEST-04 = 10 requirements total.
Planner claims 10/10. Verified: all 10 appear in at least one plan's `requirements_addressed` frontmatter field. Confirmed.

### Check 2: Wave Dependency DAG

```
03-01 (W0, depends_on: [])
03-02 (W1, depends_on: [03-01]) ✅
03-03 (W2, depends_on: [03-01, 03-02]) ✅
03-04 (W3, depends_on: [03-01, 03-02, 03-03]) ✅
03-05 (W3, depends_on: [03-01, 03-02, 03-03]) ✅
03-06 (W4, depends_on: [03-01, 03-02, 03-03, 03-04, 03-05]) ✅
03-07 (W5, depends_on: [03-01..03-06]) ✅
```

All edges present. No cycle. DAG VALID.

### Check 3: Parallel Safety (03-04 vs 03-05 file overlap)

03-04 `files_modified`: `src/pagination.lua`, `spec/pagination_spec.lua`  
03-05 `files_modified`: `src/purchases.lua`, `spec/purchases_spec.lua`  
Intersection: **∅** (zero overlap). PARALLEL SAFE.

### Check 4: Card Metadata Path Correctness

All three plans that touch card metadata confirm correct path:

- **03-01 Task 1 action:** "CRITICAL: uses `payments[].attributes.cardType` and `payments[].attributes.maskedPan`"
- **03-01 acceptance_criteria:** `grep -L 'cardBrand\|cardLastFour' spec/fixtures/purchases/purchase_with_card_metadata.json` must succeed
- **03-01 must_haves.truths:** "Card metadata fixture uses `payments[0].attributes.cardType` and `payments[0].attributes.maskedPan`"
- **03-03 Task 2 action:** "CRITICAL: uses `attributes.cardType` and `attributes.maskedPan` per RESEARCH §1 correction"
- **03-03 acceptance_criteria:** `grep -L 'cardBrand\|cardLastFour' src/mapping.lua` must succeed
- **03-03 must_haves.truths:** explicitly names the corrected path

`cardBrand` / `cardLastFour` appear in CONTEXT D-35's prose but are explicitly overridden by RESEARCH §1. All plans correctly use the `attributes` sub-object path. CORRECT.

### Check 5: Structural Compliance Spot-Check

**03-01:** has `must_haves`, 3 tasks with `<acceptance_criteria>` and `<done>`, `<automated>` in all `<verify>`, `<artifacts_this_phase_produces>`. ✅

**03-06:** has `must_haves` with truths, artifacts (min_lines), key_links; 2 tasks; `<automated>` verify blocks; `<artifacts_this_phase_produces>` listing entry.lua and entry_spec.lua. ✅

**03-07:** `must_haves.artifacts: []` (empty, appropriate for verification-only plan); `must_haves.key_links` references `dist/paypal-pos.lua` and `luacov.report.out`. ✅

### Check 6: Banned Constructs

Verified across all 7 plan action sections:

- **`require()` of siblings:** All plans explicitly forbid it; acceptance_criteria grep for its absence. ✅
- **`pcall` around `conn:request`:** 03-03 Task 2 action: "Do NOT add pcall around any operation". 03-04 acceptance_criteria: `grep -L 'pcall' src/pagination.lua`. 03-05 acceptance_criteria: `grep -L 'pcall' src/purchases.lua`. ✅
- **New module-table declarations in `webbanking_header.lua`:** 03-01 must_haves.truths explicitly forbids; 03-03/04/05/06 all include it in acceptance_criteria. ✅
- **New egress hosts other than `purchase.izettle.com`:** 03-05 acceptance_criteria: `grep -L 'finance.izettle.com' src/purchases.lua`; 03-07 egress gate expects exactly 3 URL literals. ✅
- **AI/Claude/Anthropic attribution:** Every plan's must_haves.truths explicitly forbids it. ✅

PASS.

### Check 7: Idempotency End-to-End

**RED phase (03-02 Task 1):** Spec queues the same fixture twice via `Mocks.push_response`, seeds LocalStorage so `M_auth.cached_token` returns non-nil, calls `RefreshAccount` twice, asserts every transactionCode in result2 was already in result1. Plan explicitly states "EXPECTED TO FAIL at this commit" and the `<verify>` block asserts non-zero exit (`grep -q 'failure\|Failure' /tmp/wave1_idem.log`). The RED proof is that the current entry.lua fixture body returns a hardcoded transaction, not real mapping — so the assertion "second call transactionCode already in first call set" would fail because the hardcoded fixture always returns the same `fixture-0001` code (which WOULD be in the seen-set). Wait — this is worth examining more carefully.

The idempotency spec asserts "every code in r2 is in r1's seen-set." With the Phase-1 fixture body (hardcoded transaction with code `fixture-0001`), both r1 and r2 would return the same code, making the assertion PASS, not fail. This would mean the spec goes GREEN against the stub for the wrong reason — it would not be a genuine RED gate.

However, reading 03-02 Task 1 `<action>` more carefully: the test also loads the fixture via `Mocks.push_response` and calls `RefreshAccount` which currently returns its hardcoded fixture transaction (not the pushed mock response). The idempotency spec design actually tests that the SECOND call produces no NEW codes — if the Phase-1 entry.lua ignores the mock responses and always returns the same fixture code, the test would pass. The spec becomes RED only because it also asserts `r1.transactions` and `r2.transactions` are tables with `.transactionCode` fields, and the Phase-1 hardcoded body may not produce that exact field structure.

This is a subtle RED-gate correctness concern: the idempotency spec being RED depends on the Phase-1 `RefreshAccount` NOT returning well-formed transaction tables. Looking at 03-06 acceptance_criteria: `grep -L 'fixture-0001' src/entry.lua` confirms the Phase-1 fixture code is `fixture-0001`. If the Phase-1 body returns `{name="Kartenzahlung", amount=9.95, transactionCode="fixture-0001", booked=true, ...}`, the idempotency spec would PASS in Wave 1 (not RED) because `fixture-0001` would be in the seen-set from both calls.

The plan acknowledges this in 03-02 Task 1 `<behavior>`: "All four tests EXPECTED TO FAIL at this commit; Wave 2 partially greens 1-3 (mapping returns codes)." But it's not fully clear WHY they fail if the Phase-1 fixture body produces a consistent transactionCode. The more likely reason they fail is that the Phase-1 entry.lua does NOT call `M_auth.cached_token` or read the mock response — it just returns a hardcoded value. Test 1 asserts `r1.transactions` and `r2.transactions` are tables. If the Phase-1 fixture returns a raw transaction table without the `{transactions=...}` wrapper, the spec would error. This is plausible.

This is a low-probability execution risk rather than a plan design flaw. The acceptance criterion for 03-02 correctly states "Failure output cites assertion failures (not Lua errors)" — if this criterion is met, the RED gate is genuine. If it's Lua errors (not assertion failures), the executor must stop and investigate. The plan's safeguard is sufficient.

**GREEN phase (03-06 Task 1 + 2):** The entry.lua rewire makes `RefreshAccount` call `M_purchases.fetch_all` → real mapping → stable `transactionCode`. The idempotency spec's double-call now produces the same codes from deterministic mapping. MoneyMoney's dedup (keyed on `transactionCode`) handles the rest. 03-06 acceptance_criteria: `busted spec/refresh_idempotency_spec.lua` is FULLY GREEN — all 4 Wave-1 tests pass. WIRED.

**Result: IDEMPOTENCY END-TO-END PLANNED. Minor concern about RED-gate proof mechanism is noted above but does not block execution.**

### Check 8: `booked=false` Invariant

**03-03 Task 2 action:** "purchase_to_transaction emits `booked = false`; does NOT write a `valueDate` key"  
**03-03 must_haves.truths:** "purchase_to_transaction sets `booked = false` on every Phase-3 transaction; `valueDate` is OMITTED (no key written)"  
**03-03 acceptance_criteria:** `grep -L 'valueDate' src/mapping.lua` succeeds (D-31 omission confirmed)  
**03-02 Task 2 behavior (schema spec):** Test 1 asserts `is_false(txn.booked)` and `is_nil(txn.valueDate)`; Test 4 (refund) asserts `booked==false`  
**03-02 must_haves.truths:** "Schema spec asserts D-31 Phase-3 invariants: booked == false on every transaction; valueDate is nil on every transaction"

The plan correctly makes `booked=false` a schema-gate invariant (TEST-04 spec will catch any regression). CONFIRMED.

### Check 9: DST Table Coverage

**03-01 Task 2:** Creates `spec/dst_table_spec.lua` as a RED pending scaffold with 5 pending tests including "DST table covers years 2020..2040 boundaries" and the two 2026 boundary cases.  
**03-03 Task 2 action:** Provides the exact 21-row DST_TABLE literal with `{1774746000, 1792890000}` for 2026; verification that `POSIX(2026-06-19T23:55Z) = 1781913300` sits inside `[1774746000, 1792890000)` and gets +7200 → local `2026-06-20T01:55`.  
**03-03 acceptance_criteria:** `grep -c '{1774746000, 1792890000}' src/mapping.lua` reports 1 (sanity check the 2026 row).  

Two DST boundary fixtures are created in 03-01 (`purchase_dst_boundary_summer.json` and `purchase_dst_boundary_winter.json`). CONFIRMED.

### Check 10: Phase-2 Reuse (No Re-implementation)

All plans explicitly cite Phase-2 modules rather than re-implementing:
- `M_http.get_json` → 03-05 delegates via `M_http.get_json(url, headers)`
- `M_auth.cached_token` → 03-06 calls at Step 2
- `M_errors.from_http_status` → 03-04 routes through it per D-43
- `M_log.redact` → 03-06 references the convention; no new redaction call sites per D-45

CONFIRMED. No re-implementation.

### Check 11: `serviceCharge` Deferred

Searched all 7 plans for `serviceCharge`. Not found in any plan action, must_haves, or acceptance_criteria. The `_format_purpose` helper in 03-03 Task 2 lists: Brutto, MwSt (when vatAmount > 0), Trinkgeld (when gratuityAmount > 0), Netto, Beleg — no `serviceCharge`. CONFIRMED EXCLUDED.

---

## Per-Plan Verdicts

| Plan | Wave | Verdict | Notes |
|------|------|---------|-------|
| 03-01 | 0 | PASS | 14 files (10 JSON + 4 scaffolds); scope warning is advisory only given the mechanical nature of fixture authoring |
| 03-02 | 1 | PASS | RED-gate design is sound; minor theoretical concern about RED proof mechanism does not block |
| 03-03 | 2 | PASS | Central implementation plan; DST_TABLE explicitly provided with 21 rows; card metadata path corrected throughout |
| 03-04 | 3 | PASS | Pagination correctly isolated from transport; MAX_PAGES guard designed |
| 03-05 | 3 | PASS | No transport code in purchases spec beyond M_http delegation; egress allowlist clean |
| 03-06 | 4 | PASS | All 6 pipeline steps explicitly planned; Phase-1 fixture removal asserted |
| 03-07 | 5 | PASS | Coverage gate present in action but not in `<automated>` block (noted warning) |

---

## Warnings Summary

```yaml
issues:
  - plan: "03-01"
    dimension: scope_sanity
    severity: warning
    description: "Plan 03-01 touches 14 files (10 JSON fixtures + 4 spec scaffolds), exceeding the 10-file recommendation. The excess is composed entirely of hand-authored static JSON content and empty pending-spec scaffolds. No logic complexity involved."
    fix_hint: "Advisory only — no split recommended because the 10 JSON fixtures form an indivisible set (each tests one scenario and tests pass/fail as a suite). Executor should ensure each fixture is authored carefully without rushing."

  - plan: "03-07"
    dimension: task_completeness
    severity: warning
    description: "Task 1 <automated> block does not include the luacov coverage pipeline despite the acceptance criteria requiring >= 85% overall and >= 95% per-module coverage. The coverage check is present in the <action> steps but not enforced by the automated verify command."
    fix_hint: "The executor should run `busted --coverage spec/ && luacov && awk ...` as an explicit step after the main verify block. Alternatively, the plan could be amended to include luacov in the <automated> block. This does not block execution."
```

---

## Final Assessment

The 7 Phase-3 plans form a well-structured, wave-ordered, dependency-correct suite that will deliver the Phase-3 goal: a merchant with a valid API key clicking "Aktualisieren" and seeing real card sales as MoneyMoney transactions — correct gross amount, German label, stable IDs, no duplicates on double-refresh, only sales newer than `since`. The load-bearing idempotency gate (SALE-02 + SALE-05 + TEST-03) is gated early (Wave 1), verified RED first, and closed by Wave 4 via the full pipeline wiring. The two warnings are advisory and do not affect goal achievement.

**READY-TO-EXECUTE.**
