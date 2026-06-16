# Phase 1 — Locked Context

**Phase:** 1 — Foundations & Sandbox Probes
**Locked:** 2026-06-16
**Status:** Pending (first executable phase)

---

## Phase scope (in)

| # | In scope | Source |
|---|----------|--------|
| 1 | Repo skeleton: `src/`, `spec/`, `tools/`, `docs/adr/`, `.github/workflows/`, `dist/` (gitignored), `LICENSE` (MIT, Yves Vogl), root configs `.luacheckrc`, `.busted`, `.luacov`, `.gitignore` | RESEARCH §Recommended Project Structure |
| 2 | 13 source modules under `src/` per RESEARCH §Module-by-Module File Inventory (`webbanking_header`, `log`, `errors`, `i18n`, `model`, `http`, `auth`, `pagination`, `purchases`, `payouts`, `balance`, `mapping`, `entry`) — Phase 2–4 modules ship as empty `M_* = {}` stubs | RESEARCH RQ-1, §Inventory |
| 3 | Custom amalgamator `tools/build.lua` + `tools/manifest.txt` producing `dist/paypal-pos.lua`; `--verify` flag double-builds and diffs SHA256; LF-normalized, no timestamps, no git SHA, no `$USER` | BUILD-01, BUILD-02; RESEARCH RQ-1 |
| 4 | Build-time gates inside `tools/build.lua`: (a) abort on `DEBUG%s*=%s*true` outside comments; (b) abort on `require(`, `dofile(`, `loadfile(`, `io.open(`, `os.execute(`, `io.popen(` anywhere in `src/` | SEC-04; H8; RESEARCH RQ-4, RQ-10 |
| 5 | `spec/helpers/mm_mocks.lua` covering every MoneyMoney global the v1 artifact will touch (full table in RESEARCH RQ-2); `Mocks.setup()`/`Mocks.teardown()`; `Mocks.push_response()` queue; `_response_queue` and `LocalStorage` reset between tests | TEST-01; RESEARCH RQ-2 |
| 6 | `src/log.lua` with `M_log.{debug,info,warn,error}` and `M_log.redact()` stripping JWT-shape, `Bearer …`, `assertion=…`, `access_token=…`; no bare `print()` in `src/` outside `M_log` | SEC-01; RESEARCH RQ-4 |
| 7 | `src/i18n.lua` with `STRINGS.de` (primary), `STRINGS.en` (fallback, never UI-exposed in v1), `M_i18n.t(key, ...)`; locale hard-coded `"de"`; key set from RESEARCH RQ-3 | I18N-02, I18N-03; RESEARCH RQ-3 |
| 8 | Walking-skeleton `src/entry.lua`: `SupportsBank`, `InitializeSession2` (non-empty-credential check, no network), `ListAccounts` (one fixture `AccountTypeGiro`, `currency="EUR"`), `RefreshAccount` (one fixture transaction with German strings via `M_i18n.t`), `EndSession` — zero network calls | RESEARCH §Walking-Skeleton Entry Module |
| 9 | `src/webbanking_header.lua`: `WebBanking{}` registration with `services = {"PayPal POS"}`, `country = "de"`, `version = 0.00` (Phase-6 substitutes `__VERSION__`), `DEBUG = false`, all `M_*` table predeclarations | RESEARCH RQ-1, RQ-5 |
| 10 | busted specs: `mm_mocks_spec`, `log_redaction_spec`, `i18n_spec`, `build_spec`, `entry_spec` — coverage gate ≥85% on `src/` excluding `webbanking_header.lua` | TEST-01; CI-02 (Phase 6 hardens further) |
| 11 | Minimum-viable CI workflow `.github/workflows/ci.yml`: setup Lua 5.4 via `leafo/gh-actions-lua@v13` + `leafo/gh-actions-luarocks@v6.1.0`, install busted/luacheck/luacov/dkjson, run lint + tests + coverage + `build` + `build --verify` + DEBUG grep + egress-allowlist grep; `LC_ALL=C` | RESEARCH RQ-7 |
| 12 | Probe extension `tools/probe.lua`: standalone, `bankCode == "PayPal POS Probe"`, runs Q1/Q4/Q5/Q8 via `print()` to MoneyMoney's Protokoll panel; Q2/Q3/Q6 noted as Phase 2/4 work; not part of the amalgamation, not shipped | RESEARCH RQ-6 |
| 13 | ADRs scaffolded: `docs/adr/0001-amalgamator-design.md` (filled — documents `lua-amalg` rejection + custom builder); `docs/adr/0003-sandbox-probe-results.md` (template per RESEARCH RQ-8, populated by maintainer after running the probe) | RESEARCH RQ-8; DOC-06 (partial — full set in Phase 6) |
| 14 | Walking-skeleton manual verification: maintainer drops `dist/paypal-pos.lua` into MoneyMoney's `Extensions/` once, observes "PayPal POS" in "Konto hinzufügen", adds an account with any non-empty key, sees the fixture transaction; this counts as the human verification step | RESEARCH §Walking-Skeleton Entry Module |

