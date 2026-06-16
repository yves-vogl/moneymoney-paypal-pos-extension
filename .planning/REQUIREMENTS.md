# Requirements: MoneyMoney PayPal POS Extension

**Defined:** 2026-06-16
**Core Value:** A German PayPal POS merchant pastes their API key into MoneyMoney once and from then on sees every card transaction, refund, fee, and payout automatically in MoneyMoney — accurately, on schedule, with VAT and tip transparency suitable for bookkeeping.

## v1 Requirements

Requirements for the v1.0.0 release. Each maps to roadmap phases (filled in during roadmap creation).

### Authentication & Session

- [ ] **AUTH-01**: User can paste a PayPal POS API key into MoneyMoney's add-account dialog (custom credential field labelled in German)
- [ ] **AUTH-02**: Extension authenticates against `oauth.zettle.com/token` using `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer` with `client_id` and `assertion=<API_KEY>`
- [ ] **AUTH-03**: An invalid API key produces a synchronous `LoginFailed` at add-account time (fail-fast profile-ping inside `InitializeSession2`) rather than a delayed error at first refresh
- [ ] **AUTH-04**: Access tokens are cached in `LocalStorage` with `expires_at` and re-minted on cache miss (60 s pre-expiry guard); no refresh-token rotation
- [ ] **AUTH-05**: The API key itself is never written to `LocalStorage`, never logged, never echoed in error messages — only MoneyMoney's credentials store holds it
- [ ] **AUTH-06**: Token cache survives MoneyMoney restart (verified via Phase-1 probe Q5)

### Account & Balance

- [ ] **ACCT-01**: Extension exposes one MoneyMoney account per PayPal POS merchant of type `AccountTypeGiro`
- [ ] **ACCT-02**: Account label is `"PayPal POS — <merchant-name>"` so multiple instances are distinguishable in MoneyMoney's sidebar
- [ ] **ACCT-03**: Refresh returns `balance` (settled/paid-out balance) and `pendingBalance` (sales not yet settled) from the Finance API
- [ ] **ACCT-04**: User can add the extension multiple times to track multiple merchant accounts (one extension instance per merchant)

### Sales

- [ ] **SALE-01**: Each completed PayPal POS sale is returned as one positive MoneyMoney transaction with gross amount (VAT- and tip-inclusive)
- [ ] **SALE-02**: Sale transactions carry a stable `transactionCode = "zettle:sale:<purchaseUUID1>"` that does not change across refreshes
- [ ] **SALE-03**: Pending (not-yet-settled) sales are flagged `booked = false`; settled sales `booked = true` with `valueDate` set to the payout date
- [ ] **SALE-04**: `bookingDate` reflects the sale timestamp converted from Zettle's UTC ISO-8601 to POSIX local time
- [ ] **SALE-05**: A double-refresh produces zero duplicate transactions (idempotency invariant, enforced via golden-file test)
- [ ] **SALE-06**: Incremental refresh respects MoneyMoney's `since` parameter — only purchases dated after `since` are fetched and returned
- [ ] **SALE-07**: Card brand and entry mode (`cardType`, `cardPaymentEntryMode`) are visible in the transaction `purpose` field when the API provides them
- [ ] **SALE-08**: `name` field carries the customer-facing payment label (e.g. card brand + last-four when available, otherwise "Kartenzahlung")

### Refunds

- [ ] **REF-01**: Each refund is returned as one negative MoneyMoney transaction
- [ ] **REF-02**: Refund `purpose` includes a reference to the original sale's receipt number (`refundsPurchaseUUID1` resolved to `purchaseNumber`)
- [ ] **REF-03**: Partial refunds are handled — multiple refund transactions can reference the same original sale

### Fees (PayPal POS commission)

- [ ] **FEE-01**: Each PayPal POS transaction fee is returned as one negative MoneyMoney transaction, linked to its originating sale via the Finance API's `originatingTransactionUuid`
- [ ] **FEE-02**: Fee `purpose` cites the originating sale's receipt number to make per-sale fee inspection possible
- [ ] **FEE-03**: When per-sale linkage is unavailable (e.g. Finance API returns aggregated fees only), the extension falls back to a single daily-aggregate fee transaction with `purpose = "PayPal POS Transaktionsgebühren <date>"` and logs a clear warning

### Payouts

- [ ] **PAYOUT-01**: Each payout from PayPal POS to the merchant's bank account is returned as one negative MoneyMoney transaction
- [ ] **PAYOUT-02**: Payout transactions are labelled `"Auszahlung an Bankkonto"` in `name` to make the cash-flow direction unambiguous
- [ ] **PAYOUT-03**: Payout `bookingDate` matches the settlement date returned by the Finance API

