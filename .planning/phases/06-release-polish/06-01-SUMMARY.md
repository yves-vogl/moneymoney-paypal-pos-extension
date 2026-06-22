---
phase: 06-release-polish
plan: 01
subsystem: build-pipeline + ci-gates
tags: [wave-1, build, ci, gitleaks, commit-lint, meta-03, tdd, mvp, build-03, doc-04, ci-05, d-78, d-79]
requires:
  - Phase-5 baseline (373 specs, reproducible SHA 5dbcb8ea...)
  - phase-6/release-polish branch from main
provides:
  - BUILD-03 __VERSION__ substitution from $GITHUB_REF_NAME (tools/build.lua + src/webbanking_header.lua)
  - META-03 walker extended to documentation markdown (Phase-4 src/dist gate preserved)
  - CI gates: gitleaks secret-scan, commit-lint, D-79 raw-print() grep
  - Pitfall-3 DEV BUILD banner for dev builds
  - Pitfall-5 .gitleaksignore allowlist (21 audited false-positive fingerprints)
  - Pitfall-6 audit-before-extend discipline applied to META-03 doc extension
  - Three new CI check names for 06-02 branch-protection CHECKS array
affects:
  - tools/build.lua (resolve_version_string + version_to_number_string + VERSION_NUMBER + gsub + DEV banner)
  - src/webbanking_header.lua (line 24: version = 0.00 -> version = __VERSION__)
  - src/log.lua (line 61: + D-79-allowed sentinel comment)
  - .luacheckrc (globals[] += __VERSION__)
  - .gitleaksignore (new — 21 fingerprints)
  - .github/workflows/ci.yml (+ D-79 step inside test job; + secret-scan job)
  - .github/workflows/commit-lint.yml (new)
  - spec/build_version_substitution_spec.lua (new — 7 it() cases)
  - spec/meta_no_tax_classification_spec.lua (+ DOC_TARGETS + 3rd it() block)
tech-stack:
  added:
    - gitleaks/gitleaks-action@v2 (CI-only, official organisation, OpenSSF-recommended)
    - shell-only Conventional Commits regex (no Node/husky toolchain)
  patterns:
    - Lua-side __VERSION__ substitution (Pitfall 3 DEV banner via VERSION_NUMBER == "0.00" branch)
    - Per-fingerprint .gitleaksignore (never blanket paths allowlist)
    - Inline sentinel comment for D-79 grep exclusion (M_log canonical emission point only)
key-files:
  created:
    - spec/build_version_substitution_spec.lua
    - .github/workflows/commit-lint.yml
    - .gitleaksignore
  modified:
    - tools/build.lua
    - src/webbanking_header.lua
    - src/log.lua
    - .luacheckrc
    - .github/workflows/ci.yml
    - spec/meta_no_tax_classification_spec.lua
decisions:
  - "MoneyMoney decimal-fraction minor formatting — v1.2.3 -> 1.20 (not 1.02): treat minor as decimal-fraction (one digit gets trailing zero pad)"
  - "DEV BUILD banner on line 2 only when VERSION_NUMBER == '0.00' (substitution-derived, not env-derived; covers both unset env and env-with-non-matching-shape)"
  - "D-79 grep exclusion via inline sentinel comment '-- D-79-allowed: M_log emission point' (single load-bearing line in src/log.lua); avoids restructuring M_log's terminal print() path"
  - "Per-fingerprint .gitleaksignore (21 entries) instead of blanket paths allowlist — preserves leak detection in same files for any new code"
  - "Tagged-build SHA recomputation accepted as expected delta from Phase 5 (header bytes change by design)"
metrics:
  duration: "~10 minutes"
  completed: "2026-06-22"
  tasks_completed: 4
  commits: 5
  files_created: 3
  files_modified: 6
  busted_baseline: "373/0/0/0"
  busted_after: "381/0/0/0 (+8 new cases)"
  luacheck: "clean (41 files, 0 warnings, 0 errors)"
  reproducible_sha_phase5_baseline: "5dbcb8ea97ae2fb2b675442439ac93b342893e84b9e7849b29df07e9612b777e"
  reproducible_sha_dev_build_post_06_01: "4526a33fceab55122a6e624207c03cf76545939685825c3072c9d9001653304c"
  reproducible_sha_tagged_v1_0_0: "d1afc595edc528db6719b826a084765719a7f249cb3b8a53cf1c6dd2790c8d36"
---

# Phase 6 Plan 01: Wave-1 build-pipeline + CI-gates Summary

`__VERSION__` substitution + META-03 doc walker + gitleaks/commit-lint/D-79 CI gates landed across 5 GPG-signed commits, unblocking every Wave-2 task in Phase 6.

