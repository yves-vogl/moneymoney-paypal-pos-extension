---
phase: 04-enrichment-refunds-fees-payouts
plan: "06"
subsystem: release-polish
tags: [wave-5, release, docs, adr, audit, ci, human-checkpoint, mvp]
dependency_graph:
  requires: [04-02, 04-03, 04-04, 04-05]
  provides:
    - "ADR-0004 — Finance API scope requirement + D-49 Option B trade-off + temporal payout inference (ACCEPTED 2026-06-21)"
    - "CHANGELOG.md [0.2.0] section (German, engineering-draft; lektor-review pending as Yves checkpoint)"
    - "README.md three new German sections: Was die Extension jetzt kann / Was die Extension nicht macht / Inbetriebnahme bei bestehendem v0.1.0 API-Key"
    - "Phase-3 surface preservation audit: spec/phase3_surface_preservation_spec.lua (11 it() blocks; behavioural + source-tree contract checks for all 4 frozen callbacks)"
    - "SEC-02 egress allowlist: confirmed finance.izettle.com already present in .github/workflows/ci.yml line 87 (no commit needed)"
  affects: []
tech_stack:
  added: []
  patterns:
    - "MADR-format ADR mirroring docs/adr/0001 shape (Status / Date / Deciders / Context / Decision / Consequences / References)"
    - "Surface preservation audit pattern: behavioural fixture-driven assertions + source-tree substring checks for frozen function bodies — catches BOTH a behavioural regression (callback returns different value) AND a source rewrite that happens to preserve behaviour but loses byte-identity"
    - "lektor-review HTML-comment marker in user-facing docs flagging engineering placeholder for a future polish pass"
    - "v0.2.0 CHANGELOG section consolidates prior Unreleased Phase-1/2/3 foundations under a 'Foundations' subsection — v0.2.0 is the first cut release (v0.1.0 was planned but never tagged)"
key_files:
  created:
    - docs/adr/0004-finance-api-scope-and-fee-fallback.md
    - spec/phase3_surface_preservation_spec.lua
    - .planning/phases/04-enrichment-refunds-fees-payouts/04-06-SUMMARY.md
  modified:
    - CHANGELOG.md
    - README.md
  deleted: []
decisions:
  - "Plan-04-01 (Q3 live probe) verdict still pending Yves' sandbox key — ADR-0004 is therefore informative-priority, not CRITICAL-PRIORITY; if Yves' key turns out to lack READ:FINANCE on Phase 4 first refresh, the README 'Inbetriebnahme bei bestehendem v0.1.0 API-Key' section becomes load-bearing"
  - "CI egress allowlist (Task 1) was a no-op: finance.izettle.com was already added in commit ec64b19 (Phase-2 deferred LOW-severity findings) per the existing .github/workflows/ci.yml line 87 — no new commit needed; the artifact-host scan returns only the 3 allowed hosts (oauth.zettle.com, purchase.izettle.com, finance.izettle.com)"
  - "Surface preservation audit added BOTH behavioural assertions (matches the Phase-3 baseline outputs for SupportsBank/InitializeSession2/ListAccounts/EndSession via fixture-driven invocation) AND source-tree byte-substring assertions (catches a hypothetical regression where the source body is rewritten but the behavioural contract happens to hold); the duplication is intentional defence-in-depth, mirroring Plan 04-05's META-02 spec duplication pattern"
  - "lektor pass marked TBD-Yves per orchestrator instructions: do NOT auto-invoke loop-lektor agent; the engineering-draft German wording lives behind an HTML <!-- lektor-review: pending --> marker in both CHANGELOG.md and README.md; final polish is a Yves checkpoint after merge (Plan 04-06 Task 4 'human-action' deferred)"
  - "META-03 forbidden-phrase grep clean across all three user-facing docs (CHANGELOG.md, README.md, docs/adr/0004); wording uses 'steuerrechtliche Bewertung' + 'GoBD-Bewertung' which contain none of the 13 D-55 substrings"
  - "CHANGELOG.md restructured: the prior Unreleased section (which described Phase 1/2/3 scaffolding) is consolidated under the new [0.2.0] section as 'Foundations (previously tracked under Unreleased)' — v0.2.0 is the first cut release because v0.1.0 was planned but never tagged"
