# Roadmap: MoneyMoney PayPal POS Extension

**Created:** 2026-06-16
**Granularity:** standard (6 phases)
**Mode:** mvp (vertical-slice-when-possible; foundation layers 1–3 unavoidable before first user-facing demo at end of Phase 3)
**Coverage:** 70/70 v1 requirements mapped to phases
**Phase count rationale:** Reconciles research synthesis (FEATURES=5, ARCH=6, PITFALLS labeled 1–8) onto the dependency-ordered 6-phase backbone from `research/SUMMARY.md §7` under `granularity=standard`.

---

## Core Value (recap)

> A German PayPal POS merchant pastes their API key into MoneyMoney once and from then on sees every card transaction, refund, fee, and payout automatically in MoneyMoney — accurately, on schedule, with VAT and tip transparency suitable for bookkeeping.

The first observable end-to-end demo lands at **end of Phase 3** (paste API key → see card sales in MoneyMoney with stable IDs and no duplicates on double-refresh). Every subsequent phase adds an observable enrichment slice on top.

---

## Phases

- [x] **Phase 1: Foundations & Sandbox Probes** — Stand up the build pipeline, mocks, infra modules, and pin Lua-sandbox capabilities via 8 live probes before any auth code is written. **Completed 2026-06-17.**
- [x] **Phase 2: Authenticated Network Layer** — Implement the JWT-bearer OAuth flow, hostname-allowlisted HTTP wrapper, token cache in LocalStorage, and `ListAccounts` so the user can add a PayPal POS account and a bad key fails fast. (completed 2026-06-19)
- [ ] **Phase 3: Sale Spine (first user-visible slice)** — End-to-end `RefreshAccount` that returns card sales as MoneyMoney transactions with stable identity, idempotent on double-refresh; the first phase a real user can see working.
- [ ] **Phase 4: Enrichment — Refunds, Fees, Payouts, Balance, VAT, Tips** — Layer the remaining transaction kinds and per-purpose metadata onto the spine; the slice that justifies this extension's existence over CSV export.
- [ ] **Phase 5: Resilience & Error Handling** — Branched error handling for all 5 categories (token-mint, post-mint 401, 429, 5xx, network) with the fail-whole-refresh invariant enforced so `since` watermark cannot silently advance past undelivered data.
- [ ] **Phase 6: Release & Polish — Reproducible Build, CI/CD, German Docs** — Tag-triggered reproducible release, GPG-tag verification, SHA256-attached artifact, bilingual README with "Inoffizielle Extensions erlauben" screenshot, GoBD-Hinweis, MADR ADRs — the things that make a stranger trust the extension.
- [ ] **Phase 6.1 (INSERTED): Supply-chain & Scorecard hardening** — Lift OpenSSF Scorecard aggregate from 5.2 to ≥ 8.5 by pinning GitHub Actions to commit-SHAs, scoping workflow tokens to least-privilege, enabling branch-protection introspection, adding Semgrep SAST, and earning the OpenSSF Best Practices passing badge. See `.planning/research/openssf-scorecard-sprint-proposal.md`.
- [ ] **Phase 7 (POST-v1, DEFERRED 2026-06-21): Optional OAuth Authorization-Code flow** — Add an opt-in OAuth2 Authorization-Code path (Zettle "Public/Partner App") next to the existing JWT-Bearer Assertion grant so non-technical merchants can connect via "Mit Zettle anmelden" instead of generating an API key manually. Requires: Zettle Partner-App registration + review, MoneyMoney-sandbox-compatible Out-Of-Band redirect handling (`urn:ietf:wg:oauth:2.0:oob`) verification, MADR ADR-0005 with rationale, dual-path `src/auth.lua` that preserves the Phase-2 JWT-Bearer surface byte-identically. Triggered if/when real users report API-key generation as a UX blocker. Not in v1.0.0 scope.

---

## Phase Details

### Phase 1: Foundations & Sandbox Probes

