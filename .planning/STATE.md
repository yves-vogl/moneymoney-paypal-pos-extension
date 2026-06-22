---
gsd_state_version: 1.0
milestone: v1.0.0
milestone_name: has stabilized in production for several weeks.
status: All 5 plans landed across 4 waves on `phase-5/resilience` branch + Plan 05-06 post-review fix-batch landed (REVIEW.md WR-01/WR-02/WR-03 + SECURITY-REVIEW S-01/S-02/S-03/S-04/S-05/S-06 addressed; Tier-3 WR-04/IN-01..04/S-07 deferred to follow-up PR). ADR-0005 ACCEPTED with 6 invariants pinned + 3 carve-outs (SSL bypass / HTTP-date Retry-After degradation / anchor stub) + Implementation Pin extended with two new contracts (599-sentinel emission live + per-request wall-clock cap) + sleep mechanism (MM.sleep + pcall-defensive) + updated worst-case timing budget. Retry semantics shipped in src/http.lua _request_with_retry (5xx 3-attempts {1,2,4}s; 429 single-retry Retry-After integer-only with 60s cap + 30s default + strict digit-only precheck post-S-04; 599 sentinel emission NOW LIVE for server_error/internal_error/backend_error/service_unavailable/temporarily_unavailable/server_busy 5xx body shapes post-S-02; _WALL_CLOCK_CAP=60s bounds adversarial mixed-error sequences post-S-01). ERR-04 post-mint 401 → German error.token_revoked via iterator-layer 401-direct-check (4 call sites). ERR-06 fail-whole-refresh structurally enforced. SEC-03 invariant preserved + extended (Gate D + Gate D extended for malicious cursor CR/LF percent-encoding post-S-03 + degraded MM.sleep pcall path coverage post-S-06). Phase-4 surface frozen.
last_updated: "2026-06-22T09:58:20.441Z"
progress:
  total_phases: 7
  completed_phases: 3
  total_plans: 31
  completed_plans: 29
  percent: 43
---

# Project State: MoneyMoney PayPal POS Extension

**Initialized:** 2026-06-16
**Last updated:** 2026-06-18 (post-plan-phase-2; ready to execute Phase 2)

---

## Project Reference

**Core Value:**
> A German PayPal POS merchant pastes their API key into MoneyMoney once and from then on sees every card transaction, refund, fee, and payout automatically in MoneyMoney — accurately, on schedule, with VAT and tip transparency suitable for bookkeeping.

**Current Focus:** Phase 06 — release-polish (Plan 06-01 SHIPPED 2026-06-22; Plan 06-02 + 06-03 queued)

**Granularity:** standard (6 phases)
**Mode:** mvp / yolo (per `config.json`)

---

## Current Position

Phase: 06 (release-polish) — **Plan 06-01 (Wave-1 build-pipeline + CI-gates) SHIPPED 2026-06-22; Plans 06-02 + 06-03 queued**

**Plan 06-01 commits** (on `phase-6/release-polish`, all GPG-signed):

- `cc14215` test(06-01): RED scaffold for `__VERSION__` substitution spec (BUILD-03)
- `0bad03e` feat(06-01): `__VERSION__` substitution from `$GITHUB_REF_NAME` (BUILD-03 / D-73)
- `3b33b3a` test(06-01): extend META-03 walker to documentation markdown (DOC-04 / Pitfall 6)
- `1796676` ci(06-01): allowlist fixture-only gitleaks fingerprints (Pitfall 5; 21 audited false-positive fingerprints)
- `6b14185` ci(06-01): add gitleaks + commit-lint + D-79 raw-print() grep (CI-05 / D-78 / D-79)

Full suite **381 successes / 0 failures / 0 errors / 0 pending** (was 373; +7 BUILD-03 + 1 META-03 doc-extension). luacheck clean (41 files). Reproducible build SHA recomputed: dev `4526a33fceab55122a6e624207c03cf76545939685825c3072c9d9001653304c`, tagged-v1.0.0 `d1afc595edc528db6719b826a084765719a7f249cb3b8a53cf1c6dd2790c8d36` (Phase-5 baseline was `5dbcb8ea…`; delta is by design — header now substitutes `__VERSION__` + optional DEV BUILD banner).

**CI check names for 06-02 setup-branch-protection.sh CHECKS array:** `Lint + tests + reproducible build` (existing), `gitleaks secret scan` (new), `Commit-message lint` (new).

