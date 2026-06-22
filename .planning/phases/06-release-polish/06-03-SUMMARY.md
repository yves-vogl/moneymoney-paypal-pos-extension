---
phase: 06-release-polish
plan: 03
subsystem: changelog + state-transition + handoff-runbook
tags: [wave-3, changelog, state, handoff, v1-0-0-ready-for-tag, mvp]
requires:
  - 06-01 (BUILD-03 __VERSION__ substitution + META-03 doc walker; reproducible dev-build SHA 4526a33f...)
  - 06-02 (release.yml + setup scripts + README.de.md + CONTRIBUTING.md + 4 ADRs)
provides:
  - CHANGELOG.md [1.0.0] section in Keep-a-Changelog 1.1.0 format (DOC-10 / D-81)
  - .planning/STATE.md v1.0.0-ready-for-tag transition + CP-1..CP-5 dispositions table
  - .planning/phases/06-release-polish/06-HANDOFF.md consolidated post-merge / pre-tag runbook for Yves
affects:
  - CHANGELOG.md (+69 lines: [1.0.0] section between [Unreleased] and [0.2.0]; footnote links updated)
  - .planning/STATE.md (frontmatter + Current Position rewritten; Phase 5 demoted to Previous Phase; CP-1..CP-5 table inserted)
  - .planning/phases/06-release-polish/06-HANDOFF.md (NEW, 254 lines)
tech-stack:
  added: []
  patterns:
    - Keep-a-Changelog 1.1.0 reverse-chronological insertion ([1.0.0] between [Unreleased] and [0.2.0])
    - Footnote-link triad pattern ([Unreleased] compare-against-latest + [VERSION] release-tag links)
    - HTML-comment lektor-review marker ("<!-- lektor-review: pending — CP-1 -->")
    - Phase-handoff runbook structure (state → per-CP section → verification matrix → troubleshooting → forward-pointer)
    - Verification matrix mapping requirement IDs to verification commands + post-CP status
    - META-03 spec invocation as authoritative D-55 gate (no inline literal pattern listing in runbook to avoid self-flag)
key-files:
  created:
    - .planning/phases/06-release-polish/06-HANDOFF.md
  modified:
    - CHANGELOG.md
    - .planning/STATE.md
decisions:
  - "CHANGELOG.md [1.0.0] entry uses safe German phrases (Token-Revocation / Erstabgleich / Egress-Allowlist) — never invokes the 13 D-55 forbidden literals, so the extended META-03 walker stays GREEN without exemptions"
  - "Date placeholder 2026-MM-DD stays in the [1.0.0] section; Yves finalizes it at CP-4 prereq via a separate `docs(changelog): finalize v1.0.0 release date YYYY-MM-DD` commit on main — this is the commit that gets tagged"
  - "06-HANDOFF.md references the META-03 spec invocation instead of inlining the 13-phrase grep literally — inlining would self-flag during META-03 walks if .planning/ ever joins DOC_TARGETS in a future hardening sprint"
  - "STATE.md frontmatter status field advances from `implementation-complete` to `v1.0.0-ready-for-tag` — single-string contract for gsd-tools + human consumers"
  - "CP-1 (lektor) is the only checkpoint that gates CP-4 (v1.0.0 tag); CP-2 / CP-3 / CP-5 are independent and can fire in any order post-merge"
metrics:
  duration: "~6 minutes"
  completed: "2026-06-22"
  tasks_completed: 3
  commits: 3
  files_created: 1
  files_modified: 2
  busted_baseline: "381/0/0/0 (from 06-02)"
  busted_after: "381/0/0/0 (no spec changes; meta_no_tax_classification_spec still GREEN 3/0/0/0 — extended walker scans the new [1.0.0] CHANGELOG section)"
  luacheck: "clean on CI (Lua 5.4); local Lua 5.5 has the luacheck.standards regression noted in Phase-5 line 65 — not a 06-03 regression"
  reproducible_sha_dev_build: "4526a33fceab55122a6e624207c03cf76545939685825c3072c9d9001653304c"
  reproducible_sha_status: "UNCHANGED from 06-01 / 06-02 baseline (this plan modifies only CHANGELOG.md + .planning/ documents; nothing in dist/paypal-pos.lua manifest)"
