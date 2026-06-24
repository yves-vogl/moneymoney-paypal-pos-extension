# ADR-0009: OpenSSF Scorecard Stance

## Status

ACCEPTED

## Date

2026-06-23

## Deciders

Yves Vogl

## Context

The OpenSSF Scorecard is an automated assessment of a repository's
supply-chain security posture across ~18 checks (Pinned-Dependencies,
Token-Permissions, Branch-Protection, SAST, Code-Review, Fuzzing,
Maintained, Packaging, Signed-Releases, CII-Best-Practices, etc.). Each
check returns a score on the 0–10 scale; the aggregate is the average of
the applicable checks.

A baseline run against this repository post-Phase-6 returned an aggregate
of **5.2 / 10** with the following per-check breakdown (the five gaps that
matter for the stance taken in this ADR):

| Check | Baseline score | Disposition |
|-------|----------------|-------------|
| Fuzzing | 0 / 10 | accepted gap |
| Code-Review | 0 / 10 | accepted gap |
| Packaging | -1 (N/A) | structural N/A |
| Contributors | 6 / 10 | partial — accepted, structural ceiling (already passes Scorecard's threshold; see P6.1-R-09 below) |
| Maintained | 0 / 10 | heals-itself |

Phase 6.1 was scoped to lift the aggregate by hardening every check whose
gap is genuinely fixable in a solo-maintainer setting (Pinned-Dependencies,
Token-Permissions, Branch-Protection introspectability, SAST, CII Best
Practices, gitleaks explicit config, Dependabot grouping). The five gaps
listed above resist that path for the reasons documented below.

Two **upstream-timed** events affect the aggregate independently of any
change in this repository:

1. `ossf/scorecard#5103` — open upstream PR that adds Semgrep to the SAST
   detection list. Once merged, the `SAST.score` for this repo
   automatically flips from 0 to 10 on the next nightly Scorecard run,
   because the Semgrep workflow (Plan 06.1-03) is already live and
   ERROR-blocking.
2. **Repo-age ≥ 90 days** — the `Maintained` check returns 0 until the
   repository is at least 90 days old. Repo created ~2026-06-15; healing
   point ~2026-09-15. No action required.

References:

- OpenSSF Scorecard project — https://github.com/ossf/scorecard
- Phase 6 R1 and R2 security reviews — `.planning/phases/06-release-polish/`
- Plan 06.1-01..04 hardening commits (89f4ee4, 7d12378, 035522f, c9a8c1a,
  c515dfe, 27d7476, 184b2f6, 93684aa, d506bda)
- Plan 06.1-06 MkDocs site (ca006fc, 773b166, a89b39b)
- P6.1-R-08 note: SHAs above reference the pre-squash Phase-6.1 branch
  history; Phase 6.1 was squash-merged into `main` as a single commit
  (`c6a9865`, PR #16). The 7-char SHAs are stable references inside the
  phase-branch's history (still resolvable via `git log --all`) and were
  normalised here to 7-char form for consistency with other ADRs.
- 06.1-RESEARCH §4 (Branch-Protection options), §5 (SAST detection),
  §10 (revised aggregate target), §11 (per-gap acceptance text)

## Decision

The project adopts the following stance toward the OpenSSF Scorecard:

1. **Ship the five Phase-6.1 hardening PRs** (Plans 06.1-01 through
   06.1-06 plus this consolidating Plan 06.1-08) — pinned actions,
   least-privilege tokens, Semgrep SAST, branch-protection introspection
   via `SCORECARD_READ_TOKEN`, explicit gitleaks config, Dependabot
   grouping, MkDocs documentation site, CII Best Practices passing badge
   (Plan 06.1-07, gated on Yves' questionnaire).
2. **Accept Branch-Protection at Tier 1 = score >= 3 / 10** per
   06.1-RESEARCH §4 Option A. Solo single-account maintainer constraint;
   neither Option B (1-reviewer second-account) nor Option C
   (bot-reviewer) is adopted (see Alternatives Considered).
3. **Accept SAST = 0 short-term** until `ossf/scorecard#5103` merges. The
   Semgrep workflow is live and ERROR-blocking, so the underlying security
   control is in place; only Scorecard's *detection* of it is missing.
4. **Revise the aggregate target** from "≥ 8.5" (the original ROADMAP
   value) to:
   - **≥ 7.5 short-term** — realistic given the five accepted gaps.
   - **≥ 8.5 once both upstream-timed events resolve** —
     `ossf/scorecard#5103` merges (SAST 0 → 10) AND repo age crosses 90
     days (Maintained 0 → 8+).

### The five accepted gaps

**Fuzzing (0 / 10).** This extension is a thin Lua wrapper around a
remote HTTPS API. It contains no parser, codec, wireformat decoder, or
binary protocol implementation — only JSON response handling via the
MoneyMoney-built-in `JSON()` helper and integer arithmetic on
minor-currency-unit amounts. OSS-Fuzz / ClusterFuzzLite produce no
findings on wrapper code because there is no input surface for them to
attack: every byte that enters the extension was either (a) emitted by
the Zettle/PayPal POS API over TLS, (b) typed into MoneyMoney's
credentials dialog, or (c) read from `LocalStorage` previously written by
the extension itself. Compensating: the busted unit-test suite includes
fixture-driven edge-case tests on every response shape we receive
(mid-page errors, malformed JSON, off-by-one timestamps, multi-page
pagination boundaries); property-based tests for the mapping layer are a
backlog item but not gating.

**Code-Review (0 / 10).** Scorecard's Code-Review check requires that the
default branch's recent commits show approval by a user *different from
the commit author*. Solo single-account maintainer — every commit is
authored and (when merged via PR) approved by the same GitHub identity.
Compensating: GPG-signed commits with the maintainer key
`FDE07046A6178E89ADB57FD3DE300C53D8E18642`; branch protection with
required signed commits and linear history; required PR for every change
to `main` (force-push and delete blocked, admin bypass disabled);
post-merge security re-reviews via the `loop-security-engineer` agent on
every Phase-N→main merge; the Phase-6 review batch caught and remediated
1 BLOCKER + 1 CRITICAL + 6 HIGH findings before the v1.0.0 tag, which is
the substantive equivalent of distributed code review.

**Packaging (-1 / N/A).** This extension is distributed as a single
`paypal-pos.lua` artifact attached to GitHub Releases. There is no
LuaRocks, npm, PyPI, or equivalent package-registry publish path that
makes sense for MoneyMoney extensions — MoneyMoney loads single-file
extensions from a user-managed folder, not from a package registry.
Scorecard's Packaging check has no mode that matches this distribution
model; -1 (N/A) is the correct value. Compensating: SHA256 checksum file
shipped alongside the artifact (BUILD-05); reproducible build verified
in CI (BUILD-02); GPG-signed git tags trigger the release pipeline
(BUILD-04).

**Contributors (6 / 10).** Scorecard auto-detects that Yves' git
commits use his work email at adesso SE; the check counts adesso SE as
one of the project's "organisations". Structural: a single-organisation
project will not score higher on this check until external contributors
join. **P6.1-R-09 clarification:** 6 / 10 already passes Scorecard's
Contributors threshold (the check rewards >= 2 distinct contributing
organisations; 1 org yields a partial score, not the floor). Listed
here as "partial — accepted, structural ceiling" rather than "gap" —
this is the highest score the check will return until external
contributors land, and no further compensating control is meaningful
at the project's current scale. Compensating: open-source-under-MIT
licence (BUILD-07 / DOC-07) that explicitly welcomes contributions;
`CONTRIBUTING.md` documents the contribution workflow; the project has
an explicit no-CLA policy.

**Maintained (0 / 10).** Scorecard's Maintained check requires the
repository to be at least 90 days old (and to show activity in that
window). Repo created ~2026-06-15; the check will return 0 until
~2026-09-15 and then auto-heals to 8+ assuming continued activity. No
action required.

### Compensating mitigations across all five gaps

The combined posture (active controls that compensate for the
non-scoring gaps above) is enumerated in `SECURITY.md` "Lieferketten-
Kontrollen / Supply-chain controls":

- Semgrep SAST (`p/security-audit` + `p/secrets`, ERROR-blocking, SARIF
  to code-scanning) — security control in place; Scorecard score
  reporting deferred per `ossf/scorecard#5103` (SEC-08).
- Reproducible build via `lua tools/build.lua --verify` (BUILD-02).
- TLS-only egress via MoneyMoney's `Connection()` defaults (no opt-out
  exists; ADR-0007).
- Redact-before-log: every `print()` call routes through `M_log.*` which
  strips JWT and `Bearer ` substrings (SEC-01 / D-79 gate).
- Egress allowlist: CI greps the built artifact to assert only
  `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com` are
  referenced (SEC-04 / D-12).
- GPG-signed commits enforced via branch protection (SEC-05).
- GPG-signed git tags trigger releases (`verify-signed-tag` job —
  BUILD-04).
- Pinned GitHub Actions to commit-SHA with `# vX.Y.Z` comment (SEC-06).
- Least-privilege workflow tokens (`permissions: read-all` top-level,
  job-local writes — SEC-07).
- Branch protection on `main`: PR required, signed commits, linear
  history, force-push + delete blocked, no admin bypass, 5 required
  status checks (SEC-05).
- Gitleaks secret scan with explicit `.gitleaks.toml` config and
  per-fingerprint `.gitleaksignore` allowlist (CI-05).
- CII Best Practices Passing-tier badge (BUILD-07; landing via Plan
  06.1-07).
- MkDocs Material documentation site (D-37) at
  `https://yves-vogl.github.io/moneymoney-paypal-pos-extension/`.

### Backlog (silver-tier and upstream tracking)

- **CII Best Practices → Silver.** Tracked as a post-v1.0.0 backlog
  issue. Estimated +3 h of additional questionnaire effort. Not gating
  for v1.0.0 release.
- **Track `ossf/scorecard#5103`.** Tracked as a backlog issue. Once
  merged upstream, the next nightly Scorecard run flips `SAST.score`
  from 0 to 10 with no further change in this repository.
- **SBOM + Sigstore/cosign attestation + SLSA Provenance Level 3** —
  deferred to v1.1.x per D-38. Upgrade path documented below.

## Consequences

Landing this ADR means:

- The realistic Scorecard target communicated to external auditors is
  ≥ 7.5 short-term, ≥ 8.5 once `ossf/scorecard#5103` merges and repo age
  crosses 90 days. The original ROADMAP target of ≥ 8.5 is revised in
  ROADMAP.md success-criteria block.
- Future nightly Scorecard runs are interpreted against this baseline —
  a drop of the aggregate below 7.5 (after the upstream-timed events) is
  a regression worth investigating; a Branch-Protection score of 3 is
  not a regression.
- Two backlog issues opened post-merge (Yves task; see Backlog above
  and the SUMMARY for this plan):
  1. `CII Best Practices → Silver` linked from this ADR.
  2. `Track ossf/scorecard#5103 merge for Semgrep SAST detection`
     linked from this ADR + SEC-08 acceptance text.
- The SEC-05 expansion + SEC-06 / SEC-07 / SEC-08 / BUILD-07 acceptance
  bars are formally recorded in `.planning/REQUIREMENTS.md`; DOC-11 is
  closed by this plan.
- `SECURITY.md` carries a bilingual "Lieferketten-Kontrollen /
  Supply-chain controls" section so an external researcher can audit
  the supply-chain posture without parsing CI YAML.

## Alternatives Considered

**Branch-Protection Option B — 1 reviewer, second-account
self-approval.** Rejected per 06.1-RESEARCH §4. Trade-off: lifts
Branch-Protection from 3 → 8, requires Yves to maintain a second
authenticated GitHub account and approve every PR via a separate
browser profile. Operationally feasible but the accepted-gap policy
(do not introduce process scaffolding that exists only to satisfy a
score) prevails. Revisit if a real second maintainer joins the project.

**Branch-Protection Option C — bot reviewer (CodeRabbit / Greptile /
Diamond).** Rejected per D-35 and ADR-0008 lineage. Trade-off: lifts
both Branch-Protection and Code-Review checks to ≥ 8 each. Costs
USD 20-50 / month, adds an external SaaS dependency that the project's
no-telemetry / no-third-party-dependency constraint (CLAUDE.md → "What
NOT to use" → telemetry row) forbids. Revisit if/when a self-hosted
reviewer bot exists that meets the no-telemetry bar.

**Snyk Code as a second SAST tool.** Rejected per 06.1-RESEARCH §5
Option C. Trade-off: lifts `SAST.score` from 0 → 10 immediately
(Scorecard's SAST check detects Snyk natively). Adds an external-service
dependency; partial Lua coverage; subject to Snyk's commercial-tier
changes. Wait for `ossf/scorecard#5103` instead — same outcome, no
external dependency, no commercial-tier exposure.

**SBOM + cosign attestation + SLSA Provenance Level 3 in Phase 6.1.**
Rejected per D-38. Trade-off: would land the artefacts in 6.1 but the
Scorecard `Signed-Releases` check only fires AFTER a release exists;
Phase 6.1 does not produce a release. Defer to a v1.1.x supply-chain
follow-up phase. Upgrade path (concrete YAML diff in 06.1-RESEARCH §7):
add `actions/attest-build-provenance@<SHA>` to `release.yml`'s publish
job; add CycloneDX SBOM generation step before publish; add `cosign
sign-blob` step on `paypal-pos.lua` using the GPG-trust-rooted Sigstore
identity. All three are SHA-pinnable and fit the Phase-6.1 hardening
baseline.

**G-09 awk shell-interpolation fix as full hardening.** Accepted as
low-severity per 06.1-RESEARCH §11 #9. The theoretical injection
requires a malicious git tag name; `release.yml`'s
`on: push: tags: ['v[0-9]+...']` pattern + the `verify-signed-tag` gate
block this path. Plan 06.1-01 still replaced the `awk | sed | cut`
anti-pattern with a single safe shell expansion — the awk-injection
defence happens to land alongside without being a separately-tracked
mitigation.

**Lua-specific Semgrep community rules (`p/lua-community`).** Rejected
per D-34. ~15 rules in the public ruleset, most irrelevant for an API
wrapper (the rules target Nginx config patterns, OpenResty handlers,
and load-balancer scripting — none of which apply here). Revisit if a
false-negative in Phase-2/3 ever motivates a coverage gap.

**`p/ci` Semgrep ruleset for GitHub-Actions hardening.** Rejected per
D-34. The threat model the `p/ci` rules cover is already addressed by
SEC-06 (pinned actions to commit-SHA, comment-anchored) and SEC-07
(`permissions: read-all` top-level, job-local writes); the Semgrep
overlap would produce duplicate findings against the same code surface.