**Goal:** Toolchain, infra modules, and an ADR-pinned answer to "what does MoneyMoney's Lua sandbox actually let us do" before any business logic is written.
**Mode:** mvp
**Depends on:** Nothing (entry phase)
**Phase-1 probe dependency:** OWNS all 8 probes Q1–Q8 — every later phase consumes their outputs.
**Requirements:** BUILD-01, BUILD-02, TEST-01, I18N-02, I18N-03, SEC-01, SEC-04
**Success Criteria** (observable behaviors):

  1. `busted spec/` runs green from a clean checkout with `dkjson` as the only external dep; CI workflow scaffolds and runs locally via `act` (or equivalent).
  2. `lua tools/build.lua && lua tools/build.lua --verify` produces byte-identical output across two consecutive builds and exits non-zero on tampering (`BUILD-01`, `BUILD-02`).
  3. `docs/adr/0003-sandbox-probe-results.md` exists and contains live-verified answers to all 8 probes (Q1 globals enumeration, Q2 redirect behavior, Q3 `finance.izettle.com` host, Q4 JSON integer round-trip, Q5 `LocalStorage` cross-restart, Q6 `client_id`, Q7 services-label rendering, Q8 TLS default verification).
  4. `log.redact()` strips JWT-shape and `Bearer …` substrings from every string before `print`; a unit test for the redactor passes (`SEC-01`).
  5. The shipped artifact contains `DEBUG = false` at the top level and the build aborts if it sees `DEBUG = true` in any source file (`SEC-04`).
  6. The internal `i18n.t(key)` module exists with `{de = {...}, en = {...}}` tables and defaults to `de`; English strings are present as a fallback but never exposed via UI (`I18N-02`, `I18N-03`).
  7. `spec/helpers/mm_mocks.lua` defines `Connection`, `JSON`, `LocalStorage`, `MM.*`, `WebBanking`, account-type and protocol constants so tests run outside MoneyMoney (`TEST-01`).

**Plans:** TBD
**UI hint:** no
**AI integration hint:** no

### Phase 2: Authenticated Network Layer

**Goal:** A merchant pastes an API key into MoneyMoney's add-account dialog, the extension authenticates against `oauth.zettle.com`, and a wrong key fails synchronously with `LoginFailed` — without ever leaking the key into logs, errors, or LocalStorage.
**Mode:** mvp
**Depends on:** Phase 1 (probes Q1, Q2, Q5, Q6, Q8 must be resolved; mocks, redactor, build pipeline must exist)
**Phase-1 probe dependency:** Q2 (redirect behavior of `Connection():request` on the token endpoint), Q5 (`LocalStorage` cross-restart persistence), Q6 (PayPal POS first-party `client_id`), Q8 (TLS default verification).
**Requirements:** AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, AUTH-06, SEC-03, ACCT-01, ACCT-02, ACCT-04
**Success Criteria** (observable behaviors):

  1. User adds the extension in MoneyMoney's "Konto hinzufügen" dialog with a custom German-labelled API-key field; pasting a valid key shows the account `"PayPal POS — <merchant-name>"` of type Giro in the sidebar (`AUTH-01`, `ACCT-01`, `ACCT-02`).
  2. Pasting a wrong API key surfaces a German `LoginFailed`-equivalent error **synchronously** in the add-account dialog (not silently hours later on first refresh), driven by the fail-fast profile-ping inside `InitializeSession2` (`AUTH-03`).
  3. Token cache survives MoneyMoney restart: after a fresh login the token sits in `LocalStorage.zettle` with `access_token`, `expires_at`, `obtained_at`, `client_id`; the second `RefreshAccount` within 2h reuses the cached token and the third after restart reuses it too (`AUTH-04`, `AUTH-06`).
  4. The API key never appears in `LocalStorage`, in any `print()` output, in any returned error string, or in any debug field; an explicit unit test exercises an auth failure and greps the resulting error string for JWT shape and `Bearer` — must find nothing (`AUTH-05`, `SEC-03`).
  5. A user can add the extension **a second time** with a different API key and both accounts coexist with distinguishable labels in MoneyMoney's sidebar (`ACCT-04`).
  6. The OAuth round-trip targets exactly `POST https://oauth.zettle.com/token` with `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`, `client_id=<uuid>`, `assertion=<API_KEY>` — confirmed by a sandbox spike captured as a recorded fixture (`AUTH-02`).