---

# Phase 6 Plan 03: Wave-3 release cut Summary

CHANGELOG.md [1.0.0] section landed in Keep-a-Changelog 1.1.0 format with First-stable-release banner, full Hinzugefügt feature inventory, Bekannte Grenzen carry-over, and Sicherheit re-assertion. STATE.md transitions to `v1.0.0-ready-for-tag` with the CP-1..CP-5 dispositions table inserted and Phase 5 demoted to Previous Phase. 06-HANDOFF.md (NEW, 254 lines) is the consolidated post-merge / pre-tag runbook for Yves. Three GPG-signed commits; reproducible-build SHA `4526a33f...` unchanged.

## What landed

### CHANGELOG.md [1.0.0] section (DOC-10 / D-81)

Inserted between `## [Unreleased]` and `## [0.2.0]` per Keep-a-Changelog 1.1.0 reverse-chronological convention. Body structure:

- **Lektor-review marker:** `<!-- lektor-review: pending — CP-1; CHANGELOG.md v1.0.0 wording is engineering-grade; Yves or loop-lektor finalises before tag publication. -->`
- **First stable release** banner (bold) per D-81.
- **10 Hinzugefügt bullets** enumerating the Phase-6 surface:
  1. Reproduzierbare Release-Pipeline (release.yml — GPG-verified, deterministic build, .lua + .sha256 attachments)
  2. `__VERSION__` substitution from $GITHUB_REF_NAME (BUILD-03)
  3. Zweisprachige Dokumentation (README.de.md German-primary + README.md English pointer)
  4. CONTRIBUTING.md (dev loop + release process + GPG-signed-tag requirement)
  5. Vier neue MADR-ADRs (0002 / 0006 / 0007 / 0008 backfilling Phases 2..5)
  6. Secret-Scanning via gitleaks
  7. Conventional-Commits-Lint
  8. Branch protection on `main` (PR + signatures + checks + linear history)
  9. Repository metadata (D-82 description + 7 topics)
  10. META-03 walker extension to README/CHANGELOG/CONTRIBUTING/ADRs
- **Bekannte Grenzen (unverändert seit v0.2.0)** — 5 bullets carrying forward documented limitations: ADR-0004 payout delay, fee aggregation fallback, 90-Tage-Erstabgleich, non-EUR skip, ERR-04 token-revoked.
- **Sicherheit** — 3 bullets re-asserting: zero telemetry + 3-host egress allowlist (oauth.zettle.com / purchase.izettle.com / finance.izettle.com); API-keys via MoneyMoney credentials API only (never LocalStorage / never logs / never errors); GPG-signed tags with maintainer fingerprint `FDE07046A6178E89ADB57FD3DE300C53D8E18642`.

**Footnote links** (Keep-a-Changelog 1.1.0 convention):

```
[Unreleased]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases/tag/v1.0.0
[0.2.0]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases/tag/v0.2.0
```

`[Unreleased]` now compares against `v1.0.0...HEAD` (was `v0.2.0...HEAD`); `[1.0.0]` is new; `[0.2.0]` preserved byte-identically.

**Date placeholder:** `## [1.0.0] - 2026-MM-DD` stays — Yves replaces with the actual tag-publication date at CP-4 prereq via `docs(changelog): finalize v1.0.0 release date YYYY-MM-DD` commit on main (the commit that gets tagged).

**META-03 audit:** Full-file 13-phrase grep on CHANGELOG.md returns ZERO matches. The extended walker (`spec/meta_no_tax_classification_spec.lua`) scans the updated content and passes 3/0/0/0 (covers README.md, README.de.md, CONTRIBUTING.md, CHANGELOG.md, and 8 ADRs).

