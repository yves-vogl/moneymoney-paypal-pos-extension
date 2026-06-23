---
phase: 06-release-polish
verified: 2026-06-23T03:15:00Z
status: gaps_found
score: 24/25 must-haves verified
overrides_applied: 0
gaps:
  - truth: "release.yml job 2 BUILD-03 sanity step asserts artifact version literal matches the tag (`grep -q 'version = ${EXPECTED},' dist/paypal-pos.lua`)"
    status: failed
    reason: |
      The artifact emitted by tools/build.lua (via src/webbanking_header.lua line 24)
      writes `  version     = 1.00,` — TWO leading spaces and FIVE spaces between
      `version` and `=` (the formatting from the original `version     = 0.00,`
      placeholder, preserved by tools/build.lua's `normalise()` which strips only
      trailing whitespace). The release.yml line-138 grep pattern uses a single
      space (`version = 1.00,`) and will NOT match. At CP-4 the release pipeline
      will abort with:
        "FAIL: artifact version != expected 1.00"
      No release will publish. Both Phase-6 CI (ci.yml) and local builds work
      because they do not run this grep — it only fires inside release.yml.
    artifacts:
      - path: ".github/workflows/release.yml"
        issue: "Line 138 `grep -q \"version = ${EXPECTED},\" dist/paypal-pos.lua` will never match the actual emitted line `  version     = 1.00,` (5-space gap between `version` and `=`)."
      - path: "src/webbanking_header.lua"
        issue: "Line 24 reads `  version     = __VERSION__,` with 2 leading spaces + 5-space gap — the substitution preserves this formatting; release.yml grep does not."
    missing:
      - "Loosen release.yml line-138 grep to a whitespace-tolerant pattern, e.g. `grep -qE \"version[[:space:]]*=[[:space:]]*${EXPECTED},\" dist/paypal-pos.lua` (and update the line-143 success-echo to match)."
      - "Alternatively: add a spec/release_sanity_grep_spec.lua that runs the exact release.yml grep against the substituted artifact so the discrepancy can't reach CP-4 again."
deferred: []
---

# Phase 6: Release & Polish Verification Report

**Phase Goal:** Ship v1.0.0 of the paypal-pos-plugin (MoneyMoney PayPal POS Extension) with a reproducible release pipeline, signed-tag trust chain, German-primary docs, ADR backfill, and CI hardening.
**Verified:** 2026-06-23
**Status:** gaps_found (1 BLOCKER — release pipeline grep mismatch will abort CP-4)
**Re-verification:** No — initial verification.