### VAT & Tip Display

- [ ] **META-01**: When `groupedVatAmounts` is populated, the `purpose` field includes a per-rate VAT breakdown in German (e.g. `"19% MwSt: 3,83 EUR"`, `"7% MwSt: 1,40 EUR"`)
- [ ] **META-02**: When `payments[].gratuityAmount` is greater than zero, the `purpose` field includes a German tip line (`"Trinkgeld: X,YY EUR"`); when zero or absent, no tip line appears
- [ ] **META-03**: The extension never classifies tips as taxable or non-taxable, never claims VAT or GoBD conformance — it surfaces facts and leaves bookkeeping classification to the operator and their Steuerberater

### Localization

- [ ] **I18N-01**: All user-facing strings (account label, error messages, credential field labels, `purpose` templates, `name` fallbacks) are German
- [ ] **I18N-02**: Strings are managed via an internal `i18n.t(key)` module with `{de = {...}, en = {...}}` tables; German is the default
- [ ] **I18N-03**: English strings are available as a fallback but not exposed via UI in v1 (no locale switch)

### Error Handling & Resilience

- [ ] **ERR-01**: A token-mint `invalid_grant` response returns the `LoginFailed` constant (per MoneyMoney spec) so the user is prompted to re-enter credentials
- [ ] **ERR-02**: A transient 5xx response triggers retry-with-backoff (max 3 attempts) before the refresh fails
- [ ] **ERR-03**: A 429 response honours the `Retry-After` header (with a sane cap)
- [ ] **ERR-04**: A post-token-mint 401 response triggers a single silent token re-mint, not a `LoginFailed`
- [ ] **ERR-05**: A network failure produces a German error string returned from `RefreshAccount` — never a Lua error, never a partial result
- [ ] **ERR-06**: Any failure inside `RefreshAccount` aborts the whole refresh — the extension never returns partial transactions that would advance MoneyMoney's `since` watermark past undelivered data

### Security & Trust

- [ ] **SEC-01**: A `log.redact()` function is applied to every string before `print()`; it strips JWT-shaped substrings and any `Bearer …` substring
- [ ] **SEC-02**: CI greps the shipped artifact to assert there are no calls to hosts outside the egress allowlist (`oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`)
- [ ] **SEC-03**: An authentication-failure test asserts no API-key fragment, JWT, or `Bearer` token appears in the resulting error string
- [ ] **SEC-04**: `DEBUG = false` is hard-coded in the shipped artifact (CI rejects builds where `DEBUG = true`)
- [ ] **SEC-05**: Branch protection on `main` requires GPG-signed commits and CI green

### Build & Release Engineering

- [ ] **BUILD-01**: Source is organised under `src/` and `tools/build.lua` amalgamates it deterministically into a single `paypal-pos.lua` artifact
- [ ] **BUILD-02**: The build is byte-reproducible — building twice on the same input produces identical bytes (LF normalization, deterministic manifest ordering, no timestamps/SHAs embedded)
- [ ] **BUILD-03**: The `WebBanking{version = X.YY}` field in the shipped artifact is substituted from the Git tag at build time; a test asserts artifact-version == tag
- [ ] **BUILD-04**: Releases are triggered by pushing a GPG-signed Git tag (`git tag -s vX.Y.Z`); CI verifies the tag signature before publishing
- [ ] **BUILD-05**: Release assets include the `paypal-pos.lua` artifact and a `paypal-pos.lua.sha256` checksum file
- [ ] **BUILD-06**: CI uses `softprops/action-gh-release@v2` to publish the GitHub Release with the verified tag's annotation as the release notes

### CI/CD

- [ ] **CI-01**: GitHub Actions runs luacheck (lint), busted (tests), and luacov (coverage) on every push and PR
- [ ] **CI-02**: Coverage gate is ≥85% line coverage on `src/` (excluding `webbanking_header.lua`); regressions fail the pipeline
- [ ] **CI-03**: CI runs on `ubuntu-24.04` with Lua 5.4 pinned via `leafo/gh-actions-lua@v13` and `leafo/gh-actions-luarocks@v6.1.0`; `LC_ALL=C` for determinism
- [ ] **CI-04**: A reproducible-build job builds the artifact twice in two clean checkouts and diffs the outputs — a non-empty diff fails the pipeline
- [ ] **CI-05**: A gitleaks-or-equivalent scan runs in CI to catch accidentally committed secrets
- [ ] **CI-06**: Dependabot (or equivalent) tracks dev-tooling and GitHub-Actions versions

