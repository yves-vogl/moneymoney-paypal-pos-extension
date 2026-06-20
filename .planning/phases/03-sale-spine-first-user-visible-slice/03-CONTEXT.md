# Phase 3: Sale Spine (first user-visible slice) - Context

**Gathered:** 2026-06-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire `src/purchases.lua`, `src/mapping.lua`, and `src/pagination.lua` (Phase-1 empty stubs) into a working sale ingestion path: `RefreshAccount` calls `GET https://purchase.izettle.com/purchases/v2` with the Phase-2 Bearer token, iterates `lastPurchaseHash` cursor pages, maps each completed purchase into a single `AccountTypeGiro` transaction with stable `transactionCode = "zettle:sale:<purchaseUUID1>"`, surfaces a German payment label, and respects MoneyMoney's `since` parameter so an unchanged account refreshes empty. The double-refresh idempotency gate (`SALE-02` + `SALE-05` + `TEST-03`) is the load-bearing acceptance criterion — if it fails, the phase has failed.

**In scope:**
- `M_purchases.fetch(account, since)` — single fetch round-trip per page, returning normalized purchase records
- `M_pagination.iterate(connection_fn, initial_params)` — cursor loop using `lastPurchaseHash` until `purchases[]` shorter than `limit` or empty
- `M_mapping.purchase_to_transaction(purchase)` — pure-logic transformation from Zettle purchase JSON to MoneyMoney transaction table (`name`, `amount`, `currency`, `bookingDate`, `purpose`, `transactionCode`, `booked`)
- `M_mapping.refund_to_transaction(refund_purchase)` — separate negative-amount transaction for refunds (D-32)
- Filtering: `since` clamp to max-90-days-back on first refresh (D-33); skip non-EUR purchases (D-37); skip purchases not yet completed
- German user-facing strings via `M_i18n.t` extensions (`account.purpose.gross`, `account.purpose.vat`, `account.purpose.tip`, `account.purpose.net`, `account.purpose.refund_for`, `account.name.card_payment`) — I18N-01
- `src/entry.lua RefreshAccount` swaps its Phase-2 fixture transaction for the real mapping pipeline
- Idempotency gating spec (`spec/refresh_idempotency_spec.lua`): two consecutive RefreshAccount calls on the same fixture produce zero new transactions on the second call (TEST-03)
- Golden-file schema spec (`spec/mapping_schema_spec.lua`): every returned transaction has `name`, `amount`, `currency`, `bookingDate`, `purpose`, `transactionCode`, `booked` (TEST-04)
- bookingDate: UTC ISO-8601 → POSIX local-time (Europe/Berlin, DST-aware via small hardcoded rules table, D-36)

**Out of scope:**
- Payout fetch and the `booked=false → true` + `valueDate` transition — **Phase 4** (Finance API integration). Phase 3 ships **every** sale with `booked=false` and no `valueDate`; Phase 4 re-emits with the same `transactionCode` and updates these fields (D-31).
- Per-sale fee (commission) display in `purpose` — Phase 4, sourced from `payments[].commission.totalAmount` plus Finance API `PAYMENT_FEE` cross-check.
- VAT breakdown by rate (e.g., 7% / 19% split using `groupedVatAmounts`) — Phase 5 enrichment.
- Retry / backoff / 429 throttling — Phase 5 (`errors.lua` expansion). Phase 3 surfaces 429 verbatim via Phase-2's existing `M_errors.from_http_status` → the German `error.rate_limit` string.
- Force-full-sync toggle / configurable max-age cap — Phase 5/6. README documents the 90-day clamp as a known constraint of v0.1.0.
- Receipt-copy URL (`purchase.receiptCopyAllowed`) and GPS coordinates (`purchase.gpsCoordinates`) in `purpose` — Phase 5/6.
- Multi-currency support beyond EUR — out of scope for v1.0.0; non-EUR purchases are SKIPPED with an INFO log line (D-37).
- Discounts (`purchase.discounts[]`) detailed rendering — Phase 5 enrichment. Phase 3 trusts the top-level `amount` (already includes discounts and VAT per Zettle docs) for the transaction's gross amount.

