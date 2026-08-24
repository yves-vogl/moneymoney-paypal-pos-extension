# OpenSSF Best Practices — Silver questionnaire, pre-filled answers

**Drafted:** 2026-08-24
**Purpose:** transcription source for `@yves-vogl` when filling the Silver
tier form at <https://www.bestpractices.dev> (after the Passing badge is
earned — see `openssf-best-practices-silver-gap-analysis.md` § 4 for the
full maintainer-only sequence).
**Do not submit this file anywhere** — it exists only so the questionnaire
fill-in is a five-minute copy/paste instead of a re-derivation. Every answer
below matches the status recorded in the companion gap-analysis file; read
that file first if a status looks surprising.

Repo base for evidence links:
`https://github.com/yves-vogl/moneymoney-paypal-pos-extension/blob/main/`

---

## Basics

**`contribution_requirements`** — **Met**
> Contribution requirements (tests, luacheck-clean, GPG-signed + DCO
> sign-off commits, Conventional Commits) are documented in CONTRIBUTING.md
> "Pre-commit checklist" and "Commit conventions".
Evidence: `CONTRIBUTING.md#pre-commit-checklist`

**`dco`** — **Met**
> Contributions are accepted under DCO v1.1; every commit must carry a
> `Signed-off-by` trailer. No CLA is used.
Evidence: `CONTRIBUTING.md#developer-certificate-of-origin-dco`

**`governance`** — **Met**
> Single-maintainer ("benevolent dictator") governance model, documented
> including decision process and dispute handling.
Evidence: `GOVERNANCE.md`

**`code_of_conduct`** — **Met**
> Contributor Covenant v2.1, at the standard repository-root location.
Evidence: `CODE_OF_CONDUCT.md`

**`roles_responsibilities`** — **Met**
> Maintainer and Contributor roles and responsibilities are tabulated.
Evidence: `GOVERNANCE.md#roles-and-responsibilities`

**`access_continuity`** — **Met**
> MIT license, reproducible build, no private build infrastructure, fully
> signed git history — a fork can continue with no maintainer involvement.
Evidence: `GOVERNANCE.md#access-continuity-bus-factor`

**`bus_factor`** — **Unmet**
> Honest bus factor of 1 (single maintainer). Structural mitigations
> (MIT license, reproducible build, no private infra, signed history,
> complete contributor docs) are documented so a fork can continue; a
> second maintainer has not joined the project.
Evidence: `GOVERNANCE.md#access-continuity-bus-factor`,
`docs/adr/0009-openssf-scorecard-stance.md`

**`documentation_roadmap`** — **Met**
> 12-month roadmap: standing commitments, planned items, explicit
> non-goals, support policy.
Evidence: `ROADMAP.md`

**`documentation_architecture`** — **Met**
> Architecture is documented via 9 MADR-format ADRs plus a source-layout
> map and amalgamator/error-pattern/logging sections in CONTRIBUTING.md.
Evidence: `docs/adr/`, `CONTRIBUTING.md#architecture`

**`documentation_security`** — **Met**
> Full security policy: supported versions, egress allowlist, disclosure
> channels, response-time commitments, out-of-scope list, supply-chain
> controls, and a dedicated assurance case.
Evidence: `SECURITY.md`

**`documentation_quick_start`** — **Met**
> Five-step quick-start from download to first MoneyMoney refresh.
Evidence: `docs/installation.md`, `docs/index.md`

**`documentation_current`** — **Met**
> Documentation is kept in sync with the current release; the CI amalgamator
> substitutes the live version tag into the shipped artifact, and doc
> pages are corrected whenever found stale (see CHANGELOG [Unreleased]
> "Dokumentation" entry, 2026-08-24, for the most recent fix).
Evidence: `CHANGELOG.md`, `docs/index.md`

**`documentation_achievements`** — **Unmet**
> No achievement badge exists yet to link — this Silver submission is
> itself the next achievement pending. Will be added to README.md within
> 48h of the badge being issued.
Evidence: (n/a until badge exists)

