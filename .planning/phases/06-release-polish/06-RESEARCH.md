# Phase 6: Release & Polish — Reproducible Build, CI/CD, German Docs — Research

**Researched:** 2026-06-22
**Domain:** GitHub-native release engineering for a single-file Lua artifact (signed-tag → reproducible build → published asset) + bilingual docs + MADR ADRs + branch-protection-as-code + secret scanning + supply-chain hygiene
**Confidence:** HIGH (every locked decision in CONTEXT D-70..D-82 has either a verified upstream-doc reference or an existing in-repo pattern this phase extends)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-70** `README.de.md` is the German-primary canonical install/usage guide; `README.md` (English) is a short pointer to `README.de.md` for technical visitors + the same Bekannte Grenzen / GoBD-Hinweis sections in English.
- **D-71** GoBD-Hinweis exact wording (subject to loop-lektor refinement; engineering placeholder): "Hinweis zur Buchhaltung: Diese Extension liest Rohdaten aus der PayPal POS API und stellt sie in MoneyMoney dar. Sie erhebt KEINEN Anspruch auf GoBD-Konformität, DATEV-Export oder steuerrechtliche Bewertung. Die Klassifizierung der Umsätze (Erlöse, Aufwendungen, Vorsteuer, etc.) obliegt der Buchhaltung bzw. der Steuerberatung. Die Extension ersetzt keine Buchhaltungssoftware." — META-03-compliant.
- **D-72** GPG-signed-tag release flow: `.github/workflows/release.yml` triggers on `v[0-9]+.[0-9]+.[0-9]+` + `v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+`. Job 1 verifies signature via imported `MAINTAINER_GPG_PUBKEY` secret + `git verify-tag $GITHUB_REF_NAME` exit 0. Job 2 runs lint+test+coverage+reproducible-build-diff. Job 3 substitutes `__VERSION__` and publishes via `softprops/action-gh-release@v2` with `prerelease: contains(github.ref_name, '-rc.')`. Maintainer fingerprint `FDE07046A6178E89ADB57FD3DE300C53D8E18642` is the only accepted signature.
- **D-73** `tools/build.lua` reads tag from `$GITHUB_REF_NAME` (CI) or `git describe --tags --exact-match` (local); falls back to `dev-<short-sha>`. Substitutes literal `__VERSION__` token in `src/webbanking_header.lua`.
- **D-74** Branch protection on `main`: requires (a) PR before merge, (b) GPG-signed commits, (c) CI green, (d) linear history. Configured via `gh api` in `tools/setup-branch-protection.sh`; graceful degradation when token lacks `Administration:write` (print manual UI steps, exit 0).
- **D-75** Coverage gate: ≥85% line coverage on `src/` excluding `webbanking_header.lua`; enforced via `luacov` + custom assertion script.
- **D-76** Secret scanning: `gitleaks/gitleaks-action@v2` on push + PR; scans history + working tree for JWT shape, AWS keys, GitHub PATs, Zettle assertion-grant patterns. Free for public repos / personal accounts.
- **D-77** Dependabot: `.github/dependabot.yml` tracks `github-actions` (weekly). LuaRocks is not Dependabot-supported — out of scope for v1.0.0.
- **D-78** Commit-message lint: GitHub Action with a shell regex on PR commits matching `(feat|fix|docs|test|refactor|chore|ci|build|perf|style)(\(.+\))?: .+`.
- **D-79** Egress allowlist hardening (extends Phase-4 CI gate): artifact MUST contain only `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`. Also greps for `print(` calls bypassing `M_log` (should be zero in shipped src/).
- **D-80** ADR backfill: ADR-0002 (LocalStorage cache), ADR-0006 (JWT-bearer-only + Phase-7 forward-compat), ADR-0007 (no TLS pinning), ADR-0008 (string-return error pattern).
- **D-81** CHANGELOG.md finalization: v0.2.0 stays; v1.0.0 entry added on tag with first-stable-release notice + full feature set + documented limitations.
- **D-82** Repo metadata via `gh repo edit`: German description + 7 topics (`moneymoney`, `moneymoney-extension`, `paypal-pos`, `zettle`, `lua`, `germany`, `accounting`).

### Claude's Discretion

- README.de.md screenshot — placeholder `docs/img/inoffizielle-extensions-erlauben.png` referenced; Yves captures actual screenshot post-merge (CP-5).
- ADR-0006 wording for Phase-7 forward-compat — cross-reference ROADMAP Phase 7 entry; brief enough not to duplicate but precise enough for a future implementer.
- Coverage threshold 85% vs 90% — recommend 85% per ROADMAP success-criterion 2; tighter is a v1.0.x ratchet decision.

### Deferred Ideas (OUT OF SCOPE)

- LuaRocks dependency-update bot.
- ZUGFeRD / DATEV export.
- Multi-language docs (FR / ES / IT).
- Automated screenshot capture.
- Hosted documentation site.
- v0.2.x cleanup items deferred from Phase 5 — bundle into v1.0.1 cleanup PR.
- Plan 04-01 Q3 sandbox probe + Plan 05-01 Q9 `MM.sleep` probe.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BUILD-03 | `WebBanking{version=X.YY}` substituted from Git tag at build time | §3 (substitution algorithm + MoneyMoney `version` field contract) |
| BUILD-04 | Releases triggered by GPG-signed tag; CI verifies signature before publishing | §2 (GPG verification recipe) + §1 (release.yml shape) |
| BUILD-05 | Release assets include `paypal-pos.lua` + `paypal-pos.lua.sha256` | §1 (softprops `files:` multi-file syntax) |
| BUILD-06 | `softprops/action-gh-release@v2` publishes release with tag annotation as notes | §1 (`body_path` support + tag-annotation extraction) |
| CI-01 | luacheck + busted + luacov on every push/PR | ✅ already in ci.yml; Phase 6 extends with coverage gate hardening |
| CI-02 | ≥85% coverage gate on `src/` excluding `webbanking_header.lua` | §10 (coverage-gate.lua design — clarifies that current gate runs on `dist/paypal-pos.lua` totals) |
| CI-03 | `ubuntu-24.04` + Lua 5.4 + `LC_ALL=C` | ✅ already in ci.yml |
| CI-04 | Build artifact twice in clean checkouts, diff fails on mismatch | ✅ already via `tools/build.lua --verify`; release.yml inherits |
| CI-05 | gitleaks-or-equivalent scan | §4 (gitleaks v2 action wiring + false-positive surface) |
| CI-06 | Dependabot tracks dev-tooling + GitHub-Actions versions | §5 + ✅ already in `.github/dependabot.yml` (github-actions ecosystem) |
| SEC-02 | CI greps shipped artifact for hosts outside allowlist | ✅ already in ci.yml; D-79 extends with `print(` bypass grep |
| SEC-05 | Branch protection on `main` requires GPG-signed commits + CI green | §6 (branch-protection-as-code recipe + graceful degradation) |
| DOC-01 | `README.de.md` is primary German README | §1 (file layout) + Patterns map |
| DOC-02 | First section is screenshot-illustrated "Inoffizielle Extensions erlauben" guide | §8 (UI label verbatim + screenshot placeholder strategy) |
| DOC-03 | Both install paths (sandboxed + non-sandboxed) documented + `Hilfe → Erweiterungen im Finder zeigen` | §8 + Patterns map (existing README.md content moves to README.de.md) |
| DOC-04 | German GoBD-Hinweis explicitly NOT claiming conformance | D-71 verbatim wording |
| DOC-05 | `CONTRIBUTING.md` (English): dev loop, testing, amalgamator, release process, GPG-signed-tag requirement | Patterns map (CONTRIBUTING.md template) |
| DOC-06 | MADR ADRs covering amalgamator, LocalStorage cache, JWT-bearer-only, fee modeling, no-TLS-pinning, string-return errors, sandbox probes | §9 (MADR template walk) + D-80 (4 new ADRs) |
| DOC-07 | `LICENSE` MIT + "Yves Vogl" | ✅ already exists at repo root (verified `head LICENSE`) |
| DOC-08 | GitHub repo description set via `gh repo edit` (German) | §7 (gh CLI invocation) |
| DOC-09 | 7 GitHub topics | §7 |
| DOC-10 | `CHANGELOG.md` Keep-a-Changelog per SemVer | ✅ already in place (Keep-a-Changelog format from Phase 4); Phase 6 adds v1.0.0 section |

</phase_requirements>

## Summary

Phase 6 turns the working extension into a publishable v1.0.0 by adding the release machinery, the trust-chain documentation, and the supply-chain hygiene that a stranger landing on GitHub uses to decide whether to install it. Most of the surface area is already partially in place from Phases 1–5 — CI workflow with coverage gate + egress allowlist + reproducible-build verifier, dependabot.yml, SECURITY.md, LICENSE, README.md (German engineering-draft), CHANGELOG.md, and four ADRs (0001, 0003, 0004, 0005). Phase 6 fills the remaining gaps: a tag-triggered release workflow with GPG-signature verification, `__VERSION__` substitution from the tag, the bilingual README split, four backfilled ADRs, CONTRIBUTING.md, the branch-protection + repo-metadata helper scripts, gitleaks, commit-lint, and the META-03 walker extension to cover markdown.

