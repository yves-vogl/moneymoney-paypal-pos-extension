---
phase: 06-release-polish
reviewed: 2026-06-23T00:00:00Z
depth: deep
files_reviewed: 7
files_reviewed_list:
  - .github/workflows/release.yml
  - .github/workflows/commit-lint.yml
  - CHANGELOG.md
  - docs/adr/0001-amalgamator-design.md
  - docs/adr/0008-string-return-error-pattern.md
  - src/log.lua
  - spec/log_redaction_spec.lua
  - tools/build.lua
  - tools/setup-branch-protection.sh
  - spec/build_version_substitution_spec.lua
findings:
  critical: 0
  warning: 0
  info: 1
  total: 1
status: clean
scope: e1b0736^..b68d57a (10 fix commits)
test_suite: 388/388 passing
dist_sha_stable: yes (18bb7a6ae43d8b9c60951f13afe7476b19c2854256a07e42cfeca9e73d58e0c1 before/after spec run)
---

# Phase 6 — Code Review R2 (Fix-Batch Verification)

Re-review of the 10-commit fix batch `e1b0736^..b68d57a` against the
findings from `06-REVIEW.md`. Scope is the diff only; the broader Phase 6
surface was already reviewed.

## Per-commit verdicts

| Commit | Finding(s) addressed | Verdict | Notes |
|--------|----------------------|---------|-------|
| `e1b0736` | P6-R-01 + verifier BLOCKER | **PASS** | Bash algorithm now mirrors `tools/build.lua` `version_to_number_string()` exactly: one-digit minor zero-suffixed (`MINOR0`), two-or-more-digit minor truncated to first two (`${MINOR:0:2}`). Grep uses `version[[:space:]]*=[[:space:]]*${EXPECTED},` — whitespace-tolerant on the BRE. Manual cross-check of v1.0.0→`1.00`, v1.2.3→`1.20`, v0.10.0→`0.10`, v1.5.0→`1.50`, v1.0.0-rc.1→`1.00` all match the Lua side. |
| `1f0fd7a` | P6-R-02 | **PASS** | v1.0.0 heading carries real date `2026-06-23`. Both `<!-- lektor-review: pending -->` HTML comments removed from the v1.0.0 section AND the [Unreleased] section. The v0.2.0 placeholder `2026-MM-DD` remains but is explicitly out of scope per the commit message AND outside the release-notes extraction window (release.yml awk extracts only the v1.0.0 section). |
| `58a20f7` | P6-R-03 | **PASS** | `grep -n "M_refresh\|error.internal_unexpected\|M_log.error" docs/adr/0008-string-return-error-pattern.md` returns zero matches. ADR now describes the real contract: WebBanking callbacks in `src/entry.lua` use ordered early-return of localized error strings; discipline enforced by review + test suite, not a runtime `pcall` firewall. Future-work item explicitly noted. |
| `6b6098b` | P6-R-04 | **PASS** | `docs/adr/0001-amalgamator-design.md` predeclaration list now reads `M_log, M_errors, M_i18n, M_model, M_http, M_auth, M_pagination, M_purchases, M_finance, M_mapping` — byte-exact match against `src/webbanking_header.lua` lines 8-17. No more `M_payouts` / `M_balance` / `M_refresh` references. |
| `c62d434` | G-02 | **PASS** | `|| true` dropped; RC captured cleanly via `set +e; gh verify-tag --raw …; RC=$?; set -e` and rejected when non-zero (`exit 1`). VALIDSIG grep anchored on `^\[GNUPG:\] VALIDSIG ` (gpg status-fd machine-parseable prefix) with two alternates covering signing-key OR primary-key match — handles subkey signing correctly. Spoofing the prefix via tag annotation body is now infeasible because `git verify-tag --raw` only emits `[GNUPG:]` lines from gpg itself. |
| `d929708` | G-03 | **PASS** (with IN-R2-01) | Case-variant bearer regex `[Bb][Ee][Aa][Rr][Ee][Rr]` added. JWT signature class extended to `[%w%-_.+=]` — `/` deliberately omitted with thorough inline comment explaining the URL-preservation rationale. Verified by direct Lua test that `https://finance.izettle.com/v2/accounts/liquid/transactions` is NOT redacted (third segment `com` after the second `.` is only 3 chars before hitting `/`, fails the `+` quantifier). Four new JSON-form keys: `assertion`, `refresh_token`, `id_token`, `client_secret`. 7 new specs all green; full suite 388/388 passing. See IN-R2-01 for a minor cosmetic note. |
| `a2e0f71` | P6-R-05 | **PASS** | Both PUT invocations refactored from broken `if ! cmd; then RC=$?; fi` idiom (which always captures `!`'s exit code, not gh's) to canonical `set +e; cmd; RC=$?; set -e`. Post-condition GET implemented with three field assertions: (a) `enforce_admins.enabled == true`, (b) all 3 required-check contexts present via `jq -e index`, (c) `required_signatures.enabled == true`. `bash -n` syntax-clean. Silent partial-apply path is now fail-loud. |
| `69b3263` | P6-R-06 | **PASS** | Format string changed from `%(contents)` to `%(contents:subject)%n%n%(contents:body)` — both sub-attributes auto-strip the PGP block per git docs. Belt-and-braces `sed '/^-----BEGIN PGP SIGNATURE-----/,/^-----END PGP SIGNATURE-----/d'` added as secondary scrub. Hard assertion `grep -q 'BEGIN PGP SIGNATURE\|END PGP SIGNATURE'` fails the workflow if any marker survives — defends against future git or format-string regressions. |
| `21cf4fc` | P6-R-07 | **PASS** | Regex extended to `(\([^)]+\))?!?: .+` — verified locally that `feat: x`, `feat(scope): x`, `feat!: x`, `feat(scope)!: x` all match while `feat:` (missing description) and `random: x` (unknown type) still fail. Conventional Commits 1.0.0 grammar correctly captured. |
| `b68d57a` | P6-R-08 | **PASS** | `tools/build.lua` honors `BUILD_OUT_PATH` env var, defaulting to `dist/paypal-pos.lua` (CI behaviour unchanged). `TMP_PATH = OUTPUT_PATH .. ".tmp"` derives correctly. `write_output` now extracts parent dir from path and `mkdir -p`s it instead of hard-coding `dist/`. Spec refactored to use `os.tmpname()` + `after_each` cleanup. **Confirmed empirically**: dist sha256 = `18bb7a6...e0c1` before AND after running `busted spec/build_version_substitution_spec.lua` — canonical artifact no longer clobbered by the spec suite. |