**`accessibility_best_practices`** — **Unmet**
> No formal accessibility audit has been performed on the MkDocs Material
> documentation site or the German user-facing extension strings; the
> theme's defaults are reasonable but unverified.
Evidence: (none — honestly unmet)

**`internationalization`** — **Unmet**
> German is the primary language for user-facing content (extension
> strings, installation docs); English is used for contributor-facing
> docs (CONTRIBUTING.md, ADRs, code comments). This is bilingual-by-
> audience rather than a runtime-switchable i18n system — `src/i18n.lua`
> ships a single German string table.
Evidence: `src/i18n.lua`, `CONTRIBUTING.md` (intro note on language split)

**`sites_password_security`** — **N/A**
> The project operates no site or service that stores end-user passwords.
> The only credential (a Zettle API key) is stored by MoneyMoney's own
> encrypted credential store, not by any project-operated system.
Evidence: `SECURITY.md#assurance-case`

---

## Change control

**`maintenance_or_update`** — **Met**
> Only the latest release is supported; the upgrade path is replacing a
> single `.lua` file, satisfying the criterion's upgrade-path clause.
Evidence: `SECURITY.md` (supported-versions table), `ROADMAP.md#support-policy`

---

## Reporting

**`report_tracker`** — **Met**
> Public, searchable GitHub Issues.
Evidence: `https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues`

**`vulnerability_report_credit`** — **Met**
> The credit policy is documented; zero vulnerability reports have been
> resolved to date (verified via the GitHub Security Advisories API), so
> there is nothing yet to credit — the commitment itself is what the
> criterion requires.
Evidence: `SECURITY.md` ("Wer eine Lücke verantwortungsvoll meldet, wird im
Release-Changelog... benannt")

**`vulnerability_response_process`** — **Met**
> Documented process: GitHub Private Vulnerability Reporting (enabled,
> preferred) or GPG-encrypted email; 72h acknowledgement / 7-day first
> assessment targets.
Evidence: `SECURITY.md#eine-sicherheitslücke-melden`

---

## Quality

**`coding_standards`** — **Met**
> The project's coding style (indentation, naming, module-boundary rules,
> sandbox-discipline gates) is explicitly documented.
Evidence: `CONTRIBUTING.md#coding-style`

**`coding_standards_enforced`** — **Met**
> `luacheck` runs as a required, blocking CI status check on every push
> and pull request.
Evidence: `.luacheckrc`, `.github/workflows/ci.yml`

**`build_standard_variables`** — **N/A**
> No native/compiled binaries are produced; the project ships a single
> concatenated Lua source file. There are no compiler/linker environment
> variables applicable.
Evidence: `docs/adr/0001-amalgamator-design.md`

**`build_preserve_debug`** — **N/A**
> No compiled artifact exists to strip or preserve debug information from.
Evidence: `docs/adr/0001-amalgamator-design.md`

**`build_non_recursive`** — **Met**
> The build is a single flat pass over an ordered module manifest — no
> recursive subdirectory builds exist.
Evidence: `tools/build.lua`, `tools/manifest.txt`

**`build_repeatable`** — **Met**
> `lua tools/build.lua --verify` builds twice and asserts a byte-identical
> SHA-256; this gate runs in CI on every push.
Evidence: `tools/build.lua`, `.github/workflows/ci.yml`

**`installation_common`** — **Met**
> MoneyMoney extensions are installed by placing the `.lua` file into the
> host application's Extensions folder — the standard convention for this
> ecosystem (no package-registry distribution channel exists for
> MoneyMoney extensions). Documented step-by-step.
Evidence: `docs/installation.md`