---

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                                                                                                | Status      | Evidence                                                                                                                  |
| -- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------- |
| 1  | `tools/build.lua` substitutes `__VERSION__` from `$GITHUB_REF_NAME` / git tag / dev-sha fallback (BUILD-03)                                                          | VERIFIED    | `tools/build.lua:96-156`; `GITHUB_REF_NAME=v1.0.0 lua tools/build.lua` produced `  version     = 1.00,` at dist line 25   |
| 2  | DEV BUILD banner appears on dist line 2 when VERSION_NUMBER == "0.00" (Pitfall 3)                                                                                    | VERIFIED    | `env -u GITHUB_REF_NAME lua tools/build.lua`; `head -2 dist/paypal-pos.lua` shows BANNER + `DEV BUILD (no tag)`           |
| 3  | Reproducible build per-tag: two `lua tools/build.lua --verify` invocations produce byte-identical SHA (CI-04)                                                        | VERIFIED    | `lua tools/build.lua --verify` reported `OK: reproducible (sha256: 4526a33f…)`                                            |
| 4  | `src/webbanking_header.lua` line 24 declares `version     = __VERSION__,`; `.luacheckrc` registers `__VERSION__` as global                                           | VERIFIED    | `src/webbanking_header.lua:24`; `.luacheckrc:42` (`globals[#globals+1] = "__VERSION__"`)                                  |
| 5  | `.github/workflows/release.yml` job 1 verifies tag signature via `VALIDSIG <FINGERPRINT>` grep against maintainer fingerprint (Pitfall 8)                            | VERIFIED    | `.github/workflows/release.yml:29` env + `:70` `grep -q "VALIDSIG ${MAINTAINER_FINGERPRINT}"`                             |
| 6  | release.yml `on: push: tags:` filter scopes to `v[0-9]+.[0-9]+.[0-9]+` and `…-rc.[0-9]+` only (Pitfall 10); workflow-level `contents: read`, publish-job `contents: write` (Pitfall 7) | VERIFIED    | `.github/workflows/release.yml:18-22` + `:24-25` + `:188-189` (only publish job escalates to write; count of write = 1) |
| 7  | release.yml job 2 BUILD-03 sanity grep asserts artifact version matches the tag                                                                                       | **FAILED**  | Line 138 uses single-space pattern `grep -q "version = ${EXPECTED},"`; actual artifact line is `  version     = 1.00,` (2+5 spaces). Grep WILL miss. See BLOCKER below. |
| 8  | release.yml job 2 computes SHA256 sidecar (BUILD-05) + extracts tag annotation as release notes with CHANGELOG awk fallback (BUILD-06)                               | VERIFIED    | `.github/workflows/release.yml:152-171` (sha256sum + git for-each-ref + awk fallback)                                     |
| 9  | release.yml job 3 publishes via `softprops/action-gh-release@v2` with `.lua + .sha256` files, `body_path: dist/release-notes.md`, `fail_on_unmatched_files: true`, dynamic prerelease | VERIFIED    | `.github/workflows/release.yml:197-208`                                                                                  |
| 10 | `tools/setup-branch-protection.sh` exists, executable, syntax-clean, contains 3 EXACT CI check names, `required_signatures` sub-resource PUT, graceful degradation   | VERIFIED    | `tools/setup-branch-protection.sh` mode 100755; `bash -n` ok; lines 50-54 CHECKS array, line 129 sub-resource PUT, lines 88-119 403-degradation block |
| 11 | `tools/setup-repo-metadata.sh` exists, executable, contains D-82 verbatim description + 7 topics, uses `PUT /repos/.../topics` (exact-set, not `--add-topic`)         | VERIFIED    | `tools/setup-repo-metadata.sh` mode 100755; line 37 description; lines 41-49 7 topics; lines 60-69 `gh api -X PUT topics` |
| 12 | `README.de.md` (>=150 lines) German-primary canonical README with "Inoffizielle Extensions erlauben" section + GoBD-Hinweis per D-71                                 | VERIFIED    | `README.de.md` 213 lines; section "Inoffizielle Extensions erlauben" lines 31-49 with both screenshot refs; "GoBD-Hinweis" lines 78-85 (D-71 verbatim text incl. "stellt sie in MoneyMoney dar … obliegt der Buchhaltung bzw. der Steuerberatung") |
| 13 | `README.md` reduced to English pointer (~50 lines) linking to README.de.md + CONTRIBUTING.md                                                                          | VERIFIED    | `README.md` 54 lines; line 18 "Primary documentation"; line 20 link to README.de.md; line 40 link to CONTRIBUTING.md     |
| 14 | `docs/img/inoffizielle-extensions-erlauben.png` + `help-menu-extensions-folder.png` valid PNGs (placeholders, CP-5 capture pending) + img/README.md queue tracker     | VERIFIED    | `file` reports both as `PNG image data, 1 x 1, 8-bit/color RGBA`; `docs/img/README.md` 1325 bytes                       |
| 15 | `CONTRIBUTING.md` (>=100 lines, English) covers dev loop, TDD, amalgamator, release process, first-time setup with the 3 admin one-liners                            | VERIFIED    | `CONTRIBUTING.md` 280 lines; contains TDD / MAINTAINER_GPG_PUBKEY / setup-branch-protection.sh / setup-repo-metadata.sh / Conventional Commits |
| 16 | 4 backfilled MADR ADRs exist (0002 LocalStorage, 0006 JWT-bearer, 0007 no-TLS-pinning, 0008 string-return) all ACCEPTED with Status/Context/Decision/Consequences    | VERIFIED    | `docs/adr/000{2,6,7,8}-*.md` present (121/126/146/150 lines); all have ACCEPTED + 4 standard MADR sections                |
| 17 | META-03 walker (`spec/meta_no_tax_classification_spec.lua`) extended to scan README.md + README.de.md + CONTRIBUTING.md + CHANGELOG.md + `docs/adr/*.md`             | VERIFIED    | `spec/meta_no_tax_classification_spec.lua:30-44` DOC_TARGETS + dynamic `ls docs/adr/*.md`; `:120-140` 3rd `it()` block    |
| 18 | META-03 13-phrase grep returns zero hits across README.md + README.de.md + CONTRIBUTING.md + CHANGELOG.md + 8 ADRs                                                   | VERIFIED    | `grep -lnE 'USt-frei\|…\|non-taxable' README.md README.de.md CONTRIBUTING.md CHANGELOG.md docs/adr/*.md` returned no matches (exit 1) |
| 19 | D-79 raw-`print(` CI gate present in ci.yml; grep walks dist/paypal-pos.lua and excludes lines carrying the `D-79-allowed` sentinel                                  | VERIFIED    | `.github/workflows/ci.yml:122-144`; manual reproduction of grep returned empty BAD; sentinel present at `src/log.lua:61` |
| 20 | SEC-03 invariant — Bearer never logged in shipped artifact (Phase 6 did not reintroduce raw print)                                                                    | VERIFIED    | Only one `print(` in dist/ — on the M_log emission line carrying the inline sentinel; D-79 CI gate confirms zero unguarded raw prints |
| 21 | gitleaks secret-scan job present (CI-05) with job `name: gitleaks secret scan` (consumed by branch-protection CHECKS); `.gitleaksignore` carries per-fingerprint allowlist (Pitfall 5) | VERIFIED    | `.github/workflows/ci.yml:229-250` job exists; `.gitleaksignore` 25 entries (incl. updates from fix-batch 06-04)         |
| 22 | commit-lint workflow present (D-78) with `pull_request` trigger and Conventional Commits regex; job `name: Commit-message lint`                                       | VERIFIED    | `.github/workflows/commit-lint.yml` exists; regex `^(feat\|fix\|docs\|test\|refactor\|chore\|ci\|build\|perf\|style\|revert)(\([^)]+\))?: .+`; job name "Commit-message lint" |
| 23 | CHANGELOG.md cut to `## [1.0.0]` with First-stable-release banner + footnote links updated ([Unreleased]→v1.0.0...HEAD; [1.0.0]→releases/tag/v1.0.0; [0.2.0] preserved) (DOC-10) | VERIFIED    | `CHANGELOG.md:12` `## [1.0.0] - 2026-MM-DD`; line 16 "First stable release."; tail shows all 3 footnote links              |
| 24 | `.planning/STATE.md` transitions to `status: v1.0.0-ready-for-tag` with Phase-6 narrative + CP-1..CP-5 dispositions table                                            | VERIFIED    | `.planning/STATE.md:5` status; line 54 "Yves Checkpoints (CP-1..CP-5)" heading                                            |
| 25 | `06-HANDOFF.md` exists (>=60 lines) covering all 5 CPs, MAINTAINER_GPG_PUBKEY one-liner, `git tag -s v1.0.0`, dry-run rc.N, Phase 6.1 forward-pointer                | VERIFIED    | `06-HANDOFF.md` 254 lines; 21 CP-1..CP-5 references; all required tokens present                                          |

