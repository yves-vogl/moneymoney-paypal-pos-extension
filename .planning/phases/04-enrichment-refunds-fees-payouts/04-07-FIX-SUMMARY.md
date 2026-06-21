---
phase: 04-enrichment-refunds-fees-payouts
plan: 04-07-FIX
subsystem: entry / mapping / finance / probe-tooling / ci / docs
tags: [security, bug-fix, tdd, review-findings, post-review-batch]
dependency_graph:
  requires: [04-06-SUMMARY.md, REVIEW.md, SECURITY-REVIEW.md]
  provides: [post-review-fix-batch]
  affects:
    - src/entry.lua
    - src/mapping.lua
    - src/finance.lua
    - spec/entry_spec.lua
    - spec/mapping_spec.lua
    - spec/finance_spec.lua
    - spec/refresh_idempotency_spec.lua
    - spec/refresh_log_redaction_spec.lua
    - spec/fixtures/finance/finance_payment_fee_LINKED_for_double_book_test.json
    - spec/fixtures/purchases/purchase_for_double_book_test.json
    - tools/probe-finance.sh
    - .github/workflows/ci.yml
    - docs/adr/0004-finance-api-scope-and-fee-fallback.md
    - README.md
tech_stack:
  added: []
  patterns: [tdd-red-green, range-guard, first-write-wins, longest-prefix-match, observable-fallback, posix-portable-regex]
key_files:
  created:
    - spec/fixtures/finance/finance_payment_fee_LINKED_for_double_book_test.json
    - spec/fixtures/purchases/purchase_for_double_book_test.json
  modified:
    - src/entry.lua
    - src/mapping.lua
    - src/finance.lua
    - spec/entry_spec.lua
    - spec/mapping_spec.lua
    - spec/finance_spec.lua
    - spec/refresh_idempotency_spec.lua
    - spec/refresh_log_redaction_spec.lua
    - tools/probe-finance.sh
    - .github/workflows/ci.yml
    - docs/adr/0004-finance-api-scope-and-fee-fallback.md
    - README.md
decisions:
  - "BL-01: Wrap covering payout UTC POSIX in M_mapping.to_berlin_local_time before promote_to_booked — sale.valueDate now matches sale.bookingDate's Berlin-local convention end-to-end (D-36)"
  - "BL-02: Replace \\s* with [[:space:]]* in probe-finance.sh; add inline smoke test that aborts the script on this platform if the redactor ever regresses"
  - "BL-03: Accept v0.2.0 Option B contract; explicitly document the cross-refresh fee re-classification limitation in ADR-0004 + README; new spec D-58 case 4b enumerates the case (test passes by documenting, not preventing)"
  - "S-01: Range-guard tonumber(k) result to [0..100] inside _format_purpose's groupedVatAmounts loop — out-of-range and non-numeric keys silently skipped"
  - "S-05: Add complementary TLD-pattern grep alongside the scheme-prefixed grep in CI; exclude known Lua namespace prefixes (account.*, transaction.*, etc.) to avoid false positives on i18n keys ending in .net etc."
  - "S-06: First-write-wins on all three cross-refresh indexes with German WARN logs; preserves earliest record (more likely canonical in a Zettle backfill scenario)"
  - "WR-01: Pin Finance API end_posix once before fetch_all's pagination loop starts; thread through each M_finance.fetch call via the closure"
  - "WR-02: Replace 'any-prefix-matches' with longest_matching_prefix so the closed-set test cannot pass when a real prefix bucket is empty"
  - "WR-03: Keep the existing R-4 fallback contract (account.balance when finance balance nil) but emit a WARN so the divergence with the freshly-fetched pendingBalance is observable"
  - "WR-05: Normalise cardType to upper-case before BRAND_MAP lookup in _format_label so sale name and purpose-tail brand strings stay byte-identical"
  - "S-02 / S-04 / S-07: defence-in-depth (currency-cap propagation, cardType cap, stable sort tiebreaker) — same patterns as Phase-3 S-01 / S-03 / S-05"
metrics:
  duration: "~2.5 hours autonomous-window"
  completed: "2026-06-21"
  tasks_completed: 13
  files_modified: 12
  files_created: 2
  new_tests_added: 7
  test_suite_progression: "328 -> 335 / 0 failures / 0 errors"
  reproducible_build_sha_before: "d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712"
  reproducible_build_sha_after:  "6f4f685fd40f2922cb318a786c08b4d7182e0eb167e2c5c90c137fe47308fe54"
