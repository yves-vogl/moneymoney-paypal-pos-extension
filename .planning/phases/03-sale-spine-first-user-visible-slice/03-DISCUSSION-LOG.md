# Phase 3: Sale Spine (first user-visible slice) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-20
**Phase:** 03-sale-spine-first-user-visible-slice
**Areas discussed:** Pending/Booked Transition (SALE-03), Refund-Handling, First-Refresh Pagination
**Mode:** discuss (user is in 48h autonomous-work window — recommendations marked, user picked Recommended for all three)

**Pre-flight finding:** Phase-1 ADR-0003 question Q4 (JSON integer round-trip with `amount = 995`) was already RESOLVED with status PASS. Plain Lua numbers can be used for minor-unit amounts in `mapping.lua`; no `string.format("%d", v)` workaround is required. This eliminated what would otherwise have been the first gray area in Phase 3.

---

## Pending/Booked Transition (SALE-03)

**Question presented:** How does Phase 3 deliver the pending → booked transition without the Finance API (which is Phase 4)?

| Option | Description | Selected |
|--------|-------------|----------|
| Alle Sales `booked=false`; Phase 4 promotet | Phase 3 emits every sale with `booked=false` and no `valueDate`. Phase 4 re-emits with same `transactionCode` + `booked=true` + `valueDate`. MM updates via `transactionCode`. Cleanest separation, matches SALE-03 spec exactly. User sees "vorgemerkt" until Phase 4 ships. | ✓ |
| Heuristik: älter als 5 Tage = booked | Pragmatic (payouts are typically T+1–T+3), but inaccurate against the spec. Risk: user sees "gebucht" while the funds are still in flight at Zettle. Violates PROJECT.md's "accurate for bookkeeping" contract. | |
| Finance-API teilweise in Phase 3 ziehen | Scope creep: would pull Phase 4 auth/endpoint code forward, burn the Phase-4 scope budget, risk a further live probe Q3 (`finance.izettle.com` host) in Phase 3 instead of Phase 4. | |

**User's choice:** Alle Sales `booked=false`; Phase 4 promotet (Recommended)
**Notes:** Captured as D-31 in CONTEXT.md. Visible consequence (every Phase-3 sale in "vorgemerkte Umsätze") will be documented in README v0.1.0 so testers don't misread it as a bug.

---

## Refund-Handling

**Question presented:** How are refunds presented in MoneyMoney?

| Option | Description | Selected |
|--------|-------------|----------|
| Eigener negativer Transaction | Refund purchase becomes its own MoneyMoney row, `transactionCode = "zettle:refund:<purchaseUUID1>"`, negative `amount`, `purpose` references original ("Rückerstattung zu Beleg #..."). Original sale unchanged. Maximally transparent for DATEV/UStG bookkeeping. | ✓ |
| Original-Sale updaten | MoneyMoney's extension API does not support genuine transaction edits via `RefreshAccount` return value. Not reliably implementable. Pseudo-update via `transactionCode` replay would violate idempotency. | |
| Beides (negativer Refund + Original) | Duplicative without added value — the original is already unchanged in option 1. Just unnecessary complexity. | |

**User's choice:** Eigener negativer Transaction (Recommended)
**Notes:** Captured as D-32 in CONTEXT.md. Refund's `name` field carries " Rückerstattung" suffix; multiple refunds for the same sale each get their own row (D-32).

---

## First-Refresh Pagination

**Question presented:** How much history does the first refresh fetch after API-key paste?

| Option | Description | Selected |
|--------|-------------|----------|
| Clamp auf 90 Tage | First refresh = max 90 days back (`since = max(since, now - 90d)`). README documents "older receipts via later Force-Full-Sync (Phase 5+)". Stays within 30 s budget from PROJECT.md, ~1000–2000 sales for typical merchant, no timeout risk. | ✓ |
| 12 Monate Default | More out-of-the-box history (~3–5k sales), but refresh time can reach 1–2 minutes. Risk: MoneyMoney's per-call timeout fires; user sees "Refresh failed". PROJECT.md is explicit about the 30 s budget. | |
| Full 3-Jahre-History | Maximum correctness, but 3–5 min refresh duration, almost certain timeout. Breaks the first MoneyMoney experience. Bad for MVP acceptance. | |

**User's choice:** Clamp auf 90 Tage (Recommended)
**Notes:** Captured as D-33 in CONTEXT.md. README v0.1.0 will document the clamp verbatim plus the workaround path.

---

## Claude's Discretion

The following implementation areas were resolved by Claude without surfacing them as separate gray areas — recommendations captured in CONTEXT.md so downstream agents (planner, executor) act on them without re-asking:

- **D-36 — `bookingDate` timezone:** UTC ISO-8601 → Europe/Berlin local via a hardcoded EU-DST rules table (2020–2040) inside `src/mapping.lua`. Reason: deterministic on CI runners (which are typically UTC); pure `os.time` is fragile.
- **D-34 — `purpose` field format:** Multi-line German bookkeeping-oriented format (`Brutto`/`MwSt`/`Trinkgeld`/`Netto`/`Beleg #`). Reason: matches German invoice/bookkeeping conventions; easier to scan than a single concatenated string.
- **D-35 — `name` field format:** Default `"Kartenzahlung"`; upgrade to `"<CardBrand> •••• <last_four>"` when `payments[1].cardBrand` and `cardLastFour` are present. Refunds get `" Rückerstattung"` suffix.
- **D-37 — Multi-currency:** Skip non-EUR purchases silently with an INFO log line. Reason: Phase-2 hard-locked the account to EUR; a non-EUR amount surfacing as an EUR transaction is a real bookkeeping error.
- **D-40 — File layout:** Phase-1 stubs `src/purchases.lua`, `src/pagination.lua`, `src/mapping.lua` are filled in; no new module-table declarations in `webbanking_header.lua`.

The fourth gray area presented but **not selected** by the user — `bookingDate` timezone strategy — was therefore captured as Claude's discretion (D-36) with the explicit DST-rules-table approach.

## Deferred Ideas

Captured in CONTEXT.md's `<deferred>` block. Highlights:

- Booked = true transition with `valueDate` — Phase 4 (requires Finance API + payout cross-reference)
- Per-purchase fee display (`commission.totalAmount`) — Phase 4
- VAT split by rate (`groupedVatAmounts`) — Phase 5 enrichment
- Force-full-sync flag (override the 90-day clamp from D-33) — Phase 5/6
- Multi-currency support beyond EUR — out of scope for v1.0.0
- Retry/backoff for 429 and 5xx — Phase 5 (`errors.lua` expansion)
- Per-day or per-payout grouping for display — Phase 4 with payout data