## Phase scope (out)

| Item | Reason |
|------|--------|
| Any real network call from the amalgamated artifact | Phase 2 — auth/HTTP layer |
| `LocalStorage` read/write logic | Phase 2 — token cache |
| Error categorisation (`LoginFailed`, retry/backoff, 429, 5xx, network) | Phase 5 — `errors.lua` ships as `M_errors = {}` stub only |
| Fixtures under `spec/fixtures/` (other than what helpers themselves need) | Phase 2/3/4 — recorded API responses |
| Per-sale-fee, refunds, payouts, balance, VAT/tip rendering | Phase 4 |
| `__VERSION__` tag-time substitution, GPG-tag-triggered release, SHA256 attachment, gitleaks, Dependabot, branch protection | Phase 6 (BUILD-03..06, CI-04..06, SEC-02, SEC-05) |
| Bilingual README, GoBD-Hinweis, install-path screenshots, ADRs 0002/0004/0005/0006 | Phase 6 (DOC-01..10) |
| Q2/Q3/Q6 probe answers | Live answers obtained in Phase 2 (Q2, Q6) and Phase 4 (Q3); the Phase-1 probe extension stubs these rows |
| MRH RSA signing, Apple Developer ID code-signing | Permanently out of scope per PROJECT.md `## Out of Scope` |

## Locked decisions

