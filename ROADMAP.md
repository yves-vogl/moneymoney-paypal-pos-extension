# Roadmap

This roadmap covers the next twelve months (from 2026-08) and satisfies the
OpenSSF Best Practices (Silver tier) criterion `documentation_roadmap`. The
project is **feature-complete for its stated scope** — a MoneyMoney
WebBanking extension surfacing PayPal POS (Zettle) card turnover, refunds,
fees and payouts — and is in **active maintenance mode**.

Authoritative, always-current planning lives in the
[GitHub issue tracker](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues);
this file states the standing commitments and the known larger items.

## Standing commitments (continuous)

- **API compatibility**: track changes to the Zettle OAuth, purchase and
  finance endpoints; ship fixes when upstream behaviour changes. Breakage
  reports via issues are prioritised.
- **MoneyMoney compatibility**: verify the extension against new MoneyMoney
  releases; adapt if the WebBanking API surface changes.
- **Security response**: per [`SECURITY.md`](SECURITY.md) —
  acknowledgement ≤ 72 h, first assessment ≤ 7 days, prioritised fix
  releases for critical issues.
- **Dependency hygiene**: weekly Dependabot cadence for GitHub Actions and
  the pinned CI toolchain; lockfiles regenerated via `pip-compile` when
  grouped bumps break hash-pin consistency.
- **Supply-chain posture**: keep the Scorecard-measurable controls from
  `SECURITY.md` (pinned actions, blocking SAST, signed releases,
  reproducible build) green.

## Planned items (next 12 months)

| Item | Status | Tracking |
|------|--------|----------|
| OpenSSF Best Practices **Passing** badge (self-assessment on bestpractices.dev) | maintainer task, open | [#42](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues/42) |
| OpenSSF Best Practices **Silver** tier pursuit (governance/DCO/roadmap docs shipped; badge entry pending) | in progress | [#42](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues/42) |
| Maintenance releases (v1.0.x / v1.1.x) as fixes accumulate | as needed | [Releases](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases) |

## Explicit non-goals

- Support for payment providers other than PayPal POS (Zettle).
- A settings UI beyond MoneyMoney's credential fields.
- Bundling third-party Lua libraries into the artifact beyond what
  MoneyMoney's runtime provides.

Feature requests outside this scope are welcome as issues, but expect a
conservative default: this extension deliberately stays small, auditable and
reproducible.

## Support policy

Only the **latest release** receives fixes (see the supported-versions table
in `SECURITY.md`). There is no LTS branch; upgrading means replacing a
single `.lua` file, so staying current is cheap by design.