## What landed

### BUILD-03 — `__VERSION__` substitution (D-73)

TDD-driven RED -> GREEN. The pipeline now derives the shipped `WebBanking{version}` literal from `$GITHUB_REF_NAME` (CI) -> `git describe --tags --exact-match` (local tagged) -> `dev-<short-sha>` (local untagged).

`tools/build.lua` gains:

- `resolve_version_string()` — three-tier resolution (env -> exact-match git tag -> dev-sha fallback)
- `version_to_number_string(s)` — `^v(%d+)%.(%d+)` capture mapped to MoneyMoney's decimal-fraction minor convention. `v1.2.3 -> 1.20`, `v0.10.0 -> 0.10`, non-matching -> `0.00`
- Module-scope `VERSION_NUMBER` (resolved once, avoids subshell re-spawn)
- DEV BUILD banner line on line 2 of `dist/paypal-pos.lua` when `VERSION_NUMBER == "0.00"` (Pitfall 3 mitigation)
- `HEADER_MOD` branch does `content:gsub("__VERSION__", VERSION_NUMBER)` before emission (literal token, no pattern injection, idempotent)

`src/webbanking_header.lua` line 24 flipped from `version = 0.00,` to `version = __VERSION__,` (exact 5-space gap preserved; the raw file is now Lua-syntax-invalid until built — intentional, file is never loaded directly).

`.luacheckrc` globals[] gains `__VERSION__` so luacheck does not flag the unresolved placeholder.

`spec/build_version_substitution_spec.lua` (new, 138 lines) drives 7 `it()` cases:
1. `v1.0.0 -> 1.00`
2. `v1.2.3 -> 1.20` (patch dropped, decimal-fraction minor)
3. `v0.10.0 -> 0.10`
4. `v1.0.0-rc.1 -> 1.00` (rc + patch dropped)
5. `env -u GITHUB_REF_NAME` fallback (tolerates 0.00 OR local-tag-derived numeric)
6. DEV BUILD banner appears for dev fallback, absent for tagged
7. Two consecutive `--verify` invocations at the same tag are reproducible

### META-03 walker extension (DOC-04 / Pitfall 6)

`spec/meta_no_tax_classification_spec.lua` gains `DOC_TARGETS` (static: README.md, README.de.md, CONTRIBUTING.md, CHANGELOG.md; dynamic: `ls docs/adr/*.md`) and a third `it()` block scanning every target that physically exists for the 13 D-55 forbidden phrases. Files absent at scan time (W1: README.de.md / CONTRIBUTING.md not yet authored) are skipped silently; at least one target must exist so a delete-everything regression still trips the gate.

Pre-extension audit per Pitfall 6 — `grep -nE 'USt-frei|USt frei|steuerfrei|steuerlich|GoBD-konform|GoBD konform|DATEV-fähig|DATEV fähig|VAT-exempt|VAT exempt|tax-free|tax exempt|non-taxable' README.md CHANGELOG.md docs/adr/*.md` returned zero hits. The walker now protects every Wave-2 doc author from introducing a forbidden phrase as `README.de.md`, `CONTRIBUTING.md`, and the four new ADRs land in 06-02.

The pre-existing `src/*.lua` walker and `dist/paypal-pos.lua` walker are unchanged byte-identically (Phase-4 invariant preserved).

### CI extensions (CI-05 / D-78 / D-79)

`.github/workflows/ci.yml`:
- NEW step inside the existing `test` job between the egress allowlist and the no-AI-attribution gate: D-79 raw-`print(` grep over `dist/paypal-pos.lua`. The single legitimate emission point (M_log `_emit` in `src/log.lua` line 61) carries the inline sentinel `-- D-79-allowed: M_log emission point` which the grep filter explicitly skips.
- NEW sibling job `secret-scan` (name: `gitleaks secret scan`) using `gitleaks/gitleaks-action@v2`. `yves-vogl/paypal-pos-plugin` is a personal-account repo so no `GITLEAKS_LICENSE` secret is required.

`.github/workflows/commit-lint.yml` (new): pull_request-only trigger; walks every commit in `BASE..HEAD` with the Conventional Commits regex `^(feat|fix|docs|test|refactor|chore|ci|build|perf|style|revert)(\([^)]+\))?: .+` and fails on the first non-conforming subject. Job name `Commit-message lint`.

### Pitfall mitigations