**Awk fallback sanity:** `awk '/^## \[1\.0\.0\]/{flag=1;next} /^## \[/{flag=0} flag' CHANGELOG.md` produces a non-empty multi-line output starting with the lektor-review HTML comment and the First-stable-release banner — `release.yml` job 2's CHANGELOG-fallback extraction works as designed.

### .planning/STATE.md transition

- **Frontmatter:** `status` flipped from the long verbose Phase-5 narrative string to the single-string contract `v1.0.0-ready-for-tag`. `completed_phases: 3 → 6`; `completed_plans: 30 → 31`; `percent: 43 → 100`; `last_updated` refreshed to 2026-06-22T12:25:00.000Z.
- **Current Focus** line updated: Phase 06 release-polish IMPLEMENTATION COMPLETE; v1.0.0-READY-FOR-TAG.
- **Current Position block** rewritten as a Phase-6 narrative — status sentence + per-plan commit enumeration + suite metrics + reproducible-build SHA + CI check names + Phase-6 requirement-ID closure list + recommended next steps.
- **Yves Checkpoints (CP-1..CP-5) table** inserted with ID + Item + Trigger + Owner + Status columns + the dependency-chain note (CP-1 gates CP-4; CP-2/CP-3/CP-5 are independent).
- **Phase 5 demoted to Previous Phase: 05** — body preserved byte-identically.
- **Phase 4 + Performance Metrics + Decisions + Active Todos + Roadmap Evolution + Blockers + Phase-1 Probe Status + Session Continuity** all preserved byte-identically.

### .planning/phases/06-release-polish/06-HANDOFF.md (NEW)

254 lines, structured as:

1. **State at hand-off** — branch / merge method / reproducible-build SHA / requirement-IDs-delivered / maintainer fingerprint.
2. **CP-1** loop-lektor pass — targets + Option A (Yves) + Option B (subagent) + hard-fail discipline + verification (META-03 walker invocation).
3. **CP-2** branch protection — prerequisite (PAT) + command + success/graceful-degradation paths + verification via `gh api`.
4. **CP-3** repo metadata — prerequisite + command + verification via `gh repo view`.
5. **CP-5** screenshots — capture procedure + commit recipe + `file` verification.
6. **CP-4 prerequisites** — MAINTAINER_GPG_PUBKEY one-liner + CHANGELOG date fix recipe.
7. **CP-4 cut-v1.0.0 sequence** — 7-step ordered list: prereq verify → optional v1.0.0-rc.1 dry-run → tag-sign + push → `gh run watch` → release-page verify → curl + shasum verify → BUILD-03 sanity grep.
8. **Verification matrix** — table mapping every Phase-6 requirement ID (BUILD-03..06, CI-01..06, SEC-02, SEC-05, DOC-01..10) to a verification command + post-CP-4 status.
9. **If anything fails** — 5 failure modes covering Pitfalls 1/2/4/7 + gitleaks fixture flag.
10. **Phase 6.1 unblocked** — OpenSSF Scorecard hardening forward pointer.
11. **Cross-reference** — runbook is authoritative for v1.0.0; CONTRIBUTING.md is authoritative for v1.0.1+.

The META-03 13-phrase pattern is referenced via the spec invocation — not inlined literally — so the runbook stays clean even if a future hardening sprint extends DOC_TARGETS to include `.planning/`.

## Reproducible build SHA — unchanged from 06-01 / 06-02

| Build context | SHA256 |
|---|---|
| Phase 6 dev build (no `GITHUB_REF_NAME`) — 06-01 baseline | `4526a33fceab55122a6e624207c03cf76545939685825c3072c9d9001653304c` |
| Phase 6 dev build — after 06-02 | `4526a33fceab55122a6e624207c03cf76545939685825c3072c9d9001653304c` |
| Phase 6 dev build — after 06-03 | `4526a33fceab55122a6e624207c03cf76545939685825c3072c9d9001653304c` |

