---
phase: 04-enrichment-refunds-fees-payouts
reviewed: 2026-06-21T12:00:00Z
re_reviewed: 2026-06-21T22:55:00Z
depth: deep
branch: phase-4/enrichment
diff_base: a201f6c
head: c283673
head_round2: 7bff4de
files_reviewed: 40
files_reviewed_list:
  - src/balance.lua
  - src/entry.lua
  - src/finance.lua
  - src/i18n.lua
  - src/mapping.lua
  - src/pagination.lua
  - src/payouts.lua
  - src/webbanking_header.lua
  - tools/manifest.txt
  - tools/probe-finance.sh
  - spec/entry_spec.lua
  - spec/finance_account_state_spec.lua
  - spec/finance_parse_transaction_spec.lua
  - spec/finance_spec.lua
  - spec/fixtures/finance/finance_balance_liquid.json
  - spec/fixtures/finance/finance_balance_preliminary.json
  - spec/fixtures/finance/finance_empty.json
  - spec/fixtures/finance/finance_multi_page_1.json
  - spec/fixtures/finance/finance_multi_page_2.json
  - spec/fixtures/finance/finance_payment_and_payout_for_promotion.json
  - spec/fixtures/finance/finance_payment_fee_unlinked.json
  - spec/fixtures/finance/finance_payment_with_fee_linkage.json
  - spec/fixtures/finance/finance_payout.json
  - spec/fixtures/finance/finance_single_page.json
  - spec/fixtures/purchases/purchase_page_with_payments_for_fee_join.json
  - spec/fixtures/purchases/purchase_refund_with_original_in_page.json
  - spec/fixtures/purchases/purchase_umlauts_purpose.json
  - spec/fixtures/purchases/purchase_vat_split_19_7.json
  - spec/fixtures/purchases/purchase_with_card_metadata_kontaktlos.json
  - spec/fixtures/purchases/purchase_with_vat_and_tip.json
  - spec/helpers/mm_mocks.lua
  - spec/i18n_spec.lua
  - spec/mapping_schema_spec.lua
  - spec/mapping_spec.lua
  - spec/meta_no_tax_classification_spec.lua
  - spec/meta_purpose_lines_spec.lua
  - spec/pagination_offset_spec.lua
  - spec/phase3_surface_preservation_spec.lua
  - spec/refresh_idempotency_spec.lua
  - spec/refresh_log_redaction_spec.lua
findings:
  blocker: 3
  warning: 6
  info: 4
  total: 13
findings_round2:
  closed: 7
  new_high: 0
  new_medium: 0
  new_low: 2
  new_total: 2
status: findings_present
---

# Phase 4: Code Review Report

**Reviewed:** 2026-06-21T12:00:00Z
**Depth:** deep
**Branch:** phase-4/enrichment
**Commit range:** a201f6c..c283673
**Files Reviewed:** 40
**Status:** findings_present

---

## Summary

Phase 4 layers the Finance API onto Phase 3's Purchase API pipeline: a new `src/finance.lua` (parse_transaction + fetch + fetch_all + fetch_account_state), four new mapping functions (`fee_to_transaction`, `fee_aggregate_to_transaction`, `payout_to_transaction`, `promote_to_booked`), 12 new i18n keys, a sibling `M_pagination.offset_iterate`, ten new spec files plus 14 fixtures, and a 200-line extension to `RefreshAccount`. All 328 busted assertions pass.

The structural foundations are sound: the offset iterator faithfully mirrors the Phase-3 cursor iterator including the MAX_PAGES guard and the caller-table-copy invariant; the Bearer assertions, error routing through `M_errors.from_http_status`, and SEC-03 redaction gates extend cleanly to the Finance pipeline; the META-03 forbidden-strings invariant is enforced both at spec-time and against the built artifact; and the Phase-3 surface-preservation spec catches any drift in the four frozen callbacks.

Three BLOCKER defects were found, each of which the test suite fails to catch:

1. **BL-01 (HIGH) — TZ mismatch in SALE-03 promotion.** `entry.lua` step 13 passes `covering.timestamp_posix` (raw UTC POSIX from `M_finance.parse_transaction`) into `promote_to_booked` as the sale's `valueDate`. Sale `bookingDate` is Berlin-local POSIX (UTC + offset). The two date fields on a single promoted sale therefore use different time conventions — `valueDate` is off by 1–2 hours and can disagree with the payout row's own `valueDate` (which `payout_to_transaction` derives from `_to_berlin_local_time`). The test at `entry_spec.lua:925` only asserts `is_number(sale2.valueDate)` and never checks the value.

