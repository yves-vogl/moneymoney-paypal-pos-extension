# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project scaffolding under `.planning/` (PROJECT, REQUIREMENTS, ROADMAP, STATE, research).
- MIT license, `.gitignore`, German-language README, GPG-verification documentation.
- GPG-signed commits and tags enforced via branch protection (`required_signatures`, `required_linear_history`).
- Phase 1 source-tree foundations: deterministic amalgamator (`tools/build.lua` + `tools/manifest.txt`) with pure-Lua SHA-256 and `--verify` byte-identical check; `src/` module layout with `webbanking_header.lua`, `log.lua` (SEC-01 redactor), `i18n.lua` (DE/EN tables), and `entry.lua` walking skeleton.
- Test harness: `spec/helpers/mm_mocks.lua` mocking the full MoneyMoney embedded-interpreter surface; 40 busted tests (build, mocks, redaction, i18n, entry); 99.19 % luacov line coverage on the amalgamated artifact.
- Sandbox probe extension `tools/probe.lua` (Q1/Q4/Q5/Q7/Q8) and ADR-0003 template; ADR-0001 (amalgamator design) accepted.
- GitHub Actions CI workflow (`.github/workflows/ci.yml`): luacheck, busted, 85 % coverage threshold gate, self-hosted coverage badge generation + push to `coverage-badge` branch (only on `main` pushes), reproducible-build check, `DEBUG = false` gate, egress allowlist gate, no-AI-attribution gate. Pinned to `ubuntu-24.04`, Lua 5.4 via `leafo/gh-actions-lua@v13`.
- README badges: CI status, self-hosted Coverage, OpenSSF Scorecard, GitHub Sponsors, MIT, Pre-Release status, Lua 5.4, MoneyMoney-Extension, Conventional Commits 1.0.0, GPG-signed commits. The coverage badge is served from the repo's own `coverage-badge` branch via `raw.githubusercontent.com` — no third-party renderer or coverage host.
- OpenSSF Scorecard workflow (`.github/workflows/scorecard.yml`): weekly + on `main` push + on branch-protection-rule changes. Analyses the repo against the 18 supply-chain-security checks and publishes the score to `api.securityscorecards.dev` (Linux Foundation public-good infrastructure). SARIF results are also uploaded to GitHub code-scanning for in-repo review.
- GitHub Sponsors funding metadata (`.github/FUNDING.yml`) and README *Unterstützen* section.

### Planned for v0.1.0

- PayPal POS / Zettle JWT-bearer authentication flow.
- Sales transactions, refunds, fees, payouts visible in MoneyMoney.
- Tip and VAT breakdown in transaction memo.
- German user-facing strings throughout.
- Reproducible single-file Lua artifact built from `src/` via deterministic amalgamator.
- SHA256 checksum and GPG signature published with every release.

[Unreleased]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/commits/main
