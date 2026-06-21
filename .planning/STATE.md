---
gsd_state_version: 1.0
milestone: v1.0.0
milestone_name: has stabilized in production for several weeks.
status: executing
last_updated: "2026-06-20T03:55:54.485Z"
progress:
  total_phases: 7
  completed_phases: 1
  total_plans: 8
  completed_plans: 8
  percent: 14
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

Phase: 03 (sale-spine-first-user-visible-slice) — **SPINE MERGED, verifier report shipping**
**Status:** Phase-3 spine + post-review fix batch (S/HI/ME findings) squash-merged via PR #8 (`a11287d` on main 2026-06-20). Verifier report (`03-VERIFICATION.md`) shipping in a follow-up PR.
**Progress:** `[████████████░░░░░░░░] Phase 3 spine on main; Phase 4 unblocked once verifier PR merges`

```
Phase 1: Foundations & Sandbox Probes      [DONE ✅ — merged]
Phase 2: Authenticated Network Layer       [DONE ✅ — merged via PR #6 + Lows PR #7]
Phase 3: Sale Spine                        [SPINE MERGED ✅ via PR #8 — verifier report in follow-up PR]
Phase 4: Enrichment                        [READY — spine on main; discuss-phase next]
Phase 5: Resilience & Error Handling       [BLOCKED on Phase 4]
Phase 6: Release & Polish                  [BLOCKED on Phase 5]
Phase 6.1: OpenSSF Scorecard Hardening     [BLOCKED on Phase 6]
```

**Branch state:** PR #9 was opened against main with 45 commits, but conflicted because PR #8 had already squash-merged the same 39 source commits — both versions of the same content on different SHAs produced a synthetic 3-way merge conflict. PR #9 was closed; a clean `phase-3/post-review-fixes` branch was opened from current main with only the genuinely missing artifact (`03-VERIFICATION.md`) cherry-picked on. Verifier verdict: 10/10 must-haves PASSED, READY-TO-MERGE; busted 203/0/0/0; reproducible build SHA `344011f9…`; luacheck clean; coverage 99.23 %. Lesson recorded in memory: open Phase PRs before squash-merging the same branch from a different SHA. Memory `feedback_gpg_signed_pr_merge` still governs merge method (`--squash` mandatory).

**Phase-3 captured decisions (CONTEXT.md):**

- **D-31** Pending/booked: all Phase-3 sales emit `booked=false`; Phase 4 promotes via same `transactionCode`.
- **D-32** Refunds: own negative transaction `zettle:refund:<purchaseUUID1>`; original sale unchanged.
- **D-33** First-refresh pagination: clamp `since` to max 90 days back; README documents.
- **D-36 (Claude's discretion)** `bookingDate`: Europe/Berlin DST-aware via hardcoded EU rules table (2020–2040).
- **D-34/D-35** purpose/name German bookkeeping format.
- **D-37** Multi-currency defensive: skip non-EUR purchases silently with INFO log.
- See `.planning/phases/03-sale-spine-first-user-visible-slice/03-CONTEXT.md` for D-31..D-45 full text.

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

Phase-3 planning (autonomous 48h window from 2026-06-20 ~03:30 UTC, see `feedback_48h_autonomous_window` memory):

- **CONTEXT captured** ✅ commit `b359a2e` — D-31..D-45 locked
- **NEXT: `/gsd-plan-phase 3`** — spawn gsd-phase-researcher (research mapping/pagination/idempotency approaches) → gsd-pattern-mapper (Phase-3 PATTERNS.md against Phase-1/2 analogs) → gsd-planner (Opus, emits PLAN files) → gsd-plan-checker (verify)
- **Phase-3 execution** — wave-by-wave Sonnet executors (same model as Phase 2), worktrees, GPG-signed, no AI attribution
- **Verifier + security + code-review** — parallel after execution
- **PR + squash merge** — `gh pr merge --squash` (lesson from PR #6 saved as `feedback_gpg_signed_pr_merge`)
- **Phase 4 planning** if time remains in 48h window

### Roadmap Evolution

- Phase 6.1 inserted after Phase 6 on 2026-06-17 (URGENT) — Supply-chain & Scorecard hardening (OpenSSF Scorecard 5.2 → 8.5+); see `.planning/research/openssf-scorecard-sprint-proposal.md`.

### Blockers

(None.)

### Phase-1 Probe Status

Resolved live on MoneyMoney 2.4.72 / macOS 26.4.1 ARM (see ADR-0003 ACCEPTED). All Phase-3-relevant questions closed:

- **Q4 RESOLVED (PASS):** `JSON():set({amount=995}):json()` round-trips integers; `mapping.lua` stores minor-unit amounts as plain Lua numbers. No `string.format("%d", v)` workaround needed.
- **Q3 (still DEFERRED to Phase 4):** `finance.izettle.com` host for payouts. Phase 3 only calls `purchase.izettle.com`; Q3 is not a Phase-3 blocker.

---

## Session Continuity

**Last action:** Phase 3 Plan 03-01 (Wave 0) executed. 10 fixtures under `spec/fixtures/purchases/` created. 4 pending spec scaffolds created (`spec/dst_table_spec.lua`, `spec/mapping_spec.lua`, `spec/pagination_spec.lua`, `spec/purchases_spec.lua`). Full busted suite: 119/0/0/36. luacheck: clean. Commits: `2650f0a` (fixtures) + `de82bea` (DST spec) + `e81f513` (mapping/pagination/purchases specs). Branch: `worktree-agent-ab3ac8af8d3e9bf1b`.

**Next action:** Wave 1 — Plan 03-02 (gating RED specs: `spec/refresh_idempotency_spec.lua` + `spec/mapping_schema_spec.lua`).

**Session resume prompt template** (if context lost):

> We are working on the MoneyMoney PayPal POS Extension. Phase 2 (Authenticated Network Layer) was merged to main on 2026-06-20 via PRs #6 + #7. Phase 3 (Sale Spine) is in PLANNING — `03-CONTEXT.md` captured the decisions D-31..D-45. Next step: `/gsd-plan-phase 3` (research + pattern-mapper + planner + plan-checker). Granularity: standard. Mode: mvp / yolo. All commits GPG-signed (`FDE07046A6178E89ADB57FD3DE300C53D8E18642`); no Claude/AI attribution in commits, PRs, or shipped code. **PR merge method: `--squash` (lesson saved as memory `feedback_gpg_signed_pr_merge`; `--rebase` produces unsigned commits).**

---

*State initialized: 2026-06-16 via `/gsd-roadmap`. Will be updated on every plan execution, phase transition, and milestone.*