**Score:** 24/25 truths verified

---

## Required Artifacts

| Artifact                                                       | Expected                                                                       | Status   | Details                                                                                            |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------ | -------- | -------------------------------------------------------------------------------------------------- |
| `.github/workflows/release.yml`                                | 3-job GPG-tag-triggered pipeline with VALIDSIG + softprops@v2 + .sha256        | PARTIAL  | All structure present; BUILD-03 sanity grep at line 138 will not match real artifact (see BLOCKER) |
| `.github/workflows/ci.yml`                                     | Existing test job extended with D-79 step + new secret-scan job (gitleaks)     | VERIFIED | Lines 122-144 D-79 step; lines 229-250 gitleaks job; existing egress allowlist preserved           |
| `.github/workflows/commit-lint.yml`                            | pull_request trigger + Conventional Commits regex                              | VERIFIED | 51 lines, job name "Commit-message lint", regex matches plan spec                                  |
| `tools/build.lua`                                              | resolve_version_string + version_to_number_string + `__VERSION__` gsub + DEV banner | VERIFIED | Lines 96-156 helpers + module-scope cache; lines 220-227 DEV banner; line 245 gsub                |
| `tools/setup-branch-protection.sh`                             | exec; 3 CHECKS; required_signatures sub-resource; 403 degradation              | VERIFIED | 139 lines; mode 100755                                                                              |
| `tools/setup-repo-metadata.sh`                                 | exec; D-82 description; PUT /topics with 7 topics                              | VERIFIED | 73 lines; mode 100755                                                                              |
| `README.de.md` / `README.md` / `CONTRIBUTING.md`               | German-primary + English pointer + contributor onboarding                      | VERIFIED | 213 / 54 / 280 lines respectively; META-03-clean                                                   |
| 4 new ADRs (0002 / 0006 / 0007 / 0008)                         | MADR ACCEPTED with Status/Context/Decision/Consequences sections               | VERIFIED | All 4 files present with full MADR shape                                                            |
| `docs/img/*.png` placeholders + `docs/img/README.md` tracker   | Valid PNG bytes + queue table                                                  | VERIFIED | Both PNGs valid; README.md present                                                                  |
| `.gitleaksignore`                                              | Per-fingerprint allowlist                                                      | VERIFIED | 25 entries; updated in fix-batch 06-04                                                              |
| `spec/build_version_substitution_spec.lua` / `spec/meta_no_tax_classification_spec.lua` | TDD spec + walker extension                                  | VERIFIED | New 138-line spec + 43-line extension to walker                                                     |
| `CHANGELOG.md` `[1.0.0]` section + footnote links              | Keep-a-Changelog v1.0.0 entry                                                  | VERIFIED | Section + footnotes present (date stays `2026-MM-DD`, Yves fixes at CP-4 prereq)                  |
| `.planning/STATE.md` `v1.0.0-ready-for-tag`                    | Status transition + CP-1..CP-5 table                                           | VERIFIED |                                                                                                     |
| `.planning/phases/06-release-polish/06-HANDOFF.md`             | Post-merge / pre-tag runbook                                                   | VERIFIED | 254 lines                                                                                           |

