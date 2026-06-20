---
phase: 3
slug: sale-spine-first-user-visible-slice
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-20
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `03-RESEARCH.md` § Validation Architecture, anchored to CONTEXT.md decisions D-31..D-45 and requirements SALE-01..06+08, I18N-01, TEST-03, TEST-04.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | busted 2.3.0 (Lua 5.4) + luacheck 1.2.0 + luacov 0.16.0 |
| **Config file** | `.busted` (Phase 0 / Phase 1) + `.luacheckrc` (Phase 1 + Phase 2 Lows widening) |
| **Quick run command** | `./.luarocks/bin/busted spec/<file_under_test>_spec.lua` (single spec file, post-task) |
| **Full suite command** | `./.luarocks/bin/busted spec/ && ./.luarocks/bin/luacheck . && lua tools/build.lua --verify` |
| **Estimated runtime** | quick ≈ 0.3 s · full ≈ 2.5 s |
| **Coverage target** | ≥85 % on `src/` excluding `src/webbanking_header.lua` (Phase-1 D-06 carryover); Phase 3 aim ≥95 % on new modules |

---

## Sampling Rate

- **After every task commit:** run quick command for the directly-touched spec file
- **After every plan wave:** run full suite + reproducible build (`lua tools/build.lua --verify` twice and assert SHA matches)
- **Before `/gsd-verify-work` (or Phase verification):** full suite must be green, reproducible build SHA identical, egress-allowlist grep returns only `oauth.zettle.com` and `purchase.izettle.com` (Phase 3 introduces no new egress hosts; `finance.izettle.com` remains Phase-4 territory)
- **Max feedback latency:** ~3 s (lua + busted are fast; CI on GitHub Actions ≈ 1–2 min cold, ≈ 30 s warm)
- **Idempotency-gate sampling:** the gating spec `spec/refresh_idempotency_spec.lua` (TEST-03) runs in BOTH the quick post-task command for any change touching `entry.lua`, `purchases.lua`, `pagination.lua`, or `mapping.lua` AND in the full suite per wave. Running it more often costs almost nothing and the load-bearing acceptance criterion deserves the redundancy.

---

## Per-Task Verification Map

