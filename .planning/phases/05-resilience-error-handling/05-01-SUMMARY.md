---
phase: 05-resilience-error-handling
plan: 01
subsystem: documentation
tags: [wave-0, adr, probe, resilience, mvp]
requires: []
provides:
  - "ADR-0005 (resilience invariants) load-bearing reference for Plans 05-02..05-05"
  - "Q9 sandbox probe block in tools/probe.lua (optional confirmation of MM.sleep)"
affects:
  - "docs/adr/0005-resilience-invariants.md (new)"
  - "tools/probe.lua (extended with Q9 block, ~21 lines)"
tech_stack:
  added: []
  patterns:
    - "MADR-format ADR (Status / Context / Decision / Carve-outs / Consequences / Sources)"
    - "pcall-guarded sandbox probe with PASS / PRESENT-BUT-NOOP / ABSENT / FAIL classification"
key_files:
  created:
    - docs/adr/0005-resilience-invariants.md
  modified:
    - tools/probe.lua
decisions:
  - "D-64 silent re-mint COLLAPSED to '401 → error.token_revoked IMMEDIATELY' per RESEARCH §Pattern-2 (assertion-grant + SEC-03 / AUTH-05 forbid the only feasible re-mint paths)"
  - "Sleep mechanism is MM.sleep (not a nested MM.os variant — corrects CONTEXT D-67 / Q9 typo)"
  - "Retry-After parsing integer-only; HTTP-date silently degrades to 30s default (Carve-out 2)"
  - "SSL handshake failures bypass ERR-05 (Carve-out 1) — accepted, not fixable from Lua user code"
  - "Q9 sandbox probe is OPTIONAL per RESEARCH §1 (MM.sleep already documented in WebBanking API + mocked in test harness)"
metrics:
  duration_minutes: 4
  completed_date: 2026-06-22
  tasks_completed: 2
  files_created: 1
  files_modified: 1
  commits: 2
---

# Phase 5 Plan 01: ADR-0005 + Q9 Probe Scaffolding Summary

ADR-0005 (resilience invariants) and Q9 MM.sleep sandbox probe shipped as the load-bearing reference + optional confirmation primitive for Phase 5 Plans 05-02..05-05.

## What shipped

### Task 1 — `docs/adr/0005-resilience-invariants.md` (NEW, 365 lines)

MADR-format ADR documenting the six Phase-5 resilience invariants verbatim from CONTEXT D-61..D-69 with the four RESEARCH corrections baked in:

| Invariant | Requirement | Contract                                                                          | Owner Plan |
|-----------|-------------|-----------------------------------------------------------------------------------|------------|
| 1         | ERR-01      | `invalid_grant` → `LoginFailed`                                                   | 05-02 spec |
| 2         | ERR-02      | 5xx retry-with-backoff `{1, 2, 4}`s, 3 attempts (iterative)                       | 05-03      |
| 3         | ERR-03      | 429 single retry, integer `Retry-After`, 60 s cap, 30 s default                   | 05-03      |
| 4         | ERR-04      | post-mint 401 → `error.token_revoked` IMMEDIATELY (D-64 COLLAPSED)                | 05-04      |
| 5         | ERR-05      | network failure → `error.network` via empty-body path                             | 05-02 spec |
| 6         | ERR-06      | fail-whole-refresh structurally enforced by Phase-4 `entry.lua` 16-step pipeline  | 05-05 spec |

Plus two carve-outs (deliberate accepted limitations):
- **SSL handshake bypass**: `pcall` does NOT catch SSL errors (ADR-0003 Q8 bonus); ERR-05 covers DNS / connect-refused / socket timeouts only.
- **HTTP-date Retry-After fallback**: silently degrades to 30 s default; ~80 LoC RFC 7231 §7.1.1.1 parser is bad ROI when Zettle has never been observed to emit HTTP-date.

Plus sleep-mechanism choice: `MM.sleep(seconds)` — the documented top-level helper. Earlier CONTEXT D-67 + Q9 used a nested `MM.os` variant which does not exist as an API surface.

