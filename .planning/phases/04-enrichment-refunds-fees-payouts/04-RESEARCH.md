# Phase 4: Enrichment — Refunds, Fees, Payouts, Balance, VAT, Tips — Research

**Researched:** 2026-06-21
**Domain:** Zettle Finance API (`finance.izettle.com/v2`) layered onto Phase 3's Purchase API spine; cross-refresh purchase↔payment indexing for refund original-sale lookup, per-sale fee linkage with daily-aggregate fallback, payout emission, balance/pendingBalance, per-rate VAT, German bookkeeping invariants
**Confidence:** HIGH (Finance API surface is fully documented; only Phase-4 Wave-0 live probe remains for D-46)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-46..D-60)

- **D-46 (PROBE-REQUIRED; recommendation: `finance.izettle.com`)** — Finance API base host. Wave 0 Plan 04-01 is a single live GET probe against `/v2/accounts/liquid/transactions` with the sandbox token. **This research independently confirms `finance.izettle.com` as the official OpenAPI-published host (see Section 1).** Probe is now a confirmation step, not an open question; if it fails, Wave 1+ replans.
- **D-47** — Finance API auth reuses Phase 2's `M_auth.cached_token(orgUuid)` Bearer byte-identically. Same 2-hour TTL. No new client_id, no new grant. **Conditional on the user's API key having been issued with both `READ:PURCHASE` AND `READ:FINANCE` scopes** (see new risk R-1 in Section 9).
- **D-48** — Pagination: offset-based via parallel `M_pagination.offset_iterate(fetch_page_fn, initial_params)`. **DO NOT modify the Phase-3 cursor iterator `M_pagination.iterate`.** MAX_PAGES guard of 50, same as Phase 3.
- **D-49 (PAY/COMPLIANCE; Yves sign-off pending)** — Fee linkage:
  - **Primary**: every `PAYMENT_FEE` with non-empty `originatingTransactionUuid` resolving to a `payments[].uuid` in the in-refresh `payments_by_uuid` index → `M_mapping.fee_to_transaction`. `transactionCode = "zettle:fee:" .. fee.uuid`. (NOTE: the link target is `payments[].uuid`, NOT `purchaseUUID1` — see Section 2.)
  - **Fallback**: every `PAYMENT_FEE` whose link is missing/unresolved → daily aggregate per ISO Berlin-local date. `transactionCode = "zettle:fee:aggregate:" .. YYYY-MM-DD`. WARN log per aggregate row.
  - **Once aggregated for a date, always aggregated** — even if Zettle later back-fills linkage, we never re-emit those fees as per-sale rows (idempotency wins over linkage upgrades).
- **D-50** — Refund original-sale lookup via in-refresh `purchases_by_uuid` index in `entry.lua`. Built BEFORE mapping refunds. Falls back to Phase-3 D-32 UUID display when the original is out of window.
- **D-51** — Payout = single negative transaction (`amount = -payout.amount`) in the PayPal POS account. The merchant's bank account is touched only via its own MoneyMoney extension.
- **D-52** — Balance + pendingBalance contract: returned via `RefreshAccount`'s return table. **Research correction: there is no single `pendingBalance` field on the Finance API; pendingBalance comes from `/v2/accounts/preliminary/balance` and balance from `/v2/accounts/liquid/balance` (see Section 1.4 and Open Question Q9).**
- **D-53** — Per-rate VAT lines, sorted descending by rate. **Confirmed: `groupedVatAmounts` keys are decimal strings like `"19.0"`, `"7.0"`, `"0.0"`; values are integer minor units of VAT amount itself (NOT net portion). Refund records carry negative values.**
- **D-54** — Tip line unchanged from Phase 3 (D-34 format). Promote zero-suppression to own spec file `spec/meta_purpose_lines_spec.lua`.
- **D-55 (PAY/COMPLIANCE; Yves sign-off pending)** — META-03 invariant: forbidden-strings spec `spec/meta_no_tax_classification_spec.lua` asserts the 13 phrases listed in CONTEXT D-55 never appear in `src/*.lua` or `dist/paypal-pos.lua`.
- **D-56** — SALE-03 closure: when a Finance `PAYMENT` matches a Phase-3 purchase AND a covering `PAYOUT` exists in the same refresh, re-emit the sale with same `transactionCode`, `booked = true`, `valueDate = payout.timestamp_local`. **CRITICAL RESEARCH FINDING: Zettle does NOT publish a documented payout-to-payment link field; "covering" must be inferred by ordering (PAYMENT timestamp ≤ PAYOUT timestamp AND PAYMENT not covered by an earlier PAYOUT). See Section 4 for the recommended inference.**
- **D-57** — Card-brand + entry-mode tail in `purpose`. German labels: `kontaktlos`, `chip`, `swipe`, `magstripe`, `unknown`. **Research correction: actual API values are `CONTACTLESS_EMV`, `ICC`, `ECOMMERCE` (confirmed); `MSR` is ASSUMED. See Section 6.**
- **D-58** — Idempotency gating spec extended to: simple-sale→promoted, payout-only, per-sale fee, aggregate fee with linkage-upgrade-no-double-book.
- **D-59** — Cross-refresh state owned by MoneyMoney dedup; `entry.lua` builds `purchases_by_uuid` and `payments_by_uuid` indexes per-refresh only. No extension-owned state file.
- **D-60** — Plan structure: Wave 0 (Q3 probe — Yves), W1 (Finance mapping pure-logic + offset pagination), W2 (Finance fetch + cross-refresh index + SALE-03 promotion), W3 (per-rate VAT + card-tail in `_format_purpose`), W4 (META-03 invariant + extended idempotency spec), W5 (CHANGELOG + i18n loop-lektor review + Phase-3 surface preservation audit).

### Claude's Discretion (from CONTEXT.md)

- Card-brand tail as separate `purpose` line vs inline at end of `Brutto` line — recommendation: **separate line**, above `Beleg #` footer.
- German wording of D-49 aggregate `purpose` text and WARN log line — loop-lektor pass in Wave 5 owns final.
- META-03 enforcement: spec-only vs also `tools/build.lua` halt — recommendation: **spec-only** for Phase 4; build halt is Phase 6 release-polish.
- Cross-refresh index in `entry.lua`: closure vs small `M_index` module — recommendation: **closure inside RefreshAccount** (no consumer outside RefreshAccount in Phase 4).

### Deferred Ideas (OUT OF SCOPE)

- Per-payout drilldown (which sales belong to which payout, beyond `originatingTransactionUuid`) — Phase 5/6 UX.
- Retry / backoff / 429 throttling for Finance API — Phase 5 (`errors.lua` expansion, same Phase as Purchase API retry).
- Force-full-historical-sync flag — Phase 5/6 UX (override D-33 90-day clamp).
- Per-payment-method-fee analytics — never (Steuerberater task, not extension feature).
- Multi-currency support — out of scope for v1.0.0; D-37 skip applies to Finance records too.
- Cancellations (`cancelled = true` flag) — not in documented schema; revisit if real users report.
- Receipt-copy URL + GPS coordinates in `purpose` — Phase 5/6 enrichment.
- ZUGFeRD / DATEV export — far-future; out of scope.
- A separate "payouts" subaccount in MoneyMoney — out of scope; payouts surface as negatives in the single Giro account (D-51).
- Real TZ database for `bookingDate` — Phase 6+ if cross-locale support added; v1 stays on the D-36 hardcoded EU-DST table (now 2020-2050).
- DEBUG-level logging gated by a runtime toggle — out of scope per D27/D29 + SEC-04.
- Surfacing `ADJUSTMENT`, `CASHBACK`, `FROZEN_FUNDS`, `ADVANCE*`, `INVOICE_*`, `PAYMENT_PAYOUT`, `FAILED_PAYOUT` transaction types — Phase 5+ (Phase 4 filters to PAYMENT, PAYMENT_FEE, PAYOUT only).

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ACCT-03 | `balance` (settled) + `pendingBalance` (in-flight) from Finance API | Section 1.4 — separate `/v2/accounts/liquid/balance` and `/v2/accounts/preliminary/balance` endpoints; field name on each is `totalBalance` |
| SALE-07 | Card brand + entry-mode in `purpose` when API provides them | Section 6 — `payments[].attributes.cardType` + `cardPaymentEntryMode`; German label map with `_unknown` fallback |
| REF-01 | Each refund is one negative MoneyMoney transaction | Already shipped Phase 3 (D-32). Phase 4 only extends `purpose` lookup. |
| REF-02 | Refund `purpose` includes original sale's receipt number | Section 2 — `purchases_by_uuid` index in `entry.lua`; refund.refundsPurchaseUUID1 → purchase.purchaseNumber |
| REF-03 | Partial refunds handled — multiple refunds → same original | Section 2 — multiple refunds with distinct `purchaseUUID1` map to distinct refund transactions, all citing same `refundsPurchaseUUID1` |
| FEE-01 | Per-sale fee linkage via Finance `originatingTransactionUuid` | Section 3 — Finance `originatingTransactionUuid` → `payments[].uuid` (NOT `purchaseUUID1`); reverse index builds `payment_uuid → purchase` |
| FEE-02 | Fee `purpose` cites originating sale's receipt number | Section 3 — derived from index lookup |
| FEE-03 | Daily-aggregate fee fallback when linkage unavailable | Section 3 — `transactionCode = "zettle:fee:aggregate:YYYY-MM-DD"`; once-aggregated-always-aggregated invariant |
| PAYOUT-01 | Each payout = one negative MoneyMoney transaction | Section 4 — `originatorTransactionType = PAYOUT`, amount already negative in API |
| PAYOUT-02 | `name = "Auszahlung an Bankkonto"` | Section 4 — new i18n key `account.name.payout` |
| PAYOUT-03 | `bookingDate` = settlement date | Section 4 — `payout.timestamp` UTC → Berlin local via existing `_to_berlin_local_time` DST table (2020-2050) |
| META-01 | Per-rate VAT lines in `purpose` when `groupedVatAmounts` populated | Section 5 — keys are decimal-string rates `"19.0"`, `"7.0"`; values are minor-units VAT itself; emit one line per rate sorted descending |
| META-02 | Tip line when `gratuityAmount > 0` | Already shipped Phase 3 (D-34); Phase 4 promotes zero-suppression invariant to its own spec |
| META-03 | Never classify tax/VAT/GoBD/DATEV | Section 7 — 13-phrase forbidden-strings spec |
| TEST-02 | Recorded fixtures cover all permutations (sale, refund, fee, payout, VAT-split, tip, umlauts) | Section 8 — 9 new fixtures named explicitly |

</phase_requirements>

---

## Summary

Phase 4 is **not** a fresh integration — it's a precision layering of the Finance API on top of Phase 3's fully working Purchase API spine, with one new module (`src/finance.lua`), two new mapping functions (`fee_to_transaction`, `payout_to_transaction`, `fee_aggregate_to_transaction`), one new pagination iterator (`M_pagination.offset_iterate` — sibling, not modification), and one extension to `_format_purpose` (per-rate VAT lines + card-brand tail). The entry layer (`RefreshAccount`) gains two new fetch calls and an in-refresh cross-reference step that resolves refund originals, attaches per-sale fees, and promotes Phase-3 sales from `booked=false` to `booked=true + valueDate` when settlement is confirmed.

Three findings from this research materially affect the planner's task structure:

1. **The Finance API's link key is `payments[].uuid`, not `purchaseUUID1`.** The official docs (`fetch-purchase-information-for-transactions-v2.md`) state explicitly: *"The `originatingTransactionUuid` of a transaction in the Finance API corresponds to the `uuid` of `payments` in the Purchase API."* The `purchases_by_uuid` index name in CONTEXT D-50 is conceptually right but the index must be keyed by `payments[].uuid` (sweeping `payment.uuid` across every payment in every purchase), with each entry pointing back to its parent purchase. Refund lookup (REF-02) keys by `refundsPurchaseUUID1 → purchaseUUID1`; fee/payment lookup (FEE-01, D-56) keys by `originatingTransactionUuid → payments[].uuid → parent purchase`. Two distinct indexes are required.

2. **There is NO documented PAYOUT → PAYMENT link field.** The official enum description for `PAYOUT` is the only authoritative text: *"a payout can be positive or negative... if the account balance is paid out from the merchant's liquid account... the payout is negative"* — and that's the entire link contract. PAYOUT records carry their own `originatingTransactionUuid` (the payout's own UUID, observable in the doc examples) but do NOT enumerate the PAYMENTs they covered. D-56's settlement promotion must be inferred from temporal ordering: a PAYMENT is "settled by" the earliest PAYOUT whose timestamp is ≥ the PAYMENT's timestamp **and** which has not already settled an earlier PAYMENT. Phase 4 should ship a conservative inference (see Section 4) and document the limitation in README.

3. **The balance contract is two endpoints, not one.** CONTEXT D-52 implies a single `/v2/accounts/liquid` call returns `{balance, pendingBalance}`. The official spec has two separate endpoints: `GET /v2/accounts/liquid/balance` (settled balance for ACCT-03 `balance`) and `GET /v2/accounts/preliminary/balance` (in-flight for ACCT-03 `pendingBalance`). Each returns `{ data: { totalBalance, currencyId } }`. Phase 4's entry layer must issue both GETs (or only one if pendingBalance is omitted on a refresh with empty preliminary, which the doc does not guarantee). This is two more HTTP calls per refresh than D-52 implied — well within budget but worth noting in the per-refresh HTTP-call count comment.