metrics:
  duration: "~30 minutes"
  completed: "2026-06-21"
  tasks_completed: 4
  files_created: 3
  files_modified: 2
  files_deleted: 0
  commits: 3
---

# Phase 04 Plan 06: Wave-5 Release Polish + Audit Summary

Wave-5 closes Phase 4 with the release-polish + audit deliverables that turn the working extension into a publishable `v0.2.0`. ADR-0004 (Finance API scope + fee-fallback contract + temporal payout inference) is ACCEPTED. CHANGELOG.md gains a German `[0.2.0]` section with engineering-draft wording (lektor pass deferred to a Yves checkpoint after merge). README.md gains three new German sections covering capability surface, non-claims, and the v0.1.0→v0.2.0 API-key re-mint path. The Phase-3 surface preservation audit spec (`spec/phase3_surface_preservation_spec.lua`) asserts via both behavioural fixture replay and source-tree byte-substring checks that all four Phase-2 callbacks frozen by Phase-3 (SupportsBank, InitializeSession2, ListAccounts, EndSession) survived Plan 04-03's RefreshAccount extension untouched.

Full suite: **328 successes / 0 failures / 0 errors / 0 pending** (Plan 04-05 baseline 317 → +11 for the new surface-preservation spec). `luacheck .` reports `0 warnings / 0 errors in 38 files`. `lua tools/build.lua --verify` reports `OK: reproducible (sha256: d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712)` — unchanged from Plan 04-05 because this plan is docs + spec only, no `src/*.lua` touched.

## What Was Built

### Task 1 — CI egress allowlist (SEC-02): no-op (already in place)

The orchestrator brief mandated extending the allowlist regex to include `finance.izettle.com`. Inspection of `.github/workflows/ci.yml` showed the host was already present on **line 87** since commit `ec64b19` (Phase-2 deferred LOW-severity findings, predates Phase 4):

```yaml
| grep -v 'oauth\.zettle\.com\|purchase\.izettle\.com\|finance\.izettle\.com' \
```

No new commit required. Verified the artifact-host scan returns only the three allowed hosts:

```
$ grep -oE 'https?://[a-z0-9.-]+/' dist/paypal-pos.lua | sort -u
https://finance.izettle.com/v2/accounts/liquid/balance
https://finance.izettle.com/v2/accounts/liquid/transactions
https://finance.izettle.com/v2/accounts/liquid/transactions?
https://finance.izettle.com/v2/accounts/preliminary/balance
https://oauth.zettle.com
https://oauth.zettle.com/token
https://oauth.zettle.com/users/self
https://purchase.izettle.com/purchases/v2?
```

The `BAD=` invert-grep used by CI returns empty — gate passes.

### Task 2a — docs/adr/0004-finance-api-scope-and-fee-fallback.md (NEW, ACCEPTED)

202-line MADR-format ADR mirroring `docs/adr/0001-amalgamator-design.md` structure. Status ACCEPTED 2026-06-21; Deciders: Yves Vogl.

Three concerns documented:

1. **OAuth scope requirement** — `READ:PURCHASE` + `READ:FINANCE`; v0.1.0 user-side re-mint flow via `https://my.zettle.com/apps/api-keys?scopes=READ:PURCHASE+READ:FINANCE` with a remove + re-add in MoneyMoney. The extension surfaces a generic `LoginFailed` on 401 today; a future Phase 5/6 may add a scope-specific German error string.

2. **Fee-fallback dedup contract (D-49 Option B chosen)** — per-refresh Berlin-local-date clustering. When any fee on a date is unlinked, all fees on that date aggregate into `zettle:fee:aggregate:<YYYY-MM-DD>`. When all fees on a date resolve, per-sale `zettle:fee:<originatingTransactionUuid>` rows emit. Trade-off accepted: linkage-upgrade-between-refreshes can double-book a single date's fees; README documents this and the manual delete remediation.

3. **Temporal payout inference (RESEARCH §4.2)** — settlement is "earliest PAYOUT whose timestamp ≥ PAYMENT.timestamp". Conservative-miss behaviour (no false positives); 1-2 refresh-cycle delay for weekly/monthly payout periodicities. FROZEN_FUNDS / ADJUSTMENT carve-outs are NOT modelled (out of Phase-4 `includeTransactionType` filter scope).