**Plans:** 7/7 plans complete
**Wave 1**

- [x] 02-01-PLAN.md — Wave 0: test infrastructure (fixtures, real base64decode mock, spec scaffolds)
- [x] 02-02-PLAN.md — Wave 1: M_errors.from_http_status per D-24
- [x] 02-03-PLAN.md — Wave 1: JWT base64url decoder + client_id extraction per D-22

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-04-PLAN.md — Wave 2: M_http (post_form, get_json, shutdown, _infer_status) per D-25 + Risk R-1
- [x] 02-05-PLAN.md — Wave 2: M_auth orchestration (exchange_assertion, fetch_profile, persist_session, cached_token)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-06-PLAN.md — Wave 3: Entry integration (InitializeSession2, ListAccounts, EndSession)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 02-07-PLAN.md — Wave 4: SEC-03 gating spec + manifest/coverage/egress verification

**Cross-cutting constraints:**

- Commits are GPG-signed by FDE07046A6178E89ADB57FD3DE300C53D8E18642; no Claude/AI attribution in commit message, code, or comments
- Commits are GPG-signed by FDE07046A6178E89ADB57FD3DE300C53D8E18642; no Claude/AI attribution

**UI hint:** no
**AI integration hint:** no

### Phase 3: Sale Spine (first user-visible slice)

**Goal:** A merchant with a valid API key clicks "Aktualisieren" in MoneyMoney and sees their real card sales as MoneyMoney transactions — correct gross amount, German label, stable IDs, no duplicates on double-refresh, only sales newer than `since` are fetched.
**Mode:** mvp
**Depends on:** Phase 2 (authenticated HTTP layer, account listing)
**Phase-1 probe dependency:** Q4 (JSON integer round-trip for minor-unit amounts) — must be resolved before mapping is locked.
**Requirements:** SALE-01, SALE-02, SALE-03, SALE-04, SALE-05, SALE-06, SALE-08, I18N-01, TEST-03, TEST-04
**Success Criteria** (observable behaviors):

  1. Each completed PayPal POS sale appears as one positive MoneyMoney transaction with VAT- and tip-inclusive gross amount in EUR (`SALE-01`).
  2. Each sale carries `transactionCode = "zettle:sale:<purchaseUUID1>"` that does not change across refreshes; double-refresh on the same fixture produces **zero** new transactions — the gating idempotency test (`SALE-02`, `SALE-05`, `TEST-03`).
  3. Pending (unsettled) sales appear with `booked = false`; once linked to a payout they become `booked = true` with `valueDate` set to the payout date (`SALE-03`).
  4. `bookingDate` is the sale timestamp converted from Zettle's UTC ISO-8601 to POSIX local time; a fixture with a sale at 23:55 UTC verifies the local-day classification (`SALE-04`).
  5. Refreshing with a non-zero `since` fetches only purchases newer than `since` (verified by URL-capture spec asserting `startDate ≈ since`); a refresh of an unchanged account returns an empty `transactions` array (`SALE-06`).
  6. `name` carries a German customer-facing payment label ("Kartenzahlung" or card-brand + last-four when available); a golden-file schema test fails the build the moment any returned transaction is missing `name`, `amount`, `currency`, `bookingDate`, `purpose`, `transactionCode`, or `booked` (`SALE-08`, `I18N-01`, `TEST-04`).

**Plans:** TBD
**UI hint:** no
**AI integration hint:** no

### Phase 4: Enrichment — Refunds, Fees, Payouts, Balance, VAT, Tips