| ID | Decision | Source |
|----|----------|--------|
| D-01 | Lua runtime is 5.4 (MoneyMoney embeds 5.4.8); CI matrix pins same | RESEARCH §Standard Stack; PROJECT Constraints |
| D-02 | Shipping shape: single-file `dist/paypal-pos.lua` generated from modular `src/*.lua`; **zero** `require()` of sibling files anywhere in shipped code | PROJECT Constraints; RESEARCH RQ-1 |
| D-03 | Amalgamator is a custom `tools/build.lua` (~150 lines) driven by `tools/manifest.txt`; `lua-amalg` is rejected because its `package.preload` output is incompatible with MoneyMoney's top-level-script load model | RESEARCH RQ-1; SUMMARY D3 |
| D-04 | Test stack is busted 2.3.0 + luacheck 1.2.0 + luacov 0.16.0 + dkjson 2.7+; coverage gate ≥85% on `src/` excluding `webbanking_header.lua` | RESEARCH §Standard Stack |
| D-05 | CI runs on `ubuntu-24.04` with `leafo/gh-actions-lua@v13` + `leafo/gh-actions-luarocks@v6.1.0`, `LC_ALL=C` for determinism | RESEARCH RQ-7 |
| D-06 | `services = {"PayPal POS"}` is the sole entry the artifact registers; the probe extension uses `services = {"PayPal POS Probe"}` and a matching `SupportsBank` branch to avoid collision | RESEARCH RQ-5, RQ-6 |
| D-07 | `DEBUG = false` is declared once in `src/webbanking_header.lua` at the top level; `tools/build.lua` aborts the build if any non-comment line in `src/` matches `DEBUG%s*=%s*true` | SEC-04; RESEARCH RQ-4 |
| D-08 | `M_log.redact()` is called inside every `M_log.{debug,info,warn,error}` before `print()`; no module ever calls bare `print()`; CI greps the shipped artifact for `print(` outside `M_log` | SEC-01; RESEARCH RQ-4, RQ-10 |
| D-09 | i18n uses an internal `M_i18n.t(key, ...)` with `STRINGS.de` (primary) and `STRINGS.en` (fallback); locale is hard-coded `"de"` in v1; `MM.localizeText` is **not** used for our keys | I18N-02, I18N-03; SUMMARY D26; RESEARCH RQ-3 |
| D-10 | Walking-skeleton `RefreshAccount` returns one hard-coded fixture transaction with `currency="EUR"`, German `name`/`bookingText`, and a `purpose` block; **zero** network calls in Phase 1 | RESEARCH §Walking-Skeleton Entry Module |
| D-11 | Probe outputs are emitted via `print()` to MoneyMoney's Protokoll panel; the maintainer copies them into `docs/adr/0003-sandbox-probe-results.md`; the probe extension is removed/disabled after ADR-0003 is filled in | RESEARCH RQ-6, RQ-8 |
| D-12 | Egress allowlist constants in source (not yet hit by Phase 1 code): `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`; CI greps the shipped artifact for `https?://` outside the allowlist | RESEARCH RQ-7; SEC-02 (full enforcement Phase 6) |
| D-13 | All commits in Phase 1 are GPG-signed under key `FDE07046A6178E89ADB57FD3DE300C53D8E18642`; no Claude / AI attribution in any file or commit message | PROJECT trust model |
| D-14 | Phase-1 module stubs (`model`, `http`, `auth`, `pagination`, `purchases`, `payouts`, `balance`, `mapping`, `errors`) are minimal `do … end` blocks attaching no functions to their predeclared `M_*` tables, plus a one-line `-- Phase N` comment indicating the consumer phase | RESEARCH §Inventory |
| D-15 | `.luacheckrc` declares MoneyMoney built-in globals as `read_globals`, the five WebBanking callbacks as `globals`, and the predeclared `M_*` tables + `DEBUG` as `globals`; `require`/`io`/`os`/`debug`/`socket` are deliberately absent so any source use trips luacheck | RESEARCH RQ-7, RQ-10 |
| D-16 | `dist/` is gitignored; only `src/`, `spec/`, `tools/`, configs, docs are committed | RESEARCH RQ-10 |
| D-17 | The amalgamated header emits a closing sentinel comment `-- paypal-pos build: complete` but **no** SHA256, version, or build date inside the artifact (SHA256 lives in Phase-6 release assets) | RESEARCH RQ-1, RQ-10 |
| D-18 | The Phase 1 ADR-0003 file ships with the 8 result cells empty (template); ADR-0003 is **not** a code gate inside CI but is a documented human gate before declaring Phase 1 complete | RESEARCH RQ-8 |
| D-19 | Build artifact name is `dist/paypal-pos.lua` (matches repo name and what users drop into `Extensions/`); MoneyMoney does not require the script filename to match `services[1]` | RESEARCH RQ-1, §Recommended Structure |
| D-20 | `version = 0.00` in Phase 1's `WebBanking{}` table; Phase 6 introduces `__VERSION__` substitution from the Git tag | RESEARCH RQ-10; SUMMARY D33 |

## Requirement coverage (Phase 1)

| Req ID | Coverage anchor |
|--------|-----------------|
| BUILD-01 | `tools/build.lua` writes `dist/paypal-pos.lua` from manifest order (D-03) |
| BUILD-02 | `tools/build.lua --verify` double-builds and exits non-zero on diff (D-03) |
| TEST-01 | `spec/helpers/mm_mocks.lua` + `spec/mm_mocks_spec.lua` (D-04, RESEARCH RQ-2/RQ-9) |
| I18N-02 | `src/i18n.lua` with `STRINGS.de` and `M_i18n.t` (D-09) |
| I18N-03 | `STRINGS.en` mirrors `STRINGS.de` keys; never exposed via UI in v1 (D-09) |
| SEC-01 | `M_log.redact()` strips JWT-shape, `Bearer …`, `assertion=…`, `access_token=…` (D-08) |
| SEC-04 | `DEBUG = false` in header; build aborts on `DEBUG = true` in source (D-07) |

## Success criteria

The phase is complete when **all** of the following are observable from a clean checkout:

1. `lua tools/build.lua` exits 0 and writes `dist/paypal-pos.lua`. (BUILD-01, D-03)
2. `lua tools/build.lua --verify` exits 0 ("OK: reproducible"). (BUILD-02, D-03)
3. `lua tools/build.lua` exits non-zero with a clear message when `DEBUG = true` exists outside a comment in any `src/*.lua`. (SEC-04, D-07)
4. `lua tools/build.lua` exits non-zero when a `src/*.lua` file calls `require(`, `dofile(`, `loadfile(`, `io.open(`, `os.execute(`, or `io.popen(`. (H8, D-15)
5. `busted spec/` runs green from a clean checkout (dkjson is the only external runtime dep). (TEST-01, D-04)
6. `luacheck .` exits 0 against `.luacheckrc`. (D-15)
7. `busted --coverage spec/` reports ≥85% line coverage on `src/` excluding `webbanking_header.lua`. (D-04)
8. `spec/log_redaction_spec.lua` asserts that `M_log.info("Bearer eyJabc.def.ghi")` produces a `print` output containing neither `eyJ` nor any base64-like JWT fragment. (SEC-01)
9. `spec/i18n_spec.lua` asserts (a) `M_i18n.t("account.name", "X")` returns a German string formatted with `"X"`; (b) every key in `STRINGS.de` exists in `STRINGS.en`. (I18N-02, I18N-03)
10. `spec/entry_spec.lua` asserts: `SupportsBank(ProtocolWebBanking, "PayPal POS")` is true; `SupportsBank("FinTS", "PayPal POS")` is false; `InitializeSession2` with empty credential returns the German error string; `ListAccounts` returns exactly one account with `type == AccountTypeGiro` and `currency == "EUR"`; `RefreshAccount` returns a table with one transaction whose `transactionCode` starts with `"zettle:sale:"` and whose `currency == "EUR"`. (Walking-skeleton gate)
11. CI workflow file exists and (locally via `act` or on a feature-branch push) runs lint + test + coverage + build + verify + DEBUG-grep + egress-allowlist-grep, all green.
12. `docs/adr/0001-amalgamator-design.md` is filled in (documents the `lua-amalg` rejection); `docs/adr/0003-sandbox-probe-results.md` exists with all 8 result cells empty (template). (D-11, D-18)
13. Maintainer has installed `tools/probe.lua` once, run `RefreshAccount` on the "PayPal POS Probe" account, copied the Protokoll output, and filled in Q1, Q4, Q5, Q7, Q8 of ADR-0003. (Q2/Q3/Q6 stay empty until Phases 2/4.) (D-11, D-18)
14. Maintainer has dropped `dist/paypal-pos.lua` into MoneyMoney's `Extensions/` once, confirmed "PayPal POS" appears in "Konto hinzufügen", and observed the fixture transaction in the account view. (Walking-skeleton manual gate; D-10)

## Risk register (Phase 1 only)

| ID | Risk | Mitigation |
|----|------|------------|
| R1 | Q7 probe finds the `"PayPal POS"` label is ambiguous in MoneyMoney's UI | RESEARCH RQ-5 decision tree pre-defines the `"PayPal POS (Zettle)"` fallback; only the `services` string and one `SupportsBank` equality change |
| R2 | Q1 probe finds `os` is absent from the sandbox | Walking-skeleton `RefreshAccount` uses `os.time()` for `bookingDate`; if absent, swap to a hard-coded POSIX timestamp constant and re-run the build (one-line change in `src/entry.lua`) |
| R3 | Build determinism flake from locale or LF normalisation | `LC_ALL=C` in CI; explicit `\r\n`→`\n` and `\r`→`\n` normalisation in `tools/build.lua` |
| R4 | A developer accidentally leaves `DEBUG = true` after a debug session | SEC-04 build-time grep gate (D-07) |
| R5 | A new contributor adds a bare `print()` and bypasses redaction | luacheck `read_globals` does not include `print` as a free pass for `src/`; spec `log_redaction_spec.lua` covers the redaction path; a CI grep step (Phase 6) hardens this |

## Out-of-scope re-confirmations (read these before opening any later-phase plan)

- No `require()`, `dofile`, `loadfile`, `io.popen`, `os.execute` anywhere in shipped code.
- No external Lua C modules (`.so`, `.dylib`) in `dist/paypal-pos.lua`.
- No telemetry, no auto-update pings, no third-party domains beyond the allowlist (allowlist not exercised until Phase 2).
- API key never logged, never written to `LocalStorage`, never echoed in any error string (`LocalStorage` not touched at all in Phase 1).
- No Claude / AI attribution in any committed artifact.
- No commits to `main` directly; the orchestrator commits to a feature branch per the project workflow.