---

# Phase 4 Plan 07: Post-Review Fix Batch Summary

One-liner: Thirteen findings fixed across the BLOCKER tier (REVIEW), HIGH tier (SECURITY-REVIEW), and selected MEDIUM tier (REVIEW + SECURITY-REVIEW); 7 new TDD regression tests added; suite 328 → 335 green / 0 failures / 0 errors; build SHA refreshed.

---

## Objective

Address all Tier-1 findings (REVIEW BL-01..BL-03 + SECURITY-REVIEW S-01 HIGH) from the 2026-06-21 dual-review pass plus the Tier-2 1-line-patch items from the briefing (S-02, S-04, S-05, S-06, S-07, WR-01, WR-02, WR-03, WR-05). Defer the rest to a follow-up backlog as planned. TDD discipline: every fix proved RED first, then GREEN. Commits atomic, Conventional Commits with `(04-07)` scope, GPG-signed, no AI attribution.

---

## Findings Addressed

### BL-01 HIGH (REVIEW) — SALE-03 promotion TZ mismatch

**File:** `src/entry.lua` step 13 / `spec/entry_spec.lua`
**Commit:** `f804e97`

The promote step passed `covering.timestamp_posix` (pure UTC from `M_finance.parse_transaction`) as `valueDate` to `M_mapping.promote_to_booked`. Sale's `bookingDate` is Berlin-local POSIX (D-36), and `payout_to_transaction` also writes Berlin-local — so promoted sales carried `valueDate` 1–2 hours earlier than `bookingDate` (CET/CEST dependent), and could fall on a different calendar day from the covering payout's `valueDate` at 23:00 UTC under CEST.

Fix: wrap with `M_mapping.to_berlin_local_time(covering.timestamp_posix)` before the call. New regression test asserts both (a) `sale.valueDate == to_berlin_local_time(payout_utc)` and (b) `sale.valueDate == covering_payout_txn.bookingDate` (end-to-end same-convention check).

---

### BL-02 HIGH (REVIEW) — probe-finance.sh redactor fails on macOS BSD sed

**File:** `tools/probe-finance.sh`
**Commit:** `b1ae8cf`

The PII redactor used `\s*` whitespace shorthand — a PCRE/GNU-sed extension that BSD sed (macOS default) does NOT recognise inside `-E` ERE. The name/userId/organizationId rules silently failed to match `jq`'s `"key": "value"` pretty-print output (space after colon). Pasting probe output into a public ADR would have leaked merchant PII into git history.

Fix: replace each `\s*` with the POSIX `[[:space:]]*` character class (portable across BSD and GNU sed). Added an inline smoke test that runs at every script invocation: feeds a known PII sample through `redact()` and aborts with `FATAL exit 3` if any of name, userId, or bare UUID survives unredacted. Verified locally on macOS 25.5.0 + verified the regression (`\s*` revert) trips the smoke test.

---

### BL-03 HIGH (REVIEW) — D-49 cross-refresh fee re-classification (document as known limitation)

**Files:** `docs/adr/0004-finance-api-scope-and-fee-fallback.md`, `README.md`, `src/entry.lua` step 14 comment, `spec/refresh_idempotency_spec.lua` case 4a/4b, `spec/fixtures/finance/finance_payment_fee_LINKED_for_double_book_test.json` (new), `spec/fixtures/purchases/purchase_for_double_book_test.json` (new)
**Commit:** `6c12da4`

The shipped Option B (per-refresh date clustering) cannot enforce the original D-49 "once aggregated, always aggregated" contract across refreshes if Zettle back-fills fee linkage between refreshes. The aggregate row from refresh N stays in MoneyMoney while refresh N+1 emits per-sale rows — double-booking the date. Yves picked Option B for v0.2.0 to avoid LocalStorage persistence complexity, so the v0.2.0-acceptable contract becomes within-refresh stability + explicitly documented cross-refresh limitation + user-facing manual-cleanup guidance.

Changes:

