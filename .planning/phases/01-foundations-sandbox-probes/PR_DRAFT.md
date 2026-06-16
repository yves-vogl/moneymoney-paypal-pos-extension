# PR Draft — Phase 1: Foundations & Sandbox Probes

> This is the pre-drafted body for the PR that will open `phase-1/foundations-sandbox-probes` → `main` once T12 (probe install + ADR-0003 ACCEPTED) and T13 (walking-skeleton manual verification in MoneyMoney) are complete. **Do not open the PR before then.**
>
> Open with:
> ```bash
> gh pr create --base main \
>   --head phase-1/foundations-sandbox-probes \
>   --title "Phase 1: Foundations & Sandbox Probes" \
>   --body-file .planning/phases/01-foundations-sandbox-probes/PR_DRAFT.md
> ```

---

## Summary

Phase 1 stands up the build, test, and lint toolchain for the extension and produces a working walking-skeleton artifact that loads in MoneyMoney and renders one fixture transaction — without making a single network call. Settles the seven Phase-1 v1 requirements and runs the eight sandbox probes (Q1–Q8) against live MoneyMoney to lock down assumptions Phase 2 depends on.

After this merges, the source tree is ready for Phase 2 (Authenticated Network Layer): JWT-bearer auth against `oauth.zettle.com`, `Connection()` wrapper with hostname allowlist and retry/backoff, LocalStorage-backed token cache.

## Phase 1 Requirements Satisfied

| ID | Requirement | Where |
|----|-------------|-------|
| BUILD-01 | `tools/build.lua` amalgamator concatenates `src/*.lua` into `dist/paypal-pos.lua` | `tools/build.lua`, `tools/manifest.txt` |
| BUILD-02 | Byte-reproducible build verified by `--verify` flag (in-memory pure-Lua SHA-256) | `tools/build.lua --verify` |
| TEST-01 | Spec suite uses busted with MoneyMoney globals mocked in `mm_mocks.lua` | `spec/helpers/mm_mocks.lua`, 40 busted tests |
| I18N-02 | Internal `M_i18n.t(key, ...)` module with German default + English fallback | `src/i18n.lua` |
| I18N-03 | English fallback table never reaches UI in v1 (locale hard-coded `"de"`) | `src/i18n.lua`, asserted by `spec/i18n_spec.lua` |
| SEC-01 | `M_log.redact()` strips JWT-shape, `Bearer …`, `assertion=`, `access_token=` from every log line | `src/log.lua`, asserted by `spec/log_redaction_spec.lua` |
| SEC-04 | `DEBUG = false` hard-coded; CI grep + amalgamator gate abort on `DEBUG = true` in any source | `src/webbanking_header.lua`, `tools/build.lua`, `spec/build_spec.lua` |

## Walking Skeleton — what loads in MoneyMoney

- `SupportsBank(WebBanking, "PayPal POS")` → `true`
- `InitializeSession2` validates non-empty credential (no PayPal call yet)
- `ListAccounts` → one `AccountTypeGiro`, currency `EUR`, name `PayPal POS — Test-Händler`
- `RefreshAccount` → balance `9,95 EUR`, one fixture transaction (`Kartenzahlung`, multi-line purpose with German VAT + UUID lines, `transactionCode = "zettle:sale:fixture-0001"`)
- `EndSession` → `nil`

No network code. No LocalStorage logic. No real error categories. All of that lands in Phase 2 / Phase 5.

## Test results

- `luacheck .` — 0 warnings / 0 errors over the source + spec + tooling tree
- `busted spec/` — **40 successes / 0 failures / 0 errors**
- `lua tools/build.lua` — produces `dist/paypal-pos.lua` (211 lines)
- `lua tools/build.lua --verify` — `OK: reproducible (sha256: 5e8f907399…)` (byte-identical across two consecutive runs)
- `luacov` — **99.19 % line coverage** on the amalgamated artifact (122 / 123 lines hit; the single missed line is the top-level `WebBanking{}` call only reached when MoneyMoney loads the artifact, not during dofile)
- All CI gates green on the latest commit: lint, test, threshold ≥ 85 %, reproducible build, `DEBUG = false`, egress allowlist (only `oauth.zettle.com` in dist), no-AI-attribution

