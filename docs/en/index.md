# MoneyMoney PayPal POS Extension

A community extension for [MoneyMoney](https://moneymoney.app) (macOS
personal-finance app) that adds PayPal POS (formerly Zettle) as a
supported account type — card transactions, refunds, fees, and payouts
surfaced directly in MoneyMoney.

## Quick Start

1. **[Full README](readme.md)** — Installation, API-key generation
   (scopes `READ:PURCHASE` + `READ:FINANCE`), GoBD guidance for German
   bookkeeping, signed-release verification.
2. **[Security policy](security.md)** — Responsible-disclosure pipeline.
3. **[Contributing](contributing.md)** — Local development setup,
   Conventional Commits, test and coverage expectations.

## Architecture

Architecture decisions are documented as MADR-format ADRs under
**[Architecture (ADRs)](adr/0001-amalgamator-design.md)**:

- Amalgamator design (ADR-0001)
- LocalStorage token cache (ADR-0002)
- Sandbox probes (ADR-0003)
- Finance API scope (ADR-0004)
- Resilience invariants (ADR-0005)
- JWT bearer auth (ADR-0006)
- No TLS pinning (ADR-0007)
- String-return error pattern (ADR-0008)
- OpenSSF Scorecard stance (ADR-0009)

## Status

Active development; no installable release yet. Current capabilities
and the contribution path are described in the
[repository README](https://github.com/yves-vogl/moneymoney-paypal-pos-extension)
and in the [changelog](changelog.md).