1. ADR-0004 gains a "Known Limitation: cross-refresh fee re-classification" subsection that spells out what Option B CAN enforce (within-refresh determinism), what it CANNOT enforce (linkage upgrade), user mitigations, and the Option A escape hatch for if/when the limitation becomes a recurring support burden.
2. `spec/refresh_idempotency_spec.lua`: case 4 split into 4a (within-refresh stability, unchanged behaviour) and 4b (BL-03 cross-refresh divergence enumeration). 4b queues two different fixture sets — refresh 1 emits aggregate, refresh 2 emits per-sale for the same fee UUID. Test PASSES by documenting the behaviour, not preventing it.
3. Two new fixtures (`finance_payment_fee_LINKED_for_double_book_test.json` and `purchase_for_double_book_test.json`) provide the matching-uuid + payment payload that lets refresh 2's payments_by_uuid lookup succeed.
4. README "Bekannte Grenzen" section added above "Warum diese Extension" with three German-language bullets: payout-delay, the BL-03 fee re-classification case with manual-cleanup instructions, and multi-merchant note.
5. `src/entry.lua` step-14 in-code comment replaced with explicit ADR-0004 + spec case 4a/4b references so a future reader knows where the contract lives.

---

### S-01 HIGH (SECURITY-REVIEW) — Multi-rate VAT formatter Lua crash on pathological rate key

**File:** `src/mapping.lua` `_format_purpose`
**Commit:** `cab01e1`

`tonumber(k)` accepted scientific-notation keys like `"1e308"`; `math.floor(1e308) == 1e308` evaluates true so the formatter fell into the `string.format("%d", e.rate)` branch — which raised "number has no integer representation" and aborted `RefreshAccount`. Same defensive class as Phase-3 S-02.

Fix: range-guard `rate_num` to `[0, 100]` after `tonumber(k)`. No real-world tax regime carries a VAT rate outside this band, so the cap is silent for legitimate inputs and forecloses the crash path. Two new regression tests cover the single-rate fallback path (one legit key + 3 pathological) and the multi-rate path (two legit + three pathological).

---

### S-02 MEDIUM (SECURITY-REVIEW) — Currency-cap propagation to Finance balance log sites

**File:** `src/finance.lua` `fetch_account_state` (liquid + preliminary log sites)
**Commit:** `d0a234f`

Phase-3 S-01 closed an unbounded log-concat for the mapping layer by capping the `currency` field at 8 chars. Phase-4 introduced two new log sites on the analogous `currencyId` field without inheriting the cap — a 10 000-char response would bloat the log line correspondingly.

Fix: apply the same `:sub(1, 8)` pattern at both sites. No behaviour change for legitimate ISO-4217 codes (3 chars).

---

### S-04 MEDIUM (SECURITY-REVIEW) — `cardType` / `cardPaymentEntryMode` unbounded concatenation

**File:** `src/mapping.lua` `_format_purpose` card-tail block
**Commit:** `8b98065`

`attrs.cardType` and `attrs.cardPaymentEntryMode` were concatenated directly into the purpose string with no length cap. A pathological 100KB cardType would balloon the purpose field per transaction, inflating the return table.

Fix: cap both at 32 bytes (generous for all documented Zettle values — VISA / MASTERCARD / GIROCARD / CONTACTLESS_EMV are all < 16 chars). Defence-in-depth pattern identical to Phase-3 S-01.

---

### S-05 MEDIUM (SECURITY-REVIEW) — CI egress allowlist gate misses scheme-less hosts

**File:** `.github/workflows/ci.yml`
**Commit:** `b1bac98`

The single `https?://` grep silently passed (a) scheme-less hostnames (`Connection():get("evil.example.com")`) and (b) string-concatenated URLs where the host appears without scheme prefix.

Fix: add a complementary TLD-shaped grep over `dist/paypal-pos.lua`. Subtract (a) the three legitimate API hosts and (b) known Lua namespace prefixes (`account.*`, `transaction.*`, `credential.*`, …) that incidentally end in TLD-shaped suffixes like `account.purpose.net`. Verified locally: injecting `evil.example.com` into a copy of `dist/` trips the gate; the production dist passes cleanly.

---

### S-06 MEDIUM (SECURITY-REVIEW) — Cross-refresh index silent overwrites

**Files:** `src/entry.lua` (three index sites) + `spec/entry_spec.lua`
**Commit:** `885f406`

The three indexes built in `RefreshAccount` silently overwrote on duplicate keys: `purchases_by_uuid` (refund→original Beleg), `payments_by_uuid` (fee→sale Beleg), `fin_payments_by_uuid` (PAYMENT→PAYOUT for SALE-03 promotion). Each is a distinct bookkeeping-integrity failure mode.