Grep verification:
- `grep -c 'READ:FINANCE'` reports 6 (Context + Decision Concern 1 + References).
- `grep -c 'Option B'` reports 3 (Context + Decision + Consequences).
- `grep -c 'temporal'` reports 3 (Context + Decision Concern 3 + References).
- `grep -c 'ACCEPTED'` reports 1 (Status).

### Task 2b — spec/phase3_surface_preservation_spec.lua (NEW, GREEN)

216-line spec with 11 `it()` blocks across one describe. Two assertion strategies:

**Behavioural (10 it() blocks):**

| # | Callback | Input | Expected output |
|---|---|---|---|
| 1 | SupportsBank | ProtocolWebBanking + "PayPal POS" | true |
| 2 | SupportsBank | ProtocolFinTS + "PayPal POS" | false |
| 3 | SupportsBank | ProtocolWebBanking + "Some Other Bank" | false |
| 4 | InitializeSession2 | nil credentials | challenge object (title/challenge/label all = German API-Key label) |
| 5 | InitializeSession2 | valid JWT + token_ok + users_self_ok fixtures | nil; LocalStorage.zettle written under org UUID b2c3d4e5-... |
| 6 | InitializeSession2 | valid JWT + token_invalid_grant fixture | LoginFailed (MoneyMoney built-in); LocalStorage unchanged |
| 7 | InitializeSession2 | malformed JWT | non-empty error string; zero network calls (Mocks._last_request == nil) |
| 8 | ListAccounts | empty cache | single-element fixture array (accountNumber="paypal-pos-fixture-001", AccountTypeGiro, "EUR", portfolio=false) |
| 9 | ListAccounts | cache populated via two-call probe | single record (accountNumber=b2c3d4e5-..., AccountTypeGiro, "EUR", portfolio=false, name contains "Beispiel") |
| 10 | EndSession | — | nil |

**Source-tree (1 it() block):** reads `src/entry.lua` and asserts byte-substring presence of:
- the full SupportsBank function body (single-line predicate + closing `end`),
- the InitializeSession2 signature line + the three-line challenge object,
- the ListAccounts signature line + the `accountNumber = "paypal-pos-fixture-001"` literal,
- the full four-line EndSession body.

Defence-in-depth rationale: catches a hypothetical regression where the source body is rewritten in a way that preserves the behavioural contract but loses byte-identity (e.g., a refactor that inlines `M_i18n.t` calls); mirrors Plan 04-05's META-02 spec-duplication pattern.

### Task 3 — CHANGELOG.md + README.md v0.2.0 sections (German, engineering draft)

**CHANGELOG.md `[0.2.0]` section (5 subsections per RESEARCH §11.1):**

- **Hinzugefügt** — full bookkeeping view (payouts, fees, VAT split, settled vs pending balance, refund-to-receipt linkage, per-card metadata, per-rate VAT for mixed-rate businesses).
- **Geändert** — `balance` / `pendingBalance` semantics; `valueDate`-on-payout promotion via temporal inference.
- **Voraussetzung für Bestandskunden** — READ:FINANCE scope upgrade path with the `my.zettle.com` URL pre-selecting both scopes.
- **Bekannte Grenzen** — monthly/weekly payout periodicity delay (1-2 refresh cycles), D-49 Option B fee aggregate-then-per-sale double-booking failure mode, 90-day initial-sync clamp, non-EUR silent skip.
- **Sicherheit** — META-03 non-claims (no `steuerrechtliche Bewertung`, no `GoBD-Bewertung`) + egress allowlist + Bearer redaction reiteration.

Also: the prior `[Unreleased]` section (containing Phase 1/2/3 scaffolding bullets) was consolidated under `[0.2.0]` as a `Foundations (previously tracked under Unreleased — Phase 1 + 2 + 3 scaffolding)` subsection. `v0.2.0` is the first cut release because `v0.1.0` was planned but never tagged. Compare-URL footer updated to point at the v0.2.0 tag.

**README.md three new German sections (per RESEARCH §11.2):**