**Goal:** The full bookkeeping picture: refunds linked to original sales, per-sale fees via Finance API, payouts as separate negatives, settled-and-pending balances, VAT split per rate in `purpose`, tip surfaced as its own line — the slice that makes this extension worth choosing over CSV export.
**Mode:** mvp
**Depends on:** Phase 3 (sale spine + canonical `buildTransaction()` helper)
**Phase-1 probe dependency:** Q3 (`finance.izettle.com` host confirmation) — must be live-verified before Finance API integration can be locked.
**Requirements:** ACCT-03, REF-01, REF-02, REF-03, FEE-01, FEE-02, FEE-03, PAYOUT-01, PAYOUT-02, PAYOUT-03, META-01, META-02, META-03, SALE-07, TEST-02
**Success Criteria** (observable behaviors):

  1. The account row in MoneyMoney's sidebar shows both `balance` (settled / paid-out) and `pendingBalance` (in-flight sales not yet settled), both sourced from the Finance API liquid account endpoint and matching `my.zettle.com` to the cent (`ACCT-03`).
  2. Each refund appears as one negative transaction; `purpose` cites the original sale's receipt number (`refundsPurchaseUUID1` → `purchaseNumber` lookup); partial refunds produce multiple refund rows each pointing at the same original sale (`REF-01`, `REF-02`, `REF-03`).
  3. Each PayPal POS fee appears as one negative transaction linked per-sale via Finance API `originatingTransactionUuid` (primary); when linkage fails or is unavailable the extension emits one daily-aggregate fee row with `purpose = "PayPal POS Transaktionsgebühren <date>"` and writes a clear German warning to the log (`FEE-01`, `FEE-02`, `FEE-03`).
  4. Each payout appears as one negative transaction with `name = "Auszahlung an Bankkonto"` and `bookingDate` set to the Finance-API-reported settlement date (`PAYOUT-01`, `PAYOUT-02`, `PAYOUT-03`).
  5. When `groupedVatAmounts` is populated, `purpose` includes a per-rate German VAT breakdown (`"19% MwSt: 3,83 EUR"`, `"7% MwSt: 1,40 EUR"`); when `payments[].gratuityAmount > 0`, `purpose` includes a `"Trinkgeld: X,YY EUR"` line; when zero the line is **absent** (no `"Trinkgeld: 0,00 EUR"` noise); the extension never writes a tax-classification phrase such as "USt-frei" or "GoBD-konform" anywhere (`META-01`, `META-02`, `META-03`).
  6. When the Purchase API provides `cardType` and `cardPaymentEntryMode`, they appear as a tail line in `purpose`; a recorded fixture suite covers auth success / `invalid_grant` / 401 / 429 / 5xx / network failure, single + multi-page Purchase API, single + multi-page Finance API for each of sale/refund/fee/payout, dual-rate VAT split, non-zero tip, and umlaut characters in `purpose` (`SALE-07`, `TEST-02`).

**Plans:** 6 plans
**Wave 0** *(human-blocking; Yves runs the Q3 sandbox probe)*

- [ ] 04-01-PLAN.md — Wave 0: Yves Q3 live probe + ADR-0003 Q3 transition (DEFERRED → ACCEPTED / REJECTED)

**Wave 1** *(blocked on no plan; runs in parallel with Wave 0 against the research-recommended host)*

- [x] 04-02-PLAN.md — Wave 1: pure-logic Finance mapping + offset pagination + 13 new/regenerated fixtures + manifest consolidation (M_pagination.offset_iterate, M_finance.parse_transaction, M_mapping fee_to_transaction/fee_aggregate_to_transaction/payout_to_transaction/promote_to_booked + refund_to_transaction(opts), 12 new i18n keys) — **SHIPPED 2026-06-21** (3 commits, 255/0 successes)

**Wave 2** *(blocked on 04-02)*

- [x] 04-03-PLAN.md — Wave 2: M_finance HTTP fetch + entry-layer integration (fetch/fetch_all/fetch_account_state; RefreshAccount 16-step sequence: purchases_by_uuid + payments_by_uuid indexes, SALE-03 promotion, D-49 Option B fee classification, payout mapping); D-49 Yves-blocker RESOLVED (Option B) — **SHIPPED 2026-06-21** (2 commits, 300/0 successes, repro SHA `d6356d5b...`)

**Wave 3** *(blocked on 04-02; parallel with Wave 2)*

- [x] 04-04-PLAN.md — Wave 3: per-rate VAT + card-brand+entry-mode tail in _format_purpose; Phase-3 surface preservation snapshot — **SHIPPED 2026-06-21** (2 commits)