## Sandbox Probes (Q1–Q8)

| Probe | Owner | Status |
|-------|-------|--------|
| Q1 — Sandbox globals enumeration | Phase 1 | **ANSWERED** — `require`/`dofile`/`loadfile`/`io`/`os`/`debug`/`package` all present in MoneyMoney's sandbox. Our amalgamator-level ban on those in `src/` is a code-discipline rule, not a sandbox requirement. R2 dispelled: `os.time()` in `entry.lua` is safe. |
| Q2 — `Connection():request` redirect behaviour | Phase 2 | Deferred |
| Q3 — `finance.izettle.com` host | Phase 4 | Deferred |
| Q4 — JSON integer round-trip on `amount=995` | Phase 1 | **ANSWERED** — integer preserved; no `string.format("%d", v)` workaround needed in `mapping.lua` |
| Q5 — LocalStorage cross-restart persistence | Phase 1 | _PENDING — second observation after MoneyMoney restart_ |
| Q6 — PayPal POS first-party `client_id` | Phase 2 | Deferred (lookup on `developer.zettle.com`) |
| Q7 — `services` label rendering in "Konto hinzufügen" | Phase 1 | _PENDING — bank-list label confirmation_ |
| Q8 — TLS verification default | Phase 1 | **ANSWERED** — MoneyMoney rejects `expired.badssl.com` with `errSSLXCertChainInvalid`. TLS verification is active by default; no pinning needed. Bonus finding: `pcall` does NOT catch MM-Connection SSL errors — important for Phase 2 `http.lua` error-handling design. |

The Q5 and Q7 cells in `docs/adr/0003-sandbox-probe-results.md` fill in once the probe second run completes (maintainer-driven, T12 finalisation step). The ADR flips from `PROPOSED` to `ACCEPTED` at that point.

## Phase-2 inputs surfaced by this phase

- **Credential UI design gap — challenge-object shape unknown.** Phase 1 attempted to return a challenge object from `InitializeSession2` on the first call (`{ title, challenge, label }`); MM 2.4.72 did NOT honour this shape and fell back to the default Username+Password UI. Phase 2 must research the actual challenge-schema MM accepts (likely a different field set; reference Trading 212 / N26 / Qonto community extensions that use API-key auth). The current code's defensive multi-shape credential extraction is the temporary safety net.
- **Connection-error handling.** `pcall()` does not catch `errSSLXCertChainInvalid` and similar MoneyMoney-Connection failures. Phase 2 `http.lua` must rely on MM-specific error channels (typically `nil + error string` return pattern), not Lua-level exception handling.
- **No `require`-based sandbox restriction.** All sandbox-banned tokens (`require`, `dofile`, `io.open`, `os.execute`, etc.) are available in MM but kept out by our amalgamator gate for portability and audit reasons. Phase 2 modules continue to use only the predeclared `M_*` table pattern.
- **LocalStorage cross-restart persistence unobserved.** Phase 1 confirmed LocalStorage is writable within a session (counter `0 → 1`). The restart-persistence observation was overtaken by the T13 install. Phase 2 token cache designs defensively for both outcomes; a single log line at cache-miss will reveal actual persistence behaviour in production.

## Ancillary repo work bundled in this PR

