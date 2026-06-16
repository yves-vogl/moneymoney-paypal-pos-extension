# Project State: MoneyMoney PayPal POS Extension

**Initialized:** 2026-06-16
**Last updated:** 2026-06-16 (post-plan-phase-1)

---

## Project Reference

**Core Value:**
> A German PayPal POS merchant pastes their API key into MoneyMoney once and from then on sees every card transaction, refund, fee, and payout automatically in MoneyMoney — accurately, on schedule, with VAT and tip transparency suitable for bookkeeping.

**Current Focus:** Foundations & Sandbox Probes — settle MEDIUM-confidence assumptions about MoneyMoney's Lua sandbox via 8 live probes, stand up the build/test toolchain, and write the infra modules (`log.redact`, `i18n`, `errors`, `model`) that every later phase depends on.

**Granularity:** standard (6 phases)
**Mode:** mvp / yolo (per `config.json`)

---

## Current Position

**Phase:** 1 — Foundations & Sandbox Probes
**Plan:** `.planning/phases/01-foundations-sandbox-probes/PLAN.md` (13 tasks T01–T13)
**Status:** In Progress — T01-T11 implemented and CI-verified on feature branch `phase-1/foundations-sandbox-probes`; awaiting maintainer-driven T12 (probe install in MoneyMoney → fill ADR-0003) and T13 (walking-skeleton manual verification).
**Progress:** `[██████░░░░░░░░░░░░░░] T11/T13 in phase 1 · 0/6 phases overall complete`

```
Phase 1: Foundations & Sandbox Probes      [T01-T11 DONE · CI GREEN · T12/T13 MANUAL]  ← current
Phase 2: Authenticated Network Layer       [BLOCKED on Phase 1]
Phase 3: Sale Spine                        [BLOCKED on Phase 2]
Phase 4: Enrichment                        [BLOCKED on Phase 3]
Phase 5: Resilience & Error Handling       [BLOCKED on Phase 4]
Phase 6: Release & Polish                  [BLOCKED on Phase 5]
```

**Branch state:** `phase-1/foundations-sandbox-probes` is ahead of `main` by ~17 commits, all GPG-signed, all CI-green. Coverage 99.19 % (luacov, self-hosted badge on `coverage-badge` branch). 40 busted tests pass. Build is byte-reproducible. PR to `main` is intentionally not opened yet — T12/T13 close out first.

---

## Performance Metrics

(Populated as phases complete via `/gsd-transition`.)

| Phase | Started | Completed | Duration | Plans | Issues |
|-------|---------|-----------|----------|-------|--------|
| 1 | - | - | - | - | - |
| 2 | - | - | - | - | - |
| 3 | - | - | - | - | - |
| 4 | - | - | - | - | - |
| 5 | - | - | - | - | - |
| 6 | - | - | - | - | - |

---

## Accumulated Context

### Decisions (from research)

The 37 canonical decisions are pinned in `.planning/research/SUMMARY.md §2`. Highlights gating Phase 1:

- **D1** Lua 5.4 (currently 5.4.8) — pin CI to same patch line.
- **D2** Single `Extension.lua` generated from `src/*.lua`; no `require` in the artifact.
- **D3** Custom ~150-line `tools/build.lua` amalgamator + `tools/manifest.txt`; lua-amalg rejected.
- **D6** Coverage gate ≥85% on `src/` excluding `webbanking_header.lua`.
- **D27** `log.redact()` applied to every string before `print`; strips JWT-shape and `Bearer …`; `DEBUG = false` in shipped build.
- **D29** Production URLs hard-coded; sandbox URLs injected at build time for CI only; no env toggle in UI.
- **D31** Reproducible build: LF normalization, explicit manifest, no timestamps/SHAs/env leakage; CI builds twice + diffs.

### Active Todos

- Run `/gsd-execute-phase 1` to implement T01–T11 (scaffold → amalgamator → infra modules → mocks → specs → walking-skeleton entry → coverage gate → probe extension → ADRs → local e2e → CI workflow).
- After T11 lands green: maintainer-driven T12 (run probe extension in live MoneyMoney, transcribe results into ADR-0003) and T13 (manual walking-skeleton install + fixture observation in MoneyMoney).

### Blockers

(None.)

### Phase-1 Probe Status

| Probe | Question | Status |
|-------|----------|--------|
| Q1 | Lua sandbox globals (`require`, `os.execute`, `io.popen`, `package.loadlib`, `dofile`, `loadfile`, `debug.*`) | PENDING |
| Q2 | `Connection():request` redirect behavior on `oauth.zettle.com/token` | PENDING |
| Q3 | `finance.izettle.com` host with `GET /v2/accounts/liquid/balance` | PENDING |
| Q4 | `JSON():set(t):json()` integer round-trip with `amount=995` | PENDING |
| Q5 | `LocalStorage` cross-restart persistence | PENDING |
| Q6 | PayPal POS first-party `client_id` value | PENDING |
| Q7 | `services = {"PayPal POS"}` label rendering in MM German UI | PENDING |
| Q8 | `Connection()` TLS verification default (badssl.com test) | PENDING |

---

## Session Continuity

**Last action:** `/gsd-plan-phase 1` produced RESEARCH.md (76k), CONTEXT.md (14k), PLAN.md (37k, 13 tasks), SKELETON.md (13k), and VERIFICATION.md (PASS after one orchestrator closeout edit).

**Next action:** `/gsd-execute-phase 1` — implement T01–T11 sequentially with GPG-signed atomic commits per task. T12 and T13 are maintainer-driven gates after T11.

**Session resume prompt template** (if context lost):

> We are working on the MoneyMoney PayPal POS Extension. Phase 1 is PLANNED with 13 tasks in `.planning/phases/01-foundations-sandbox-probes/PLAN.md`. Walking-Skeleton mode active. Run `/gsd-execute-phase 1` to start implementation. Granularity: standard. Mode: mvp / yolo. All commits GPG-signed (`FDE07046A6178E89ADB57FD3DE300C53D8E18642`); no Claude/AI attribution in commits, PRs, or shipped code.

---

*State initialized: 2026-06-16 via `/gsd-roadmap`. Will be updated on every plan execution, phase transition, and milestone.*