**Wave 4** *(blocked on 04-03 + 04-04)*

- [ ] 04-05-PLAN.md — Wave 4: META-03 forbidden-strings invariant spec + META-02 zero-suppression spec + extended idempotency (4 D-58 cases) + extended log-redaction (D-38 5-prefix gate + SEC-03 Finance API); surfaces D-55 Yves-blocker

**Wave 5** *(blocked on 04-03 + 04-04 + 04-05)*

- [ ] 04-06-PLAN.md — Wave 5: CI egress allowlist + ADR-0004 + CHANGELOG/README v0.2.0 German sections + Phase-3 surface preservation audit + loop-lektor checkpoint

**Cross-cutting constraints:**

- Commits GPG-signed by FDE07046A6178E89ADB57FD3DE300C53D8E18642; no AI/Claude attribution in commit messages, code, comments, fixtures, or i18n strings
- Conventional Commits: `feat(04-NN):`, `fix(04-NN):`, `test(04-NN):`, `docs(04-NN):`, `refactor(04-NN):`, `ci(04-NN):`
- No `require()` of siblings in shipped `src/*.lua` (cross-module access via global M_* tables per D-02)
- 85%+ coverage on amalgamated artifact (Phase 3 landed 99.23%)
- Reproducible build SHA across two `lua tools/build.lua --verify` runs
- luacheck clean across all source + spec files
- TDD discipline: RED spec committed before GREEN impl in each wave
- German user-facing strings only; English fallback for technical-contributor docs
- All HTTP via `M_http.get_json` (D-42 inherited); all errors via `M_errors.from_http_status` (D-43 inherited); Bearer never logged (D-45 SEC-03 extends to Finance API)
- transactionCode prefix gate extends to fee + fee:aggregate + payout (D-58)
- since clamp at entry boundary (D-33 inherited); non-EUR records silently skipped (D-37 inherited; applies to Finance records too)

**Yves-blockers (surfaced across the phase):**

- **Q3** (Plan 04-01): live probe of `finance.izettle.com`; ADR-0003 Q3 transition
- **D-49** (Plan 04-03 preamble): Option A (LocalStorage persistence) vs Option B (per-refresh date clustering); plan defaults to Option B per research recommendation
- **D-55** (Plan 04-05 preamble): META-03 forbidden-strings list completeness; plan implements the 13-phrase CONTEXT recommendation

**UI hint:** no
**AI integration hint:** no

### Phase 5: Resilience & Error Handling