**`installation_standard_variables`** — **N/A**
> No project-controlled installer exists; the install location is fixed
> by the host application (MoneyMoney's Extensions folder).
Evidence: `docs/installation.md`

**`installation_development_quick`** — **Met**
> A documented four-command LuaRocks setup plus a single-command
> test/lint/build loop gets a new contributor productive quickly.
Evidence: `CONTRIBUTING.md#prerequisites`, `CONTRIBUTING.md#test-loop`

**`external_dependencies`** — **Unmet**
> GitHub Actions and the Python CI toolchain (docs/SAST) both have
> computer-processable dependency manifests (Dependabot ecosystem config;
> pip-compile hash-locked requirements files). The shipped runtime
> artifact has zero external dependencies. However, the Lua dev/test
> toolchain (busted, luacheck, luacov, dkjson) has no machine-readable
> manifest — no rockspec, no lockfile — only prose in CONTRIBUTING.md and
> unpinned `luarocks install` calls in CI. Answering "Unmet" honestly
> rather than overclaiming; see the gap-analysis file for the concrete
> follow-up.
Evidence: `.github/dependabot.yml`, `requirements/`, `CONTRIBUTING.md#prerequisites`
(the counter-evidence for the "Unmet" part)

**`dependency_monitoring`** — **Unmet**
> Same split as above: GitHub Actions and pip dependencies are monitored
> weekly via Dependabot. The Lua toolchain is not — Dependabot does not
> support the LuaRocks ecosystem, and CI installing "latest" on every run
> is not equivalent to monitored/audited dependency tracking.
Evidence: `.github/dependabot.yml` (see its own comment on LuaRocks non-support)

**`updateable_reused_components`** — **Unmet**
> Same reasoning — GH Actions/pip components are trivially identifiable
> and updateable via Dependabot PRs; the Lua toolchain has no pinned
> version to identify or update from.
Evidence: `.github/dependabot.yml`

**`interfaces_current`** — **Met**
> No deprecated MoneyMoney WebBanking API calls or legacy Zettle OAuth
> flows are in use.
Evidence: `docs/adr/0006-jwt-bearer-only-auth.md`

**`automated_integration_testing`** — **Met**
> `busted spec/` runs as a required status check on every push and PR.
Evidence: `.github/workflows/ci.yml`, `spec/`

**`regression_tests_added50`** — **Met**
> The binding test policy requires a regression test for every bug fix
> (exceeding the 50% floor), enforced by a documented RED→GREEN commit
> discipline.
Evidence: `CONTRIBUTING.md#testing-conventions` ("Test policy (binding)")

**`test_statement_coverage80`** — **Met**
> CI enforces an 85% luacov statement-coverage floor — above the 80%
> criterion threshold.
Evidence: `.github/workflows/ci.yml` ("enforce 85% threshold" step)

**`test_policy_mandated`** — **Met**
> Formal written policy: new major functionality must ship with automated
> tests, or the PR is rejected.
Evidence: `CONTRIBUTING.md#testing-conventions`

**`tests_documented_added`** — **Met**
> The policy lives in the documented contribution instructions themselves
> (not just an internal convention).
Evidence: `CONTRIBUTING.md#testing-conventions`

**`warnings_strict`** — **Met**
> `luacheck .` must report zero warnings and zero errors; it is a
> required, blocking CI check.
Evidence: `.luacheckrc`, `.github/workflows/ci.yml`

---

## Security

**`implement_secure_design`** — **Met**
> Secure-design principles applied: string-return error pattern avoids
> leaking internals; a documented assurance case names trust boundaries
> and mitigations.
Evidence: `SECURITY.md#assurance-case`, `docs/adr/0008-string-return-error-pattern.md`

**`crypto_weaknesses`** — **N/A**
> The extension implements no cryptographic primitives of its own.
Evidence: `SECURITY.md#assurance-case` (threat table, "Cryptographic weaknesses" row)

**`crypto_algorithm_agility`** — **N/A**
> No project-selected cryptographic algorithm exists to make agile.
Evidence: `SECURITY.md#assurance-case`

**`crypto_credential_agility`** — **N/A**
> The extension writes no credential files of its own; the API key and
> token cache live in MoneyMoney's own credential store / `LocalStorage`.
Evidence: `docs/adr/0002-localstorage-token-cache.md`

**`crypto_used_network`** — **Met**
> All network communication is HTTPS-only via MoneyMoney's `Connection()`;
> no non-TLS fallback exists.
Evidence: `SECURITY.md#ausgehende-verbindungen--egress`

**`crypto_tls12`** — **Met**
> TLS version selection is delegated entirely to MoneyMoney's
> `Connection()` / the host OS; the extension never specifies or
> downgrades a TLS version.
Evidence: `docs/adr/0007-no-tls-pinning.md`

**`crypto_certificate_verification`** — **Met**
> MoneyMoney's `Connection()` performs system certificate verification by
> default; the extension never disables it.
Evidence: `docs/adr/0007-no-tls-pinning.md`

**`crypto_verification_private`** — **Met**
> `Connection():request()` is atomic — TLS handshake and verification
> complete before any request (including the `Authorization: Bearer`
> header) is sent; the extension never constructs its own socket.
Evidence: `src/http.lua`, `docs/adr/0007-no-tls-pinning.md`

**`signed_releases`** — **Met**
> Every release tag is GPG-signed; `release.yml`'s `verify-signed-tag` job
> verifies the signature against the maintainer's published fingerprint
> before publishing. Re-verified live: `git tag -v v1.0.1` →
> "Good signature".
Evidence: `SECURITY.md` (fingerprint + key server), `.github/workflows/release.yml`

**`version_tags_signed`** — **Met**
> All version tags (not just release tags) are GPG-signed.
Evidence: same as above

**`input_validation`** — **Met**
> Untrusted API responses are never trusted blindly: JSON decoding of
> attacker-controlled payloads runs inside `pcall`; decoded structures are
> consumed field-by-field; unexpected shapes degrade to a localized error
> string rather than propagating raw data.
Evidence: `src/auth.lua` (JSON-parse pcall block), `src/http.lua`
(`_request_with_retry`), `docs/adr/0008-string-return-error-pattern.md`

**`hardening`** — **Met**
> Retry-with-backoff on 5xx, `Retry-After` honoring on 429 with a
> wall-clock cap, an egress allowlist CI gate, and a redact-before-log
> pipeline for every log line.
Evidence: `src/http.lua`, `SECURITY.md#lieferketten-kontrollen`

**`assurance_case`** — **Met**
> A dedicated assurance-case section names protected assets, trust
> boundaries, a threat/mitigation table, and accepted residual risks.
Evidence: `SECURITY.md#assurance-case`

---

## Analysis

**`static_analysis_common_vulnerabilities`** — **Met**
> Semgrep `p/security-audit` and `p/secrets` rulesets run on every push
> and pull request; results upload to GitHub code-scanning.
Evidence: `.github/workflows/sast.yml`

**`dynamic_analysis_unsafe`** — **N/A**
> Lua is a memory-safe language; this criterion applies only to
> memory-unsafe languages (C/C++), which this project does not use.
Evidence: (n/a by language choice)

---

## Notes for the transcriber

- The BadgeApp UI groups a few of these differently and pre-fills some
  fields from repo metadata (license, URL, description) — skip those.
- Six criteria are answered honestly as **Unmet**: `bus_factor`,
  `documentation_achievements` (temporarily, until the Passing badge
  exists), `accessibility_best_practices`, `internationalization`,
  `external_dependencies`, `dependency_monitoring`,
  `updateable_reused_components`. That is seven, all either genuinely
  structural (solo maintainer) or a concrete, named follow-up (Lua
  toolchain pinning) — not hand-waving.
- If bestpractices.dev computes a percentage below the Silver threshold
  after transcription, the three `external_dependencies` /
  `dependency_monitoring` / `updateable_reused_components` "Unmet"
  answers are the ones with the clearest fix: add a `.rockspec` (or
  equivalent) pinning `busted`/`luacheck`/`luacov`/`dkjson` to exact
  versions, commit it, and CI installs from it instead of "latest". That
  is a real engineering change (touches `tools/`, possibly `ci.yml`) and
  was deliberately left out of this docs-only pass — open a follow-up
  issue if you want it done.