Identical to 06-02 because Wave-3 modifies **only** CHANGELOG.md + .planning/ documents — nothing in the `dist/paypal-pos.lua` manifest (`src/*.lua` + `tools/build.lua` + `tools/manifest.txt`) is touched.

## CI / test gates

| Gate | Result |
|---|---|
| `busted spec/` | 381 / 0 / 0 / 0 (unchanged from 06-02) |
| `busted spec/meta_no_tax_classification_spec.lua` | 3 / 0 / 0 / 0 — scans the new CHANGELOG [1.0.0] section + all prior DOC_TARGETS |
| META-03 13-phrase grep on CHANGELOG.md | 0 matches |
| META-03 13-phrase grep on 06-HANDOFF.md | 0 matches |
| `lua tools/build.lua --verify` (twice) | `OK: reproducible (sha256: 4526a33f...)` — byte-identical |
| Awk fallback: `awk '/^## \[1\.0\.0\]/{flag=1;next} /^## \[/{flag=0} flag' CHANGELOG.md` | non-empty multi-line output (release.yml job 2 fallback works) |
| luacheck (local Lua 5.5) | luacheck.standards module regression (Phase-5 standing condition); CI Lua 5.4 path passes per leafo/gh-actions-lua@v13 pinning |

## Commits

1. `ef66f57` — `docs(06-03): cut CHANGELOG [1.0.0] section in Keep-a-Changelog format (DOC-10 / D-81)`
2. `796b223` — `docs(state): Phase 6 implementation complete — v1.0.0-ready-for-tag (06-01/02/03 landed)`
3. `c2839ed` — `docs(06-03): add 06-HANDOFF.md — post-merge / pre-tag runbook for Yves`

All 3 GPG-signed by `FDE07046A6178E89ADB57FD3DE300C53D8E18642` (verified via `git log --show-signature -3`); no AI authorship attribution; Conventional Commits with `(06-03)` and `(state)` scopes.

## Phase-6 audit — all 22 requirement IDs delivered

| Req ID | Delivering plan | Artifact |
|---|---|---|
| BUILD-03 | 06-01 Task 2 | `tools/build.lua` `__VERSION__` substitution from `$GITHUB_REF_NAME` |
| BUILD-04 | 06-02 Task 1 | `.github/workflows/release.yml` job 1 (VALIDSIG fingerprint grep) |
| BUILD-05 | 06-02 Task 1 | `release.yml` job 2 computes `paypal-pos.lua.sha256`; job 3 publishes both |
| BUILD-06 | 06-02 Task 1 | `release.yml` job 2 extracts tag annotation as `dist/release-notes.md` with CHANGELOG fallback |
| CI-01..04 | existing `ci.yml` (Phase 1 + 2) | luacheck + busted + 85% coverage + reproducible build |
| CI-05 | 06-01 Task 4 | gitleaks `.github/workflows/ci.yml` job |
| CI-06 | 06-01 Task 4 | `.github/workflows/commit-lint.yml` |
| SEC-02 | existing `ci.yml` + 06-01 D-79 hardening | egress-allowlist gate + raw print() grep |
| SEC-05 | 06-02 Task 2 | `tools/setup-branch-protection.sh` (CP-2 fires post-merge) |
| DOC-01..04 | 06-02 Task 3 | `README.de.md` 212 lines (Inoffizielle-Extensions guide + GoBD-Hinweis + bilingual) |
| DOC-05 | 06-02 Task 4 | `CONTRIBUTING.md` 283 lines (dev loop + release process + GPG-signed-tag) |
| DOC-06 | 06-02 Task 4 | 4 backfilled ADRs (0002 / 0006 / 0007 / 0008) joining 4 existing = 8 total |
| DOC-07 | pre-existing | `LICENSE` MIT + Copyright (c) 2026 Yves Vogl (verified NO-OP) |
| DOC-08..09 | 06-02 Task 2 | `tools/setup-repo-metadata.sh` (CP-3 fires post-merge) |
| DOC-10 | **06-03 Task 1** | **`CHANGELOG.md` [1.0.0] section in Keep-a-Changelog format** |

