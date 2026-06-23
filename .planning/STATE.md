---
gsd_state_version: 1.0
milestone: v1.0.0
milestone_name: has stabilized in production for several weeks.
status: v1.0.0-shipped-pending-tag-and-6.1-shipped
last_updated: "2026-06-23T14:30:00.000Z"
progress:
  total_phases: 7
  completed_phases: 7
  total_plans: 38
  completed_plans: 38
  percent: 100
---

# Project State: MoneyMoney PayPal POS Extension

**Initialized:** 2026-06-16
**Last updated:** 2026-06-23 (Phase 6.1 closed via Plan 06.1-08; pending PR + merge to main)

---

## Project Reference

**Core Value:**
> A German PayPal POS merchant pastes their API key into MoneyMoney once and from then on sees every card transaction, refund, fee, and payout automatically in MoneyMoney — accurately, on schedule, with VAT and tip transparency suitable for bookkeeping.

**Current Focus:** Phase 6.1 (OpenSSF Scorecard hardening) closed by Plan 06.1-08; awaiting PR open + merge to `main`. Phase 6 already SHIPPED via PR #14 (`d1e1003`); v1.0.0 tag publication gated on Yves CP-4 + CP-5.

**Granularity:** standard (7 phases)
**Mode:** mvp / yolo

---

## Current Position

Phase: **6.1 (supply-chain-scorecard-hardening) — SHIPPED 2026-06-23** (pending PR merge; commits on `phase-6.1/scorecard-hardening`).
Phase: **06 (release-polish) — MERGED 2026-06-23** via PR #14 (squash; `d1e1003`).

### Yves Checkpoints (Phase 6) — CP-1..CP-5 post-Phase-6 status

| ID | Item | Owner | Status |
|----|------|-------|--------|
| CP-1 | loop-lektor pass on README.de.md + CHANGELOG [1.0.0] + 4 new ADRs + CONTRIBUTING | autonomous (lektor agent) | **DONE 2026-06-23** — 36 findings (5 HIGH); cleanup batch landed in 4 commits (33986b0/0a929c8/193e9ca/e17001b); merged via PR #14 |
| CP-2 | Branch protection: `bash tools/setup-branch-protection.sh` | orchestrator | **DONE 2026-06-23** — verified via `gh api …/branches/main/protection`: enforce_admins=true, 3 required checks, linear_history=true, allow_force_pushes=false, allow_deletions=false, required_signatures=true |
| CP-3 | Repo metadata: `bash tools/setup-repo-metadata.sh` | orchestrator | **DONE 2026-06-23** — description + 7 topics |
| CP-4 | v1.0.0 tag publication: `git tag -s v1.0.0 -m "Release v1.0.0"` → `git push origin v1.0.0` | **Yves** | **pending** — gated on CP-5 and on setting `MAINTAINER_GPG_PUBKEY` repo secret |
| CP-5 | Capture real screenshots for `docs/img/inoffizielle-extensions-erlauben.png` + `docs/img/help-menu-extensions-folder.png` | **Yves** ("die Tage") | **pending — reminder for orchestrator to surface at session start** |

### Yves Checkpoints (Phase 6.1) — CP-6.1-A..CP-6.1-D + CP-Post-08

| ID | Item | Owner | Status |
|----|------|-------|--------|
| CP-6.1-A | Provision `SCORECARD_READ_TOKEN` repo secret (fine-grained PAT, `Administration:read`, ≤1y expiry) | **Yves** | **pending — post-merge of Phase 6.1 PR** |
| CP-6.1-B | Re-run `tools/setup-branch-protection.sh` to lift CHECKS array to 5 entries (CI + Scorecard + Semgrep + gitleaks + commit-lint) | **Yves** | **pending — post-merge of Phase 6.1 PR, after CP-6.1-A** |
| CP-6.1-C | Enable GitHub Pages with source = "GitHub Actions" so docs site deploy can publish | **Yves** | **pending — pre-first-deploy of MkDocs site** |
| CP-6.1-D | Complete CII Best Practices self-assessment questionnaire to earn passing badge (BUILD-07; gates Plan 06.1-07) | **Yves** | **pending off-repo** |
| CP-Post-08 | Open 2 backlog issues: (a) `CII Best Practices → Silver`, (b) `Track ossf/scorecard#5103 merge for Semgrep SAST detection` | **Yves** | **pending — post-merge of Plan 06.1-08** |

---

### Phase 6 ship summary

PR #14 merged 2026-06-23T01:38:21Z as `d1e1003d`. Composition: 14 implementation commits (06-01/02/03) + 1 CI-fix (1468018) + 10 fix-batch commits (e1b0736..b68d57a addressing 1 verifier BLOCKER + 1 CRITICAL + 6 HIGH from R1 reviewer/security) + 4 lektor cleanup commits (33986b0..e17001b).

Final test status at merge: 388 successes / 0 failures / 0 errors / 0 pending. Reproducible build SHA: dev `18bb7a6ae43d8b9c60951f13afe7476b19c2854256a07e42cfeca9e73d58e0c1`. v1.0.0-tagged SHA differs because `__VERSION__` substitutes to `1.0` instead of `<DEV BUILD>`.