</domain>

<decisions>
## Implementation Decisions

### Pending vs Booked transition (Area A — SALE-03)
- **D-31:** Phase 3 emits **every** mapped sale with `booked = false` and **no** `valueDate`. The full SALE-03 lifecycle (`booked = false → true` once a payout is linked, with `valueDate = payout date`) requires Finance API + payout cross-reference, which is Phase 4. Phase 3 ships the static `false` half of the contract; Phase 4 closes the dynamic transition. MoneyMoney's idempotency contract guarantees Phase 4 can re-emit each transaction with the same `transactionCode` and the `booked`/`valueDate` fields will be updated in place — no schema migration, no transaction deletion, no user-visible churn.
- **Visible consequence in Phase 3:** Every PayPal POS sale shows in MoneyMoney's "vorgemerkte Umsätze" (pending transactions) section until Phase 4 ships. README explicitly documents this transitional state so v0.1.0 testers don't misread it as a bug.
- **Why not a heuristic** (e.g., "sales older than 5 days = booked"): PROJECT.md's contract is "accurate, suitable for bookkeeping". A heuristic guess about settled-vs-pending state would surface as booked transactions that are still unsettled by Zettle — a real bookkeeping error for DATEV/UStG users. Either we know (Phase 4) or we don't (Phase 3 = false).

