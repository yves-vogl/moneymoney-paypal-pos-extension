---
gsd_state_version: 1.0
milestone: v1.0.1
milestone_name: shipped — post-release maintenance
status: v1.0.1-shipped-maintenance
last_updated: "2026-07-11T10:00:00.000Z"
progress:
  total_phases: 8
  completed_phases: 8
  total_plans: 39
  completed_plans: 39
  percent: 100
---

# Project State: MoneyMoney PayPal POS Extension

**Initialized:** 2026-06-16
**Last updated:** 2026-07-11 (post-release maintenance session: Dependabot batch cleared, stray branches reconciled, CP-Post-08 closed)

---

## Project Reference

**Core Value:**
> A German PayPal POS merchant pastes their API key into MoneyMoney once and from then on sees every card transaction, refund, fee, and payout automatically in MoneyMoney — accurately, on schedule, with VAT and tip transparency suitable for bookkeeping.

**Current Focus:** Post-release maintenance. v1.0.0 and v1.0.1 are published GitHub Releases; the milestone is SHIPPED. Remaining work is Yves-gated hardening checkpoints (see below) and v1.1.x backlog.

---

## Release State

| Release | Date | Content |
|---------|------|---------|
| v1.0.0 | 2026-06-24 | Phases 1–6.1 (full extension + supply-chain hardening); rc.1–rc.3 pre-releases |
| v1.0.1 | 2026-06-24 | rc.3 cleanup-batch (PR #26: SHA bumps, 25 deferred findings, docs site as customer guide, README dispatcher) + **Phase 7 update-check** (PR #37, D-83) |

Phase 7 (optional GitHub-Release update-check, D-83) was executed outside the original 7-phase roadmap as an ad-hoc feature phase and is contained in the v1.0.1 tag (merged 2026-06-24T13:07, tagged 13:10).

```
Phase 1: Foundations & Sandbox Probes          [DONE — merged]
Phase 2: Authenticated Network Layer           [DONE — PR #6 + #7]
Phase 3: Sale Spine                            [DONE — PR #8 + #10]
Phase 4: Enrichment                            [DONE — PR #11]
Phase 5: Resilience & Error Handling           [DONE — PR #13]
Phase 6: Release & Polish                      [DONE — PR #14]
Phase 6.1: OpenSSF Scorecard Hardening         [DONE — merged; released in v1.0.0]
Phase 7: GitHub-Release Update-Check (D-83)    [DONE — PR #37; released in v1.0.1]
```

---

## Yves Checkpoints — consolidated status (verified live 2026-07-11)

| ID | Item | Owner | Status |
|----|------|-------|--------|
| CP-1 | Lektor pass README/CHANGELOG/ADRs | agent | **DONE 2026-06-23** (PR #14) |
| CP-2 | Branch protection setup | orchestrator | **DONE 2026-06-23** — 3 required checks active (CI, gitleaks, commit-lint); lift to 5 pending CP-6.1-B |
| CP-3 | Repo metadata | orchestrator | **DONE 2026-06-23** |
| CP-4 | v1.0.0 tag publication + `MAINTAINER_GPG_PUBKEY` secret | Yves | **DONE 2026-06-24** — secret set 10:48 UTC, v1.0.0 released 12:53 UTC |
| CP-5 | Real screenshots for `docs/img/*.png` | **Yves** | **OPEN** — both files are still 68-byte placeholders |
| CP-6.1-A | `SCORECARD_READ_TOKEN` repo secret (fine-grained PAT, `Administration:read`, ≤1y) | **Yves** | **OPEN** — secret not present; Branch-Protection scorecard check reads −1 until set |
| CP-6.1-B | Re-run `tools/setup-branch-protection.sh` → 5 required checks (adds Scorecard + Semgrep) | **Yves** | **OPEN** — run only after CP-6.1-A, else PRs block on a never-reporting check |
| CP-6.1-C | Enable GitHub Pages (source = GitHub Actions) | Yves | **DONE** — site live at https://yves-vogl.github.io/moneymoney-paypal-pos-extension/ |
| CP-6.1-D | CII Best Practices questionnaire (Passing tier) | **Yves** | **OPEN** — off-repo; gates Plan 06.1-07 (badge in both READMEs) |
| CP-Post-08 | Open 2 backlog issues | orchestrator | **DONE 2026-07-11** — #42 (CII Silver), #43 (ossf/scorecard#5103 tracking) |

---

## Maintenance session 2026-07-11

- **Dependabot backlog cleared (10 PRs):**
  - Merged #27 (codeql-action SHA), #28 (action-gh-release v3.0.1 — same inputs, exercised at next tag), #29 + #30 (deploy-pages v5 + upload-pages-artifact v5 pair), #31 (gitleaks-action v3.0.0 — green as required check on its own PR).
  - Closed #33/#34/#35/#36/#39 as superseded by **PR #40**: single `pip-compile --generate-hashes` regeneration of both lockfiles (Python 3.12 = CI), bumping `mkdocs-material` → 9.7.6 and `semgrep` → 1.169.0 and adding the `backrefs` transitive dep whose absence broke Dependabot's group bump. Verified locally with CI-identical commands (`mkdocs build --strict` clean).
- **Stray-branch reconciliation:** audited every local/remote branch tree-vs-tree against `main`. All phase/fix/worktree branches confirmed fully landed (spot checks: log-redaction S-03/S-04, 599 sentinel, SEC-07 ci.yml permissions, phase-3 context docs). Only genuinely unlanded work: `CLAUDE.md` removal (decision 2026-06-19) → landed via **PR #41**. Local `main` (2 redundant docs commits) reset onto `origin/main`; stale remote branches deleted.
- **Scorecard:** aggregate **6.3** (2026-07-11); weekly + push runs green. Remaining gaps map 1:1 to ADR-0009 accepted gaps + open CPs: Branch-Protection −1 (CP-6.1-A/B), CII 0 (CP-6.1-D), Signed-Releases 0 (D-38: cosign/SLSA deferred to v1.1.x), Maintained 0 (heals ~2026-09), SAST 4 (issue #43), Code-Review/Fuzzing/Contributors structural (solo maintainer).

---

## Active Todos

- **CP-5 screenshots (Yves)** — replace the two 68-byte placeholders in `docs/img/`.
- **CP-6.1-A → CP-6.1-B (Yves, in this order)** — PAT secret, then re-run `tools/setup-branch-protection.sh`.
- **CP-6.1-D CII questionnaire (Yves)** — then execute deferred Plan 06.1-07 (badge in both READMEs).
- **Plan 04-01 Q3 sandbox probe (Yves API key)** — live Finance-API call to flip ADR-0003 Q3 DEFERRED → ACCEPTED. Non-blocking.
- **Plan 05-01 Q9 `MM.sleep` probe (optional)** — defensive pcall already in place.
- **v1.1.x backlog** — SBOM + cosign + SLSA provenance (D-38), CII Silver (#42), SAST score flip (#43).

---

## Session Continuity

**Last action (2026-07-11):** Maintenance batch — Dependabot queue emptied (5 merged, 5 superseded by #40), CLAUDE.md removal landed (#41), branch landscape reconciled, issues #42/#43 opened, STATE.md reconciled to live GitHub state.

**Next action:** Yves executes CP-5, CP-6.1-A/B, CP-6.1-D. No agent-side work pending.

---

*State initialized 2026-06-16 via `/gsd-roadmap`. Updated on every phase transition. Last reconciled 2026-07-11 against live GitHub state (releases, secrets, protection, scorecard, issues).*
