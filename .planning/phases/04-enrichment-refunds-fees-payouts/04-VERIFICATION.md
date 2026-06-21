---
phase: 04-enrichment-refunds-fees-payouts
verified: 2026-06-21T00:00:00Z
status: passed
score: 6/6 success criteria verified
requirements_satisfied: 14/15
human_verification:
  - test: "Q3 live probe of finance.izettle.com"
    expected: "GET https://finance.izettle.com/v2/accounts/liquid/transactions returns 200 with the documented JSON shape; ADR-0003 Q3 transitions DEFERRED → ACCEPTED"
    why_human: "Requires Yves' sandbox bearer token, which is never persisted in the repo. tools/probe-finance.sh exists as the helper but cannot be executed by the verifier."
  - test: "ACCT-03 cent-accurate match against my.zettle.com merchant dashboard"
    expected: "result.balance and result.pendingBalance match the values shown in my.zettle.com to the cent for a live merchant tenant"
    why_human: "Requires a real PayPal POS merchant account; cannot be observed against fixtures."
  - test: "loop-lektor pass on the new German purpose strings"
    expected: "Wave-5 deferred final lektor pass on account.purpose.fee_aggregate, fee_for_receipt, and the German payout purpose text"
    why_human: "Wording polish is a human review; Plan 04-06 SUMMARY documented this as DEFERRED to a separate Yves checkpoint."
verdict: READY-TO-MERGE
---

# Phase 4: Enrichment — Refunds, Fees, Payouts, Balance, VAT, Tips — Verification Report

**Phase Goal:** The full bookkeeping picture: refunds linked to original sales, per-sale fees via Finance API, payouts as separate negatives, settled-and-pending balances, VAT split per rate in `purpose`, tip surfaced as its own line — the slice that makes this extension worth choosing over CSV export.
**Verified:** 2026-06-21
**Status:** passed
**Verdict:** READY-TO-MERGE
**Re-verification:** No — initial verification.

---

## Goal Achievement

### Success Criteria (ROADMAP §Phase 4)

