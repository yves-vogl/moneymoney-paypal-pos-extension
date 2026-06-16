# MoneyMoney PayPal POS Extension

## What This Is

A community extension for [MoneyMoney](https://moneymoney.app) (macOS personal finance app) that adds **PayPal POS** (formerly Zettle) as a supported account type. German sole proprietors and small merchants who use PayPal POS for card-present payments can finally see their card revenue, refunds, fees, and payouts directly in MoneyMoney alongside their bank and credit-card accounts — no manual CSV import, no spreadsheet detour.

Distributed as a single Lua script on GitHub under MIT license. Free, open-source, no telemetry.

## Core Value

**A German PayPal POS merchant pastes their API key into MoneyMoney once and from then on sees every card transaction, refund, fee, and payout automatically in MoneyMoney — accurately, on schedule, with VAT and tip transparency suitable for bookkeeping.**

If everything else is good but the data is wrong, incomplete, or stale, the project has failed.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward v1.0.0. -->

- [ ] User can install the extension by dropping a single `.lua` file into MoneyMoney's `Extensions` directory
- [ ] User can configure the extension with a PayPal POS / Zettle API key (no OAuth dance, no browser redirect — the key is pasted into MoneyMoney's credentials dialog)
- [ ] Extension authenticates against the PayPal POS / Zettle Public API using the user-supplied key
- [ ] Extension presents the PayPal POS account as `AccountTypeGiro` with both `balance` (paid-out) and `pendingBalance` (not yet settled)
- [ ] Each card sale becomes one transaction (gross amount, including VAT and tips, marked with the customer-facing label and timestamp)
- [ ] Each refund becomes one negative transaction referencing the original sale
- [ ] Each PayPal POS transaction fee becomes one separate negative transaction (booked per-sale if the API exposes it that way, otherwise as a daily aggregate)
- [ ] Each payout from PayPal POS to the merchant's bank becomes one negative transaction labelled as "Auszahlung an Bankkonto"
- [ ] VAT breakdown (e.g. `19% MwSt: 3,83 EUR`) appears in the transaction `purpose` field when the API delivers it
- [ ] Tip amount appears in the transaction `purpose` field when the API delivers it as a separate field
- [ ] Incremental refresh — only transactions newer than MoneyMoney's `since` timestamp are fetched
- [ ] German user-facing strings (account label, error messages, credentials field labels, README)
- [ ] Test suite with high coverage running in CI on every push/PR
- [ ] GitHub Actions CI/CD pipeline — lint (luacheck), test (busted), reproducible build of release `.lua`, attaches SHA256 to release
- [ ] GPG-signed Git tags on every release (`git tag -s vX.Y.Z`)
- [ ] Conventional Commits enforced for all commits
- [ ] Public GitHub repo at `github.com/yves-vogl/moneymoney-paypal-pos-extension` under MIT license
- [ ] README in both German (primary, customer-facing) and English (technical contributor docs)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- **MoneyMoney RSA signature** — Lua extensions can only be RSA-signed by the MoneyMoney maintainer (MRH applications). Third parties cannot self-sign. We ship as a community extension; users must enable "Inoffizielle Extensions erlauben" in MoneyMoney settings. Stretch goal (out of v1 scope): PR to the official MoneyMoney extension repository after stabilization, so MRH can sign it.
- **Apple Developer ID code-signing of the `.lua` file** — `codesign` and Apple notarization apply to Mach-O binaries, frameworks, and app bundles; they have no semantic effect on a plain Lua text file as MoneyMoney interprets it. The Apple Developer account stays unused for this project.
- **OAuth browser flow** — the user supplies a pre-issued API key. Pursuing the OAuth2 authorization-code flow inside a MoneyMoney extension is not supported by the extension API (no browser handoff, no callback URL).
- **Write operations** — the extension is read-only. It does not initiate refunds, payouts, or any state-changing call against PayPal POS.
- **Multi-merchant / multi-account in a single extension instance** — one extension instance = one PayPal POS merchant. A user with multiple merchant accounts adds the extension multiple times.
- **Non-German currencies as primary scope** — primary user is the German merchant. The extension will not reject other currencies, but VAT-related conveniences and German UI strings are the design focus.
- **Telemetry, analytics, crash reporting** — strict no-telemetry policy. The extension makes only the API calls necessary to fetch transactions.
- **Manual paid versions, donations, or sponsorship asks inside the extension** — the product is free. Sponsorship via GitHub Sponsors on the repo is fine but the Lua file stays clean.
- **Live integration tests against the production PayPal POS API in CI** — CI uses recorded fixtures and the PayPal sandbox; production keys never leave the maintainer's machine.

## Context

**MoneyMoney extension ecosystem:**
- Extensions are plain Lua scripts placed in `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions`
- Required entry points: `SupportsBank`, `InitializeSession` (or `InitializeSession2` for credential-array auth), `ListAccounts`, `RefreshAccount`, `EndSession`
- Networking: built-in `Connection()`, `JSON()`, `HTML()`, `PDF()` helpers
- Account type constants: `AccountTypeGiro`, `AccountTypeCreditCard`, `AccountTypePortfolio`, `AccountTypeOther`, etc.
- Transaction record fields: `name`, `amount`, `currency`, `bookingDate`, `valueDate`, `purpose`, `bookingText`, `booked` (bool, pending vs settled), `transactionCode`, etc.
- API reference: https://moneymoney.app/api/webbanking/

**PayPal POS / Zettle context:**
- "PayPal POS" is the rebranded German market name for what was previously sold as PayPal Zettle (and earlier as iZettle). The technical API surface lives at `developer.zettle.com` (PayPal in-person overview at `developer.paypal.com/docs/in-person/` redirects merchants to Zettle for the SDK/API specifics).
- Authentication: OAuth2 client-credentials with a merchant-issued API key (to be verified in research phase — likely `assertion`-grant on `oauth.zettle.com/token`).
- Relevant API surfaces: Purchase API (transactions), Finance API (payouts/settlement), Products API (optional).
- Settlement cadence: typically 1–2 working days from sale to bank deposit.
- Target geography for v1: Germany (EUR, German tax conventions, German UI).

**Bookkeeping context (Germany):**
- Sales drive USt-Voranmeldung (advance VAT return); separate VAT amounts in `purpose` are valuable for the operator.
- PayPal POS fees are deductible business expenses (Betriebsausgabe); booking them separately from gross sale rather than netting is the bookkeeping-correct approach.
- Tips for the merchant (sole proprietor): taxable revenue. Tips passed through to employees: tax-free per § 3 Nr. 51 EStG. Either way, separating tips from base sale in the `purpose` field gives the operator the visibility needed at tax time.

**Maintainer & trust model:**
- Maintainer: Yves Vogl (`github.com/yves-vogl`, `yves.vogl@mac.com`)
- Trust chain: all commits GPG-signed (key `FDE07046A6178E89ADB57FD3DE300C53D8E18642`), all tags GPG-signed, releases attached with SHA256 checksums, reproducible build via GitHub Actions.
- Branch Protection on `main`: required signed commits, required PR review, required CI green.

**Prior work / experience:**
- Maintainer has Apple Developer account (not the right tool for this project — see Out of Scope).
- Maintainer has live PayPal POS account → real-data verification possible.
- Maintainer can provision PayPal sandbox → CI/CD without burning live data.

## Constraints

- **Tech stack — Lua 5.x** as enforced by MoneyMoney's embedded interpreter. No external Lua C modules (MoneyMoney runs in a sandboxed environment). No native dependencies of any kind in the shipped artifact.
- **Tech stack — test harness must run Lua + busted + luacheck outside MoneyMoney** so CI can execute without a macOS+MoneyMoney runtime. MoneyMoney-specific globals (`Connection`, `JSON`, etc.) are mocked.
- **Distribution — single `.lua` file**, no Lua module/package system, no `require()` of sibling files. If we split source for maintainability, the build step concatenates / inlines into one file before release.
- **Security — API keys are never logged, never written to debug output, never echoed back to the user**. MoneyMoney's credentials API is the only persistence path.
- **Performance — single full refresh must complete within MoneyMoney's network timeout** (conservative target: under 30 s for a typical merchant's incremental refresh of last 90 days).
- **Compatibility — extension must work on the current stable MoneyMoney release** and the previous one. No reliance on undocumented internal APIs.
- **Compliance — no telemetry, no third-party calls beyond PayPal/Zettle API endpoints**. README explicitly states this.
- **Localization — primary user strings German**; English strings only for technical contributor-facing material (CONTRIBUTING.md, ADRs, code comments).
- **Maintainability — Conventional Commits, MADR-format ADRs under `docs/adr/`, SemVer releases, Dependabot for tooling deps.**

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Repo name: `moneymoney-paypal-pos-extension` | Convention in MoneyMoney extension ecosystem; product-name first | — Pending |
| License: MIT | Standard for MoneyMoney community extensions; maximally permissive; encourages adoption and contribution | — Pending |
| GitHub home: `github.com/yves-vogl` (personal account, not org) | Solo maintainer; no organizational overhead needed | — Pending |
| Account model: `AccountTypeGiro` with `balance` + `pendingBalance` | Matches PayPal POS reality (settled vs pending); native MoneyMoney support; semantically clearer than "credit card" or "two accounts" | — Pending |
| Transaction granularity: four types (Sale gross, Refund gross, Fee, Payout) as separate transactions | Bookkeeping-correct for German VAT and business expense tracking; gives operator full transparency | — Pending |
| VAT and tip details embedded in `purpose` field as text metadata | MoneyMoney has no structured VAT/tip fields; text in `purpose` is searchable and exportable | — Pending |
| Auth via `InitializeSession2` with API-key credential field | Matches OAuth2 client-credentials grant of PayPal POS API; native MoneyMoney UI for custom credential fields | — Pending |
| Signing strategy: GPG-signed commits/tags + community-extension distribution (no MoneyMoney signature in v1) | Apple Developer ID does not apply to Lua scripts; MoneyMoney's RSA signing is maintainer-controlled. GPG + reproducible builds provide the trust chain available to third parties | — Pending |
| Localization: German primary UI/README, English contributor docs | Target audience is German merchants; contributors are international developers | — Pending |
| Testing strategy: Lua + busted + luacheck in CI; MoneyMoney globals mocked; fixtures recorded from real and sandbox API responses | Enables CI without macOS+MoneyMoney runtime; high coverage is enforceable | — Pending |
| Stretch goal: PR to official MoneyMoney extension repo after stabilization | Gets the extension MRH-signed → out-of-the-box install for end users without enabling unofficial-extensions flag | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-16 after initialization*