Fix: identical first-write-wins guard with `M_log.warn` (8-char UUID prefix) at all three sites. New regression test queues a 3-record fixture with two sales sharing `purchaseUUID1` + a refund pointing at the shared UUID; asserts (a) WARN was logged and (b) the refund cites the first-seen `purchaseNumber 8001` not the overwritten `8002`.

---

### S-07 LOW (SECURITY-REVIEW) — Unstable payout sort

**File:** `src/entry.lua` step 10
**Commit:** `554d09a`

`table.sort` is not stable. Two payouts tied at second-granularity could swap order across refreshes, flipping SALE-03's `valueDate` non-deterministically.

Fix: add `originatingTransactionUuid` lexicographic tiebreaker to the comparator. `tostring()` wrappers defensively guard against any non-string slipping through `parse_transaction`.

---

### WR-01 WARNING (REVIEW) — Offset-pagination end-anchor drift

**Files:** `src/finance.lua` `fetch` / `fetch_all` + `spec/finance_spec.lua`
**Commit:** `4fe3a2a`

`M_finance.fetch` recomputed `end=os.time()+60` each call. Across a multi-page pagination the end-anchor drifted, breaking offset-pagination's stable-dataset assumption — records that landed during the loop could duplicate or be skipped.

Fix: `fetch` grows an optional `end_posix` argument (legacy default preserved for direct callers). `fetch_all` computes `os.time()+60` once before the iterator starts and threads it through every page via the closure. Matches Zettle's official sample code's pagination convention. New regression test asserts the fetch contract: when `end_posix` is passed, the URL uses exactly that value.

---

### WR-02 WARNING (REVIEW) — D-38 prefix gate overlap (`^zettle:fee:` swallows `^zettle:fee:aggregate:`)

**File:** `spec/refresh_log_redaction_spec.lua`
**Commits:** `5bde30c`, `14625ef` (luacheck cleanup)

Both prefixes were in `ALLOWED_PREFIXES` and the matcher marked BOTH as "seen" for every aggregate code — so the "all 5 buckets exercised" assertion was structurally unfalsifiable.

Fix: introduce `longest_matching_prefix` — each code claims exactly one bucket (the most-specific matching prefix). The assertion now genuinely requires per-sale fees and aggregate fees to both be exercised. Test refactor only; no behaviour change in shipped code.

---

### WR-03 WARNING (REVIEW) — Non-EUR balance fallback hides the case from MoneyMoney

**Files:** `src/entry.lua` step 16 + `spec/entry_spec.lua`
**Commit:** `6119035`

`balance = (account_state.balance) or (account.balance)` silently substituted the stale MoneyMoney snapshot when the Finance API returned `nil` (R-4 non-EUR liquid case). The pendingBalance side had no fallback so the two fields could quietly diverge.

Minimal fix (the architecturally cleaner "drop the fallback" would break R-4 and change v0.2.0 user-visible behaviour). Keep the fallback, but emit a WARN when it fires so the divergence is observable. The existing R-4 test was extended to assert the WARN is captured.

---

### WR-05 WARNING (REVIEW) — `_format_label` / `_format_purpose` BRAND_MAP case inconsistency

**Files:** `src/mapping.lua` `_format_label` + `spec/mapping_spec.lua`
**Commit:** `f598f84`

`_format_label` used `BRAND_MAP[card_type]` (raw); `_format_purpose`'s card-tail used `BRAND_MAP[card_type:upper()]`. If Zettle ever sent `"Visa"` instead of `"VISA"`, the sale's `name` and `purpose`-tail would carry mismatched brand spellings.

