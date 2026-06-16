# Walking Skeleton — MoneyMoney PayPal POS Extension

**Phase:** 1
**Generated:** 2026-06-16

## Capability proven end-to-end

A maintainer drops `dist/paypal-pos.lua` (produced by `lua tools/build.lua`) into MoneyMoney's `Extensions/` folder, sees **"PayPal POS"** in "Konto hinzufügen", adds an account with any non-empty API-key string, and sees one German-labelled fixture transaction in the account view — without the extension making any network call.

The full development loop runs outside MoneyMoney: `busted spec/` is green, `luacheck .` is clean, `lua tools/build.lua --verify` exits 0 (byte-identical second build).

## Architectural decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Language / runtime | Lua 5.4 (MoneyMoney embeds 5.4.8) | Only runtime MoneyMoney supports; CI matrix pins the same. |
| Shipping shape | Single file `dist/paypal-pos.lua` amalgamated from `src/*.lua` | MoneyMoney loads extensions as top-level scripts; users drop one file into `Extensions/`. |
| Amalgamator | Custom `tools/build.lua` (~150 lines) driven by `tools/manifest.txt` | `lua-amalg` emits `package.preload`/`require`-bootstrap output incompatible with MoneyMoney's top-level-script model. |
| Module composition | Predeclared `local M_<name> = {}` tables in `src/webbanking_header.lua`; each `src/<name>.lua` wrapped in `do … end` and attaches functions to its predeclared table | Lets sibling modules reference each other without `require()`; keeps each source file independently testable. |
| Test harness | busted 2.3.0 + dkjson 2.7+, with `spec/helpers/mm_mocks.lua` injecting `Connection`, `JSON`, `MM.*`, `LocalStorage`, account-type and protocol constants into `_G` per test | CI runs without macOS / MoneyMoney; mock at the MoneyMoney-API boundary, not at the HTTP-socket boundary. |
| Lint | luacheck 1.2.0 with `std = "lua54+busted"` and MoneyMoney built-ins declared as `read_globals`; `require`/`io`/`os`/`debug` deliberately absent so any source use trips lint | Catches sandbox escapes before they reach MoneyMoney. |
| Coverage | luacov 0.16.0 with `threshold = 85` on `src/` excluding `webbanking_header.lua` | Same gate Phase 6 will enforce in CI. |
| i18n | Internal `M_i18n.t(key, ...)` with `STRINGS.de` (primary) + `STRINGS.en` (fallback, not UI-exposed in v1); locale hard-coded `"de"` | `MM.localizeText` resolves only MoneyMoney's own bundle; we own our string table. |
| Secret hygiene | `M_log.{debug,info,warn,error}` is the only print path; `M_log.redact()` strips JWT-shape, `Bearer …`, `assertion=…`, `access_token=…` before every `print()` | API key is the highest-value secret in the system; SEC-01. |
| `DEBUG` flag | `DEBUG = false` declared once at the top of the artifact; `tools/build.lua` aborts the build on `DEBUG%s*=%s*true` outside a comment in any `src/*.lua` | SEC-04 build-time gate. |
| Determinism | LF-only output, no timestamps / git SHA / `$USER` / `os.time()` reads, explicit manifest order; `LC_ALL=C` in CI; `--verify` flag double-builds and diffs SHA256 | BUILD-02; H10. |
| Probe strategy | Standalone `tools/probe.lua` extension (`bankCode == "PayPal POS Probe"`); emits Q1/Q4/Q5/Q8 results via `print()` to MoneyMoney's Protokoll panel; maintainer pastes into `docs/adr/0003-sandbox-probe-results.md` | MoneyMoney extensions cannot write files; `print()` to Protokoll is the only persistent-output channel. |

## Stack touched in Phase 1

- [x] Project scaffold — directories, configs, license, `.gitignore`, `.luacheckrc`, `.busted`, `.luacov`
- [x] Build pipeline — `tools/build.lua` + `tools/manifest.txt` produce `dist/paypal-pos.lua` deterministically
- [x] Test harness — busted runs green; `mm_mocks.lua` covers every MoneyMoney global the v1 artifact will touch
- [x] Lint — luacheck green against `src/`, `spec/`, `tools/`
- [x] Coverage — luacov reports ≥85% on `src/` (excluding `webbanking_header.lua`)
- [x] Routing — `SupportsBank` returns true for `(ProtocolWebBanking, "PayPal POS")` and false otherwise
- [x] UI surface — `InitializeSession2` registers the German API-key credential field and validates non-empty input
- [x] Read path — `ListAccounts` returns one `AccountTypeGiro` account, `RefreshAccount` returns one fixture transaction with German strings
- [x] Manual deploy — maintainer drops the artifact into `Extensions/` once and observes the fixture transaction in MoneyMoney
- [x] CI — `.github/workflows/ci.yml` runs lint, test, coverage, build, `build --verify`, DEBUG grep, egress-allowlist grep on every push and PR
- [x] Sandbox probes — `tools/probe.lua` installed once, Q1/Q4/Q5/Q7/Q8 transcribed into `docs/adr/0003-sandbox-probe-results.md`; Q2/Q3/Q6 cells left empty for Phases 2/4