### Phase 6.1 ship summary

Phase 6.1 closed 2026-06-23 via Plan 06.1-08. All 8 plans executed (06.1-01 through 06.1-08, excluding 06.1-07 which gates on CP-6.1-D Yves off-repo questionnaire — placeholder slot reserved in README badge cluster). Composition:

- **06.1-01** (89f4ee4, 7d12378): SHA-pin 17 action references across 4 workflows; `permissions: read-all` top-level; `persist-credentials: false`.
- **06.1-02** (035522f): explicit `.gitleaks.toml` config.
- **06.1-03** (c9a8c1a, c515dfe, 27d7476): Semgrep SAST workflow (ERROR-blocking, SARIF in code-scanning).
- **06.1-04** (184b2f6, 93684aa, d506bda): wire `SCORECARD_READ_TOKEN` into scorecard.yml; extend `setup-branch-protection.sh` CHECKS to 5 entries + S-R2-L-01 post-conditions.
- **06.1-05** (a7754218): Dependabot github-actions minor+patch grouping.
- **06.1-06** (ca006fc, 773b166, a89b39b, b532838): MkDocs Material site + GitHub Pages workflow + bilingual Documentation/Dokumentation badge.
- **06.1-07** (deferred): CII Best Practices badge — gates CP-6.1-D.
- **06.1-08** (this plan): ADR-0009, SECURITY.md supply-chain section, REQUIREMENTS.md SEC-05 modify + SEC-06/07/08/BUILD-07/DOC-11 append, ROADMAP.md success criteria revision + Phase 6.1 marked [x], mkdocs.yml ADR-0009 nav un-comment.

### Branch state on `main`

```
d1e1003 Phase 6: Release & Polish — Reproducible Build, CI/CD, German Docs (#14)
2102bda docs(state): Phase 6 SHIPPED — STATE.md transition + Phase 6.1 unblock (#15)
9bc6c8f Phase 5: Resilience & Error Handling (#13)
74f644c Phase 4: Enrichment — Refunds, Fees, Payouts, Balance, VAT, Tips (#11)
a201f6c docs(03): Phase 3 verifier report — READY-TO-MERGE closure (#10)
a11287d Phase 3: Sale Spine (first user-visible slice) (#8)
```

```
Phase 1: Foundations & Sandbox Probes          [DONE — merged]
Phase 2: Authenticated Network Layer           [DONE — PR #6 + #7]
Phase 3: Sale Spine                            [DONE — PR #8 + #10]
Phase 4: Enrichment                            [DONE — PR #11]
Phase 5: Resilience & Error Handling           [DONE — PR #13]
Phase 6: Release & Polish                      [DONE — PR #14]
Phase 6.1: OpenSSF Scorecard Hardening         [DONE — pending merge of phase-6.1/scorecard-hardening]
```

---

## Active Todos (carry-over watch-items)

- **Phase 6.1 PR (orchestrator)** — open PR for `phase-6.1/scorecard-hardening` → `main`. After merge, Yves runs CP-6.1-A/B/C/Post-08.
- **CP-4 v1.0.0 tag (Yves)** — after CP-5; sets the `MAINTAINER_GPG_PUBKEY` repo secret, then signs the tag and pushes. Triggers release.yml automatically.
- **CP-5 docs/img screenshots (Yves, "die Tage")** — Inoffizielle-Extensions + Help-Menu-Extensions screenshots. Currently 68-byte placeholders.
- **CP-6.1-A SCORECARD_READ_TOKEN (Yves)** — fine-grained PAT, `Administration:read`, ≤1y expiry; provisioned via `gh secret set SCORECARD_READ_TOKEN`. Required before scorecard.yml introspection works.
- **CP-6.1-B re-run setup-branch-protection.sh (Yves)** — lifts required-status-checks count to 5 (CI + Scorecard + Semgrep + gitleaks + commit-lint).
- **CP-6.1-C enable GitHub Pages (Yves)** — source = "GitHub Actions"; pre-first-deploy of MkDocs site.
- **CP-6.1-D CII questionnaire (Yves)** — off-repo questionnaire; gates Plan 06.1-07 (badge in READMEs).
- **CP-Post-08 backlog issues (Yves)** — open 2 issues: CII Silver, ossf/scorecard#5103 tracking.
- **Local main divergence** — local `main` carries 2 stale Phase-3 context commits (`9fb4b1c`, `b359a2e`) that never made it through a PR. Yves denied `git reset --hard origin/main` on 2026-06-21. Reconciliation pending Yves' decision.
- **Plan 04-01 Q3 sandbox probe (Yves API-key)** — live `https://finance.izettle.com/v2/accounts/liquid/transactions` call to flip ADR-0003 Q3 from DEFERRED → ACCEPTED. Non-blocking for v1.0.0.
- **Plan 05-01 Q9 MM.sleep probe (optional)** — verify `MM.sleep` actually exists at the MoneyMoney runtime; defensive pcall already in place either way.
- **v0.2.x deferred Tier-3 findings** — Phase-5 INFO items (WR-04 / IN-01..04 / S-07), Phase-6 R2 backlog (S-R2-L-01 + S-R2-M-01), 11 Phase-6 LOW/INFO from REVIEW.md not addressed in fix-batch.

