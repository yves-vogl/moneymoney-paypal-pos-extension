# Phase 4: Enrichment — Refunds, Fees, Payouts, Balance, VAT, Tips - Context

**Gathered:** 2026-06-21 (autonomous draft within the 48 h window granted 2026-06-20 03:30 UTC → 2026-06-22 03:30 UTC; each gray area below carries a *recommended* answer ready for Yves' review)
**Status:** Draft — awaiting Yves on (1) the Q3 live probe of `finance.izettle.com` and (2) Pay/Compliance-touchpoint sign-off (D-49 fee-fallback contract, D-55 META-03 wording invariant). All other decisions are locked recommendations ready for planning.

<domain>
## Phase Boundary

Layer the **Finance API** onto Phase 3's Purchase API pipeline so a merchant sees the full bookkeeping picture in MoneyMoney: settled vs in-flight balance, refunds tied back to their original sale by receipt number, per-sale card-acceptance fees (with a documented daily-aggregate fallback when per-sale linkage is unavailable), payouts to the bank account as separate negatives, per-rate German VAT lines, and tip lines when present. `RefreshAccount` continues to be the only entry point: it now drives **two** paginated pipelines (Purchase + Finance) in sequence, cross-references their records inside one refresh cycle to attach fees and resolve refund originals, and re-emits Phase-3 sales with `booked = true` + `valueDate = payout_date` when the Finance API confirms settlement (closing the dynamic half of D-31). The Finance API host (`finance.izettle.com`) and its `/v2/accounts/liquid/transactions` endpoint must be live-verified once with a real sandbox key (Q3 from ADR-0003) before the Wave 1 plans can lock — this is the single Yves-blocker for Phase 4 to leave PLANNING.

**In scope:**
- `M_finance.fetch(account, since, bearer)` — single fetch round-trip per page against `https://finance.izettle.com/v2/accounts/liquid/transactions` with `includeTransactionType=PAYMENT&includeTransactionType=PAYMENT_FEE&includeTransactionType=PAYOUT` (the three types Phase 4 cares about; Zettle's `REFUND` is **not** included — refunds come from the Purchase API as negative purchases per Phase-3 D-32)
- `M_finance.fetch_all(since, bearer)` — offset-based pagination loop (Finance API uses `offset += limit` until a short page; distinct from Purchase API's `lastPurchaseHash` cursor)
- `M_finance.parse_transaction(raw)` — pure-logic mapping of one Finance record into a typed Lua record `{ kind = "PAYMENT" | "PAYMENT_FEE" | "PAYOUT", amount, timestamp, originatingTransactionUuid }`
- `M_mapping.fee_to_transaction(fee_record, originating_sale)` — pure-logic mapping for FEE-01 (per-sale linkage). `transactionCode = "zettle:fee:" .. fee_uuid`. Amount is negative. `purpose` cites the originating sale's `purchaseNumber` (FEE-02).
- `M_mapping.fee_aggregate_to_transaction(fees, date)` — pure-logic mapping for FEE-03 fallback. `transactionCode = "zettle:fee:aggregate:" .. date_iso`. `name = "PayPal POS Transaktionsgebühren"`. `purpose` contains the German daily-aggregate explanation + count.
- `M_mapping.payout_to_transaction(payout_record)` — pure-logic mapping for PAYOUT-01/02/03. `transactionCode = "zettle:payout:" .. payout_uuid`. `amount = -payout.amount`. `name = "Auszahlung an Bankkonto"` (PAYOUT-02). `bookingDate = payout.timestamp converted to Berlin local` per Phase-3 D-36 DST table (PAYOUT-03).
- **Phase-3 sale re-emission with promoted `booked`/`valueDate`** — when a Finance API `PAYMENT` record matches a Purchase API purchase via `originatingTransactionUuid` ↔ `purchaseUUID1`, the entry-layer cross-reference promotes that sale's transaction to `booked = true` + `valueDate = matching_payout.timestamp_local`. The `transactionCode` is byte-identical to Phase 3's; MoneyMoney's dedup updates the existing row in place (closes SALE-03 dynamic half per D-31).
- **Refund original-sale resolution** — `M_mapping.refund_to_transaction` is upgraded so its `purpose` field embeds the originating sale's `purchaseNumber` (REF-02), looked up via a `purchases_by_uuid` index built in `entry.lua` during the current refresh (D-59). If the original is not on the same page set (rare but possible across batches), `purpose` falls back to citing `refundsPurchaseUUID1` directly — already the Phase-3 D-32 behaviour.
- **Per-rate VAT line in `purpose`** — `M_mapping._format_purpose` is extended: when `groupedVatAmounts` has more than one key, emit one German line per rate (`"19% MwSt: 3,83 EUR"`, `"7% MwSt: 1,40 EUR"`), sorted descending by rate. When `groupedVatAmounts` is empty/absent, fall through to Phase-3's existing single `MwSt` line from `vatAmount`. (META-01)
- **Tip line** — already implemented in Phase 3 per D-34 (`account.purpose.tip = "Trinkgeld: {1} EUR"`); Phase 4 only re-confirms META-02 (line absent when `gratuityAmount == 0`).
- **Card-brand + entry-mode tail** — `M_mapping._format_purpose` adds a tail line `"Zahlart: <cardType> (<cardPaymentEntryMode>)"` when both fields present (SALE-07). German display labels are mapped via new i18n keys (`account.purpose.payment_method_kontaktlos`, `_chip`, `_swipe`, `_magstripe`, `_unknown`).
- **Balance + pendingBalance** — `entry.lua RefreshAccount` calls a new `M_finance.fetch_account_state(bearer)` against `/v2/accounts/liquid` (or whichever sub-endpoint Q3 confirms; placeholder until probe) returning `{ balance, pendingBalance }`. Both values are returned to MoneyMoney via the `RefreshAccount` return table. (ACCT-03)
- **META-03 invariant** — a build-time grep + a runtime spec assert that no string in any `src/*.lua` contains `"USt-frei"`, `"GoBD-konform"`, `"steuerfrei"`, `"steuerlich"`, `"tax-free"`, `"VAT-exempt"`, or any cognate; the extension surfaces facts and never classifies. (META-03)
- **TEST-02 fixture matrix** — `spec/fixtures/finance/` adds: `finance_single_page.json`, `finance_multi_page_1.json` + `_2.json` (offset boundary), `finance_payment_with_fee_linkage.json`, `finance_payment_fee_unlinked.json` (drives D-49 fallback), `finance_payout.json`, `finance_empty.json`. Plus Purchase API additions: `purchase_vat_split_19_7.json`, `purchase_with_card_metadata_kontaktlos.json`, `purchase_umlauts_purpose.json`. (TEST-02 — all enumerated permutations)
- **SEC-02 egress allowlist** — `finance.izettle.com` added to the CI-grep allowlist alongside the existing `oauth.zettle.com` + `purchase.izettle.com` (predicated on Q3 PASS — see D-57 + Yves-blocker section below).
- **CHANGELOG / README v0.2.0 entry** — concise German changelog noting "Vollständige Buchhaltungssicht: Auszahlungen, Gebühren, MwSt-Aufschlüsselung, beglichene vs. offene Salden" (release-polish wording goes through `loop-lektor` in Wave 5).

**Out of scope:**
- Retry / backoff / 429 throttling for the Finance API — **Phase 5** (`errors.lua` expansion alongside Purchase API retry). Phase 4 surfaces 429/5xx verbatim via Phase-2's `M_errors.from_http_status`, fails-whole-refresh, and lets MoneyMoney retry on the user's next "Aktualisieren" click.
- Per-payout itemisation (which sales belong to which payout, beyond the single `originatingTransactionUuid` link) — Phase 5/6 enrichment. v0.2.0 ships per-sale fee linkage and per-payout total; the "drill into a payout to see its constituent sales" UX is a deferred MoneyMoney UI enhancement.
- Currency conversion (non-EUR sales were skipped in Phase 3 per D-37; non-EUR payouts likewise skipped in Phase 4 — out of scope for v1.0.0).
- Cancellations (Zettle's `cancelled = true` flag if it ever materialises) — not in the documented schema; not in scope until a real user files an issue.
- Discounts breakdown rendering — already trusted via top-level `amount` in Phase 3; Phase 5/6 enrichment if discount visibility becomes a feature ask.
- Receipt-copy URL + GPS coordinates — Phase 5/6.
- ZUGFeRD / DATEV export — far-future, not on the roadmap.
- A "force full historical sync" toggle — Phase 5/6 UX work. Phase 4 inherits Phase-3's D-33 90-day clamp.
- A separate UI-facing payouts subaccount — out of scope; payouts appear as negatives in the single Giro account.

</domain>

<decisions>
## Implementation Decisions

Numbering continues from Phase 3 (which closed at D-45) — D-46..D-60.

### Finance API host + endpoints (Area A — Q3 + ACCT-03 + FEE-01..03 + PAYOUT-01..03)
- **D-46 (PROBE-REQUIRED; recommendation: `finance.izettle.com`)** — Finance API base host. Zettle's official developer portal documents the `finance.izettle.com` host shape and the `/v2/accounts/liquid/transactions` endpoint surface, but the live verification (ADR-0003 Q3) is still DEFERRED to Phase 4's first live call. The recommendation is to lock `finance.izettle.com` and execute the probe as Wave 0 Plan 04-01 — a single GET against `/v2/accounts/liquid/transactions?start=...&end=...&limit=1` with the user's sandbox token and an assertion that the response is 200 with the documented JSON shape. If the probe fails (different host, different path, different shape), the planner replans Wave 1+ with the observed truth. **Yves' action required** to execute this probe — see "Yves Blockers" section at the end of this CONTEXT.
- **D-47** — Finance API authentication reuses Phase-2's Bearer token from `M_auth.cached_token(orgUuid)` byte-identically. The Zettle assertion-grant token scope covers both `purchase.izettle.com` and `finance.izettle.com`. No new client_id or grant flow. The same 2-hour expiry, the same re-mint on cache miss. (Predicated on Q3 probe also returning 200 with the existing token — recorded as a check in the Wave 0 probe plan.)
- **D-48** — Pagination strategy: **offset-based** (`offset=0,limit=1000`; increment `offset` by `limit` until a short page or empty result). Distinct from Phase 3's `lastPurchaseHash` cursor. `M_pagination.iterate` is **NOT** reused — Phase 4 ships a parallel `M_pagination.offset_iterate(fetch_page_fn, initial_params)` so the two strategies stay independently testable. MAX_PAGES guard of 50 same as Phase 3's D-43. The two iterators share the same caller-params-copy invariant.
- **D-49 (PAY/COMPLIANCE; recommendation needs Yves' sign-off)** — Fee linkage contract for FEE-01 / FEE-03:
  - **Primary path:** every Finance `PAYMENT_FEE` record with a non-empty `originatingTransactionUuid` that resolves to a Purchase API `purchaseUUID1` becomes one `M_mapping.fee_to_transaction(fee, originating_sale)` row. `purpose` cites the originating sale's `purchaseNumber`. `transactionCode = "zettle:fee:" .. fee.uuid`.
  - **Fallback path:** every `PAYMENT_FEE` whose `originatingTransactionUuid` is empty, nil, or resolves to a purchase **not on the current refresh's page set** is aggregated by ISO date (`fee.timestamp` → Berlin local → `YYYY-MM-DD`). One `M_mapping.fee_aggregate_to_transaction(fees_for_date, date_iso)` row emits per date. `transactionCode = "zettle:fee:aggregate:" .. date_iso`. `purpose = "Tagesaggregat — {N} Einzelgebühren — Detail-Verknüpfung nicht verfügbar"` (German wording subject to loop-lektor review in Wave 5). A WARNING-level log line is emitted per aggregate row.
  - **Why Yves' sign-off is needed:** the fallback decision lives at the boundary between "data we have" and "data the bookkeeper will see". A merchant whose Steuerberater audits the books will see daily-aggregate rows mixed with per-sale rows when Zettle's linkage data is partial. The fallback wording, the warning-log behaviour, and the dedup contract (`zettle:fee:aggregate:YYYY-MM-DD` is stable across refreshes — but if Zettle later upgrades a fee's linkage from "missing" to "present", we'd emit BOTH the aggregate AND the per-sale row, double-booking the fee). The recommended mitigation: **once an aggregate row exists for a date, all subsequent fees for that date go into the aggregate**, even when linkage becomes available. This requires Yves to confirm the bookkeeping tradeoff (slightly lossy linkage in exchange for hard idempotency).
- **D-50** — Refund original-sale lookup: in `entry.lua RefreshAccount`, build a `purchases_by_uuid` index (`{ [purchaseUUID1] = purchase_record }`) over the full Purchase API result set BEFORE mapping refunds. Pass this index into `M_mapping.refund_to_transaction` so `purpose` can cite the original sale's `purchaseNumber`. When the original is not in the index (already-archived sale beyond the 90-day window), fall back to the Phase-3 D-32 behaviour (`purpose` cites `refundsPurchaseUUID1` directly). REF-02 satisfied for in-window pairs, gracefully degraded out-of-window.
- **D-51** — Payout row direction: each payout emits a **single negative** transaction (`amount = -payout.amount`) in the PayPal POS account. From the merchant's perspective: money leaves the PayPal POS holding balance, arrives in the bank account. The bank account itself is **not** touched by this extension — it has its own MoneyMoney connection and its own deposit transaction; the merchant reconciles by matching `name = "Auszahlung an Bankkonto"` rows in PayPal POS with deposit rows in the bank account on the same `bookingDate`. No double-entry bookkeeping inside this extension. (PAYOUT-01/02)
- **D-52** — Balance + pendingBalance contract: Finance API `/v2/accounts/liquid` (or whichever endpoint Q3 confirms) returns the account state. `balance` = settled (paid-out) liquid balance. `pendingBalance` = sales captured but not yet settled. Both are returned to MoneyMoney via `RefreshAccount`'s return table (`{ balance = X, pendingBalance = Y, transactions = ... }`). Verified against `my.zettle.com`'s merchant dashboard to the cent during T13 walking-skeleton phase (Phase 6). (ACCT-03)

### VAT, tips, and metadata (Area B — META-01..03 + SALE-07)
- **D-53** — VAT split format: extend `M_mapping._format_purpose` to read `groupedVatAmounts` (a `{ [rate_as_decimal_string] = amount_in_minor_units }` map per Zettle docs). When the map has **two or more** rates, emit one line per rate, **sorted descending by rate**, in the format `"{rate}% MwSt: {amount_de} EUR"` — e.g. `"19% MwSt: 3,83 EUR"` then `"7% MwSt: 1,40 EUR"`. When the map has zero or one rate, fall through to Phase-3's existing single `MwSt` line from `vatAmount`. The amount is formatted via the existing `_format_amount` helper (German decimal-comma). (META-01)
- **D-54** — Tip line: keep Phase 3's existing `account.purpose.tip = "Trinkgeld: {1} EUR"` format and zero-suppression logic byte-identically. Phase 4 only adds a confirming META-02 spec to gate the zero-suppression invariant separately (currently asserted inside `mapping_spec.lua`; Phase 4 promotes it to its own `meta_purpose_lines_spec.lua`). META-02 satisfied without code change.
- **D-55 (PAY/COMPLIANCE; recommendation needs Yves' sign-off)** — META-03 invariant: a forbidden-strings list lives in `spec/meta_no_tax_classification_spec.lua` and asserts that no UTF-8 string anywhere in `src/*.lua` matches any of: `"USt-frei"`, `"USt frei"`, `"steuerfrei"`, `"steuerlich"`, `"GoBD-konform"`, `"GoBD konform"`, `"DATEV-fähig"`, `"DATEV fähig"`, `"VAT-exempt"`, `"VAT exempt"`, `"tax-free"`, `"tax exempt"`, `"non-taxable"`. The list is enforced both at spec-time and via a CI grep against `dist/paypal-pos.lua`. **Why Yves' sign-off:** the list defines what Phase 4 promises to NEVER say. Adding wording the extension *is* allowed to use ("Brutto", "Netto", "MwSt", "Trinkgeld", "Beleg #", "Gebühr") is implicit (anything not on the forbidden list); Yves confirms the forbidden list is complete relative to German tax-classification phrasing he wants to avoid. Once locked, this is a permanent invariant.
- **D-56** — SALE-03 closure (Phase-3 promise): when a Finance API `PAYMENT` record matches a Phase-3 purchase via `originatingTransactionUuid` ↔ `purchaseUUID1` AND the same refresh sees a `PAYOUT` record whose timestamp follows the `PAYMENT`'s settlement, re-emit that sale's transaction with the same `transactionCode = "zettle:sale:<uuid>"` but `booked = true` and `valueDate = payout.timestamp_local`. MoneyMoney's dedup updates the row in place. Sales seen by Phase 4 BEFORE their payout lands continue to ship `booked = false`; Phase 4 idempotency tests gate both the "first refresh — still pending" and "second refresh — promoted" paths.

### Card metadata tail (Area C — SALE-07)
- **D-57** — Card-brand + entry-mode tail in `purpose`: when `payments[1].attributes.cardType` AND `payments[1].attributes.cardPaymentEntryMode` are both present, emit a tail line `"Zahlart: {german_card_type} ({german_entry_mode})"` — e.g. `"Zahlart: Visa (kontaktlos)"`, `"Zahlart: Mastercard (Chip)"`. German entry-mode labels via new i18n keys: `account.purpose.payment_method.kontaktlos`, `.chip`, `.swipe`, `.magstripe`, `.unknown`. `cardType` is rendered verbatim (Visa, Mastercard, Amex are universal). When either field absent, the tail line is omitted (no `"Zahlart: unbekannt"` noise). SALE-07 satisfied.

### Cross-refresh state + idempotency (Area D — extends TEST-03 + builds on D-31, D-32, D-38, D-39)
- **D-58** — Idempotency gating spec extension: `spec/refresh_idempotency_spec.lua` (Phase 3) extends to cover the new transaction kinds:
  - simple_sale + payout_arrives_next_refresh → first refresh emits `booked=false`, second refresh promotes the same `transactionCode` to `booked=true` + `valueDate`, no new transactionCodes (D-56 path).
  - payout-only refresh → single negative transaction with `transactionCode = "zettle:payout:<uuid>"` on first refresh, zero new transactions on second refresh.
  - per-sale fee linked → fee transaction with `transactionCode = "zettle:fee:<uuid>"` on first refresh, zero new on second.
  - aggregate fee fallback (D-49) → single `transactionCode = "zettle:fee:aggregate:<date>"` on first refresh, zero new on second, **AND** even when fee linkage later becomes available the aggregate transactionCode persists (no double-booking).
- **D-59** — Cross-refresh state (Phase-3 promote-to-booked): the entry layer does NOT persist any state between refreshes beyond what already lives in MoneyMoney (which dedups by `transactionCode`). On every refresh, Phase 4 re-fetches both Purchase and Finance APIs over the `since` window, builds the in-refresh `purchases_by_uuid` and `payments_by_uuid` indexes, and re-emits sales with whatever `booked`/`valueDate` state the current Finance API view supports. Idempotency falls out of MoneyMoney's dedup; no extension-owned state file.
- **D-60** — Plan structure: Wave 0 (Q3 probe — Yves), Wave 1 (Finance API mapping pure-logic + offset-pagination), Wave 2 (Finance API fetch + cross-refresh index in entry.lua + SALE-03 promotion), Wave 3 (per-rate VAT + card-tail extension to `_format_purpose`), Wave 4 (META-03 invariant spec + meta_purpose_lines_spec + extended idempotency spec), Wave 5 (CHANGELOG + i18n loop-lektor review + Phase-3 surface preservation audit). Six waves total; Phase 3's 6-wave structure (Plans 03-01..03-07) is the reference shape.

### Claude's Discretion
- Whether to ship the SALE-07 card-brand tail line as a **separate** line in `purpose` (above the `Beleg #` footer) or **inline** at the end of the `Brutto` line. Recommendation: separate line, so a merchant scanning `purpose` can grep visually. Plan 04-04 can flip this if a UX argument emerges.
- The exact wording of D-49's German fallback log line and the aggregate-row `purpose` text — `loop-lektor` final pass in Wave 5 owns the choice; current draft is engineering placeholder.
- Whether to gate Wave 4's META-03 invariant via spec-only or also via a `tools/build.lua` halt — recommendation: spec-only for Phase 4 (build halt is a Phase-6 release-polish item alongside the existing `DEBUG = false` gate from Phase 1).
- Whether the cross-refresh index in `entry.lua` lives as a closure or a small `M_index` module — recommendation: closure inside RefreshAccount, since it never crosses a refresh boundary. Promote to a module if Phase 5+ adds another consumer.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap + Requirements
- `.planning/ROADMAP.md` §"Phase 4: Enrichment — Refunds, Fees, Payouts, Balance, VAT, Tips" — phase goal, success criteria (6 bullets), 15 mapped requirements
- `.planning/REQUIREMENTS.md` — ACCT-03, SALE-07, REF-01/02/03, FEE-01/02/03, PAYOUT-01/02/03, META-01/02/03, TEST-02 verbatim
- `.planning/PROJECT.md` §"Non-goals / out of scope" — read-only contract; no write operations against PayPal POS
- `.planning/STATE.md` §"Accumulated Context → Decisions" — D1..D31 still apply

### iZettle / Zettle / PayPal POS API references
- `iZettle/api-documentation/finance-api/user-guides/fetch-account-transactions-v2.md` (GitHub) — verbatim Finance API request/response shape: path `/v2/accounts/liquid/transactions`, query params (`start`, `end`, `limit` 1..1000, `offset`, `includeTransactionType`), pagination semantics (offset-based), transaction shape `{ timestamp, amount, originatorTransactionType ∈ {PAYMENT, PAYMENT_FEE, PAYOUT, …}, originatingTransactionUuid }`
- `developer.zettle.com/docs/api/finance/overview` — Finance API context, scope mapping
- `iZettle/api-documentation/purchase.adoc` — `groupedVatAmounts` shape (already consumed in Phase 3 for `vatAmount`; Phase 4 reads the per-rate map)
- `iZettle/api-documentation/authorization.md` — Bearer-token shape (reused from Phase 2)

### MoneyMoney WebBanking API
- `moneymoney.app/api/webbanking/` — `RefreshAccount(account, since)` return-table contract: `{ balance, pendingBalance, transactions }`. `pendingBalance` is the new field Phase 4 introduces vs Phase 3. `balance` updates per refresh (not pass-through from Phase 3's `account.balance` placeholder).
- `moneymoney.app/api/webbanking/` §"Transaction table" — `valueDate` field semantics (POSIX timestamp; meaning "value date" in banking sense = when the credit/debit clears); `booked = true` + `valueDate` set is the "fully booked" state Phase 3 deferred to Phase 4 per D-31.

### ADRs
- `docs/adr/0003-sandbox-probe-results.md` Q3 — `finance.izettle.com` host live verification (DEFERRED to Phase 4 first live Finance call; Phase 4 Wave 0 closes this)
- `docs/adr/0003-sandbox-probe-results.md` Q4 — JSON integer round-trip PASS (applies to Finance `amount` minor-units same as Purchase API)
- `.planning/research/SUMMARY.md` §2 — D1..D31 canonical decisions, still authoritative for Phase 4 (D29 production URLs, D31 reproducible build, D6 coverage ≥85%, D27 redactor)

### Phase 3 carryover (still in force)
- D-31 (booked-false in Phase 3, promotion in Phase 4 — Phase 4 closes this per D-56 above)
- D-32 (refund mapping + own UUID transactionCode — Phase 4 extends purpose with original-sale lookup per D-50)
- D-33 (90-day since clamp at entry boundary — Phase 4 inherits unchanged)
- D-36 (Berlin-local DST table — Phase 4 reuses for payout `bookingDate` per PAYOUT-03)
- D-37 (non-EUR skipped with INFO log — Phase 4 applies the same guard to Finance records)
- D-38 (transactionCode prefix gate — Phase 4 extends the allowed-prefix set to `zettle:sale:`, `zettle:refund:`, `zettle:fee:`, `zettle:fee:aggregate:`, `zettle:payout:`; SEC-03 gating spec updated accordingly)
- D-41 (cached_token nil guard — Phase 4 inherits)
- D-42 (no direct `Connection()`; everything via `M_http.get_json` — Phase 4 inherits)
- D-43 (errors via `M_errors.from_http_status` in pagination — Phase 4 inherits for both iterators)
- D-45 (SEC-03 Bearer redaction — Phase 4 inherits; extends gating spec to cover Finance API responses)

### Test infrastructure (already in repo)
- `spec/helpers/mm_mocks.lua` — `Mocks.push_response()` queue, `Mocks._last_request` introspection; Phase 4 uses the same harness for Finance API responses
- `spec/helpers/fixtures.lua` — `Fixtures.load("finance/<name>")` loader (extends the existing `purchases/<name>` pattern from Phase 3)
- `spec/refresh_idempotency_spec.lua` (Phase 3) — Phase 4 extends with new gating cases per D-58
- `spec/mapping_schema_spec.lua` (Phase 3) — Phase 4 extends `REQUIRED_FIELDS` walk to cover fee + payout transactions (no new required fields, same 7-field contract)
- `spec/refresh_log_redaction_spec.lua` (Phase 3) — Phase 4 extends `transactionCode` prefix gate per D-38 update

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`M_http.get_json(url, headers)` (`src/http.lua`)** — Phase 2 transport. Finance API uses the same. No new HTTP surface.
- **`M_auth.cached_token(orgUuid)` (`src/auth.lua`)** — Phase 2 token-cache read; Phase 4 reuses without modification (D-47).
- **`M_pagination.iterate` (`src/pagination.lua`)** — Phase 3's cursor iterator. Phase 4 adds a **sibling** `M_pagination.offset_iterate` (NOT a modification) for offset-based Finance API pagination per D-48.
- **`M_mapping._parse_iso8601_utc` + `_to_berlin_local_time` + `DST_TABLE` (`src/mapping.lua`)** — Phase 3's date helpers extended to 2050 in the post-review fix batch. Phase 4 reuses for payout `bookingDate` (PAYOUT-03), fee timestamp aggregation (D-49), and `valueDate` promotion (D-56). No new date code.
- **`M_mapping._format_amount` + `_format_label` + `_format_purpose` (`src/mapping.lua`)** — Phase 3 formatters. Phase 4 extends `_format_purpose` to handle multi-rate VAT (D-53) and the card-brand+entry-mode tail (D-57). The other two unchanged.
- **`M_mapping.purchase_to_transaction` + `refund_to_transaction` (`src/mapping.lua`)** — Phase 3 entry points. Phase 4 adds `fee_to_transaction`, `fee_aggregate_to_transaction`, `payout_to_transaction` as sibling pure-logic mappers, and a `promote_to_booked(sale_txn, valueDate)` mutator helper for D-56.
- **`M_errors.from_http_status` (`src/errors.lua`)** — Phase 2 error mapper. Phase 4 inherits unchanged for Finance API errors (any retry/backoff work is Phase 5).
- **`M_log.redact` (`src/log.lua`)** — Phase 1 + Phase-2-Lows-widened. Phase 4 inherits unchanged; SEC-03 gating spec extends to cover Finance API response payloads (same gate, more fixtures).
- **`M_i18n.t` (`src/i18n.lua`)** — Phase 3 added 7 keys. Phase 4 adds: `account.purpose.fee_label`, `account.purpose.fee_for_receipt`, `account.purpose.fee_aggregate`, `account.purpose.fee_aggregate_count`, `account.name.payout`, `account.name.fee`, `account.name.fee_aggregate`, `account.purpose.payment_method.kontaktlos`, `.chip`, `.swipe`, `.magstripe`, `.unknown`. All in both `de` (primary) and `en` (technical fallback).
- **`Fixtures.load(...)` (`spec/helpers/fixtures.lua`)** — Phase 0 loader. Phase 4 adds `spec/fixtures/finance/*.json` and reuses verbatim.

### Established Patterns
- **`do … end` block wrap** — every `src/*.lua` is wrapped by `tools/build.lua`. Phase 4 follows.
- **No `require()` of siblings** — cross-module via global `M_*` tables; Phase 4 adds `M_finance` to the same registry.
- **Pure-logic mapping modules return transaction tables, never call I/O** — Phase 3's mapping.lua never touches the network; Phase 4's fee_to_transaction / payout_to_transaction / fee_aggregate_to_transaction follow this.
- **`pcall` around `JSON()` parse only** — never around `conn:request`. Phase 4 inherits.
- **`-- luacheck: ignore 431` for callback args** — already applied to Phase 3's `RefreshAccount(account, since)`; Phase 4's expanded callback body inherits.
- **`transactionCode` prefix as the dedup contract** — D-38 (Phase 3) plus D-58 (Phase 4) extension. SEC-03 gating spec is the structural enforcement.
- **Boundary clamps live in `entry.lua RefreshAccount`** — D-33 since-clamp pattern. Phase 4's `purchases_by_uuid` index build (D-50) lives at the same boundary, NOT inside the mapping module.

### Integration Points
- **`src/entry.lua RefreshAccount(account, since)`** — Phase 3 rewired this to: clamp since → cached_token → purchases.fetch_all → mapping. Phase 4 extends to:
  1. clamp since (D-33 unchanged)
  2. cached_token (D-41 unchanged)
  3. `M_purchases.fetch_all(effective_since, bearer)` → `all_purchases`
  4. `M_finance.fetch_account_state(bearer)` → `{ balance, pendingBalance }`
  5. `M_finance.fetch_all(effective_since, bearer)` → `all_finance_records` (split internally into `payments`, `fees`, `payouts`)
  6. Build `purchases_by_uuid` index (D-50)
  7. Map purchases → sale transactions (Phase 3 logic, unchanged)
  8. Cross-reference each sale against `payments_by_uuid` index from finance results; if matched AND a corresponding payout exists, promote `booked=true` + `valueDate` via D-56 mutator
  9. Map refunds → refund transactions WITH original-sale lookup from `purchases_by_uuid` (D-50)
  10. Map per-sale fees (linked) via `fee_to_transaction` + originating sale lookup (D-49 primary)
  11. Aggregate unlinked fees by date via `fee_aggregate_to_transaction` (D-49 fallback)
  12. Map payouts via `payout_to_transaction`
  13. Return `{ balance, pendingBalance, transactions = combined_list }`
- **`src/purchases.lua`, `src/mapping.lua`, `src/pagination.lua`** — Phase 3 implementations are touch-free for Phase 4's added mapping functions; `_format_purpose` gets extended in `mapping.lua` per D-53 + D-57 (additive only, no Phase 3 behaviour changes).
- **`src/finance.lua`** — new module, Phase-1 stub-table only currently; Phase 4 fills `M_finance.fetch`, `fetch_all`, `fetch_account_state`, `parse_transaction`.
- **`src/i18n.lua`** — additive (12 new keys per `M_i18n.t` section above).
- **CI egress allowlist** — extend the existing SEC-02 grep allowlist regex with `finance.izettle.com` (Plan 04-06; predicated on D-46 Q3 PASS).

</code_context>

<specifics>
## Specific Ideas

- **Q3 sandbox probe is the single hard prerequisite.** Plan 04-01 (Wave 0) is exactly one task: a Yves-executed live GET against `https://finance.izettle.com/v2/accounts/liquid/transactions?start=2026-06-01T00:00:00.000+0000&end=2026-06-21T00:00:00.000+0000&limit=1&includeTransactionType=PAYMENT` with the user's sandbox token, the response body redacted-and-pasted into a worktree comment, and an ADR-0003 Q3 transition from DEFERRED → ACCEPTED with the live response shape attached. If the host turns out to be different (e.g., `oauth.zettle.com` redirects, or a `finance-eu.izettle.com` regional sharding emerges), the Q3 ADR records the truth and Wave 1 replans.
- **The fee-fallback contract (D-49) is the load-bearing UX promise.** A merchant who runs Phase 4 must understand from looking at MoneyMoney's transaction list whether they're seeing per-sale fees or daily aggregates. Plan 04-05 must add a German `purpose` text that makes this self-explanatory ("Tagesaggregat — {N} Einzelgebühren — Detail-Verknüpfung nicht verfügbar") — loop-lektor will refine in Wave 5.
- **The SALE-03 closure (D-56) is observable as a regression risk.** Phase 3's idempotency gating spec asserts double-refresh produces zero new transactionCodes. Phase 4's extension must assert the same — including for sales whose `booked` flag toggles. The dedup contract relies on MoneyMoney updating the same row in place, which the WebBanking API documents but Phase 4 should verify empirically against a fixture matrix that includes both "first-refresh pending" and "second-refresh promoted" snapshots.
- **META-03 (D-55) is a permanent, never-rewrite invariant.** Once Yves signs off the forbidden-strings list in Wave 0, it's locked for the lifetime of the project. Any future feature request that adds tax-classification wording (e.g., "show 0% MwSt purchases as USt-frei") requires this CONTEXT to be revisited explicitly, not silently overridden in a plan.
- **Phase 3's surface preservation is non-negotiable** — `SupportsBank`, `InitializeSession2`, `ListAccounts`, `EndSession` continue to be byte-identical from Phase 2. `RefreshAccount` changes shape (new `pendingBalance` return field, expanded transaction list) but the function signature and the legacy `balance` field remain. Wave 5's audit spec confirms.
- **Coverage gate stays at 99 %+** — Phase 3 landed 99.23 %; Phase 4's added mapping modules + Finance fetch should stay at or above this. Defensive nil-guards (analogous to Phase 3's 4 dead lines) are acceptable as long as they're documented in the Plan summaries.

</specifics>

<deferred>
## Deferred Ideas

- **Per-payout drilldown** (which sales belong to a payout) — Phase 5/6 UX. Phase 4 ships the per-sale + per-payout rows independently.
- **Retry / backoff for 429 + 5xx on the Finance API** — Phase 5 (`errors.lua` expansion; same Phase as Purchase API retry).
- **Force-full-historical-sync flag** — Phase 5/6 UX (override D-33 90-day clamp on demand).
- **Per-payment-method-fee analytics** (e.g., "show me only contactless fees this month") — never; this is a Steuerberater task, not an extension feature.
- **Multi-currency support** — out of scope for v1.0.0; D-37 skip still applies.
- **Cancellations** (Zettle's hypothetical `cancelled = true` flag) — not in the documented schema; revisit if real users report.
- **Receipt-copy URL + GPS coordinates in `purpose`** — Phase 5/6 enrichment.
- **ZUGFeRD / DATEV export** — far-future; out of scope.
- **A separate "payouts" subaccount in MoneyMoney** — out of scope; payouts surface as negatives in the single Giro account per D-51.
- **Real TZ database for `bookingDate`** — Phase 6+ if cross-locale support is added; v1 stays on the D-36 + post-review hardcoded EU-DST table (now 2020-2050).
- **DEBUG-level logging gated by a runtime toggle** — out of scope per D27/D29 + SEC-04; Phase 4 inherits the hardcoded `DEBUG = false` invariant.

</deferred>

---

## Yves Blockers (autonomous-window pauses)

Per `~/.claude/projects/-Users-yves-Development-paypal-pos-plugin/memory/project_48h_autonomous_window.md`, the autonomous window does NOT cover credential setup or Pay/Compliance decisions. The following items are queued for Yves' return:

| ID | Item | Type | Recommended | What Yves Needs to Do |
|----|------|------|-------------|------------------------|
| **Q3** | `finance.izettle.com` host live verification | Credential setup | Execute Plan 04-01 probe against sandbox tenant | Run a single live GET with sandbox token; record response shape; flip ADR-0003 Q3 from DEFERRED → ACCEPTED with the observed body |
| **D-49** | Fee-fallback contract (per-sale vs daily aggregate; once-aggregated-always-aggregated dedup) | Pay/Compliance | Aggregate persistence wins over linkage upgrades to preserve idempotency | Confirm the bookkeeping tradeoff: slightly lossy fee linkage is acceptable in exchange for hard dedup |
| **D-55** | META-03 forbidden-strings list completeness | Pay/Compliance | List as drafted above (13 phrases) | Confirm the list captures the German tax-classification wording you want to permanently forbid; add cognates if any are missing |

**Once Q3 + D-49 + D-55 are confirmed, planning Wave 0 can lock and `/gsd-plan-phase 4 --auto` can run to completion.** Until then, this CONTEXT serves as the recommendation document; nothing else has been committed and no source files have been touched.

---

*Phase: 04-enrichment-refunds-fees-payouts*
*Context gathered: 2026-06-21*