## Phase-1 file set (the smallest set that lets the slice run)

```
src/
  webbanking_header.lua    # WebBanking{}, predeclared M_*, DEBUG=false
  log.lua                  # M_log.{debug,info,warn,error} + redact()
  errors.lua               # M_errors = {}  -- Phase 5 stub
  i18n.lua                 # M_i18n.t + STRINGS.de/en
  model.lua                # M_model = {}  -- Phase 3 stub
  http.lua                 # M_http = {}   -- Phase 2 stub
  auth.lua                 # M_auth = {}   -- Phase 2 stub
  pagination.lua           # M_pagination = {}  -- Phase 3 stub
  purchases.lua            # M_purchases = {}   -- Phase 3 stub
  payouts.lua              # M_payouts = {}     -- Phase 4 stub
  balance.lua              # M_balance = {}     -- Phase 4 stub
  mapping.lua              # M_mapping = {}     -- Phase 3 stub
  entry.lua                # SupportsBank, InitializeSession2, ListAccounts, RefreshAccount, EndSession

tools/
  build.lua                # Amalgamator + --verify + DEBUG gate + sandbox-call gate
  manifest.txt             # Module order
  probe.lua                # Standalone Q1/Q4/Q5/Q8 probe extension (not in manifest)

spec/
  helpers/
    mm_mocks.lua           # All MoneyMoney globals mocked
    fixtures.lua           # load(name) helper
  mm_mocks_spec.lua        # TEST-01: every global reachable & callable
  log_redaction_spec.lua   # SEC-01: redactor strips JWT/Bearer/assertion/access_token
  i18n_spec.lua            # I18N-02 + I18N-03: t() and key-parity
  build_spec.lua           # BUILD-01 + BUILD-02 + SEC-04: build, --verify, DEBUG-grep
  entry_spec.lua           # Walking-skeleton: SupportsBank, InitializeSession2, ListAccounts, RefreshAccount

docs/adr/
  0001-amalgamator-design.md           # filled
  0003-sandbox-probe-results.md        # template, filled by maintainer post-probe

.github/workflows/ci.yml
.luacheckrc
.busted
.luacov
.gitignore                              # includes dist/, luacov.*
LICENSE                                 # MIT, copyright Yves Vogl
dist/                                   # gitignored output directory (created by build)
```

Total tracked-in-git additions for Phase 1: 13 source files + 3 tools files + 5 spec files + 2 helpers + 2 ADRs + 1 CI workflow + 4 root configs + LICENSE = 31 files.

## Behaviors the slice proves

1. The repo builds: `lua tools/build.lua` exits 0 and writes `dist/paypal-pos.lua`.
2. The build is reproducible: `lua tools/build.lua --verify` exits 0 with "OK: reproducible".
3. The build refuses a debug-flagged source: a `src/*.lua` containing `DEBUG = true` outside a comment causes `lua tools/build.lua` to exit non-zero with a clear error.
4. The build refuses a sandbox-illegal source: any `src/*.lua` containing `require(`, `dofile(`, `loadfile(`, `io.open(`, `os.execute(`, or `io.popen(` causes `lua tools/build.lua` to exit non-zero.
5. The test suite passes: `busted spec/` is green from a clean checkout with only `dkjson` as the external runtime dep.
6. Lint is clean: `luacheck .` exits 0 against `.luacheckrc`.
7. Coverage holds: `busted --coverage spec/` produces a luacov report with ≥85% line coverage on `src/` excluding `webbanking_header.lua`.
8. The redactor works: `M_log.info("Bearer eyJabc.def.ghi assertion=eyJxyz.uvw.rst")` produces a `print()` output containing neither `eyJ`, nor `Bearer ` followed by a JWT, nor `assertion=eyJ…`.
9. The i18n table is complete: every key in `STRINGS.de` exists in `STRINGS.en`; `M_i18n.t("account.name", "X")` returns a German-language string interpolated with `"X"`.
10. The walking-skeleton entry points behave: `SupportsBank` discriminates correctly; empty credential → German `LoginFailed` (-equivalent error string per AUTH-03 will land in Phase 2 — Phase 1 just returns the German error string from `M_i18n.t("error.invalid_grant")`); `ListAccounts` returns exactly one `AccountTypeGiro` with `currency="EUR"`; `RefreshAccount` returns one transaction with `transactionCode` matching `^zettle:sale:` and `currency="EUR"`.
11. Manual install works: dropping `dist/paypal-pos.lua` into `Extensions/` surfaces "PayPal POS" in "Konto hinzufügen" and shows the fixture transaction once an account is added.
12. The sandbox is mapped: `docs/adr/0003-sandbox-probe-results.md` is filled in for Q1, Q4, Q5, Q7, Q8.