---

## Performance Metrics

| Phase | Plans | Tests at end | Disposition |
|-------|-------|--------------|-------------|
| 1 | 1 | n/a | merged |
| 2 | (sub-plans) | n/a | PR #6 + #7 |
| 3 | (sub-plans) | n/a | PR #8 + #10 |
| 4 | 6 + post-review | 335 | PR #11 |
| 5 | 6 (incl. post-review) | 373 | PR #13 |
| 6 | 3 + R1 fix-batch + CP-1 cleanup | 388 | PR #14 |
| 6.1 | 8 (07 deferred to CP-6.1-D) | 388 (no src/ changes) | pending PR |

---

## Decisions of record (Phases 6 + 6.1)

The 37 canonical decisions are pinned in `.planning/research/SUMMARY.md §2`. Phase-6-specific decisions D-70..D-82 live in `.planning/phases/06-release-polish/06-CONTEXT.md`. Phase-6.1 decisions D-33..D-40 live in `.planning/phases/06.1-supply-chain-scorecard-hardening/06.1-CONTEXT.md`. Highlights:

- **D-70** README split: German-primary `README.de.md` + English pointer `README.md`.
- **D-71** GoBD-Hinweis text: read-only export; GoBD-Konformität bleibt Verantwortung der Buchhaltung.
- **D-72** GPG-verified-tag release pipeline.
- **D-74** Branch protection mandatory.
- **D-76** Gitleaks secret-scan job.
- **D-78** Commit-message lint.
- **D-79** Raw `print()` CI gate.
- **D-81** CHANGELOG cuts in Keep-a-Changelog 1.1.0 format.
- **D-33/34** Semgrep ruleset locked to `p/security-audit` + `p/secrets`; reject `p/lua-community` + `p/ci`.
- **D-35** Branch-Protection Tier 1 (Option A) accepted; CII passing-tier target.
- **D-36** New requirement IDs SEC-06/07/08 + BUILD-07 + DOC-11.
- **D-37** MkDocs Material as docs-site engine; bilingual; GitHub Pages deploy.
- **D-38** SBOM + cosign + SLSA Provenance Level 3 deferred to v1.1.x.
- **D-39** ADR file number 0009 (not 0004 as originally drafted).
- **D-40** CII badge in BOTH `README.md` and `README.de.md`.
- **MADR retro-documentation** ACCEPTED 2026-06-22 — ADRs 0002/0006/0007/0008 backfilled.
- **ADR-0009** ACCEPTED 2026-06-23 — OpenSSF Scorecard stance, accepted gaps + alternatives + revised aggregate target.

---

## Session Continuity

**Last action:** Phase 6.1 Plan 06.1-08 executed on `phase-6.1/scorecard-hardening`. ADR-0009 created (266 lines, MADR format), SECURITY.md bilingual supply-chain section appended (DE + EN), REQUIREMENTS.md SEC-05 expanded + SEC-06/SEC-07/SEC-08/BUILD-07/DOC-11 appended + traceability table updated to 75/75, ROADMAP.md Phase 6.1 success criteria revised (aggregate ≥7.5, BP ≥3, SAST deferred, ADR-0009, both READMEs, MkDocs criterion) + Phase 6.1 marked `[x]` + progress table appended, mkdocs.yml ADR-0009 nav uncommented (+ EN nav_translation). META-03 walker passes 3/0/0/0. Reproducible-build SHA on `dist/paypal-pos.lua` unchanged (no src/ edits).

**Next action:** Open PR for `phase-6.1/scorecard-hardening` → `main`. After merge, Yves runs CP-6.1-A (SCORECARD_READ_TOKEN secret) + CP-6.1-B (re-run setup-branch-protection.sh) + CP-6.1-C (enable Pages = GitHub Actions) + CP-Post-08 (open 2 backlog issues). Plan 06.1-07 (CII badge) remains deferred until CP-6.1-D questionnaire is complete.

**v1.0.0 tag publication path (Yves):**

```bash
# 1) Set the MAINTAINER_GPG_PUBKEY CI secret (one-time)
gpg --armor --export FDE07046A6178E89ADB57FD3DE300C53D8E18642 \
  | gh secret set MAINTAINER_GPG_PUBKEY \
      --repo yves-vogl/moneymoney-paypal-pos-extension

# 2) After CP-5 screenshots shipped:
git switch main && git pull --ff-only
git tag -s v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# release.yml pipeline does the rest: verify signature → reproducible build →
# publish dist/paypal-pos.lua + dist/paypal-pos.lua.sha256 as GitHub Release assets.
```

---

*State initialized 2026-06-16 via `/gsd-roadmap`. Updated on every phase transition. Last reconciled 2026-06-23 after Plan 06.1-08 closure.*