**Primary recommendation:** Plan structure should be:
- **W0**: Yves Q3 probe (single live GET) + fixture matrix + RED gating specs (extended idempotency, META-03 forbidden-strings, schema-extension to cover new transaction kinds).
- **W1**: `M_pagination.offset_iterate` (sibling iterator) + `M_finance.parse_transaction` (pure-logic) + `M_mapping.fee_to_transaction` / `payout_to_transaction` / `fee_aggregate_to_transaction` (pure-logic mappers).
- **W2**: `M_finance.fetch` / `fetch_all` / `fetch_account_state` (HTTP-bound, reusing `M_http.get_json`) + `entry.lua` cross-reference indexes + SALE-03 promotion mutator.
- **W3**: `_format_purpose` extension (per-rate VAT + card tail) — pure additive to Phase-3 code.
- **W4**: META-03 invariant + extended idempotency spec (linkage-upgrade scenario) + Phase-3 surface preservation audit.
- **W5**: CHANGELOG + README v0.2.0 wording + i18n loop-lektor pass + final spec/luacheck/coverage sweep.

Six waves, 6–8 plan files. The Wave-0 RED-first discipline from Phase 3 (gating specs run RED against empty stubs before W1 fills them GREEN) carries over verbatim.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Finance API HTTP fetch (transactions + 2× balance) | `src/finance.lua` (M_finance) | `src/http.lua` (M_http.get_json) | Same separation as Phase-3 purchases.lua vs http.lua |
| Offset-based pagination | `src/pagination.lua` (M_pagination.offset_iterate) | `src/finance.lua` (consumer) | Sibling to Phase-3 `iterate`; independently testable |
| Finance record → transaction mapping | `src/mapping.lua` (extend) | `src/i18n.lua` (12 new keys) | Pure transformations; existing module owns this |
| Cross-refresh purchases_by_uuid + payments_by_uuid index | `src/entry.lua` (closure inside RefreshAccount) | — | Per-refresh-only state; no persistence boundary crossed |
| SALE-03 booked/valueDate promotion | `src/mapping.lua` (new `promote_to_booked` mutator) + `src/entry.lua` (orchestration) | — | Mutator is pure-logic; orchestration is per-refresh |
| Balance + pendingBalance fetch | `src/finance.lua` (`fetch_account_state`) | `src/entry.lua` (return-table assembly) | Two-endpoint fetch; entry assembles `{balance, pendingBalance, transactions}` |
| Per-rate VAT formatting | `src/mapping.lua` (`_format_purpose` extension) | `src/i18n.lua` (no new key — uses existing `account.purpose.vat`) | Additive to Phase-3 formatter |
| Card-brand + entry-mode tail | `src/mapping.lua` (`_format_purpose` extension) | `src/i18n.lua` (5 new entry-mode keys) | Same as VAT — pure additive |
| META-03 forbidden-strings invariant | `spec/meta_no_tax_classification_spec.lua` (new) | CI (egress-allowlist grep already exists, this is a new grep) | Spec-only enforcement per CONTEXT discretion |
| Egress allowlist update | `tests/repro_build_spec.lua` (or equivalent) + CI grep | — | Add `finance.izettle.com` predicated on Q3 PASS |

---

## Section 1: Finance API Surface

### 1.1 Base host

**`https://finance.izettle.com/v2`** — confirmed via the official OpenAPI 3.0 reference at `iZettle/api-documentation/finance-api/api-reference-v2.yaml` § `servers`:

```yaml
servers:
  - url: https://finance.izettle.com/v2
    description: Production
```

[VERIFIED: github.com/iZettle/api-documentation/blob/master/finance-api/api-reference-v2.yaml]

**Implication for D-46:** The Wave 0 probe is now a **confirmation step**, not an exploratory one. The probe asserts:
- HTTPS GET against `https://finance.izettle.com/v2/accounts/liquid/transactions?start=...&end=...&limit=1` returns 200.
- Authorization header with the existing Phase-2 Bearer is accepted (i.e., the user's key has `READ:FINANCE` scope — see R-1 below).
- Response body matches the documented `{ "data": [...] }` wrapper shape.

If any of those three fails, replan; otherwise lock D-46 and update ADR-0003 Q3 from DEFERRED → ACCEPTED with the recorded response body (redacted).

### 1.2 OAuth scope requirement (NEW RISK — Section 9 R-1)

The official `authorization.md` documents the scopes required: **`READ:FINANCE`** for Finance API, **`READ:PURCHASE`** for Purchase API. Phase 2's setup wording in README (Phase-6 release) must instruct users to issue their API key with **both** scopes:

> `https://my.zettle.com/apps/api-keys?name=<key-name>&scopes=READ:PURCHASE+READ:FINANCE`

[VERIFIED: github.com/iZettle/api-documentation/blob/master/authorization.md]

**Implication:** A Phase-3 user whose key was minted only with `READ:PURCHASE` will hit a 401 on the Finance API call. Phase 4's error mapping (which inherits Phase-2's `M_errors.from_http_status`) returns `LoginFailed` on 401, which prompts re-credentialing — the correct UX **but** the error message should ideally cite the missing scope. Phase 4 inherits Phase 2's generic `LoginFailed` (no scope-specific German string); README documentation must mention the dual-scope requirement explicitly. Track as new ADR-0004 (Wave 5 documentation task).

### 1.3 List account transactions

**Endpoint:** `GET /v2/accounts/{accountTypeGroup}/transactions` where `accountTypeGroup ∈ {liquid, preliminary}`.

For Phase 4, **`liquid` is the only account type read** (matches D-52: settled-and-pending; preliminary is for the balance endpoint only).

**Query parameters** [VERIFIED: api-reference-v2.yaml]:

