# MoneyMoney PayPal POS Extension

> Community extension for [MoneyMoney](https://moneymoney.app) (macOS personal-finance app) that adds PayPal POS (formerly Zettle) card transactions, refunds, fees, and payouts to MoneyMoney.

[![CI](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml)
[![Coverage](https://raw.githubusercontent.com/yves-vogl/moneymoney-paypal-pos-extension/coverage-badge/coverage.svg)](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/yves-vogl/moneymoney-paypal-pos-extension/badge)](https://securityscorecards.dev/viewer/?uri=github.com/yves-vogl/moneymoney-paypal-pos-extension)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/yves-vogl?logo=githubsponsors&logoColor=white&label=Sponsors&color=ea4aaa)](https://github.com/sponsors/yves-vogl)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Status: Pre-Release](https://img.shields.io/badge/Status-Pre--Release-orange.svg)](README.de.md#status)
[![Lua 5.4](https://img.shields.io/badge/Lua-5.4-blue.svg?logo=lua&logoColor=white)](https://www.lua.org/)
[![MoneyMoney](https://img.shields.io/badge/MoneyMoney-Extension-3b8dbd.svg)](https://moneymoney.app/extensions/)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://www.conventionalcommits.org)
[![GPG-signed commits](https://img.shields.io/badge/GPG-signed%20commits-success.svg)](README.de.md#verifikation-signierter-releases)

---

## Primary documentation

This extension's primary user documentation is German, because its primary audience is German sole proprietors and small merchants using PayPal POS for card-present payments. See **[README.de.md](README.de.md)** for:

- Step-by-step installation guide (with screenshots for the "Inoffizielle Extensions erlauben" toggle).
- API-Key setup walkthrough (Zettle scopes `READ:PURCHASE` + `READ:FINANCE`).
- GoBD-Hinweis for German accounting expectations.
- Privacy & security guarantees (no telemetry, read-only, API key never logged).
- Release verification recipe (SHA256 sidecar + GPG-signed tag).

---

## What this extension is and isn't (English summary)

**It is:** a read-only adapter between PayPal POS / Zettle's APIs and MoneyMoney. The shipped artifact is a single Lua file (`paypal-pos.lua`) loaded by MoneyMoney's embedded Lua 5.4 sandbox. Every release is published from a GPG-signed git tag, with a SHA256 sidecar and a reproducible build (`lua tools/build.lua --verify`).

**It is not:** an accounting tool. It does NOT classify revenue, does NOT claim GoBD or DATEV conformance, and does NOT replace a tax advisor. It reads raw transaction data and presents it in MoneyMoney's transaction list — classification of the resulting entries is the responsibility of the merchant's bookkeeping or accountant.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development loop (Lua 5.4 + busted + luacheck + luacov), TDD conventions, amalgamator architecture (`tools/build.lua`), the release process (GPG-signed tag → `release.yml` → `softprops/action-gh-release@v2`), and the Conventional Commits + GPG-signed-commits requirements enforced by branch protection on `main`.

Bug reports → [Issues](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues). Questions and ideas → [Discussions](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/discussions).

---

## License

[MIT](LICENSE) — Copyright (c) 2026 Yves Vogl <yves@kadenz.live>.

---

## Disclaimer

This is an **unofficial community project**. Neither **MoneyMoney GmbH** nor **PayPal / Zettle** are publishers, sponsors, or otherwise responsible for this extension. All trademarks belong to their respective owners.