---

## Key Link Verification

| From                                                | To                                                                         | Status   | Details                                                                                                  |
| --------------------------------------------------- | -------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------- |
| release.yml job 1 VALIDSIG grep                     | maintainer fingerprint `FDE07046A6178E89ADB57FD3DE300C53D8E18642`          | WIRED    | grep pattern at release.yml:70 uses `${MAINTAINER_FINGERPRINT}` env (set at :29 to the exact fingerprint) |
| release.yml job 2 build                             | `$GITHUB_REF_NAME` → tools/build.lua resolve_version_string                | WIRED    | implicit GITHUB_REF_NAME env on tag-trigger consumed by tools/build.lua:98                               |
| release.yml job 2 BUILD-03 sanity                   | dist/paypal-pos.lua `version = X.YY,` line                                 | **NOT_WIRED** | grep at :138 uses single-space pattern; real artifact uses 2-leading-space + 5-space-gap; grep misses |
| release.yml job 3 softprops                         | dist/paypal-pos.lua + dist/paypal-pos.lua.sha256                           | WIRED    | files: multi-line at :202-204                                                                            |
| setup-branch-protection.sh CHECKS                   | ci.yml job names (test / secret-scan / commit-lint)                        | WIRED    | All 3 strings match byte-identically                                                                      |
| setup-repo-metadata.sh PUT /topics                  | 7 D-82 topics                                                              | WIRED    | Exact-set PUT semantics                                                                                   |
| README.de.md GoBD-Hinweis                           | D-71 verbatim wording                                                      | WIRED    | "Diese Extension liest Rohdaten … erhebt KEINEN Anspruch auf GoBD-Konformität, DATEV-Export oder steuerrechtliche Bewertung" |
| META-03 walker DOC_TARGETS                          | README/CHANGELOG/CONTRIBUTING + dynamic docs/adr/*.md                      | WIRED    | Static + dynamic enumeration in spec/meta_no_tax_classification_spec.lua:30-44                            |
| CONTRIBUTING.md Release process                     | `gh secret set MAINTAINER_GPG_PUBKEY` + 2 setup-*.sh scripts               | WIRED    | All 3 one-liners referenced                                                                               |

---

## Behavioral Spot-Checks

| Behavior                                              | Command                                                                                            | Result                                              | Status |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ------ |
| Full busted suite GREEN                               | `./.luarocks/bin/busted spec/`                                                                     | 381 successes / 0 failures / 0 errors / 0 pending  | PASS   |
| Reproducible build (dev)                              | `lua tools/build.lua --verify`                                                                     | `OK: reproducible (sha256: 4526a33f…)`              | PASS   |
| Tagged build emits substituted version literal        | `GITHUB_REF_NAME=v1.0.0 lua tools/build.lua && grep '__VERSION__' dist/paypal-pos.lua \|\| echo ok` | ok (no `__VERSION__` token in dist; line 25 = `  version     = 1.00,`) | PASS   |
| DEV BUILD banner on dev fallback                      | `env -u GITHUB_REF_NAME lua tools/build.lua && head -2 dist/paypal-pos.lua`                        | Line 2 contains `DEV BUILD (no tag)`                | PASS   |
| D-79 grep (manual reproduction)                       | `grep -nE '^[^-]*print\(' dist/paypal-pos.lua \| grep -v '^[[:space:]]*--' \| grep -v 'D-79-allowed'` | empty                                            | PASS   |
| META-03 grep across all new/modified docs             | `grep -lnE 'USt-frei\|…\|non-taxable' README.md README.de.md CONTRIBUTING.md CHANGELOG.md docs/adr/*.md` | no matches (exit 1)                              | PASS   |
| release.yml BUILD-03 sanity grep against real artifact| `EXPECTED=1.00; grep -q "version = ${EXPECTED}," dist/paypal-pos.lua && echo MATCH \|\| echo MISS` | **MISS**                                            | **FAIL** |
| Shell-syntax check on admin scripts                   | `bash -n tools/setup-branch-protection.sh tools/setup-repo-metadata.sh`                            | ok                                                  | PASS   |

---

## Probe Execution

Not applicable. Phase 6 is documentation + CI + release-pipeline scaffolding; no scripts/*/tests/probe-*.sh files are declared or implied. The release.yml workflow itself will be exercised at CP-4 post-merge (via `v1.0.0-rc.1` dry-run option documented in 06-HANDOFF.md) — Yves' responsibility, not the verifier's.

