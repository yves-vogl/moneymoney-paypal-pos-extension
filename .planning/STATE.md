---
gsd_state_version: 1.0
milestone: v1.0.0
milestone_name: has stabilized in production for several weeks.
status: v1.0.0-shipped-pending-tag
last_updated: "2026-06-23T01:40:00.000Z"
progress:
  total_phases: 7
  completed_phases: 6
  total_plans: 31
  completed_plans: 31
  percent: 100
---

# Project State: MoneyMoney PayPal POS Extension

**Initialized:** 2026-06-16
**Last updated:** 2026-06-23 (Phase 6 merged to main via PR #14; v1.0.0 awaiting CP-4 + CP-5)

---

## Project Reference

**Core Value:**
> A German PayPal POS merchant pastes their API key into MoneyMoney once and from then on sees every card transaction, refund, fee, and payout automatically in MoneyMoney — accurately, on schedule, with VAT and tip transparency suitable for bookkeeping.

**Current Focus:** Phase 06 SHIPPED to `main` via PR #14 (`d1e1003`); v1.0.0 tag publication gated on Yves CP-4 + CP-5. Phase 6.1 (OpenSSF Scorecard hardening) unblocked.

**Granularity:** standard (7 phases)
**Mode:** mvp / yolo

---

## Current Position

Phase: 06 (release-polish) — **MERGED 2026-06-23** via PR #14 (squash; `d1e1003`).
Next: Phase 6.1 (OpenSSF Scorecard hardening 5.2 → 8.5+).

### Yves Checkpoints (CP-1..CP-5) — post-Phase-6 status

| ID | Item | Owner | Status |
|----|------|-------|--------|
| CP-1 | loop-lektor pass on README.de.md + CHANGELOG [1.0.0] + 4 new ADRs + CONTRIBUTING | autonomous (lektor agent) | **DONE 2026-06-23** — 36 findings (5 HIGH); cleanup batch landed in 4 commits (33986b0/0a929c8/193e9ca/e17001b); merged via PR #14 |
| CP-2 | Branch protection: `bash tools/setup-branch-protection.sh` | orchestrator | **DONE 2026-06-23** — verified via `gh api …/branches/main/protection`: enforce_admins=true, 3 required checks, linear_history=true, allow_force_pushes=false, allow_deletions=false, required_signatures=true |
| CP-3 | Repo metadata: `bash tools/setup-repo-metadata.sh` | orchestrator | **DONE 2026-06-23** — description + 7 topics (`moneymoney`, `moneymoney-extension`, `paypal-pos`, `zettle`, `lua`, `germany`, `accounting`) |
| CP-4 | v1.0.0 tag publication: `git tag -s v1.0.0 -m "Release v1.0.0"` → `git push origin v1.0.0` | **Yves** | **pending** — gated on CP-5 and on setting `MAINTAINER_GPG_PUBKEY` repo secret (`gpg --armor --export FDE07046A6178E89ADB57FD3DE300C53D8E18642 \| gh secret set MAINTAINER_GPG_PUBKEY`) |
| CP-5 | Capture real screenshots for `docs/img/inoffizielle-extensions-erlauben.png` + `docs/img/help-menu-extensions-folder.png`; commit with `docs(img): capture <filename>` | **Yves** ("die Tage") | **pending — reminder for orchestrator to surface at session start** |

CP-4 prerequisites all satisfied except the GPG-pubkey CI secret. After CP-5 ships the screenshots, Yves can sign+push the v1.0.0 tag and the release.yml pipeline does the rest.

---

### Phase 06 ship summary

PR #14 merged 2026-06-23T01:38:21Z as `d1e1003d`. Composition: 14 implementation commits (06-01/02/03) + 1 CI-fix (1468018) + 10 fix-batch commits (e1b0736..b68d57a addressing 1 verifier BLOCKER + 1 CRITICAL + 6 HIGH from R1 reviewer/security) + 4 lektor cleanup commits (33986b0..e17001b).

Final test status at merge: 388 successes / 0 failures / 0 errors / 0 pending. Reproducible build SHA: dev `18bb7a6ae43d8b9c60951f13afe7476b19c2854256a07e42cfeca9e73d58e0c1`. v1.0.0-tagged SHA differs because `__VERSION__` substitutes to `1.0` instead of `<DEV BUILD>`.

R2 reviewer + security verdict: **SHIP** (0 NEW HIGH/CRITICAL; minor watch-items deferred to backlog: S-R2-L-01 branch-protection post-condition + S-R2-M-01 JWT-`/`-char redaction monitoring).

### Branch state on `main`

```
d1e1003 Phase 6: Release & Polish — Reproducible Build, CI/CD, German Docs (#14)
9bc6c8f Phase 5: Resilience & Error Handling (#13)
74f644c Phase 4: Enrichment — Refunds, Fees, Payouts, Balance, VAT, Tips (#11)
a201f6c docs(03): Phase 3 verifier report — READY-TO-MERGE closure (#10)
a11287d Phase 3: Sale Spine (first user-visible slice) (#8)
```

```
Phase 1: Foundations & Sandbox Probes          [DONE ✅ — merged]
Phase 2: Authenticated Network Layer           [DONE ✅ — PR #6 + #7]
Phase 3: Sale Spine                            [DONE ✅ — PR #8 + #10]
Phase 4: Enrichment                            [DONE ✅ — PR #11]
Phase 5: Resilience & Error Handling           [DONE ✅ — PR #13]
Phase 6: Release & Polish                      [DONE ✅ — PR #14]
Phase 6.1: OpenSSF Scorecard Hardening         [UNBLOCKED — next]
```

---

## Active Todos (carry-over watch-items)

- **CP-4 v1.0.0 tag (Yves)** — after CP-5; sets the `MAINTAINER_GPG_PUBKEY` repo secret, then signs the tag and pushes. Triggers release.yml automatically.
- **CP-5 docs/img screenshots (Yves, "die Tage")** — Inoffizielle-Extensions + Help-Menu-Extensions screenshots. Currently 68-byte placeholders. Orchestrator should remind Yves at session start until done.
- **Local main divergence** — local `main` carries 2 stale Phase-3 context commits (`9fb4b1c`, `b359a2e`) that never made it through a PR. Yves denied `git reset --hard origin/main` on 2026-06-21. Reconciliation pending Yves' decision (recommend: cherry-pick onto fresh branch + PR, OR accept the reset once Yves confirms nothing local-only is at risk).
- **Plan 04-01 Q3 sandbox probe (Yves API-key)** — live `https://finance.izettle.com/v2/accounts/liquid/transactions` call to flip ADR-0003 Q3 from DEFERRED → ACCEPTED. Non-blocking for v1.0.0; documented in ADR-0004 as known operational item.
- **Plan 05-01 Q9 MM.sleep probe (optional)** — verify `MM.sleep` actually exists at the MoneyMoney runtime; defensive pcall already in place either way.
- **v0.2.x deferred Tier-3 findings** — Phase-5 INFO items (WR-04 / IN-01..04 / S-07), Phase-6 R2 backlog (S-R2-L-01 + S-R2-M-01), 11 Phase-6 LOW/INFO from REVIEW.md not addressed in fix-batch. Cluster into a v1.0.x or v1.1.0 cleanup batch.

---

## Phase 6.1 — Next Up

OpenSSF Scorecard hardening (5.2 → 8.5+). Inserted as Phase 6.1 on 2026-06-17 (URGENT) — see `.planning/research/openssf-scorecard-sprint-proposal.md`.

Likely scope (to be confirmed in discuss-phase): SHA-pin all third-party GitHub Actions (G-05 from Phase-6 R1 security), enable Dependabot for `github-actions`, add `persist-credentials: false` to checkout invocations (G-06), add `.gitleaks.toml` explicit config (G-14), add SBOM + provenance attestation (G-16), add `setup-branch-protection.sh` post-condition hardening (S-R2-L-01), tighten egress allowlist (G-01), expand log redactor `/` handling (G-03 residual / S-R2-M-01).

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
| 6.1 | — | — | not yet started |

---

## Decisions of record (Phase 6)

The 37 canonical decisions are pinned in `.planning/research/SUMMARY.md §2`. Phase-6-specific decisions D-70..D-82 live in `.planning/phases/06-release-polish/06-CONTEXT.md`. Highlights:

- **D-70** README split: German-primary `README.de.md` + English pointer `README.md`.
- **D-71** GoBD-Hinweis text: read-only export; GoBD-Konformität bleibt Verantwortung der Buchhaltung.
- **D-72** GPG-verified-tag release pipeline: `verify-signed-tag` → `build-test-coverage-repro` → `publish` (3 jobs, `softprops/action-gh-release@v2`).
- **D-74** Branch protection mandatory.
- **D-76** Gitleaks secret-scan job.
- **D-78** Commit-message lint.
- **D-79** Raw `print()` CI gate (all log output routes through `M_log.*` redactor).
- **D-81** CHANGELOG cuts in Keep-a-Changelog 1.1.0 format.
- **MADR retro-documentation** ACCEPTED 2026-06-22 — ADRs 0002/0006/0007/0008 backfilled Phase-2..5 decisions.

---

## Session Continuity

**Last action:** Phase 6 merged to main via PR #14 squash-merge 2026-06-23. CP-1 (lektor) + CP-2 (branch protection) + CP-3 (repo metadata) all complete. R1 + R2 reviewer rounds dry. Local main not yet synced (carries 2 stale Phase-3 context commits — Yves decision pending).

**Next action:** Phase 6.1 OpenSSF Scorecard hardening — `/gsd-discuss-phase 6.1` → research+patterns → planner → execute → ship.

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

*State initialized 2026-06-16 via `/gsd-roadmap`. Updated on every phase transition.*