| Pitfall | Mitigation | Disposition |
|---|---|---|
| Pitfall 3 — dev-build pretending to be release | DEV BUILD banner on line 2 of `dist/paypal-pos.lua` when `VERSION_NUMBER == "0.00"` | landed in `tools/build.lua` |
| Pitfall 5 — gitleaks fixture-blocking | `.gitleaksignore` with 21 per-fingerprint entries (JWT-shaped test fixtures + planning-doc `key = purchaseUUID1` documentation strings); confirmed `gitleaks detect` clean | landed in `.gitleaksignore` |
| Pitfall 6 — META-03 walker rewrites existing committed docs | Pre-extension grep audit returned zero hits across README.md + CHANGELOG.md + docs/adr/0001/0003/0004/0005 before the spec extension landed | confirmed clean; spec landed |

### Local gitleaks dry-run disposition

`gitleaks/gitleaks-action@v2` (version 8.30.1 locally) scanned 318 commits / 6.78 MB and found 21 leaks, ALL audited as false positives:

- 11 fingerprints in `spec/auth_spec.lua` + `spec/entry_spec.lua` — JWT-shaped test fixtures (`hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig` is a hand-crafted placeholder, not a credential to any real service)
- 10 fingerprints in `.planning/phases/04-enrichment-refunds-fees-payouts/*.md` — documentation strings (`key = purchaseUUID1` describes MoneyMoney's `transactionCode` dual-write contract)

After `.gitleaksignore` landed: `gitleaks detect --no-banner --source .` reports `no leaks found`. The allowlist is per-fingerprint (never per-path), so any new code in those files that introduces a real secret would still trip the gate.

## Reproducible build SHA delta

| Build context | sha256 |
|---|---|
| Phase 5 baseline (pre-substitution) | `5dbcb8ea97ae2fb2b675442439ac93b342893e84b9e7849b29df07e9612b777e` |
| Phase 6 dev build (no tag, DEV banner) | `4526a33fceab55122a6e624207c03cf76545939685825c3072c9d9001653304c` |
| Phase 6 tagged build (`GITHUB_REF_NAME=v1.0.0`) | `d1afc595edc528db6719b826a084765719a7f249cb3b8a53cf1c6dd2790c8d36` |

The SHA delta from Phase 5 is by design — `dist/paypal-pos.lua` now contains:
1. The substituted `__VERSION__` literal (`0.00` for dev, `<major>.<2-digit-minor>` for tags)
2. Optional DEV BUILD banner line (dev builds only)
3. Inline `-- D-79-allowed: M_log emission point` sentinel on src/log.lua line 61

Two consecutive `GITHUB_REF_NAME=<same-tag> lua tools/build.lua --verify` invocations produce byte-identical output, so CI-04 reproducibility is preserved under the substitution.

## CI check names for 06-02 branch-protection CHECKS array

The setup-branch-protection.sh script in Plan 06-02 should reference these three check names verbatim:

- `Lint + tests + reproducible build` (pre-existing test job; extended with the D-79 step)
- `gitleaks secret scan` (NEW)
- `Commit-message lint` (NEW)

## Commits

1. `cc14215` — `test(06-01): RED scaffold for __VERSION__ substitution spec (BUILD-03)`
2. `0bad03e` — `feat(06-01): __VERSION__ substitution from $GITHUB_REF_NAME (BUILD-03 / D-73)`
3. `3b33b3a` — `test(06-01): extend META-03 walker to documentation markdown (DOC-04)`
4. `1796676` — `ci(06-01): allowlist fixture-only gitleaks fingerprints (Pitfall 5)`
5. `6b14185` — `ci(06-01): add gitleaks + commit-lint + D-79 raw-print() grep (CI-05 / D-78 / D-79)`

All 5 commits GPG-signed by `FDE07046A6178E89ADB57FD3DE300C53D8E18642`; no AI attribution; all Conventional Commits with `(06-01)` scope.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] D-79 grep against unmodified dist would fail at CI**