---

## Requirements Coverage

| Requirement | Source Plan                | Description                                                          | Status   | Evidence                                                                                            |
| ----------- | -------------------------- | -------------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------- |
| BUILD-03    | 06-01 Task 2               | `__VERSION__` substitution from $GITHUB_REF_NAME                     | SATISFIED | tools/build.lua + src/webbanking_header.lua + spec/build_version_substitution_spec.lua             |
| BUILD-04    | 06-02 Task 1               | GPG-signed-tag release trigger + VALIDSIG fingerprint match          | SATISFIED | .github/workflows/release.yml job 1                                                                |
| BUILD-05    | 06-02 Task 1               | SHA256 sidecar attached to release                                   | SATISFIED | release.yml job 2 sha256sum step + job 3 files: list                                               |
| BUILD-06    | 06-02 Task 1               | Tag annotation as release notes (CHANGELOG fallback)                 | SATISFIED | release.yml job 2 `git for-each-ref` + awk fallback                                                |
| CI-01..06   | 06-01 Task 4 + pre-existing| Lint+test+coverage+reproducible-build + gitleaks + commit-lint       | SATISFIED | ci.yml + commit-lint.yml; gitleaks job at ci.yml:229                                               |
| SEC-02      | 06-01 Task 4 + Phase-4     | Egress allowlist + D-79 raw-print() bypass gate                      | SATISFIED | ci.yml:83-120 (egress) + :122-144 (D-79)                                                            |
| SEC-05      | 06-02 Task 2 (CP-2 deferred to post-merge) | Branch protection on main (PR + GPG + checks + linear) | SATISFIED-PENDING-CP2 | setup-branch-protection.sh ready; Yves runs at CP-2                                       |
| DOC-01..04  | 06-02 Task 3               | German-primary README + Inoffizielle-Extensions + GoBD-Hinweis       | SATISFIED | README.de.md sections 31-49 + 78-85                                                                 |
| DOC-05      | 06-02 Task 4               | CONTRIBUTING.md                                                      | SATISFIED | 280 lines covering all required topics                                                              |
| DOC-06      | 06-02 Task 4               | 4 backfilled MADR ADRs (0002 / 0006 / 0007 / 0008)                  | SATISFIED | All 4 ACCEPTED with full MADR shape                                                                 |
| DOC-07      | pre-existing               | LICENSE = MIT + Copyright 2026 Yves Vogl                             | SATISFIED | head -3 LICENSE confirmed                                                                           |
| DOC-08..09  | 06-02 Task 2 (CP-3 deferred to post-merge) | Repo metadata (description + 7 topics)                    | SATISFIED-PENDING-CP3 | setup-repo-metadata.sh ready; Yves runs at CP-3                                            |
| DOC-10      | 06-03 Task 1               | CHANGELOG.md [1.0.0] section in Keep-a-Changelog                     | SATISFIED | Section + footnote links present                                                                    |