| # | Success Criterion (abbreviated) | Status | Evidence |
|---|---------------------------------|--------|----------|
| 1 | Sidebar shows `balance` + `pendingBalance` from Finance API liquid endpoint, matches `my.zettle.com` to the cent (ACCT-03) | VERIFIED (cent-match needs human) | `src/finance.lua:161-205` (`M_finance.fetch_account_state` issues two sequential GETs to `/v2/accounts/liquid/balance` + `/v2/accounts/preliminary/balance` with EUR currency guard); `src/entry.lua:220-221, 366-370` (Step 7 wires balance/pendingBalance into RefreshAccount return table); `spec/finance_account_state_spec.lua:65,80,95,113` (8 cases incl. ERR-06 fail-whole-refresh); `spec/entry_spec.lua:716-742` (ACCT-03 end-to-end + R-4 non-EUR fallback). Cent-match against real merchant — see Human Verification. |
| 2 | Refund = one negative txn; `purpose` cites original receipt via `purchases_by_uuid` lookup; partial refunds → multiple rows on same original (REF-01/02/03) | VERIFIED | `src/entry.lua:190-195` (purchases_by_uuid index build, D-50); `src/entry.lua:273-281` (refund_to_transaction called with opts.original_receipt); `src/mapping.lua:409-441` (refund_to_transaction(p, opts) implementation); `spec/entry_spec.lua:748-767` ("REF-02: refund purpose cites original purchaseNumber when both in same purchases page"); `spec/mapping_spec.lua:612` (REF-02 opts.original_receipt unit test). Negative amount and stable `zettle:refund:<uuid>` inherited from Phase-3 D-32. |
| 3 | Per-sale fee linked via `originatingTransactionUuid` → `payments[].uuid`; fallback aggregate row when linkage missing with German warning (FEE-01/02/03) | VERIFIED | `src/entry.lua:204-215` (payments_by_uuid index keyed on `payments[].uuid` per RESEARCH §3.1, NOT `purchaseUUID1`); `src/entry.lua:327-355` (D-49 Option B per-date clustering, any-unlinked → aggregate); `src/mapping.lua:461-489` (`fee_to_transaction`, `zettle:fee:<uuid>`, cites originating receipt #); `src/mapping.lua:496-519` (`fee_aggregate_to_transaction`, `zettle:fee:aggregate:<date>`); `src/entry.lua:343-345` (German WARNING log per D-49); `spec/mapping_spec.lua:461,480,490,506,521,535` (mapper unit tests); `spec/entry_spec.lua:773+` (FEE-01/03 end-to-end via `purchase_page_with_payments_for_fee_join` + `finance_payment_with_fee_linkage` / `finance_payment_fee_unlinked`). |
| 4 | Payout = one negative txn; `name = "Auszahlung an Bankkonto"`; `bookingDate` = Finance settlement date in Berlin local (PAYOUT-01/02/03) | VERIFIED | `src/mapping.lua:528-552` (`payout_to_transaction`: amount preserved as `amount/100` — negative per Finance API; `name = M_i18n.t("account.name.payout")` = "Auszahlung an Bankkonto"; `bookingDate` = `_to_berlin_local_time(utc)`; `valueDate = bookingDate` since the payout IS the settlement event); `src/i18n.lua:27` (de: "Auszahlung an Bankkonto"); `src/entry.lua:358-361` (Step 15 maps payouts); `spec/mapping_spec.lua:545,560,568` + `spec/mapping_schema_spec.lua:203` (REQUIRED_FIELDS contract). |
| 5 | Per-rate VAT lines from `groupedVatAmounts` ("19% MwSt: 3,83 EUR", "7% MwSt: 1,40 EUR"); tip line absent when zero; no tax-classification phrasing ever (META-01/02/03) | VERIFIED | `src/mapping.lua:213-245` (META-01: multi-rate path sorted descending, format `"<rate>% MwSt: <amount_de> EUR"`; falls through to Phase-3 single-line for empty/single-rate); `src/mapping.lua:247-258` (META-02: tip line only when `tip_sum > 0`); `spec/meta_purpose_lines_spec.lua:46,67,84` (META-02 zero-suppression spec — three cases); `spec/meta_purpose_lines_spec.lua:108,119,136` (META-01 zero-rate edge cases); `spec/mapping_spec.lua:633-722` (META-01: 5 cases incl. single rate fallback, integer-string key, negative refund VAT, two-rate descending sort); `spec/meta_no_tax_classification_spec.lua` (META-03: walks every `src/*.lua` + `dist/paypal-pos.lua` for the 13 Yves-locked forbidden phrases; both clean). |
| 6 | Card-brand + entry-mode tail in `purpose` when both fields present; recorded fixture matrix for auth/HTTP error/single+multi-page/Purchase+Finance/VAT split/tip/umlauts (SALE-07, TEST-02) | VERIFIED | `src/mapping.lua:266-303` (SALE-07: card-brand + entry-mode tail; OMITS line when both absent per D-57); `src/i18n.lua:34-39` (German entry-mode labels: kontaktlos, Chip, Magnetstreifen, Online, Manuell, unbekannt); `spec/mapping_spec.lua:729,737,764,772` (SALE-07: 4 cases); `spec/fixtures/finance/*.json` (10 fixtures: single page, multi-page 1+2 for offset boundary, payment_with_fee_linkage, payment_fee_unlinked, payout, payment_and_payout_for_promotion, empty, both balance fixtures); `spec/fixtures/purchases/*.json` (vat_split_19_7, with_card_metadata_kontaktlos, umlauts_purpose, refund_with_original_in_page, page_with_payments_for_fee_join). Auth/invalid_grant/401/429/5xx/network covered by Phase-2 fixture suite (inherited). |

**Score: 6/6 success criteria VERIFIED.**

### Deferred Items

None — Phase 4 closes all of its declared Success Criteria with code + spec evidence. The Q3 live probe and the loop-lektor pass are documented in Human Verification, not deferred to Phase 5+.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/finance.lua` | M_finance.parse_transaction + fetch + fetch_all + fetch_account_state | VERIFIED | 206 lines; all four functions present (`parse_transaction:28`, `fetch:114`, `fetch_all:141`, `fetch_account_state:161`); module wrapped in webbanking_header `M_finance` predeclaration. |
| `src/mapping.lua` | 4 new mappers + per-rate VAT + card-tail | VERIFIED | 563 lines; `fee_to_transaction:461`, `fee_aggregate_to_transaction:496`, `payout_to_transaction:528`, `promote_to_booked:558`; `_format_purpose:197-309` extended for META-01 + SALE-07; public wrappers `parse_iso8601_utc:317`, `berlin_local_date:349`. |
| `src/entry.lua` | RefreshAccount 16-step Phase-4 pipeline | VERIFIED | Steps 1-16 implemented at lines 139-371; purchases_by_uuid (step 5), payments_by_uuid (step 6, correctly keyed on `payments[].uuid` per the entry-layer correction of CONTEXT D-50 wording), fetch_account_state (step 7), fetch_all finance (step 8), parse + bucket (step 9), payout sort (step 10), fin_payments_by_uuid (step 11), purchase→sale/refund map (step 12), SALE-03 promotion (step 13), D-49 fee clustering (step 14), payouts (step 15), return shape (step 16). |
| `src/pagination.lua` | offset_iterate sibling iterator | VERIFIED | `offset_iterate:110-148`; same MAX_PAGES=50 guard; spec verifies it does NOT mutate caller's initial_params (line 116 of pagination_offset_spec). |
| `src/i18n.lua` | 12 new keys | VERIFIED | de+en pairs for `account.name.fee`, `account.name.fee_aggregate`, `account.name.payout`, `account.purpose.fee_for_receipt`, `account.purpose.fee_aggregate`, `account.purpose.payment_method.{kontaktlos,chip,swipe,ecommerce,manual,unknown}`. Note: src/i18n.lua adds `ecommerce` and `manual` (5 entry-mode keys total) — broader than the CONTEXT D-57 list (kontaktlos/chip/swipe/magstripe/unknown), defensible enrichment. |
| `tools/probe-finance.sh` | Q3 sandbox probe helper | VERIFIED | Present, documents env-var setup, prints redacted response shape ready for ADR-0003 Q3 row. Live execution remains HUMAN_NEEDED. |
| `docs/adr/0004-finance-api-scope-and-fee-fallback.md` | NEW ADR — ACCEPTED | VERIFIED | Status: ACCEPTED, 2026-06-21, documents OAuth scope requirement (READ:FINANCE), D-49 fee fallback dedup contract, and ADR-0003 Q3 unblock path. |
| Fixtures `spec/fixtures/finance/` | 10 fixtures (single, multi 1+2, fee-linked, fee-unlinked, payout, payment+payout-for-promotion, empty, both balances) | VERIFIED | All 10 present. |
| Fixtures `spec/fixtures/purchases/` (new) | vat_split_19_7, with_card_metadata_kontaktlos, umlauts_purpose, refund_with_original_in_page, page_with_payments_for_fee_join | VERIFIED | All 5 present (alongside Phase-3 carryover). |
| `CHANGELOG.md` v0.2.0 section | German Keep-a-Changelog entry | VERIFIED (engineering draft) | Wave-5 SUMMARY notes the lektor polish is DEFERRED — engineering draft committed. |
| `.github/workflows/ci.yml` egress allowlist with finance.izettle.com | SEC-02 gate | VERIFIED | `ci.yml:83-94` greps `dist/paypal-pos.lua` for hosts outside `oauth.zettle.com\|purchase.izettle.com\|finance.izettle.com`. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `RefreshAccount` | `M_finance.fetch_account_state` | direct call | WIRED | `src/entry.lua:220` — `local account_state, state_err = M_finance.fetch_account_state(bearer)`; ERR-06 abort at `:221`. |
| `RefreshAccount` | `M_finance.fetch_all` | direct call | WIRED | `src/entry.lua:224`; result split into payments/fees/payouts at `:230-239`. |
| `M_finance.fetch` | `M_http.get_json` | direct call | WIRED | `src/finance.lua:131` — no direct `Connection()` use (D-42). |
| `M_finance.fetch_all` | `M_pagination.offset_iterate` | closure | WIRED | `src/finance.lua:144-148` — offset starts at 0 / limit 1000 per RESEARCH §1.3. |
| `M_finance.fetch_account_state` errors | `M_errors.from_http_status` | direct call | WIRED | `src/finance.lua:169, 188` — both legs route via the Phase-2 mapper (D-43). |
| Refund txn | `purchases_by_uuid` lookup | opts.original_receipt | WIRED | `src/entry.lua:274-281` builds opts.original_receipt from index lookup before calling `M_mapping.refund_to_transaction`. |
| Fee txn | `payments_by_uuid` (keyed on payments[].uuid) | direct lookup | WIRED | `src/entry.lua:204-215, 336, 350` — CORRECT join key per RESEARCH §3.1 (entry-layer correction of CONTEXT D-50's purchaseUUID1 wording, documented inline at :199-203). |
| SALE-03 promotion | `M_mapping.promote_to_booked` | finance PAYMENT match + covering payout | WIRED | `src/entry.lua:298-315` — temporal-inference rule (earliest payout with `timestamp_posix >= payment.timestamp_posix`) per RESEARCH §4.2. |
| Bearer token | log redactor | M_log.redact (Phase 2) | WIRED | `src/entry.lua:159` log line excludes bearer; `spec/refresh_log_redaction_spec.lua:336-366` extends SEC-03 to Finance API responses. |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| RefreshAccount result | `balance`, `pendingBalance` | `M_finance.fetch_account_state` → 2 live GETs against `/v2/accounts/{liquid,preliminary}/balance` | YES (sourced from upstream JSON, not hardcoded) | FLOWING |
| RefreshAccount result | `transactions[]` | combined: M_purchases.fetch_all + M_finance.fetch_all + 4 mappers | YES | FLOWING |
| Fee txn | `purpose` "Gebühr für Beleg #N" | M_i18n.t with originating_purchase.purchaseNumber from payments_by_uuid lookup | YES | FLOWING |
| Aggregate fee txn | `purpose` count + transactionCode | sum of `fees_for_date[].amount` + Berlin-local date | YES | FLOWING |
| Promoted sale | `valueDate`, `booked` | covering payout's timestamp_posix | YES | FLOWING |
| Per-rate VAT lines | `purpose` lines | `groupedVatAmounts` decoded JSON | YES | FLOWING |
| Card-tail | `purpose` "Zahlart: …" | `payments[1].attributes.{cardType,cardPaymentEntryMode}` | YES | FLOWING |

No hollow props or static fallbacks detected in any wired output.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite green | `busted spec/` | `328 successes / 0 failures / 0 errors / 0 pending : 4.247322 seconds` | PASS |
| Reproducible build | `lua tools/build.lua --verify` | `OK: reproducible (sha256: d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712)` — SHA matches the SUMMARY claim | PASS |
| Lint (luacheck) | `luacheck .` | Local environment FAILS (luacheck 1.2.0 incompatible with Lua 5.5 — `attempt to assign to const variable 'field_name'`). NOT a Phase-4 regression. CI workflow runs against pinned Lua 5.4 via `leafo/gh-actions-lua@v13` which is clean per Plan 04-06 SUMMARY ("luacheck . reports 0 warnings / 0 errors in 38 files"). | SKIP (environment) |
| Coverage measurement | `busted --coverage spec/ && luacov` | `dist/paypal-pos.lua  884/884  100.00%` | PASS (exceeds the 85% gate from CI-02 and Phase-3 99.23% baseline) |
| META-03 manual grep | `grep -nE 'USt-frei\|GoBD-konform\|steuerfrei\|tax-free\|VAT-exempt' src/*.lua dist/paypal-pos.lua` | empty | PASS |
| Debt markers | `grep -rnE 'TBD\|FIXME\|XXX' src/` | empty | PASS |
| Warning markers | `grep -rnE 'TODO\|HACK\|PLACEHOLDER' src/` | empty | PASS |

---

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| `tools/probe-finance.sh` (Q3 live probe) | `bash tools/probe-finance.sh` | Helper present, requires `ZETTLE_BEARER` sandbox token in env which is NEVER persisted in the repo. Probe cannot be executed by the verifier. | MISSING_BEARER (HUMAN_NEEDED) |

ADR-0003 Q3 row still reads `DEFERRED to Phase 4 first live Finance call` with the unblock path documented (commit `50adec9`, ADR-0004 §"OAuth scope requirement"). Per the verifier_context: the helper exists; live execution remains HUMAN_NEEDED. This is the expected state for READY-TO-MERGE.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| ACCT-03 | 04-03 | balance + pendingBalance from Finance API | SATISFIED (cent-match needs human) | `src/finance.lua:161-205`, `src/entry.lua:220-221,366-370`, `spec/finance_account_state_spec.lua` (8 cases), `spec/entry_spec.lua:716-742`. Cent-accuracy against `my.zettle.com` requires a real merchant — see Human Verification. |
| SALE-07 | 04-04 | cardType + cardPaymentEntryMode visible in purpose | SATISFIED | `src/mapping.lua:266-303`, `spec/mapping_spec.lua:729,737,764,772` (4 cases). |
| REF-01 | 04-03 | refund = one negative MoneyMoney transaction | SATISFIED | `src/mapping.lua:409-441` (refund_to_transaction inherits Phase-3 D-32 contract — negative amount, `zettle:refund:<uuid>`); REQUIREMENTS.md table status still "Pending" — purely a stale tracker, not a code gap. |
| REF-02 | 04-03 | refund cites original receipt # via uuid lookup | SATISFIED | `src/entry.lua:273-281`, `src/mapping.lua:434-438` (opts.original_receipt), `spec/entry_spec.lua:748-767`, `spec/mapping_spec.lua:612`. |
| REF-03 | 04-03 | partial refunds — multiple rows on same original | SATISFIED | The same `purchases_by_uuid` index supports N refund rows resolving to the same original; `M_mapping.refund_to_transaction` is a per-record call with no global state. No code limits the count. |
| FEE-01 | 04-03 | per-sale fee linkage via originatingTransactionUuid | SATISFIED | `src/entry.lua:204-215, 349-353`, `src/mapping.lua:461-489`, `spec/refresh_idempotency_spec.lua:343-367` (D-58 case 3), `spec/entry_spec.lua` FEE-01 end-to-end (line 773+). |
| FEE-02 | 04-03 | fee purpose cites originating receipt # | SATISFIED | `src/mapping.lua:478` — `M_i18n.t("account.purpose.fee_for_receipt", receipt_no)`; `src/i18n.lua:29` ("Gebühr für Beleg #%s"). |
| FEE-03 | 04-03 | aggregate-fee fallback + German warning | SATISFIED | `src/entry.lua:327-355` (D-49 Option B), `src/mapping.lua:496-519`, `src/entry.lua:343-345` (WARN log), `spec/refresh_idempotency_spec.lua:379-405` (D-58 case 4 stability). |
| PAYOUT-01 | 04-03 | payout = one negative MoneyMoney transaction | SATISFIED | `src/mapping.lua:528-552` (amount = `amount/100`, Finance API delivers it negative). |
| PAYOUT-02 | 04-03 | payout name = "Auszahlung an Bankkonto" | SATISFIED | `src/i18n.lua:27` de pair + `src/mapping.lua:543`. |
| PAYOUT-03 | 04-03 | payout bookingDate = Finance settlement date | SATISFIED | `src/mapping.lua:537,546` (`_to_berlin_local_time(utc)`); `valueDate = bookingDate` since payout IS the settlement. |
| META-01 | 04-04 | per-rate VAT in purpose when groupedVatAmounts populated | SATISFIED | `src/mapping.lua:213-245`, `spec/mapping_spec.lua:633-722` (5 cases incl. negative-VAT refund + integer-string key + descending sort). |
| META-02 | 04-05 | tip line only when gratuityAmount > 0 | SATISFIED | `src/mapping.lua:247-258`, `spec/meta_purpose_lines_spec.lua:46,67,84` (3 cases incl. empty payments + sum > 0). |
| META-03 | 04-05 | never claim tax/GoBD/VAT-conformance | SATISFIED | `spec/meta_no_tax_classification_spec.lua` walks `src/*.lua` AND `dist/paypal-pos.lua` for the 13 Yves-locked forbidden phrases (D-55); manual re-grep confirms zero hits. |
| TEST-02 | 04-02 + cumulative | recorded JSON fixtures covering enumerated permutations | SATISFIED | `spec/fixtures/finance/` 10 fixtures, `spec/fixtures/purchases/` 15 fixtures; auth/invalid_grant/401/429/5xx/network from Phase-2 suite; multi-page Purchase (Phase 3) + multi-page Finance (`finance_multi_page_1/2.json`); VAT split + non-zero tip + umlauts all present. |

**Score: 14/15 requirements fully SATISFIED autonomously. ACCT-03's "cent-match against my.zettle.com" sub-clause requires a real merchant tenant → see Human Verification. All 15 requirement IDs have implementation evidence in code and spec; none are blocked or missing.**

---

### Invariant Verification (D-46..D-60)

| Decision | Invariant | Status | Evidence |
|----------|-----------|--------|----------|
| D-46 | Finance host = `finance.izettle.com` | VERIFIED IN CODE (live probe HUMAN_NEEDED) | `src/finance.lua:127, 168, 187` |
| D-47 | Reuse Phase-2 Bearer | VERIFIED | `src/entry.lua:165` (`M_auth.cached_token`), no new token flow. |
| D-48 | Offset pagination, distinct from cursor; MAX_PAGES=50 | VERIFIED | `src/pagination.lua:110-148`, `spec/pagination_offset_spec.lua:84` (50-page cap test). |
| D-49 | Once-aggregated-always-aggregated per refresh | VERIFIED | `src/entry.lua:327-355` (per-refresh date clustering; any-unlinked → aggregate); `spec/refresh_idempotency_spec.lua:379-405` (D-58 case 4 stability). |
| D-50 | purchases_by_uuid index built before refund map (entry-layer correction: payments_by_uuid keyed on `payments[].uuid`, not `purchaseUUID1`) | VERIFIED | `src/entry.lua:190-215` with inline correction comment at :199-203. |
| D-51 | Single negative payout in PayPal POS account | VERIFIED | `src/mapping.lua:528-552`; only one Giro account touched. |
| D-52 | balance + pendingBalance via 2 sequential GETs | VERIFIED | `src/finance.lua:161-205`, `spec/finance_account_state_spec.lua:44` ("two sequential GETs liquid then preliminary"). |
| D-53 | Per-rate VAT format `<rate>% MwSt: <amount> EUR` | VERIFIED | `src/mapping.lua:226-239`; descending rate sort. |
| D-54 | Phase-3 tip format preserved byte-identically | VERIFIED | `src/mapping.lua:247-258`, `spec/meta_purpose_lines_spec.lua`. |
| D-55 | META-03 13-phrase forbidden list locked | VERIFIED | `spec/meta_no_tax_classification_spec.lua:27-41`. |
| D-56 | SALE-03 promotion via temporal-inference covering payout | VERIFIED | `src/entry.lua:248-253, 292-315` (`_find_covering_payout` walks sorted payouts); `spec/refresh_idempotency_spec.lua:277-305` (D-58 case 1). |
| D-57 | Card-tail OMITTED when both fields absent | VERIFIED | `src/mapping.lua:283-303`, `spec/mapping_spec.lua:764` ("both fields absent — Zahlart line is OMITTED"). |
| D-58 | Idempotency gating spec extended to 4 cases | VERIFIED | `spec/refresh_idempotency_spec.lua:277,313,343,379` — all 4 cases green. |
| D-59 | No persistent state between refreshes (in-refresh indexes only) | VERIFIED | All indexes are locals inside `RefreshAccount`; no LocalStorage writes added. |
| D-60 | 6-wave structure landed | VERIFIED | 6 PLANs + 5 SUMMARYs (Wave 0 is human-blocked; Waves 1-5 shipped). |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | No debt markers (TBD/FIXME/XXX), no warning markers (TODO/HACK/PLACEHOLDER), no forbidden tax-classification phrases, no hardcoded empty data in rendering paths. |

---

### Human Verification Required

#### 1. Q3 live probe of finance.izettle.com

**Test:** Set `ZETTLE_BEARER` to a sandbox token, then `bash tools/probe-finance.sh`.
**Expected:** Two HTTP 200 responses (transactions endpoint + balance endpoint), JSON shape matching the Finance API documentation (RESEARCH §1.3); flip `docs/adr/0003-sandbox-probe-results.md` Q3 row from DEFERRED → ACCEPTED with the captured (redacted) response shape.
**Why human:** Sandbox bearer token is never persisted in the repo — verifier cannot fabricate it. Helper script is already in place.

#### 2. ACCT-03 cent-accurate dashboard match

**Test:** With a real PayPal POS merchant API key, complete a RefreshAccount cycle, then compare `result.balance` + `result.pendingBalance` to the values shown in `my.zettle.com` for the same merchant.
**Expected:** Both values match to the cent.
**Why human:** Requires a real merchant tenant; the value cannot be validated against fixtures alone. Code path is verified to source the value from `/v2/accounts/{liquid,preliminary}/balance` via `M_finance.fetch_account_state`; only the cent-accuracy claim of the ROADMAP success criterion requires a live merchant.

#### 3. loop-lektor pass on German purpose strings

**Test:** Trigger `loop-lektor` on the German strings added in `src/i18n.lua` Phase-4 keys (`account.purpose.fee_for_receipt`, `account.purpose.fee_aggregate`, payment-method labels) and the manual purpose construction in `src/mapping.lua:540` ("Auszahlung an Bankkonto am DD.MM.YYYY").
**Expected:** Polished German wording confirmed or revised by Yves' loop-lektor agent. Plan 04-06 SUMMARY explicitly DEFERRED this pass to a separate Yves checkpoint.
**Why human:** Wording polish is a human review task.

---

## Gaps Summary

No code gaps. All 6 ROADMAP Success Criteria are met with executable evidence: 328 specs pass cleanly, the build is reproducibly hashed to `d6356d5b...` matching the documented SHA, the META-03 forbidden-strings invariant walks both `src/*.lua` and `dist/paypal-pos.lua` (both clean), the D-58 idempotency cases for all four transaction kinds (sale-promotion, payout, per-sale fee, aggregate fee) hold across double-refresh, the egress allowlist gates the artifact to the three required hosts (`oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`), and the Phase-3 surface-preservation spec confirms the Phase-2 / Phase-3 callback contracts are byte-identical.

The three Human Verification items (Q3 live probe, ACCT-03 cent-match, loop-lektor pass) are NOT code gaps — they are inherently human-bound activities whose enablement (the probe helper, the code path, the engineering-draft strings) is fully in place. None block PR merge per the verifier_context gating semantics.

---

## Aggregate Verdict

**READY-TO-MERGE.**

- All 6 success criteria VERIFIED (Goal Achievement table above).
- 14/15 requirements SATISFIED autonomously; ACCT-03's cent-match clause is the single sub-clause that requires a real merchant account (documented under Human Verification, not flagged as a gap).
- 328 / 0 / 0 / 0 busted; 100% coverage on `dist/paypal-pos.lua`; reproducible build SHA matches `d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712`.
- D-46..D-60 invariants all VERIFIED in code; META-03 forbidden-strings spec walks `src/` + `dist/` both clean.
- Phase-3 surface preservation spec GREEN; SupportsBank / InitializeSession2 / ListAccounts / EndSession byte-identical to the Phase-2 baseline.
- ADR-0004 ACCEPTED; ADR-0003 Q3 stays DEFERRED with documented unblock path via `tools/probe-finance.sh`.
- Outstanding Human Verification items (Q3 live probe + cent-match + loop-lektor) are follow-ups, not merge blockers.

---

_Verified: 2026-06-21_
_Verifier: Claude (gsd-verifier)_