### Refund handling (Area B)
- **D-32:** A purchase with `refund == true` becomes its **own** MoneyMoney transaction record with `transactionCode = "zettle:refund:" .. purchaseUUID1` (where `purchaseUUID1` is the refund's own UUID, not the original sale's). `amount` is negative (= `-purchase.amount`). `purpose` field starts with the German "Rückerstattung zu Beleg #" followed by the original sale's `purchaseNumber` (looked up from `refundsPurchaseUUID1` via a same-page lookup; if the original is not on the current page, fall back to "Rückerstattung zu Beleg <refundsPurchaseUUID1>" using the UUID). The original sale's transaction is **not** modified — MoneyMoney's own dedup keeps it as it was. Net effect: in the merchant's transaction list, a refund appears as a clearly-marked negative transaction next to (or below) the corresponding sale.
- `name` field for refunds: "Kartenzahlung Rückerstattung" (or "Visa •••• 1234 Rückerstattung" if card metadata is preserved on the refund purchase — Zettle echoes the original payment method, per the spec's `payments[]` shape).
- Multiple refunds for the same original sale: each gets its own row. Single original sale → multiple refund rows. Sum is transparent in the merchant's bookkeeping ledger.

### First-refresh pagination strategy (Area C)
- **D-33:** Phase 3 clamps the `since` parameter passed to the Zettle API to `max(since_from_moneymoney, now() - 90 * 86400)`. On a freshly-added account (MoneyMoney passes `since = 0` or close to it), this means **only the last 90 days of purchases** are fetched. Subsequent refreshes use the real `since` from MoneyMoney's incremental contract, so newly-arriving sales after the first refresh are picked up normally.
- README v0.1.0 documents this verbatim, including the workaround: "Older sales can be re-imported by [Phase-5+ TBD flag] or by manually editing the account's `lastFetched` timestamp via MoneyMoney's database tooling (advanced)."
- **Why 90 days and not 30/180:** 90 days balances first-touch responsiveness (well inside MoneyMoney's per-call timeout — typical merchant has ≤2000 purchases in 90 days, fits in 1–3 cursor pages, refresh completes in <10s) against bookkeeping usefulness (covers a full quarter, including most VAT-relevant windows for UStG advance payments).
- **Phase-1 ADR-0003 carryover (Q3):** The Phase-3 `purchases.lua` only calls `purchase.izettle.com` — `finance.izettle.com` (Q3) remains deferred to Phase 4. The egress allowlist already permits both hosts (Phase-1 D-12); no allowlist change in Phase 3.

### bookingDate timezone (Claude's Discretion — captured for record)
- **D-36:** `bookingDate` is computed as **Europe/Berlin local time** (DST-aware), not raw UTC and not system-`os.date` (which would be fragile under CI runs in non-Berlin timezones). The Phase-3 implementation ships a small hardcoded EU DST rules table inside `src/mapping.lua`: DST starts last Sunday of March at 01:00 UTC (offset +2h), DST ends last Sunday of October at 01:00 UTC (offset +1h). The table covers years 2020–2040 generated deterministically at build time — `tools/build.lua` already runs Lua, so generating ~20 boundary timestamps is trivial. A spec asserts a sale at `2026-06-19T23:55:00Z` maps to `bookingDate` representing local-day `2026-06-20` (SALE-04 acceptance criterion), and a sale at `2026-01-31T23:55:00Z` (CET, +1h) maps to local-day `2026-02-01`.
- **Why not pure `os.time(os.date("*t", t))`:** the result depends on `$TZ` at runtime; CI runs on GitHub Actions in UTC by default. The deterministic table makes the spec passable on every developer's laptop and on CI without `TZ=Europe/Berlin` environment seeding.
- **Acceptable tech debt:** if the project ever ships beyond the German-merchant target, the hardcoded table is replaced by a real TZ database or by `MM.localizeDate` (if MoneyMoney exposes such a helper — to be checked in Phase 5/6). The 20-year boundary range covers v1.0.0's expected lifetime conservatively.

### Purpose-field format for VAT and Tip (Claude's Discretion — captured)
- **D-34:** `purpose` is a multi-line German bookkeeping-oriented string. Lines (each `\n`-separated):
  1. `Brutto: <amount> €` (always — the headline gross amount, equivalent to the transaction's `amount` field but visible at-a-glance in the purpose body)
  2. `MwSt: <vat_amount> €` (always when `vatAmount > 0`; omitted on zero-VAT purchases)
  3. `Trinkgeld: <tip_sum> €` (only when sum of `payments[].gratuityAmount > 0`)
  4. `Netto: <amount - vat_amount - tip_sum> €` (always — the merchant's actual revenue net of VAT and tip)
- Numbers formatted with German conventions: comma decimal separator, no thousands separator below 10000 (e.g., `9,95` not `9.95`; `9.999,95` if needed).
- `purchaseNumber` is appended as a final line: `Beleg #<purchaseNumber>` — helps merchant reconcile with Zettle's own receipt list.
- Reason this format: bookkeeping users (DATEV/UStG) need to verify gross/VAT/net at a glance; the inline format is easier to scan than a single concatenated string and matches German invoice conventions.

### Payment label (`name` field) format (Claude's Discretion — captured)
- **D-35:** Default `name = "Kartenzahlung"`. When `purchase.payments[1]` carries card metadata (`cardBrand` and `cardLastFour`, per Zettle's purchase schema), upgrade to `"<CardBrand> •••• <last_four>"` with the bullet-dot Unicode character (U+2022). Recognized `cardBrand` values mapped to display: `VISA → Visa`, `MASTERCARD → Mastercard`, `AMEX → Amex`, `MAESTRO → Maestro`, `GIROCARD → girocard`, `UNIONPAY → UnionPay`. Unknown brands surface as their capitalized literal.
- Refunds get the suffix `" Rückerstattung"` appended (D-32) — the brand-and-last-four prefix is preserved.
- This satisfies success criterion 6 (I18N-01) which requires a German customer-facing label.

### Multi-currency defensive guard (Claude's Discretion — captured)
- **D-37:** If `purchase.currency != "EUR"`, the purchase is **silently SKIPPED** (not surfaced to MoneyMoney, an INFO log line records the skip). Phase 2 hard-locked the account to EUR (`account.currency = "EUR"` from D-23a); a mixed-currency response would otherwise produce an EUR transaction with a non-EUR amount value, which is a real bookkeeping error.
- Phase 5/6 may revisit if real users need cross-currency. Out of scope for v1.0.0.

### transactionCode schema and idempotency contract
- **D-38:** transactionCode formats:
  - Sales: `"zettle:sale:" .. purchaseUUID1`
  - Refunds: `"zettle:refund:" .. purchaseUUID1` (where `purchaseUUID1` is the refund purchase's own UUID, not the original's)
  - Reserved for future phases: `"zettle:payout:<payoutUuid>"` (Phase 4), `"zettle:fee:<feeTransactionUuid>"` (Phase 4/5)
- **D-39:** Idempotency gating contract: `RefreshAccount(account, since)` called twice in a row on the same backend state MUST return zero new transactions on the second call (MoneyMoney's own dedup, keyed on `transactionCode`, handles this — but Phase 3 ships the gating spec that proves it works for our mapping). `spec/refresh_idempotency_spec.lua` queues the same purchase fixture twice in the mock, runs RefreshAccount twice, and asserts: first call returns N transactions, second call returns ≥0 but every emitted transaction has a `transactionCode` already in the first batch (i.e., no new ones from MoneyMoney's perspective). TEST-03 is locked by this spec.

### File layout (planner constraint, not surface)
- **D-40:** Phase 3 fills the following Phase-1 stubs (already declared as `M_* = {}` in `src/webbanking_header.lua`):
  - `src/purchases.lua` — `M_purchases.fetch(account, since)` (single page) and the orchestration that drives pagination
  - `src/pagination.lua` — `M_pagination.iterate(fetch_page_fn, initial_params)` (cursor loop with `lastPurchaseHash`)
  - `src/mapping.lua` — `M_mapping.purchase_to_transaction(p)`, `M_mapping.refund_to_transaction(p, page_index_for_original_lookup)`, plus internal helpers `_format_amount`, `_format_purpose`, `_format_label`, `_to_berlin_local_time`
  - `src/entry.lua RefreshAccount` is **rewired** to drive the new pipeline (Phase-2 left it returning a fixture). The Phase-2 surface contract for `InitializeSession2`, `ListAccounts`, `EndSession` is **frozen** — Phase 3 does not touch those callbacks.
  - `src/i18n.lua` gets the six new keys (D-34/D-35) added to both `STRINGS.de` and `STRINGS.en`.
- **No new module-table declarations** in `webbanking_header.lua`. The pre-declared `M_purchases`, `M_pagination`, `M_mapping` are sufficient.

### Cross-cutting decisions tied to all areas
- **D-41:** Phase 3 calls `M_auth.cached_token(orgUuid)` (Phase 2 D-23d) to obtain the Bearer; never re-authenticates from within RefreshAccount. If `cached_token` returns nil (e.g., user removed the account or token storage was cleared), RefreshAccount returns the German `error.network` string — no silent re-auth.
- **D-42:** Phase 3 calls `M_http.get_json(url, headers)` (Phase 2 D-25) for all purchase fetches. No new HTTP surface, no new redaction patterns, no new egress hosts. The Bearer header passes through Phase-2's existing redaction (`M_log.redact`).
- **D-43:** Phase 3 calls `M_errors.from_http_status(status, body)` (Phase 2 D-24) for HTTP error mapping. No new error cases introduced in Phase 3 — the additive expansion is reserved for Phase 5.
- **D-44:** Test fixtures for Phase 3 are hand-rolled JSON files under `spec/fixtures/purchases/`. Required fixtures: `purchase_simple_sale.json` (single sale, EUR, no VAT, no tip), `purchase_with_vat_and_tip.json` (VAT-bearing, tip, with `groupedVatAmounts`), `purchase_refund.json` (refund=true with `refundsPurchaseUUID1`), `purchase_page1.json` (≥1 record + `lastPurchaseHash`), `purchase_page2.json` (continuation page), `purchases_empty.json` (empty array), `purchase_non_eur.json` (`currency: "USD"`, must be skipped), `purchase_dst_boundary.json` (timestamp at `2026-06-19T23:55:00Z` for SALE-04 verification), `purchase_with_card_metadata.json` (Visa with `cardLastFour`).
- **D-45:** SEC-03 redaction (Phase 2 D-29) is **not re-tested** in Phase 3 — the gating spec was already merged. Phase 3's specs do not invalidate any redaction invariant (no new log call sites that could leak the Bearer; all log calls go through `M_log.redact`).

### Claude's Discretion (delegated to planner)
- Internal helper-function signatures inside `mapping.lua` (the public surface `M_mapping.purchase_to_transaction` / `M_mapping.refund_to_transaction` is locked above; private helpers are planner's call)
- Exact spec file partitioning under `spec/` (one file per module vs split by feature) — planner's call
- Whether to inline the DST rules table inside `mapping.lua` or hoist to a small `src/timezone.lua` (only Phase-3-introduced module if hoisted; planner decides based on size and readability)
- Order of pagination loop checks (loop-then-check vs check-then-loop) — planner's call subject to: empty `purchases[]` array MUST terminate the loop unconditionally

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project decisions and prior phase context
- `.planning/PROJECT.md` — paste-once UX, 30 s refresh budget, no telemetry, bookkeeping accuracy contract ("if the data is wrong, incomplete, or stale, the project has failed")
- `.planning/REQUIREMENTS.md` §§ SALE-01, SALE-02, SALE-03, SALE-04, SALE-05, SALE-06, SALE-08, I18N-01, TEST-03, TEST-04 — verbatim requirement text
- `.planning/ROADMAP.md` — Phase 3 section (goal, success criteria 1–6, dependency on Phase 2, ADR-0003 Q4 dependency)
- `.planning/phases/02-authenticated-network-layer/02-CONTEXT.md` — Phase-2 locked decisions, especially D-21 (token+profile probe), D-23a/b/c/d (cache shape), D-24 (`from_http_status`), D-25 (`get_json` / `post_form`), D-26 (egress allowlist), D-29 (SEC-03 invariant)
- `.planning/phases/02-authenticated-network-layer/02-{01..07}-SUMMARY.md` and `02-08-FIX-SUMMARY.md` — what was actually built in Phase 2, what the Bearer flow looks like in practice, and what redaction tests cover
- `.planning/phases/01-foundations-sandbox-probes/CONTEXT.md` — Phase-1 amalgamator + mock conventions (D-02 no-`require`, D-08 redaction primitives, D-14 module-stub posture, D-19 build artifact name)
- `.planning/phases/01-foundations-sandbox-probes/RESEARCH.md` — module inventory and mock surface

### Architecture decision records
- `docs/adr/0001-amalgamator-design.md` — single-file build constraint; Phase-3 code must survive `tools/build.lua` concatenation; no `require()` of siblings
- `docs/adr/0003-sandbox-probe-results.md`:
  - **Q4 (PASS, resolved)** — JSON integer round-trip with `amount=995` works; `mapping.lua` stores minor-unit amounts as plain Lua numbers. **Phase 3 unblocked by this resolution.**
  - **Q3 (DEFERRED to Phase 4)** — `finance.izettle.com` host verification. Phase 3 only calls `purchase.izettle.com`; Q3 remains for Phase 4's payout work.
  - **Q5 (partially resolved)** — `LocalStorage` nested-table writability confirmed (cross-restart persistence still observed in production logs). Phase 3 makes no new `LocalStorage` writes — purely uses Phase 2's existing cache.

### iZettle / Zettle / PayPal POS API references
- `iZettle/api-documentation/purchase.adoc` (GitHub) — verbatim purchase JSON shape, including `purchaseUUID1`, `amount` (minor units integer), `vatAmount`, `currency`, `timestamp` (ISO-8601 UTC), `purchaseNumber`, `refund` (bool), `refundsPurchaseUUID1`, `refundedByPurchaseUUIDs1`, `products[]`, `payments[]` (which carries `cardBrand`, `cardLastFour`, `gratuityAmount`, `commission.totalAmount`), `groupedVatAmounts`
- `developer.zettle.com/docs/api/purchase/user-guides/fetch-purchases/fetch-a-list-of-purchases` — query params (`startDate`, `endDate`, `limit`, `descending`, `lastPurchaseHash`), pagination semantics, host `purchase.izettle.com`
- `iZettle/api-documentation/authorization.md` — Bearer-token shape (reused from Phase 2; no new auth code in Phase 3)

### MoneyMoney WebBanking API
- `moneymoney.app/api/webbanking/` — `RefreshAccount(account, since)` signature and return conventions, including the transaction table fields (`name`, `amount`, `currency`, `bookingDate`, `valueDate`, `purpose`, `transactionCode`, `booked`), the `since` parameter as POSIX timestamp, and the contract that returning a transaction with a previously-seen `transactionCode` is idempotent (MoneyMoney dedup keyed on `transactionCode`)

### Test infrastructure (already in repo)
- `spec/helpers/mm_mocks.lua` — `Mocks.push_response()` queue and `Mocks._last_request` introspection (Phase 0/2)
- `spec/helpers/fixtures.lua` — `Fixtures.load("purchases/<name>")` loader (Phase 0); Phase 3 adds the JSON files under `spec/fixtures/purchases/`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`M_http.get_json(url, headers)` (`src/http.lua`)** — Phase 2's transport. Returns 5-tuple destructured response per D-25; Phase 3 calls this for every page fetch. No new HTTP surface.
- **`M_auth.cached_token(orgUuid)` (`src/auth.lua`)** — Phase 2's token-cache read. Returns access_token string or nil. Phase 3 calls once per RefreshAccount (token is reused across all pages of one refresh).
- **`M_errors.from_http_status(status, body)` (`src/errors.lua`)** — Phase 2's error mapper. Phase 3 piped through this for any non-2xx — no new error codes.
- **`M_log.redact(s)` (`src/log.lua`)** — Phase 1 + Phase-2-Lows widened. Phase 3 calls this on every body before any DEBUG log line. No new redaction patterns required.
- **`M_i18n.t(key, ...)` (`src/i18n.lua`)** — Phase 3 adds six new keys (`account.purpose.gross`, `account.purpose.vat`, `account.purpose.tip`, `account.purpose.net`, `account.purpose.refund_for`, `account.purpose.receipt_number`, `account.name.card_payment`) to both `STRINGS.de` (primary) and `STRINGS.en` (technical contributors).
- **`JSON()`** (MoneyMoney built-in; mocked via `spec/helpers/mm_mocks.lua`) — `JSON(raw):dictionary()` decodes the response body. `pcall`-wrap when decoding attacker-controlled body (consistent with Phase 2's D-25).
- **`spec/helpers/fixtures.lua Fixtures.load("purchases/<name>")`** — Phase-0 loader, works on macOS POSIX; Phase 3 adds JSON files under `spec/fixtures/purchases/`.

### Established Patterns
- **`do … end` block wrap** — every `src/*.lua` is wrapped by `tools/build.lua`. Phase 3 follows this.
- **No `require()` of siblings** — cross-module access via global `M_*` tables.
- **5-tuple destructure of `Connection:request` return** — handled inside `M_http` (Phase 2). Phase 3 only sees the parsed JSON / status pair returned by `get_json`.
- **`pcall` around `JSON()` parse only** — never around `conn:request` (Phase-1 ADR-0003 Q8: pcall does NOT catch `Connection()` SSL/network errors).
- **`-- luacheck: ignore 431` for callback args** — `RefreshAccount(account, since)` follows the same shadowing pattern.

### Integration Points
- **`src/entry.lua RefreshAccount(account, since)`** — currently returns a Phase-2 fixture transaction. Phase 3 swaps the fixture for: (1) read `account.accountNumber` (= `orgUuid` per Phase-2 D-23a), (2) `M_auth.cached_token(orgUuid)` → Bearer, (3) clamp `since` per D-33, (4) call `M_purchases.fetch(...)` driving pagination, (5) call `M_mapping.purchase_to_transaction` (or `refund_to_transaction`) for each non-skipped purchase, (6) return `{ balance = account.balance, transactions = ... }`. Balance stays `account.balance` (not refreshed in Phase 3 — Phase 4 wires it from Finance API).
- **`src/purchases.lua`, `src/mapping.lua`, `src/pagination.lua`** — Phase-1 declared the module tables as empty stubs in `src/webbanking_header.lua`. Phase 3 fills the function tables.
- **Egress** — only `purchase.izettle.com` is touched (Phase-2 D-26 allowlist already permits this; `oauth.zettle.com` was used in Phase 2, `finance.izettle.com` will be Phase 4). CI's egress-grep continues to gate.

</code_context>

<specifics>
## Specific Ideas

- **Idempotency is the load-bearing acceptance criterion.** Success criterion 2 (SALE-02 + SALE-05 + TEST-03) explicitly names "zero new transactions on double-refresh" as the gating test. If this fails, no other Phase-3 work compensates. Plan 03-0X (TBD: idempotency spec) must be one of the **earliest** plans (Wave 1) and must run RED first against an empty `purchases.lua` to prove the spec actually fails before the implementation makes it pass.
- **TEST-04 golden-file schema spec** asserts the seven required transaction fields exist on every returned transaction. This is the structural gate: if mapping.lua ever drops a field or renames one, the schema spec fails the build before MoneyMoney sees a malformed transaction. Plan 03-0X (TBD: schema spec) goes in Wave 1 alongside idempotency.
- **The `since` clamp (D-33) is enforced at the boundary in `RefreshAccount`**, not inside `M_purchases.fetch`. The fetch function gets the already-clamped value and treats it as a literal POSIX timestamp; the boundary keeps the clamp visible at the entry point for future debugging.
- **Phase 2's Phase-3 carryover** (`SECURITY-REVIEW.md` § "T6 multi-merchant cache pollution: PARTIAL — S-01 nil orgUuid crash" — note that S-01 was already fixed in the Phase-2 post-review fix batch) means Phase 3 inherits Phase-2's guard that `orgUuid` is a non-empty string before any cache lookup. No re-test needed.
- **Card metadata MAY be absent** even on a successful card payment (e.g., older Zettle terminals, regional regulations). The mapping must default to "Kartenzahlung" without ever erroring on absent fields — every `payments[1].cardBrand` / `cardLastFour` access is guarded.
- **The DST boundary fixture** (`purchase_dst_boundary.json`) carries a timestamp at `2026-06-19T23:55:00Z` (=Berlin 01:55+02:00 local on 2026-06-20). The spec asserts the mapped `bookingDate` represents local-day `2026-06-20`. A second fixture at `2026-01-31T23:55:00Z` (=Berlin 00:55+01:00 local on 2026-02-01) covers the winter (CET) case. Both fixtures gate D-36.

</specifics>

<deferred>
## Deferred Ideas

- **Booked = true transition with `valueDate = payout date`** — Phase 4, requires Finance API + payout-to-purchase cross-reference
- **Per-purchase fee display** (`payments[].commission.totalAmount`) — Phase 4 (cross-reference with Finance API `PAYMENT_FEE`) and/or Phase 5 (display refinement)
- **VAT split by rate** (`groupedVatAmounts` breakdown e.g. 7% / 19%) — Phase 5 enrichment
- **Receipt-copy URL** (`purchase.receiptCopyAllowed`) and GPS coordinates in `purpose` — Phase 5/6
- **Discounts breakdown** (`purchase.discounts[]` rendered as a deduction line) — Phase 5 enrichment; Phase 3 trusts the top-level `amount` which already includes discounts
- **Force-full-sync flag** (override the 90-day clamp from D-33 for one refresh) — Phase 5/6 UX work
- **Multi-currency support** (currently EUR-only per D-37, non-EUR purchases skipped) — out of scope for v1.0.0; revisit if a non-German user files an issue
- **Retry/backoff for 429 and 5xx** — Phase 5 (`errors.lua` expansion). Phase 3 surfaces these errors verbatim via Phase 2's `from_http_status`.
- **Real TZ database for `bookingDate`** (replacing the hardcoded EU-DST table from D-36) — Phase 5/6 if cross-locale support is added; v1.0.0's hardcoded table covers 2020–2040 deterministically
- **Per-day or per-payout grouping** for display (e.g., Zettle's "settlement" grouping) — Phase 4 with payout data
- **Cancellation handling** (purchase with `cancelled = true` field if Zettle adds it) — not currently in the purchase schema as documented; revisit if real users report seeing these

</deferred>

---

*Phase: 03-sale-spine-first-user-visible-slice*
*Context gathered: 2026-06-20*