- **Found during:** Task 4 verification
- **Issue:** The plan's D-79 grep `grep -nE '^[^-]*print\(' dist/paypal-pos.lua | grep -v '^[[:space:]]*--'` matches the canonical M_log emission point at `dist/paypal-pos.lua:94` (M_log's `_emit` calls `print(...)` to write to MoneyMoney's stdout). The plan's acceptance criterion claims "the artifact is clean today (Phase-5 closure invariant)" but it actually wasn't — the M_log emission line had always been there and was the intentional terminal print() call.
- **Fix:** Added inline sentinel comment `-- D-79-allowed: M_log emission point` on `src/log.lua:61` and extended the CI grep filter to skip lines matching `D-79-allowed`. The sentinel is the single load-bearing exclusion — any new raw `print(` introduced anywhere else fails the gate.
- **Files modified:** `src/log.lua` (added sentinel), `.github/workflows/ci.yml` (added `grep -v 'D-79-allowed'`)
- **Commit:** `6b14185`

**2. [Rule 1 - Bug] version_to_number_string mapping initially formatted minor as `%02d` instead of decimal-fraction**

- **Found during:** Task 2 GREEN — initial Lua spec expected `v1.2.3 -> 1.20` but `string.format("%d.%02d", 1, 2)` returned `1.02`.
- **Issue:** The MoneyMoney `<major>.<minor>` convention treats the minor as a decimal-fraction (single-digit minor "2" becomes "20", two-digit minor "10" stays "10"). The initial implementation used `%02d` (left-pad with zero) which would produce wrong results for any minor > 9.
- **Fix:** Rewrote `version_to_number_string` to render minor as a 2-char string: `#minor == 1` -> append trailing zero (`"2"` -> `"20"`); else take `minor:sub(1, 2)` (`"10"` -> `"10"`).
- **Files modified:** `tools/build.lua` (lines 92-103 — inline in the same Task-2 GREEN commit)
- **Commit:** `0bad03e`

### Plan-Honored Pitfalls (not deviations — explicit plan items)

- Pitfall 3 — DEV BUILD banner: landed exactly as specified
- Pitfall 5 — `.gitleaksignore`: needed (21 fingerprints), landed as separate commit per plan Option B
- Pitfall 6 — META-03 audit-before-extend: pre-extension grep returned zero hits as expected

## Threat Flags

None. The threat surface introduced by this plan is fully covered by the plan's `<threat_model>` block (T-06-01-01..T-06-01-SC). No new endpoints, no new auth paths, no new file-access patterns, no schema changes. Two new GitHub Actions added (`gitleaks/gitleaks-action@v2` only — `softprops/action-gh-release@v2` is queued for 06-02), both approved per the 06-RESEARCH §Package Legitimacy Audit.

## Plan 06-02 unblocked

The Wave-2 plan (`06-02-PLAN.md`) can now proceed with:

- `release.yml` — references `__VERSION__` substitution (this plan provides)
- `tools/setup-branch-protection.sh` — references the three CI check names (this plan provides)
- `README.de.md` + `CONTRIBUTING.md` — META-03 walker auto-picks them up the moment they exist
- 4 new ADRs in `docs/adr/` — META-03 walker auto-scans them via dynamic enumeration

## Self-Check: PASSED

- `[x] test -f spec/build_version_substitution_spec.lua` — confirmed
- `[x] tools/build.lua contains resolve_version_string, version_to_number_string, gsub("__VERSION__", ...), DEV BUILD banner` — confirmed
- `[x] src/webbanking_header.lua line 24: version = __VERSION__,` — confirmed
- `[x] .luacheckrc globals[] += __VERSION__` — confirmed
- `[x] .github/workflows/ci.yml has gitleaks job (name: 'gitleaks secret scan') and D-79 step` — confirmed
- `[x] .github/workflows/commit-lint.yml exists (name: 'Commit-message lint')` — confirmed
- `[x] .gitleaksignore exists, 21 fingerprints, gitleaks detect clean` — confirmed
- `[x] spec/meta_no_tax_classification_spec.lua has DOC_TARGETS + 3rd it() block` — confirmed
- `[x] Pre-extension META-03 grep across README.md + CHANGELOG.md + docs/adr/*.md returns zero hits` — confirmed
- `[x] busted spec/ -> 381/0/0/0` (Phase-5 baseline 373/0/0/0 + 7 new BUILD-03 + 1 new META-03 doc-extension = 381) — confirmed
- `[x] luacheck . clean (41 files)` — confirmed
- `[x] lua tools/build.lua --verify reproducible (both dev and tagged)` — confirmed
- `[x] dev build line 2 contains 'DEV BUILD'` — confirmed
- `[x] tagged build (GITHUB_REF_NAME=v1.0.0) substitutes 'version = 1.00,'` — confirmed
- `[x] D-79 grep over dist/ returns empty after sentinel filter` — confirmed
- `[x] All 5 commits GPG-signed (status 'G')` — confirmed via `git log --show-signature`
- `[x] No AI attribution in any commit message or staged file` — confirmed via no-AI-attribution-gate dry-run
- `[x] All commits use Conventional Commits with (06-01) scope` — confirmed

| Commit | Status | Confirmed via |
|---|---|---|
| `cc14215` | exists, GPG-signed | `git log --show-signature -1 cc14215` |
| `0bad03e` | exists, GPG-signed | `git log --show-signature -1 0bad03e` |
| `3b33b3a` | exists, GPG-signed | `git log --show-signature -1 3b33b3a` |
| `1796676` | exists, GPG-signed | `git log --show-signature -1 1796676` |
| `6b14185` | exists, GPG-signed | `git log --show-signature -1 6b14185` |
