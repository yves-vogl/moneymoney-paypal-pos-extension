# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project scaffolding under `.planning/` (PROJECT, REQUIREMENTS, ROADMAP, STATE, research).
- MIT license, `.gitignore`, German-language README, GPG-verification documentation.
- GPG-signed commits and tags enforced via branch protection (`required_signatures`, `required_linear_history`).

### Planned for v0.1.0

- PayPal POS / Zettle JWT-bearer authentication flow.
- Sales transactions, refunds, fees, payouts visible in MoneyMoney.
- Tip and VAT breakdown in transaction memo.
- German user-facing strings throughout.
- Reproducible single-file Lua artifact built from `src/` via deterministic amalgamator.
- SHA256 checksum and GPG signature published with every release.

[Unreleased]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/commits/main