**Closes:** BUILD-03, CI-05 fully; META-03 walker now covers documentation markdown (DOC-04 scaffolding in place for Wave-2 doc authoring).

**Previous: Phase 5** — **IMPLEMENTATION + 05-06 FIX-BATCH COMPLETE; READY-FOR-RE-VERIFICATION 2026-06-22**

**Status:** All 5 plans landed across 4 waves on `phase-5/resilience` branch + Plan 05-06 post-review fix-batch landed (REVIEW.md WR-01/WR-02/WR-03 + SECURITY-REVIEW S-01/S-02/S-03/S-04/S-05/S-06 addressed; Tier-3 WR-04/IN-01..04/S-07 deferred to follow-up PR). ADR-0005 ACCEPTED with 6 invariants pinned + 3 carve-outs (SSL bypass / HTTP-date Retry-After degradation / anchor stub) + Implementation Pin extended with two new contracts (599-sentinel emission live + per-request wall-clock cap) + sleep mechanism (MM.sleep + pcall-defensive) + updated worst-case timing budget. Retry semantics shipped in src/http.lua _request_with_retry (5xx 3-attempts {1,2,4}s; 429 single-retry Retry-After integer-only with 60s cap + 30s default + strict digit-only precheck post-S-04; 599 sentinel emission NOW LIVE for server_error/internal_error/backend_error/service_unavailable/temporarily_unavailable/server_busy 5xx body shapes post-S-02; _WALL_CLOCK_CAP=60s bounds adversarial mixed-error sequences post-S-01). ERR-04 post-mint 401 → German error.token_revoked via iterator-layer 401-direct-check (4 call sites). ERR-06 fail-whole-refresh structurally enforced. SEC-03 invariant preserved + extended (Gate D + Gate D extended for malicious cursor CR/LF percent-encoding post-S-03 + degraded MM.sleep pcall path coverage post-S-06). Phase-4 surface frozen.

**Plan-05 commits** (on `phase-5/resilience`, all GPG-signed):

- Plan 05-01: ADR-0005 transition Proposed → ACCEPTED + Q9 probe block in tools/probe.lua
- Plan 05-02: i18n keys (error.server_busy + error.token_revoked) + M_errors 599 sentinel + RED scaffolds (http_retry_spec + refresh_fail_whole_spec)
- Plan 05-03: M_http retry-with-backoff (5xx + 429 + 599 sentinel + D-68 INFO log) + 8 pending → GREEN flips in http_retry_spec
- Plan 05-04: ERR-04 401-direct-check (iterator + inline) + ERR-01 round-trip regression + fix-batch (4 commits including 868c241 HI-01 + e8b0bf7 HI-02 + 19be0fb ME-01 + 119ea7c S-04)
- Plan 05-05: 4 ERR-06 fail-whole cases (1de7caf) + SEC-03 Gate D (9d05f95) + Phase-4 surface preservation (06ac4c7) + ADR-0005 Implementation Pin (ca4df8f)
- **Plan 05-06 (post-review fix-batch, NEW):** 4 source-changing fixes (43ebc46 S-02/WR-01/WR-02 599-sentinel-live + bdb78cd S-01/WR-03 wall-clock-cap + 301e157 S-04 hex-reject + 714ff3e ADR-0005 update) + 4 RED-first / regression-only test commits (c781acc + cf1f23b + f119f02 + 51e09e1 S-03 Gate-D-extended + 9efab5b S-06 degraded-MM.sleep).

Full suite **373 successes / 0 failures / 0 errors / 0 pending** (was 365; +8 new regression tests). luacheck: local env runs Lua 5.5 where the luacheck 1.2.0-1 module has a runtime regression (`luacheck.standards` const assignment); CI runs Lua 5.4 where it passes (pinned by `leafo/gh-actions-lua@v13`). Reproducible build sha **`5dbcb8ea97ae2fb2b675442439ac93b342893e84b9e7849b29df07e9612b777e`** (was `b151f16…`; changed because of S-02, S-01, S-04 source fixes to src/http.lua).

**Recommended next steps:** re-run gsd-verifier on Phase 5 to confirm 6/6 must-haves still pass after fix-batch; optional parallel re-run of gsd-code-reviewer + loop-security-engineer to confirm only Tier-3 deferred items remain; PR via `gh pr create` + squash merge per `feedback_gpg_signed_pr_merge` (never `--rebase`); Phase 6 unblocked once Phase 5 lands on main.