Every ID has a delivering artifact. CP-2 (SEC-05) + CP-3 (DOC-08/09) + CP-4 (BUILD-03..06 published-artifact verification) are post-merge Yves actions; the artifacts themselves all land in this PR.

## Yves checkpoints queued for post-merge — final disposition table

| ID | Item | Trigger | Status | Gate-of |
|---|---|---|---|---|
| CP-1 | loop-lektor pass (README.de.md + CHANGELOG [1.0.0] + 4 new ADRs) | manual or `loop-lektor` subagent | pending (pre-tag) | CP-4 |
| CP-2 | `bash tools/setup-branch-protection.sh` (Administration:write PAT) | post-merge | pending | independent |
| CP-3 | `bash tools/setup-repo-metadata.sh` (repo-metadata write PAT) | post-merge | pending | independent |
| CP-4 | v1.0.0 tag publication (CHANGELOG date fix → `git tag -s v1.0.0` → push) | after CP-1 + MAINTAINER_GPG_PUBKEY upload + CHANGELOG date fix | pending | release.yml fires |
| CP-5 | Real screenshot capture (replace 2 placeholder PNGs) | any time post-merge | pending | independent |

Yves prerequisite one-liner for CP-4 (CONTRIBUTING.md "First-time setup" + 06-HANDOFF.md repeated):

```bash
gpg --armor --export FDE07046A6178E89ADB57FD3DE300C53D8E18642 | \
  gh secret set MAINTAINER_GPG_PUBKEY --repo yves-vogl/moneymoney-paypal-pos-extension
```

## Deviations from Plan

None — plan executed exactly as written. Three tasks, three GPG-signed commits, all acceptance criteria satisfied.

### Minor adaptation (not a deviation)

The plan's verification snippet inside 06-HANDOFF.md's CP-1 section originally proposed inlining the 13-phrase grep pattern as a shell one-liner. Inlining the D-55 forbidden literals as a regex alternation would technically violate META-03 if `.planning/` ever joined `DOC_TARGETS` (currently it does not). To future-proof the runbook against an OpenSSF-Scorecard-hardening sprint that extends the walker's scope, the verification snippet now invokes `./.luarocks/bin/busted spec/meta_no_tax_classification_spec.lua` directly — the spec file itself is the canonical pattern source (CONTEXT D-55 locked-permanent), and a passing run confirms the walker scanned all DOC_TARGETS and found no matches. Substance preserved; future-proofing added.

## Self-Check: PASSED