- **"Was die Extension jetzt kann"** — bullet list mirroring CHANGELOG Hinzugefügt.
- **"Was die Extension nicht macht"** — META-03 non-claims surface (`keine steuerrechtliche Bewertung`, `keine GoBD-Bewertung`, `keine USt-Voranmeldung`, `kein Steuerberater-Ersatz`).
- **"Inbetriebnahme bei bestehendem v0.1.0 API-Key"** — step-by-step R-1 mitigation with the scoped `my.zettle.com` URL and the remove + re-add flow in MoneyMoney.

Both files carry an HTML comment `<!-- lektor-review: pending -->` flagging that a final lektor pass is queued as a Yves checkpoint after merge (per Task 4 below).

### Task 4 — Lektor pass (DEFERRED to Yves checkpoint, per orchestrator instructions)

Per the orchestrator brief: "do not invoke loop-lektor agent — leave that as a Yves checkpoint after merge." The engineering-draft wording in CHANGELOG.md, README.md, and the user-facing narrative paragraphs of ADR-0004 is intentionally engineer-German rather than professional bookkeeping-German. A future lektor pass (Yves or `loop-lektor` invocation, post-merge) can refine: sentence rhythm, Steuerberater register alignment, Anglizismen removal, final META-03 forbidden-phrase recheck. The `<!-- lektor-review: pending -->` HTML markers in both files signal the entry points.

Task 4 disposition: **defer lektor** (Yves checkpoint after merge).

## Tasks Completed

| # | Task | Disposition | Commit |
|---|---|---|---|
| 1 | CI egress allowlist (SEC-02): include finance.izettle.com | NO-OP (already present in ci.yml line 87 since commit ec64b19) | — |
| 2a | ADR-0004 Finance API scope + fee-fallback contract | ACCEPTED | `61ed67f` |
| 2b | spec/phase3_surface_preservation_spec.lua audit | GREEN (11 it() blocks; behavioural + source-tree) | `ec077d9` |
| 3 | CHANGELOG.md + README.md v0.2.0 German sections | engineering draft (META-03 forbidden-phrase clean) | `16a06de` |
| 4 | Lektor pass | DEFERRED to Yves checkpoint post-merge | — |

All three landing commits GPG-signed (G) by `FDE07046A6178E89ADB57FD3DE300C53D8E18642`; Conventional Commits prefixes `docs(04-06):` ×2 + `test(04-06):` ×1; zero AI-attribution patterns in the diff (`git grep -nE 'Co-Authored-By:[[:space:]]*Claude|Generated with Claude|🤖' -- . ':!.planning' ':!CLAUDE.md' ':!.github/'` returns empty).

## Test Count

| Phase | Suite count |
|---|---|
| Plan 04-05 baseline | 317 / 0 / 0 / 0 |
| Plan 04-06 additions | +11 (phase3 surface preservation: 11) |
| **Phase-4 cumulative after Plan 04-06** | **328 / 0 / 0 / 0** |

`./.luarocks/bin/busted spec/` → `328 successes / 0 failures / 0 errors / 0 pending`. Runtime ~4.8s on the maintainer's machine.

## Coverage (src/)

Coverage measurement was not re-executed in this plan because Plan 04-06 is documentation + spec only — no `src/*.lua` was modified. Plan 04-05 noted Phase-3 baseline 99.23%; the Wave-1..4 src/ additions (M_pagination.offset_iterate, M_finance.fetch/fetch_all/fetch_account_state/parse_transaction, 4 mapping mappers, per-rate VAT, card tail, RefreshAccount extension) are exercised by the 317-baseline test suite. A full coverage re-measurement is recommended at the Phase-4 verifier step (separate from Plan 04-06).

## Reproducible Build

```
$ lua tools/build.lua --verify
OK: reproducible (sha256: d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712)
```

SHA unchanged from Plan 04-05 (no src/ delta in this plan).

## Phase-3 Surface Preservation Audit Result