## Summary counts

- **PASS**: 10 / 10
- **FAIL**: 0
- **NEW-FINDING (HIGH/CRITICAL)**: 0
- **NEW-FINDING (Info)**: 1 (see below)

## New Info findings

### IN-R2-01: case-insensitive `bearer` regex can over-redact words containing "bearer"

**File:** `src/log.lua:34`
**Severity:** Info (over-redaction is the safe direction; SEC-01 design pillar)
**Issue:** The new pattern `[Bb][Ee][Aa][Rr][Ee][Rr]%s+%S+` is unanchored on word boundaries. A log line containing e.g. `forebearer foo` would match `bearer foo` (positions 5+) and the substitution yields `fore<Bearer <redacted>>`-style output, dropping the trailing token after "bearer" anywhere in the line.

In practice this is harmless because:
1. The redactor's design pillar (SEC-01, ADR-0006) is to over-redact rather than under-redact.
2. No realistic log message in the codebase contains words like `forebearer`, `unbearable`, etc.
3. Lua's pattern language has no `\b` word-boundary anchor; adding `%f[%w]` frontier patterns front and back would complicate the regex without changing the security posture.

**Fix (optional, defer to backlog):** No action required for v1.0.0. If a future log line surfaces a false positive that obscures useful debugging information, switch to a `%f[%w][Bb][Ee][Aa][Rr][Ee][Rr]%f[%W]%s+%S+` frontier-anchored variant and add a spec for the boundary case.

## Cross-cutting verification

- **Test suite**: 388 successes / 0 failures / 0 errors after the full batch.
- **Reproducible artifact**: `dist/paypal-pos.lua` SHA256 = `18bb7a6ae43d8b9c60951f13afe7476b19c2854256a07e42cfeca9e73d58e0c1` is stable across spec runs (was the goal of P6-R-08).
- **No regressions** introduced to any of the 10 commits' fix surfaces.
- **No new security exposure**: G-02 narrows the VALIDSIG gate; G-03 broadens the redactor; both move the security posture in the right direction.

## Recommendation

**SHIP.** All 10 commits successfully address their respective findings without introducing regressions. The one Info-level note (IN-R2-01) is a defensible design choice consistent with the project's over-redact-by-default security stance and can be deferred to backlog.

---

_Reviewed: 2026-06-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep (per-commit diff inspection + cross-file impact verification + test suite execution)_