> Filled in by the planner during plan emission. Each PLAN file's tasks must include an `<automated>` block citing one of the rows below.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 (W0 fixtures) | 0 | SALE-01..06+08, TEST-04 | — | hand-rolled JSON shapes match Zettle docs (no live keys, no PII) | scaffold | `test -f spec/fixtures/purchases/purchase_simple_sale.json` | ⬜ W0 | ⬜ pending |
| 3-01-02 | 01 (W0 DST table) | 0 | SALE-04 | — | DST boundary timestamps generated deterministically | scaffold | `./.luarocks/bin/busted spec/dst_table_spec.lua` | ⬜ W0 | ⬜ pending |
| 3-02-01 | 02 (gating specs RED) | 1 | TEST-03, TEST-04 | — | gating specs FAIL against empty stubs | unit | `./.luarocks/bin/busted spec/refresh_idempotency_spec.lua spec/mapping_schema_spec.lua` (expect FAIL) | ⬜ W0 | ⬜ pending |
| 3-03-01 | 03 (mapping pure-logic) | 2 | SALE-01, SALE-02, SALE-08, I18N-01, D-34, D-35, D-36, D-37 | — | API key / Bearer never appears in any mapping output | unit | `./.luarocks/bin/busted spec/mapping_spec.lua` | ⬜ W0 | ⬜ pending |
| 3-03-02 | 03 (refund mapping) | 2 | SALE-01, D-32 | — | refund row is separate; transactionCode = "zettle:refund:..." | unit | `./.luarocks/bin/busted spec/mapping_spec.lua --filter refund` | ⬜ W0 | ⬜ pending |
| 3-04-01 | 04 (pagination cursor) | 3 | SALE-06 | — | empty-array AND missing `lastPurchaseHash` BOTH terminate | unit | `./.luarocks/bin/busted spec/pagination_spec.lua` | ⬜ W0 | ⬜ pending |
| 3-05-01 | 05 (purchases fetch) | 3 | SALE-06, D-33 | — | URL contains `startDate=<clamped-iso>`; bearer header passes redaction | unit | `./.luarocks/bin/busted spec/purchases_spec.lua` | ⬜ W0 | ⬜ pending |
| 3-06-01 | 06 (entry integration + i18n) | 4 | SALE-01..06+08, I18N-01 | — | RefreshAccount returns transactions matching golden schema; double-refresh idempotency | integration | `./.luarocks/bin/busted spec/refresh_idempotency_spec.lua spec/mapping_schema_spec.lua` (now GREEN) | ⬜ W0 | ⬜ pending |
| 3-07-01 | 07 (coverage + reproducible build) | 5 | TEST-04, BUILD-02 (Phase-1 carryover) | — | coverage ≥ 95 % on Phase-3 modules; SHA identical across two consecutive build runs | integration | `./.luarocks/bin/busted --coverage spec/ && lua tools/build.lua --verify && lua tools/build.lua --verify` | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Wave 0 (plan `03-01-PLAN.md` in the planner's output) installs ALL of the following before any subsequent wave starts:

- [ ] `spec/fixtures/purchases/purchase_simple_sale.json` — single sale, EUR, no VAT, no tip
- [ ] `spec/fixtures/purchases/purchase_with_vat_and_tip.json` — VAT-bearing sale with tip via `payments[].gratuityAmount`
- [ ] `spec/fixtures/purchases/purchase_refund.json` — `refund=true` with `refundsPurchaseUUID1`
- [ ] `spec/fixtures/purchases/purchase_page1.json` and `purchase_page2.json` — two-page cursor scenario
- [ ] `spec/fixtures/purchases/purchases_empty.json` — empty `purchases[]` array (terminal page)
- [ ] `spec/fixtures/purchases/purchase_non_eur.json` — `currency: "USD"`, must be skipped per D-37
- [ ] `spec/fixtures/purchases/purchase_dst_boundary_summer.json` — timestamp at `2026-06-19T23:55:00Z` (DST-active → Berlin +02:00, local day `2026-06-20`)
- [ ] `spec/fixtures/purchases/purchase_dst_boundary_winter.json` — timestamp at `2026-01-31T23:55:00Z` (CET → Berlin +01:00, local day `2026-02-01`)
- [ ] `spec/fixtures/purchases/purchase_with_card_metadata.json` — Visa with `payments[].attributes.cardType = "VISA"` and `payments[].attributes.maskedPan = "************1234"` (per RESEARCH.md correction over CONTEXT D-35: cardType / maskedPan, not cardBrand / cardLastFour)
- [ ] `spec/dst_table_spec.lua` — pending spec scaffold asserting the EU-DST hardcoded table (`_to_berlin_local_time`) handles 2020–2040 boundaries correctly. Boundary timestamps generated deterministically via the helper `last_sunday_utc(year, month)` from RESEARCH.md § Section 2 (b).
- [ ] `spec/mapping_spec.lua` — pending spec scaffold for `M_mapping.purchase_to_transaction` and `refund_to_transaction`
- [ ] `spec/pagination_spec.lua` — pending spec scaffold for `M_pagination.iterate` cursor termination
- [ ] `spec/purchases_spec.lua` — pending spec scaffold for `M_purchases.fetch` URL shape + bearer use
- [ ] `spec/refresh_idempotency_spec.lua` — pending spec scaffold for TEST-03 idempotency
- [ ] `spec/mapping_schema_spec.lua` — pending spec scaffold for TEST-04 golden-file schema gate

If `webbanking_header.lua` requires no change (the M_purchases / M_pagination / M_mapping tables are already declared per Phase 1), Wave 0 does NOT touch it. Verify in Wave 0 before any subsequent wave assumes the tables exist.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| **End-to-end smoke against a real PayPal POS API key** | SALE-01..06+08 in production | Live API call costs a real merchant account and a live API key; CI runs no live calls. | Maintainer adds the built `dist/paypal-pos.lua` to MoneyMoney's Extensions folder, adds a PayPal POS account with their own API key, clicks "Aktualisieren", verifies card sales appear as transactions with German labels and stable transactionCodes, runs a second "Aktualisieren" and verifies no duplicates appear. Repeat with a refund-purchase if available. |
| **MoneyMoney transactionCode dedup** | SALE-02, SALE-05, TEST-03 production behavior | The automated idempotency spec proves the mapper returns stable codes; that MoneyMoney itself dedups on transactionCode is a contract documented in `moneymoney.app/api/webbanking/` but only observable by running the live extension. | Same as above; observe that the second "Aktualisieren" adds zero new rows to the transaction list. |
| **DST boundary verification on a real timestamp from production** | SALE-04 | The hardcoded EU-DST table can be wrong for a year not covered by the spec's fixture coverage. | At each DST transition (last Sunday of March 2026 / October 2026 / etc.), maintainer pulls a sale that crossed the boundary and confirms `bookingDate` reflects Berlin local time. Issue an annual reminder in the maintainer's calendar. |

---

## Sampling Continuity Check

The Per-Task Verification Map above ensures **every** plan/wave has at least one `<automated>` row. The longest stretch without an automated verify in the planner's emission MUST be ≤ 2 consecutive tasks (Nyquist criterion). The current map satisfies this — every plan ends with at least one automated command.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags (`-w`, `--watch`) anywhere
- [ ] Feedback latency < 5 s (well below — Lua + busted is fast)
- [ ] `nyquist_compliant: true` set in frontmatter after planner verifies the per-task verify map is complete

**Approval:** pending — flipped to `approved YYYY-MM-DD` by the planner after PLAN files exist and every task references one of the rows in the verification map.
