# Project State: MoneyMoney PayPal POS Extension

**Initialized:** 2026-06-16
**Last updated:** 2026-06-16 (post-roadmap)

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
**Plan:** (none yet — awaiting `/gsd-plan-phase 1`)
**Status:** ready
**Progress:** `[░░░░░░░░░░░░░░░░░░░░] 0/6 phases (0%)`

```
Phase 1: Foundations & Sandbox Probes      [READY]    ← current
Phase 2: Authenticated Network Layer       [BLOCKED on Phase 1]
Phase 3: Sale Spine                        [BLOCKED on Phase 2]
Phase 4: Enrichment                        [BLOCKED on Phase 3]
Phase 5: Resilience & Error Handling       [BLOCKED on Phase 4]
Phase 6: Release & Polish                  [BLOCKED on Phase 5]
```

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

- Run `/gsd-plan-phase 1` to decompose Phase 1 into executable plans.
- Probe extension (Q1–Q8) must execute against a live MoneyMoney instance — schedule with maintainer access.

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

**Last action:** `/gsd-roadmap` created `ROADMAP.md`, initialized `STATE.md`, populated `REQUIREMENTS.md` traceability table.

**Next action:** `/gsd-plan-phase 1` — decompose Phase 1 (Foundations & Sandbox Probes) into ordered plans. Plans likely include:
1. Repo skeleton (`src/`, `spec/`, `tools/`, `.luacheckrc`, `.busted`, `.luacov`, minimal `ci.yml`)
2. `tools/build.lua` amalgamator + `tools/manifest.txt`
3. `spec/helpers/mm_mocks.lua` (Connection/JSON/LocalStorage/MM mocks)
4. Infra modules: `model`, `i18n`, `errors`, `log` with `redact()`
5. Probe extension + execution against live MoneyMoney + ADR `0003-sandbox-probe-results.md`
6. Phase-1 gate: `busted` green, `lua tools/build.lua --verify` byte-identical, all 8 probes in ADR.

**Session resume prompt template** (if context lost):

> We are working on the MoneyMoney PayPal POS Extension. ROADMAP.md is committed with 6 phases. We are at the start of Phase 1 (Foundations & Sandbox Probes). Run `/gsd-plan-phase 1` to decompose into executable plans. Granularity: standard. Mode: mvp / yolo. See `.planning/ROADMAP.md` and `.planning/research/SUMMARY.md` for canonical context.

---

*State initialized: 2026-06-16 via `/gsd-roadmap`. Will be updated on every plan execution, phase transition, and milestone.*