### Testing

- [ ] **TEST-01**: Spec suite uses busted with MoneyMoney globals (`Connection`, `JSON`, `LocalStorage`, account-type constants) mocked in `spec/helpers/mm_mocks.lua`
- [ ] **TEST-02**: HTTP responses are tested via recorded JSON fixtures (PII-scrubbed) under `spec/fixtures/`, covering: auth success / `invalid_grant` / 401 / 429 / 5xx / network failure, single-page and multi-page Purchase API responses, single-page and multi-page Finance API responses (sale, refund, fee, payout), VAT split with two rates, sale with non-zero tip, umlaut characters in `purpose`
- [ ] **TEST-03**: A double-refresh idempotency test fails the build when sales are duplicated
- [ ] **TEST-04**: A golden-file schema test fails the build when a returned transaction is missing required fields (`name`, `amount`, `currency`, `bookingDate`, `purpose`, `transactionCode`, `booked`)

### Distribution & Documentation

- [ ] **DOC-01**: `README.de.md` is the primary README (German), linked from the GitHub repo `README.md` which itself is German with an English-summary section for international contributors
- [ ] **DOC-02**: README's first section is a screenshot-illustrated guide to enabling "Inoffizielle Extensions erlauben" in MoneyMoney settings
- [ ] **DOC-03**: README documents both install paths (sandboxed App-Store build and non-sandboxed direct-download build) and points users to `Hilfe → Erweiterungen im Finder zeigen`
- [ ] **DOC-04**: README includes a German "GoBD-Hinweis" section that explicitly does NOT claim conformance and points users to their Steuerberater
- [ ] **DOC-05**: `CONTRIBUTING.md` (English) documents the dev loop, testing, amalgamator, release process, and the GPG-signed-tag requirement
- [ ] **DOC-06**: ADRs (MADR format) under `docs/adr/` cover at minimum: amalgamator choice, LocalStorage token cache, JWT-bearer-only auth, fee modeling, no-TLS-pinning, string-return error pattern, sandbox probe results
- [ ] **DOC-07**: `LICENSE` file at repo root contains MIT License with copyright "Yves Vogl"
- [ ] **DOC-08**: GitHub repo description (set via `gh repo edit`) reads (German): "MoneyMoney-Extension für PayPal POS — Karten-Umsätze, Refunds, Gebühren und Auszahlungen direkt in MoneyMoney. Open Source, MIT, GPG-signiert."
- [ ] **DOC-09**: GitHub repo topics: `moneymoney`, `moneymoney-extension`, `paypal-pos`, `zettle`, `lua`, `germany`, `accounting`
- [ ] **DOC-10**: A `CHANGELOG.md` (Keep a Changelog format) is maintained per SemVer release

## v2 Requirements

Acknowledged but not in current roadmap.

### Multi-Location Awareness

- **MULTI-01**: When a single merchant operates several PayPal POS terminals or locations, transactions are tagged with location metadata in `purpose`
- **MULTI-02**: Investigate whether the API exposes location IDs and whether MoneyMoney users actually want this distinction

### Upstream Distribution

- **UP-01**: After stabilisation (~v1.0 + several weeks of real-world use), submit the extension as a pull request to MRH applications' official MoneyMoney extension repository so it can be RSA-signed by the maintainer and shipped out-of-the-box

### Localization Beyond German

- **LOC-01**: English UI for non-German MoneyMoney users (the i18n module already supports it, but the locale switch and English README copy are not in v1 scope)

### Per-Line-Item Inspection