---

### Previous Phase: 04 — DONE (merged)

Phase: 04 (enrichment-refunds-fees-payouts) — **IMPLEMENTATION + POST-REVIEW FIX BATCH COMPLETE; READY-FOR-RE-VERIFICATION 2026-06-21**
**Status:** Phase 3 fully merged to main (spine via PR #8 `a11287d`; verifier closure via PR #10 `a201f6c`). Phase 4 planning artifacts complete + Waves 1+2+3+4+5 implementation landed + Plan 04-07 (post-review fix batch) landed:

- Plan 04-02 (Wave-1 pure-logic) shipped 3 GPG-signed commits (`24990d9` test fixtures + RED scaffolds; `a75f6d7` offset_iterate + manifest consolidation; `c4ed80e` M_finance.parse_transaction + 4 mapping mappers + 12 i18n keys).
- Plan 04-04 (Wave-3 mapping enrichment) shipped 2 GPG-signed commits (`d3d1311` RED scaffolds + new fixtures; `08207a4` per-rate VAT + card-tail in _format_purpose).
- Plan 04-03 (Wave-2 Finance HTTP + cross-refresh integration) shipped 2 GPG-signed commits (`54e6fd8` M_finance.fetch + fetch_all + fetch_account_state; `84052c3` 16-step RefreshAccount extension with purchases_by_uuid + payments_by_uuid + SALE-03 promotion + D-49 Option B + payout mapping).
- Plan 04-05 (Wave-4 invariant gates) shipped 3 GPG-signed commits (`8f3455c` META-03 forbidden-strings spec; `d52e8df` META-02 zero-suppression + META-01 zero-rate edge spec; `0803ed2` D-58 idempotency extensions + D-38 prefix gate + SEC-03 Finance API redaction).
- Plan 04-06 (Wave-5 release polish + audit) shipped 3 GPG-signed commits (`61ed67f` ADR-0004 Finance API scope + fee-fallback contract; `ec077d9` Phase-3 surface preservation audit spec; `16a06de` CHANGELOG + README v0.2.0 German sections engineering-draft).
- **Plan 04-07 (post-review fix batch — autonomous-window) shipped 13 GPG-signed commits** addressing REVIEW.md (3 BLOCKER + 4 WARNING) + SECURITY-REVIEW.md (1 HIGH + 4 MEDIUM + 1 LOW). Full per-finding mapping in `04-07-FIX-SUMMARY.md`.

Full suite 328 → **335 successes / 0 failures**; luacheck 0/0 in 38 files; reproducible build sha `6f4f685fd40f2922cb318a786c08b4d7182e0eb167e2c5c90c137fe47308fe54`. Plan 04-01 (Q3 sandbox probe) still pending Yves' live verification. Plan 04-06 Task 4 (loop-lektor pass on CHANGELOG/README/ADR-0004 German wording) deferred to Yves checkpoint after merge per orchestrator standing instruction.
**Progress:** [█████████░] 89%

```
Phase 1: Foundations & Sandbox Probes      [DONE ✅ — merged]
Phase 2: Authenticated Network Layer       [DONE ✅ — merged via PR #6 + Lows PR #7]
Phase 3: Sale Spine                        [DONE ✅ — merged via PR #8 spine + PR #10 verifier closure]
Phase 4: Enrichment                        [PLANNED ✅ — 04-CONTEXT/RESEARCH/PATTERNS/6 PLANs/PLAN-REVIEW committed; awaiting Yves unblock]
Phase 5: Resilience & Error Handling       [IMPLEMENTATION COMPLETE ✅ — READY-FOR-VERIFIER 2026-06-22]
Phase 6: Release & Polish                  [BLOCKED on Phase 5 ship to main]
Phase 6.1: OpenSSF Scorecard Hardening     [BLOCKED on Phase 6]
```

**Branch state:** On `phase-4/enrichment` (created 2026-06-21 from `origin/main` @ `a201f6c`). 25 local commits (6 planning + 3 Plan-04-02 + 2 Plan-04-04 + 2 Plan-04-03 + 3 Plan-04-05 + 3 Plan-04-06 + 5 docs/state/summary + 1 tools/probe):

- `1578b75` docs(04): capture phase 4 enrichment context (autonomous draft)
- `211da0b` docs(state): mark Phase 3 fully merged, Phase 4 context drafted
- `0ac35b7` docs(04): research Phase 4 enrichment domain — Finance API surface, fee linkage, payout matching
- `686df47` docs(04): map Phase 4 enrichment patterns to Phase-1/2/3 analogs
- `26d6736` docs(04): create Phase 4 plans 04-01..04-06 across 6 waves
- `c2d857d` docs(04): plan-check verification report — READY-FOR-EXECUTION
- `b87426f` docs(state): Phase 4 fully planned — READY-FOR-EXECUTION
- `50adec9` tools(04-01): add probe-finance.sh helper for Q3 sandbox closure
- `24990d9` test(04-02): add Phase-4 fixtures + RED scaffolds for finance/pagination_offset specs
- `a75f6d7` feat(04-02): add M_pagination.offset_iterate + consolidate manifest
- `c4ed80e` feat(04-02): add M_finance.parse_transaction + 4 mapping mappers + 12 i18n keys
- `d28508c` docs(04): land Yves-checkpoint decisions + Plan 04-02 summary
- `d3d1311` test(04-04): add fixtures + RED scaffolds for META-01 per-rate VAT + SALE-07 card tail + Phase-3 snapshot
- `08207a4` feat(04-04): per-rate VAT lines + card-brand+entry-mode tail in _format_purpose (META-01, SALE-07, D-53, D-57)
- `54e6fd8` feat(04-03): add M_finance.fetch + fetch_all + fetch_account_state (RESEARCH §1.3, §1.4)
- `f521105` docs(04-04): Plan 04-04 summary — per-rate VAT + card tail enrichments landed
- `84052c3` feat(04-03): wire finance API + cross-refresh indexes into RefreshAccount

Not yet pushed — held local pending Yves' review of Q3 / D-49 / D-55. Memory `feedback_gpg_signed_pr_merge` still governs merge method (`--squash` mandatory). Memory `feedback_post_squash_no_repr` records the PR #9 → #10 reconciliation lesson.

**Phase-3 captured decisions** (still authoritative; D-31..D-45 inherited by Phase 4): see `.planning/phases/03-sale-spine-first-user-visible-slice/03-CONTEXT.md`.

**Phase-4 Yves blockers** (queued — autonomous window cannot resolve):

- **Q3** Live probe of `https://finance.izettle.com/v2/accounts/liquid/transactions` with sandbox API key; flip ADR-0003 Q3 from DEFERRED → ACCEPTED. Plan 04-01 (Wave 0) is exactly this single task.
- **D-49** **RESOLVED 2026-06-21**: Option B (per-refresh date clustering) implemented per Yves checkpoint. README disclaimer queued for Plan 04-06.
- **D-55** **RESOLVED 2026-06-21**: 13-phrase forbidden-strings list confirmed; Plan 04-05 gating spec lands the invariant.

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

**Last action:** Plan 06-01 (Wave-1 build-pipeline + CI-gates) executed 2026-06-22 on `phase-6/release-polish`. 5 GPG-signed commits (`cc14215` RED → `0bad03e` GREEN → `3b33b3a` META-03 doc-extension → `1796676` .gitleaksignore → `6b14185` gitleaks/commit-lint/D-79). Full busted: 381/0/0/0; luacheck clean; reproducible. Summary at `.planning/phases/06-release-polish/06-01-SUMMARY.md`.

**Next action:** Plan 06-02 (Wave-2 release.yml + setup-branch-protection.sh + README.de.md/EN split + 4 new ADRs). The 3 CI check names for the branch-protection script are documented in 06-01-SUMMARY.md.

**Session resume prompt template** (if context lost):

> We are working on the MoneyMoney PayPal POS Extension. Phase 2 (Authenticated Network Layer) was merged to main on 2026-06-20 via PRs #6 + #7. Phase 3 (Sale Spine) is in PLANNING — `03-CONTEXT.md` captured the decisions D-31..D-45. Next step: `/gsd-plan-phase 3` (research + pattern-mapper + planner + plan-checker). Granularity: standard. Mode: mvp / yolo. All commits GPG-signed (`FDE07046A6178E89ADB57FD3DE300C53D8E18642`); no Claude/AI attribution in commits, PRs, or shipped code. **PR merge method: `--squash` (lesson saved as memory `feedback_gpg_signed_pr_merge`; `--rebase` produces unsigned commits).**

---

*State initialized: 2026-06-16 via `/gsd-roadmap`. Will be updated on every plan execution, phase transition, and milestone.*