`git diff a201f6c -- src/entry.lua` shows:
- Lines 10-12 **SupportsBank**: byte-identical to Phase-3 baseline.
- Lines 14-94 **InitializeSession2**: byte-identical to Phase-3 baseline.
- Lines 96-132 **ListAccounts**: byte-identical to Phase-3 baseline.
- Lines 134-371 **RefreshAccount**: intentionally extended by Plan 04-03 (Phase-3 lines 174-200 replaced by Phase-4 lines 174-371 = +220 lines net for Finance API wiring, cross-refresh indexes, SALE-03 promotion, D-49 Option B, payout mapping). This is the **only** intended Phase-4 delta in `src/entry.lua`.
- Lines 373-377 **EndSession**: byte-identical to Phase-3 baseline.

The new `spec/phase3_surface_preservation_spec.lua` automates this assertion for the four frozen callbacks (behavioural + source-tree). All 11 `it()` blocks PASS.

## Deviations from Plan

### Rule-3-equivalent (Task 1 already done)

**Task 1 was already complete before plan execution started.** The orchestrator brief instructed to add `finance.izettle.com` to the egress allowlist, but grep of `.github/workflows/ci.yml` showed the host already present (line 87). Tracked as a no-op task; no Rule-1/2/3 deviation needed because nothing was bugged or missing — the work was simply already done in a prior commit (`ec64b19`, Phase-2 deferred LOW-severity findings).

### CHANGELOG.md structure consolidation (Rule-2 scope expansion)

**Found during Task 3.** The pre-existing `## [Unreleased]` section in CHANGELOG.md contained an extensive list of Phase 1/2/3 scaffolding bullets. Per Keep-a-Changelog convention, `[Unreleased]` should hold future-not-yet-released changes; the existing Phase 1/2/3 content described work that is **part of** v0.2.0 (because v0.1.0 was planned but never tagged). Consolidated under the new `## [0.2.0]` section as a `Foundations (previously tracked under Unreleased)` subsection rather than creating a separate `[0.1.0]` section that never had a tag. Footer compare-link updated to `v0.2.0`.

This was outside the strict Task 3 brief (which said "extend with v0.2.0 entry") but is necessary to avoid the changelog file becoming structurally invalid (two `## [Unreleased]` headers). Treated as Rule-2 (essential structural correctness).

### Task 4 lektor disposition

Task 4 is a `checkpoint:human-action` per the plan, but the orchestrator brief explicitly overrode this: "do not invoke loop-lektor agent — leave that as a Yves checkpoint after merge." Disposition: **defer lektor**. Both CHANGELOG.md and README.md carry an HTML comment `<!-- lektor-review: pending -->` so the future polish pass has a clear entry point. SUMMARY records this above; no further action in this plan.

## Authentication Gates

None. All work is local — no network, no MoneyMoney credential UI, no Zettle API interaction.

## Known Stubs

None. The CHANGELOG date placeholder `2026-MM-DD` is intentional (the release date is set when the tag is cut; the date-of-cut is the merge-and-release step, not a documentation step).

## Threat Surface Scan

No new attack surface. Threat register entries from PLAN.md:
- **T-04-W5-01** (Tampering — CI egress allowlist): `mitigate` — verified clean (no unexpected hosts; gate is closed alternation of 3 hosts).
- **T-04-W5-02** (Information Disclosure — README/CHANGELOG wording): `mitigate` — META-03 forbidden-phrase grep clean across all three user-facing docs.
- **T-04-W5-03** (Tampering — surface preservation audit): `mitigate` — spec GREEN, byte-identity confirmed for all four frozen callbacks.
- **T-04-W5-04** (Info Disclosure — ADR documents scope requirement publicly): `accept` — public Zettle knowledge per `iZettle/api-documentation/authorization.md`.
- **T-04-W5-SC** (npm/luarocks installs): `accept` — zero installs in this plan.

No `threat_flag:` entries to surface.

## Yves-Blocker Status (Phase-4 cumulative)

| Blocker | Source | Surfaced in | Final Disposition |
|---|---|---|---|
| Q3 (PRD-vs-CONTEXT scope drift; sandbox-probe verdict) | Phase-4 kickoff | Plan 04-01 | **PENDING Yves' live probe.** ADR-0003 Q3 row still DEFERRED; ADR-0004 documents both possible outcomes (informative if Yves' key has READ:FINANCE; load-bearing user-facing guidance if not). |
| D-49 Option A vs B | RESEARCH §3.5 | Plan 04-03 preamble | **RESOLVED 2026-06-21**: Option B (per-refresh date clustering, no persistent state). Documented in ADR-0004 Concern 2 + README "Bekannte Grenzen". |
| D-55 (META-03 forbidden phrase list) | CONTEXT D-55 | Plan 04-05 preamble | **RESOLVED 2026-06-21**: 13-phrase list LOCKED. Gating spec `spec/meta_no_tax_classification_spec.lua` enforces; user-facing docs in this plan also clean by manual grep. |