No ORPHANED requirements detected.

---

## Anti-Patterns Found

| File                              | Line | Pattern                       | Severity | Impact                                                                                                  |
| --------------------------------- | ---- | ----------------------------- | -------- | ------------------------------------------------------------------------------------------------------- |
| `.github/workflows/release.yml`   | 138  | grep pattern too strict       | **Blocker** | BUILD-03 sanity step misses the real artifact line shape; release.yml will abort at CP-4. See HIGH-SEVERITY gap above. |
| `CHANGELOG.md`                    | 79   | `## [0.2.0] - 2026-MM-DD` (legacy placeholder, predates Phase 6)  | Info     | Inherited from Phase 4; the v0.2.0 release was never tagged because it pre-dates the GPG-signed-tag release pipeline. Yves fixes both 0.2.0 AND 1.0.0 dates at CP-4 prereq, or leaves 0.2.0 as a historical placeholder. Not a Phase-6 regression. |
| `README.de.md`                    | 24-27, 38, 45, 80 | `<!-- … pending — CP-X -->` HTML markers | Info     | Intentional CP-1 lektor / CP-5 screenshot trail; documented in 06-HANDOFF.md. Removed by Yves post-CP-1/CP-5. |
| `CHANGELOG.md`                    | 12   | `## [1.0.0] - 2026-MM-DD`     | Info     | Intentional date placeholder; Yves finalises at CP-4 prereq with single commit `docs(changelog): finalize v1.0.0 release date <YYYY-MM-DD>`. Documented in 06-HANDOFF.md. |

