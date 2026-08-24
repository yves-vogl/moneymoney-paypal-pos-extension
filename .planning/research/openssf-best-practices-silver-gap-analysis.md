# OpenSSF Best Practices — Silver tier gap analysis

**Drafted:** 2026-08-24
**Status:** preparation complete; submission is maintainer-only (see "What remains")
**Scope:** Issue [#42](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues/42)
**Criteria source:** `WebFetch https://www.bestpractices.dev/en/criteria/1`, accessed
2026-08-24. This is the live Silver-tier criteria page (tier confirmed in the
fetched content: "Tier: Silver Badge"). Every row below is checked against this
list, not against a remembered/older list — the badge site's criteria set does
change over time.

---

## 0. Sequencing premise (unchanged from the 2026-08-19/22 issue findings)

Silver's first criterion is `achieve_passing` ("The project MUST achieve a
passing level badge"). Re-verified today:
`https://www.bestpractices.dev/en/projects.json?q=moneymoney` still returns
zero registered projects for this repository. **Nobody has clicked "Get Your
Badge Now" yet** — that is an account-gated action only `@yves-vogl` can take
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
| `external_dependencies` | MUST | **PARTIAL — corrects a prior over-claim** | Two of three dependency surfaces are computer-processable: GitHub Actions (`.github/dependabot.yml` `package-ecosystem: github-actions`) and the Python CI toolchain (`requirements/{docs,sast}.in` + pip-compile-generated `requirements/{docs,sast}.txt` hash-locked files). The **Lua dev/test toolchain** (`busted`, `luacheck`, `luacov`, `dkjson`) has no machine-readable manifest anywhere in the repo — no `.rockspec`, no lockfile; the versions are named only in `CONTRIBUTING.md` prose and in `ci.yml`'s unpinned `luarocks install <name>` lines. The shipped runtime artifact (`dist/paypal-pos.lua`) itself has **zero** external dependencies (single-file, no libraries), so this gap only concerns the dev toolchain. An earlier issue-#42 status comment (2026-08-20) claimed this criterion fully MET via "Dependabot + pinned lockfiles" — that claim did not account for the Lua toolchain and is corrected here. |
| `dependency_monitoring` | MUST | **PARTIAL — same correction** | GitHub Actions and the pip toolchain are monitored by Dependabot (weekly PRs, verified via `.github/dependabot.yml`). The Lua dev toolchain is **not** monitored by any tool — `.github/dependabot.yml`'s own comment states the reason accurately ("LuaRocks is not supported by Dependabot"), but the stated compensating claim ("CI installs the latest published version of each tool, which keeps the toolchain current") is a floating-`latest` install, not a monitored/audited dependency — it trades staleness risk for supply-chain-trust risk (an unpinned `luarocks install busted` on a compromised or typosquatted package would go undetected until it broke something visibly). |
| `updateable_reused_components` | MUST | **PARTIAL — same correction** | Same reasoning as the two rows above: GH Actions and pip components are trivially identifiable/updateable (Dependabot PRs); the Lua toolchain has no identifiable pinned version to update *from* in the first place. |
| `interfaces_current` | SHOULD | **MET** | No deprecated MoneyMoney WebBanking API calls or Zettle endpoints are in use; `docs/adr/0006-jwt-bearer-only-auth.md` documents the currently-recommended Zettle OAuth flow (no legacy password grant). |
| `automated_integration_testing` | MUST | **MET** | `busted spec/` runs as a required status check on every push/PR (`.github/workflows/ci.yml`); re-verified locally today: 409 successes / 0 failures / 0 errors / 0 pending. |
| `regression_tests_added50` | MUST | **MET** | `CONTRIBUTING.md` § "Test policy (binding)" mandates a regression test for **every** bug fix (stricter than the 50% floor), enforced via the documented RED→GREEN commit-pair discipline. No systematic commit-archaeology audit of "which of the last 6 months' fixes actually shipped a regression test" was performed in this pass — flagged as a light residual verification step for whoever fills the questionnaire, not a reason to downgrade the status (the *policy* is unambiguously stronger than the criterion requires). |
| `test_statement_coverage80` | MUST | **MET** | CI enforces **85%** luacov statement coverage as a hard gate (`.github/workflows/ci.yml` "Generate text coverage report and enforce 85% threshold" step) — above the 80% floor. |
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
| `static_analysis_common_vulnerabilities` | MUST | **MET** | Semgrep `p/security-audit` + `p/secrets` rulesets run on every push/PR (`.github/workflows/sast.yml`), SARIF uploaded to code-scanning. The criterion only requires the tool to be *used*, not that it be a required/blocking merge check (see cross-cutting finding below on the actual required-check list). |
| `dynamic_analysis_unsafe` | MUST | **N/A** | Lua is a memory-safe language; the criterion only applies to memory-unsafe languages (C/C++). |

---

## 2. Cross-cutting finding — `SECURITY.md` overstates the required-check count

**This is the most important finding of this pass** — verified live against the
GitHub API today (2026-08-24), not assumed:

```
$ gh api repos/yves-vogl/moneymoney-paypal-pos-extension/branches/main/protection \
    --jq '.required_status_checks.contexts'
["Lint + tests + reproducible build","gitleaks secret scan","Commit-message lint"]
```

`SECURITY.md` (both the German and English "Lieferketten-Kontrollen" /
"Supply-chain controls" sections) states: *"required status checks: 5
(Lint+tests+reproducible build, gitleaks secret scan, Commit-message lint,
**Scorecard analysis, Semgrep SAST**)."* That is currently **false** —
branch protection on `main` only requires the first three. Scorecard and
Semgrep run on every push and PR and upload results, but a red run on either
of them today would **not** block a merge to `main`.

This does not change any Silver-criterion status above (`static_analysis_
common_vulnerabilities` only requires the tool to run, not that it gate
merges), but it is a factual inaccuracy in a MUST-have document
(`documentation_security` / `assurance_case`) and should be corrected. Fixing
it is a two-way decision (tighten branch protection to add the two checks,
*or* soften the doc's claim to match reality) that touches
`SECURITY.md` and possibly `tools/setup-branch-protection.sh` /
`.github/workflows/*` — outside this PR's docs-only file whitelist.
**Handed off to `loop-security-engineer` and the maintainer** (see PR body).

---

## 3. What this PR closes (see file diff)

- `docs/index.md` — stale "Release-Candidate-Phase für v1.0.0" claim, fixes
  `documentation_current`.
- `CONTRIBUTING.md` § "Coding style" (new) — names the style guide
  explicitly, fixes `coding_standards`.
- `README.md` — links `GOVERNANCE.md`, `CODE_OF_CONDUCT.md`, `ROADMAP.md`
  from the front page's "Mitwirken" section (front-page discoverability, in
  the spirit of `documentation_achievements`/`roles_responsibilities`
  though the badge link itself remains blocked).
- This file and `openssf-best-practices-silver-questionnaire-answers.md` —
  the gap analysis and pre-filled questionnaire text itself.

## 4. What remains — genuinely needs `@yves-vogl`'s bestpractices.dev account

1. Log in at <https://www.bestpractices.dev>, click "Get Your Badge Now,"
   select this repository — creates the project entry and unblocks
   `achieve_passing`.
2. Fill the **Passing** questionnaire first (Silver requires it as a
   prerequisite). Source material: `README.md`, `CONTRIBUTING.md`,
   `SECURITY.md`, `docs/`.
3. Add the Passing badge to `README.md` within 48h of earning it
   (`documentation_achievements`).
4. Switch the form to **Silver** and transcribe the answers from
   `openssf-best-practices-silver-questionnaire-answers.md` in this
   directory — every criterion above already has its answer text and
   evidence link ready.
5. Decide the `SECURITY.md` required-check-count fix (§2 above) — either
   tighten branch protection or correct the doc — and route it through
   `loop-security-engineer` before or shortly after Silver submission; it
   does not block submission but should not stay inaccurate.
6. Report back on issue #42; close it once the Silver percentage clears the
   passing threshold on bestpractices.dev.

Not one step above can be completed by an agent — bestpractices.dev has no
API for questionnaire submission and requires the maintainer's own GitHub
login.