Fix: normalise to upper-case before the lookup in `_format_label` (mirrors `_format_purpose`'s convention). Unknown-brand fallback still uses the capitalize-literal pattern. New regression test feeds mixed-case `cardType="Visa"` and asserts both `name` and `purpose` render "Visa" consistently.

---

## Deferred Items (rationale + follow-up tracking)

The following findings were classified as out-of-scope for this fix batch per the briefing's Tier-3 boundary, OR were structurally larger than a 1-line patch and require dedicated planning work.

### WR-04 — Hardcoded German strings outside i18n.lua

**Why deferred:** This is a refactor across `_format_purpose`, `refund_to_transaction`, `fee_to_transaction`, `payout_to_transaction` plus DE + EN i18n entries plus parity-test updates — explicitly the briefing's "would require a real design change (i18n hygiene refactor)" Tier-3 case. The relevant strings are: `"Rückerstattung"`, `"Auszahlung an Bankkonto am "`, `"Betrag:"`, `"Zahlart:"`. Until EN locale rollout is real (no current user demand), the deferral cost is zero.

**Follow-up:** track as a `i18n-hygiene` planning item for Phase 5 or 6 alongside the missing scope-specific German error string (I-02). loop-lektor reviews `account.purpose.*` keys at that time.

### WR-06 — Single-rate VAT path ignores `groupedVatAmounts` when `vatAmount=0`

**Why deferred:** This is genuine behavioural ambiguity (when the map disagrees with `vatAmount`, which wins?) that needs a design decision before code, not a 1-line patch. Today the path matches the META-01 zero-suppression spec test; changing it would require updating that spec too. Low-priority because real Zettle responses do not exhibit the disagreement.

**Follow-up:** open an ADR question — "single-rate VAT: trust vatAmount or trust groupedVatAmounts?" — for the META-01 owner to decide.

### IN-01 — `ENTRY_MODE_MAP` / i18n-key naming drift (`_swipe` vs `_magstripe`)

**Why deferred:** Cosmetic naming inconsistency; no user impact. Renaming would touch i18n.lua DE + EN entries plus the test fixtures. Right call is to roll the rename into the WR-04 i18n-hygiene pass.

### IN-02 — `M_finance.fetch_all` exposes no `limit` override

**Why deferred:** The iterator-level test already exercises multi-page paths; this is a coverage gap of the boundary, not a defect. A clean fix is a small `opts` parameter — track as a follow-up developer-ergonomics improvement.

### IN-03 — `_format_purpose` Pitfall-8 comment uncorroborated

**Why deferred:** Comment-only nit; the WR-05 fix touches the same function. Roll the comment trim into a future cleanup commit when `_format_purpose` is next touched.

### IN-04 — `/tmp/probe-finance.status` fixed-path scratch file

**Why deferred:** `probe-finance.sh` is a developer tool. The race exists only on a shared box with concurrent runs — not Yves' setup. Low priority; bundle with any future probe-finance.sh maintenance.

### S-03 — `_url_encode_query` skips percent-encoding (defensive-only)

**Why deferred:** Safe by accident today (both callers pass formatted numerics). Hardening would require a defensive type-assert at the encoder entry — a real fix but with zero current user-facing risk.

**Follow-up:** add an `assert(type(v)=="number")` at the encoder entry as part of any future `M_finance.fetch` signature change.

### S-08 — `originatingTransactionUuid` not pattern-validated

**Why deferred:** Low impact (UUIDs flow into `transactionCode` strings; downstream MoneyMoney consumers byte-compare). Stronger validation would mean a 36-char regex check at the parse_transaction boundary plus equivalent guards in each mapper — a real change that wants test coverage planning.

**Follow-up:** queue alongside S-03 as a "Finance API input-validation hardening" mini-plan.

### S-09 — Fee aggregate sums have no per-record or per-sum cap

**Why deferred:** Real-world Zettle fee amounts are bounded by definition (< €100 per record typically). The risk surface is a compromised-CDN scenario; the fix is straightforward (`MAX_FEE_MINOR_UNITS` constant + per-aggregate cap) but requires choosing the threshold values, which Yves should sign off on (rather than the autonomous window).

**Follow-up:** add a one-line Yves-checkpoint item — "approve `MAX_FEE_MINOR_UNITS = 100_000 * 100` and `MAX_AGG_MINOR_UNITS = 1_000_000 * 100`?" — then ship the cap.

### S-10 — `_berlin_date_to_posix` regex rejects 5-digit-year dates

**Why deferred:** Year-10000+ adversarial path is essentially never going to fire on real Zettle data. The fix is structurally simple but the test fixture (a fee with timestamp `9999-12-31T23:00:00Z`) is contrived; the right pairing is with S-09 in a single defence-in-depth mini-plan.

### I-01 — META-03 walker omits `spec/fixtures/`

**Why deferred:** Process gap, not a runtime gap. The fix is a 3-line walker extension — bundle with whatever PR next touches `meta_no_tax_classification_spec.lua` or the META-03 invariant.

### I-02 — Generic LoginFailed on missing READ:FINANCE scope

**Why deferred:** ADR-0004 already accepts the deferral to Phase 5. The README upgrade-path section covers the diagnosis flow. Lower priority than a real scope-specific German error string overhaul which Phase 5 will own anyway.

---

## Metrics

- **Findings addressed:** 13 (3 BLOCKER + 1 HIGH-sec + 5 MEDIUM-sec + 4 WARNING-review)
- **Findings deferred:** 12 (WR-04, WR-06, IN-01..IN-04, S-03, S-08, S-09, S-10, I-01, I-02) — each with rationale + follow-up handle above
- **Commits authored:** 13 GPG-signed, Conventional Commits with `(04-07)` scope, no AI/Claude attribution
- **Files modified:** 12
- **Files created:** 2 (two new test fixtures)
- **New TDD regression tests:** 7
  - BL-01 (sale promotion TZ assertion in entry_spec)
  - BL-03 (case 4b cross-refresh divergence enumeration)
  - S-01 (single-rate + multi-rate pathological key tests in mapping_spec)
  - S-06 (duplicate purchaseUUID1 WARN + first-write-wins in entry_spec)
  - WR-01 (end_posix contract assertion in finance_spec)
  - WR-05 (mixed-case cardType consistency test in mapping_spec)
- **Test suite progression:** 328 → 335 / 0 failures / 0 errors
- **luacheck:** 0 warnings / 0 errors in 38 files
- **Reproducible build SHA before:** `d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712`
- **Reproducible build SHA after:**  `6f4f685fd40f2922cb318a786c08b4d7182e0eb167e2c5c90c137fe47308fe54`
- **Branch:** `phase-4/enrichment` — local only; pre-existing autonomous-window convention (push deferred until Yves' review)

---

## Commit Index

| # | SHA | Subject |
|---|-----|---------|
| 1 | `f804e97` | fix(04-07): BL-01 SALE-03 promotion converts payout UTC to Berlin-local POSIX |
| 2 | `b1ae8cf` | fix(04-07): BL-02 probe-finance.sh redactor works on macOS BSD sed |
| 3 | `6c12da4` | fix(04-07): BL-03 document D-49 cross-refresh fee re-classification as known limitation |
| 4 | `cab01e1` | fix(04-07): S-01 range-guard groupedVatAmounts rate key to [0..100] |
| 5 | `b1bac98` | fix(04-07): S-05 CI egress allowlist also catches scheme-less hostnames |
| 6 | `885f406` | fix(04-07): S-06 first-write-wins guards on three cross-refresh indexes |
| 7 | `5bde30c` | fix(04-07): WR-02 D-38 prefix gate uses longest-match (closes overlap) |
| 8 | `f598f84` | fix(04-07): WR-05 _format_label uppercases cardType before BRAND_MAP lookup |
| 9 | `6119035` | fix(04-07): WR-03 emit WARN when liquid-balance fallback to account.balance fires |
| 10 | `4fe3a2a` | fix(04-07): WR-01 pin Finance API end-anchor once per fetch_all pagination loop |
| 11 | `d0a234f` | fix(04-07): S-02 cap currencyId at 8 chars on Finance balance log sites |
| 12 | `554d09a` | fix(04-07): S-07 stable payout sort via originatingTransactionUuid tiebreaker |
| 13 | `8b98065` | fix(04-07): S-04 cap cardType and cardPaymentEntryMode at 32 bytes |
| 14 | `14625ef` | chore(04-07): drop unused matches_allowed_prefix helper from refresh_log_redaction_spec |

---

## Hand-off

Phase 4 is **READY-FOR-RE-VERIFICATION**. The next step is a re-run of `loop-security-engineer` (closing S-01 / S-05 / S-06 + the bundled MEDIUM/LOW items) and `gsd-code-reviewer` (closing BL-01 / BL-02 / BL-03 + the bundled WR items) to confirm the fix-batch lands cleanly. After re-verification:

1. Yves checkpoint for the BL-03 ADR-0004 + README wording and the deferred-items list above (especially S-09 threshold approval).
2. loop-lektor pass on the German strings in ADR-0004 + README "Bekannte Grenzen" + any new WARN log lines (Plan 04-06 Task 4 was already deferred — bundle into one lektor session).
3. Plan 04-01 (Q3 sandbox probe) still pending Yves' live verification.
4. PR squash-merge to `main` (per `feedback_gpg_signed_pr_merge` — `--squash` mandatory).

---

_Plan 04-07 closes the dual-review gap from REVIEW.md + SECURITY-REVIEW.md without regressing any green test._