- `[x] git log --show-signature -3` confirms all 3 commits GPG-signed (G) by `FDE07046A6178E89ADB57FD3DE300C53D8E18642` (`ef66f57`, `796b223`, `c2839ed`)
- `[x] grep '## \[1.0.0\]' CHANGELOG.md` — confirmed
- `[x] grep 'First stable release' CHANGELOG.md` — confirmed
- `[x] grep 'Reproduzierbare Release-Pipeline' CHANGELOG.md` — confirmed
- `[x] grep '__VERSION__' CHANGELOG.md` — confirmed
- `[x] grep 'README.de.md' CHANGELOG.md` — confirmed
- `[x] grep 'CONTRIBUTING.md' CHANGELOG.md` — confirmed
- `[x] grep 'ADR-0002\|ADR-0006\|ADR-0007\|ADR-0008' CHANGELOG.md` — confirmed
- `[x] grep 'gitleaks' CHANGELOG.md` — confirmed
- `[x] grep 'FDE07046A6178E89ADB57FD3DE300C53D8E18642' CHANGELOG.md` — confirmed (Sicherheit section)
- `[x] grep '[1.0.0]: https://github.com/yves-vogl/.../releases/tag/v1.0.0' CHANGELOG.md` — footnote present
- `[x] grep '[Unreleased]: ...compare/v1.0.0...HEAD' CHANGELOG.md` — footnote updated
- `[x] grep '[0.2.0]: ...releases/tag/v0.2.0' CHANGELOG.md` — preserved byte-identically
- `[x] META-03 13-phrase grep on full CHANGELOG.md returns empty`
- `[x] busted spec/meta_no_tax_classification_spec.lua` GREEN 3/0/0/0
- `[x] grep 'v1.0.0-ready-for-tag' .planning/STATE.md` — confirmed
- `[x] grep 'completed_phases: 6' .planning/STATE.md` — confirmed
- `[x] grep 'Phase: 06 (release-polish)' .planning/STATE.md` — confirmed
- `[x] grep 'Yves Checkpoints (CP-1..CP-5)' .planning/STATE.md` — table heading confirmed
- `[x] grep 'Previous Phase: 05' .planning/STATE.md` — Phase 5 demoted
- `[x] grep 'Previous Phase: 04' .planning/STATE.md` — Phase 4 preserved
- `[x] grep 'Accumulated Context' .planning/STATE.md` — preserved
- `[x] grep 'Session Continuity' .planning/STATE.md` — preserved
- `[x] test -f .planning/phases/06-release-polish/06-HANDOFF.md` — confirmed (254 lines, >= 60 required)
- `[x] All 12 acceptance-criterion grep tokens present in 06-HANDOFF.md` (CP-1..CP-5, MAINTAINER_GPG_PUBKEY, both setup scripts, `git tag -s v1.0.0`, `v1.0.0-rc.1`, Phase 6.1, maintainer fingerprint)
- `[x] META-03 13-phrase grep on 06-HANDOFF.md returns empty`
- `[x] busted spec/` 381/0/0/0 — unchanged from 06-02 baseline
- `[x] lua tools/build.lua --verify` produces `4526a33f...` — byte-identical to 06-02
- `[x] awk '/^## \[1\.0\.0\]/{flag=1;next} /^## \[/{flag=0} flag' CHANGELOG.md` produces non-empty multi-line output

| Commit | Status | Confirmed via |
|---|---|---|
| `ef66f57` | exists, GPG-signed, docs(06-03) | `git log --show-signature -1 ef66f57` → "Korrekte Signatur" + RSA `FDE0...8642` |
| `796b223` | exists, GPG-signed, docs(state) | same |
| `c2839ed` | exists, GPG-signed, docs(06-03) | same |

## Threat Flags

None. The threat surface introduced by this plan is fully covered by the plan's `<threat_model>` block (T-06-03-01..T-06-03-SC). No new source-code surface, no new auth paths, no new file-access patterns, no schema changes. Three new markdown / state documents; META-03 walker GREEN; reproducible-build SHA unchanged.

## Phase 6 PR — ready to open

Branch `phase-6/release-polish` (16+ commits ahead of `origin/main`) is ready to PR against `main`. Merge method: `gh pr merge --squash` (NEVER `--rebase`; see memory `feedback_gpg_signed_pr_merge`). After merge, Yves runs the 5 CPs per `06-HANDOFF.md`; `release.yml` fires when CP-4 pushes `v1.0.0`; the GitHub Release page publishes `paypal-pos.lua` + `paypal-pos.lua.sha256` with the maintainer-signed tag annotation as the body.

## Phase 6.1 unblocked

After v1.0.0 stabilises ~2 weeks, ROADMAP Phase 6.1 (OpenSSF Scorecard hardening) becomes the next planning candidate. Reference: `.planning/research/openssf-scorecard-sprint-proposal.md`. Baseline Scorecard ~5.2 → target 8.5+ via pinned action SHAs, SLSA-style provenance, permissions minimisation across remaining workflows.