**Phase 4 implementation is COMPLETE; READY-FOR-VERIFIER.** Q3 remains the one open Yves-blocker; it does not block the verifier step (the verifier validates artifact correctness against the Phase-4 acceptance gates, which are independent of the scope-probe verdict — the scope-probe only changes the README upgrade-path section's priority from "advisory" to "load-bearing").

## Phase-4 Requirement Coverage (cumulative, all plans)

Mapping of CONTEXT/REQUIREMENTS IDs to the Plan that delivered them:

| Requirement | Delivered by | Notes |
|---|---|---|
| ACCT-03 (balance + pendingBalance from Finance API) | Plan 04-03 | M_finance.fetch_account_state + RefreshAccount Step 7 |
| REF-01 (refund as separate transaction) | Plan 04-02 + 04-03 | M_mapping.refund_to_transaction + RefreshAccount Step 12 |
| REF-02 (refund cites original Belegnummer) | Plan 04-03 | purchases_by_uuid lookup + opts.original_receipt |
| REF-03 (refund prefix gating) | Plan 04-05 | D-38 extended prefix gate (zettle:refund:) |
| FEE-01 (per-sale fee linkage) | Plan 04-03 | payments_by_uuid + M_mapping.fee_to_transaction; gated by D-58 case 3 (Plan 04-05) |
| FEE-02 (fee linked to originating sale) | Plan 04-03 + 04-05 | fee_to_transaction(fee, originating); D-38 prefix gate |
| FEE-03 (aggregate fallback when unlinked) | Plan 04-03 (Option B impl) + 04-05 (D-58 case 4 gate) | fees_by_date clustering; ADR-0004 documents trade-off |
| PAYOUT-01 (payouts as separate negatives) | Plan 04-03 | M_mapping.payout_to_transaction + RefreshAccount Step 15 |
| PAYOUT-02 (SALE-03 promotion via temporal inference) | Plan 04-03 | _find_covering_payout + promote_to_booked; gated by D-58 case 1 |
| PAYOUT-03 (payout-only refresh stability) | Plan 04-05 | D-58 case 2 idempotency assertion |
| META-01 (zero-rate VAT suppression) | Plan 04-04 (impl already correct) + 04-05 (gate) | _format_purpose `#rate_entries >= 2` guard; meta_purpose_lines_spec |
| META-02 (zero-tip line suppression) | Plan 04-04 + 04-05 | _format_purpose Trinkgeld guard; meta_purpose_lines_spec |
| META-03 (no tax-classification claims) | Plan 04-05 | 13-phrase invariant spec; this plan extends maintainer discipline to user-facing docs |
| SALE-07 (card tail in purpose) | Plan 04-04 | _format_purpose card brand + entry-mode tail |
| TEST-02 (negative-list regression gate) | Plan 04-05 | meta_no_tax_classification_spec |

## Hand-off Notes for Verifier + Reviewer + Ship

### For the Phase-4 verifier

Phase 4 implementation is **COMPLETE / READY-FOR-VERIFIER**. The verifier should:

1. Re-run the full gate locally:
   - `./.luarocks/bin/busted spec/` → expect `328 successes / 0 failures / 0 errors / 0 pending`.
   - `./.luarocks/bin/luacheck .` → expect clean (`0 warnings / 0 errors in 38 files`).
   - `lua tools/build.lua --verify` → expect `OK: reproducible (sha256: d6356d5bef63708e49707587d5079c4ece7cd863057f693a18ddd09dd79f1712)`.
   - `busted --coverage spec/` + `luacov` → coverage on `src/` modules (recommend ≥ 95% on Wave-1/2/3 src/ additions; Phase-3 baseline 99.23%).
2. Confirm the 5 CI gates pass on the branch (push triggers `.github/workflows/ci.yml`):
   - luacheck, busted, coverage 85%, reproducible-build, DEBUG=false, egress allowlist (3 hosts), no-AI-attribution.
3. Confirm the OpenSSF Scorecard workflow remains green (no new dependencies in this phase, score should be stable).
4. Spot-check that ADR-0004 is correctly numbered and follows MADR shape; that the v0.2.0 CHANGELOG section is structurally valid Keep-a-Changelog; that README new sections render correctly in GitHub.
5. Confirm the surface preservation audit spec catches a deliberate break (manual smoke: change one byte in src/entry.lua SupportsBank, re-run, expect failure with descriptive message — then revert).

### For the Phase-4 reviewer (loop-security-engineer + loop-qa)

- **loop-security-engineer** — review Phase 4 src/ additions (M_finance, RefreshAccount extension) against SEC-03 (Bearer redaction) and the threat register from PLAN.md ×5 Wave plans. All Phase-4 spec files (`spec/refresh_log_redaction_spec.lua` extended in Plan 04-05) gate redaction across Finance API call paths.
- **loop-qa** — review the META-03 forbidden-phrase list completeness in user-facing docs; verify the v0.2.0 release notes are technically accurate.

### For ship

Once verifier + reviewers approve:
1. **Lektor pass** (Yves manual or loop-lektor invocation) on CHANGELOG.md `[0.2.0]` + README.md three new sections + ADR-0004 narrative paragraphs. Replace `<!-- lektor-review: pending -->` markers with `<!-- lektor-review: 2026-MM-DD approved -->` on completion.
2. **Yves Q3 sandbox probe** (Plan 04-01 outstanding task). Outcome determines whether ADR-0004 is informative or load-bearing; updates ADR-0003 Q3 row from DEFERRED to ACCEPTED.
3. **Date stamp** — replace `2026-MM-DD` in CHANGELOG.md `[0.2.0]` header with the actual release date.
4. **Open PR** for `phase-4/enrichment` → `main`. Per `feedback_gpg_signed_pr_merge` use `--squash` (not `--rebase`). PR description references this SUMMARY + all 5 plan SUMMARYs.
5. **Tag** `v0.2.0` (GPG-signed via `git tag -s v0.2.0`) at the merge commit; push to remote.
6. **GitHub Release** auto-created by `softprops/action-gh-release@v2` from the tag — attaches `dist/paypal-pos.lua` + `Extension.lua.sha256` + `.asc` signature.

The autonomous-window deadline (~2026-06-22 03:30 UTC per `project_48h_autonomous_window`) likely overlaps with the verifier + reviewer + ship steps; expect those to be Yves-driven manual operations rather than further autonomous Plan execution.

## Self-Check: PASSED

| Artifact | Status |
|---|---|
| docs/adr/0004-finance-api-scope-and-fee-fallback.md | FOUND |
| spec/phase3_surface_preservation_spec.lua | FOUND |
| CHANGELOG.md [0.2.0] section | FOUND (5 subsections: Hinzugefügt / Geändert / Voraussetzung / Bekannte Grenzen / Sicherheit) |
| README.md "Was die Extension jetzt kann" | FOUND |
| README.md "Was die Extension nicht macht" | FOUND |
| README.md "Inbetriebnahme bei bestehendem v0.1.0 API-Key" | FOUND |
| Commit 61ed67f (docs(04-06): ADR-0004) | FOUND (GPG-signed G) |
| Commit ec077d9 (test(04-06): surface preservation) | FOUND (GPG-signed G) |
| Commit 16a06de (docs(04-06): CHANGELOG + README) | FOUND (GPG-signed G) |
| busted spec/ | 328 / 0 / 0 / 0 |
| luacheck . | 0 warnings / 0 errors in 38 files |
| lua tools/build.lua --verify | OK: reproducible (sha256 d6356d5b...) |
| META-03 forbidden-phrase grep across CHANGELOG.md, README.md, docs/adr/0004 | clean |
| CI egress allowlist host scan against dist/paypal-pos.lua | clean (only 3 allowed hosts) |
| No AI-attribution in tracked files (excluding .planning/, CLAUDE.md, .github/) | clean |
