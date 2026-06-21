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

Phase: 04 (enrichment-refunds-fees-payouts) — **IN EXECUTION; Plan 04-02 (Wave-1 pure-logic) shipped 2026-06-21**
**Status:** Phase 3 fully merged to main (spine via PR #8 `a11287d`; verifier closure via PR #10 `a201f6c`). Phase 4 planning artifacts complete + Wave-1 implementation landed: Plan 04-02 shipped 3 GPG-signed commits (`24990d9` test fixtures + RED scaffolds; `a75f6d7` offset_iterate + manifest consolidation; `c4ed80e` M_finance.parse_transaction + 4 mapping mappers + 12 i18n keys). Full suite 203 → 255 successes / 0 failures; luacheck 0/0; reproducible build sha `6bc796e66d5af246...`. Plan 04-01 (Q3 sandbox probe) still pending Yves. Plan 04-03 (Wave 2 — Finance API HTTP + cross-refresh indexes) unblocked.
**Progress:** `[████████████████░░░░] 3/7 phases shipped; Phase 4 Wave 1 (Plan 04-02) shipped; Plan 04-01 (Yves Q3 probe) + Plans 04-03..04-06 pending`

```
Phase 1: Foundations & Sandbox Probes      [DONE ✅ — merged]
Phase 2: Authenticated Network Layer       [DONE ✅ — merged via PR #6 + Lows PR #7]
Phase 3: Sale Spine                        [DONE ✅ — merged via PR #8 spine + PR #10 verifier closure]
Phase 4: Enrichment                        [PLANNED ✅ — 04-CONTEXT/RESEARCH/PATTERNS/6 PLANs/PLAN-REVIEW committed; awaiting Yves unblock]
Phase 5: Resilience & Error Handling       [BLOCKED on Phase 4]
Phase 6: Release & Polish                  [BLOCKED on Phase 5]
Phase 6.1: OpenSSF Scorecard Hardening     [BLOCKED on Phase 6]
```

**Branch state:** On `phase-4/enrichment` (created 2026-06-21 from `origin/main` @ `a201f6c`). 9 local commits (6 planning + 3 Plan-04-02 execution):
- `1578b75` docs(04): capture phase 4 enrichment context (autonomous draft)
- `211da0b` docs(state): mark Phase 3 fully merged, Phase 4 context drafted
- `0ac35b7` docs(04): research Phase 4 enrichment domain — Finance API surface, fee linkage, payout matching
- `686df47` docs(04): map Phase 4 enrichment patterns to Phase-1/2/3 analogs
- `26d6736` docs(04): create Phase 4 plans 04-01..04-06 across 6 waves
- `c2d857d` docs(04): plan-check verification report — READY-FOR-EXECUTION
- `24990d9` test(04-02): add Phase-4 fixtures + RED scaffolds for finance/pagination_offset specs
- `a75f6d7` feat(04-02): add M_pagination.offset_iterate + consolidate manifest
- `c4ed80e` feat(04-02): add M_finance.parse_transaction + 4 mapping mappers + 12 i18n keys

Not yet pushed — held local pending Yves' review of Q3 / D-49 / D-55. Memory `feedback_gpg_signed_pr_merge` still governs merge method (`--squash` mandatory). Memory `feedback_post_squash_no_repr` records the PR #9 → #10 reconciliation lesson.

**Phase-3 captured decisions** (still authoritative; D-31..D-45 inherited by Phase 4): see `.planning/phases/03-sale-spine-first-user-visible-slice/03-CONTEXT.md`.

**Phase-4 Yves blockers** (queued — autonomous window cannot resolve):

- **Q3** Live probe of `https://finance.izettle.com/v2/accounts/liquid/transactions` with sandbox API key; flip ADR-0003 Q3 from DEFERRED → ACCEPTED. Plan 04-01 (Wave 0) is exactly this single task.
- **D-49** Pay/Compliance sign-off on fee-fallback contract: aggregate persistence wins over linkage upgrades (slightly lossy fee linkage in exchange for hard dedup; once aggregated for a date, never re-emitted as per-sale rows).
- **D-55** Pay/Compliance sign-off on META-03 forbidden-strings list (13 phrases drafted; permanent invariant once locked).

See `.planning/phases/04-enrichment-refunds-fees-payouts/04-CONTEXT.md` for full D-46..D-60 text.

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
