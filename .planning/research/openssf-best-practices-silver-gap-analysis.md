# OpenSSF Best Practices — Silver tier gap analysis

**Drafted:** 2026-08-24
**Revised:** 2026-08-27 — second pass: closed the three PARTIAL dependency
criteria with real repository changes, ran the regression-test archaeology the
first pass deferred, replaced the coverage claim with a measured number, and
retired §2 (the required-check-count finding, since fixed).
**Status:** every criterion that can be satisfied inside this repository is
satisfied; the two remaining are account-gated (see "What remains")
**Scope:** Issue [#42](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues/42)
**Criteria source:** `WebFetch https://www.bestpractices.dev/en/criteria/1`, accessed
2026-08-24. This is the live Silver-tier criteria page (tier confirmed in the
fetched content: "Tier: Silver Badge"). Every row below is checked against this
list, not against a remembered/older list — the badge site's criteria set does
change over time.

---

## 0. Sequencing premise (re-verified 2026-08-27)

Silver's first criterion is `achieve_passing` ("The project MUST achieve a
passing level badge"). Re-verified again on **2026-08-27**, and deliberately
falsified rather than merely repeated: `projects.json?q=moneymoney`,
`?q=paypal-pos`, `?q=zettle`, `?q=yves-vogl` and the `?url=` lookup all return
`[]`, while a control query for a known project (`?q=curl`) returns a populated
record (id 63) — so the endpoint is live and the empty result is a real
absence, not an API outage. **Nobody has clicked "Get Your Badge Now" yet** — that is an account-gated action only `@yves-vogl` can take
(see "What remains" at the bottom). This gap analysis is written so it holds
regardless of when that step happens: every other criterion below is scored
against what actually exists in the repository/GitHub configuration today.

---

## 1. Gap analysis — all Silver-tier criteria

Legend: **MET** (repo reality satisfies it, evidence given) · **PARTIAL**
(some but not full coverage — action item given) · **NOT MET** (does not
hold — reason given) · **N/A** (criterion inapplicable to this project's
shape, with delegation/reasoning) · **BLOCKED** (cannot be satisfied without
the maintainer's badge-site account).

### Basics

| Criterion | Tier | Status | Evidence |
|---|---|---|---|
| `achieve_passing` | MUST | **BLOCKED** | No bestpractices.dev project entry exists yet (verified live, see §0). Maintainer-only. |
| `contribution_requirements` | MUST | **MET** | `CONTRIBUTING.md` "Pre-commit checklist" + "Testing conventions" + "Commit conventions" sections state binding acceptance requirements (tests, luacheck-clean, GPG-signed + DCO-signed-off commits, Conventional Commits). |
| `dco` | SHOULD | **MET** | `CONTRIBUTING.md` § "Developer Certificate of Origin (DCO)" — DCO v1.1, `Signed-off-by` trailer required on every commit, explicit "no CLA" statement. |
| `governance` | MUST | **MET** | `GOVERNANCE.md` (whole file) — single-maintainer "benevolent dictator" model, decision process, dispute handling. |
| `code_of_conduct` | MUST | **MET** | `CODE_OF_CONDUCT.md` — Contributor Covenant v2.1, standard repo-root location, linked from `CONTRIBUTING.md` and (as of this PR) `README.md`. |
| `roles_responsibilities` | MUST | **MET** | `GOVERNANCE.md` § "Roles and responsibilities" — table of Maintainer vs. Contributor duties. |
| `access_continuity` | MUST | **MET** | `GOVERNANCE.md` § "Access continuity (\"bus factor\")" — MIT license, reproducible build, no private infra, signed history as structural continuity mechanisms. |
| `bus_factor` | SHOULD | **NOT MET (honest, accepted)** | Factually 1 (`@yves-vogl` is the sole maintainer). `GOVERNANCE.md` states this plainly rather than obscuring it; `docs/adr/0009-openssf-scorecard-stance.md` "Code-Review (0/10)" and "Contributors (6/10)" sections record the same structural constraint for the Scorecard context. SHOULD, not MUST — answer "Unmet" with the justification text in the questionnaire-answers file. |
| `documentation_roadmap` | MUST | **MET** | `ROADMAP.md` — explicit 12-month horizon, standing commitments, explicit non-goals. |
| `documentation_architecture` | MUST | **MET** | `docs/adr/0001`–`0009` (MADR-format ADRs) + `CONTRIBUTING.md` § "Source layout" (module map) + § "Architecture" (amalgamator, error pattern, logging). |
| `documentation_security` | MUST | **MET** | `SECURITY.md` in full — supported versions, egress hosts, disclosure channel, response-time table, out-of-scope list, supply-chain controls table, assurance case. |
| `documentation_quick_start` | MUST | **MET** | `docs/installation.md` "In drei Schritten" / `docs/index.md` — five numbered steps from download to first refresh. |
| `documentation_current` | MUST | **MET (fixed by this PR)** | `docs/index.md` previously stated "Release-Candidate-Phase für v1.0.0" while `v1.0.1` has been the shipped release since 2026-06-24 (`CHANGELOG.md`, `git tag`) — a real `documentation_current` violation, corrected in this PR. |
| `documentation_achievements` | MUST | **BLOCKED** | No badge exists yet to hyperlink (depends on `achieve_passing`). `SECURITY.md` and `ROADMAP.md` already point at issue #42 instead of a stale claim, so nothing false is currently asserted. |
| `accessibility_best_practices` | SHOULD | **PARTIAL** | No formal accessibility audit of the MkDocs Material site exists; Material's default theme has reasonable baseline a11y (semantic HTML, keyboard nav, contrast-checked palette) but this project has not verified it. Answer "Unmet" honestly. |
| `internationalization` | SHOULD | **PARTIAL** | German is primary (extension UI strings, `docs/`), English is used for `CONTRIBUTING.md`/ADRs/code comments. This is bilingual-by-audience, not full i18n (no runtime locale switching — `src/i18n.lua` ships one German string table). Answer "Unmet" with the bilingual-docs justification. |
| `sites_password_security` | MUST | **N/A** | The project operates no site that stores end-user passwords. The extension's only credential (the Zettle API key) is stored by MoneyMoney's own encrypted credentials store, not by any project-operated site. |

### Change control

| Criterion | Tier | Status | Evidence |
|---|---|---|---|
| `maintenance_or_update` | MUST | **MET** | `SECURITY.md` supported-versions table + `ROADMAP.md` "Support policy": only the latest release is supported, but the upgrade path is a single-file replacement — satisfies the criterion's "OR provide an upgrade path" clause. |

### Reporting

| Criterion | Tier | Status | Evidence |
|---|---|---|---|
| `report_tracker` | MUST | **MET** | GitHub Issues, public, searchable: `https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues`. |
| `vulnerability_report_credit` | MUST | **MET (vacuously)** | `SECURITY.md` states the credit policy ("wird im Release-Changelog... benannt"). Verified live via `gh api .../security-advisories` → `[]` — zero vulnerability reports have been resolved in the project's history, so there is nothing to credit yet; the policy itself is what the criterion requires. |
| `vulnerability_response_process` | MUST | **MET** | `SECURITY.md` full disclosure process: preferred channel (GitHub Private Vulnerability Reporting, verified live via `gh api repos/.../private-vulnerability-reporting` → `{"enabled":true}`), GPG-encrypted-email alternative, response-time table (72h ack / 7d assessment). |

### Quality

| Criterion | Tier | Status | Evidence |
|---|---|---|---|
| `coding_standards` | MUST | **MET (fixed by this PR)** | `CONTRIBUTING.md` § "Coding style" (new) now explicitly names the project's conventions (indentation, naming, module-boundary rules, sandbox-discipline gates) instead of only referencing the linter obliquely. |
| `coding_standards_enforced` | MUST | **MET** | `luacheck` 1.2.0 against `.luacheckrc`, run as the blocking "Lint + tests + reproducible build" required status check on every push/PR (`.github/workflows/ci.yml`). |
| `build_standard_variables` | MUST | **N/A** | No native/compiled binaries — the amalgamator concatenates Lua source into a single `.lua` text file; there are no compiler/linker environment variables to honour. |
| `build_preserve_debug` | SHOULD | **N/A** | Same reasoning — no compiled artifact, no debug-symbol stripping step exists. |
| `build_non_recursive` | MUST | **MET (trivially)** | `tools/build.lua` performs one flat pass over `tools/manifest.txt`; there is no subdirectory build recursion to have cross-dependency bugs in. |
| `build_repeatable` | MUST | **MET** | `lua tools/build.lua --verify` — re-verified locally today (2026-08-24): `OK: reproducible (sha256: 17ffcdd29d1a30a1427a844a4fad4156307ffd12c80634f51264b9d0673e202b)`. Same gate runs in CI on every push. |
| `installation_common` | MUST | **MET** | `docs/installation.md` documents the standard MoneyMoney extension convention: drop the `.lua` file into MoneyMoney's Extensions folder (opened via **Hilfe → Datenbank im Finder zeigen**). There is no package-registry distribution channel for MoneyMoney extensions — this drop-in convention *is* the commonly-used convention for this ecosystem. |
| `installation_standard_variables` | MUST | **N/A** | No installer exists; MoneyMoney's Extensions folder is the single, fixed install location the host application defines — there is no project-controlled "where do built artifacts go" decision to honour standard variables for. |
| `installation_development_quick` | MUST | **MET** | `CONTRIBUTING.md` § "Prerequisites" + "Test loop" — `brew install lua@5.4 luarocks` + four `luarocks install` lines + the single-command test/lint/build loop gets a new contributor productive in minutes. |
| `external_dependencies` | MUST | **MET (was PARTIAL; closed 2026-08-27)** | All three dependency surfaces are now computer-processable. GitHub Actions: `.github/dependabot.yml` (`package-ecosystem: github-actions`). Python CI toolchain: `requirements/{docs,sast}.in` + pip-compile hash-locked `.txt`. **Lua dev toolchain: `moneymoney-paypal-pos-extension-dev-1.rockspec`** — a dev-only manifest in the conventional LuaRocks format pinning `busted == 2.3.0-1`, `luacheck == 1.2.0-1`, `luacov == 0.17.0-1`, `dkjson == 2.11-1`. `ci.yml` and `release.yml` now install with `luarocks install --only-deps <rockspec>` instead of four bare `luarocks install <name>` lines. Verified: `luarocks lint` exit 0, and `--only-deps` resolves the full closure under both Lua 5.4 and 5.5. The shipped artifact still has **zero** runtime dependencies. |
| `dependency_monitoring` | MUST | **MET (was PARTIAL; closed 2026-08-27)** | GH Actions + pip are monitored by Dependabot. The Lua toolchain is now monitored by `.github/workflows/lua-toolchain-audit.yml`: weekly (`cron: 0 6 * * 1`), it parses the pins out of the rockspec with `lua` itself, queries `luarocks search --porcelain` for the newest published version of each, and opens/updates a tracking issue on drift. **Stated limit, not papered over:** this is a *freshness* check, not a CVE check. No vulnerability feed exists for this ecosystem — OSV.dev rejects `"ecosystem":"LuaRocks"` with `{"code":3,"message":"invalid ecosystem"}` (verified 2026-08-27) and the GitHub Advisory Database carries no LuaRocks advisories. The criterion's "monitor or periodically check" is met by the best signal the ecosystem actually offers; claiming CVE coverage here would be false. |
| `updateable_reused_components` | MUST | **MET (was PARTIAL; closed 2026-08-27)** | Every reused component now has an identifiable pinned version to update *from*: Dependabot PRs for Actions/pip, and a single-line edit in the rockspec (validated by CI) for the Lua toolchain. The old floating `luarocks install <name>` had no version to update from at all, which is why this was PARTIAL. |
| `interfaces_current` | SHOULD | **MET** | No deprecated MoneyMoney WebBanking API calls or Zettle endpoints are in use; `docs/adr/0006-jwt-bearer-only-auth.md` documents the currently-recommended Zettle OAuth flow (no legacy password grant). |
| `automated_integration_testing` | MUST | **MET** | `busted spec/` runs as a required status check on every push/PR (`.github/workflows/ci.yml`); re-verified locally today: 409 successes / 0 failures / 0 errors / 0 pending. |
| `regression_tests_added50` | MUST | **MET — now audited, not assumed** | The first pass flagged that no commit archaeology had been done. Done now. Ten `fix:` commits since 2026-02-27; five touch `src/` (i.e. are software-bug fixes rather than CI/tooling fixes). Of those five, four shipped a regression test: `9050e31` (spec in the same commit) and `762cead` / `e925111` / `03e6964`, whose RED half is the preceding commit `7db9865` ("test(02): add failing tests for B-01/B-02 nil-crash paths and H-01/M-02 rate_limit path", +120 lines across `spec/auth_spec.lua`, `spec/entry_spec.lua`, `spec/http_spec.lua`) — the documented RED→GREEN pair discipline, which a same-commit-only search misses. That is 4/5 = **80 %**, above the 50 % floor. The fifth, `66d9b95`, had **no** regression test — closed in this pass by `spec/webbanking_declaration_spec.lua` (see §3), taking the ratio to 5/5. |
| `test_statement_coverage80` | MUST | **MET — measured, not inferred** | The first pass cited the CI *threshold* (85 %). The criterion asks what coverage the suite actually provides, so it was measured with the project's own tooling on 2026-08-27: `busted --coverage spec/` + `luacov` → **415 successes / 0 failures / 0 errors / 0 pending, 94.53 % statement coverage** (1037 hit / 60 missed on `dist/paypal-pos.lua`; it was 93.78 % / 409 tests before this pass added `spec/webbanking_declaration_spec.lua`). Comfortably above the 80 % floor, and above the repo's own 85 % CI gate. |
| `test_policy_mandated` | MUST | **MET** | `CONTRIBUTING.md` § "Test policy (binding)" point 1. |
| `tests_documented_added` | MUST | **MET** | Same section, point 1 — the policy is in the documented contribution instructions, not just in an internal convention. |
| `warnings_strict` | MUST | **MET** | `luacheck .` required check is zero-warnings, zero-errors, blocking (`.luacheckrc` at repo root; `CONTRIBUTING.md` pre-commit checklist). |

### Security

| Criterion | Tier | Status | Evidence |
|---|---|---|---|
| `implement_secure_design` | MUST | **MET** | `SECURITY.md` § "Assurance case" — trust boundaries, threat/mitigation table; string-return error pattern (`docs/adr/0008-string-return-error-pattern.md`) avoids leaking raw internals to the user or logs. |
| `crypto_weaknesses` | MUST | **N/A** | The extension implements no cryptographic primitives of its own (`SECURITY.md` § "Assurance case" § "Threats considered", row "Cryptographic weaknesses"). |
| `crypto_algorithm_agility` | SHOULD | **N/A** | Same delegation — there is no project-selected algorithm to make agile. |
| `crypto_credential_agility` | MUST | **N/A** | The extension writes no credential files of its own; the API key lives in MoneyMoney's own encrypted credential store, and the token cache lives in `LocalStorage` (`docs/adr/0002-localstorage-token-cache.md`) — both are the host application's storage, not project-authored files mixing credentials with other data. |
| `crypto_used_network` | SHOULD | **MET** | All network calls run over HTTPS via MoneyMoney's `Connection()` (`SECURITY.md` § "Ausgehende Verbindungen"); no non-TLS fallback exists. |
| `crypto_tls12` | SHOULD | **MET (by delegation)** | TLS version selection is entirely MoneyMoney's `Connection()` responsibility; the extension never specifies or downgrades a TLS version. Modern MoneyMoney builds use TLS 1.2+ by OS default. |
| `crypto_certificate_verification` | MUST | **MET** | `docs/adr/0007-no-tls-pinning.md` — MoneyMoney's `Connection()` performs system certificate verification by default; the extension never disables it and deliberately adds no custom pinning logic that could be misconfigured. |
| `crypto_verification_private` | MUST | **MET** | `Connection():request()` is atomic (TLS handshake + verification happen before any request body/headers are sent) — there is no code path in `src/http.lua` that could send the `Authorization: Bearer` header before verification completes, because the extension never constructs the socket itself. |
| `signed_releases` | MUST | **MET** | Re-verified live today: `git tag -v v1.0.1` → `gpg: Good signature from "Vogl, Yves <yves.vogl@mac.com>"`, exit 0. `.github/workflows/release.yml` job `verify-signed-tag` enforces this on every release push. Public key documented in `SECURITY.md` (fingerprint + `keys.openpgp.org`). |
| `version_tags_signed` | SUGGESTED | **MET** | Same evidence — every `v*` tag is signed, not just release tags. |
| `input_validation` | MUST | **MET** | Untrusted API responses are never trusted blindly: `src/auth.lua:25-38` wraps the JSON decode of an attacker-controlled payload in `pcall`; `src/http.lua` (`_request_with_retry`, JSON-parse block ~L198-244) applies the same pattern project-wide (documented as "Phase-2 invariant: pcall ONLY around JSON parse"); decoded structures are consumed field-by-field and unexpected shapes degrade to a localized error string (`docs/adr/0008-string-return-error-pattern.md`) rather than propagating. |
| `hardening` | SHOULD | **MET** | 5xx retry-with-backoff + 429 `Retry-After` honoring + a 60s wall-clock cap (`src/http.lua`); egress allowlist CI gate; redact-before-log (`M_log`, SEC-01). |
| `assurance_case` | MUST | **MET** | `SECURITY.md` § "Assurance case" — protected assets, trust boundaries, threat/mitigation table, accepted residual risks. Re-read in full for this pass; still accurate except for the branch-protection required-check count noted below. |

### Analysis

| Criterion | Tier | Status | Evidence |
|---|---|---|---|
| `static_analysis_common_vulnerabilities` | MUST | **MET** | Semgrep `p/security-audit` + `p/secrets` rulesets run on every push/PR (`.github/workflows/sast.yml`), SARIF uploaded to code-scanning. Since PR #80 it is also a required status check on `main` (verified live 2026-08-27), though the criterion only requires the tool to be *used*. |
| `dynamic_analysis_unsafe` | MUST | **N/A** | Lua is a memory-safe language; the criterion only applies to memory-unsafe languages (C/C++). |

---

## 2. Cross-cutting finding of the first pass — RESOLVED

The 2026-08-24 pass found that `SECURITY.md` claimed 5 required status checks
while branch protection actually required 3, and flagged it as a factual
inaccuracy in a MUST-have document (`documentation_security` /
`assurance_case`).

**That is now closed.** Re-verified live on 2026-08-27:

```
$ gh api repos/yves-vogl/moneymoney-paypal-pos-extension/branches/main/protection \
    --jq '.required_status_checks.contexts'
["Lint + tests + reproducible build","gitleaks secret scan","Commit-message lint","Semgrep SAST"]
```

Both halves of the two-way decision were taken: branch protection was tightened
(`Semgrep SAST` became a required check, PR #80) *and* the doc was corrected to
match (PRs #81, #82, #83). `SECURITY.md` now states 4 and additionally records
why `Scorecard analysis` structurally *cannot* be a fifth — `scorecard.yml` has
no `pull_request` trigger, so as a required check it would block every PR
forever rather than gate it. Nothing in that area is outstanding.

---

## 3. What the 2026-08-27 pass changed in the repository

Not documentation-only this time — the three PARTIAL rows above were real gaps
and were closed with real changes:

- **`moneymoney-paypal-pos-extension-dev-1.rockspec`** (new) — computer-processable,
  exactly-pinned manifest for the Lua dev toolchain, in the conventional LuaRocks
  format. `luarocks lint` exit 0; `--only-deps` resolution verified under Lua 5.4
  (the CI version) and 5.5.
- **`.github/workflows/ci.yml`, `.github/workflows/release.yml`** — the four bare
  `luarocks install <name>` lines replaced by
  `luarocks install --only-deps moneymoney-paypal-pos-extension-dev-1.rockspec`.
  Before this, the toolchain floated to whatever luarocks.org served at job start.
- **`.github/workflows/lua-toolchain-audit.yml`** (new) — weekly pin-vs-upstream
  comparison, files/updates a drift issue. Both the no-drift and drift paths, the
  step-summary output and the generated issue body were executed locally before
  commit, not just written.
- **`spec/webbanking_declaration_spec.lua`** (new, 6 examples) — regression cover
  for the `WebBanking{credentials=…}` declaration fixed in `66d9b95`, the one
  in-scope bug fix that had none. This sat in a genuine blind spot: `.luacov`
  excludes `^src/webbanking_header$`, no other spec touches the table, and
  `tools/build.lua` gates only DEBUG/egress — so deleting the `credentials`
  array would have kept the suite green while breaking every user's account
  setup. Verified as a real guard by mutation: with the array removed the file
  goes from 6 passes to 1 failure + 3 errors.
- **`.github/dependabot.yml`** — the Lua-tooling comment made two contradictory
  claims ("pinned by the rockspec resolution" vs. "CI installs the latest
  published version"); the second was the true one. Replaced with an accurate
  description plus a pointer to the rockspec and audit workflow.
- **`.planning/REQUIREMENTS.md`** — SEC-09 defined, traced and counted, so the
  new `SECURITY.md` rows cite a requirement ID that actually exists.
- **`SECURITY.md`, `CONTRIBUTING.md`** — supply-chain control rows (DE + EN) and
  contributor install instructions updated to the pinned-manifest workflow.
- Repository labels `dependencies`, `python`, `github-actions` created — they
  were referenced by `.github/dependabot.yml` but did not exist, so the audit
  workflow's `gh issue create --label dependencies` would have failed.

Measured after the change: **415 successes / 0 failures, 94.53 % statement
coverage**, `lua tools/build.lua --verify` → `OK: reproducible` with the
artifact SHA-256 unchanged (`17ffcdd2…`), `luacheck .` → 0 warnings / 0 errors
in 45 files (run under Lua 5.4 to match CI).

---

## 4. What remains — structurally account-gated, not deferrable work

Exactly two Silver criteria are still open, and no amount of repository work can
close either:

| Criterion | Tier | Why it cannot be closed here |
|---|---|---|
| `achieve_passing` | MUST | Silver's first criterion is "the project MUST achieve a passing level badge". A badge presupposes a project entry on bestpractices.dev, and entries can only be created by a signed-in GitHub user via "Get Your Badge Now" — the BadgeApp has no anonymous or token-based project-creation endpoint. Re-verified 2026-08-27: `projects.json?q=moneymoney`, `?q=paypal-pos`, `?q=zettle`, `?q=yves-vogl` and the `?url=` lookup all return `[]`, while the same API returns a populated record for a known project (`?q=curl` → id 63), so the API is live and the emptiness is real. |
| `documentation_achievements` | MUST | Requires the earned badge to be linked from the README within 48 h. There is no badge ID to link until the row above happens. Nothing false is asserted in the meantime — `SECURITY.md` and `ROADMAP.md` point at issue #42 rather than claiming a badge. |

Both are a single ~15-minute session for `@yves-vogl`:

1. Sign in at <https://www.bestpractices.dev> and register the repository.
2. Fill the **Passing** questionnaire — answers and evidence URLs are pre-written
   in `openssf-best-practices-silver-questionnaire-answers.md` in this directory.
3. Add the badge to `README.md` (closes `documentation_achievements`).
4. Switch the form to **Silver** and transcribe the same file's Silver answers.

Everything else is green or honestly answered:

- All other MUST criteria are Met or N/A-with-justification.
- `bus_factor` (SHOULD) is answered **Unmet with justification** — it is factually
  1, and `GOVERNANCE.md` documents the structural mitigations rather than
  obscuring the number. This does not block the badge: the BadgeApp requires MUST
  criteria to be Met/N-A, but permits SHOULD criteria to be Unmet when a
  justification is supplied.
- `accessibility_best_practices` and `internationalization` (both SHOULD) are
  likewise answered Unmet with justification, and are tracked as their own issues
  rather than being fudged green here.