## Tests that gate the slice

| Spec file | Gates |
|-----------|-------|
| `spec/build_spec.lua` | BUILD-01, BUILD-02, SEC-04 (positive + negative DEBUG gate), sandbox-call grep gate |
| `spec/mm_mocks_spec.lua` | TEST-01 (mock surface) |
| `spec/log_redaction_spec.lua` | SEC-01 (four redaction cases: JWT, Bearer, assertion=, access_token=) |
| `spec/i18n_spec.lua` | I18N-02 (German default + interpolation), I18N-03 (DE/EN key parity) |
| `spec/entry_spec.lua` | Walking-skeleton: SupportsBank discrimination, InitializeSession2 empty-cred path, ListAccounts shape, RefreshAccount shape and `transactionCode` prefix |

Plus the build-time greps inside `tools/build.lua` (SEC-04 + sandbox-illegal-call gate) — these run on every developer build and every CI invocation.

## Out of scope (deferred to later slices)

| Item | Lands in |
|------|----------|
| Any real HTTPS call from the amalgamated artifact | Phase 2 (`src/http.lua`, `src/auth.lua`) |
| `LocalStorage` read/write logic | Phase 2 (token cache) |
| OAuth JWT-bearer round-trip against `oauth.zettle.com/token` | Phase 2 |
| `LoginFailed` constant return on `invalid_grant` | Phase 2 (semantic), Phase 5 (full error taxonomy) |
| Real `ListAccounts` (one account per merchant, real `userId`-derived `accountNumber`, merchant-name label) | Phase 2 (`ACCT-01`, `ACCT-02`, `ACCT-04`) |
| Real `RefreshAccount` (Purchase API call, pagination, mapping, stable `transactionCode`, idempotency) | Phase 3 |
| Refunds, fees, payouts, balance, VAT/tip rendering | Phase 4 |
| Retry/backoff, 429 `Retry-After`, post-mint 401 silent re-mint, fail-whole-refresh enforcement | Phase 5 |
| `__VERSION__` tag-time substitution, GPG-tag-triggered release, SHA256 release asset, gitleaks, Dependabot, branch protection | Phase 6 |
| Bilingual README, GoBD-Hinweis, install-path screenshots, ADRs 0002 / 0004 / 0005 / 0006 | Phase 6 |
| Q2 (redirect behavior), Q3 (Finance host), Q6 (`client_id`) live answers | Phase 2 (Q2, Q6), Phase 4 (Q3) — cells left empty in ADR-0003 after Phase 1 |
| MRH RSA signature, Apple Developer ID code-signing of the `.lua` | Permanently out of scope per `PROJECT.md ## Out of Scope` |

## Subsequent slice plan

Each later phase adds one vertical slice on top of this skeleton without changing its architectural decisions:

- **Phase 2** — A merchant pastes a real API key into "Konto hinzufügen", the extension authenticates against `oauth.zettle.com/token`, a wrong key fails synchronously with `LoginFailed`, the merchant's account surfaces in MoneyMoney's sidebar with the merchant's name. The token cache lands in `LocalStorage`. No transactions yet.
- **Phase 3** — `RefreshAccount` calls the Purchase API and returns real card sales as MoneyMoney transactions with stable `zettle:sale:<purchaseUUID1>` IDs. Double-refresh produces zero duplicates. This is the first user-visible end-to-end demo.
- **Phase 4** — Refunds, per-sale fees via Finance API, payouts, settled-vs-pending balance, multi-line German `purpose` with VAT split and tip line.
- **Phase 5** — Every error category (token-mint `invalid_grant`, post-mint 401, 429, 5xx, network) returns a localized German error string from `RefreshAccount` and never advances `since` past undelivered data.
- **Phase 6** — Tag-triggered reproducible release: GPG-verified tag → byte-identical artifact + SHA256 → published via `softprops/action-gh-release@v2`; bilingual README; full MADR ADR set; gitleaks; Dependabot; branch protection on `main`.

## Exit criterion ("alive")

Phase 1 is **alive** when all five conditions hold simultaneously:

1. `busted spec/` is green.
2. `luacheck .` exits 0.
3. `lua tools/build.lua` exits 0 and `lua tools/build.lua --verify` exits 0.
4. The maintainer has manually loaded `dist/paypal-pos.lua` in MoneyMoney once and confirmed "PayPal POS" appears in "Konto hinzufügen", an account can be added with a dummy key, and the fixture transaction is visible.
5. `docs/adr/0003-sandbox-probe-results.md` has rows Q1, Q4, Q5, Q7, Q8 filled in from a live probe-extension run (Q2, Q3, Q6 may remain empty — they are owned by Phases 2/4).