- **Self-hosted Coverage Badge** — `coverage-badge` branch holds a single `coverage.svg` regenerated by CI on every `main` push. No third-party renderer or coverage host. The badge in the README points at `raw.githubusercontent.com/.../coverage-badge/coverage.svg`.
- **OpenSSF Scorecard** — `.github/workflows/scorecard.yml` analyses the repo weekly + on `main` push + on branch-protection-rule change. Publishes to `api.securityscorecards.dev` (Linux Foundation public-good infrastructure). README badge populates after the first scan completes on `main`.
- **`SECURITY.md`** — bilingual disclosure policy (German primary, English fallback) with GitHub Private Vulnerability Reporting as preferred channel and GPG-encrypted email fallback. Lifts Scorecard's `Security-Policy` check.
- **Dependabot for GitHub Actions** — weekly Monday bumps with `ci:` Conventional-Commit prefix. Lifts Scorecard's `Dependency-Update-Tool` check. LuaRocks is not Dependabot-supported; Lua tool versions float to latest at CI install time.
- **GitHub Sponsors funding metadata** — `.github/FUNDING.yml` points at `@yves-vogl`; README has a short *Unterstützen* section.
- **README badges** — CI status, self-hosted Coverage, OpenSSF Scorecard, GitHub Sponsors, MIT, Pre-Release status, Lua 5.4, MoneyMoney-Extension, Conventional Commits 1.0.0, GPG-signed commits.
- **`.luacov` pattern bug** discovered and fixed (KI-01 resolved): luacov strips the `.lua` extension before applying include/exclude patterns; the original `src/.+%.lua$` pattern silently matched nothing. Patterns rewritten to prefix form.

## Out of Scope (explicit)

The following are intentionally deferred to later phases per ROADMAP, NOT missing:

- Network code (`http.lua`, `auth.lua`, `pagination.lua`) — stubs only, implemented in Phase 2
- Sales mapping (`purchases.lua`, `mapping.lua`) — Phase 3
- Refunds, fees, payouts, VAT split, tips — Phase 4
- Resilience: retry/backoff, rate-limit handling, partial-fetch policy — Phase 5
- Release pipeline: tag-triggered build, GPG-verified tag, SHA256 attached, public `v0.1.0` release — Phase 6
- `CONTRIBUTING.md` and developer-onboarding docs — Phase 6
- SHA-pinning of GitHub Actions, step-level token-permission tightening, GitHub Private Vulnerability Reporting toggle — deferred Scorecard hardening, follow-up tracked

## Test Plan

- [x] `lua tools/build.lua --verify` byte-identical (CI gate)
- [x] `busted --coverage spec/` — 40 / 40 pass (CI gate)
- [x] `luacov` total ≥ 85 % (CI gate; actual 99.19 %)
- [x] `luacheck .` — 0 warnings, 0 errors (CI gate)
- [x] No off-allowlist hosts in `dist/paypal-pos.lua` (CI gate)
- [x] No AI-attribution patterns in committed content (CI gate)
- [x] All commits GPG-signed under `FDE07046A6178E89ADB57FD3DE300C53D8E18642` (branch protection gate)
- [x] T12.a — probe extension installed in MoneyMoney, Q1/Q4/Q5(first run)/Q8 captured from Protokoll
- [x] T12.b — ADR-0003 cells Q1/Q4/Q5/Q7/Q8 filled; status flipped to `ACCEPTED` (Q5 cross-restart persistence pragmatically deferred — Phase 2 designs defensively)
- [x] T13 — fresh `dist/paypal-pos.lua` installed in MoneyMoney 2.4.72; bank-list shows `PayPal POS`; add-account flow completes (via defensive credential extraction — MM 2.4.72 does NOT honour the challenge object I returned, falls back to default Username+Password UI); fixture transaction renders as `17.06.2026 Kartenzahlung 9,95 EUR` with the full multi-line German purpose (`Brutto / USt 19% / UUID`)
- [x] STATE.md updated to mark Phase 1 complete; ROADMAP.md updates Phase 1 status to ✅

## Commits

```
$ git log --oneline origin/main..phase-1/foundations-sandbox-probes
```
~21 commits (T01 through T11 plus ancillary repo work), all GPG-signed.

## Trust chain

- All commits GPG-signed under maintainer key fingerprint `FDE07046 A617 8E89 ADB5 7FD3 DE30 0C53 D8E1 8642`.
- Branch protection on `main` requires signed commits + linear history.
- The `coverage-badge` branch holds bot-authored unsigned commits intentionally — it carries only generated artifacts (`coverage.svg`), not authored content.
- Once merged, the next maintenance step is the first reproducible release artifact in Phase 6, which adds SHA256 + GPG-signed tag verification on top of this trust chain.
