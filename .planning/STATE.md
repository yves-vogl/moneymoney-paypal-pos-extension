---
gsd_state_version: 1.0
milestone: v1.0.0
milestone_name: has stabilized in production for several weeks.
status: executing
last_updated: "2026-06-18T12:24:22.948Z"
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 7
  completed_plans: 4
  percent: 57
---

# Project State: MoneyMoney PayPal POS Extension

**Initialized:** 2026-06-16
**Last updated:** 2026-06-18 (post-plan-phase-2; ready to execute Phase 2)

---

## Project Reference

**Core Value:**
> A German PayPal POS merchant pastes their API key into MoneyMoney once and from then on sees every card transaction, refund, fee, and payout automatically in MoneyMoney — accurately, on schedule, with VAT and tip transparency suitable for bookkeeping.

**Current Focus:** Phase 02 — authenticated-network-layer

**Granularity:** standard (6 phases)
**Mode:** mvp / yolo (per `config.json`)

---

## Current Position

Phase: 02 (authenticated-network-layer) — EXECUTING
Plan: 3 of 7 complete
**Phase:** 2 — Authenticated Network Layer — **EXECUTING (Wave 1 done)**
**Plans:** `.planning/phases/02-authenticated-network-layer/02-0{1..7}-PLAN.md` (7 plans across 6 waves W0–W5)
**Status:** Executing Phase 02 — Wave 1 complete, dispatching Wave 2 next
**Progress:** `[████████░░░░░░░░░░░░] 3/7 plans complete` (W0 02-01, W1 02-02, W1 02-03)

```
Phase 1: Foundations & Sandbox Probes      [DONE ✅ — merged]
Phase 2: Authenticated Network Layer       [PLANNED — ready to execute]
Phase 3: Sale Spine                        [BLOCKED on Phase 2]
Phase 4: Enrichment                        [BLOCKED on Phase 3]
Phase 5: Resilience & Error Handling       [BLOCKED on Phase 4]
Phase 6: Release & Polish                  [BLOCKED on Phase 5]
Phase 6.1: OpenSSF Scorecard Hardening     [BLOCKED on Phase 6]
```

**Branch state:** `phase-2/authenticated-network-layer` is ahead of `main` with the Phase 1 history (24 commits, all GPG-signed, CI-green) plus Phase 2 planning artefacts: `docs(02): capture phase context`, `docs(02): add validation strategy`, `docs(02): create phase plan`, plus a Phase-6.1 detour (`docs(06.1): …`, `docs(roadmap): insert Phase 6.1 …`). No execution commits yet on Phase 2.

**Phase-2 inputs surfaced from Phase 1 (recorded here for the planner):**

- MM 2.4.72 does NOT honour the InitializeSession2 challenge object shape `{title, challenge, label}`; falls back to default Username+Password UI. Phase 2 must research the actual challenge-schema format MM accepts.
- `pcall()` does NOT catch `Connection()` SSL / network errors. Phase 2 `http.lua` must rely on MM's documented error-return pattern (`nil + error string` typical).
- LocalStorage cross-restart persistence is unobserved — Phase 2 token cache designs defensively for both outcomes; log line on cache-miss surfaces actual behaviour retroactively.

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

Phase-2 wave-by-wave execution (DAG-corrected — 02-05 depends on 02-04 so cannot run parallel):

- **Wave 0:** 02-01 (mocks + fixtures) — **DONE** ✅ commit `dab9db0`
- **Wave 1 (parallel):** 02-02 (`src/errors.lua` D-24 status→error map) + 02-03 (`src/auth.lua` JWT pure-logic D-22) — **DONE** ✅ commits `c58f297`, `3a99bf8`, `d3f7c71`, `19c26d0`
- **Wave 2:** 02-04 (`src/http.lua` Connection wrapper per D-25) — NEXT
- **Wave 3:** 02-05 (`src/auth.lua` orchestration: exchange_assertion, fetch_profile, persist_session D-23c, cached_token D-23d)
- **Wave 4:** 02-06 (`src/entry.lua` D-21 two-call probe integration)
- **Wave 5:** 02-07 (SEC-03 gating + manifest + reproducible-build)
- **Verification:** gsd-verifier + `/gsd-code-review 2` + loop-security-engineer SEC-03 adversarial review

### Roadmap Evolution

- Phase 6.1 inserted after Phase 6 on 2026-06-17 (URGENT) — Supply-chain & Scorecard hardening (OpenSSF Scorecard 5.2 → 8.5+); see `.planning/research/openssf-scorecard-sprint-proposal.md`.

### Blockers

(None.)

### Phase-1 Probe Status

Resolved live on MoneyMoney 2.4.72 / macOS 26.4.1 ARM (see ADR-0003 ACCEPTED). Surviving caveat carried into Phase 2:

- Q4 `JSON():set(t):json()` integer round-trip with `amount=995` — flagged as a Phase-3 precondition for the gross/VAT/tip mapping decision; not a Phase-2 blocker but to be revisited in `/gsd-discuss-phase 3`.

---

## Session Continuity

**Last action:** Wave 1 (Plans 02-02 + 02-03) executed in parallel via two Sonnet gsd-executor agents in worktrees. Implementation commits cherry-picked back onto `phase-2/authenticated-network-layer`. Plan-summaries copied; ROADMAP updated via `gsd-tools roadmap update-plan-progress 2`.

**Next action:** Dispatch Wave 2 — Plan 02-04 (`src/http.lua` Connection wrapper per D-25). Single Sonnet executor in worktree, baseRef=head.

**Session resume prompt template** (if context lost):

> We are working on the MoneyMoney PayPal POS Extension. Phase 2 (Authenticated Network Layer) is PLANNED with 7 plans across 5 waves in `.planning/phases/02-authenticated-network-layer/`. Run `/gsd-execute-phase 2` to start implementation. Granularity: standard. Mode: mvp / yolo. All commits GPG-signed (`FDE07046A6178E89ADB57FD3DE300C53D8E18642`); no Claude/AI attribution in commits, PRs, or shipped code.

---

*State initialized: 2026-06-16 via `/gsd-roadmap`. Will be updated on every plan execution, phase transition, and milestone.*
