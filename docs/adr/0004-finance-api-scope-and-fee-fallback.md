# ADR-0004: Finance API scope requirement and fee-fallback dedup contract

## Status

ACCEPTED

## Date

2026-06-21

## Deciders

Yves Vogl

## Context

Phase 4 (v0.2.0) adds PayPal POS / Zettle Finance API integration on top of
Phase 2's authenticated network layer. Three design questions surfaced during
planning that warrant durable documentation because they constrain the
user-side setup, shape the behavioural contract a future maintainer must
preserve, and document a deliberate limitation that real merchants may notice
in production.

1. **OAuth scope requirement.** Phase 2's existing Bearer tokens for
   `purchase.izettle.com` may **NOT** have permission to call
   `finance.izettle.com` if the user's API key was minted with `READ:PURCHASE`
   only. The Zettle authorization documentation
   ([VERIFIED: github.com/iZettle/api-documentation/blob/master/authorization.md])
   confirms that `READ:FINANCE` is a separate scope; v0.1.0 users who never
   needed it will hit HTTP 401 on the first refresh after upgrading to v0.2.0.

2. **Fee-linkage fallback dedup contract.** Zettle's Finance API returns
   `PAYMENT_FEE` records carrying `originatingTransactionUuid` that the
   extension joins to the originating purchase's `payments[].uuid`. The
   official documentation does not enumerate failure modes for that linkage —
   every documented example shows it populated. Phase 4 nevertheless ships a
   defensive aggregate-fallback path for the day a single fee record is
   missing or has a stale uuid that does not resolve in the current refresh
   window. Two implementation strategies were evaluated:

   - **Option A** (originally suggested by CONTEXT D-49): persist a
     `LocalStorage.zettle.fees_aggregated` set keyed by Berlin-local date,
     ensuring "once a date is aggregated, always aggregated" — bulletproof
     against double-booking, but requires amending D-59 ("no
     extension-owned state file").
   - **Option B** (research-recommended, RESEARCH §3.5): cluster fees by
     Berlin-local date per-refresh and decide per-refresh: if any fee on a
     date is unlinked, aggregate all fees for that date; if all fees on a
     date are linked, emit per-sale rows. Simpler — no persistent state —
     but if Zettle later back-fills the linkage and a subsequent refresh sees
     the same date fully linked, MoneyMoney ends up with both the original
     aggregate row and the new per-sale rows.

3. **Temporal payout inference.** Zettle does NOT publish a documented
   `PAYOUT → PAYMENT` link field (RESEARCH §4.1). The Finance API treats the
   liquid account as a single ledger: PAYMENTs add, PAYOUTs subtract, sum =
   `liquid.totalBalance`. SALE-03's "promote a sale to booked when its
   settlement payout is visible" therefore has to be inferred from temporal
   ordering, and the inference rule needs to be defensible enough to stand up
   to merchant scrutiny.

Reference: Phase-4 research plan
[`.planning/phases/04-enrichment-refunds-fees-payouts/04-RESEARCH.md`]
sections 1.2 (OAuth scope), 3.5 (D-49 Option A vs B trade-off), 4.1 / 4.2
(payout inference + limitations).

## Decision

### Concern 1 — OAuth scope: `READ:PURCHASE` AND `READ:FINANCE`

- The recommended user-facing setup mints API keys at
  `https://my.zettle.com/apps/api-keys?scopes=READ:PURCHASE+READ:FINANCE`
  with **both** scopes selected.
- Existing v0.1.0 users whose key was minted with `READ:PURCHASE` only must
  re-mint a new key with both scopes before upgrading to v0.2.0, then
  remove and re-add the PayPal POS account in MoneyMoney with the new key.
- The extension does **NOT** detect the scope mismatch explicitly. An HTTP
  401 on the first Finance API call surfaces through Phase 2's existing
  `M_errors.from_http_status` as `LoginFailed` (German: `MoneyMoney`'s
  built-in `LoginFailed` constant), which prompts the user to re-enter
  credentials. This is correct UX for a generic auth failure but does not
  cite the specific missing scope.
- A future Phase 5 or Phase 6 may add a scope-specific German error string
  to distinguish the missing-scope case from a genuine credential
  invalidation. The README v0.2.0 section "Inbetriebnahme bei bestehendem
  v0.1.0 API-Key" documents the upgrade path so users diagnose this case
  correctly without an extension-side improvement.

### Concern 2 — Fee-fallback dedup: Option B (per-refresh date clustering)

- **Implementation chosen:** Option B. When any fee on a given Berlin-local
  date has unresolved linkage (its `originatingTransactionUuid` does not map
  to a `payments_by_uuid` entry in the current refresh), **all** fees on
  that date are aggregated into a single transactionCode
  `zettle:fee:aggregate:<YYYY-MM-DD>`. When **all** fees on a date have
  resolved linkage, per-sale `zettle:fee:<originatingTransactionUuid>` rows
  emit instead.
- **Trade-off accepted:** if a date is aggregated in refresh N because at
  least one fee was unlinked, and the same date in refresh N+M sees all
  fees newly-linked (e.g., Zettle back-filled the link), the extension
  emits per-sale rows on refresh N+M while the aggregate row from refresh N
  remains in MoneyMoney's database — double-booking that single date's
  fees. The README v0.2.0 "Bekannte Grenzen" section documents this and
  instructs users to manually delete the stale aggregate row if it occurs.
- This decision amends D-59 ("no extension-owned state file") implicitly by
  accepting the double-booking risk in exchange for keeping the extension
  stateless. Phase 5 or later may revisit if real merchants hit the
  failure mode and the support burden justifies a minimal
  `LocalStorage.zettle.fees_aggregated` set.

### Concern 3 — Temporal payout inference rule

- **Inference rule (SALE-03 promotion):** a PAYMENT is "settled by" the
  earliest PAYOUT in the current Finance result set whose
  `timestamp >= payment.timestamp`. The promoted sale's `valueDate` is set
  to that PAYOUT's timestamp.
- **Conservative-miss behaviour:** a PAYMENT made today with no PAYOUT yet
  visible stays `booked=false` until a future refresh sees the covering
  PAYOUT. There are no false positives — a sale is never promoted on the
  basis of a PAYOUT that did not actually cover it.
- **Edge case:** merchants with weekly or monthly payout periodicity may
  experience a 1-2 refresh-cycle delay before sales are promoted to
  `booked=true`. The READMEv0.2.0 "Bekannte Grenzen" section documents
  this.
- **FROZEN_FUNDS / ADJUSTMENT carve-outs** between PAYMENT and PAYOUT are
  not modelled — they are outside the Phase-4 `includeTransactionType`
  filter (PAYMENT, PAYMENT_FEE, PAYOUT only). Their amounts are reflected
  in `liquid.totalBalance` so the displayed balance stays correct, but the
  promotion logic does not surface them as separate transactions.

## Consequences

### Positive

- The extension surfaces the full bookkeeping picture for a German PayPal
  POS merchant: settled balance, pending balance, refunds linked to their
  originating sale via Belegnummer, fees as per-sale or daily aggregate,
  payouts as separate negative transactions — all without any persistent
  state owned by the extension.
- The dedup contract (Option B) is simple enough that the per-refresh
  invariant ("two consecutive refreshes against the same Zettle state
  produce byte-identical transactions") is testable in pure Lua against
  recorded fixtures — `spec/refresh_idempotency_spec.lua` gates all four
  cases (sale+payout promotion, payout-only, per-sale fee linked,
  aggregate fee unlinked).
- The temporal payout inference rule is conservative and free of false
  positives, which matters for a tool whose merchants treat the booked
  date as accounting evidence.

### Negative

- Existing v0.1.0 users must perform a one-time API-key re-mint with the
  `READ:FINANCE` scope before upgrading. The extension's German error
  string does not yet name the missing scope explicitly — diagnosis
  requires reading the README upgrade-path section.
- The Option B fee-aggregate path may double-book the fees of a single
  Berlin-local date if Zettle's linkage data becomes more complete
  between refreshes. Affected users must manually delete the stale
  aggregate row in MoneyMoney.
- Merchants with weekly or monthly payout periodicity see a 1-2
  refresh-cycle delay before a sale is promoted to `booked=true`. The
  sale is still visible from refresh 1 — only the `booked` flag and
  `valueDate` change later.

### Mitigations

- README v0.2.0 "Inbetriebnahme bei bestehendem v0.1.0 API-Key" section
  documents the scope re-mint path including the URL with both scopes
  pre-selected.
- README v0.2.0 "Bekannte Grenzen" section documents the fee
  aggregate-then-per-sale double-booking failure mode and the temporal
  inference delay for weekly/monthly payout periodicities.
- Phase 5 may revisit either decision: a scope-specific German error
  string distinguishing missing-scope from invalid-credential 401s, and
  optionally Option A (`LocalStorage.zettle.fees_aggregated`) if real
  users hit the Option B failure mode.

## References

- Research plan:
  `.planning/phases/04-enrichment-refunds-fees-payouts/04-RESEARCH.md`
  - §1.2 — OAuth scope requirement (READ:PURCHASE + READ:FINANCE)
  - §3.5 — Aggregate dedup contract (D-49 Option A vs Option B trade-off)
  - §4.1 — PAYOUT-to-PAYMENT link absence (research conclusion)
  - §4.2 — Settlement inference rule (temporal ordering)
- Requirements: REQUIREMENTS.md
  - ACCT-03 (Finance API balance + pendingBalance)
  - FEE-01, FEE-02, FEE-03 (per-sale fees, fee linkage, aggregate fallback)
  - PAYOUT-01, PAYOUT-02, PAYOUT-03 (payout surfacing, settlement
    promotion, periodicity awareness)
- ADR-0001 (single-file amalgamation via `tools/build.lua`) — the Phase-4
  source extensions ship through the same deterministic build path.
- ADR-0003 (sandbox probe results) — Q3 ("does the Finance API host
  return data for a v0.1.0-shape Bearer token?") was queued for live
  verification; the answer determines whether this ADR is informative
  (Yves' key already had both scopes) or load-bearing user-facing
  guidance (Yves' key had `READ:PURCHASE` only and the upgrade-path
  section is mandatory reading).
- Zettle authorization documentation:
  `github.com/iZettle/api-documentation/blob/master/authorization.md`
- Zettle Finance API documentation:
  `github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-account-transactions-v2.md`