No TBD / FIXME / XXX debt markers found in Phase-6 surface files. The HTML-comment markers in README.de.md are intentional CP trails and reference the formal checkpoint runbook (06-HANDOFF.md).

---

## Human Verification Required

None for Phase-6 implementation itself — the CP-1..CP-5 checkpoints are explicit Yves actions queued in `06-HANDOFF.md` and surfaced in `.planning/STATE.md`, not verification gaps. The phase as planned was autonomous and the 5 CPs are documented post-merge / pre-tag steps in Yves' runbook.

After the BLOCKER is fixed and merged, Yves still owns the 5 CPs per the HANDOFF runbook — but those are not Phase-6-implementation verification items, they are release-ceremony steps gated on the merged PR.

---

## Gaps Summary

**1 BLOCKER — load-bearing release-pipeline grep mismatch.**

`.github/workflows/release.yml` line 138 uses `grep -q "version = ${EXPECTED}," dist/paypal-pos.lua` (single space between `version` and `=`). The artifact emitted by `tools/build.lua` from `src/webbanking_header.lua` produces `  version     = 1.00,` (two leading spaces + five-space gap — preserved from the original `version     = 0.00,` placeholder formatting; `normalise()` strips only trailing whitespace).

At CP-4 (`git push origin v1.0.0`), release.yml job 2 will fail at the "BUILD-03 sanity" step with `FAIL: artifact version != expected 1.00`. The release will NOT publish. This blocks the v1.0.0 ship.

**Why this slipped through:**
- 06-02 Plan Task 1 wrote the grep pattern from RESEARCH §3 example wording without normalising against the actual emitted line shape.
- 06-02 SUMMARY's Self-Check checked that the grep step EXISTS but did not run it against a substituted artifact.
- ci.yml does NOT include this sanity grep (the egress allowlist + D-79 + META-03 walker cover dist/, but none assert the version literal).
- The Phase-6 SUMMARY pass relied on the visual check + reproducibility check + `__VERSION__` absence — all true and irrelevant to whether the GREP shape matches.

**Recommended fix (single-commit, minimal):**

```yaml
# .github/workflows/release.yml line 138 — loosen grep to tolerate the
# 5-space gap from src/webbanking_header.lua's original formatting.
- if ! grep -q "version = ${EXPECTED}," dist/paypal-pos.lua; then
+ if ! grep -qE "version[[:space:]]*=[[:space:]]*${EXPECTED}," dist/paypal-pos.lua; then
```

And add a spec to lock the contract so regressions can't reach CP-4 again:

```lua
-- spec/release_yml_sanity_spec.lua
-- Asserts the regex used by release.yml's BUILD-03 sanity step matches the
-- shape emitted by tools/build.lua + src/webbanking_header.lua. Catches
-- drift between the workflow's grep pattern and the artifact's formatting.
```

**Other observations (not gaps):**
- All 22 phase requirement IDs traced to a delivering artifact.
- Phase-2/3/4/5 src/spec surface preserved with one legitimate deviation: `spec/http_retry_spec.lua` gained 12 lines in fix-batch commit `4d5363a (fix(06-04): CI green — gitleaks false-positives + flaky http_retry test)`. This is documented in the commit body as a deterministic-time fix for a CI flake, not a behavior change. `src/log.lua` also gained the D-79 sentinel line (already documented in 06-01-SUMMARY).
- Two `06-04` fix-batch commits (`4d5363a` + `1468018`) exist that aren't documented in the 3 plans — they're post-PR-open CI-fix commits (gitleaks false-positives + http_retry CI flake). Both have proper Conventional Commits prefixes, GPG-signed, and are scoped correctly.

---

_Verified: 2026-06-23_
_Verifier: Claude (gsd-verifier)_