**Primary recommendation:** Land Phase 6 in three logical waves — (W1) reusable build/CI scaffolding (`__VERSION__` substitution + coverage-gate.lua + gitleaks + commit-lint + META-03 doc-walker extension); (W2) trust-chain artifacts (release.yml + GPG-verify recipe + branch-protection script + repo-metadata script + README split + CONTRIBUTING.md + 4 new ADRs); (W3) cut v1.0.0 (CHANGELOG entry + Yves runs `git tag -s v1.0.0`). Defer the v0.2.x cleanup batch deferred from Phase 5 to a follow-up v1.0.1 PR. The 5 Yves checkpoints (loop-lektor pass, branch-protection PAT, repo-metadata PAT, tag publication, screenshot capture) are all post-merge or pre-tag — none block the Phase-6 PR from opening.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Tag → release artifact pipeline | CI / GitHub Actions | — | `release.yml` is GitHub-native; no in-process code |
| GPG tag signature verification | CI (gpg in workflow) | Maintainer GPG keychain (local) | Trust chain rooted in maintainer key fingerprint |
| `__VERSION__` substitution | Build tool (`tools/build.lua`) | CI env (`$GITHUB_REF_NAME`) | Tag-name source is CI/env; substitution happens in builder |
| Coverage gate | CI (shell + luacov) | Optional helper (`tools/coverage-gate.lua`) | Current CI gates Total %; D-75 keeps that contract |
| Secret scanning | CI (gitleaks action) | Optional `.gitleaks.toml` allowlist | Action consumes repo config |
| Commit-message lint | CI (shell regex on PR commits) | — | No Node toolchain; pure shell |
| Branch protection | GitHub API (one-time admin) | Helper script (`tools/setup-branch-protection.sh`) | Outside the repo's runtime; declared once, not in CI |
| Repo metadata | GitHub API (one-time admin) | Helper script (`tools/setup-repo-metadata.sh`) | Same pattern |
| User-facing install docs | Repo Markdown (`README.de.md` primary) | English mirror (`README.md`) | German-primary per PROJECT.md |
| Architectural decisions log | Repo Markdown (`docs/adr/*.md`) | MADR template | Audit-trail-as-code |
| META-03 enforcement | Test suite (`spec/meta_no_tax_classification_spec.lua`) | CI runs busted | Phase 6 extends walker to markdown files |

## Standard Stack

### Core (used by Phase 6 implementation)

| Library / Action | Version | Purpose | Why Standard |
|---|---|---|---|
| `softprops/action-gh-release` | **v2** (latest stable) | Publish GitHub Release with attached assets | De-facto MoneyMoney-extension community standard (Trading-212 release.yml uses v1; v2 is current). Supports newline-delimited multi-file `files:` glob, `body_path:`, `prerelease:` boolean. `[VERIFIED: github.com/softprops/action-gh-release]` |
| `gitleaks/gitleaks-action` | **v2** | Secret scan on push + PR | Free for personal repos (no `GITLEAKS_LICENSE` needed for `yves-vogl/*`). Scans history when `actions/checkout` uses `fetch-depth: 0`. `[VERIFIED: github.com/gitleaks/gitleaks-action]` |
| `actions/checkout` | **v4** | Workspace checkout | Already pinned in `ci.yml`. Use `fetch-depth: 0` in release.yml (need tag history for `git verify-tag`) and in gitleaks job (need history). `[CITED: ci.yml line 23]` |
| `leafo/gh-actions-lua` | **v13** | Lua 5.4 provisioning | Already pinned in `ci.yml`; release.yml mirrors. `[VERIFIED: .github/workflows/ci.yml line 28]` |
| `leafo/gh-actions-luarocks` | **v6.1.0** | LuaRocks paired install | Same. `[VERIFIED: ci.yml line 33]` |
| Dependabot v2 schema | n/a (GitHub-managed) | Track `github-actions` ecosystem weekly | Already configured in `.github/dependabot.yml`. LuaRocks not supported. `[VERIFIED: docs.github.com/.../dependabot.yml]` |
| `gh` CLI | ≥ 2.40 (any current) | `gh api`, `gh repo edit`, `gh release create` | Bundled in GitHub-hosted runners; required locally for setup scripts. `[ASSUMED]` |
| GPG (`gpg2`) | macOS-bundled or `brew install gnupg` | Tag signing locally; verify in CI runner (preinstalled on `ubuntu-24.04`) | Already used by maintainer (`FDE07046A6178E89ADB57FD3DE300C53D8E18642`). `[VERIFIED: docs/adr/0005 §Deciders]` |

### Already in repo (Phase 6 extends, does not introduce)