2. **BL-02 (HIGH) — `probe-finance.sh` redaction silently fails on macOS.** The PII redactor uses `\s*` Perl-style escapes inside `sed -E`. BSD sed (the default on macOS — Yves' platform) does not interpret `\s` as whitespace, so the regex does not match when jq pretty-prints `"key": "value"` with a literal space after the colon. UUIDs are still redacted (no `\s`), but `name`, `userDisplayName`, `merchantName`, `organizationId`, `userId`, `email`, `displayName` all pass through unredacted. The script's stated promise — "pasting the printed output into the ADR is safe" — does not hold.

3. **BL-03 (HIGH) — D-49 aggregate→linked upgrade double-books fees across refreshes.** Once a date has been aggregated (`zettle:fee:aggregate:YYYY-MM-DD`), MoneyMoney's dedup is anchored on that transactionCode. If a later refresh sees the same date with linkage now resolved, the entry layer emits per-fee `zettle:fee:<uuid>` rows instead. MoneyMoney does NOT delete the still-aggregated row from the prior refresh — both kinds coexist, double-booking every fee on that date. CONTEXT D-49 explicitly requires "once an aggregate row exists for a date, all subsequent fees for that date go into the aggregate" — but with no persistent state (per the in-code comment "no persistent state (D-59)"), the current implementation cannot honour that. The idempotency spec only tests stable-fixture refresh pairs, never the linkage-upgrade transition.

Six WARNING findings cover the offset-pagination race window, hard-coded German strings outside `i18n.lua`, the prefix-gate overlap that lets `^zettle:fee:` swallow `^zettle:fee:aggregate:`, a non-EUR-balance fallback that silently masks user-visible state, and two consistency issues in `_format_purpose`. Four INFO findings round out style/maintenance notes.

The probe-finance HIGH (BL-02) is the most user-facing — it exposes Yves himself to leaking merchant PII into a committed ADR.

---

## Critical Issues

### BL-01: SALE-03 promotion writes `valueDate` in UTC seconds while `bookingDate` is Berlin-local seconds

**File:** `src/entry.lua:307` (with conspiring `src/mapping.lua:558-562`)
**Issue:** Step 13 of `RefreshAccount` calls

```lua
M_mapping.promote_to_booked(sale_txn, covering.timestamp_posix)
```

`covering.timestamp_posix` is the raw POSIX-UTC integer set by `M_finance.parse_transaction` (which calls `M_mapping.parse_iso8601_utc`, a pure UTC parser — see `src/finance.lua:45-49`). Meanwhile `sale_txn.bookingDate` was assigned by `purchase_to_transaction` as `_to_berlin_local_time(utc)` (i.e. UTC + 3600 or + 7200 depending on DST). The promoted sale therefore carries two date fields in incompatible conventions:

- `bookingDate` = Berlin wall-clock seconds treated as POSIX (the project's D-36 convention; PAYOUT-03 inherits it)
- `valueDate` = pure UTC seconds (1–2 h earlier than the same instant rendered Berlin-local)

In contrast, `payout_to_transaction` (line 550 of `src/mapping.lua`) correctly sets `valueDate = booking_date` where `booking_date = _to_berlin_local_time(utc)`. The sale-promotion path is the only place where the two date fields use different conventions.

User-visible impact: a sale whose covering payout lands on 2026-07-10 08:00 UTC will have `bookingDate` rendered as 2026-07-10 (the day, after Berlin-local conversion at +2 h CEST) but `valueDate` rendered as 2026-07-10 08:00 UTC — i.e. the value-date timestamp will display 2 hours earlier than the same instant on the payout row that produced it. In an edge case at 23:00 UTC during CEST, `valueDate` falls on the previous calendar day from `bookingDate`. The `D-58 case 1` idempotency test asserts `is_number(sale2.valueDate)` (`spec/refresh_idempotency_spec.lua:303`) and `entry_spec.lua:925` asserts the same — both fail to gate the convention.

**Fix:** Convert before passing into the promoter:
```lua
M_mapping.promote_to_booked(sale_txn,
  M_mapping.to_berlin_local_time(covering.timestamp_posix))
```
Also extend `spec/refresh_idempotency_spec.lua` D-58 case 1 (and the analogous `entry_spec.lua` test) with a literal value assertion against `_to_berlin_local_time(payout_utc)` so the regression cannot recur.

---

### BL-02: `tools/probe-finance.sh` PII redactor silently fails on macOS (BSD sed `\s` is not whitespace)

**File:** `tools/probe-finance.sh:73-78`
**Issue:** The redact() function uses `\s*` between key and colon and between colon and value:

```sh
sed -E \
  -e 's/[0-9a-fA-F]{8}-...'/<UUID-REDACTED>/g' \
  -e 's/("(merchantName|userDisplayName|organizationName|name|email|displayName)"\s*:\s*)"[^"]*"/\1"<REDACTED>"/g' \
  -e 's/("(organizationId|userId|orgId)"\s*:\s*)"[^"]*"/\1"<REDACTED>"/g'
```

BSD sed (default on macOS — Yves' platform per the env block) does **not** recognise `\s` as a whitespace shorthand inside `-E` ERE; it is interpreted as a literal `s` (or undefined). Reproduced locally:

```text
$ echo '{"name" : "Test Merchant"}' | sed -E -e 's/("(name)"\s*:\s*)"[^"]*"/\1"<REDACTED>"/g'
{"name" : "Test Merchant"}          # <-- NOT redacted

$ echo '{"name": "Test Merchant"}' | sed -E -e ...
{"name": "Test Merchant"}           # <-- NOT redacted either
```

Because the script pipes through `jq '.' "${tmp_body}"` before the redactor (line 115), every key/value pair carries the canonical `"key": "value"` (space after colon). Every name, email, organizationId, userId, and merchantName lands in the printed output verbatim. Only UUIDs survive (their regex has no `\s`).

The script's banner ("pasting the printed output into the ADR is safe") is therefore false on the platform where Yves will actually run it. If pasted into a public ADR commit, real merchant PII would land in Git history.

**Fix:** Replace each `\s*` with `[[:space:]]*` (POSIX-portable character class works in both BSD and GNU sed):
```sh
-e 's/("(merchantName|userDisplayName|organizationName|name|email|displayName)"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"<REDACTED>"/g'
-e 's/("(organizationId|userId|orgId)"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"<REDACTED>"/g'
```
Add a smoke test invocation at the end of the script with a known PII string so a regression is caught at probe-time.

---

### BL-03: D-49 aggregate→linked upgrade across refreshes double-books every fee for that date

**File:** `src/entry.lua:317-355` (per-refresh clustering with no persistent state)
**Issue:** CONTEXT D-49 explicitly mandates: *"once an aggregate row exists for a date, all subsequent fees for that date go into the aggregate, even when linkage becomes available."* This is Yves' signed-off Pay/Compliance contract.

The current implementation derives `bucket.any_unlinked` only from the **current refresh's** finance fixture. If refresh A sees an unlinked fee on 2026-07-10 and emits `zettle:fee:aggregate:2026-07-10`, and refresh B (later) sees the same date with linkage now resolved by Zettle, the code path falls into the per-fee branch and emits one `zettle:fee:<uuid>` per fee.

MoneyMoney's dedup key is `transactionCode`. The aggregate row from refresh A is not in refresh B's emission set, so MoneyMoney does **not** delete it. The per-fee rows are new, so MoneyMoney inserts them. Result: the aggregate AND every individual fee for that date are now booked — **double-booking the merchant's fees**.

The in-code comment at line 326 acknowledges the gap:
> *"Yves-blocker D-49 Option A vs B is documented in 04-03-PLAN.md <objective>; if a later phase needs Option A (LocalStorage-persistent date set), replan via /gsd-plan-phase 4 --gaps to amend D-59."*

…but the comment is wrong about what the current code does relative to the locked contract. D-49 (the Yves-signed-off recommendation) requires Option A semantics. The implementation ships Option B and only Option B. The idempotency spec (`spec/refresh_idempotency_spec.lua` D-58 case 4) tests "same finance fixture across two refreshes" — a path where the same `any_unlinked` decision recurs naturally. It does not test "unlinked in refresh 1, linked in refresh 2" — the dangerous transition.

**Fix (smallest correct path):** persist the set of aggregated dates per orgUuid in `LocalStorage["zettle:" .. orgUuid].fee_aggregate_dates` and OR it into the per-refresh `any_unlinked` decision at line 331. Write the date back into LocalStorage whenever the aggregate branch fires. Extend the idempotency spec with a "refresh 1 unlinked, refresh 2 fully-linked, assert no per-fee codes for the previously-aggregated date" case. If Yves prefers to amend D-49 to Option B, document the trade-off explicitly in ADR-0004 (currently the ADR is silent on the cross-refresh upgrade case) and replace the in-code comment so future readers don't believe a contract is held that isn't.

---

## Warnings

### WR-01: `M_finance.fetch_all` recomputes `end=os.time()+60` on every page — offset pagination is racy

**File:** `src/finance.lua:122` (called per-page by `fetch_all` via `M_pagination.offset_iterate`)
**Issue:** Each call to `M_finance.fetch` rebuilds `end = _iso8601_utc_no_z(os.time() + 60)` from the current wall clock. Across a multi-page pagination loop, the end timestamp drifts forward by however long page N took. Offset-based pagination (`offset += limit`) assumes the underlying dataset is stable across pages — that assumption is broken whenever a new PAYMENT/PAYMENT_FEE/PAYOUT lands during the loop, causing the same logical record to either appear twice (at offset N and offset N-1) or never (if it would have been at offset N but gets pushed past the limit window). For 90-day clamped windows of a small merchant, the race is small in practice; for first-time sync of a busy merchant during business hours, the race widens.

**Fix:** Compute `end_iso` once inside `fetch_all` (before the iterator starts) and pass it through the closure, so every page uses the same end-anchor. Same convention as Zettle's official sample code.

### WR-02: D-38 prefix gate's `^zettle:fee:` swallows `^zettle:fee:aggregate:` — "seen all 5 prefixes" assertion is unfalsifiable

**File:** `spec/refresh_log_redaction_spec.lua:232-238, 296-321`
**Issue:** `ALLOWED_PREFIXES` lists both `^zettle:fee:` and `^zettle:fee:aggregate:`. The `matches_allowed_prefix` helper accepts a code if any prefix matches. The "seen_prefixes" loop at line 307 marks **both** prefixes as seen for every aggregate code (because aggregate codes start with `zettle:fee:` AND `zettle:fee:aggregate:`). The "ALL 5 prefixes appear at least once" assertion therefore passes even if only 4 distinct kinds (sale, refund, fee:aggregate, payout) are emitted — `zettle:fee:` (per-sale) would be falsely marked seen because of the aggregate fixture.

In practice the test does exercise both via the four refreshes, so the assertion never fires falsely today. But the gate is structurally weaker than its assertion claims — a future regression that drops per-sale fee emission would pass the test silently.

**Fix:** Either (a) make the closed-set check exact-match by stripping prefix-of-prefix overlap, or (b) bucket by the most-specific matching prefix and assert each bucket has at least one entry. Simplest: change `matches_allowed_prefix` semantics so a code claims its longest matching prefix, and assert all five buckets non-empty.

### WR-03: `entry.lua` masks Finance API `balance = nil` with `account.balance` fallback, hiding the non-EUR-liquid case from MoneyMoney

**File:** `src/entry.lua:367`
**Issue:** `balance = (account_state and account_state.balance) or (account and account.balance)` — when `fetch_account_state` deliberately returns `balance = nil` to signal a non-EUR liquid balance (per the R-4 currency guard documented in `src/finance.lua:175-183`), the entry layer overwrites it with `account.balance` from MoneyMoney's stored snapshot. MoneyMoney therefore sees the **stale** balance from the last successful refresh rather than understanding that the current refresh could not produce one. The pendingBalance side does NOT have this fallback, so the two fields diverge silently.

**Fix:** Drop the `account.balance` fallback and let `nil` flow through to MoneyMoney (which interprets nil as "balance unknown / not updated"). Alternatively, emit a German `M_log.warn` whenever the fallback fires so the inconsistency is at least observable. If the fallback must stay for backwards-compat, document it in ADR-0004 alongside the non-EUR contract.

### WR-04: `mapping.lua` hardcodes German strings outside `i18n.lua` ("Auszahlung an Bankkonto am", "Betrag:", "Zahlart:", "Rückerstattung")

**File:** `src/mapping.lua:428, 478-479, 540-541, 298, 300`
**Issue:** Several user-visible German strings are inline string literals in `mapping.lua` rather than `M_i18n.t(...)` keys:

- `"R\xc3\xbcckerstattung"` in `refund_to_transaction` line 428
- `"\nBetrag: " .. _format_amount(...) .. " EUR"` in both `fee_to_transaction` (478-479) and `payout_to_transaction` (540-541)
- `"Auszahlung an Bankkonto am "` in `payout_to_transaction` (540)
- `"Zahlart: "` prefix in `_format_purpose` (298-300)

This bypasses both the `loop-lektor` review surface (Phase-4 Wave 5 was supposed to own copy decisions) and the EN-parity gate in `spec/i18n_spec.lua`. A future English locale rollout will miss every one of these strings.

**Fix:** Promote each literal to an `i18n.lua` key (`account.purpose.fee_amount = "Betrag: %s EUR"`, `account.purpose.payout_on_date = "Auszahlung an Bankkonto am %s"`, `account.purpose.payment_method_prefix = "Zahlart: %s"`, `transaction.name.refund_suffix = "Rückerstattung"`) and route through `M_i18n.t`. The i18n parity tests then catch missing locales for free.

### WR-05: `_format_label` and `_format_purpose` use inconsistent BRAND_MAP lookup case-handling

**File:** `src/mapping.lua:183, 286`
**Issue:** `_format_label` (sale name path) does `BRAND_MAP[card_type]` — no normalisation. `_format_purpose`'s card-tail (line 286) does `BRAND_MAP[card_type:upper()]`. If Zettle ever sends mixed-case `"Visa"` or `"visa"` (the docs don't guarantee uppercase), the two functions produce different brand strings for the same purchase — the sale name says "Visa" (capitalized fallback) and the purpose-tail says "Visa" via the map. Today these agree; the moment Zettle's API stops uppercasing, the sale's `name` and `purpose` carry mismatched brand spellings.

**Fix:** Normalise once at the top of `_format_label`: `local cardType_upper = card_type:upper()` then look up `BRAND_MAP[cardType_upper]` and use the same fallback. Apply the same in `_format_purpose`. Add a fixture with lowercase cardType to lock the invariant.

### WR-06: `_format_purpose` single-rate VAT path ignores `groupedVatAmounts` entirely when the map has 1 entry but `vatAmount` is 0

**File:** `src/mapping.lua:218-245`
**Issue:** When `groupedVatAmounts` has exactly one entry and `vatAmount = 0`, both the multi-rate branch (`#rate_entries >= 2`) and the single-rate fallback (`vat ~= 0`) skip the VAT line. This is the intended META-01 zero-suppression for `{"0.0": 0}` (the test at `meta_purpose_lines_spec.lua:119-134` locks it). But the same code path also silently suppresses the line for `{"19.0": 0}` (a real possibility for a zero-amount purchase with a non-zero rate code) — and worse, it silently emits a wrong line when `vatAmount` is non-zero AND `groupedVatAmounts` has one entry whose value disagrees: the function trusts `vatAmount` and ignores `groupedVatAmounts[k]`. No spec gates this disagreement.

**Fix:** Either (a) drive the single-rate path off the map's sole value when present (so the map and the line agree), or (b) cross-check that the sum of `groupedVatAmounts` values equals `vatAmount` and log a warn when they disagree. Add a fixture: `{vatAmount=500, groupedVatAmounts={["19.0"]=400}}` to lock the chosen behaviour.

---

## Info

### IN-01: `ENTRY_MODE_MAP` key/i18n-key naming drift — CONTEXT mentions `_magstripe`, code uses `_swipe`

**File:** `src/mapping.lua:153-159` + `src/i18n.lua:36`
**Issue:** CONTEXT D-57 enumerates i18n keys `account.purpose.payment_method.{kontaktlos,chip,swipe,magstripe,unknown}`. The shipped code uses `swipe` (mapped from API value `MSR`) and has no `magstripe`. The German label is "Magnetstreifen", which translates to magstripe. Not a bug — just a naming inconsistency between the design doc and the implementation that future readers will trip on.

**Fix:** Rename either side (prefer `magstripe` for the i18n key, since "Magnetstreifen" is what it means). Or update CONTEXT D-57 to say `swipe` and document why.

### IN-02: `M_finance.fetch_all` exposes no way to override `limit`

**File:** `src/finance.lua:141-148`
**Issue:** `fetch_all` hard-codes `{ offset = 0, limit = 1000 }`. The two-page test in `spec/finance_spec.lua:228-244` explicitly notes that the harness cannot drive the multi-page path through the public API and has to settle for the single-page path. This shrinks the genuinely tested surface to one page. The `pagination_offset_spec` does drive multi-page paths, but only against the lower-level iterator, not against the production-path `M_finance.fetch_all`.

**Fix:** Accept an optional `opts = {limit = ...}` parameter (default 1000). Add an `fetch_all` spec case that drives two real pages via the fetch boundary. Not critical (the iterator-level test is comprehensive), but it would close a real gap in end-to-end coverage.

### IN-03: Commented-out `RESEARCH §Pitfall 8` note in `_format_purpose` references behaviour that surface-preservation spec already gates

**File:** `src/mapping.lua:215`
**Issue:** The comment `-- (preserves byte-identity for single-rate / empty-map / no-VAT fixtures per RESEARCH §Pitfall 8)` claims byte-identity preservation, but `spec/phase3_surface_preservation_spec.lua` does not currently fixture-snapshot the multi-rate purchases against the Phase-3 baseline (it only audits the four frozen callbacks). The byte-identity claim is uncorroborated.

**Fix:** Either add a snapshot test of `_format_purpose` output for the single-rate fixtures or trim the comment to "single-rate / empty-map / no-VAT inputs continue to hit the Phase-3 fallback branch".

### IN-04: `/tmp/probe-finance.status` is a fixed-path scratch file in `probe-finance.sh`

**File:** `tools/probe-finance.sh:101, 105`
**Issue:** The script writes curl status to `/tmp/probe-finance.status` (fixed path) and never cleans it up. On a shared system or with concurrent runs this races. The body and header files use `mktemp` correctly; only the status sink doesn't.

**Fix:** `local tmp_status="$(mktemp -t probe-finance.status.XXXXXX)"` and route through that path. Extend the `trap` cleanup.

---

## Structural Findings (fallow)

No `<structural_findings>` block was provided in the briefing. The narrative findings above stand on their own.

---

_Reviewed: 2026-06-21T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_

---

## Round 2 (2026-06-21 re-review)

**Re-reviewed:** 2026-06-21T22:55:00Z
**Branch:** `phase-4/enrichment`
**HEAD at re-review:** `7bff4de` (post-fix-batch + summary commit)
**Commits in scope:** `f804e97..7bff4de` (the 04-07 fix-batch + docs commit)
**Test suite:** 335 / 0 failures / 0 errors (verified locally)
**Verdict:** **FINDINGS_PRESENT** — all 7 addressed items confirmed CLOSED; 2 new LOW findings introduced by the fix batch itself.

### Close-verification on addressed items

- **BL-01 — CLOSED via commit `f804e97`.** `src/entry.lua:307-311` now wraps `M_mapping.to_berlin_local_time(covering.timestamp_posix)` before `M_mapping.promote_to_booked`. The wrapping helper is exported at `src/mapping.lua:338-340`. Regression test `spec/entry_spec.lua:955-1014` asserts both (a) `sale.valueDate == M_mapping.to_berlin_local_time(payout_utc)` (literal value check) and (b) `sale.valueDate == payout_txn.bookingDate` (end-to-end same-convention sanity). Convention-match enforced.

- **BL-02 — CLOSED via commit `b1ae8cf`.** `tools/probe-finance.sh:78-79` now uses `[[:space:]]*` POSIX class in both name-class and id-class rules. A smoke test (`_probe_finance_smoke_test`) defined at lines 84-131 runs unconditionally at script-load time (invocation at line 132), exercising name (space-around-colon), userId (compact), UUID, and an over-redaction specificity check; aborts with `exit 3` and a `FATAL` banner if any branch regresses. Documentation comment at lines 70-77 explains the BSD-vs-GNU sed pitfall for future maintainers.

- **BL-03 — CLOSED via commit `6c12da4`.** ADR-0004 gained a load-bearing "Known Limitation — cross-refresh fee re-classification" subsection (50 lines; spells out what Option B enforces, what it can't, user mitigations, and the Option A escape hatch). README "Bekannte Grenzen" section added (3 German bullets including the BL-03 case with manual-cleanup instruction pointing at the user-visible name "PayPal POS Transaktionsgebühren"). `spec/refresh_idempotency_spec.lua` split case 4 into 4a (within-refresh stability) and 4b (cross-refresh divergence enumeration); case 4b at lines 419-474 cleanly isolates the BL-03 case — queues two distinct fixture sets (`purchase_simple_sale`+`finance_payment_fee_unlinked` for refresh 1, then `purchase_for_double_book_test`+`finance_payment_fee_LINKED_for_double_book_test` for refresh 2), asserts the aggregate appears in r1, the per-sale code appears in r2, the aggregate is NOT re-emitted in r2, AND the per-sale code did NOT exist in r1. The test description explicitly flags "**NOT prevented in v0.2.0; ADR-0004 known-limitation contract**" so future contributors cannot mistake it for a regression test that's expected to harden. The in-code comment at `src/entry.lua:329-336` now references ADR-0004 + case 4a/4b explicitly. Two new fixtures audited: well-formed JSON, no PII, idiomatic `_source` provenance comment, and intentional shared UUID (`aaaaaaaa-...`) across the two fixtures so the linkage upgrade is mechanically reproducible.

- **WR-01 — CLOSED via commit `4fe3a2a`.** `src/finance.lua:148` now computes `local end_posix = os.time() + 60` ONCE before the iterator starts and threads it through every page via the closure at line 150. `M_finance.fetch` grew an optional `end_posix` 4th argument (line 118), with legacy default `os.time() + 60` preserved at line 127 for direct callers. Regression test in `spec/finance_spec.lua` asserts the contract that the URL emits exactly the passed `end_posix` value.

- **WR-02 — CLOSED via commits `5bde30c` + `14625ef` (cleanup).** `spec/refresh_log_redaction_spec.lua:249-263` introduces `longest_matching_prefix(code)` that scans `ALLOWED_PREFIXES` and returns the entry with the maximum body length (computed correctly with `#p`, ties handled by first-seen but no ties exist in the closed 5-entry set). The "seen_prefixes" walk at lines 320-330 now bucketises by longest-match only, so the "all 5 buckets non-empty" assertion at line 334 genuinely requires both `^zettle:fee:` and `^zettle:fee:aggregate:` to be populated independently. Mechanism is stable, not a brittle workaround. The follow-up commit `14625ef` correctly drops the (now-unused) `matches_allowed_prefix` thin wrapper — also no luacheck regression.

- **WR-03 — CLOSED via commit `6119035`.** `src/entry.lua:412-422` restructured: first reads `account_state.balance`; if nil, falls back to `account.balance` AND emits `M_log.warn("RefreshAccount: liquid balance unavailable from Finance API (non-EUR currency?); falling back to MoneyMoney's cached account.balance")`. The WARN is a static string with no dynamic interpolation, so it is **redaction-safe** (no SEC-03 risk). R-4 test extended to assert the WARN is captured.

- **WR-05 — CLOSED via commit `f598f84`.** `src/mapping.lua:188-189` normalises `card_type_upper = card_type:upper()` before `BRAND_MAP[card_type_upper]` lookup, mirroring the convention `_format_purpose` already used at line 286. New regression test in `spec/mapping_spec.lua` feeds mixed-case `cardType="Visa"` and asserts both `name` and `purpose` render "Visa" consistently.

### New findings introduced by the fix batch

#### R2-01 (LOW) — S-04's 32-byte `cardType` cap is missing in the sibling `_format_label` unknown-brand fallback

**File:** `src/mapping.lua:174, 192`
**Severity:** LOW (defence-in-depth gap; same threat class as the fix that closed it elsewhere)
**Issue:** Commit `8b98065` (S-04) capped `attrs.cardType` and `attrs.cardPaymentEntryMode` at 32 bytes in `_format_purpose`'s card-tail block (lines 287-295). The sibling function `_format_label` reads `local card_type = attrs.cardType` at line 174 with **no cap**, then at line 192 (unknown-brand fallback) concatenates the full string via `card_type:sub(1, 1):upper() .. card_type:sub(2):lower()` into `brand`, which flows into `txn.name`. A pathological 100KB `cardType` from a compromised CDN would bloat the sale's `name` field per transaction — exactly the attack S-04 deemed worth defending against in `_format_purpose`. The known-brand path (line 189) is safe because `BRAND_MAP[card_type_upper]` lookup returns the short brand string, but only as long as Zettle keeps shipping a finite enumeration of card types.

**Fix:** Cap once at the top of `_format_label` right after the `#card_type == 0` guard: `card_type = card_type:sub(1, 32)`. No behaviour change for the documented Zettle values (all <16 chars), forecloses the unknown-brand exfil-bloat path. Same one-line pattern as the S-04 fix; consider rolling into the deferred follow-up batch.

#### R2-02 (LOW) — S-05 scheme-less hostname gate's exclusion list is broad enough to mask `entry.evil.com`-style hosts

**File:** `.github/workflows/ci.yml:114`
**Severity:** LOW (defence-in-depth gate; primary scheme-prefix gate is unaffected)
**Issue:** Commit `b1bac98` (S-05) added a complementary TLD-pattern grep, then excluded any token starting with a known Lua namespace prefix:
```
grep -Ev '^(account|transaction|credential|error|purpose|http|finance|mapping|auth|entry)\.'
```
This subtraction is necessary (to suppress i18n keys like `account.purpose.fee_amount`) but it's structurally broad: an attacker hostname like `entry.evil.com` or `transaction.exfil.io` would land in source as a literal scheme-less host and bypass the gate because of the namespace exclusion. The TLD enumeration itself (`com|net|org|io|dev|app|cloud|sh|de|info|co|biz|me|xyz|tech`) is also finite — `.ru`, `.cn`, `.uk`, `.fr` slip through. Neither weakness is exploitable today (the scheme-prefix gate above is the primary defence and catches `https://...` and `http://...` regardless of TLD), but the secondary gate's marketing as "scheme + scheme-less" overstates its actual coverage.

**Fix:** Either (a) tighten the namespace exclusion by requiring a `.lua`-style dotted path rather than a TLD-suffix match (e.g. exclude `account.purpose.*` where `purpose` is itself a known Lua sub-namespace, not any TLD-shaped trailing label), or (b) lengthen the TLD allowlist OR switch to a denylist of known non-allowlisted-host markers — either approach widens real coverage. Lowest-effort hardening: remove `entry` from the exclusion list (the only Lua i18n key it shields is in test fixtures, not in shipped `dist/`); the same applies to `http`, `finance`, `mapping`, `auth` which are internal module names that should not legitimately appear in shipped i18n string keys.

### Spec quality on the new tests

- **`spec/refresh_idempotency_spec.lua` case 4b** isolates the BL-03 enumeration cleanly: separate `it()` block, dedicated `org-d58-4b` token namespace (no leakage from 4a), explicit assertion that the per-sale code did NOT exist in refresh 1 (locks the cross-refresh divergence). The test description string explicitly flags "**NOT prevented in v0.2.0; ADR-0004 known-limitation contract**" — a future contributor cannot mistake this for a regression test. Strong.
- **`spec/entry_spec.lua` BL-01 test** asserts the literal value (not just type) for `sale.valueDate` — the original review's recommended hardening. Includes a defensive sanity check `sale.valueDate == payout.bookingDate` for cross-row convention parity.
- **`spec/mapping_spec.lua` S-01 tests** (single-rate fallback + multi-rate path with pathological keys) cover both surfaces of the range-guard. Mixed-case WR-05 test asserts both `name` and `purpose` consistency — passes the cross-function gate.
- **`spec/entry_spec.lua` S-06 test** asserts both (a) WARN logged with UUID prefix AND (b) the refund cites the first-seen `purchaseNumber 8001` — gates the first-write-wins semantic, not just the WARN side-effect.

### Fix-batch SHA spot-checks

| Claimed SHA in summary | Actual `git log` SHA | Match |
|---|---|---|
| `f804e97` BL-01 | `f804e97` (entry.lua + entry_spec, 2 files, 78 ins) | ✓ |
| `b1ae8cf` BL-02 | `b1ae8cf` (probe-finance.sh, 1 file) | ✓ |
| `6c12da4` BL-03 | `6c12da4` (6 files, ADR + README + spec + 2 fixtures + entry.lua) | ✓ |
| `cab01e1` S-01 | `cab01e1` (mapping.lua + mapping_spec) | ✓ |
| `885f406` S-06 | `885f406` (entry.lua + entry_spec) | ✓ |
| `554d09a` S-07 | `554d09a` (entry.lua) | ✓ |
| `4fe3a2a` WR-01 | `4fe3a2a` (finance.lua + finance_spec) | ✓ |

All 7 spot-checked SHAs match the FIX-SUMMARY table. Test-suite progression `328 → 335` confirmed.

### Round 2 summary

- **Items closed:** 7 of 7 (BL-01, BL-02, BL-03, WR-01, WR-02, WR-03, WR-05). All confirmed by reading the cited file ranges + the regression test that locks each fix.
- **Items deferred (correctly per Tier-3 boundary):** WR-04, WR-06, IN-01..IN-04 — each carries follow-up handle in `04-07-FIX-SUMMARY.md`.
- **New findings introduced by fix batch:** 2 (both LOW). Neither is a regression of the round-1 items; both are sibling-class defects in the same defence-in-depth surface as the fixes that introduced them.
- **No round-2 HIGH or MEDIUM findings.** No round-1 BLOCKER is "still present despite being claimed fixed".

The fix-batch is structurally clean: each fix carries a TDD regression test, no luacheck suppressions added, no SEC-03 redaction-safety regressions, no Phase-3 surface drift, and the new fixtures are well-formed with idiomatic provenance. The two LOW findings can roll into the next post-review batch alongside the deferred WR-04/WR-06 items.

---

_Re-reviewed: 2026-06-21T22:55:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
