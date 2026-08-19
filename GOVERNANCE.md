# Governance

This document describes how the MoneyMoney PayPal POS extension project is
governed. It exists to satisfy the OpenSSF Best Practices (Silver tier)
criteria `governance`, `roles_responsibilities`, `access_continuity` and
`bus_factor`, and — more importantly — to make explicit how decisions are
made so contributors know what to expect.

## Governance model

The project uses a **single-maintainer ("benevolent dictator") model**.

- **Maintainer:** Yves Vogl ([@yves-vogl](https://github.com/yves-vogl)),
  GPG fingerprint `FDE07046 A617 8E89 ADB5 7FD3 DE30 0C53 D8E1 8642`
  (published on `keys.openpgp.org`).

The maintainer has final decision authority on scope, releases, and disputed
changes. Day-to-day decisions happen in the open via GitHub issues and pull
requests; architectural decisions are recorded as MADR-format Architecture
Decision Records in [`docs/adr/`](docs/adr/).

## Roles and responsibilities

| Role | Who | Responsibilities |
|------|-----|------------------|
| Maintainer | @yves-vogl | Reviews and merges PRs, cuts GPG-signed releases, triages issues, handles vulnerability reports per [`SECURITY.md`](SECURITY.md), maintains CI and branch protection, owns the ADR log. |
| Contributor | anyone | Proposes changes via PRs that follow [`CONTRIBUTING.md`](CONTRIBUTING.md) (tests, luacheck, Conventional Commits, DCO sign-off), reports bugs via issues, reports vulnerabilities privately per `SECURITY.md`. |

There are currently no intermediate roles (committers, triagers). If the
contributor base grows, additional maintainers can be nominated by the
existing maintainer based on a track record of high-quality contributions;
the nomination and its rationale will be documented in a public issue.

## Decision process

1. **Small changes** (bug fixes, docs, dependency bumps): a PR that passes
   the required CI gates and maintainer review is sufficient.
2. **Behavioural or architectural changes**: open an issue first. If the
   change alters an invariant documented in an ADR, the PR must include a
   new or superseding ADR in `docs/adr/`.
3. **Disputes**: the maintainer decides and documents the rationale in the
   issue or ADR. Forking is always a legitimate outcome — see below.

## Access continuity ("bus factor")

The project honestly has a bus factor of **1** (single maintainer). The
following structural mitigations ensure the project can outlive the
maintainer's unavailability:

- **MIT license** — anyone may fork and continue the project without legal
  friction.
- **Reproducible build** — `lua tools/build.lua --verify` produces a
  byte-identical artifact from public sources; no private build machine or
  secret build input exists.
- **No private infrastructure** — everything needed to build, test, and
  release lives in this public repository (CI definitions included). The
  only maintainer-private materials are the GPG release-signing key and the
  `SCORECARD_READ_TOKEN` PAT; a successor fork would generate its own,
  publish the new fingerprint, and users would verify against it.
- **Complete contributor documentation** — `CONTRIBUTING.md` documents the
  full development loop; CI is the executable specification of the quality
  gates.
- **Signed history** — all commits and release tags are GPG-signed, so a
  successor can cryptographically establish the last authentic state.

If the maintainer is unresponsive for more than 90 days on a critical issue
(e.g. an unpatched vulnerability), community members are encouraged to fork
under a new name and reference this repository. MoneyMoney users can switch
extensions by replacing a single `.lua` file.

## Changes to this document

Changes to governance are proposed via PR like any other change and take
effect when merged by the maintainer.