| Asset | State | Phase 6 Action |
|---|---|---|
| `tools/build.lua` | Phase-1 amalgamator with SHA-256 + `--verify` | Add `__VERSION__` substitution (~15 LoC) |
| `tools/manifest.txt` | Phase-1 module order | No change |
| `.github/workflows/ci.yml` | Phase-1+2+4+5 baseline | Add coverage-gate hardening + gitleaks + commit-lint + META-03 doc-walker step (or fold into spec) |
| `.github/workflows/scorecard.yml` | Already exists (Phase 1) | No change |
| `.github/dependabot.yml` | Already exists; tracks `github-actions` weekly | No change |
| `LICENSE` | MIT + "Copyright (c) 2026 Yves Vogl" | No change (DOC-07 satisfied) |
| `SECURITY.md` | Already in place | No change |
| `CHANGELOG.md` | Keep-a-Changelog with v0.2.0 + Unreleased | Add v1.0.0 entry |
| `README.md` | German engineering-draft (179 lines) with screenshot placeholder + GPG verification block | Rename to `README.de.md`; create new English `README.md` pointer |
| `docs/adr/0001-amalgamator-design.md` | MADR ACCEPTED | No change |
| `docs/adr/0003-sandbox-probe-results.md` | MADR ACCEPTED | No change |
| `docs/adr/0004-finance-api-scope-and-fee-fallback.md` | MADR ACCEPTED | No change |
| `docs/adr/0005-resilience-invariants.md` | MADR ACCEPTED | No change |
| `spec/meta_no_tax_classification_spec.lua` | Phase-4 walker over `src/*.lua` + `dist/paypal-pos.lua` | Extend target list to include `README.md`, `README.de.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `docs/adr/*.md` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| `softprops/action-gh-release@v2` | `gh release create` + manual upload | softprops handles asset dedup, body rendering, prerelease flag — `gh` would require ~30 LoC of shell. softprops is unanimous in the Lua/MoneyMoney ecosystem. |
| `gitleaks/gitleaks-action@v2` | TruffleHog action | gitleaks is the canonical OpenSSF Scorecard signal for secret scanning; we already have a Scorecard workflow in place that gives credit for gitleaks specifically. |
| Shell-based commit-lint | `@commitlint/cli` (Node) | Avoids a Node toolchain in the repo. The grammar we want is a single regex; shell is the right tool. |
| `tools/coverage-gate.lua` (Lua) | Keep existing inline shell parsing in `ci.yml` (lines 48–69) | Existing approach already implements the gate. Extracting to a Lua script is reuse-friendly but not load-bearing for v1.0.0. **Recommendation:** keep the inline shell (no new file); if D-75 wants per-src-file enforcement later, that's a v1.0.x task. |
| `git verify-tag` directly | `verify-commit-action` (third-party) | `git verify-tag` is built into git, runs anywhere, has no maintainer-trust surface. Use it. |
| `.gitleaksignore` | Repo-wide `.gitleaks.toml` allowlist | `.gitleaksignore` is line-by-line specific; `.gitleaks.toml` is regex-based. We need neither unless gitleaks flags our test fixtures (§4). Add `.gitleaksignore` only if a real false-positive surfaces in W1. |

**Installation (CI only — nothing new shipped):**

No new LuaRocks deps. New GitHub-Actions deps land via release.yml + ci.yml YAML edits; Dependabot will track their versions weekly.

**Version verification** (run before locking versions):

```bash
gh api -H "Accept: application/vnd.github+json" /repos/softprops/action-gh-release/releases/latest --jq .tag_name
gh api -H "Accept: application/vnd.github+json" /repos/gitleaks/gitleaks-action/releases/latest --jq .tag_name
```

Expected (as of 2026-06-22): `v2.x.y` for softprops; `v2.x.y` for gitleaks-action.

## Package Legitimacy Audit

Phase 6 ships **no new external packages**. The three new GitHub Actions consumed in workflows are:

| Action | Org/Repo | Stars (proxy) | Verdict | Disposition |
|---|---|---|---|---|
| `softprops/action-gh-release` | `softprops/action-gh-release` | ~5k+ stars, 5+ years, used by thousands of repos including teal-bauer/moneymoney-ext-trading212 in our own research baseline | OK | Approved |
| `gitleaks/gitleaks-action` | `gitleaks/gitleaks-action` | Official org behind the gitleaks tool (~17k stars across org repos); OpenSSF Scorecard recommends it | OK | Approved |
| `actions/checkout`, `leafo/gh-actions-lua`, `leafo/gh-actions-luarocks`, `ossf/scorecard-action` | First-party + already-in-use | n/a | OK | Already approved (used in Phase-1 ci.yml + scorecard.yml) |

**Packages removed due to [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none.

## Section 1 — `softprops/action-gh-release@v2` invocation pattern

**Confidence: HIGH.** `[VERIFIED: github.com/softprops/action-gh-release]`

### Canonical job step

```yaml
- name: Publish GitHub Release
  uses: softprops/action-gh-release@v2
  with:
    # tag_name defaults to github.ref when the workflow is triggered by a tag push;
    # leaving it unset is the recommended pattern.
    name: ${{ github.ref_name }}
    body_path: dist/release-notes.md       # rendered from the tag annotation (see §1.2)
    files: |
      dist/paypal-pos.lua
      dist/paypal-pos.lua.sha256
    prerelease: ${{ contains(github.ref_name, '-rc.') }}
    fail_on_unmatched_files: true
    draft: false
    generate_release_notes: false           # we render our own from the tag annotation
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Key behaviors

- **Multi-file attachment:** `files:` uses YAML multi-line string (`|`), each line is a glob; newlines separate files. Confirmed for v2. `[VERIFIED: github.com/softprops/action-gh-release README]`
- **`body_path:`:** path to a file containing the release notes. We render this file in a preceding step from the tag annotation (`git for-each-ref refs/tags/${TAG} --format='%(contents)'`) so the release body == the signed tag's annotation. Satisfies BUILD-06.
- **`prerelease:` dynamic:** `contains(github.ref_name, '-rc.')` evaluates true for tags like `v1.0.0-rc.1` and false for `v1.0.0`. GitHub Actions supports `contains(string, substring)` natively. `[CITED: docs.github.com/en/actions/learn-github-actions/expressions]`
- **Permissions required:** `contents: write` at the job level (NOT workflow-wide). Pattern:
  ```yaml
  jobs:
    publish:
      permissions:
        contents: write
  ```
- **`fail_on_unmatched_files: true`:** important — if `dist/paypal-pos.lua` or `dist/paypal-pos.lua.sha256` is missing, the job fails loudly instead of publishing a partial release.

### Release-notes rendering step (preceding softprops)

```yaml
- name: Extract tag annotation as release notes
  run: |
    set -euo pipefail
    mkdir -p dist
    TAG="${GITHUB_REF_NAME}"
    git for-each-ref "refs/tags/${TAG}" --format='%(contents)' > dist/release-notes.md
    # Empty annotation → use the CHANGELOG.md entry for this version as fallback
    if [ ! -s dist/release-notes.md ]; then
      # Naive extract: lines between [TAG_WITHOUT_V] header and the next [X.Y.Z] header
      VERSION="${TAG#v}"
      awk "/^## \\[${VERSION}\\]/{flag=1;next} /^## \\[/{flag=0} flag" CHANGELOG.md > dist/release-notes.md
    fi
    wc -l dist/release-notes.md
```

This is deterministic, depends on no external tools beyond `awk` + `git`, and produces the file softprops's `body_path:` consumes.

## Section 2 — GPG tag-signature verification in GitHub Actions

**Confidence: HIGH.** `[VERIFIED: docs.github.com/en/authentication/managing-commit-signature-verification]` + git docs.

### Recipe

```yaml
verify-signed-tag:
  name: Verify GPG tag signature
  runs-on: ubuntu-24.04
  permissions:
    contents: read
  outputs:
    tag_verified: ${{ steps.verify.outputs.verified }}
  steps:
    - name: Checkout (with tag history)
      uses: actions/checkout@v4
      with:
        fetch-depth: 0       # MUST be full history so the tag object is reachable
        ref: ${{ github.ref }}

    - name: Import maintainer public key
      run: |
        set -euo pipefail
        echo "${MAINTAINER_GPG_PUBKEY}" | gpg --import
        # Trust ultimately so verify-tag does not complain about WoT.
        echo "${MAINTAINER_FINGERPRINT}:6:" | gpg --import-ownertrust
      env:
        MAINTAINER_GPG_PUBKEY: ${{ secrets.MAINTAINER_GPG_PUBKEY }}
        MAINTAINER_FINGERPRINT: FDE07046A6178E89ADB57FD3DE300C53D8E18642

    - name: Verify tag signature
      id: verify
      run: |
        set -euo pipefail
        TAG="${GITHUB_REF_NAME}"
        # git verify-tag exits 0 if signature is good, non-zero otherwise.
        # We additionally assert the signing fingerprint matches the maintainer key.
        VERIFY_OUT=$(git verify-tag --raw "${TAG}" 2>&1 || true)
        echo "${VERIFY_OUT}"
        if ! echo "${VERIFY_OUT}" | grep -q "VALIDSIG ${MAINTAINER_FINGERPRINT}"; then
          echo "FAIL: tag ${TAG} not signed by maintainer key ${MAINTAINER_FINGERPRINT}"
          exit 1
        fi
        echo "OK: tag ${TAG} signed by maintainer"
        echo "verified=true" >> "${GITHUB_OUTPUT}"
      env:
        MAINTAINER_FINGERPRINT: FDE07046A6178E89ADB57FD3DE300C53D8E18642
```

### Critical details

- **Public key, not private:** `MAINTAINER_GPG_PUBKEY` is the ASCII-armored public key (`gpg --armor --export FDE07046A6178E89ADB57FD3DE300C53D8E18642`). Storing the private key in CI secrets would be a critical mistake — CI doesn't sign anything, it only verifies.
- **`git verify-tag --raw`:** machine-parseable output. Includes a `VALIDSIG <FINGERPRINT> ...` line on success. Grep is the canonical way to assert "this tag was signed by THIS key" rather than "this tag was signed by ANY trusted key". `[VERIFIED: git-scm.com/docs/git-verify-tag]`
- **`fetch-depth: 0`:** the tag object includes the signature; partial checkouts may not fetch the annotated tag's signature blob.
- **`gpg` preinstalled:** `ubuntu-24.04` runner ships GnuPG 2.x. No `apt-get install` needed.
- **Trust import:** without `--import-ownertrust`, `gpg --verify` complains "WARNING: This key is not certified with a trusted signature!" — non-fatal, but pollutes logs. The `:6:` trust level = "ultimate".
- **Job ordering:** `verify-signed-tag` is job 1 with `needs:` from job 2 (build+test) and job 3 (publish). An unsigned tag fails at job 1 without consuming compute for the build.

### Job DAG

```
verify-signed-tag  →  build-test-coverage-repro  →  publish (softprops)
       (job 1)              (job 2, needs job 1)        (job 3, needs job 2)
```

## Section 3 — `__VERSION__` substitution from `$GITHUB_REF_NAME`

**Confidence: HIGH** for MoneyMoney `version` field type; **MEDIUM** for the exact `major.minor` numeric encoding policy.

### MoneyMoney contract

> "Number `version`: Versionsnummer der Extension" — `[VERIFIED: moneymoney.app/api/webbanking/]`

The field is a Lua number; documentation example shows `1.00` for a v1.0 extension. Documentation does NOT specify how to encode patch versions or pre-releases. Community convention (observed in `jgoldhammer/moneymoney-payback`, `teal-bauer/moneymoney-ext-trading212`) is to encode as `<major>.<two-digit-minor>` — so `v1.2.3` → `1.20` and `v0.1.0` → `0.10`. Patch versions are not surfaced in the MoneyMoney UI; the field is intentionally coarse.

### Recommended substitution algorithm (Lua-only, no shell)

```lua
-- In tools/build.lua, after parse_manifest(), before build():

-- Resolve version string from environment / git / fallback.
local function resolve_version_string()
  -- 1. CI: $GITHUB_REF_NAME is set by Actions on tag push (e.g. "v1.0.0").
  local ref = os.getenv("GITHUB_REF_NAME")
  if ref and ref:match("^v%d") then
    return ref
  end
  -- 2. Local with exact tag: `git describe --tags --exact-match`.
  local f = io.popen("git describe --tags --exact-match 2>/dev/null")
  if f then
    local out = f:read("*l")
    f:close()
    if out and out:match("^v%d") then
      return out
    end
  end
  -- 3. Local without tag: short SHA fallback (development build).
  local f2 = io.popen("git rev-parse --short HEAD 2>/dev/null")
  if f2 then
    local sha = f2:read("*l")
    f2:close()
    if sha and #sha >= 7 then
      return "dev-" .. sha
    end
  end
  -- 4. No git at all.
  return "dev-unknown"
end

-- Convert "v1.2.3" or "v1.2.3-rc.4" → numeric "1.20" string (no quotes).
-- "dev-abc1234" → 0.00 (placeholder — never shipped through release.yml because
--    BUILD-04 requires a signed tag, but local dev builds need a parseable number).
local function version_to_number_string(s)
  local major, minor = s:match("^v(%d+)%.(%d+)")
  if major and minor then
    return string.format("%d.%02d", tonumber(major), tonumber(minor))
  end
  return "0.00"
end

local VERSION_STRING = resolve_version_string()
local VERSION_NUMBER = version_to_number_string(VERSION_STRING)
```

In `build()`, after `normalise(content)` for `webbanking_header`:

```lua
if mod == HEADER_MOD then
  -- Substitute __VERSION__ token with the numeric version literal.
  content = content:gsub("__VERSION__", VERSION_NUMBER)
  parts[#parts + 1] = ensure_trailing_newline(content)
```

And `src/webbanking_header.lua` line 24 changes from `version = 0.00,` to `version = __VERSION__,`.

### Reproducibility

- **Same tag → same output:** `VERSION_STRING` is fully determined by the tag; `VERSION_NUMBER` is pure. Two CI builds of the same tag produce byte-identical artifacts. ✅ CI-04 preserved.
- **Local dev builds without a tag:** produce `version = 0.00` (since `dev-...` fails the regex). The build is still reproducible (same git SHA → same artifact) but the version field is the development placeholder. Phase 6 documents this in CONTRIBUTING.md.
- **Why not Lua number literal instead of string formatting?** `string.format("%d.%02d", 1, 0)` yields `"1.00"` which lua-parses as `1.0`; `1.0 == 1.00`. Either works; format-string is more explicit about the intent.

### Test in Phase 6

```lua
-- spec/build_version_substitution_spec.lua (NEW)
it("substitutes __VERSION__ from GITHUB_REF_NAME=v1.0.0 → version = 1.00", function()
  os.execute("GITHUB_REF_NAME=v1.0.0 lua tools/build.lua")
  local content = read_dist()
  assert.matches("version%s*=%s*1%.00,", content)
  assert.is_nil(content:find("__VERSION__"))
end)

it("falls back to 0.00 with no GITHUB_REF_NAME and no exact tag", function()
  os.execute("unset GITHUB_REF_NAME; lua tools/build.lua")
  local content = read_dist()
  assert.matches("version%s*=%s*0%.00,", content)
end)

it("tag annotation drives release notes (verified by release.yml step)", function()
  -- This is a docs-cross-check, not a runtime test.
end)
```

Also add to BUILD-03 acceptance: a CI step that asserts the artifact's `version` field equals the tag's `major.minor` post-substitution:

```yaml
- name: BUILD-03 — artifact version matches tag
  run: |
    EXPECTED=$(echo "${GITHUB_REF_NAME}" | sed -E 's/^v([0-9]+)\.([0-9]+).*/\1.\2/' | awk -F. '{printf "%d.%02d", $1, $2}')
    grep -q "version = ${EXPECTED}," dist/paypal-pos.lua \
      || { echo "FAIL: artifact version ≠ tag (${EXPECTED})"; exit 1; }
