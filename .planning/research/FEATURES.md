# Feature Research

**Domain:** MoneyMoney community extension for PayPal POS (Zettle) — German sole-proprietor / SMB merchants
**Researched:** 2026-06-16
**Confidence:** HIGH on Zettle API surface, HIGH on MoneyMoney extension conventions, MEDIUM on German VAT treatment of Zettle fees (BMF guidance not definitive)

## Reference Extensions Anchoring This Research

There is **no PayPal-consumer extension** in the MoneyMoney community list ([moneymoney.app/extensions/](https://moneymoney.app/extensions/)) as of 2026-06-16 — the listed payment-processor extensions are Stripe, Mollie, Paddle, GoCardless, and Shoop. The "feel" reference is therefore drawn from the four PSP extensions that already ship:

- **[Stripe.lua](https://github.com/nicolindemann/stripe-moneymoney)** by Nico Lindemann — ~148 LOC, single file, the cleanest reference for a payment processor. Booking model: one transaction per `balance_transaction`, fees split into separate negative transactions, gross sale + fee = net deposit. Uses `bookingDate` (created), `valueDate` (available_on), `purpose` (`type` + `description`), `endToEndReference` (source ID). This is the closest semantic match for what we're building. (HIGH confidence — source verified locally.)
- **[Mollie.lua](https://github.com/piet362/mmo)** by Piet Dieg — ~320 LOC, more elaborate. Uses dedicated branches per `transactionType` (`outgoing-transfer`, `refund`, `payment`, `invoice-compensation`). Fees appear as separate transactions with `purpose = "Fees"`. Notably has a `name` field (consumer name) where Stripe does not — relevant if Zettle ever exposes cardholder names (it does not, by design).
- **[Paddle.lua](https://github.com/lukasbestle/moneymoney-paddle)** by Lukas Bestle — ~554 LOC, more detail-rich, leans into the `purpose` field as a multi-line key-value block. Sets a precedent for putting structured-but-textual metadata in `purpose`.

Generic high-quality bank extensions like Wise / N26 / Revolut are **not in the community list** either — these vendors maintain their own apps and have not been built. The information-density reference is therefore "what Stripe.lua does, made slightly richer for German VAT context."

## PayPal POS / Zettle API Surface (what we actually get to work with)

Verified against [iZettle/api-documentation on GitHub](https://github.com/iZettle/api-documentation) and the [Zettle Developer Portal](https://developer.zettle.com/docs/api):

### Purchase API per-purchase fields ([reference](https://github.com/iZettle/api-documentation/blob/master/purchase.adoc))
- `purchaseUUID1` — stable identifier (use this; `purchaseUUID` is deprecated)
- `purchaseNumber` / `globalPurchaseNumber` — human receipt number
- `timestamp` — ISO 8601
- `amount` — gross including VAT and tip, in minor units
- `vatAmount` — total VAT, single number
- `groupedVatAmounts` — **VAT split by rate** as a map (e.g. `{"19": 380, "7": 49}`) — this is the gold field for German bookkeeping
- `products` — per-line array with `vatPercentage` and `rowTaxableAmount` per row
- `gratuityAmount` — tip, present inside `payments[].attributes` for card payments
- `payments[].attributes` (when `type=IZETTLE_CARD`): `cardType` (`VISA`, `MASTERCARD`, `MAESTRO`, `AMEX` etc.), `maskedPan`, `cardPaymentEntryMode` (`CHIP`, `CONTACTLESS`, `SWIPE`, `KEYED`), `authorizationCode`, `referenceNumber`
- `refund` (bool), `refunded` (bool), `refundsPurchaseUUID1` (UUID of original sale), `refundedByPurchaseUUIDs1` (array)
- **No per-transaction fee** in the purchase object — fees only live in the Finance API

### Finance API V2 ([reference](https://github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-account-transactions-v2.md))
- Transaction types via `originatorTransactionType`: `PAYMENT`, `PAYMENT_FEE`, `PAYOUT` (and similar for refunds — `REFUND` / `REFUND_FEE`)
- `originatingTransactionUuid` — links a `PAYMENT_FEE` row back to its `PAYMENT` (i.e. fees ARE per-transaction and linkable, not aggregate)
- `timestamp`, `amount` (signed; negative = debit), `currency`
- `PAYOUT` rows represent the bank-deposit leg; the payout itself does NOT directly list the constituent sales — you correlate by date window and amount

### Key implication
**The Finance API gives us per-sale fee granularity** — we do not have to fall back to daily aggregate. This is better than the PROJECT.md cautious "otherwise as a daily aggregate" plan suggested.

## German VAT / Bookkeeping Reality (the Steuerberater's perspective)

What a Steuerberater wants to see in MoneyMoney for clean USt-Voranmeldung and EÜR:

1. **Gross sale separate from fee** — never net the fee against the sale. The German EÜR books *Erlöse* and *Betriebsausgaben* on different lines. (Stripe.lua and Mollie.lua both honor this — established convention.)
2. **VAT amount visible per sale** — `19% MwSt: 3,83 EUR` belongs in `purpose`. Even better if multi-rate is preserved: `MwSt 19%: 3,80 / MwSt 7%: 0,49`. The `groupedVatAmounts` field makes this trivial — do not collapse it.
3. **Tip booked separately within the sale** — same `purpose` field, line `Trinkgeld: 1,50 EUR`. The Steuerberater decides whether tips belong as taxable revenue (sole proprietor) or pass-through (§ 3 Nr. 51 EStG for employees). The extension does not classify, it surfaces.
4. **Fees**: Per [betriebsausgabe.de](https://www.betriebsausgabe.de/magazin/ebay-und-paypal-gebuehren-umsatzsteuererklaerung-12178/) and [umsatzsteuernachrichten.de](https://www.umsatzsteuernachrichten.de/zahlungen-ueber-paypal-und-die-umsatzsteuer-2136407/), PayPal/Zettle fees from the Luxembourg PayPal entity are **most likely** VAT-exempt financial services under § 4 Nr. 8 UStG, but the BMF has not issued definitive guidance. **Position:** the extension surfaces the fee gross, *without* asserting a VAT classification in the `purpose` text. The Steuerberater classifies. Writing "USt-frei" into purpose would be the extension speaking outside its lane.
5. **Payouts to bank** — clearly labelled `Auszahlung an Bankkonto`, dated by `expectedDate` if present, so the operator can reconcile against the actual bank credit (which arrives in their main bank account's MoneyMoney via the bank's own extension).
6. **Card-brand metadata** — not tax-relevant, but useful for the operator to understand sales mix (Girocard vs. credit card distinguishes fee bands in many fee schedules). Belongs in `purpose` as a tail line.

## Feature Landscape

### Table Stakes (Users Expect These)

Without these the extension is broken and merchants will uninstall it within a week of trying it.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Single-`.lua`-file install | Convention for every MoneyMoney extension | LOW | Already in PROJECT.md constraints |
| API key via credentials dialog (`InitializeSession2`) | Native MoneyMoney UX — no separate config file | LOW | Standard pattern |
| Account appears as `AccountTypeGiro` | Stripe/Mollie/Paddle all use Giro for "money lives here, moves out to bank" semantics | LOW | Decided in PROJECT.md |
| Balance + pendingBalance | Zettle has both (paid-out and to-be-paid-out); merchant sees both via Finance API balance endpoint | LOW | Native MoneyMoney support |
| One transaction per card sale (gross) | This is the bookkeeping unit. Anything coarser hides reality. | LOW | One Purchase API row → one MoneyMoney transaction |
| One transaction per refund, linked to original | Refunds must be visible and traceable; `refundsPurchaseUUID1` makes this easy | LOW | Put original purchase ID in `purpose` |
| Fees as separate negative transactions | German EÜR requires gross-and-separate booking; Stripe.lua precedent | LOW | Finance API `PAYMENT_FEE` rows; link via `originatingTransactionUuid` |
| Payout to bank as separate negative transaction | Without this the balance never zeroes out in MoneyMoney's view | LOW | Finance API `PAYOUT` rows |
| VAT breakdown in `purpose` | Whole reason a German merchant chooses this over CSV export | MEDIUM | `groupedVatAmounts` → multi-line text |
| Incremental refresh (`since` honored) | MoneyMoney calls `RefreshAccount(account, since)` — full refresh every poll is unusable | LOW | Use `since` in Finance API time filter |
| German user-facing strings | Target user is German; English-only labels feel foreign | LOW | Account label "PayPal POS", purpose lines in German |
| Read-only | MoneyMoney extensions are read-only by API design; users assume it | LOW | Decided; no write endpoints called |
| Pagination of historical sales | Initial refresh can pull thousands of rows | MEDIUM | Finance API has `start`/`end` time windows; Purchase API has cursor |
| Stable ordering by `bookingDate` | MoneyMoney dedups by date+amount+purpose; instability creates ghost duplicates | LOW | Use Zettle `timestamp` consistently |

### Differentiators (Markedly Better Than CSV Export)

These are why a merchant chooses this extension over the existing CSV-export-then-manual-import workaround.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Per-rate VAT split (`19%: x,xx € / 7%: y,yy €`) in `purpose` | Steuerberater can read the USt-Voranmeldung directly off MoneyMoney's transaction list | MEDIUM | `groupedVatAmounts` → format per locale |
| Tip surfaced as separate line in `purpose` | Sole proprietor sees taxable tip income; employer sees § 3 Nr. 51 pass-through clearly | LOW | `gratuityAmount` from `payments[].attributes` |
| Card-brand + entry-mode tail line (`Visa · kontaktlos`) | Helps merchant understand fee mix at a glance; Girocard-vs-credit-card matters | LOW | `cardType` + `cardPaymentEntryMode` |
| Refund explicitly references original receipt number | "Erstattung zu Beleg #4711" is more useful than just a negative amount | LOW | `purchaseNumber` of `refundsPurchaseUUID1` target |
| Per-sale fee linked to the sale by reference | Steuerberater sees `Gebühr zu Beleg #4711`, can reconcile each fee to its sale | MEDIUM | Resolve `originatingTransactionUuid` → look up purchase number |
| Receipt number in transaction (`transactionCode` or `purpose`) | Customer disputes ("Sie haben mir am 14.06. 23,90 € berechnet…") become resolvable in seconds | LOW | `purchaseNumber` or `globalPurchaseNumber` |
| `pendingBalance` reflects Zettle's holding amount | Merchant sees "money on the way" without trusting Zettle's app | LOW | Use Finance balance endpoint |
| `valueDate` set to expected payout date when known | MoneyMoney's cash-flow forecast becomes accurate | MEDIUM | Requires correlation with payout schedule |
| Bilingual READMEs (German primary, English contributor) | German merchant comfort + international PR contributions | LOW | Decided in PROJECT.md |
| Reproducible CI build with SHA256-checksummed release | Trust signal for users enabling "Inoffizielle Extensions" | MEDIUM | Decided in PROJECT.md |

### Anti-Features (Deliberately NOT Building)

These commonly get requested or feel obvious — and they're all wrong for this product.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Initiating refunds from MoneyMoney** | "I see the sale here, why can't I refund here?" | (1) MoneyMoney extensions are read-only by API design — no UI affordance to trigger writes. (2) Liability: a misclick refunds a wrong sale. (3) Audit trail belongs in the Zettle app where refund reasons are captured. | Refund in the Zettle app or admin web UI; the next refresh picks it up |
| **VAT classification of Zettle fees ("USt-frei" in purpose)** | "The fee row has no VAT — say so." | The BMF has not definitively classified Zettle/PayPal Luxembourg fees; the extension would be stating a tax position it cannot defend. Steuerberater decides per merchant. | Surface gross fee; leave the `purpose` neutral (`Gebühr zu Beleg #4711`) |
| **Multi-currency auto-conversion to EUR** | "I had a sale in CHF — show me in EUR" | FX rate guesswork; Zettle's own settlement already converts at its rate; converting twice yields lies | Pass `amount` and `currency` through as-is from the API |
| **Line-item-per-sale as separate MoneyMoney transactions** | "I sold 3 items, I want 3 lines" | MoneyMoney's transaction model is the *payment*, not the basket. Exploding 1 purchase into N transactions breaks balance math and refund linkage. | Optionally summarize products in `purpose` text (deferred to v1.x) |
| **OAuth browser flow** | "Modern apps use OAuth" | MoneyMoney extension API has no browser handoff / callback URL | Pre-issued API key via `InitializeSession2` (decided) |
| **Automatic Steuerberater export / DATEV-format CSV** | "Export to my accountant in DATEV format" | Out of MoneyMoney's job — MoneyMoney already exports CSV/MT940; DATEV mapping belongs in a separate tool ([moneymonkey](https://github.com/timpritlove/moneymonkey) exists for this) | Recommend moneymonkey or DATEV's own import |
| **Telemetry / "did the extension work?" pings** | "We want crash reports" | Violates strict no-telemetry policy in PROJECT.md; merchants reject any phone-home | Users report issues on GitHub |
| **Multi-merchant in one extension instance** | "I have two shops" | Conflates merchant identities; one API key per instance is cleaner | Add the extension multiple times (decided) |
| **Live PayPal sandbox calls from CI** | "Test against the real thing" | Sandbox keys rotate; CI flakes; nothing learned that recorded fixtures don't show | Recorded fixtures + sandbox-on-maintainer's-machine for periodic re-verification |
| **Fancy emoji / glyph in `purpose`** | "Make it look modern" | Steuerberater's CSV export ends up with mojibake; reduces searchability | Plain text only |
| **Inferring product categories from `products[]`** | "Classify food vs. non-food for 7% / 19%" | Already in `groupedVatAmounts` — let Zettle do its job | Trust `groupedVatAmounts` |

## Feature Dependencies

```
Single-.lua install
    └── API-key credentials dialog (InitializeSession2)
            └── Authenticated API client (Zettle OAuth client-credentials)
                    ├── ListAccounts (read merchant info)
                    │       └── Account-as-Giro with balance + pendingBalance
                    └── RefreshAccount(since)
                            ├── Purchase API fetch (sales, refunds)
                            │       ├── Sale-as-transaction (gross)
                            │       │       ├── VAT-split in purpose       (uses groupedVatAmounts)
                            │       │       ├── Tip in purpose              (uses gratuityAmount)
                            │       │       └── Card-brand tail line       (uses payments[].attributes)
                            │       └── Refund-as-negative-transaction
                            │               └── Reference to original receipt  (uses refundsPurchaseUUID1 + lookup of purchaseNumber)
                            └── Finance API fetch (fees, payouts)
                                    ├── Fee-as-negative-transaction
                                    │       └── Link fee → sale by receipt number  (uses originatingTransactionUuid + cross-API lookup)
                                    └── Payout-as-negative-transaction
                                            └── valueDate = expected bank-credit date  (uses payout metadata)

Incremental refresh (since) ──enhances──> every fetch above
Pagination ──required-by──> initial-refresh-of-historical-data
German strings ──independent-of──> all data features

Initiating refunds ──conflicts──> read-only design        (excluded)
VAT classification of fees ──conflicts──> "extension stays in its lane"  (excluded)
```

### Dependency Notes

- **Sale-as-transaction is the spine** — everything else hangs off it. Build this first, prove it round-trips, then add VAT enrichment, then refunds, then fees, then payouts.
- **Fee → sale linkage requires two-API correlation** — Finance API gives `originatingTransactionUuid`, but the receipt number you want to put in `purpose` lives in the Purchase API. Either: (a) maintain a UUID→purchaseNumber map across the refresh, or (b) only show UUID short prefix. Option (a) is the better UX, option (b) is the safer v1 fallback if Purchase API quota is tight.
- **VAT-split and tip are independent of refunds and fees** — can land in any order after sale-as-transaction works.
- **Card-brand tail line is the cheapest differentiator** — pure formatting work on data we already have. Free win.
- **Per-sale fee linking is the most expensive differentiator** — cross-API correlation, retry on partial data, edge cases around refunded sales with refunded fees. Worth doing but should not block v1 if the linkage proves brittle; daily-aggregate-fee is the documented fallback.

## MVP Definition

### Launch With (v1.0.0)

The hard floor — anything less and the project has failed per the PROJECT.md Core Value statement.

- [ ] Single-`.lua` install + API-key auth via `InitializeSession2` — **why essential:** entry point; nothing works without it
- [ ] Account as `AccountTypeGiro` with `balance` + `pendingBalance` — **why essential:** the account must show up correctly or the user sees nothing
- [ ] Sale-as-transaction (gross amount, ISO timestamp, EUR) — **why essential:** the spine of the product
- [ ] Refund-as-negative-transaction with original-receipt reference — **why essential:** the merchant *will* refund and *must* see it
- [ ] Fee-as-separate-negative-transaction (per sale, via `originatingTransactionUuid`) — **why essential:** German EÜR booking convention; matches Stripe.lua precedent
- [ ] Payout-as-negative-transaction — **why essential:** otherwise the Zettle balance never reconciles against the bank
- [ ] VAT-split in `purpose` (`MwSt 19%: …` / `MwSt 7%: …` when both present) — **why essential:** the differentiator that justifies the project's existence over CSV export
- [ ] Tip in `purpose` when present — **why essential:** German sole-proprietor tax-time reality
- [ ] Incremental refresh (honors `since`) — **why essential:** poll latency
- [ ] German user-facing strings — **why essential:** target audience
- [ ] Stable UUIDs and ordering so MoneyMoney's dedup works — **why essential:** without this the user sees phantom duplicates every refresh

### Add After Validation (v1.1 — v1.x)

Features to layer in once the spine has been verified against real merchant data for ≥ 4 weeks.

- [ ] Card-brand + entry-mode tail line in `purpose` — **trigger:** users ask "which card did this come from" in the issue tracker (likely)
- [ ] Receipt number prominently in `transactionCode` field (not just `purpose`) — **trigger:** confirming MoneyMoney respects `transactionCode` for searchability
- [ ] `valueDate` set to expected payout date for sales (forward-looking cash flow) — **trigger:** payout schedule has been observed stable enough to compute
- [ ] Optional summary of top product names in `purpose` for high-ticket sales — **trigger:** user feedback that some merchants want product context
- [ ] Sandbox-mode toggle in credentials dialog — **trigger:** any contributor wanting to test without real keys

### Future Consideration (v2+)

Defer until product-market fit on v1 is established.

- [ ] PR to official MoneyMoney extension repo (MRH-signed distribution) — **why defer:** PROJECT.md says stretch goal; requires stability track record
- [ ] Multi-currency support beyond EUR (CHF, USD merchants) — **why defer:** primary user is German; explicitly scoped that way
- [ ] Configurable purpose-line format (operator chooses which lines, what order) — **why defer:** YAGNI until at least one user actually asks
- [ ] Webhook-based near-real-time refresh — **why defer:** MoneyMoney is poll-based; webhooks are out of paradigm

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Sale-as-transaction (gross) | HIGH | LOW | P1 |
| Refund-as-transaction with original reference | HIGH | LOW | P1 |
| Fee-as-separate-transaction (per-sale linked) | HIGH | MEDIUM | P1 |
| Payout-as-transaction | HIGH | LOW | P1 |
| VAT-split in purpose (per-rate) | HIGH | MEDIUM | P1 |
| Tip in purpose | HIGH | LOW | P1 |
| Incremental refresh (since) | HIGH | LOW | P1 |
| German strings | HIGH | LOW | P1 |
| Account: Giro + balance + pendingBalance | HIGH | LOW | P1 |
| Receipt number in purpose | MEDIUM | LOW | P1 |
| Card-brand tail line | MEDIUM | LOW | P2 |
| Receipt in `transactionCode` field | MEDIUM | LOW | P2 |
| valueDate = expected payout date | MEDIUM | MEDIUM | P2 |
| Daily-aggregate-fee fallback (if per-sale linkage fails) | HIGH | LOW | P1 (fallback only) |
| Product-name summary in purpose | LOW | MEDIUM | P3 |
| Sandbox toggle | LOW | LOW | P3 |
| MRH-signed distribution | HIGH | HIGH (out of our hands) | P3 |
| Initiating refunds (write) | n/a | n/a | EXCLUDED |
| Fee VAT classification text | n/a | n/a | EXCLUDED |
| Multi-currency conversion | n/a | n/a | EXCLUDED |

**Priority key:**
- P1: Required for v1.0.0 launch
- P2: v1.1 — v1.x, add when users ask
- P3: v2+, defer until product-market fit
- EXCLUDED: Documented anti-features

## Competitor / Reference Extension Comparison

| Feature | Stripe.lua | Mollie.lua | Paddle.lua | Our Approach |
|---------|------------|------------|------------|--------------|
| Account type | `AccountTypeGiro` | `AccountTypeGiro` | `AccountTypeGiro` | `AccountTypeGiro` (match convention) |
| Gross-and-separate-fee booking | Yes | Yes | Yes | Yes |
| `purpose` content | `type` + `description` | description + method | Multi-line k/v | Multi-line k/v with VAT split, tip, receipt #, card brand |
| Refund-original linkage | No (Stripe's model) | Partial (looks up payment) | n/a | Yes (`refundsPurchaseUUID1` + receipt-number lookup) |
| Multi-currency | Pass-through | Pass-through | Pass-through | Pass-through (no conversion) |
| Auth | Single API key (password field) | Single API key | API key + vendor ID | Single API key via `InitializeSession2` |
| Pagination | Cursor (`starting_after`) | HAL `_links.next` | Cursor | Time-window + cursor (Zettle gives both) |
| German VAT awareness | None | None | None | **Yes — the differentiator** |
| Tip handling | n/a (online) | n/a (online) | n/a (online) | **Yes — POS-specific** |
| Card-brand metadata | n/a | n/a | n/a | **Yes — POS-specific** |

The three POS-specific cells (VAT awareness, tip handling, card-brand) are the answer to "why does this extension need to exist when Stripe.lua already solves PSP transactions." None of the existing PSP extensions surface card-present payment context because none of them integrate a card-present processor.

## Sources

- [moneymoney.app extensions list](https://moneymoney.app/extensions/) — verified no PayPal/Wise/N26/Revolut extensions exist (2026-06-16)
- [Stripe.lua source](https://moneymoney.app/extensions/Stripe.lua) — downloaded and read in full, the closest semantic reference
- [Mollie.lua source](https://moneymoney.app/extensions/Mollie.lua) — partial read; multi-type transaction branching pattern
- [Paddle.lua source](https://moneymoney.app/extensions/Paddle.lua) — verified existence and size, k/v `purpose` precedent
- [Zettle Purchase API reference](https://developer.zettle.com/docs/api/purchase/api-reference-md)
- [iZettle/api-documentation: purchase.adoc](https://github.com/iZettle/api-documentation/blob/master/purchase.adoc) — verified field names: `purchaseUUID1`, `vatAmount`, `groupedVatAmounts`, `gratuityAmount`, `cardType`, `cardPaymentEntryMode`, `refundsPurchaseUUID1`
- [iZettle/api-documentation: finance-api/overview.md](https://github.com/iZettle/api-documentation/blob/master/finance-api/overview.md) — verified Finance API V2 transaction-type strings: `PAYMENT`, `PAYMENT_FEE`, `PAYOUT` linked via `originatingTransactionUuid`
- [Zettle Finance API: fetch payout info](https://developer.zettle.com/docs/api/finance/user-guides/fetch-payout-info)
- [Zettle Finance API: How payments with Zettle work](https://developer.zettle.com/docs/api/finance/concepts/how-payments-with-zettle-work)
- [Zettle Germany payment terms](https://www.zettle.com/de/rechtshinweise/zahlungsbedingungen) — confirms PayPal (Europe) S.à r.l. Luxembourg as contracting entity
- [betriebsausgabe.de: eBay/PayPal-Gebühren USt](https://www.betriebsausgabe.de/magazin/ebay-und-paypal-gebuehren-umsatzsteuererklaerung-12178/) — German VAT treatment of PayPal fees, § 4 Nr. 8 UStG likely applies, BMF guidance pending
- [umsatzsteuernachrichten.de: PayPal USt](https://www.umsatzsteuernachrichten.de/zahlungen-ueber-paypal-und-die-umsatzsteuer-2136407/) — corroborates VAT-exempt-financial-service position
- [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/) — official MoneyMoney extension API reference for `AccountTypeGiro`, transaction record fields, `InitializeSession2`
- [moneymonkey](https://github.com/timpritlove/moneymonkey) — example of separate-tool philosophy for DATEV export (cited in anti-features)

---
*Feature research for: MoneyMoney community extension for PayPal POS (Zettle), German SMB market*
*Researched: 2026-06-16*