- **LINE-01**: Surface basket-level line-item details from the Purchase API in a non-disruptive way (deferred — MoneyMoney's transaction model is the payment, not the basket; needs UX investigation first)

## Out of Scope

| Feature | Reason |
|---------|--------|
| MoneyMoney RSA signature in v1 | Only MRH applications can sign for MoneyMoney; third parties cannot self-sign. Tracked in v2 (UP-01). |
| Apple Developer ID code-signing of the `.lua` | `codesign` and Apple notarization do not apply to Lua text files as MoneyMoney interprets them — no semantic effect. |
| OAuth authorization-code (browser) flow | MoneyMoney extension API has no browser handoff or callback URL; not implementable from within an extension. |
| Write operations (initiating refunds, payouts from MoneyMoney) | Read-only by design — out of scope of a finance-aggregation tool and security risk if compromised credentials could move money. |
| TLS certificate pinning | Marginal security gain vs. high risk of silent breakage on cert rotation; defer to MoneyMoney's `Connection()` default verification. |
| Per-line-item transaction explosion | MoneyMoney's transaction model is the payment, not the basket — exploding into N transactions per sale would break balance math, refund linkage, and the duplication-prevention scheme. |
| Telemetry, analytics, error reporting to third parties | Strict no-third-party policy; CI enforces egress allowlist. |
| Auto-update / update-check pings | Out of allowlist; users see new versions via GitHub Releases or their MoneyMoney extension list. |
| Donations / paid tiers / sponsorship asks inside the extension | Free, free, free. GitHub Sponsors on the repo is acceptable but stays outside the Lua artifact. |
| Live integration tests against production PayPal POS API in CI | Production keys never leave the maintainer's machine; CI uses sandbox keys via GitHub Secrets and recorded fixtures. |
| Locale switch to English in v1 | German is the launch audience; the i18n module supports `en` strings, but the UI exposure is deferred to v2 (LOC-01). |
| GoBD-conformance claim | The extension surfaces facts; it does not certify bookkeeping compliance. Misclaiming GoBD conformance would expose users to risk. |
| Multi-currency conversion guesswork | Non-EUR currencies are returned as-is; the extension does not auto-convert. |
| In-extension support / debug log upload | Users open GitHub issues with their own redacted logs. |

## Traceability

Filled in during roadmap creation. Each v1 requirement maps to exactly one phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTH-01 | TBD | Pending |
| AUTH-02 | TBD | Pending |
| AUTH-03 | TBD | Pending |
| AUTH-04 | TBD | Pending |
| AUTH-05 | TBD | Pending |
| AUTH-06 | TBD | Pending |
| ACCT-01 | TBD | Pending |
| ACCT-02 | TBD | Pending |
| ACCT-03 | TBD | Pending |
| ACCT-04 | TBD | Pending |
| SALE-01 | TBD | Pending |
| SALE-02 | TBD | Pending |
| SALE-03 | TBD | Pending |
| SALE-04 | TBD | Pending |
| SALE-05 | TBD | Pending |
| SALE-06 | TBD | Pending |
| SALE-07 | TBD | Pending |
| SALE-08 | TBD | Pending |
| REF-01 | TBD | Pending |
| REF-02 | TBD | Pending |
| REF-03 | TBD | Pending |
| FEE-01 | TBD | Pending |
| FEE-02 | TBD | Pending |
| FEE-03 | TBD | Pending |
| PAYOUT-01 | TBD | Pending |
| PAYOUT-02 | TBD | Pending |
| PAYOUT-03 | TBD | Pending |
| META-01 | TBD | Pending |
| META-02 | TBD | Pending |
| META-03 | TBD | Pending |
| I18N-01 | TBD | Pending |
| I18N-02 | TBD | Pending |
| I18N-03 | TBD | Pending |
| ERR-01 | TBD | Pending |
| ERR-02 | TBD | Pending |
| ERR-03 | TBD | Pending |
| ERR-04 | TBD | Pending |
| ERR-05 | TBD | Pending |
| ERR-06 | TBD | Pending |
| SEC-01 | TBD | Pending |
| SEC-02 | TBD | Pending |
| SEC-03 | TBD | Pending |
| SEC-04 | TBD | Pending |
| SEC-05 | TBD | Pending |
| BUILD-01 | TBD | Pending |
| BUILD-02 | TBD | Pending |
| BUILD-03 | TBD | Pending |
| BUILD-04 | TBD | Pending |
| BUILD-05 | TBD | Pending |
| BUILD-06 | TBD | Pending |
| CI-01 | TBD | Pending |
| CI-02 | TBD | Pending |
| CI-03 | TBD | Pending |
| CI-04 | TBD | Pending |
| CI-05 | TBD | Pending |
| CI-06 | TBD | Pending |
| TEST-01 | TBD | Pending |
| TEST-02 | TBD | Pending |
| TEST-03 | TBD | Pending |
| TEST-04 | TBD | Pending |
| DOC-01 | TBD | Pending |
| DOC-02 | TBD | Pending |
| DOC-03 | TBD | Pending |
| DOC-04 | TBD | Pending |
| DOC-05 | TBD | Pending |
| DOC-06 | TBD | Pending |
| DOC-07 | TBD | Pending |
| DOC-08 | TBD | Pending |
| DOC-09 | TBD | Pending |
| DOC-10 | TBD | Pending |

**Coverage:**
- v1 requirements: 67 total
- Mapped to phases: 0 (pending roadmap)
- Unmapped: 67 ⚠️ — to be resolved by `/gsd-roadmap`

---
*Requirements defined: 2026-06-16*
*Last updated: 2026-06-16 after initialization*