| Param | Type | Required | Format / Range | Phase 4 usage |
|-------|------|----------|----------------|---------------|
| `start` | string | **YES** | `YYYY-MM-DDThh:mm:ss` UTC, inclusive (no `Z` suffix, no millis) | Set from `effective_since` (clamped POSIX) via `os.date("!%Y-%m-%dT%H:%M:%S", effective_since)` |
| `end` | string | **YES** | `YYYY-MM-DDThh:mm:ss` UTC, exclusive | Set from `os.date("!%Y-%m-%dT%H:%M:%S", os.time() + 60)` (small future buffer so a transaction created during the refresh isn't missed) |
| `limit` | integer | NO | default 10000, no documented upper | Use `limit=1000` (conservative; matches D-13's purchase limit family, comfortably under default) |
| `offset` | integer | NO | default 0, ≥ 0 | Increments by `limit` per page |
| `includeTransactionType` | array | NO | repeatable; enum below | Three params: `PAYMENT`, `PAYMENT_FEE`, `PAYOUT` |

**Critical difference from Purchase API:** `start` and `end` are **required**. Phase 3's purchase fetch could omit `startDate`; Phase 4's finance fetch CANNOT omit `start`/`end`. The URL builder must always include both.

**Date format gotcha:** Finance API uses `YYYY-MM-DDThh:mm:ss` (no `Z`, no millis, UTC implicit) per the OpenAPI spec. Phase 3's purchase fetch uses `YYYY-MM-DDTHH:MM:SSZ` (with `Z`). Two different `_iso8601_*` helpers, or one that accepts a `with_z` flag — planner's call.

**Full `originatorTransactionType` enum** [VERIFIED: api-reference-v2.yaml]:

```
ADJUSTMENT, ADVANCE, ADVANCE_DOWNPAYMENT, ADVANCE_FEE_DOWNPAYMENT,
CASHBACK, FAILED_PAYOUT, FROZEN_FUNDS, INVOICE_PAYMENT, INVOICE_PAYMENT_FEE,
PAYMENT, PAYMENT_FEE, PAYMENT_PAYOUT, PAYOUT
```

Phase 4 filters to **PAYMENT, PAYMENT_FEE, PAYOUT** only via `includeTransactionType=` query repetition. All other types are **ignored** by Phase 4 — they are out of scope. A future Phase 5/6 may add CASHBACK / ADJUSTMENT / FROZEN_FUNDS surfacing.

**Note on `CARD_REFUND`:** the older `fetch-purchase-information-for-transactions-v2.md` mentions `CARD_REFUND` as a transaction type, but it is **not** in the OpenAPI enum. Refunds are surfaced as PAYMENT records with a **negative** `amount` (the OpenAPI description for PAYMENT confirms: *"In the case of a refund, a transaction of the same type will occur but with the inverted amount"*). Phase 4 does NOT need to filter for `CARD_REFUND`; negative PAYMENTs are already covered.

### 1.4 Account balance — TWO endpoints

[VERIFIED: github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-account-balance-v2.md]

**Settled balance (ACCT-03 `balance`):**
```
GET /v2/accounts/liquid/balance
```

**Pending balance (ACCT-03 `pendingBalance`):**
```
GET /v2/accounts/preliminary/balance
```

**Response shape (same for both):**
```json
{
  "data": {
    "totalBalance": 100,
    "currencyId": "GBP"
  }
}
```

Field semantics:
- `totalBalance` — integer, currency's smallest unit (cents for EUR). Can be negative if refunds exceed sales.
- `currencyId` — ISO 4217 string (e.g., `"EUR"`).

**Phase 4 mapping:**
- `RefreshAccount` return-table `balance` ← `liquid.totalBalance / 100`
- `RefreshAccount` return-table `pendingBalance` ← `preliminary.totalBalance / 100`
- **Currency guard:** if either `currencyId != "EUR"`, fall back to `account.balance` (Phase-3 behavior) and INFO-log. Consistent with D-37 currency invariant.

Two HTTP calls per refresh for balance. Add to the per-refresh HTTP-call budget tracking.

### 1.5 Payout info (informational — not needed for Phase 4 core)

`GET /v2/payout-info?at={timestamp}` returns `{ totalBalance, currencyId, nextPayoutAmount, discountRemaining, periodicity }` [VERIFIED: fetch-payout-info-v2.md]. Phase 4 does NOT consume this endpoint — settlement detection is done via the transactions endpoint (PAYOUT records). The payout-info endpoint is reserved for a future "Next payout: €X on date Y" UI affordance (Phase 5/6).

### 1.6 Response structure

**Transactions response:**
```json
{
  "data": [
    {
      "timestamp": "2020-07-04T20:16:44.309+0000",
      "amount": 381,
      "originatorTransactionType": "PAYMENT_FEE",
      "originatingTransactionUuid": "30cef6e2-be09-11ea-a8e4-bce028663c34"
    },
    ...
  ]
}
```

[VERIFIED: fetch-account-transactions-v2.md doc examples]

Key fields per transaction:
- `timestamp` — ISO 8601 with millis + offset (e.g., `2020-07-04T20:16:44.309+0000`). Phase-3 `_parse_iso8601_utc` already handles `.SSS` + `+0000` + `Z` suffixes; **reuse byte-identically.**
- `amount` — integer minor units, **signed**. PAYMENT = positive on sale, negative on refund; PAYMENT_FEE = negative on sale (debit), positive on refund (rebate); PAYOUT = negative (money leaves liquid account).
- `originatorTransactionType` — string, from the enum above.
- `originatingTransactionUuid` — UUID v1 string. **On PAYMENT/PAYMENT_FEE: this is the `payments[].uuid` of the corresponding payment leg in the Purchase API, NOT `purchaseUUID1`.** On PAYOUT: this is the payout's own UUID. Doc examples confirm both (a PAYMENT/PAYMENT_FEE pair shares the same `originatingTransactionUuid` because they refer to the same payment leg).

**No pagination cursor / no totals / no `lastPurchaseHash`.** Termination is "response empty OR shorter than limit" (the offset-iterator's standard signal).

[VERIFIED: fetch-account-transactions-v2.md step 3 — *"Repeat step 2 until the response is empty or it contains fewer transactions than the limit"*]

### 1.7 Status code handling (inherits Phase 2)

Phase 4 routes every Finance API response through Phase 2's `M_errors.from_http_status(status, raw)`:

| Status | Phase 4 behavior |
|--------|------------------|
| 200 | Process `data` array |
| 400 / 401 / 403 | `LoginFailed` (Phase 5 may add scope-specific message) |
| 429 | German `error.rate_limit` (Phase 5 adds retry) |
| 5xx | German `error.network` with status code |
| nil (network) | German `error.network` |

No new error cases in Phase 4. Retry/backoff is Phase 5.

---

## Section 2: Refund original-sale lookup (REF-02 / D-50)

### 2.1 The index contract

The Phase-3 `_format_purpose(p, {kind = "refund"})` already cites `refundsPurchaseUUID1` when no `original_receipt` opts is passed. Phase 4 adds an `original_receipt` value to the `opts` table by looking up the original sale from a same-refresh index.

**Index shape** (built in `entry.lua` after `M_purchases.fetch_all` returns):

```lua
-- D-50: purchases_by_uuid index for refund original-sale lookup (REF-02).
-- Key: purchase.purchaseUUID1 (string)
-- Value: purchase record table
local purchases_by_uuid = {}
for _, p in ipairs(all_purchases or {}) do
  if type(p) == "table" and type(p.purchaseUUID1) == "string" and #p.purchaseUUID1 > 0 then
    purchases_by_uuid[p.purchaseUUID1] = p
  end
end
```

### 2.2 Lookup at refund-mapping time

```lua
-- D-50: when mapping a refund, look up the original sale's purchaseNumber.
local original_receipt = nil  -- nil triggers Phase-3 UUID fallback per D-32
if type(p.refundsPurchaseUUID1) == "string" and #p.refundsPurchaseUUID1 > 0 then
  local original = purchases_by_uuid[p.refundsPurchaseUUID1]
  if original and original.purchaseNumber then
    original_receipt = original.purchaseNumber
  end
end
local txn = M_mapping.refund_to_transaction(p, { original_receipt = original_receipt })
```

The mapper signature gains a second parameter `opts` (existing `opts` in `_format_purpose` already supports `original_receipt`; just plumb it through `M_mapping.refund_to_transaction`'s call site). **Backwards compatible:** existing Phase-3 callers passing only `p` still work because `opts` defaults to `nil`.

### 2.3 Edge cases (research-confirmed)

| Edge case | Behavior | Source |
|-----------|----------|--------|
| Refund in window, original in window | Cite `purchaseNumber` (REF-02 satisfied) | Index hit |
| Refund in window, original OUTSIDE 90-day window | Fall back to UUID display per Phase-3 D-32 | Index miss → `original_receipt = nil` |
| Refund record has `refundsPurchaseUUID1 = nil` (rare; non-refund record marked refund) | `_format_purpose` already handles `ref = nil` defensively (line 195 of mapping.lua) — emits empty placeholder | Phase 3 code |
| Multiple refunds for same original (REF-03) | Each refund has distinct `purchaseUUID1` → distinct refund transactionCode → each carries the same `original_receipt` citation | Phase 3 D-32 already supports |
| `refundsPurchaseUUID1` as array (hypothetical) | NOT documented; Zettle's `purchase.adoc` defines it as a single string. Treat as string only; if Zettle ever returns an array, `_format_purpose` would `tostring()` it producing `"table: 0x..."` — guard with `type(ref) == "string"` check in Wave 4 hardening. | [CITED: purchase.adoc field definitions] |
| `refundedByPurchaseUUIDs1` (array on original sale, listing refund UUIDs) | NOT used in Phase 4. Phase 4 only walks refunds-to-originals direction, not originals-to-refunds. | [CITED: purchase.adoc] |

[VERIFIED: github.com/iZettle/api-documentation/blob/master/purchase.adoc — `refundsPurchaseUUID1` documented as string, `refundedByPurchaseUUIDs1` as array]

### 2.4 Concrete spec example

```lua
it("REF-02: refund purpose cites original purchaseNumber when original in window", function()
  -- Arrange: page with original (purchaseNumber=1001) and its refund
  local raw = Fixtures.load("purchases/purchase_refund_with_original_in_page")
  Mocks.push_response({ content = raw })
  -- ... seed token, call RefreshAccount ...
  local result = RefreshAccount(account, 0)
  local refund_txn = find_by_prefix(result.transactions, "zettle:refund:")
  assert.is_not_nil(refund_txn:find("zu Beleg #1001", 1, true),
    "refund purpose must cite original purchaseNumber 1001")
end)
```

---

## Section 3: Fee linkage cardinality (FEE-01..03 / D-49)

### 3.1 The link key correction

CONTEXT D-49 says "`originatingTransactionUuid` that resolves to a Purchase API `purchaseUUID1`". This is **wrong** — `originatingTransactionUuid` resolves to `payments[].uuid`, NOT `purchaseUUID1`. Source [VERIFIED]:

> *"The `originatingTransactionUuid` of a transaction in the Finance API corresponds to the `uuid` of `payments` in the Purchase API."*

— from `iZettle/api-documentation/finance-api/user-guides/fetch-purchase-information-for-transactions-v2.md`, the canonical doc on how the two APIs join.

**This means a second index is required**, distinct from the refund index:

```lua
-- D-49 / FEE-01: payments_by_uuid index for fee linkage.
-- Key: payments[].uuid (string) — for EVERY payment leg of EVERY purchase
-- Value: parent purchase record table (so we can read its purchaseNumber)
local payments_by_uuid = {}
for _, purchase in ipairs(all_purchases or {}) do
  if type(purchase) == "table" and type(purchase.payments) == "table" then
    for _, payment in ipairs(purchase.payments) do
      if type(payment) == "table"
          and type(payment.uuid) == "string"
          and #payment.uuid > 0 then
        payments_by_uuid[payment.uuid] = purchase
      end
    end
  end
end
```

The fee linkage flow:
```
PAYMENT_FEE.originatingTransactionUuid
  → payments_by_uuid[uuid]
  → parent purchase
  → purchase.purchaseNumber  -- for FEE-02 purpose line
```

### 3.2 Cardinality findings (from official examples)

[VERIFIED: doc examples in fetch-account-transactions-v2.md] — every PAYMENT row in the official examples is paired with exactly one PAYMENT_FEE row carrying the SAME `originatingTransactionUuid`. The pattern is:

```json
{ "timestamp": "T1", "amount": -8867, "type": "PAYMENT_FEE", "originatingTransactionUuid": "UUID-A" }
{ "timestamp": "T1", "amount": 479300, "type": "PAYMENT",     "originatingTransactionUuid": "UUID-A" }
```

So:
- **1 PAYMENT_FEE ↔ 1 PAYMENT** (one-to-one) — confirmed in 3 separate doc examples (lines 36-100 of fetch-account-transactions-v2.md).
- Both share the same `originatingTransactionUuid` (which IS the payment leg's uuid).
- Both share the same `timestamp` (typically — the doc examples are seconds apart only on rebooked transactions).

### 3.3 When does `originatingTransactionUuid` go missing on a PAYMENT_FEE?

**Honest research finding: the docs do NOT enumerate failure modes for the link field.** Every example shows it populated. The OpenAPI schema does not mark it `required`. The CONTEXT D-49 fallback path is a defensive measure for hypothetical edge cases:

| Hypothesis | Doc support | Phase 4 stance |
|------------|-------------|----------------|
| Payment leg `uuid` was nil on the Purchase API side, so Finance has nothing to link to | Possible but undocumented; Phase 3's mapping.lua already guards `purchaseUUID1` nil-check — same risk class | Aggregate-fallback path covers this case |
| Fee is for an INVOICE_PAYMENT or PAYMENT_PAYOUT (out of Phase 4 filter) | Phase 4 already filters to PAYMENT/PAYMENT_FEE/PAYOUT only; non-matching types never reach the mapper | N/A |
| Fee row arrives BEFORE its corresponding PAYMENT on a paginated split | Possible if pagination crosses the natural pair boundary | Both PAYMENT + PAYMENT_FEE arrive in the SAME response page or across consecutive pages — the index is built AFTER all pages are fetched, so order doesn't matter |
| Bulk-corrected historical fees with no link | Speculative | Aggregate fallback handles this |
| Chargeback/dispute reversal fees | Speculative — `FROZEN_FUNDS` type exists but isn't a fee | Out of Phase-4 filter |

**Recommended Phase-4 measurement:** Wave 5 adds a TRACE log line counting `(fees_linked, fees_aggregated)` per refresh. Real users' logs after v0.2.0 release will tell us the empirical fallback rate; Phase 5/6 can revisit the aggregate threshold if real-world linkage failure is unexpectedly high. Until then, **assume linkage failures are rare** and the fallback path is a safety net.

### 3.4 Mapper signatures (Wave 1)

```lua
-- M_mapping.fee_to_transaction(fee_record, originating_sale)
--   fee_record: { kind="PAYMENT_FEE", amount, timestamp, originatingTransactionUuid }
--   originating_sale: purchase record (from payments_by_uuid lookup)
--   Returns: MoneyMoney transaction table
--   transactionCode = "zettle:fee:" .. fee_record.originatingTransactionUuid
--                     (NOTE: NOT fee.uuid because the Finance API record has no `uuid` field;
--                      the only stable identifier is the originatingTransactionUuid,
--                      which is unique per payment leg.)
--   amount         = fee_record.amount / 100  (signed; negative on sale, positive on refund)
--   bookingDate    = Berlin local from fee_record.timestamp
--   name           = M_i18n.t("account.name.fee")  -- "Gebühr"
--   purpose        = "Gebühr für Beleg #<purchaseNumber>\nBetrag: <amount> EUR"
--   booked         = true   -- finance records are settled by definition (liquid account)
```

**Subtle finding on `transactionCode`:** the Finance API transactions have NO `uuid` field of their own — only `originatingTransactionUuid`. So `transactionCode = "zettle:fee:" .. originatingTransactionUuid` is the only stable code. **This is safe**: per-payment one-to-one fee mapping means `originatingTransactionUuid` is unique per fee. Add an idempotency assertion to the gating spec.

```lua
-- M_mapping.fee_aggregate_to_transaction(fees_for_date, date_iso, count)
--   fees_for_date: array of fee_record (all on same Berlin-local date)
--   date_iso: string "YYYY-MM-DD" (Berlin local)
--   count: integer (length of fees_for_date; passed explicitly for purpose text)
--   Returns: MoneyMoney transaction table
--   transactionCode = "zettle:fee:aggregate:" .. date_iso
--   amount         = sum(fees_for_date.amount) / 100
--   bookingDate    = parsed from date_iso (Berlin local POSIX)
--   name           = M_i18n.t("account.name.fee_aggregate")  -- "PayPal POS Transaktionsgebühren"
--   purpose        = M_i18n.t("account.purpose.fee_aggregate", count)
--                  = "Tagesaggregat — N Einzelgebühren — Detail-Verknüpfung nicht verfügbar"
--   booked         = true
```

```lua
-- M_mapping.payout_to_transaction(payout_record)
--   payout_record: { kind="PAYOUT", amount, timestamp, originatingTransactionUuid }
--   Returns: MoneyMoney transaction table
--   transactionCode = "zettle:payout:" .. payout_record.originatingTransactionUuid
--                     (PAYOUT carries its OWN UUID as originatingTransactionUuid per
--                      the doc examples — d8550d7a-f347-11ea-9612-3bce5300b9a9 etc.)
--   amount         = payout_record.amount / 100  (already negative in API)
--   bookingDate    = Berlin local from payout_record.timestamp
--   name           = M_i18n.t("account.name.payout")  -- "Auszahlung an Bankkonto"
--   purpose        = "Auszahlung an Bankkonto am <Berlin-date>\nBetrag: <amount> EUR"
--   booked         = true
--   valueDate      = bookingDate  -- payout itself IS the settlement event
```

### 3.5 Aggregate dedup contract (D-49 idempotency)

The "once aggregated, always aggregated" invariant means:

```
Refresh N:   fee F1 unlinked → aggregated into zettle:fee:aggregate:2026-06-15
Refresh N+1: fee F1 now linked (Zettle back-filled the link)
             → If we emit zettle:fee:UUID-F1 row, MoneyMoney creates a NEW row
               AND the aggregate row from refresh N still exists
               → double-booking of F1
             → SOLUTION: aggregate dedup is BY DATE, not by individual fee.
               Once an aggregate transactionCode exists for a date, ALL fees
               on that date go into the aggregate, even if linked.
```

**The dedup mechanism** in `entry.lua` is **at refresh time, not persistent**:

```lua
-- Cluster fees by Berlin-local date BEFORE checking linkage.
-- Then for each date:
--   if ANY fee on that date is unlinked → aggregate ALL fees on that date.
--   if ALL fees on that date are linked → emit per-sale fee rows.
-- This makes the per-refresh decision local — no cross-refresh state needed.
-- The transactionCode of an aggregate row encodes only the date, so it's
-- stable across refreshes IF the same date's fee set continues to have at
-- least one unlinked fee. If the date's fee set becomes fully linked LATER,
-- the per-sale rows we emit then DO get new transactionCodes — but MoneyMoney
-- still has the old aggregate row from prior refreshes, so we DOUBLE-BOOK.
```

**This is the actual edge case** Yves needs to sign off on. Two pragmatic options:

**Option A (CONTEXT-recommended):** Once aggregate exists, always aggregate. Implementation requires persistent state (`LocalStorage.fees_aggregated_dates`) so refresh N+5 knows refresh N already aggregated 2026-06-15. **This contradicts D-59 (no extension-owned state file).**

**Option B (research-recommended for v0.2.0):** Cluster by date per-refresh. If any fee on a date is unlinked, aggregate ALL fees for that date in this refresh. If a later refresh sees the same date fully linked, emit per-sale rows. **Risk: a single date can be aggregate-on-day-1 and per-sale-on-day-2, double-booking.** But: if the 90-day clamp window covers the date, both old aggregate and new per-sale rows are visible — and dedup is broken anyway.

**Recommended planner action:** Either ship Option A with an explicit `LocalStorage.zettle.fees_aggregated` set (mark D-59 as Phase-4-amended to allow this minimal state) OR ship Option B with a release-note warning that fee linkage stability is a Zettle-side guarantee; if linkage flips unexpectedly, edit the affected aggregate row in MoneyMoney manually. **This is a Yves call** — it's D-49's open Pay/Compliance question made concrete.

**My recommendation (autonomous-window, not locked):** ship Option B for v0.2.0 with a release-note disclaimer ("fee linkage is assumed stable; if a date's fees switch from aggregated to per-sale, edit the duplicate aggregate row manually in MoneyMoney"). Revisit in Phase 5 if real users hit it. The state-file path is more correct but it's a permanent persistence surface that's hard to remove later — better to defer until measured.

---

## Section 4: SALE-03 closure — payout matching (D-56)

### 4.1 The research conclusion

**Zettle does NOT publish a documented payout-to-payment link.** The only authoritative description of how PAYOUT relates to PAYMENT is the OpenAPI enum description:

> *"PAYOUT — A payout can be positive or negative. If the account balance is paid out from the merchant's liquid account to the merchant's bank account or to PayPal Wallet for PayPal users, the payout is negative."*

[VERIFIED: api-reference-v2.yaml]

No field enumerates "this payout covered payments X, Y, Z". The Finance API's design is single-account-ledger: PAYMENTs add to liquid balance, PAYOUTs subtract from it, and the SUM at any time = `liquid.totalBalance`. The merchant's bookkeeper reconciles by date-range matching, not by explicit linkage.

### 4.2 Settlement inference for D-56

Phase 4's goal: re-emit a Phase-3 sale with `booked=true` and `valueDate=settlement_date`. The most defensible inference rule:

```
A PAYMENT is "settled" by the earliest PAYOUT in the current Finance result set
such that PAYOUT.timestamp >= PAYMENT.timestamp AND PAYOUT.timestamp <= now.

If no such PAYOUT exists in the result set, the PAYMENT is NOT promoted
(stays booked=false from Phase 3).
```

**Why this is safe:**
- PAYOUTs are explicitly settlement events ("paid out to the merchant's bank account").
- All PAYMENTs that occurred before a PAYOUT timestamp are by definition part of that liquid-account balance (otherwise the PAYOUT amount wouldn't include them).
- The inference is conservative: a PAYMENT made today, with no PAYOUT yet visible, stays `booked=false` until a future refresh sees the PAYOUT. **No false positives.**

**Limitations to document in README:**
- For merchants with `periodicity=DAILY` payouts (common in Germany), the inference is accurate to the day.
- For merchants with `periodicity=WEEKLY` or `MONTHLY`, a sale promoted to `booked=true` may technically settle later in the week — but the **payout** is what hits the bank account, and that's the settlement event our extension models.
- Inference assumes all payments before a payout are covered. If Zettle has a `FROZEN_FUNDS` or `ADJUSTMENT` carve-out between PAYMENT and PAYOUT, the carve-out's amount is reflected in the liquid balance but NOT in our promotion logic. **Acceptable for v0.2.0** — out-of-band frozen funds are a rare edge case for German POS merchants; READ:FINANCE shows them but we don't surface them in Phase 4.

### 4.3 Implementation (W2 task)

```lua
-- After fetching all_finance_records and building payments_by_uuid:
-- 1. Split finance records by type.
local fin_payments = {}  -- list of PAYMENT records
local fin_fees     = {}  -- list of PAYMENT_FEE records
local fin_payouts  = {}  -- list of PAYOUT records, sorted ascending by timestamp
for _, r in ipairs(finance_records) do
  if r.originatorTransactionType == "PAYMENT"     then table.insert(fin_payments, r)
  elseif r.originatorTransactionType == "PAYMENT_FEE" then table.insert(fin_fees,     r)
  elseif r.originatorTransactionType == "PAYOUT"      then table.insert(fin_payouts,  r)
  end
end
table.sort(fin_payouts, function(a, b) return a.timestamp_posix < b.timestamp_posix end)

-- 2. For each PAYMENT, find earliest PAYOUT >= payment.timestamp.
local function find_covering_payout(payment_ts_posix)
  for _, po in ipairs(fin_payouts) do
    if po.timestamp_posix >= payment_ts_posix then return po end
  end
  return nil
end

-- 3. For each sale we mapped in step 5 of RefreshAccount, look up the matching
--    PAYMENT via payments_by_uuid (reverse: purchase.payments[].uuid → finance PAYMENT
--    with matching originatingTransactionUuid). If matched AND covered → promote.
for _, sale_txn in ipairs(sale_transactions) do
  local purchase = sale_to_purchase_back_ref[sale_txn]  -- captured at map time
  if purchase and type(purchase.payments) == "table" then
    for _, pmt in ipairs(purchase.payments) do
      local fin_payment = fin_payments_by_uuid[pmt.uuid]
      if fin_payment then
        local covering = find_covering_payout(fin_payment.timestamp_posix)
        if covering then
          M_mapping.promote_to_booked(sale_txn, covering.timestamp_posix)
          break  -- one matching payment is enough; further legs would re-promote to same date
        end
      end
    end
  end
end
```

### 4.4 New mapper function

```lua
-- M_mapping.promote_to_booked(txn, valueDate_posix_local)
--   Mutates txn in place: sets booked=true, valueDate=valueDate_posix_local.
--   transactionCode UNCHANGED — MoneyMoney's dedup updates the row.
--   Idempotent: calling twice with same valueDate is a no-op.
function M_mapping.promote_to_booked(txn, valueDate_posix_local)
  if type(txn) ~= "table" then return end
  txn.booked    = true
  txn.valueDate = valueDate_posix_local
end
```

Pure-logic. Easily unit-tested.

### 4.5 Idempotency gating extension (D-58 sub-case)

Spec sequence:
- Refresh 1: 1 purchase + 0 finance records → 1 sale txn `booked=false`, no valueDate.
- Refresh 2: same purchase + 1 PAYMENT + 1 PAYOUT (later timestamp) → 1 sale txn `booked=true`, valueDate=PAYOUT.timestamp_local.
- Assert: `transactionCode` is **byte-identical** in both refreshes; `booked` and `valueDate` differ.

This validates MoneyMoney's update-in-place dedup contract. Documented behavior, but the extended idempotency spec gates it.

---

## Section 5: Per-rate VAT (META-01 / D-53)

### 5.1 Confirmed shape

[VERIFIED: purchase.adoc line 1112-1118 + purchase example responses]

```json
"groupedVatAmounts": {
  "25.0": 70000,
  "12.0": 5000
}
```

- **Keys**: decimal strings, one decimal place precision (`"19.0"`, `"7.0"`, `"0.0"`). NOT integers, NOT fractions.
- **Values**: integer minor units representing the VAT amount itself at that rate (NOT the net portion). Sum of values = `vatAmount` top-level (to the cent).
- **Refund records**: values are negative (`"12.0": -10000` in the doc's refund example).
- **Absent map**: `groupedVatAmounts: {}` is empty for purchases with no VAT (e.g., the existing fixture `purchase_with_card_metadata.json`). Existing fixture `purchase_with_vat_and_tip.json` has `{"19": 318}` — note the **integer key** instead of `"19.0"` decimal-string. **This is a fixture bug** — Phase 4 spec must accept both because real API uses decimal strings, but our fixture uses integer-string. Plan 04-04 should regenerate that fixture to match real-world format.

### 5.2 META-01 rendering rule (per D-53)

```lua
-- Extend _format_purpose: when groupedVatAmounts has >= 2 keys, emit one line
-- per rate, sorted DESCENDING by numeric rate. Fall through to Phase-3 single
-- vatAmount line when 0 or 1 keys.
local function _format_vat_lines(p)
  local gva = type(p.groupedVatAmounts) == "table" and p.groupedVatAmounts or {}
  -- Count entries
  local entries = {}
  for k, v in pairs(gva) do
    local rate_num = tonumber(k)
    if rate_num and type(v) == "number" then
      table.insert(entries, { rate = rate_num, amount = v, label = k })
    end
  end
  if #entries < 2 then
    -- Single (or zero) rate: fall through to Phase-3 vatAmount line via caller
    return nil
  end
  -- Sort descending by rate
  table.sort(entries, function(a, b) return a.rate > b.rate end)
  local lines = {}
  for _, e in ipairs(entries) do
    -- Format: "19% MwSt: 3,83 EUR"  (drop the ".0" from "19.0" for display)
    local rate_display = e.rate == math.floor(e.rate)
                         and string.format("%d", e.rate)
                         or  string.format("%g", e.rate)
    table.insert(lines, string.format(
      "%s%% MwSt: %s EUR",
      rate_display,
      _format_amount(e.amount)
    ))
  end
  return table.concat(lines, "\n")
end
```

**Display formatting:** `"19.0"` → `"19% MwSt: ..."` (drop the `.0`). `"7.5"` → `"7.5% MwSt: ..."` (preserve fractional rate). Use `e.rate == math.floor(e.rate)` to distinguish whole-number rates.

### 5.3 META-01 edge cases

| Case | Behavior |
|------|----------|
| `groupedVatAmounts` empty `{}` | Fall through to Phase-3 single `MwSt: <vatAmount>` line (only if `vatAmount > 0`) |
| Single rate (`{"19.0": 318}`) | Fall through to Phase-3 single line — visually identical to multi-rate path's single line; no reason to fork |
| 0% rate present (`{"0.0": 0, "19.0": 318}`) | Display `"0% MwSt: 0,00 EUR"` line. **Yves question:** is this noisy? Recommendation: show it because the merchant's invoice itemized it; suppressing would be a silent assumption about merchant intent. Suppress only when value is `0` AND no other VAT lines exist. |
| Reconciliation: `sum(values) ≠ vatAmount` | Trust `groupedVatAmounts`; this would be a Zettle bug. Add a WARNING log if the sum doesn't match `vatAmount` to the cent. |
| Refund with negative amounts (`{"19.0": -57}`) | Display as `"19% MwSt: -0,57 EUR"` — negative renders naturally via `_format_amount` |
| Integer-string keys (`{"19": 318}` — non-spec, but our fixture uses this) | `tonumber("19")` returns `19` — works identically. Accept both. |

### 5.4 Sort stability

Lua's `table.sort` is **not stable** for equal keys. If two rates compare equal (impossible for distinct VAT rates, but possible due to floating-point), insertion order is undefined. Not a concern for valid German VAT rates (0%, 7%, 19%), all distinct.

---

## Section 6: Card brand + entry mode (SALE-07 / D-57)

### 6.1 Confirmed field shapes

[VERIFIED: purchase.adoc Payment_types section]

```json
"attributes": {
  "cardType": "MASTERCARD",
  "maskedPan": "535583******0000",
  "cardPaymentEntryMode": "CONTACTLESS_EMV",
  "referenceNumber": "B6MFKZTMKP",
  "authorizationCode": "429579",
  ...
}
```

- `cardType` enum (confirmed): `VISA`, `MASTERCARD`, `AMEX`, `MAESTRO`, `GIROCARD`, `UNIONPAY`. Already mapped in Phase 3 `BRAND_MAP`.
- `cardPaymentEntryMode` known values (confirmed by docs): `CONTACTLESS_EMV`, `ICC`, `ECOMMERCE`. [ASSUMED] additional: `MSR` (magnetic stripe — industry standard term; not in doc examples but commonly seen in card-acquirer APIs).

### 6.2 German label mapping (NEW i18n keys per D-57)

| API value | German | i18n key |
|-----------|--------|----------|
| `CONTACTLESS_EMV` | `kontaktlos` | `account.purpose.payment_method.kontaktlos` |
| `ICC` | `Chip` | `account.purpose.payment_method.chip` |
| `MSR` [ASSUMED] | `Magnetstreifen` | `account.purpose.payment_method.magstripe` |
| `ECOMMERCE` | `Online` | `account.purpose.payment_method.ecommerce` |
| `MANUAL` [ASSUMED] | `Manuell` | `account.purpose.payment_method.manual` |
| (any other) | `unbekannt` | `account.purpose.payment_method.unknown` |

The `_unknown` fallback is critical — Zettle may add new values in the future. Skip the tail line entirely when both `cardType` AND `cardPaymentEntryMode` are absent (avoids `"Zahlart: unbekannt (unbekannt)"` noise).

### 6.3 Rendering format

Per CONTEXT D-57 + Claude's-Discretion recommendation:

```
Brutto: 19,95 €
MwSt: 3,18 €
Trinkgeld: 1,00 €
Netto: 15,77 €
Zahlart: Visa (kontaktlos)
Beleg #1002
```

- Tail line **separate** (above `Beleg #` footer) — easier to grep visually.
- Format: `"Zahlart: <cardType_display> (<entry_mode_de>)"`.
- Inserted in `_format_purpose` after the Netto line, before the receipt-number line.
- Suppressed when **both** `cardType` and `cardPaymentEntryMode` are absent or empty.
- Partial: if `cardType` present but `cardPaymentEntryMode` absent → `"Zahlart: Visa"` (no parens). Symmetric: cardType absent + entry-mode present → `"Zahlart: Kartenzahlung (kontaktlos)"` (fallback brand label).

### 6.4 New i18n key for the tail line

```lua
["account.purpose.payment_method_line"] = "Zahlart: %s"           -- when only brand or only mode
["account.purpose.payment_method_full"] = "Zahlart: %s (%s)"      -- when both present
```

Plus the 5 mode-label keys above.

---

## Section 7: META-03 forbidden-strings invariant (D-55)

### 7.1 The 13 phrases (CONTEXT D-55)

```
"USt-frei", "USt frei",
"steuerfrei", "steuerlich",
"GoBD-konform", "GoBD konform",
"DATEV-fähig", "DATEV fähig",
"VAT-exempt", "VAT exempt",
"tax-free", "tax exempt", "non-taxable"
```

### 7.2 Spec implementation pattern

Analog to Phase-3 `spec/log_redaction_spec.lua` walk-pattern:

```lua
local FORBIDDEN = {
  "USt-frei", "USt frei", "steuerfrei", "steuerlich",
  "GoBD-konform", "GoBD konform", "DATEV-fähig", "DATEV fähig",
  "VAT-exempt", "VAT exempt", "tax-free", "tax exempt", "non-taxable",
}

local function scan_file(path)
  local f = assert(io.open(path, "r"))
  local content = f:read("*a")
  f:close()
  for _, phrase in ipairs(FORBIDDEN) do
    -- Plain find (4th arg true) to avoid Lua pattern escape complications
    local idx = content:find(phrase, 1, true)
    assert.is_nil(idx, path .. " contains forbidden META-03 phrase: " .. phrase)
  end
end

describe("META-03 forbidden tax-classification phrases", function()
  it("none of src/*.lua contains a forbidden phrase", function()
    local handle = assert(io.popen("ls src/*.lua"))
    for line in handle:lines() do scan_file(line) end
    handle:close()
  end)

  it("dist/paypal-pos.lua contains no forbidden phrase", function()
    -- Build first so artifact exists
    assert(os.execute("lua tools/build.lua") == true)
    scan_file("dist/paypal-pos.lua")
  end)
end)
```

### 7.3 Boundary considerations

- **i18n keys** containing the literal forbidden phrase (e.g., a hypothetical `error.gobd_conform`) would also fail the spec. Good — that's the point.
- **Comments** in `src/*.lua` also fail. Good — even discussing "GoBD-konform" in a code comment risks future contributors lifting the phrase into user-facing text.
- **README / docs / ADRs** are NOT scanned (they intentionally discuss what we DON'T claim). Only `src/` and the built artifact.
- **PR descriptions / commit messages** are not scanned (out of CI grep scope).

### 7.4 What we ARE allowed to say

Implicit (any phrase not on the forbidden list): `Brutto`, `Netto`, `MwSt`, `USt` (alone, without `-frei`), `Trinkgeld`, `Beleg`, `Gebühr`, `Auszahlung`, `Rückerstattung`, `Bankkonto`, `Kartenzahlung`, `Visa`, `Mastercard`, etc.

The list is **negative-list** by design — anything not forbidden is allowed. This puts the maintainer in control of intent.

---

## Section 8: TEST-02 fixture matrix

### 8.1 Existing Phase-3 fixtures (don't touch)

```
spec/fixtures/purchases/
├── purchase_dst_boundary_summer.json
├── purchase_dst_boundary_winter.json
├── purchase_non_eur.json
├── purchase_page1.json
├── purchase_page2.json
├── purchase_refund.json
├── purchase_simple_sale.json
├── purchase_with_card_metadata.json     ← entry mode ICC, no cardType variety
├── purchase_with_vat_and_tip.json       ← single VAT rate "19" (integer-string key — bug)
└── purchases_empty.json
```

### 8.2 New Phase-4 fixtures

```
spec/fixtures/finance/
├── finance_empty.json                       ← {"data": []}
├── finance_single_page.json                 ← 1 PAYMENT + 1 PAYMENT_FEE + 1 PAYOUT
├── finance_multi_page_1.json                ← exactly `limit` records → triggers offset++
├── finance_multi_page_2.json                ← partial page → terminates loop
├── finance_payment_with_fee_linkage.json    ← PAYMENT + PAYMENT_FEE sharing originatingTransactionUuid (FEE-01 happy path)
├── finance_payment_fee_unlinked.json        ← PAYMENT_FEE with originatingTransactionUuid pointing nowhere (FEE-03 fallback)
├── finance_payout.json                      ← single PAYOUT, negative amount
├── finance_payment_and_payout_for_promotion.json ← PAYMENT + later PAYOUT (D-56 promotion)
├── finance_balance_liquid.json              ← {"data": {"totalBalance": 12345, "currencyId": "EUR"}}
└── finance_balance_preliminary.json         ← {"data": {"totalBalance": 678, "currencyId": "EUR"}}

spec/fixtures/purchases/    (additions)
├── purchase_vat_split_19_7.json             ← groupedVatAmounts: {"19.0": 318, "7.0": 140}
├── purchase_with_card_metadata_kontaktlos.json ← cardPaymentEntryMode = "CONTACTLESS_EMV"
├── purchase_umlauts_purpose.json            ← Beispiel-Café merchant name in purpose path
├── purchase_refund_with_original_in_page.json  ← refund + original in same fixture, REF-02 lookup test
└── purchase_page_with_payments_for_fee_join.json ← purchases whose payments[].uuid match the finance fee fixtures
```

### 8.3 Fixture authoring conventions (Phase 3 carryover)

- Root `_source` comment field cites the canonical Zettle doc URL.
- All UUIDs synthetic, deterministic (`11111111-1111-1111-1111-111111111111` family — Phase 3 style).
- Merchant name where shown: `"Beispiel-Café"` (umlaut on purpose to gate UTF-8 round-trip).
- Amounts integer minor units; explicit `currency = "EUR"` on every record except `non_eur` fixture.
- No PII, no real merchant names, no real card numbers (`411111******1111` style).
- Each new finance fixture pairs with at least one spec assertion citing the fixture by name.

### 8.4 PII-scrubbing rule (Phase 4 explicit)

The Q3 live probe (Wave 0) returns a real response body. **The recorded body MUST be redacted before being pasted into ADR-0003 Q3 closure:** redact `originatingTransactionUuid` values to `<UUID-REDACTED>`, redact merchant org IDs, redact any name or email. Only the **shape** (field names, types, response wrapper) goes into the ADR; concrete values from real production are stripped.

### 8.5 Per-fixture spec mapping (summary table)

| Fixture | Spec(s) that consume it | Validates |
|---------|--------------------------|-----------|
| `finance_empty.json` | `spec/finance_spec.lua`, `spec/pagination_offset_spec.lua` | empty `data` array terminates loop on first call |
| `finance_single_page.json` | `spec/finance_spec.lua` | parse_transaction kind dispatch (PAYMENT/PAYMENT_FEE/PAYOUT) |
| `finance_multi_page_1.json` + `_2.json` | `spec/pagination_offset_spec.lua` | offset += limit increment, terminates on short page |
| `finance_payment_with_fee_linkage.json` | `spec/mapping_spec.lua`, `spec/refresh_idempotency_spec.lua` | FEE-01 per-sale link, fee_to_transaction correctness |
| `finance_payment_fee_unlinked.json` | `spec/mapping_spec.lua` | FEE-03 fallback into aggregate, fee_aggregate_to_transaction |
| `finance_payout.json` | `spec/mapping_spec.lua` | PAYOUT-01..03, payout_to_transaction |
| `finance_payment_and_payout_for_promotion.json` | `spec/refresh_idempotency_spec.lua` | D-56 SALE-03 promotion (booked false → true) |
| `finance_balance_liquid.json` + `_preliminary.json` | `spec/entry_spec.lua` | ACCT-03 balance + pendingBalance return values |
| `purchase_vat_split_19_7.json` | `spec/mapping_spec.lua`, `spec/meta_purpose_lines_spec.lua` | META-01 per-rate VAT lines, sorted desc |
| `purchase_with_card_metadata_kontaktlos.json` | `spec/mapping_spec.lua` | SALE-07 entry-mode tail, German label `kontaktlos` |
| `purchase_umlauts_purpose.json` | `spec/mapping_spec.lua`, `spec/refresh_log_redaction_spec.lua` | UTF-8 preservation through formatting + redaction |
| `purchase_refund_with_original_in_page.json` | `spec/refresh_idempotency_spec.lua` | REF-02 in-window original lookup via purchases_by_uuid |
| `purchase_page_with_payments_for_fee_join.json` | `spec/refresh_idempotency_spec.lua` | FEE-01 end-to-end fee → purchase join |

---

## Section 9: Risk Register (Phase 4-specific)

### R-1 (HIGH): User's API key lacks `READ:FINANCE` scope

**What:** Phase 2's bearer is minted for whatever scopes the user's API key requested. If the user followed the v0.1.0 README (Phase 2 era — no Finance API mentioned), they may have minted a `READ:PURCHASE`-only key. Phase 4's first Finance API call returns 401, which is mapped to `LoginFailed` per Phase 2 — the user sees the German "Anmeldung fehlgeschlagen: API-Key wurde abgelehnt." string.

**Mitigation:**
- Wave 5 README must instruct users to mint keys with **both** scopes: `https://my.zettle.com/apps/api-keys?name=<key>&scopes=READ:PURCHASE+READ:FINANCE`.
- An ADR-0004 documents the scope requirement and the upgrade path for existing v0.1.0 users (re-mint key with additional scope).
- Phase 5 may add a German error string specifically for "missing scope" — out of Phase 4 scope.

[VERIFIED: github.com/iZettle/api-documentation/blob/master/authorization.md scope section]

### R-2 (MEDIUM): Payout-to-payment inference produces false negatives near refresh boundary

**What:** The temporal inference rule in Section 4.2 ("earliest PAYOUT ≥ PAYMENT.timestamp") fails when a PAYMENT is within the 90-day window but the covering PAYOUT is OUTSIDE the window (already aged out). The sale stays `booked=false` permanently because Phase 4 never sees the covering PAYOUT.

**Mitigation:**
- The 90-day clamp (D-33) clips the Finance API fetch the same way it clips the Purchase API. A sale from day 1 of the 90-day window WILL see its payout (which typically happens day 1-3 for `DAILY` periodicity merchants).
- Edge case: a sale on day 1 of the window, with `MONTHLY` payout periodicity, may not see its covering payout until day ~30. Within 90-day window — should be fine.
- True permanent false-negative: a sale on day 1 minus 1 (outside window) gets promoted to `booked=false` by Phase 3 because it was never seen at all. Phase 3 didn't promote it; Phase 4 doesn't either. **Non-issue** — D-33 owns this surface.

**Status:** acceptable for v0.2.0. Document in README "promotion to booked may take 1-2 refresh cycles for monthly-payout merchants."

### R-3 (MEDIUM): Fee linkage stability assumption (D-49 Option B risk)

**What:** Option B (Section 3.5) assumes Zettle's fee linkage is stable per refresh. If a date's fees flip from "any unlinked" to "all linked" between refreshes, the same fees would be emitted both as an aggregate (refresh N) and per-sale (refresh N+1), double-booking.

**Mitigation:**
- Measure via TRACE log (Wave 5): count `(fees_linked, fees_aggregated)` per refresh. If real users see linkage flipping, escalate to Phase 5.
- README v0.2.0 disclaimer: "Fee linkage is assumed stable. If a previously-aggregated date later appears as per-sale fees, edit the duplicate aggregate row manually in MoneyMoney."
- Option A (LocalStorage persistence) is the bulletproof fix; defer to Phase 5 if measured rate > 1% of refreshes.

**Yves blocker (D-49):** he must confirm Option B (this section) vs Option A (CONTEXT D-49 wording, requires D-59 amendment).

### R-4 (LOW): Currency-mismatch on Finance balance endpoint

**What:** `currencyId` on `/v2/accounts/liquid/balance` is documented as a string but the only example shows `"GBP"`. For a German merchant the value should be `"EUR"`. If a multi-currency merchant somehow has both EUR and non-EUR balances (rare; Zettle accounts are single-currency in practice), the response shape MAY split into multiple `data` entries — undocumented.

**Mitigation:** If `currencyId != "EUR"`, INFO-log and fall back to `account.balance` for both `balance` and `pendingBalance`. Same defensive posture as D-37.

### R-5 (LOW): The fixture `purchase_with_vat_and_tip.json` uses integer-string VAT key

**What:** Existing Phase-3 fixture has `"groupedVatAmounts": {"19": 318}` (integer-string key). Real Zettle API returns `"19.0"` (decimal-string). The Phase-3 mapping currently only reads `vatAmount` top-level so this fixture bug is latent. Phase 4's META-01 implementation reads `groupedVatAmounts` — the existing fixture would pass a `tonumber("19") = 19` check but a new fixture should use `"19.0"` for real-world fidelity.

**Mitigation:** Plan 04-04 (Wave 3 VAT extension) regenerates the existing fixture's `groupedVatAmounts` to use `"19.0"` key AND adds the new `purchase_vat_split_19_7.json` fixture. Both formats accepted defensively by the spec.

### R-6 (LOW): Phase-3 surface preservation

**What:** Phase 4 extends `_format_purpose` (META-01 VAT, SALE-07 card tail) and `RefreshAccount` (Finance API integration + cross-refresh indexes). The 4 callbacks frozen by Phase 2 (`SupportsBank`, `InitializeSession2`, `ListAccounts`, `EndSession`) must remain byte-identical. The Phase-3 mapping for sales-without-VAT-split-and-without-card-metadata must produce byte-identical `purpose` output.

**Mitigation:** Wave 5 audit spec — load Phase-3 fixtures, assert mapped transactions match a golden output (snapshot test). Any drift fails the build.

### R-7 (LOW): Lua `table.sort` stack-overflow on degenerate input

**What:** `fin_payouts` sort (Section 4.3) uses Lua's quicksort. With identical timestamps across many payouts (unlikely but possible at second-precision timestamps), quicksort can recurse deeply. For Phase 4's typical input (a few PAYOUTs per refresh), this is a non-issue.

**Mitigation:** Accept Lua's default. If real users hit a refresh with >1000 PAYOUTs at identical timestamps (will not happen for v0.2.0 German merchant scale), revisit.

---

## Section 10: Cross-refresh dedup contract recap (D-58 / D-59)

### 10.1 What MoneyMoney guarantees

Per `moneymoney.app/api/webbanking/`: "transactions are classified as »neu« if not already in the MoneyMoney database" — keyed (per community convention and Phase-3 ADR-0003) on `transactionCode`. [VERIFIED: webbanking API doc; ASSUMED for exact field-update behavior — same caveat as Phase-3 RESEARCH Section 2c.]

### 10.2 What Phase 4 must NOT do

- **No `LocalStorage` writes from `entry.lua RefreshAccount`** for the indexes — they're per-refresh closures. (D-59)
- **No `LocalStorage` writes for D-49 aggregate dedup** — UNLESS Yves chooses Option A. Then it's a minimal `LocalStorage.zettle.fees_aggregated` table keyed by `org_uuid → set of date strings`. D-59 amendment.
- **No mutation of the input `account` table** — Phase 4 reads `account.accountNumber`, returns a new table.

### 10.3 Idempotency gating extension (D-58 detail)

The Phase-3 `spec/refresh_idempotency_spec.lua` shape extends to cover:

| Scenario | Refresh 1 result | Refresh 2 result | Assert |
|----------|------------------|------------------|--------|
| Simple sale, no payout | 1 sale txn `booked=false` | 1 sale txn with same code, still `booked=false` | code unchanged, booked unchanged |
| Sale + matching payment + later payout | 1 sale txn `booked=false` | 1 sale txn `booked=true, valueDate=X` (same code) | code byte-identical, booked flipped, valueDate set |
| Payout-only | 1 payout txn `zettle:payout:<uuid>` | 1 payout txn with same code | code unchanged |
| Per-sale fee linked | 1 fee txn `zettle:fee:<uuid>` | 1 fee txn with same code | code unchanged |
| Aggregate fee (D-49 Option B) | 1 aggregate `zettle:fee:aggregate:2026-06-15` | refresh sees same fee set → same aggregate code | code unchanged |
| Aggregate fee, then linkage upgrade (D-49 Option B failure mode) | 1 aggregate row | Per-sale fee row WITH DIFFERENT CODE | **DOCUMENTED FAILURE — flagged in README** |
| Aggregate fee, then linkage upgrade (D-49 Option A success) | 1 aggregate row | Same aggregate code re-emitted | code unchanged (state file guarantees) |

### 10.4 Extended transactionCode prefix gate (SEC-03 / D-38 extension)

Phase 3's `spec/refresh_log_redaction_spec.lua` (or equivalent) gates the allowed prefix set. Phase 4 extends to:

```
zettle:sale:           (Phase 3)
zettle:refund:         (Phase 3)
zettle:fee:            (Phase 4 new)
zettle:fee:aggregate:  (Phase 4 new)
zettle:payout:         (Phase 4 new)
```

Anything outside this set in a Phase-4 returned transaction fails the gating spec.

---

## Section 11: CHANGELOG + README v0.2.0 wording (Wave 5)

### 11.1 CHANGELOG entry (German, draft)

```markdown
## [0.2.0] - 2026-MM-DD

### Hinzugefügt
- Vollständige Buchhaltungssicht: Auszahlungen, Gebühren, MwSt-Aufschlüsselung,
  beglichene vs. offene Salden.
- Refunds verlinken zum ursprünglichen Beleg (Belegnummer im Verwendungszweck).
- Per-Karte Anzeige: Kartentyp und Zahlungsart (kontaktlos / Chip / online).
- MwSt-Aufschlüsselung pro Satz, wenn das Unternehmen mit gemischten Sätzen
  arbeitet (z.B. 19 % auf Speisen vor Ort, 7 % zum Mitnehmen).

### Geändert
- `balance` zeigt jetzt den beglichenen Saldo (ausgezahlt oder auszahlungsbereit).
- `pendingBalance` zeigt offene Umsätze, die noch nicht abgerechnet sind.
- Abgeschlossene Verkäufe werden mit Wertstellungsdatum (Auszahlungstag) gebucht.

### Voraussetzung für Bestandskunden
- Der API-Key muss zusätzlich zur Berechtigung `READ:PURCHASE` auch
  `READ:FINANCE` enthalten. Neuen Key erzeugen unter
  https://my.zettle.com/apps/api-keys mit beiden Scopes.

### Bekannte Grenzen
- Auszahlungen werden Verkäufen zeitlich zugeordnet — bei monatlicher
  Auszahlung kann ein Verkauf 1-2 Aktualisierungszyklen brauchen, bis er als
  beglichen markiert ist.
- Die Aufschlüsselung von Gebühren (per-Verkauf vs. Tagesaggregat) richtet sich
  nach den Daten, die Zettle liefert. Bei lückenhafter Verknüpfung wird ein
  Tagesaggregat gebucht.

### Sicherheit
- Die Extension klassifiziert weder Umsätze noch Trinkgelder steuerlich und
  beansprucht keine GoBD-Konformität. Diese Beurteilung bleibt der
  Steuerberatung des Anwenders überlassen.
```

### 11.2 README v0.2.0 section additions

- **"Was die Extension jetzt kann"** — bullet list mirroring CHANGELOG `Hinzugefügt`.
- **"Was die Extension nicht macht"** — explicit non-claims (META-03 surface):
  - Wir klassifizieren keine Umsätze steuerlich.
  - Wir bestätigen keine GoBD-Konformität.
  - Wir erstellen keine USt-Voranmeldung.
  - Wir ersetzen den Steuerberater nicht.
- **"Inbetriebnahme bei bestehendem v0.1.0 API-Key"** — R-1 mitigation: explicit upgrade-path.

### 11.3 Wording discipline (loop-lektor pass in Wave 5)

The German text above is engineering-placeholder. `loop-lektor` reviews for:
- Professional German bookkeeping register (no marketing-Englisch, no Anglizismen like "Refund" → use `Rückerstattung`).
- Avoidance of any META-03 forbidden phrase (the spec gates code; lektor gates docs).
- Consistency with Phase-1/2/3 README sections (which `loop-lektor` already touched).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ISO-8601 timestamp parsing | New regex/parser | Phase-3 `_parse_iso8601_utc` (already handles `+0000`, `.SSS`, `Z`) | Identical input format in Finance API |
| Berlin local-time conversion | Re-derive DST table | Phase-3 `_to_berlin_local_time` + `DST_TABLE` (now 2020-2050) | Already covers full Finance API timestamp range |
| HTTP transport | New `Connection()` wrapper | `M_http.get_json` (Phase 2) | Same Bearer header handling, same SEC-03 redaction |
| Pagination loop | Inline `repeat...until` per call site | `M_pagination.offset_iterate` (Wave 1 — sibling to Phase 3's `iterate`) | One iterator per pagination strategy, independently testable |
| Error mapping | New status-code dispatch | `M_errors.from_http_status` (Phase 2) | Same German error strings, same fail-whole-refresh semantics |
| German amount formatting | New comma-decimal helper | Phase-3 `_format_amount` | Same convention (`9,95`, no thousands < 10k) |
| Card-brand display | New brand map | Phase-3 `BRAND_MAP` in `mapping.lua` | Existing 6-entry table; just consume |
| JSON decode | `dkjson` or custom | `JSON()` built-in (mocked via `mm_mocks`) | Phase-1/2/3 convention; no new dependency |
| Cross-refresh persistence | `io.open` + serialize | `LocalStorage` (only if D-49 Option A — minimal write) | MoneyMoney's only sanctioned persistence |
| OAuth scope upgrade flow | In-extension UI | Out of scope — README documents manual re-mint at my.zettle.com | Extension cannot launch browser |

---

## Common Pitfalls

### Pitfall 1: Linking finance records to purchases by `purchaseUUID1` instead of `payments[].uuid`

**What goes wrong:** Refunds appear to link OK (because `refundsPurchaseUUID1` IS a `purchaseUUID1`), but fees never link — every fee falls through to aggregate fallback even when linkage data is present.
**Why it happens:** Easy misread of CONTEXT D-49 / D-50; conflating the two index keys.
**How to avoid:** Two distinct indexes. `purchases_by_uuid` (key = `purchaseUUID1`, used by refund lookup). `payments_by_uuid` (key = `payments[].uuid` for every payment in every purchase, used by fee linkage). Documented [VERIFIED: fetch-purchase-information-for-transactions-v2.md].
**Warning signs:** Idempotency spec for FEE-01 fails because every fee gets aggregated; FEE-02 spec fails because no fee `purpose` cites a receipt number.

### Pitfall 2: Forgetting `start` is REQUIRED on Finance API

**What goes wrong:** Finance fetch returns 400 because `start` parameter is mandatory (unlike Purchase API's optional `startDate`).
**Why it happens:** Copy-paste of Phase-3 purchase URL builder without re-reading the Finance OpenAPI spec.
**How to avoid:** Always include `start` AND `end` in the Finance URL query string. Add a unit test in `spec/finance_spec.lua` asserting both params are present.
**Warning signs:** Finance fetch consistently fails with 400 + body mentioning "missing required parameter".

### Pitfall 3: Using `YYYY-MM-DDTHH:MM:SSZ` for Finance API timestamps

**What goes wrong:** Finance API may reject or interpret as different time. Spec uses `YYYY-MM-DDThh:mm:ss` (no `Z` suffix, no millis, UTC implicit).
**Why it happens:** Phase 3's purchase URL builder uses `os.date("!%Y-%m-%dT%H:%M:%SZ", ...)`. Reusing it without modification.
**How to avoid:** Add a `_iso8601_finance(posix)` helper in `src/finance.lua` that uses `os.date("!%Y-%m-%dT%H:%M:%S", posix)` (no `Z`). OR change Phase-3 to also use no-`Z` format and unify (riskier — touches Phase-3 code).
**Warning signs:** Live probe (Wave 0) shows the `start` parameter being rejected.

### Pitfall 4: Computing aggregate-fee dates without Berlin-local conversion

**What goes wrong:** Two fees at `2026-06-15T22:30:00Z` (=local `2026-06-16 00:30 CEST`) and `2026-06-15T23:45:00Z` (=local `2026-06-16 01:45 CEST`) are aggregated to date `"2026-06-15"` instead of `"2026-06-16"` — bookkeeping mismatch for a merchant whose Tagesabschluss is local-midnight.
**Why it happens:** Using `fee.timestamp:sub(1, 10)` to extract date.
**How to avoid:** Convert fee timestamp UTC → Berlin local POSIX via `_to_berlin_local_time`, then format as `YYYY-MM-DD` via `os.date("!%Y-%m-%d", local_posix)` (the `!` flag treats the input as UTC, which is what we want since we already added the offset).
**Warning signs:** Spec asserting "two late-evening fees same calendar day" produces two aggregate rows (one per UTC day) instead of one.

### Pitfall 5: Promotion logic running over partial finance result set

**What goes wrong:** Finance fetch fails partway (5xx on page 3), `entry.lua` continues with the partial set, marks some sales `booked=true` based on incomplete payout view, returns the (wrong) result to MoneyMoney.
**Why it happens:** Missing ERR-06 (fail-whole-refresh) propagation. Phase 3 has this guard; Phase 4 must extend it for the second pagination loop.
**How to avoid:** `if fin_err then return fin_err end` immediately after `M_finance.fetch_all(...)`. **Do not fall through with partial finance records — fail the entire RefreshAccount.**
**Warning signs:** Spec for "Finance API 5xx mid-pagination" sees promoted sale rows in the result instead of an error string.

### Pitfall 6: PAYOUT timestamp before its covered PAYMENT (impossible but defensive)

**What goes wrong:** If timestamps are misordered (Zettle bug or batch correction), the inference rule "earliest PAYOUT ≥ PAYMENT" misses the actual covering payout.
**Why it happens:** Clock skew between Zettle's payment recording and payout settlement subsystems.
**How to avoid:** Document the inference as best-effort. The conservative miss (sale stays `booked=false` longer than it should) is acceptable for v0.2.0; the alternative (false-positive promotion) is unacceptable.

### Pitfall 7: Calling `M_pagination.iterate` (Phase 3 cursor) by mistake on Finance API

**What goes wrong:** Finance API has no `lastPurchaseHash`; the cursor iterator's `if has_more` check would terminate after one page (because Finance never returns `lastPurchaseHash`).
**Why it happens:** Same module table `M_pagination`; easy autocomplete mistake.
**How to avoid:** Explicit method name `M_pagination.offset_iterate(...)` distinct from `M_pagination.iterate(...)`. Tests for `M_finance.fetch_all` assert `offset_iterate` is called, not `iterate`.

### Pitfall 8: `_format_purpose` extension breaks Phase-3 fixture-based snapshot

**What goes wrong:** Wave 3 VAT/card-tail extension changes purpose output for a fixture that previously had only 5 lines; the Phase-3 snapshot spec fails.
**Why it happens:** Snapshot specs are brittle to formatter changes.
**How to avoid:** Wave 5's "Phase-3 surface preservation" audit explicitly accepts that `_format_purpose` output changes for fixtures with multi-rate VAT OR card metadata. The audit asserts: for fixtures WITHOUT those triggers (`purchase_simple_sale.json`, etc.), output is byte-identical to Phase 3. For fixtures WITH triggers, output gains exactly the documented new lines.

### Pitfall 9: Logging the merchant's purchaseNumber as PII

**What goes wrong:** Refresh logs include `"REF-02 lookup: refund for purchase #1001"` — leaks transaction-volume info (sequential purchase numbers reveal merchant's daily transaction count).
**Why it happens:** Easy debugging temptation.
**How to avoid:** Phase 4 adds no DEBUG log lines containing `purchaseNumber`. Counts and aggregate stats are OK; specific numbers are not. SEC-03 redaction does not currently target purchaseNumber — adding a `\d+` redactor would over-redact. Discipline only.

### Pitfall 10: Manifest order forgets `finance.lua`

**What goes wrong:** Build artifact loads `M_mapping.fee_to_transaction` before `M_finance` is declared → load-time error.
**Why it happens:** New module `src/finance.lua` requires manifest insertion.
**How to avoid:** Insert `finance` in `tools/manifest.txt` between `purchases` and `payouts`:

```
webbanking_header
log
errors
i18n
model
http
auth
pagination
purchases
finance         ← Phase 4 NEW
payouts         (still stub; payouts logic actually lives in mapping/finance)
balance         (still stub; balance logic actually lives in finance)
mapping
entry
```

**Decision needed (Claude's Discretion):** Phase 4 could either fill the existing `payouts.lua` and `balance.lua` stub modules OR consolidate everything into `finance.lua`. Recommendation: consolidate into `finance.lua` (single new module) because the API endpoints are all on the same host and use the same auth — splitting payouts/balance/transactions into 3 modules is over-decomposition. The existing `payouts.lua` and `balance.lua` stubs become no-ops with a `-- Phase 4: superseded by finance.lua; kept as stub for manifest stability.` comment, OR are removed entirely from `tools/manifest.txt` (cleaner — and `webbanking_header.lua` `M_payouts` / `M_balance` table declarations are removed too). Planner to choose; both are valid.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | busted 2.3.0 (Lua 5.4) + luacheck 1.2.0 + luacov 0.16.0 |
| Config file | `.busted` + `.luacheckrc` (Phase 1 / 2) |
| Quick run command | `./.luarocks/bin/busted spec/<file>_spec.lua` |
| Full suite command | `./.luarocks/bin/busted spec/ && ./.luarocks/bin/luacheck . && lua tools/build.lua --verify` |
| Coverage target | ≥85 % on `src/` excluding `webbanking_header.lua`; Phase 4 aim ≥95 % on new mapping functions and finance.lua |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ACCT-03 | `balance` + `pendingBalance` from Finance API two-endpoint fetch | integration | `busted spec/entry_spec.lua --filter "balance"` | ❌ Wave 0 |
| SALE-07 | Card brand + entry mode in `purpose` (when both present) | unit | `busted spec/mapping_spec.lua --filter "card_tail"` | ❌ Wave 0 |
| REF-01 | Refund = one negative MoneyMoney transaction | unit (Phase 3 carries forward; new spec for index integration) | `busted spec/mapping_spec.lua --filter refund` | ✅ exists |
| REF-02 | Refund `purpose` cites original `purchaseNumber` (in-window) | integration | `busted spec/refresh_idempotency_spec.lua --filter "REF-02"` | ❌ Wave 0 |
| REF-03 | Multiple refunds, same original | integration | `busted spec/refresh_idempotency_spec.lua --filter "partial_refund"` | ❌ Wave 0 |
| FEE-01 | Per-sale fee linkage via `originatingTransactionUuid → payments[].uuid` | integration | `busted spec/refresh_idempotency_spec.lua --filter "FEE-01"` | ❌ Wave 0 |
| FEE-02 | Fee `purpose` cites receipt number | unit | `busted spec/mapping_spec.lua --filter "fee_purpose"` | ❌ Wave 0 |
| FEE-03 | Daily-aggregate fallback when linkage unavailable | integration | `busted spec/refresh_idempotency_spec.lua --filter "FEE-03"` | ❌ Wave 0 |
| PAYOUT-01 | Payout = one negative transaction | unit | `busted spec/mapping_spec.lua --filter "payout_mapping"` | ❌ Wave 0 |
| PAYOUT-02 | `name = "Auszahlung an Bankkonto"` | unit | `busted spec/mapping_spec.lua --filter "payout_name"` | ❌ Wave 0 |
| PAYOUT-03 | `bookingDate` = Berlin-local settlement date | unit | `busted spec/mapping_spec.lua --filter "payout_bookingDate"` | ❌ Wave 0 |
| META-01 | Per-rate VAT lines, sorted desc | unit | `busted spec/meta_purpose_lines_spec.lua --filter "vat_split"` | ❌ Wave 0 |
| META-02 | Tip line / zero-suppression (Phase 3 carry-forward, promoted to own spec) | unit | `busted spec/meta_purpose_lines_spec.lua --filter "tip"` | ❌ Wave 0 |
| META-03 | Forbidden tax-classification phrases never appear | invariant | `busted spec/meta_no_tax_classification_spec.lua` | ❌ Wave 0 |
| SALE-03 (Phase 4 closure) | booked=false → booked=true with valueDate on payout match | integration | `busted spec/refresh_idempotency_spec.lua --filter "SALE-03 promotion"` | ❌ Wave 0 |
| TEST-02 | Recorded fixtures cover all enumerated permutations | scaffold + smoke | `test -f spec/fixtures/finance/finance_payment_with_fee_linkage.json && busted spec/finance_spec.lua` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** quick run of the directly-touched spec file
- **Per wave merge:** full suite + reproducible build (`lua tools/build.lua --verify` twice and assert SHA matches)
- **Phase gate:** full suite green, reproducible build SHA identical, egress allowlist grep returns `oauth.zettle.com` + `purchase.izettle.com` + **NEW** `finance.izettle.com` (predicated on D-46 PASS)
- **Idempotency gating spec runs in BOTH:** every quick command touching `entry.lua`, `purchases.lua`, `pagination.lua`, `finance.lua`, or `mapping.lua` AND in the full suite per wave.
- **Max feedback latency:** ~3 s (lua + busted fast); CI cold ≈ 1-2 min, warm ≈ 30 s.

### Wave 0 Gaps

- [ ] `spec/fixtures/finance/finance_empty.json`
- [ ] `spec/fixtures/finance/finance_single_page.json`
- [ ] `spec/fixtures/finance/finance_multi_page_1.json`
- [ ] `spec/fixtures/finance/finance_multi_page_2.json`
- [ ] `spec/fixtures/finance/finance_payment_with_fee_linkage.json`
- [ ] `spec/fixtures/finance/finance_payment_fee_unlinked.json`
- [ ] `spec/fixtures/finance/finance_payout.json`
- [ ] `spec/fixtures/finance/finance_payment_and_payout_for_promotion.json`
- [ ] `spec/fixtures/finance/finance_balance_liquid.json`
- [ ] `spec/fixtures/finance/finance_balance_preliminary.json`
- [ ] `spec/fixtures/purchases/purchase_vat_split_19_7.json`
- [ ] `spec/fixtures/purchases/purchase_with_card_metadata_kontaktlos.json`
- [ ] `spec/fixtures/purchases/purchase_umlauts_purpose.json`
- [ ] `spec/fixtures/purchases/purchase_refund_with_original_in_page.json`
- [ ] `spec/fixtures/purchases/purchase_page_with_payments_for_fee_join.json`
- [ ] `spec/finance_spec.lua` — pending scaffold (M_finance.fetch, fetch_all, parse_transaction, fetch_account_state)
- [ ] `spec/pagination_offset_spec.lua` — pending scaffold (offset++ termination, MAX_PAGES guard)
- [ ] `spec/meta_purpose_lines_spec.lua` — pending scaffold (META-01 VAT split, META-02 tip zero-suppression)
- [ ] `spec/meta_no_tax_classification_spec.lua` — pending scaffold (13-phrase grep) — **MUST RUN RED first**
- [ ] **Extend** `spec/refresh_idempotency_spec.lua` — D-58 new scenarios — **MUST RUN RED first against current entry.lua**
- [ ] **Extend** `spec/mapping_schema_spec.lua` — cover new fee/payout/aggregate transaction kinds with same 7-field gate

### Wave 0 task (Yves blocker — Q3 probe)

- [ ] Plan 04-01 (single task): Yves runs `GET https://finance.izettle.com/v2/accounts/liquid/transactions?start=2026-06-01T00:00:00&end=2026-06-21T00:00:00&limit=1&includeTransactionType=PAYMENT` with sandbox token. Records response. Pastes redacted body into `docs/adr/0003-sandbox-probe-results.md` Q3 row, flips DEFERRED → ACCEPTED. **Until Q3 PASS, Wave 1 plans cannot lock the URL constants.**

---

## Security Domain

Phase 4 scope: `security_enforcement = true`, `security_asvs_level = 1`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (tokens managed by Phase 2; Phase 4 reuses unchanged) | Phase 2's `M_auth.cached_token` |
| V3 Session Management | No | Phase 2 owns session lifecycle |
| V4 Access Control | Partially — scope-gated (`READ:FINANCE` requirement, R-1) | Read-only by API contract; user-side scope grant |
| V5 Input Validation | Yes — Finance API JSON from attacker-reachable endpoint | `pcall` around `JSON(raw):dictionary()` in Phase 2's `M_http.get_json` (already present) |
| V6 Cryptography | No | Phase 4 introduces no new crypto |
| V7 Error Handling | Yes — Phase-2 error mapper extended for one new error mode (scope-missing) | Wave 5 ADR-0004 for documentation; code path inherits `LoginFailed` |
| V8 Data Protection | Yes — Bearer continues to be redacted in logs (SEC-03 invariant extended) | `spec/refresh_log_redaction_spec.lua` extended to cover Finance API responses |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed JSON in Finance API response | Tampering | `pcall` around `JSON():dictionary()` (Phase 2's `M_http.get_json`) |
| `originatingTransactionUuid` containing Lua pattern special chars | Tampering | `transactionCode = "zettle:fee:" .. uuid` uses `..` concatenation, not format with `%s`; safe against Lua pattern injection |
| Very large `amount` causing arithmetic overflow | Tampering | Lua numbers are IEEE 754 doubles; `amount / 100` for any realistic Finance API value is safe |
| Finance API response leaks via DEBUG log | Info Disclosure | `M_log.redact` already covers Bearer; response body passed through redact same as Purchase API; gated spec extends to cover Finance responses |
| `groupedVatAmounts` with attacker-controlled key like `"19; os.execute('rm -rf /')"` | Code Injection | Lua `tonumber("19; os.execute('rm -rf /')")` returns nil; spec discards non-numeric keys silently; no `loadstring`-equivalent used |
| Cross-merchant fee/payout leakage if `accountNumber` is wrong | Info Disclosure | Phase-2 D-23a + S-01 ensure `orgUuid` is always a valid non-empty string; same token gated to same merchant by Zettle's OAuth scope |
| Finance API 401 logs include user identifier (R-1) | Info Disclosure | Standard Phase-2 redaction applies; error string is a German constant, no Zettle-API content leaked |

**Phase 4 introduces no new auth, no new crypto, no new user-input surfaces beyond Finance API JSON which is structurally indistinguishable from Purchase API JSON.** The primary security concern is the new scope requirement (R-1), which is a documentation issue, not a code issue.

---

## State of the Art

| Old Approach (pre-Phase-4) | Current Approach (post-Phase-4) | Notes |
|---------------------------|--------------------------------|-------|
| Every transaction `booked=false` | Sales promoted to `booked=true + valueDate` when covering payout exists | D-56 — closes SALE-03 dynamic half |
| Single `vatAmount` line | Per-rate VAT lines sorted desc when `groupedVatAmounts` has ≥2 keys | D-53 / META-01 |
| `purpose` ends at `Beleg #X` | Optional `Zahlart: Visa (kontaktlos)` line above receipt | D-57 / SALE-07 |
| Fees not surfaced | Per-sale (`zettle:fee:<uuid>`) or daily aggregate (`zettle:fee:aggregate:<date>`) | FEE-01 / FEE-03 / D-49 |
| Payouts not surfaced | Single negative transaction per payout (`zettle:payout:<uuid>`) | PAYOUT-01..03 / D-51 |
| Refund `purpose` cites refund's `refundsPurchaseUUID1` | Refund `purpose` cites original sale's `purchaseNumber` (when in-window) | REF-02 / D-50 |
| `balance = account.balance` (pass-through) | `balance` from Finance liquid endpoint; `pendingBalance` from preliminary | ACCT-03 / D-52 |
| 1 HTTP call per refresh (Purchase API page loop) | 2-N + 2 HTTP calls (Purchase pages + Finance pages + 2 balance endpoints) | Per-refresh budget acceptable; well under 30s timeout |

**Deprecated/outdated:**
- `src/balance.lua` and `src/payouts.lua` Phase-1 stubs: superseded by consolidation in `src/finance.lua`. Either kept as no-op stubs OR removed from manifest (see Pitfall 10). Planner's call.
- The existing fixture `purchase_with_vat_and_tip.json` uses integer-string VAT keys (`"19"`); Plan 04-04 regenerates to `"19.0"` to match real API. R-5 documents.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `MSR` is a valid `cardPaymentEntryMode` value for magnetic-stripe payments | Section 6 | If wrong, the German label `Magnetstreifen` displays for a code that never appears; `_unknown` fallback covers any actual undocumented values. No user-visible harm. |
| A2 | `MANUAL` is a valid `cardPaymentEntryMode` value for manual card entry | Section 6 | Same as A1. |
| A3 | The Finance API `data` array is sorted descending by timestamp (newest first) in the doc examples; Phase 4 sorts payouts ascending internally to preserve order-independence | Section 4.3 | Independent of API ordering — Phase 4 sorts payouts itself before inference. |
| A4 | Zettle's fee linkage is stable per-refresh (D-49 Option B assumption) | Section 3.5, R-3 | If unstable, double-booking. Mitigated by README disclaimer + TRACE log measurement. |
| A5 | The temporal payout inference rule (earliest PAYOUT ≥ PAYMENT.timestamp covers it) is conservative — no false positives | Section 4.2 | If Zettle's settlement runs payouts before payment timestamps register (unlikely batch-timing edge), some sales stay `booked=false` longer than they should. No double-booking risk. |
| A6 | `currencyId = "EUR"` on liquid + preliminary balance for German merchants | Section 1.4, R-4 | If non-EUR, fall back to Phase-3 balance pass-through. Documented graceful degradation. |
| A7 | `data` is always a present key in Finance API responses (not omitted on empty result) | Section 1.6 | Doc examples consistently show `{"data": []}` on empty; assume invariant. Spec guards with `type(parsed.data) == "table"` check. |
| A8 | `originatingTransactionUuid` is always present on PAYMENT and PAYMENT_FEE records (only `[ASSUMED]` to fail on rare edge per Section 3.3) | Section 3.3 | If absent, the per-fee row aggregates correctly. No data loss. |
| A9 | MoneyMoney updates the existing transaction's `booked` and `valueDate` fields in place when `transactionCode` matches (carried from Phase 3 A5) | Section 10.1 | If MoneyMoney creates a duplicate instead of updating, D-56 promotion creates a second row per sale. Idempotency spec gates; would surface immediately. |
| A10 | The Finance API supports `limit` up to 10000 (OpenAPI default) without a smaller hard cap | Section 1.3 | If real cap is lower (e.g. 1000), the `limit=1000` choice is already conservative; would just paginate more often. |
| A11 | An aggregate fee's `bookingDate` derived from the aggregate's date_iso (`YYYY-MM-DD` Berlin local at 00:00) is acceptable to MoneyMoney | Section 3.4 | MoneyMoney's `bookingDate` is a POSIX timestamp; 00:00:00 of the Berlin local date is unambiguous. |
| A12 | Yves chooses D-49 Option B (per-refresh date clustering; not LocalStorage persistence) | Section 3.5 | If Yves picks Option A, planner adds a `LocalStorage.zettle.fees_aggregated` set + Phase-4 D-59 amendment. Both options are research-supported. |

---

## Open Questions

1. **Does `groupedVatAmounts` ever include rates that don't sum to `vatAmount` to the cent?**
   - What we know: doc examples are consistent; sum = vatAmount.
   - What's unclear: rounding edge cases on very small purchases (e.g., €0.01 with 19% VAT split).
   - Recommendation: WARN log on mismatch; display `groupedVatAmounts` as source of truth; defer reconciliation to Phase 5 if real users hit it.

2. **Is `currencyId` ever lowercase (`"eur"` vs `"EUR"`)?**
   - What we know: doc examples all uppercase (`"GBP"`).
   - What's unclear: defensive case-insensitive compare adds 1 line of code; cost is negligible.
   - Recommendation: `currency:upper() == "EUR"` for robustness.

3. **What happens on `RefreshAccount` if the Finance API fetch_account_state fails but transactions fetch succeeds?**
   - What we know: ERR-06 (fail-whole-refresh) requires aborting on any sub-step failure.
   - What's unclear: should we order calls so balance failure aborts before fetching transactions (cheaper failure path)?
   - Recommendation: order is Purchase → Finance transactions → balance liquid → balance preliminary. Each step `if err then return err end`. If balance fetch fails, the user gets a refresh error and retries; partial-success is not a Phase-4 concern.

4. **D-49 Option A vs Option B — Yves blocker.** Already captured in Section 3.5; planner needs Yves to choose before Wave 4 finalizes.

5. **Does the Finance API ever return a `Content-Encoding: gzip` response that bypasses our `JSON()` parser?**
   - What we know: Phase 2 uses `Accept: application/json` always; MoneyMoney's `Connection` handles content negotiation.
   - What's unclear: undocumented MoneyMoney behavior with compressed responses.
   - Recommendation: Trust MoneyMoney; if real users see "bad_page" errors with gzip headers in their logs, escalate.

6. **Should Phase 4 surface `FROZEN_FUNDS` to alert merchants about chargebacks?**
   - What we know: Out of CONTEXT scope; Phase 5+ if surfaced.
   - What's unclear: bookkeeper visibility might be valuable now, not later.
   - Recommendation: Stay out of scope for v0.2.0. Real chargeback handling is more than just surfacing a transaction — requires linkback to the disputed sale, which is undocumented.

7. **Phase 4 idempotency contract when `since=0` (full re-sync) is passed?**
   - What we know: D-33 clamps to 90 days; `entry.lua` already handles.
   - What's unclear: behavior is the same as any other refresh — all transactions re-emitted with same codes, MoneyMoney dedups.
   - Recommendation: Already covered by `spec/refresh_idempotency_spec.lua`.

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — Phase 4 is purely Lua source + spec additions consuming Phase 2's existing HTTP layer plus a new module that uses the same layer; no new CLI tools, databases, or services required beyond what Phase 1/2/3 established).

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 4 |
|-----------|-------------------|
| Lua 5.4 only; no C modules | All Phase-4 code: plain Lua 5.4; no `require` of external libs in shipped artifact |
| Single `.lua` artifact via `tools/build.lua` | New `src/finance.lua` follows the `do...end`-wrapped pattern; manifest update required (see Pitfall 10) |
| No `require()` of sibling files | Cross-module via global `M_*` tables; new `M_finance` is pre-declared in `webbanking_header.lua` (already exists per Phase 1) |
| API keys never logged | Phase 4 adds no new log sites that could leak Bearer; Finance responses pass through `M_log.redact` same as Purchase |
| German primary user strings | All 12 new i18n keys have German primary, English fallback |
| Coverage gate ≥85 % | Phase 4 aims ≥95 % on `finance.lua` + new `mapping.lua` functions |
| No Claude/AI attribution in any file | Implementors must follow; RESEARCH.md not in shipped artifact |
| GPG-signed commits | All Phase-4 commits signed with `FDE07046A6178E89ADB57FD3DE300C53D8E18642` |
| Conventional Commits | `feat(04):`, `test(04):`, `fix(04):` etc. |
| No `os.execute`, `io.popen`, raw `socket` in shipped artifact | `tools/build.lua` H8 gate enforces; Phase 4 spec code (`spec/meta_no_tax_classification_spec.lua`) uses `io.popen` for `ls src/*.lua` — that's spec-only, not shipped |
| Hilfe → Erweiterungen im Finder zeigen | Documented in v0.1.0 README; Phase 4 v0.2.0 README inherits |
| Read-only contract (no write operations to Zettle) | Phase 4 makes 4 GET requests per refresh (purchases pages + finance pages + liquid balance + preliminary balance); no POST/PUT/DELETE/PATCH |
| Egress allowlist enforced in CI grep | Phase 4 adds `finance.izettle.com` to the allowlist regex (predicated on Q3 PASS) |
| MoneyMoney Compat: current + previous stable | Phase 4 adds no new MoneyMoney API surface (transactions table fields unchanged; balance/pendingBalance documented since pre-v2.4); no compatibility risk |

---

## Sources

### Primary (HIGH confidence, VERIFIED)

- [VERIFIED: github.com/iZettle/api-documentation/blob/master/finance-api/api-reference-v2.yaml] — OpenAPI 3.0 spec: production host `finance.izettle.com/v2`, endpoint paths, query parameter formats, full `originatorTransactionType` enum (13 values), transaction-type semantics
- [VERIFIED: github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-account-transactions-v2.md] — request/response examples showing `{"data": [...]}` wrapper, offset pagination, PAYMENT_FEE linkage shape, PAYOUT shape
- [VERIFIED: github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-account-balance-v2.md] — two endpoints (`liquid` + `preliminary`), `{totalBalance, currencyId}` response, no `pendingBalance` field
- [VERIFIED: github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-payout-info-v2.md] — `/v2/payout-info?at=...` returns `nextPayoutAmount`, `periodicity` — used for understanding payout cadence (not consumed by Phase 4)
- [VERIFIED: github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-purchase-information-for-transactions-v2.md] — **the critical doc**: confirms `originatingTransactionUuid → payments[].uuid`, NOT to `purchaseUUID1`
- [VERIFIED: github.com/iZettle/api-documentation/blob/master/purchase.adoc] — `groupedVatAmounts` decimal-string key shape, `payments[].attributes.cardType` + `cardPaymentEntryMode` field shapes, refund record structure
- [VERIFIED: github.com/iZettle/api-documentation/blob/master/authorization.md] — `READ:FINANCE` scope requirement; API-key creation URL with `scopes=READ:PURCHASE+READ:FINANCE`
- [VERIFIED: moneymoney.app/api/webbanking/] — `RefreshAccount` return shape: `{balance, pendingBalance, transactions}` — both `balance` and `pendingBalance` documented as `Number`
- [VERIFIED: Phase 3 implementation `src/mapping.lua`] — DST_TABLE extended to 2050, `_parse_iso8601_utc` handles `.SSS+0000`/`Z`, `_format_amount` German decimal-comma, `BRAND_MAP` 6 entries
- [VERIFIED: Phase 3 implementation `src/entry.lua`] — 90-day clamp + `os.time()` upper bound, ERR-06 fail-whole-refresh pattern, `cached_token` nil guard
- [VERIFIED: Phase 3 implementation `src/pagination.lua`] — cursor iterator shape (Phase 4 mirrors for offset variant)
- [VERIFIED: Phase 3 implementation `src/purchases.lua`] — URL construction pattern, headers table
- [VERIFIED: Phase 3 `03-RESEARCH.md` + `03-PATTERNS.md` + `03-CONTEXT.md`] — pattern conventions Phase 4 follows verbatim
- [VERIFIED: spec/fixtures/purchases/* — actual fixture content read] — JSON shape conventions, `_source` comment, synthetic UUIDs

### Secondary (MEDIUM confidence)

- [CITED: developer.zettle.com/docs/api/finance/overview] — Finance API context summary (host implied)
- [CITED: developer.zettle.com/docs/api/finance/user-guides/fetch-account-balance] — high-level user-facing description; canonical content is the GitHub v2 doc above

### Tertiary (LOW / ASSUMED)

- A1, A2: `cardPaymentEntryMode = MSR` / `MANUAL` — not in doc examples; industry convention
- A3-A12: as listed in Assumptions Log

---

## Metadata

**Confidence breakdown:**
- Finance API surface (Section 1, 1.2-1.6): HIGH — full OpenAPI spec read and quoted
- Refund index (Section 2): HIGH — Phase-3 D-32 already in place; index pattern is mechanical extension
- Fee linkage (Section 3): HIGH for primary path (link target VERIFIED); MEDIUM for fallback failure-rate (Section 3.3 honestly admits doc silence on edge cases); D-49 Option choice is a Yves Pay/Compliance decision, not a research decision
- Payout matching (Section 4): HIGH for the inference rule; MEDIUM for documenting it as best-effort (Zettle does not commit to a payout-to-payment link contract)
- VAT formatting (Section 5): HIGH — `groupedVatAmounts` shape VERIFIED in multiple doc examples including refund example
- Card metadata (Section 6): HIGH for `cardType` enum (Phase 3 already implemented); MEDIUM for full `cardPaymentEntryMode` enum (A1, A2 ASSUMED entries)
- META-03 (Section 7): HIGH — spec is mechanical
- Fixture matrix (Section 8): HIGH — naming convention is Phase-3 carryover
- Risks (Section 9): HIGH for R-1, R-2, R-3 (research-driven); MEDIUM for R-4..R-7 (defensive)
- Cross-refresh dedup (Section 10): HIGH for code-level guarantees; MEDIUM for MoneyMoney's update-in-place behavior (A9; Phase-3 carries same caveat)

**Research date:** 2026-06-21
**Valid until:** 2026-09-21 (90-day shelf life for Zettle API docs; longer for Phase-3 inheritance which is stable code)

---

*Phase: 04-enrichment-refunds-fees-payouts*
*Research gathered: 2026-06-21*