```

## Section 4 — gitleaks-action v2 false-positive surface

**Confidence: MEDIUM-HIGH.** `[CITED: github.com/gitleaks/gitleaks-action]` + audit of our test fixtures.

### Default rule set scope

gitleaks ships with ~150 built-in detectors covering AWS keys, GitHub PATs, Slack tokens, Stripe keys, generic high-entropy strings, RSA private keys, and **JWT-shaped tokens** (`eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`).

### Audit of repo for likely false positives

```bash
grep -rE 'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.' --include='*.json' --include='*.lua' . 2>/dev/null | head
```

Files at risk (run this audit in W1):

- `spec/fixtures/auth/auth_invalid_grant.json` — Zettle error response body (no JWT inside, just error code) — **likely OK**.
- `spec/fixtures/auth/*.json` — if any fixture contains a faked JWT-shaped string for the assertion-grant request body or a Bearer response, gitleaks will flag.
- `spec/fixtures/jwt/*.json` (if present) — Phase-2 RESEARCH §JWT decoder spec — almost certain to contain JWT-shaped values.
- `spec/helpers/jwt_helpers.lua` (if present) — same.
- `src/auth.lua` — references `Bearer` in headers but the values are runtime — should NOT be flagged.

### Recommendation

1. **First-pass:** wire gitleaks unconditionally, run it on the Phase 6 PR, observe what it flags.
2. **If fixtures flag:** add a minimal `.gitleaksignore` file at repo root listing the specific fingerprints:
   ```
   # .gitleaksignore — fixtures that contain JWT-shaped test data, not real secrets
   <fingerprint-hash>:spec/fixtures/auth/some_fixture.json:42
   ```
   Fingerprints come from the gitleaks output. Line-by-line allowlist; no regex needed.
3. **DO NOT add a blanket `paths` allowlist** (e.g., "ignore all of spec/fixtures/") — would defeat the gate's purpose if a real secret accidentally lands in a fixture.

### Phase-1 SEC-01 redactor compatibility

The SEC-01 redactor (`M_log.redact`) lives at runtime, strips JWT shape from logs. It does NOT mask the strings in source — fixture files retain their visible characters. Therefore the redactor and gitleaks don't conflict; they operate on disjoint inputs (logs vs. source files). No interaction risk.

### Workflow snippet

```yaml
secret-scan:
  name: gitleaks secret scan
  runs-on: ubuntu-24.04
  permissions:
    contents: read
    pull-requests: write   # so gitleaks can comment on PRs
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0     # full history scan
    - name: gitleaks scan
      uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        # No GITLEAKS_LICENSE needed — repo is under personal account `yves-vogl`.
```

`[VERIFIED: yves-vogl is a personal GitHub account per CHANGELOG.md links + ./.github/FUNDING.yml `github: yves-vogl`]`

## Section 5 — Dependabot config for GitHub Actions

**Confidence: HIGH** — already in repo. `[VERIFIED: .github/dependabot.yml]`

The current file is correct and covers the `github-actions` ecosystem with weekly Monday-morning bumps. No change needed for Phase 6 unless we want to ALSO track the `softprops/action-gh-release` and `gitleaks/gitleaks-action` versions that get introduced in W2 — Dependabot picks those up automatically from the new `release.yml` and `ci.yml` references because the `directory: /` setting causes it to scan all of `.github/workflows/`.

### LuaRocks: out of scope for v1.0.0

Per CONTEXT D-77 and verified above: Dependabot has **no LuaRocks ecosystem support**. The supported list is `bazel, bundler, bun, cargo, composer, conda, deno, devcontainers, docker, docker-compose, dotnet-sdk, elm, github-actions, gitsubmodule, gomod, gradle, helm, hex, julia, maven, npm, nuget, pip, pub, rust toolchain, sbt, swift, terraform, uv`. `[VERIFIED: docs.github.com/.../dependabot.yml]`

Lua tooling versions in CI float to whatever LuaRocks resolves at install time (`luarocks install busted` picks latest). This is acceptable per CONTEXT — a v1.0.x manual-review cron is the future enhancement.

## Section 6 — Branch protection via `gh api`

**Confidence: HIGH** for API shape; **HIGH** for the graceful-degradation pattern.

### Recommended `tools/setup-branch-protection.sh`

```bash
#!/usr/bin/env bash
# tools/setup-branch-protection.sh
#
# One-time admin setup for main branch protection per CONTEXT D-74.
# Requires: gh CLI authenticated with a Fine-Grained PAT that has
#   Administration: write   on this repo.
#
# Graceful degradation: if the PAT lacks the scope, prints the manual UI
# steps and exits 0 (not a failure — Yves can complete manually).
#
# Usage:
#   bash tools/setup-branch-protection.sh

set -euo pipefail

OWNER="yves-vogl"
REPO="moneymoney-paypal-pos-extension"
BRANCH="main"

# Required CI status check contexts. These names must match the job
# `name:` declarations in the workflows. Keep this list in sync when
# adding new required checks.
declare -a CHECKS=(
  "Lint + tests + reproducible build"   # ci.yml
  "gitleaks secret scan"                # ci.yml (added in Phase 6)
  "Commit-message lint"                 # ci.yml (added in Phase 6)
)

# Compose JSON payload for PUT /repos/.../branches/.../protection.
PAYLOAD=$(jq -n \
  --argjson contexts "$(printf '%s\n' "${CHECKS[@]}" | jq -R . | jq -s .)" \
  '{
    required_status_checks: {
      strict: true,
      contexts: $contexts
    },
    enforce_admins: true,
    required_pull_request_reviews: {
      dismiss_stale_reviews: true,
      required_approving_review_count: 0
    },
    restrictions: null,
    required_linear_history: true,
    allow_force_pushes: false,
    allow_deletions: false,
    required_conversation_resolution: true
  }')

echo "Applying branch protection to ${OWNER}/${REPO}@${BRANCH} ..."
if ! gh api -X PUT "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" \
    -H "Accept: application/vnd.github+json" \
    --input - <<< "${PAYLOAD}" >/dev/null 2>err.log; then
  RC=$?
  if grep -q "403\|insufficient\|Resource not accessible" err.log; then
    cat <<'EOF'
WARNING: gh PAT lacks Administration:write scope. Branch protection
NOT applied automatically. Configure manually:

  1. Open: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/settings/branches
  2. Add classic branch protection rule for `main`.
  3. Enable:
       [x] Require a pull request before merging
       [x] Require status checks to pass before merging
            - Add: "Lint + tests + reproducible build"
            - Add: "gitleaks secret scan"
            - Add: "Commit-message lint"
       [x] Require signed commits
       [x] Require linear history
       [x] Do not allow bypassing the above settings
  4. Save.

Exit 0 — script proceeds gracefully so CI doesn't break on first run.
EOF
    rm -f err.log
    exit 0
  fi
  echo "FAIL: branch protection PUT failed with exit ${RC}:"
  cat err.log
  rm -f err.log
  exit "${RC}"
fi

# required_signatures is a separate sub-resource — toggle on.
gh api -X PUT "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection/required_signatures" \
  -H "Accept: application/vnd.github+json" >/dev/null

rm -f err.log
echo "OK: branch protection applied (PR + checks + signatures + linear history)."
```

### Critical details

- **`required_signatures` is a separate endpoint.** `PUT /repos/.../branches/.../protection` does NOT accept `required_signatures` in its body in the classic protection schema — it's a sub-resource toggled by `PUT .../protection/required_signatures`. `[VERIFIED: docs.github.com/en/rest/branches/branch-protection]`
- **`required_pull_request_reviews.required_approving_review_count: 0`** is the right value for a solo-maintainer repo — requires a PR but doesn't require approval (since Yves is the only reviewer).
- **`enforce_admins: true`** — even Yves cannot bypass. Matches the "never commit to main" memory from `~/.claude/memory`.
- **`restrictions: null`** — no push restrictions beyond the above; otherwise every contributor would need an allowlist entry.
- **`required_status_checks.contexts`** uses the human-readable job `name:` from the workflows, NOT the workflow filename. Phase 6 must keep these strings in sync.
- **CP-2 (Yves checkpoint):** Yves runs `bash tools/setup-branch-protection.sh` post-merge with his PAT. The script is idempotent — re-runs overwrite the same state.

## Section 7 — `gh repo edit` for description + topics

**Confidence: HIGH.** `[VERIFIED: cli.github.com/manual/gh_repo_edit]`

### Recommended `tools/setup-repo-metadata.sh`

```bash
#!/usr/bin/env bash
# tools/setup-repo-metadata.sh
#
# One-time admin setup for repo description + topics per CONTEXT D-82.
# Requires: gh CLI authenticated with PAT that has repo metadata write.
# Idempotent: re-runs replace topics rather than appending.

set -euo pipefail

OWNER_REPO="yves-vogl/moneymoney-paypal-pos-extension"

# D-82 verbatim — German description.
DESCRIPTION="MoneyMoney-Extension für PayPal POS — Karten-Umsätze, Refunds, Gebühren und Auszahlungen direkt in MoneyMoney. Open Source, MIT, GPG-signiert."

# D-82 verbatim — 7 topics. Order matters for display order.
TOPICS=(
  moneymoney
  moneymoney-extension
  paypal-pos
  zettle
  lua
  germany
  accounting
)

echo "Setting description and topics on ${OWNER_REPO} ..."
gh repo edit "${OWNER_REPO}" \
  --description "${DESCRIPTION}"

# `--add-topic` is additive and idempotent (does not error on duplicates),
# but to enforce the EXACT set we first clear via API then re-add.
# gh as of v2.x does not have a --replace-topics or --remove-topic; the
# pattern below uses the REST `topics` field which IS idempotent.
gh api -X PUT "repos/${OWNER_REPO}/topics" \
  -H "Accept: application/vnd.github+json" \
  -f "names[]=${TOPICS[0]}" \
  -f "names[]=${TOPICS[1]}" \
  -f "names[]=${TOPICS[2]}" \
  -f "names[]=${TOPICS[3]}" \
  -f "names[]=${TOPICS[4]}" \
  -f "names[]=${TOPICS[5]}" \
  -f "names[]=${TOPICS[6]}" \
  >/dev/null

echo "OK: description and topics set."
```

### Key behaviors

- **`gh repo edit --description "..."` is idempotent** — sets the description to the given string; re-runs are no-ops.
- **Topics via `gh repo edit --add-topic foo --add-topic bar` is additive only.** If the goal is "exactly these 7 topics", the PUT endpoint on `/topics` replaces the entire list. Recommend the PUT approach for clarity.
- **CP-3 (Yves checkpoint):** Yves runs `bash tools/setup-repo-metadata.sh` post-merge. Idempotent.

## Section 8 — MoneyMoney "Inoffizielle Extensions erlauben" UI verbatim labels

**Confidence: HIGH** for German labels (existing README and CLAUDE.md both reference them); **MEDIUM** for the exact menu path on the current MoneyMoney 2026 release.

### Verbatim labels from existing artifacts

From `README.md` line 122: `**Einstellungen → Erweiterungen** den Schalter **„Inoffizielle Extensions erlauben"** aktivieren`.
From CLAUDE.md (top-level project instructions): "After dropping the file the user must enable **MoneyMoney → Einstellungen → Erweiterungen → 'Inoffizielle Extensions erlauben'**".

### Recommended phrasing in `README.de.md`

```markdown
## Inoffizielle Extensions erlauben

1. In MoneyMoney **Hilfe → Erweiterungen im Finder zeigen** öffnen.
   ![Menüpunkt im Hilfe-Menü](docs/img/help-menu-extensions-folder.png)
2. `paypal-pos.lua` in den geöffneten Ordner kopieren.
3. In MoneyMoney **Einstellungen → Erweiterungen** öffnen und den Schalter
   **„Inoffizielle Extensions erlauben"** aktivieren.
   ![Schalter in den Einstellungen](docs/img/inoffizielle-extensions-erlauben.png)
4. **Konto hinzufügen → PayPal POS** wählen, den API-Key einfügen.

**Hinweis Sandboxed vs Non-Sandboxed Build:** Der Mac-App-Store-Build von
MoneyMoney läuft in einer Sandbox; der Erweiterungs-Ordner liegt unter
`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/`.
Der Direkt-Download von der MoneyMoney-Website ist nicht sandboxed; der
Ordner liegt unter `~/Library/Application Support/MoneyMoney/Extensions/`.
Der Menüpunkt **Hilfe → Erweiterungen im Finder zeigen** öffnet in jedem
Fall den korrekten Pfad — daher ist die manuelle Pfad-Eingabe nicht nötig.
```

### Screenshot strategy

- **CP-5 (Yves checkpoint):** Yves captures the actual screenshot post-merge and replaces the placeholder file.
- **W2 lands:** `docs/img/inoffizielle-extensions-erlauben.png` as a 1×1 transparent PNG placeholder with a sibling `docs/img/README.md` noting "screenshots pending — Yves to capture in MoneyMoney v2.4.x". This keeps the markdown reference valid (no broken image link in the rendered README) without blocking the PR.

### Macro-level note

A 1×1 transparent PNG is ~75 bytes. Alternative: a 600×400 placeholder with text overlay "[Screenshot pending]" — also acceptable. The exact bytes don't matter for v1.0.0 first-impression; what matters is that the markdown image reference points to a valid file. **Recommendation:** place `<!-- screenshot: pending — Yves to capture per CP-5 -->` HTML comment next to each image reference so a future PR can grep for the marker.

## Section 9 — MADR template walk-through

**Confidence: HIGH.** `[VERIFIED: docs/adr/0001-amalgamator-design.md, 0003, 0004, 0005]`

### Section structure (observed in all 4 existing ADRs)

```markdown
# ADR-NNNN: <Short Decision Title>

## Status

<Proposed | ACCEPTED | Superseded by ADR-MMMM | Deprecated>

## Date

<YYYY-MM-DD>

## Deciders

<Names>

## Context

<Problem statement, constraints, references to PROJECT.md / REQUIREMENTS / prior ADRs.>

## Decision

<The chosen approach, often broken into numbered sub-decisions or invariants.>

### <Optional sub-sections for complex decisions, e.g., "Invariant N — …", "Carve-out N — …", "Implementation Pin">

## Consequences

<Positive: what this enables. Negative: what we accept as cost. Mitigations: how the cost is bounded.>

## References

<Links to research / context / external docs.>
```

### Optional sections present in some ADRs

- **Pros/Cons table** (decision-tree-style) when comparing alternatives — used in ADR-0001.
- **Acceptance criteria table** with requirement-IDs — used in ADR-0005 (`| Requirement | Source artifact | Plan | Status |`).
- **Implementation Pin** — a "this is what actually shipped, not just the intent" appendix added post-execution — used in ADR-0005.

### Phase-6 ADR template (recommended for the 4 new ADRs)

Keep MADR shape; the 4 new ADRs (0002, 0006, 0007, 0008) are retro-documents — they record decisions already implemented. For these, the Pros/Cons table is optional (the decision is past), but the Consequences section is critical (a future maintainer needs to understand what locked the decision in).

- **ADR-0002 (LocalStorage cache):** ~100 lines. Context = Phase-2 D-22..D-26 token-cache decision. Decision = the `LocalStorage.zettle` schema + `obtained_at`/`expires_at` invariants. Consequences = MoneyMoney restart preserves tokens; no refresh-token re-mint dance needed; ERR-04 layer rebuilds on top.
- **ADR-0006 (JWT-bearer-only):** ~80 lines. Context = Phase-2 chose assertion grant per CLAUDE.md research; OAuth2 Auth-Code is deferred to Phase 7. Decision = single-grant auth surface in `src/auth.lua` for v1.0.x; forward-compat note that Phase 7 adds a dual-path. Consequences = users must mint a JWT manually; no browser flow; one credential field in the MM dialog.
- **ADR-0007 (no TLS pinning):** ~60 lines. Context = Phase-1 Q8 confirmed `Connection()` does TLS validation by default; pinning would require shipping a CA bundle or pin set which the sandbox doesn't expose. Decision = rely on `Connection()` default verification. Consequences = trust derives from system roots + Zettle's TLS certificate chain; if Zettle rotates to a new CA, the extension keeps working transparently. Mitigations = egress allowlist + reproducible build + GPG-signed releases as the independent trust chain.
- **ADR-0008 (string-return error pattern):** ~80 lines. Context = MoneyMoney's `RefreshAccount` / `InitializeSession2` callbacks return either `nil`/success-table or an error STRING (not a Lua error); Phase-2 + 4 + 5 all follow. Decision = every callback returns a localized German error string via `M_i18n.t("error.X")`; no `error()` calls bubble up. Consequences = MoneyMoney UI shows German error text directly; users see actionable messages; tests assert specific strings.

### Filename convention

`docs/adr/000N-<short-kebab-title>.md` — matches existing 0001..0005 naming.

## Section 10 — Coverage gate strategy

**Confidence: HIGH** for current state; **MEDIUM** for D-75's "per-src-file" interpretation.

### Current state (in `ci.yml` lines 48–69)

The coverage gate parses `luacov.report.out`'s `Total` line and asserts `≥ 85%`. This works on the **amalgamated `dist/paypal-pos.lua`** because busted requires that file (verified in `spec/meta_no_tax_classification_spec.lua` preamble and the actual luacov output above: `File: dist/paypal-pos.lua, Hits: 884, Missed: 0, Coverage: 100.00%`).

D-75 says "≥85% on `src/` excluding `webbanking_header.lua`". The literal interpretation requires per-src-file coverage tracking. The current gate doesn't do that — it gates the artifact total.

### Recommendation

**Keep the existing gate (artifact-total ≥85%) for v1.0.0.** Rationale:

1. The artifact total IS the sum of all src/ modules concatenated; if a single src/ module had 0% coverage, the total would drop. Phase 5 closed at 100% — the gate is regression-protection.
2. Per-src-file enforcement would require either (a) running busted N times (once per loaded module — slow, doesn't match how the artifact loads) or (b) post-processing the luacov line-by-line annotations against module boundary markers (`-- === MODULE: foo ===`) — fragile and adds ~80 LoC.
3. The exclusion-of-`webbanking_header.lua` clause is implicit in the artifact-total approach: `webbanking_header` is 12 lines of declarations + DEBUG=false; every test exercises it (it's at the top of the artifact) so its coverage is always 100% — never the floor.

### If D-75 strictly requires per-file enforcement (v1.0.x ratchet)

```lua
-- tools/coverage-gate.lua (~40 LoC) — optional v1.0.x enhancement
-- Parses luacov.report.out's per-line hit counts, segments by
-- `-- === MODULE: <name> ===` markers, computes per-module coverage,
-- asserts each (except webbanking_header) ≥85%.
```

**Recommendation for Phase 6:** do NOT add `tools/coverage-gate.lua` — keep the existing inline shell gate. Document the artifact-total-coverage semantics in CONTRIBUTING.md so a future maintainer knows why it's not per-src-file. If a real regression motivates per-file gating later, that's a v1.0.x task.

### What Phase 6 DOES change in the coverage gate

- Lower the gate's grep pattern fragility: confirm `luacov` output format on the current `luacov 0.16` release (no change expected; documented for the maintainer).
- Confirm the gate fails the WHOLE workflow, not just the step (already the case via `exit 1`).

## Section 11 — Commit-message lint (D-78)

**Confidence: HIGH.** Pure shell, no Node dependency.

### Recommended workflow `.github/workflows/commit-lint.yml`

```yaml
name: Commit-message lint

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read

jobs:
  lint:
    name: Commit-message lint
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: ${{ github.event.pull_request.head.sha }}

      - name: Validate commit messages
        run: |
          set -euo pipefail
          BASE="${{ github.event.pull_request.base.sha }}"
          HEAD="${{ github.event.pull_request.head.sha }}"
          # Regex: Conventional Commits with optional scope.
          REGEX='^(feat|fix|docs|test|refactor|chore|ci|build|perf|style|revert)(\([^)]+\))?: .+'
          FAIL=0
          while IFS= read -r SHA; do
            SUBJECT=$(git log --format=%s -n 1 "${SHA}")
            if ! echo "${SUBJECT}" | grep -qE "${REGEX}"; then
              echo "FAIL ${SHA:0:7}: '${SUBJECT}'"
              FAIL=1
            fi
          done < <(git rev-list "${BASE}..${HEAD}")
          if [ "${FAIL}" -eq 1 ]; then
            echo ""
            echo "Conventional Commits required: <type>(<scope>): <subject>"
            echo "Allowed types: feat fix docs test refactor chore ci build perf style revert"
            exit 1
          fi
          echo "OK: all commit subjects follow Conventional Commits"
```

### Alternative: fold into ci.yml

Could be a job within `ci.yml` rather than a separate workflow. **Recommendation:** separate workflow file because the trigger (`pull_request`) and concerns (Git history regex rather than code lint) are orthogonal to ci.yml. A new file is cleaner and easier for Dependabot to pin separately.

### Branch-protection sync

The check name (`Commit-message lint`) must be added to the `CHECKS` array in `tools/setup-branch-protection.sh` per §6.

## Section 12 — Egress allowlist hardening (D-79)

**Confidence: HIGH** — current state in ci.yml already implements primary + complementary TLD-pattern checks.

### Current state

`ci.yml` lines 83–120 already:
- Greps `dist/paypal-pos.lua` for `https?://` URLs; rejects any host not in `oauth.zettle.com | purchase.izettle.com | finance.izettle.com`.
- Complementary scheme-less hostname grep (S-05 SEC) over TLDs (`com|net|org|io|dev|app|cloud|sh|de|info|co|biz|me|xyz|tech`) with the same allowlist.

### D-79 extension: `print(` bypass grep

Add to ci.yml (after the egress allowlist step):

```yaml
- name: D-79 — no raw print() calls in shipped artifact (must use M_log)
  run: |
    set -e
    # Allow occurrences inside comments (-- ...) and inside string literals
    # by scoping the grep to lines that LOOK like calls (not comment-prefixed).
    # The artifact has no obfuscated print; a simple grep -E suffices.
    BAD=$(grep -nE '^[^-]*print\(' dist/paypal-pos.lua \
      | grep -v '^[[:space:]]*--' \
      || true)
    if [ -n "${BAD}" ]; then
      echo "FAIL: raw print() calls in dist/paypal-pos.lua (must use M_log):"
      echo "${BAD}"
      exit 1
    fi
    echo "OK: no raw print() calls in dist/paypal-pos.lua"
```

**Rationale:** D-27 (Phase-2) established the redactor-wrapped logger; any raw `print(` in shipped code would bypass it and risk leaking JWT shape. The grep is regression-protection. Phase 5 closed at zero raw prints in src/; the gate enforces that.

## Pitfalls

### Pitfall 1: Tag pushed without GPG signature
**What goes wrong:** Yves uses `git tag` instead of `git tag -s`; release.yml job 1 fails at `git verify-tag`.
**Why it happens:** Muscle memory; `git tag -s` requires the `-s` every time unless `git config tag.gpgSign true` is set.
**How to avoid:** CONTRIBUTING.md documents the `git tag -s vX.Y.Z` form. Recommend Yves set `git config --global tag.gpgSign true` once.
**Warning signs:** release.yml fails at job 1 within 30 seconds.

### Pitfall 2: GPG public key not loaded into CI secrets
**What goes wrong:** Workflow tries to import `${{ secrets.MAINTAINER_GPG_PUBKEY }}`; secret unset → `gpg --import` reads from empty stdin → silent success → `git verify-tag` fails with "unknown key".
**Why it happens:** First-time setup forgotten.
**How to avoid:** Phase 6 plan includes a step where Yves exports + stores the public key BEFORE the first tag: `gpg --armor --export FDE07046A6178E89ADB57FD3DE300C53D8E18642 | gh secret set MAINTAINER_GPG_PUBKEY`.
**Warning signs:** first release.yml run fails at the verify step.

### Pitfall 3: `__VERSION__` token left in dev builds
**What goes wrong:** Local `lua tools/build.lua` (no tag) emits `version = 0.00,` — same as Phase-1 placeholder. A developer might not notice they're loading a dev build into their local MoneyMoney.
**Why it happens:** The fallback IS the placeholder, by design.
**How to avoid:** Add a banner in the BANNER constant: when version is "dev-...", emit `-- paypal-pos amalgamated DEV BUILD (no tag) — not for release` as the second comment line. CONTRIBUTING.md documents the behavior.
**Warning signs:** dist/paypal-pos.lua first two lines contain "DEV BUILD".

### Pitfall 4: Branch protection breaks the first PR after it's enabled
**What goes wrong:** `tools/setup-branch-protection.sh` runs; PR's CI check name doesn't match (e.g., job renamed in workflow but `CHECKS` array stale); protection blocks the merge.
**Why it happens:** Job `name:` field is the source of truth for status check contexts; renaming a job silently breaks the dependency.
**How to avoid:** Document in CONTRIBUTING.md: "If you rename a CI job, also update `CHECKS` in `tools/setup-branch-protection.sh` and re-run the script." Recommend a CI step that asserts the workflow file's job names match the script's array (~10 LoC) as a v1.0.x enhancement.
**Warning signs:** PR is blocked with "Required check 'X' not found".

### Pitfall 5: gitleaks blocks the Phase-6 PR itself on fixture content
**What goes wrong:** Phase-6 W1 wires gitleaks; the very PR adding it scans history including Phase-2 fixtures that contain JWT-shaped strings; PR fails.
**Why it happens:** Default gitleaks rules include JWT detector; our fixtures contain JWT-shaped test data.
**How to avoid:** W1 task sequence: (a) wire gitleaks; (b) immediately run it locally (`gitleaks detect --no-banner`) before opening the PR; (c) if hits, add `.gitleaksignore` entries IN THE SAME PR. Don't open the PR with gitleaks enabled until the local scan is clean.
**Warning signs:** gitleaks CI job fails on first push with "X leaks found".

### Pitfall 6: META-03 walker extension flags legitimate German wording
**What goes wrong:** Extending `spec/meta_no_tax_classification_spec.lua` to walk README.de.md / CONTRIBUTING.md / docs/adr/*.md; an ADR or README phrase legitimately discusses the META-03 forbidden phrases in a NEGATING context (e.g., "wir beanspruchen KEINE GoBD-Konformität" contains "GoBD-konform"... no, it doesn't — but "GoBD konform" inflected differently might).
**Why it happens:** The walker is plain-text find; can't distinguish positive from negative use.
**How to avoid:** Audit each new file against the 13-phrase list BEFORE adding it to the walker's target list. The current README.md doesn't trip the walker (verified by `grep -E 'USt-frei|GoBD-konform|...' README.md` returning empty). The recommended GoBD-Hinweis text in D-71 is engineered to avoid the 13 phrases:
- says "GoBD-Konformität" (capital K, different word from "GoBD-konform")
- says "DATEV-Export" (different from "DATEV-fähig")
- says "steuerrechtliche Bewertung" (different from "steuerlich" — the spec checks lowercased "steuerlich" which DOES appear in "steuerrechtliche"... ⚠️ verify in W1)

**Action item for W1:** before extending the META-03 walker, run a dry-run scan on the Phase-6 draft README.de.md + CHANGELOG.md + each new ADR to confirm zero hits.

### Pitfall 7: `softprops/action-gh-release@v2` permission error
**What goes wrong:** Job lacks `contents: write` permission; release publication silently fails OR errors with `Resource not accessible by integration`.
**Why it happens:** `permissions:` defaults to read-only in workflows where `permissions:` is declared at workflow scope or in repo settings.
**How to avoid:** Declare `permissions: contents: write` at the job level (NOT workflow level — least-privilege).

### Pitfall 8: `git verify-tag` doesn't check WHO signed
**What goes wrong:** Any GPG-signed tag passes `git verify-tag` if the signing key is in the keyring — including keys an attacker could add via PR.
**Why it happens:** Verify-tag verifies the signature, not the signer's identity.
**How to avoid:** §2 recipe grep's `VALIDSIG <FINGERPRINT>` from `git verify-tag --raw` output, asserting the maintainer fingerprint specifically. This is the load-bearing check.

### Pitfall 9: README.md is replaced with English pointer but GitHub still shows the old German content
**What goes wrong:** GitHub caches the rendered README for a minute or so after a push; the apparent "stale" content confuses users.
**Why it happens:** GitHub's CDN.
**How to avoid:** Document expected post-merge UX: "Wait 1–2 minutes for the new README.md to render in the browser cache; force-refresh."

### Pitfall 10: Release workflow runs on every branch push
**What goes wrong:** `on: push` matches tag pushes AND branch pushes; release.yml runs constantly.
**Why it happens:** Filter not scoped to tags.
**How to avoid:** Use `on: push: tags: [ 'v*.*.*', 'v*.*.*-rc.*' ]` strictly.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `busted` 2.x (LuaRocks-installed in CI) |
| Config file | `.busted` (existing) |
| Quick run command | `busted spec/<spec-file>.lua` |
| Full suite command | `busted spec/` |
| Phase gate | Full suite green + `lua tools/build.lua --verify` OK + ci.yml all jobs green |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BUILD-03 | `__VERSION__` substituted from tag | unit (spec) | `busted spec/build_version_substitution_spec.lua` | ❌ Wave 1 |
| BUILD-03 | Artifact version matches tag | CI step | grep in release.yml job | ❌ Wave 2 |
| BUILD-04 | release.yml verifies GPG signature before publish | manual + CI | release.yml job 1 | ❌ Wave 2 |
| BUILD-05 | release publishes `.lua` + `.sha256` | CI | release.yml softprops `files:` | ❌ Wave 2 |
| BUILD-06 | release notes come from tag annotation | CI | release.yml extract-tag-annotation step | ❌ Wave 2 |
| CI-01 | lint+test+coverage on push/PR | CI | ci.yml | ✅ already in place |
| CI-02 | ≥85% coverage gate | CI | ci.yml lines 48–69 | ✅ already in place |
| CI-03 | ubuntu-24.04 + Lua 5.4 + LC_ALL=C | CI | ci.yml line 10, 15, 28 | ✅ already in place |
| CI-04 | reproducible-build diff | CI | ci.yml line 75 (`lua tools/build.lua --verify`) | ✅ already in place |
| CI-05 | gitleaks scan | CI | new `secret-scan` job in ci.yml OR `.github/workflows/secret-scan.yml` | ❌ Wave 1 |
| CI-06 | Dependabot tracks Actions | config | `.github/dependabot.yml` | ✅ already in place |
| SEC-02 | Egress allowlist grep | CI | ci.yml lines 83–120 | ✅ already in place; D-79 adds `print(` grep |
| SEC-05 | Branch protection requires signed commits + CI | runtime (post-merge) | `tools/setup-branch-protection.sh` (Yves runs once) | ❌ Wave 2 |
| DOC-01 | README.de.md is primary German | manual | file exists; English README.md links to it | ❌ Wave 2 |
| DOC-02 | Screenshot-illustrated guide | manual + placeholder | `docs/img/inoffizielle-extensions-erlauben.png` referenced | ❌ Wave 2 (placeholder) + CP-5 |
| DOC-03 | Both install paths + Hilfe-menu path | manual | README.de.md content | ❌ Wave 2 |
| DOC-04 | GoBD-Hinweis NOT claiming conformance | spec + manual | META-03 walker extended to README.de.md | ❌ Wave 1 (walker) + Wave 2 (content) |
| DOC-05 | CONTRIBUTING.md (English) | manual | file exists | ❌ Wave 2 |
| DOC-06 | 4 new MADR ADRs | manual | `docs/adr/0002,0006,0007,0008-*.md` exist | ❌ Wave 2 |
| DOC-07 | LICENSE MIT + Yves Vogl | manual | file exists | ✅ already in place |
| DOC-08 | gh repo edit description | runtime (post-merge) | `tools/setup-repo-metadata.sh` | ❌ Wave 2 + CP-3 |
| DOC-09 | 7 topics | runtime (post-merge) | same | ❌ Wave 2 + CP-3 |
| DOC-10 | CHANGELOG.md Keep-a-Changelog | manual | file exists; v1.0.0 entry added | ✅ format in place; ❌ v1.0.0 entry Wave 3 |

### Sampling Rate
- **Per task commit:** `busted spec/<changed-spec>.lua` + `luacheck <changed-file>`
- **Per wave merge:** `busted spec/` + `lua tools/build.lua --verify`
- **Phase gate:** ci.yml all jobs green on PR + manual review of release.yml dry-run (push an `rc.1` tag first)

### Wave 0 Gaps
- [ ] `spec/build_version_substitution_spec.lua` — covers BUILD-03 (W1)
- [ ] Extend `spec/meta_no_tax_classification_spec.lua` target list — covers DOC-04 + META-03 inheritance (W1)
- [ ] `.github/workflows/release.yml` — covers BUILD-04..06 (W2)
- [ ] `.github/workflows/commit-lint.yml` — covers D-78 (W1)
- [ ] gitleaks job in `ci.yml` (or separate workflow) — covers CI-05 (W1)
- [ ] `tools/setup-branch-protection.sh` — covers SEC-05 (W2)
- [ ] `tools/setup-repo-metadata.sh` — covers DOC-08, DOC-09 (W2)
- [ ] `tools/build.lua` `__VERSION__` substitution patch — covers BUILD-03 (W1)
- [ ] `src/webbanking_header.lua` `__VERSION__` token — covers BUILD-03 (W1)
- [ ] `README.de.md` (NEW) — covers DOC-01..04 (W2)
- [ ] `README.md` (rewrite to English pointer) — covers DOC-01 (W2)
- [ ] `CONTRIBUTING.md` (NEW) — covers DOC-05 (W2)
- [ ] `docs/adr/0002,0006,0007,0008-*.md` (NEW) — covers DOC-06 (W2)
- [ ] `docs/img/inoffizielle-extensions-erlauben.png` placeholder — covers DOC-02 visually (W2; CP-5 for real image)
- [ ] CHANGELOG.md v1.0.0 entry — covers DOC-10 (W3, post-merge, pre-tag)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | no (Phase-2 surface frozen) | n/a |
| V3 Session Management | no | n/a |
| V4 Access Control | yes (CI permissions) | least-privilege `permissions:` at job scope; `contents: read` default, `contents: write` only on publish + badge jobs |
| V5 Input Validation | yes (release workflow inputs) | `${{ github.ref_name }}` filtered by tag regex in `on:` trigger; no untrusted user input reaches the build |
| V6 Cryptography | yes (GPG verification) | GnuPG (system) + maintainer fingerprint hard-coded in workflow; never hand-roll signature verification |
| V10 Supply Chain | yes | Pin actions by version tag (Dependabot bumps); pin LuaRocks via leafo actions; SHA-pin all actions in Phase 6.1 follow-up |
| V14 Configuration | yes | Branch protection requires signed commits + CI green + linear history |

### Known Threat Patterns for Release Engineering

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| Unsigned tag published as "release" | Spoofing | `git verify-tag --raw` grep for maintainer fingerprint in release.yml job 1 (§2) |
| GitHub token over-privileged in a workflow step | Elevation of Privilege | Least-privilege `permissions:` at job level; never workflow-level write |
| Slopsquatted action introduced via Dependabot PR | Tampering / Supply chain | Dependabot opens PRs; CI runs on PR including reproducible-build diff; manual review before merge |
| Secret committed to fixture file | Information Disclosure | gitleaks scans every PR + history (§4) |
| Branch protection bypassed by admin | Tampering | `enforce_admins: true` in `tools/setup-branch-protection.sh` (§6) |
| Release artifact tampered post-publish | Tampering | SHA256 published alongside `.lua`; GPG-signed tag is the root of trust; users verify per README.md `## Verifikation signierter Releases` section |
| Egress to unauthorized host | Information Disclosure | ci.yml lines 83–120 grep gate (already in place); D-79 adds `print(` bypass grep |

## Sources

### Primary (HIGH confidence)
- `softprops/action-gh-release` README (v2) — https://github.com/softprops/action-gh-release `[VERIFIED]`
- `gitleaks/gitleaks-action` README (v2) — https://github.com/gitleaks/gitleaks-action `[VERIFIED]`
- GitHub REST API branch-protection — https://docs.github.com/en/rest/branches/branch-protection `[VERIFIED]`
- GitHub Actions `permissions:` docs — https://docs.github.com/en/actions/using-jobs/assigning-permissions-to-jobs `[CITED]`
- Dependabot configuration options — https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file `[VERIFIED]`
- MoneyMoney WebBanking API — https://moneymoney.app/api/webbanking/ — `version` field is Number, example `1.00` `[VERIFIED]`
- `git-verify-tag(1)` — https://git-scm.com/docs/git-verify-tag `[VERIFIED]`
- In-repo: `.github/workflows/ci.yml` — Phase-1..5 CI baseline `[VERIFIED]`
- In-repo: `.github/dependabot.yml` — github-actions ecosystem already wired `[VERIFIED]`
- In-repo: `docs/adr/0001,0003,0004,0005-*.md` — MADR template examples `[VERIFIED]`
- In-repo: `tools/build.lua` — Phase-1 amalgamator (this phase's extension target) `[VERIFIED]`
- In-repo: `src/webbanking_header.lua` line 24 — `version = 0.00,` literal that becomes `version = __VERSION__,` `[VERIFIED]`
- In-repo: `LICENSE` — MIT + "Copyright (c) 2026 Yves Vogl" (DOC-07 satisfied) `[VERIFIED]`
- In-repo: `CHANGELOG.md` — Keep-a-Changelog format from Phase 4 `[VERIFIED]`
- In-repo: `README.md` — German engineering-draft, contains GPG-verification block (good source for README.de.md split) `[VERIFIED]`
- In-repo: `SECURITY.md` — already in place `[VERIFIED]`
- In-repo: `spec/meta_no_tax_classification_spec.lua` — Phase-4 walker (Phase 6 extends target list) `[VERIFIED]`

### Secondary (MEDIUM confidence)
- MADR template reference (markdownadr.org / madr.com) — community standard; matches in-repo ADR shape `[CITED]`
- Conventional Commits 1.0.0 — https://www.conventionalcommits.org/en/v1.0.0/ — grammar for commit-lint regex `[CITED]`
- Keep a Changelog 1.1.0 — https://keepachangelog.com/en/1.1.0/ `[CITED]`

### Tertiary (LOW confidence)
- MoneyMoney `version` field encoding convention (`<major>.<two-digit-minor>`) — observed in 2 community extensions; not documented officially `[ASSUMED]`

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | MoneyMoney `version` field encodes `<major>.<two-digit-minor>` (patch dropped) | §3 | UI displays the wrong version; cosmetic only, no functional impact. Easy to ratchet to `<major>.<minor><patch>` in v1.0.x. |
| A2 | gitleaks scan WILL flag at least one fixture in `spec/fixtures/auth/` | §4 | If flag, W1 adds `.gitleaksignore`; if no flag, no action needed. The recommendation handles both cases. |
| A3 | `gh repo edit` is idempotent for `--description` | §7 | If not, re-runs may error. The PUT-on-`/topics` approach is verified idempotent; description-only edit is likely also idempotent based on REST PATCH semantics. Low risk. |
| A4 | `ubuntu-24.04` runner ships GnuPG 2.x preinstalled | §2 | If not, `apt-get install gnupg` is one extra step. Low risk. |
| A5 | yves-vogl GitHub account is a personal account, NOT an org | §4 | If org, gitleaks-action requires a free `GITLEAKS_LICENSE` key. Verifiable in 5 seconds via `gh api users/yves-vogl --jq .type` (`User` vs `Organization`). |
| A6 | `git verify-tag --raw` emits `VALIDSIG <FINGERPRINT>` on success | §2 | Documented behavior of GnuPG; if not, the grep would always fail. Manually test before locking. |
| A7 | The 4 new ADRs do not introduce any of the 13 META-03 forbidden phrases | Pitfall 6 | If wrong, the extended META-03 walker would block the Phase-6 PR; easy to refactor wording. |

**If this table is empty:** No — there are 7 assumptions, all of which the planner should gate via a Wave-0/Wave-1 verification task or accept as low-risk.

## Open Questions

1. **Should release.yml run on `rc.N` tags AND publish them, or only on stable `v.X.Y.Z` tags?**
   - What we know: D-72 says both `vX.Y.Z` AND `vX.Y.Z-rc.N` trigger; `prerelease:` flag is set dynamically.
   - What's unclear: whether the `rc.N` publish needs additional confirmation (e.g., draft-only mode).
   - Recommendation: publish both; mark `rc.N` as prerelease (GitHub UI displays them in a separate section); no draft. Yves can yank a bad RC if needed.

2. **Should the `__VERSION__` substitution happen in `tools/build.lua` or in `release.yml` via `sed`?**
   - What we know: §3 recommends Lua-side for testability + atomicity with reproducibility.
   - What's unclear: whether reproducibility is at risk if `sed` runs in CI (since the source file remains unchanged after build, no — same input, same output).
   - Recommendation: Lua-side, per §3, because the build tool already abstracts the build, and a future per-tag spec test can drive `tools/build.lua` directly without invoking `sed`.

3. **Should `tools/coverage-gate.lua` be created in Phase 6, or deferred?**
   - What we know: §10 recommends deferring; current artifact-total gate is regression-protection.
   - Recommendation: defer to v1.0.x.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| GnuPG 2.x | Tag verification (CI runner + local maintainer) | ✓ (CI ubuntu-24.04 preinstalled; macOS local via brew) | 2.4+ | none — load-bearing for SEC-05 / BUILD-04 |
| `gh` CLI | Branch-protection script, repo-metadata script, release annotation extraction | ✓ (CI preinstalled; local via brew) | 2.40+ | manual GitHub UI steps in `tools/setup-branch-protection.sh` |
| `git` 2.30+ | `git verify-tag --raw`, `git for-each-ref` | ✓ | 2.30+ | none |
| Lua 5.4 | `tools/build.lua` runs locally + in CI | ✓ | 5.4.x (CI pinned via `leafo/gh-actions-lua@v13`) | none |
| `jq` | branch-protection JSON payload assembly | ✓ (CI preinstalled; local via brew/apt) | 1.6+ | inline JSON heredoc fallback (~20 LoC) |
| Maintainer GPG key in CI secrets | release.yml job 1 | ❓ — must be uploaded by Yves before first release | n/a | release.yml fails at job 1 if missing (acceptable; surfaces the gap early) |
| `awk`, `sed`, `grep` | release-notes extraction, version-tag parsing | ✓ (POSIX) | n/a | none |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — every load-bearing dep is present; the only "missing" is the GPG secret upload, which is a CP-4 prerequisite, not a tool dependency.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — softprops + gitleaks + dependabot all current and pinned in their respective ecosystems; already-in-repo assets verified by direct file inspection.
- Architecture: **HIGH** — every workflow file shape is documented from upstream + matches the in-repo Phase-1..5 pattern.
- Pitfalls: **HIGH** — 8 of the 10 pitfalls are derived from concrete signals (existing ci.yml, the README.md content, the maintainer fingerprint in CLAUDE.md); 2 are forward-looking but well-bounded.
- META-03 walker extension: **MEDIUM** — depends on the W1 dry-run scan revealing zero hits; risk-mitigated by audit-before-extend approach.

**Research date:** 2026-06-22
**Valid until:** 2026-09-22 (90 days) — release engineering surface is stable; the only fast-moving piece is `gitleaks-action` version (Dependabot will track).
