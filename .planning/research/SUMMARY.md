# Project Research Summary

**Project:** MoneyMoney PayPal POS Extension
**Domain:** MoneyMoney community extension (single-file Lua) wrapping the PayPal POS / Zettle Public API for German merchants
**Researched:** 2026-06-16
**Granularity:** `standard` (5–8 phases per `.planning/config.json`)
**Confidence:** HIGH overall

---

## 1. TL;DR

1. **Stack is decided:** single hand-written `Extension.lua` against MoneyMoney's embedded Lua 5.4.8; built/tested outside MoneyMoney on busted 2.3.0 + luacheck 1.2.0 + luacov 0.16.0; CI via `leafo/gh-actions-{lua,luarocks}` + `softprops/action-gh-release@v2`. No external Lua modules in the shipped file. Source is modular under `src/` and amalgamated by a ~150-line custom `tools/build.lua` (NOT `lua-amalg` — MoneyMoney loads as top-level script, not via `require`).
2. **Auth is decided:** JWT-bearer grant against `POST https://oauth.zettle.com/token` with `assertion=<API_KEY>`; 7200 s TTL; re-mint on cache miss (no refresh-token rotation); token cached in `LocalStorage`, API key never persisted by us (MoneyMoney's credentials store owns it).
3. **API surface is decided:** Purchase API (`purchase.izettle.com/purchases/v2`, cursor `lastPurchaseHash`) for sales/refunds; Finance API (`finance.izettle.com/v2/accounts/liquid/...`) for fees, payouts, balance. Per-sale fee linkage via Finance API `originatingTransactionUuid` is feasible — PROJECT.md's "otherwise daily aggregate" caveat is now a documented fallback, not the primary path.
4. **Identity is decided:** `purchaseUUID1` (NOT `purchaseUUID`, NOT `purchaseNumber`). Used to drive `transactionCode = "zettle:<kind>:<uuid>"` and to dedupe on double-refresh.
5. **Mapping is decided:** sale = gross transaction; refund / fee / payout = separate negative transactions; VAT from `groupedVatAmounts` and tip from `payments[].gratuityAmount` rendered into multi-line `purpose` in German.
6. **Error model is decided:** `return LoginFailed` (string-return per spec, not `error()`), only on token-mint `invalid_grant`. Transient 401/429/5xx → localized string from `RefreshAccount`, never partial data (preserves `since` watermark invariant).
7. **MVP is `v0.1.0`** (Phase 1–3 done, sandbox-verified); **v1.0.0** adds CI/CD hardening, German polish, README, GoBD-Hinweis, reproducible build with SHA256 + GPG-signed tag.
8. **8 critical Phase-1 probes must run live before the rest of the design hardens** — see § 5.
9. **Phase count is 6** (reconciles FEATURES=5 / ARCH=6 / PITFALLS=8 divergence under `granularity=standard`).
10. **Highest single risk:** unstable transaction identity → MoneyMoney creates phantom duplicates that cannot be cleaned scriptably. Mitigation is a non-negotiable double-refresh idempotency test gating Phase 3.

---

## 2. Canonical Decisions

| # | Decision | Value |
|---|----------|-------|
| D1 | Lua runtime | **Lua 5.4.8** (MoneyMoney embedded) |
| D2 | Shipping shape | Single `Extension.lua` generated from `src/*.lua`; no `require` in artifact |
| D3 | Amalgamator | Custom ~150-line `tools/build.lua` with `tools/manifest.txt` |
| D4 | Test stack | busted 2.3.0, luacheck 1.2.0, luacov 0.16.0, dkjson 2.7+ |
| D5 | CI actions | `leafo/gh-actions-lua@v13`, `leafo/gh-actions-luarocks@v6.1.0`, `softprops/action-gh-release@v2` |
| D6 | Coverage gate | ≥85% on `src/` (excluding `webbanking_header.lua`) |
| D7 | OAuth flow | `POST oauth.zettle.com/token`, `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`, `client_id`, `assertion=<API_KEY>` |
| D8 | Token TTL | 7200 s; invalidate 60 s before expiry; **no refresh-token rotation** |
| D9 | Token storage | `LocalStorage.zettle = { access_token, expires_at, obtained_at, client_id }` |
| D10 | API key storage | Read from `credentials` arg each session; never copied to `LocalStorage`/disk |
| D11 | Purchase API host | `https://purchase.izettle.com/purchases/v2` |
| D12 | Finance API host | `https://finance.izettle.com/v2/accounts/liquid/...` — **MEDIUM**, Phase-1 probe required |
| D13 | Purchase pagination | `lastPurchaseHash` cursor + `limit=1000` + `descending=false`; stop when count<limit AND no `rel="next"` |
| D14 | Finance pagination | Offset-based |
| D15 | Identity field | `purchaseUUID1`; `transactionCode = "zettle:<kind>:<uuid>"` |
| D16 | Account type | `AccountTypeGiro` with `balance` + `pendingBalance` |
| D17 | Transaction granularity | Sale (gross) / Refund (neg, refs original) / Fee (neg) / Payout (neg, "Auszahlung an Bankkonto") |
| D18 | Fee modeling — PRIMARY | Per-sale via Finance API `originatingTransactionUuid` |
| D19 | Fee modeling — FALLBACK | Daily-aggregate with `purpose = "PayPal POS Transaktionsgebühren <date>"` |
| D20 | VAT in `purpose` | Multi-line German from `groupedVatAmounts` per rate |
| D21 | Tip in `purpose` | Aggregate `payments[].gratuityAmount`; render `"Trinkgeld: X,YY EUR"`; omitted when zero; never classified |
| D22 | Date mapping | `bookingDate=timestamp(UTC→POSIX)`; `valueDate=payout-date if linked else bookingDate`; `booked=false` until linked |
| D23 | Currency math | Minor→major via `10^minor_units(currency)`; EUR ÷100; guard throws on unknown currency |
| D24 | Error pattern | `return LoginFailed` (NOT `error()`) only on token-mint `invalid_grant`; transient → localized German string |
| D25 | Partial-fetch policy | **Fail whole refresh** on any sub-step failure |
| D26 | i18n | Own `i18n.t(key)` with `de`/`en` tables; NOT `MM.localizeText` for our keys; default `"de"` |
| D27 | Secret redaction | `log.redact()` applied to all strings before `print`; strips JWT-shape and `Bearer …`; `DEBUG=false` in shipped build |
| D28 | Egress allowlist | `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com` only; enforced in `Connection()` wrapper + CI grep |
| D29 | Sandbox/prod | Production URLs hard-coded; sandbox injected at build time for CI only; no env toggle in UI |
| D30 | Account label | `name = "PayPal POS — <merchant-name>"` for multi-instance distinguishability |
| D31 | Reproducible build | LF normalization, explicit manifest, no timestamps/SHA/env leakage; CI builds twice + diffs |
| D32 | Tag signing | Maintainer signs locally with GPG `FDE07046A6178E89ADB57FD3DE300C53D8E18642`; CI verifies, never signs |
| D33 | Version source | Git tag → `__VERSION__` substitution at build; test asserts artifact==tag |
| D34 | Install path | Sandboxed: `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/`. Non-sandboxed: `~/Library/Application Support/MoneyMoney/Extensions/`. README documents both. |
| D35 | Onboarding | README top: "Inoffizielle Extensions erlauben" screenshot with red arrow, German first |
| D36 | GoBD posture | Explicit "GoBD-Hinweis" section; never claim "GoBD-conform" |
| D37 | Tag workflow | Manual `git tag -s` + push; CI `on.push.tags` builds + releases |

---

## 3. PROJECT.md Drift / Corrections Needed

| # | PROJECT.md says | Research says | Action |
|---|-----------------|---------------|--------|
| C1 | "fee booked per-sale if API exposes it, otherwise daily aggregate" | Finance API `originatingTransactionUuid` exposes per-sale; per-sale is **primary**, daily-aggregate is fallback | Reword to put per-sale as primary; daily-aggregate as documented fallback |
| C2 | "Auth: ... likely `assertion`-grant on `oauth.zettle.com/token`" | Confirmed JWT-bearer assertion grant, 7200 s, no refresh-token | Remove hedging |
| C3 | "Lua 5.x" | Lua 5.4.8 in current MoneyMoney | Tighten to "Lua 5.4 (currently 5.4.8); CI matrix pins same" |
| C4 | "If we split source..." | Source IS split under `src/`; `tools/build.lua` amalgamates | Make declarative |
| C5 | 30 s refresh budget | Applies to **incremental** only; first-time 3-year sync is multi-cycle and documented | Clarify scope |
| C6 | "Auth via `InitializeSession2`" | Add fail-fast profile-ping in `InitializeSession2` | Add Key Decisions row |
| C7 | Silent on TLS cert pinning | Explicitly NOT attempted; rely on MoneyMoney `Connection()` | Add Out-of-Scope line |
| C8 | Silent on auto-update pings | Disallowed; egress allowlist enforced | Add Out-of-Scope line |
| C9 | No mention of "Hilfe → Erweiterungen im Finder zeigen" | Should be the canonical install-folder discovery in README | Add to Context |

---

## 4. Top 10 Hard Pitfalls

| # | Pitfall | Mitigation | Owns |
|---|---------|------------|------|
| H1 | Unstable transaction identity → duplicates | `purchaseUUID1` in `transactionCode`; **double-refresh idempotency test** gates phase exit | Phase 3 |
| H2 | Incomplete transaction records | Single `buildTransaction()` helper; golden-file schema test | Phase 3 |
| H3 | `bookingDate` vs `valueDate` confusion | `bookingDate=timestamp`; `valueDate=payout-date-if-linked`; `booked=false` until linked | Phase 3, 4 |
| H4 | Pagination cursor mishandling | `descending=false`; stop on count<limit AND no `rel="next"`; off-by-one fixture; 50-page cap with warning | Phase 4 |
| H5 | Wrong OAuth grant type | Hard-code JWT-bearer per Zettle spec; sandbox integration test; **Phase-1 probe** | Phase 2 |
| H6 | Wrong error type (raising `LoginFailed` on transient 401) | Only token-mint `invalid_grant` → `LoginFailed`; post-mint 401 → silent re-mint | Phase 5 |
| H7 | API key leaked in error/log | `log.redact()` applied to all strings; CI grep blocks unguarded `print`; auth-fail test asserts no JWT in error | Phase 2 |
| H8 | Lua sandbox surprises | **Phase-1 probe** enumerates `_G`; pins to ADR; artifact has zero `require` | Phase 1 |
| H9 | Sandbox/prod conflation | Production URLs hard-coded; CI grep asserts no `sandbox` in artifact | Phase 6 |
| H10 | Non-reproducible build / version desync | Deterministic amalgamator; CI builds twice + diffs; `__VERSION__` from tag; assertion test | Phase 6 |

---

## 5. Phase-1 Probes (live verifications gating further design)

| # | Probe | Confirms | Failure pivot |
|---|-------|----------|---------------|
| Q1 | Lua sandbox globals (`require`, `os.execute`, `io.popen`, `package.loadlib`, `dofile`, `loadfile`, `debug.*`) | What's safe to use; pinned in ADR | We still don't use `require` even if present |
| Q2 | `Connection():request` 302-redirect behavior on `oauth.zettle.com/token` | Whether auth needs explicit redirect loop | If no auto-follow: add max-3-hop loop in `http.lua` |
| Q3 | `finance.izettle.com` host with `GET /v2/accounts/liquid/balance` | The MEDIUM-confidence host (D12) | Pull actual host from Postman bundle and pin |
| Q4 | `JSON():set(t):json()` integer round-trip with `amount=995` | Minor-unit amounts stay integer (no float coercion) | Hand-format with `string.format("%d", v)` |
| Q5 | `LocalStorage` cross-restart persistence | Token cache survives app restart | Worst case: cache becomes module-local; design robust |
| Q6 | PayPal POS first-party `client_id` value | The constant we ship in `auth.lua` | If region-specific: constants table, default EU |
| Q7 | `services = {"PayPal POS"}` label rendering in MM German UI | Label is unambiguous | If ambiguous: `"PayPal POS (Zettle)"` |
| Q8 | `Connection()` TLS verification default (badssl.com test) | Verifies against system trust store; no cert pinning needed | If off by default: blocking MoneyMoney bug |

Probe outputs → `docs/adr/0003-sandbox-probe-results.md`.

---

## 6. MVP vs v1.0 Scope

### v0.1.0 — MVP (sandbox-verified)

- Single-file build pipeline working (`tools/build.lua` + mocks)
- Auth: JWT-bearer, `LocalStorage` cache, `LoginFailed` on `invalid_grant`
- `SupportsBank`, `InitializeSession2`, `ListAccounts` (Giro + balance), `RefreshAccount` (sales only), `EndSession`
- Sale-as-transaction with stable `transactionCode`
- Multi-line German `purpose` (gross + UUID; VAT/tip preferred but acceptable to defer)
- Incremental refresh honoring `since`
- busted + luacheck + luacov green; ≥85% coverage

### v1.0.0 — Launch target

Adds all PROJECT.md Active items:
- Refunds with original-receipt reference
- Per-sale fees via Finance API; daily-aggregate documented fallback
- Payouts as "Auszahlung an Bankkonto"
- `pendingBalance` from Finance API
- VAT-split per `groupedVatAmounts` in `purpose`
- Tip from `payments[].gratuityAmount`
- All 5 error categories per D24
- Egress allowlist enforced
- Reproducible build, byte-identical CI artifact, SHA256 file
- GPG-signed tag, `softprops/action-gh-release@v2`
- Bilingual README (DE primary, EN contributor), GoBD-Hinweis, "Inoffizielle Extensions erlauben" screenshot, both install paths
- MADR ADRs for major decisions (amalgamator, LocalStorage, JWT-bearer-only, fee modeling, no TLS pinning, string-return error pattern)
- Conventional Commits enforced via GitHub Action

---

## 7. Recommended Phase Structure — 6 phases

**Reconciliation:** FEATURES=5, ARCH=6, PITFALLS labeled 1–8. Under `granularity=standard` (5–8), **6** is right: follows ARCH §14 directly, dependency-ordered, each phase a coherent shippable unit. PITFALLS 1–8 numbering is a labeling artifact; mitigations map onto these 6 phases without loss.

### Phase 1 — Foundations & Sandbox Probes
**Rationale:** Settles MEDIUM-confidence assumptions; stands up dev/test toolchain. Nothing else locks in without these.
**Delivers:** Repo skeleton (`src/`, `spec/`, `tools/`, minimal `ci.yml`, `.luacheckrc`, `.busted`, `.luacov`); `tools/build.lua` + manifest; `spec/helpers/mm_mocks.lua`; `model`, `i18n`, `errors`, `log` with redaction; probe extension + ADR `0003-sandbox-probe-results.md`.
**Addresses:** D1–D6, D26, D27, D31; Q1–Q8.
**Avoids:** H7, H8, partial H10.
**Gate:** busted runs; `lua tools/build.lua --verify` produces byte-identical output twice; all 8 probes in ADR.

### Phase 2 — Authenticated Network Layer
**Rationale:** Auth is the chokepoint; every later phase depends on it. Network layer is the substrate.
**Delivers:** `http.lua` (Connection wrapper, hostname allowlist, retries/backoff, redirect handling per Q2), `auth.lua` (JWT-bearer, LocalStorage cache), `pagination.lua` (cursor + Finance offset iterators). Mocked Connection + one live sandbox token-exchange spike.
**Addresses:** D7–D14, D24 (partial), D28.
**Avoids:** H5, H7, partial H4.
**Gate:** Auth round-trip with cache hit/miss; `invalid_grant` → `LoginFailed`; allowlist rejects unknown host; no JWT in any error string.

### Phase 3 — Sale Spine
**Rationale:** Sale-as-transaction is the spine — everything else hangs off it. Highest-risk single phase (H1).
**Delivers:** `purchases.lua` (cursor pagination, `descending=false`), `mapping.lua` (pure record→MM transaction), canonical `buildTransaction()` helper, `webbanking_header.lua`, `entry.lua` shells, e2e `RefreshAccount` returning sales only.
**Addresses:** D15, D16, D17 (sale only), D22, D23, D25, D30.
**Avoids:** H1 (double-refresh idempotency test gates exit), H2 (golden-file schema test), H3, H4.
**Gate:** Double-refresh = zero new transactions; golden-file schema test; pending sales `booked=false`; umlaut + minor-unit fixtures pass.

### Phase 4 — Enrichment: VAT, Tip, Refunds, Fees, Payouts, Balance
**Rationale:** These layer onto the spine; group because they share Finance API integration and `purpose` template.
**Delivers:** `payouts.lua`, `balance.lua`, Finance API integration with `originatingTransactionUuid` fee linkage, refund mapping with `refundsPurchaseUUID1`→receipt resolution, VAT-split from `groupedVatAmounts`, tip from `payments[].gratuityAmount`, full multi-line German `purpose`.
**Addresses:** D17 (full), D18, D19, D20, D21.
**Avoids:** Pitfalls 10, 11, 12; partial H3.
**Gate:** All 4 transaction kinds in e2e fixture test; per-rate VAT split tested; tip omitted when zero; partial-refund covered; per-sale fee linked OR fallback engaged with clear log line.

### Phase 5 — Resilience & Error Handling
**Rationale:** Harden against the 5 error categories. Partial-fetch policy must be enforced everywhere or watermark invariant silently breaks.
**Delivers:** Branched error handling per D24, retry-with-backoff on 5xx (max 3), `Retry-After` honoring on 429, token-revoked recovery (single re-mint), fail-whole-refresh enforcement, lightweight ping in `InitializeSession2`.
**Addresses:** D24, D25; C6.
**Avoids:** H6, H4 (hard pagination cap with warning).
**Gate:** Tests for all 5 categories (401-token, 401-post-token, 429, 5xx, network); bad-key `InitializeSession2` → `LoginFailed` synchronously; no test path returns partial list.

### Phase 6 — Reproducible Release, German Polish, Docs
**Rationale:** Production hardening. Reproducibility (H10) and German polish are non-negotiable for the trust model.
**Delivers:** `release.yml` (tag-triggered, GPG verification, `softprops/action-gh-release@v2`, SHA256, `__VERSION__` substitution), CI pinned to ubuntu-24.04 + Lua 5.4 + `LC_ALL=C`, twice-build diff, `gitleaks` hook in CONTRIBUTING.md, bilingual `README.de.md` + `README.md`, "Inoffizielle Extensions erlauben" screenshot, GoBD-Hinweis, install paths, MADR ADRs `0001-amalgamator.md`, `0002-localstorage-token-cache.md`, `0003-sandbox-probe-results.md`, `0004-fee-modeling-finance-api.md`, `0005-tls-no-pinning.md`, `0006-error-pattern-string-return.md`.
**Addresses:** D29, D31–D37; C5, C7, C8, C9.
**Avoids:** H9, H10.
**Gate:** `git verify-tag v1.0.0` succeeds; CI builds twice byte-identical; SHA256 attached; fresh-user install verified; `WebBanking{version}` == tag.

### Phase Ordering Rationale
- Strict chain Phase 1→2→3 (probes → network/auth → spine); nothing parallelizable across.
- Phase 4↔5: enrichment first because resilience tests need real paths to harden.
- Phase 6 last because reproducibility is meaningful only over real code; README needs final feature set.
- 6 sits cleanly in `standard` 5–8 band; mirrors ARCH §14.

### Research Flags
| Phase | Needs `--research-phase`? | Why |
|-------|---------------------------|-----|
| 1 | **YES — probes** | Q1–Q8 gate the phase |
| 2 | NO | JWT-bearer fully specified |
| 3 | LIGHT | Verify `purchaseUUID1` stability on real refresh |
| 4 | LIGHT | Confirm `originatingTransactionUuid` shape on live Finance call; verify `gratuityAmount` location |
| 5 | NO | Standard patterns |
| 6 | NO | Reproducible-build + GPG patterns well-documented |

---

## 8. Open Questions Deferred to Phase-Specific Research

1. Exact PayPal POS first-party `client_id` — Q6 (Phase 1); if region-specific, constants table.
2. `finance.izettle.com` host confirmation — Q3.
3. `Connection():request` redirect behavior — Q2.
4. JSON integer round-trip — Q4.
5. `LocalStorage` cross-restart persistence — Q5.
6. `payments[].commission.totalAmount` (Purchase API) vs Finance API `PAYMENT_FEE` — both exist; use Finance API for booking, Purchase API only as display metadata; verify in Phase 4 that they agree to the cent.
7. Zettle rate-limit specific quotas — undocumented; defensive caps in code; revisit Phase 5 if 429s observed.
8. MM UI label for `services = {"PayPal POS"}` — Q7.
9. Locale-detection heuristic reliability (`MM.localizeText("OK")` round-trip) — verify Phase 1; fall back to hard-coded `"de"`.
10. First-time refresh UX / progress signaling — what `MM.printStatus` hooks are available; investigate Phase 5.
11. What `WebBanking{version = X.YY}` actually pins — survey existing extensions; Phase 6 ADR.
12. GoBD wording — placeholder in Phase 6, polish before release with German-tax-aware review.

---

## 9. Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | **HIGH** | All techs verified against primary sources |
| Features | **HIGH** | 3 reference PSP extensions read in full; Zettle Purchase/Finance fields verified against `purchase.adoc`; German VAT context cited with explicit BMF-non-definitive caveat |
| Architecture | **HIGH** | All MM callback contracts from official ref; LocalStorage prior-art (truelayer); string-return pattern (union-investment) directly inspected; amalgamator grounded in lua-amalg analysis |
| Pitfalls | **HIGH** for MM semantics + Zettle API; **MEDIUM** for Lua sandbox (P17 pinned by Q1) and rate-limit quotas (defensive caps) |

**Overall: HIGH.** All non-HIGH items have planned resolution points (Q1–Q8 or §8). No gap blocks the roadmap.

---

## 10. Sources (consolidated)

### MoneyMoney
- https://moneymoney.app/api/webbanking/ — HIGH
- https://moneymoney.app/extensions/ — HIGH (no PayPal/Zettle entry 2026-06)
- https://github.com/jgoldhammer/moneymoney-payback — HIGH
- https://github.com/teal-bauer/moneymoney-ext-trading212 — HIGH
- https://github.com/miracle2k/moneymoney-truelayer — HIGH (LocalStorage token pattern)
- https://github.com/joafeldmann/moneymoney-union-investment — HIGH (`return LoginFailed`)

### PayPal POS / Zettle
- https://github.com/iZettle/api-documentation/blob/master/authorization.md — HIGH
- https://github.com/iZettle/api-documentation/blob/master/oauth-api/user-guides/set-up-app-authorisation/set-up-authorisation-assertion-grant.md — HIGH
- https://github.com/iZettle/api-documentation/blob/master/oauth-api/user-guides/create-an-app/create-a-self-hosted-app/create-an-api-key.md — HIGH
- https://github.com/iZettle/api-documentation/blob/master/purchase.adoc — HIGH
- https://github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-account-transactions-v2.md — HIGH (path); MEDIUM (host)
- https://github.com/iZettle/api-documentation/blob/master/finance-api/overview.md — HIGH
- https://developer.zettle.com/docs/api/purchase/user-guides/fetch-purchases/fetch-a-list-of-purchases — HIGH
- https://developer.zettle.com/docs/api/purchase/api-reference-md — HIGH
- https://developer.zettle.com/docs/api/finance/overview — HIGH
- https://developer.zettle.com/docs/api/finance/user-guides/fetch-payout-info — HIGH
- https://developer.zettle.com/docs/api/oauth/user-guides/set-up-app-authorisation/set-up-authorisation-assertion-grant — HIGH
- https://www.zettle.com/de/rechtshinweise/zahlungsbedingungen — HIGH (PayPal Luxembourg entity)

### Standards
- https://tools.ietf.org/html/rfc7523 — HIGH (JWT Profile for OAuth 2.0)
- https://reproducible-builds.org/docs/source-date-epoch/ — HIGH

### Lua tooling & amalgamation
- https://luarocks.org/modules/lunarmodules/busted — HIGH (2.3.0)
- https://luarocks.org/modules/lunarmodules/luacheck — HIGH (1.2.0)
- https://luarocks.org/modules/hisham/luacov — HIGH (0.16.0)
- https://github.com/leafo/gh-actions-lua — HIGH (v13)
- https://github.com/leafo/gh-actions-luarocks — HIGH (v6.1.0)
- https://github.com/softprops/action-gh-release — HIGH (v2)
- https://github.com/siffiejoe/lua-amalg — HIGH (canonical; rejected for top-level-script host)

---

*Research synthesis for: MoneyMoney PayPal POS / Zettle community extension. Synthesized: 2026-06-16. Ready for roadmap.*