**Goal:** Every adversarial network condition produces a clear German message and never silently advances the `since` watermark past undelivered data.
**Mode:** mvp
**Depends on:** Phase 4 (real data paths exist to test resilience against)
**Phase-1 probe dependency:** None (the probes are settled by this point; only standard HTTP patterns remain).
**Requirements:** ERR-01, ERR-02, ERR-03, ERR-04, ERR-05, ERR-06
**Success Criteria** (observable behaviors):

  1. A token-mint `invalid_grant` response from `oauth.zettle.com/token` returns the MoneyMoney `LoginFailed` constant (string-return per spec, not `error()`), prompting the user to re-enter credentials (`ERR-01`).
  2. A transient 5xx response triggers retry-with-backoff up to 3 attempts before failing the refresh with a localized German error string (`ERR-02`).
  3. A 429 response honors the `Retry-After` header up to a sane cap; without `Retry-After`, returns a German "rate-limited, try again later" string (`ERR-03`).
  4. A 401 received **after** a successful token mint (token revoked mid-refresh) triggers exactly one silent token re-mint; only if the second attempt also 401s does the refresh fail (and it does NOT raise `LoginFailed` — that's reserved for token-mint `invalid_grant`) (`ERR-04`).
  5. A network failure (DNS / TLS / connect timeout) produces a German error string returned from `RefreshAccount`, never a Lua error or partial result; an `InitializeSession2` profile-ping at add-account time exercises the same path (`ERR-05`).
  6. Any failure inside `RefreshAccount` aborts the entire refresh — a fixture-driven test confirms that when Step-3 (payouts) fails after Step-2 (purchases) succeeded, the extension returns an error string and the next refresh re-runs both steps from the same `since` (`ERR-06`).

**Plans:** 3/5 plans executed
**UI hint:** no
**AI integration hint:** no

### Phase 6: Release & Polish — Reproducible Build, CI/CD, German Docs

**Goal:** A stranger landing on the GitHub repo can verify, install, and trust the extension in under five minutes — reproducible SHA256-attached artifact built from a GPG-signed tag, bilingual README with the unofficial-extensions enablement screenshot, GoBD-Hinweis, MADR ADRs, and a clean Conventional-Commits / Dependabot / gitleaks-gated pipeline.
**Mode:** mvp
**Depends on:** Phase 5 (complete feature set for the artifact)
**Phase-1 probe dependency:** None.
**Requirements:** BUILD-03, BUILD-04, BUILD-05, BUILD-06, CI-01, CI-02, CI-03, CI-04, CI-05, CI-06, SEC-02, SEC-05, DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07, DOC-08, DOC-09, DOC-10
**Success Criteria** (observable behaviors):

  1. Pushing a GPG-signed tag `git tag -s vX.Y.Z` triggers a release workflow that verifies the tag signature, runs lint+test+coverage+reproducible-build-diff, substitutes `__VERSION__` from the tag into the artifact, attaches `paypal-pos.lua` + `paypal-pos.lua.sha256` via `softprops/action-gh-release@v2`, and the published artifact's `WebBanking{version}` matches the tag (`BUILD-03`, `BUILD-04`, `BUILD-05`, `BUILD-06`).
  2. CI on every push/PR runs luacheck + busted + luacov on `ubuntu-24.04` with Lua 5.4 pinned and `LC_ALL=C`; coverage gate is ≥85% line coverage on `src/` excluding `webbanking_header.lua`, with a regression failing the pipeline; gitleaks (or equivalent) blocks committed secrets; Dependabot tracks tooling and Actions versions; CI builds the artifact twice in two clean checkouts and diffs them (non-empty diff fails) (`CI-01` through `CI-06`).
  3. CI greps the shipped artifact and asserts it contains no calls to hosts outside the egress allowlist (`oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`); `main` requires GPG-signed commits and CI-green via branch protection (`SEC-02`, `SEC-05`).
  4. The repo lands with a German-primary `README.de.md` whose first section is a screenshot-illustrated "Inoffizielle Extensions erlauben" guide pointing users to `Hilfe → Erweiterungen im Finder zeigen`, documenting both sandboxed and non-sandboxed install paths, including a German GoBD-Hinweis that explicitly does NOT claim conformance (`DOC-01`, `DOC-02`, `DOC-03`, `DOC-04`).
  5. `CONTRIBUTING.md` (English) documents the dev loop, testing, amalgamator, release process, and GPG-signed-tag requirement; MADR-format ADRs cover amalgamator choice, LocalStorage token cache, JWT-bearer-only auth, fee modeling, no-TLS-pinning, string-return error pattern, and sandbox probe results; `LICENSE` carries the MIT text with copyright "Yves Vogl" (`DOC-05`, `DOC-06`, `DOC-07`).
  6. The GitHub repo metadata is set via `gh repo edit`: the German description ("MoneyMoney-Extension für PayPal POS — Karten-Umsätze, Refunds, Gebühren und Auszahlungen direkt in MoneyMoney. Open Source, MIT, GPG-signiert."), the seven topics (`moneymoney`, `moneymoney-extension`, `paypal-pos`, `zettle`, `lua`, `germany`, `accounting`), and a `CHANGELOG.md` in Keep-a-Changelog format maintained per SemVer release (`DOC-08`, `DOC-09`, `DOC-10`).

**Plans:** 3 plans

Plans:
- [x] 06-01-PLAN.md — Wave 1: __VERSION__ substitution (BUILD-03) + META-03 walker extension (DOC-04) + gitleaks + commit-lint + D-79 raw-print() grep (CI-05 / D-78 / D-79 / SEC-02 hardening) — **SHIPPED 2026-06-22** (5 GPG-signed commits cc14215..6b14185; 381/0/0/0 busted; repro SHA dev 4526a33f / tagged-v1.0.0 d1afc595)
- [ ] 06-02-PLAN.md — Wave 2: release.yml (BUILD-04/05/06) + branch-protection.sh + repo-metadata.sh (SEC-05/DOC-08/09) + README.de.md/README.md split (DOC-01..04) + CONTRIBUTING.md (DOC-05) + 4 backfilled ADRs (DOC-06) + image placeholders
- [ ] 06-03-PLAN.md — Wave 3: CHANGELOG [1.0.0] cut (DOC-10) + STATE.md transition to v1.0.0-ready-for-tag + 06-HANDOFF.md post-merge/pre-tag runbook for Yves
**UI hint:** no
**AI integration hint:** no

---

## Stretch Goals (v2 — NOT v1 phases)

These are acknowledged from `REQUIREMENTS.md ## v2 Requirements` but are deliberately **not** roadmap phases — they live as future milestones to be opened once v1.0.0 has stabilized in production for several weeks.

| ID | Stretch goal | Trigger to schedule |
|----|--------------|---------------------|
| MULTI-01 | When a single merchant operates several PayPal POS terminals or locations, transactions are tagged with location metadata in `purpose`. | First real user reports the need; API exposure of location IDs verified. |
| MULTI-02 | Investigation: does the API expose location IDs, and do MoneyMoney users actually want this distinction? | Companion of MULTI-01 — runs first. |
| UP-01 | After stabilization (~v1.0 + several weeks of real-world use), submit the extension as a pull request to the official MoneyMoney extension repository so it can be RSA-signed by MRH and ship out-of-the-box. | v1.0.0 has been deployed by ≥3 users without a code-affecting bug for ≥4 weeks. |
| LOC-01 | English UI exposure (the i18n module already supports `en` strings; the locale switch and English README copy are deferred). | Demand from non-German MoneyMoney users surfaces via issues. |
| LINE-01 | Surface basket-level line-item details from the Purchase API in a non-disruptive way. | Needs UX investigation first — MoneyMoney's transaction model is the payment, not the basket. |

---

## Coverage Notes

- **Total v1 REQ-IDs in REQUIREMENTS.md:** 70.
- **Mapped to phases:** 70/70 (Phase 1: 7, Phase 2: 10, Phase 3: 10, Phase 4: 15, Phase 5: 6, Phase 6: 22). Zero orphans, zero duplicates.
- **Out-of-scope items confirmed:** MoneyMoney RSA signature (tracked as UP-01 stretch), Apple Developer ID signing, OAuth browser flow, TLS cert pinning, auto-update/telemetry, write operations, multi-merchant in one instance, non-German primary currencies, manual paid versions, live integration tests against production. See `REQUIREMENTS.md ## Out of Scope`.

---

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundations & Sandbox Probes | 0/0 | Not started | - |
| 2. Authenticated Network Layer | 7/7 | Complete   | 2026-06-19 |
| 3. Sale Spine | 0/0 | Not started | - |
| 4. Enrichment | 0/6 | Planning complete; ready to execute | - |
| 5. Resilience & Error Handling | 3/5 | In Progress|  |
| 6. Release & Polish | 0/0 | Not started | - |

---

## Dependency Graph

```
Phase 1 (Foundations + Probes)
        │
        ▼
Phase 2 (Auth + Network)        ← consumes Q2, Q5, Q6, Q8
        │
        ▼
Phase 3 (Sale Spine)            ← consumes Q4
        │
        ▼
Phase 4 (Enrichment)            ← consumes Q3
        │
        ▼
Phase 5 (Resilience)
        │
        ▼
Phase 6 (Release & Polish)
```

All phases run sequentially. No parallelization across phase boundaries — each phase's gate must be green before the next begins.

---

## Flagged Risks (for downstream `/gsd-plan-phase`)

1. **Phase 1 probe Q3** (`finance.izettle.com` host) is the single MEDIUM-confidence assumption in the entire stack. If the live probe pivots the host, Phase 4 plans must adapt (cost: rename constants in `http.lua` + `finance.lua`; low blast radius if probe runs first).
2. **Phase 3 idempotency gate** (`SALE-05` / `TEST-03`) is the single most expensive bug-class to recover from in production (MoneyMoney has no scriptable dedup repair). The double-refresh test must be green before Phase 3 is declared complete.
3. **Phase 4 fee linkage** depends on Finance API `originatingTransactionUuid` being populated in practice — if real data shows it's missing/aggregated, the FEE-03 daily-aggregate fallback is automatically engaged and Phase 4 still ships.
4. **Phase 6 reproducible build** is sensitive to runner-image drift; `ubuntu-24.04` + Lua 5.4 + `LC_ALL=C` must be pinned exactly. Dependabot updates to these are review-gated, not auto-merge.

---

*Roadmap created: 2026-06-16 via `/gsd-roadmap`. Granularity: standard. Mode: mvp. Awaiting first phase planning via `/gsd-plan-phase 1`.*

### Phase 6.1: Supply-chain & Scorecard hardening (INSERTED)

**Goal:** OpenSSF Scorecard aggregate ≥ 8.5 / 10 on `main` HEAD without compromising the project's solo-maintainer constraints; the supply-chain posture (pinned actions, least-privilege tokens, branch-protection visibility, Semgrep SAST, signed releases scaffolded in Phase 6, OpenSSF Best Practices passing badge) is documented, auditable, and stable enough to be a published prerequisite for any future v1.0.0 release.
**Mode:** mvp
**Depends on:** Phase 6 (release pipeline must exist so Signed-Releases hardening can attach)
**Requirements:** TBD — to be derived from the sprint proposal during `/gsd-discuss-phase 6.1`. Anticipated coverage: a new `SEC-05` (pinned actions), `SEC-06` (workflow token least-privilege), `SEC-07` (branch protection enforced + introspectable), `SEC-08` (SAST on every commit), `BUILD-03` (OpenSSF Best Practices passing badge), and updates to existing `SEC-04` (DEBUG=false gate) and `BUILD-01`/`BUILD-02` (Sigstore/cosign on release artifact, SLSA provenance).

**Success Criteria** (observable behaviors):

  1. `https://api.securityscorecards.dev/projects/github.com/yves-vogl/moneymoney-paypal-pos-extension` returns aggregate `score >= 8.5` for the post-merge commit.
  2. `Pinned-Dependencies` check returns score `10`: every `uses:` in `.github/workflows/*.yml` references a commit SHA followed by a `# vX.Y.Z` comment; Dependabot is configured to bump SHAs and preserve the comment tag.
  3. `Token-Permissions` check returns score `10`: every workflow declares `permissions: read-all` at top level; write-scopes (`contents: write`, `id-token: write`, `security-events: write`) are job-local and minimal.
  4. `Branch-Protection` check returns score `>= 8`: a fine-grained PAT with `Administration: read` is stored as `SCORECARD_READ_TOKEN`; `main` requires PR + status checks (CI + Scorecard + SAST) + signed commits + linear history; force-push and direct delete are blocked.
  5. `SAST` check returns score `10`: a Semgrep workflow runs on every push and PR; SARIF output is uploaded to GitHub code-scanning; the ruleset includes `p/security-audit` and `p/secrets` plus any Lua community rules.
  6. `CII-Best-Practices` check returns score `>= 5` (passing badge); badge URL is rendered in `README.md` and `README.de.md`.
  7. `docs/adr/0004-openssf-scorecard-stance.md` documents the bewusst akzeptierten Lücken (Fuzzing 0/10, Solo Code-Review 0/10, Packaging -1) with rationale and mitigations.
  8. `SECURITY.md` is extended with a "Supply-chain controls" section listing the active mitigations (pinned actions, SAST, signed releases, redact-before-log, egress allowlist) so external observers can audit the posture without parsing CI YAML.

**Plans:** TBD (run `/gsd-plan-phase 6.1` to break down)
**UI hint:** no
**AI integration hint:** no