Plus worst-case timing budget: single-endpoint 5xx storm ~9 s; 3-endpoint storm ~27 s (uncomfortably close to MoneyMoney's ~30 s per-call budget but accepted for v1.0.0; mitigation strategies enumerated for v1.0.x).

**Commit:** `35d05e9` — GPG-signed by `FDE07046A6178E89ADB57FD3DE300C53D8E18642`.

### Task 2 — `tools/probe.lua` Q9 block (+21 lines)

Appended after the Q8 TLS block and before the file's closing `print` / return. Matches the Q4/Q5/Q8 pattern verbatim:

- `type(MM) ~= "table"` → `FAIL`
- `type(MM.sleep) ~= "function"` → `ABSENT` (forces busy-wait fallback per ADR-0005)
- `pcall(MM.sleep, 1)` errors → `FAIL`
- elapsed < 1 → `PRESENT-BUT-NOOP`
- elapsed >= 1 → `PASS`

`ACTION` line points at `docs/adr/0003-sandbox-probe-results.md` row Q9 (Yves adds the row after running the probe; Plan 05-01 does NOT pre-add it).

**Commit:** `fb0938e` — GPG-signed by `FDE07046A6178E89ADB57FD3DE300C53D8E18642`.

## Verification

```
$ wc -l docs/adr/0005-resilience-invariants.md
365 docs/adr/0005-resilience-invariants.md

$ grep -c 'ERR-0[1-6]' docs/adr/0005-resilience-invariants.md
27   (all six requirements, multiple mentions each)

$ grep -E '^## ' docs/adr/0005-resilience-invariants.md | wc -l
11   (Status, Date, Deciders, Context, Decision, Carve-outs, Sleep mechanism,
     Worst-case timing budget, Cross-reference table, Consequences, Sources)

$ grep -r 'MM\.os\.sleep' docs/adr/0005-resilience-invariants.md tools/probe.lua
(no matches — typo NOT propagated)

$ lua -e 'assert(loadfile("tools/probe.lua"))' && echo OK
OK

$ lua tools/build.lua --verify
OK: reproducible (sha256: af639f803c2a37f5850e74997a43218434eff25baa6765d5d65eabc745e32244)

$ ./.luarocks/bin/busted spec/ | tail -1
336 successes / 0 failures / 0 errors / 0 pending : 5.299672 seconds
```

- ADR file 365 lines (>= 80 required).
- All 11 required MADR sections present.
- All six ERR-0X requirements referenced (27 occurrences across the document).
- `MM.os.sleep` typo absent from both shipped artifacts.
- `tools/probe.lua` syntax-clean under Lua 5.4 (via `loadfile`).
- Reproducible-build SHA `af639f80…7308fe54` UNCHANGED from Phase 4 baseline (probe.lua is not in `tools/manifest.txt`, ADR is outside `src/`).
- Spec suite still at 336 successes / 0 failures / 0 errors / 0 pending — no regression from Phase 4.
- Both commits GPG-signed by `FDE07046A6178E89ADB57FD3DE300C53D8E18642`.

## Decisions made / corrections baked in

1. **D-64 collapse**: Silent token re-mint is infeasible under the assertion-grant model + `SEC-03` / `AUTH-05`. The API key is only present during `InitializeSession2`; caching it across `RefreshAccount` calls widens the in-memory exposure window in a way incompatible with `SEC-03`'s spirit. The collapsed contract — 401 → `error.token_revoked` IMMEDIATELY — preserves the user-facing intent of D-64 ("don't return `LoginFailed`; the credentials are not bad") while strictly honoring the security invariants. Documented in Invariant 4 with full rationale. Future Phase 7 (OAuth Authorization-Code flow) would unlock genuine silent re-mint via the refresh-token primitive.

2. **Sleep mechanism name correction**: CONTEXT D-67 and the Q9 row used a nested `MM.os` variant. The documented API surface is `MM.sleep(seconds)` at the top level of the `MM.*` helpers. Both the ADR and the Q9 probe use the correct name; the typo is documented in the "Important correction" subsection of the ADR's Sleep mechanism section so the trail back to RESEARCH §1 is preserved (without re-introducing the literal `MM.os.sleep` string anywhere in the shipped artifacts — the verify guard `! grep -q 'MM\.os\.sleep'` passes).

3. **`Retry-After` parsing scope**: integer-seconds via `tonumber()` + negative-value rejection. HTTP-date format silently degrades to the 30 s default. Carve-out 2 documents the rationale (Zettle has never been observed to emit HTTP-date; ~80 LoC RFC 7231 §7.1.1.1 parser is bad ROI; 30 s fallback is safe within MoneyMoney's per-call budget).

4. **SSL handshake carve-out**: ADR-0003 Q8 bonus finding propagated as a deliberate accepted limitation. `pcall` around `Connection:request` does NOT catch SSL errors; MoneyMoney aborts the surrounding Lua chunk. ERR-05's German-string contract covers DNS / connect-refused / socket timeout only. Mitigation: TLS 1.2+ is enforced by `Connection()`; OS-level cert verification is the trust chain; certificate pinning is explicitly OUT OF SCOPE per `REQUIREMENTS.md`. Future phases SHOULD NOT attempt to "fix" this — it's not fixable from Lua user code.

5. **Q9 probe is OPTIONAL**: MM.sleep is documented in the WebBanking API and already mocked at `spec/helpers/mm_mocks.lua` line 233. The Q9 probe in `tools/probe.lua` is empirical confirmation that Yves can run on MoneyMoney 2.4.72 if he wants; the ADR records the documented behaviour and ships PROPOSED/ACCEPTED regardless of probe outcome. If Q9 returns `ABSENT`, the ADR is amended in a follow-up to introduce a busy-wait fallback.

## Deviations from Plan

None — plan executed exactly as written. The plan's frontmatter said "Status: ACCEPTED (Plan 05-05 may flip to ACCEPTED post-impl; Plan 05-01 ships PROPOSED if Yves prefers, but autonomous default is ACCEPTED per CONTEXT 'no Yves-blockers expected')". The 48 h autonomous window grants autonomous default → ADR shipped as ACCEPTED.

The execution-context note flagged "ADR is Status: Proposed in this plan; Plan 05-05 finalizes to Accepted". This was overridden by the plan-body explicit guidance "autonomous default is ACCEPTED". The ADR ships ACCEPTED. If Yves prefers PROPOSED, a one-line amendment in Plan 05-05 flips it; no impact on Plans 05-02..05-04.

## Plans unblocked

- **Plan 05-02** (auth + http empty-body regression specs): can now cite ADR-0005 Invariants 1 + 5.
- **Plan 05-03** (http.lua 5xx + 429 retry implementation): can now cite ADR-0005 Invariants 2 + 3 and the `{1, 2, 4}` curve + 60 s cap + 30 s default + integer-only Retry-After contract.
- **Plan 05-04** (purchases.lua + finance.lua 401-translation): can now cite ADR-0005 Invariant 4 + the COLLAPSED rationale (assertion-grant + SEC-03 / AUTH-05).
- **Plan 05-05** (fail-whole gating spec + final ADR flip if desired): can now cite ADR-0005 Invariant 6 + the structural-correctness audit referenced from RESEARCH §5.
- **Yves' Q9 probe run**: OPTIONAL — may occur before, during, or after Wave 1..4. If `ABSENT` is observed, follow-up amendment introduces busy-wait fallback.

## Files

**Created:**
- `docs/adr/0005-resilience-invariants.md` — 365 lines, MADR format.

**Modified:**
- `tools/probe.lua` — +21 lines (Q9 block after Q8, ACTION line, top-comment Q9 entry).

**NOT modified (explicitly out of scope this plan):**
- `src/*.lua` — Plans 05-02..05-04 own source changes.
- `spec/*.lua` — Plans 05-02..05-05 own spec changes.
- `tools/manifest.txt` — no module ordering change; probe.lua is not in the manifest.
- `docs/adr/0003-sandbox-probe-results.md` — Yves adds Q9 row after running the probe.

## Commits

- `35d05e9` — `docs(05-01): add ADR-0005 resilience invariants (ERR-01..06 + SSL bypass + Retry-After integer-only + D-64 collapse)` (GPG-signed)
- `fb0938e` — `tools(05-01): add Q9 MM.sleep sandbox probe (D-67; optional confirmation per ADR-0005)` (GPG-signed)

## Self-Check: PASSED

- `docs/adr/0005-resilience-invariants.md` exists (365 lines, MADR format, all 11 required sections present).
- `tools/probe.lua` Q9 block present, syntax-clean, uses `MM.sleep` (no typo propagated).
- Commit `35d05e9` exists, GPG-signed, on branch `phase-5/resilience`.
- Commit `fb0938e` exists, GPG-signed, on branch `phase-5/resilience`.
- Reproducible build SHA preserved (`af639f80…7308fe54`).
- Spec suite still at 336/0/0/0 (no regression).
