# Phase 6 Hand-off — v1.0.0 release runbook

**Audience:** Yves (post-merge of Phase-6 PR).
**Purpose:** the exact sequence of 5 checkpoints + verification commands that turn the merged Phase-6 PR into the v1.0.0 GitHub Release.

---

## State at hand-off

- Branch `phase-6/release-polish` ready to PR against `main`. 14 GPG-signed commits across 06-01 / 06-02 / 06-03.
- Merge method: `gh pr merge --squash` (NEVER `--rebase` — see memory `feedback_gpg_signed_pr_merge`; `--rebase` produces unsigned commits on `main`).
- Reproducible-build SHA for dev builds (no `GITHUB_REF_NAME`): `4526a33fceab55122a6e624207c03cf76545939685825c3072c9d9001653304c`. The v1.0.0-tagged SHA will be computed by release.yml job 2 at CP-4 (it differs from the dev SHA because `__VERSION__` substitutes to `1.00` instead of `<DEV BUILD>`).
- All 22 Phase-6 requirement IDs delivered (cross-reference Verification matrix below).
- Maintainer fingerprint: `FDE07046A6178E89ADB57FD3DE300C53D8E18642` (`gpg --list-keys` should show this as the ultimate-trust key).

---

## CP-1 — loop-lektor pass on German wording

**Targets:**

- `README.de.md` (GoBD-Hinweis section per D-71 + Inoffizielle-Extensions wording + all engineering-grade German text)
- `CHANGELOG.md` `[1.0.0]` section (the new Hinzugefügt / Bekannte Grenzen / Sicherheit blocks landed in 06-03)
- `docs/adr/0002-localstorage-token-cache.md`, `docs/adr/0006-jwt-bearer-only-auth.md`, `docs/adr/0007-no-tls-pinning.md`, `docs/adr/0008-string-return-error-pattern.md` (English narrative — lektor may polish prose)

**Invocation Option A (Yves directly):** open each file, refine sentence rhythm + register; commit `docs(lektor): refine v1.0.0 German wording per CP-1` (GPG-signed).

**Invocation Option B (`loop-lektor` subagent):** spawn the agent pointing it at the 5 files above; the agent returns suggested wording changes inline as a report; Yves accepts/rejects and commits per Option A.

**Hard-fail discipline:** lektor MUST NOT introduce any of the 13 D-55 forbidden phrases. The extended META-03 walker (`spec/meta_no_tax_classification_spec.lua`) enforces this on every push and every CI run. If lektor proposes a forbidden phrase, reject and route through the same audit-before-extend protocol Phase 4 used.

**Verification:**

```bash
# Authoritative — runs the 13-phrase D-55 walker over every documentation target:
./.luarocks/bin/busted spec/meta_no_tax_classification_spec.lua  # expects 3/0/0/0
```

The 13-phrase list is locked in `spec/meta_no_tax_classification_spec.lua` (CONTEXT D-55, immutable). A passing walker is the load-bearing check; a failing walker names the offending file + phrase in the spec output.

---

## CP-2 — Branch protection (one-time admin)

**Prerequisite:** `gh auth login` with a Fine-Grained PAT scoped to `yves-vogl/moneymoney-paypal-pos-extension` with `Administration: write`.

**Command:**

```bash
bash tools/setup-branch-protection.sh
```

**Expected output (success path):**

```
OK: branch protection applied (PR + checks + signatures + linear history).
```

**Expected output (graceful degradation):** the script prints the manual UI fallback with the github.com settings/branches URL + a 5-step checklist + the 3 required CI check names (`Lint + tests + reproducible build`, `gitleaks secret scan`, `Commit-message lint`); exits 0. Yves follows the UI steps once.

**Verification:**

```bash
gh api repos/yves-vogl/moneymoney-paypal-pos-extension/branches/main/protection | jq '{
  checks: .required_status_checks.contexts,
  signatures: .required_signatures.enabled,
  linear: .required_linear_history.enabled,
  enforce_admins: .enforce_admins.enabled
}'
```

Expected: `checks` lists the 3 CI names, `signatures: true`, `linear: true`, `enforce_admins: true`.

---

## CP-3 — Repo metadata (one-time admin)

**Prerequisite:** `gh auth login` PAT with repo-metadata write (Yves' default PAT typically suffices).

**Command:**

```bash
bash tools/setup-repo-metadata.sh
```

**Expected output:**

```
OK: description and topics set.
```

**Verification:**

```bash
gh repo view yves-vogl/moneymoney-paypal-pos-extension --json description,topics | jq .
```

Expected: `description` matches D-82 verbatim (German); `topics` is exactly the 7 D-82 strings (`moneymoney`, `moneymoney-extension`, `paypal-pos`, `zettle`, `lua`, `germany`, `accounting`).

---

## CP-5 — Real screenshots (independent of CP-4 — can happen any time)

**Targets:** `docs/img/inoffizielle-extensions-erlauben.png` (current placeholder 1×1 PNG) + `docs/img/help-menu-extensions-folder.png`.

**Capture procedure:**

1. Open current-stable MoneyMoney (target version 2.4.x per ADR-0003).
2. For `help-menu-extensions-folder.png`: open the Hilfe menu and hover the "Erweiterungen im Finder zeigen" item; screenshot via `Cmd+Shift+4` + space + click the menu window.
3. For `inoffizielle-extensions-erlauben.png`: open Einstellungen → Erweiterungen and reveal the "Inoffizielle Extensions erlauben" toggle; screenshot the window.
4. Save at the exact same paths so README.de.md image references stay valid.
5. Commit: `docs(img): capture inoffizielle-extensions-erlauben.png + help-menu-extensions-folder.png` (GPG-signed).
6. The `<!-- screenshot: pending — CP-5 -->` HTML markers in README.de.md become stale comments; optionally remove them in the same commit.

**Verification:**

```bash
file docs/img/inoffizielle-extensions-erlauben.png  # expect PNG image data, > 1 x 1
file docs/img/help-menu-extensions-folder.png       # expect PNG image data, > 1 x 1
```

---

## CP-4 prerequisites — MAINTAINER_GPG_PUBKEY + CHANGELOG date

### MAINTAINER_GPG_PUBKEY (one-time per repo)

```bash
gpg --armor --export FDE07046A6178E89ADB57FD3DE300C53D8E18642 | \
  gh secret set MAINTAINER_GPG_PUBKEY --repo yves-vogl/moneymoney-paypal-pos-extension
```

**Verification:**

```bash
gh secret list --repo yves-vogl/moneymoney-paypal-pos-extension | grep MAINTAINER_GPG_PUBKEY
```

WITHOUT this secret, `release.yml` job 1 fails at the `gpg --import` step with the explicit FAIL message instructing Yves to run this one-liner.

### CHANGELOG date fix

Replace `## [1.0.0] - 2026-MM-DD` with `## [1.0.0] - <actual YYYY-MM-DD>`. Single commit on `main`:

```bash
# After CP-1 lektor pass merged to main, on main, with the date you intend to publish:
sed -i.bak 's/^## \[1\.0\.0\] - 2026-MM-DD$/## [1.0.0] - 2026-06-22/' CHANGELOG.md   # adapt date
rm CHANGELOG.md.bak
git add CHANGELOG.md
git commit -S -m "docs(changelog): finalize v1.0.0 release date 2026-06-22"
```

This commit is the one that gets tagged at CP-4 step 3.

---

## CP-4 — Cut v1.0.0 tag (the release moment)

Sequenced steps:

1. **Verify prerequisites:**
   - CP-1 lektor done and merged.
   - MAINTAINER_GPG_PUBKEY secret set (above).
   - CHANGELOG date finalized (above).
   - `main` is at the CHANGELOG-date-finalized commit; `git log -1 --show-signature` shows `Korrekte Signatur` and the maintainer key fingerprint.

2. **(Optional dry-run via `v1.0.0-rc.1`):** push a release-candidate tag first to exercise `release.yml` end-to-end without committing the v1.0.0 first impression:

   ```bash
   git tag -s v1.0.0-rc.1 -m "Release v1.0.0-rc.1 (dry-run for release.yml verification)"
   git push origin v1.0.0-rc.1
   gh run watch
   ```

   Verify the GitHub Releases page shows a prerelease tagged `v1.0.0-rc.1` with `paypal-pos.lua` + `paypal-pos.lua.sha256` attached. If anything fails, fix and delete the tag (`git tag -d v1.0.0-rc.1 && git push --delete origin v1.0.0-rc.1`) before cutting v1.0.0.

3. **Cut the stable v1.0.0 tag** (paste the CHANGELOG `[1.0.0]` section body into the tag annotation; `release.yml` job 2 also falls back to extracting it via awk if the annotation is empty):

   ```bash
   git tag -s v1.0.0 -m "Release v1.0.0

   First stable release. See CHANGELOG.md [1.0.0] for the full changeset."
   git push origin v1.0.0
   ```

4. **Watch release.yml:**

   ```bash
   gh run watch
   ```

   Three jobs: `Verify GPG tag signature` → `Build + test + reproducible build (release)` → `Publish GitHub Release`. Each should be GREEN.

5. **Verify the GitHub Releases page** at https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases/tag/v1.0.0:
   - Tag annotation rendered as release body (or CHANGELOG `[1.0.0]` section if annotation was empty).
   - 2 attached assets: `paypal-pos.lua` + `paypal-pos.lua.sha256`.
   - Marked as latest stable (not prerelease — `contains(github.ref_name, '-rc.')` is false for `v1.0.0`).

6. **Verify the artifact bytes match the published checksum:**

   ```bash
   curl -L https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases/download/v1.0.0/paypal-pos.lua -o /tmp/paypal-pos.lua
   curl -L https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases/download/v1.0.0/paypal-pos.lua.sha256 -o /tmp/paypal-pos.lua.sha256
   shasum -a 256 -c /tmp/paypal-pos.lua.sha256   # expects OK
   ```

7. **Verify `__VERSION__` substituted correctly:**

   ```bash
   grep -E 'version = 1\.00,' /tmp/paypal-pos.lua   # BUILD-03 sanity
   ```

---

## Verification matrix

| Req ID | Verification | Status (post-CP-4) |
|--------|--------------|--------------------|
| BUILD-03 | `grep 'version = 1.00,' <downloaded artifact>` | pending CP-4 |
| BUILD-04 | release.yml job 1 `VALIDSIG FDE07046A6178E89ADB57FD3DE300C53D8E18642` match in run log | pending CP-4 |
| BUILD-05 | `gh release view v1.0.0 --json assets` shows both `.lua` + `.lua.sha256` | pending CP-4 |
| BUILD-06 | release body equals tag annotation or CHANGELOG `[1.0.0]` section | pending CP-4 |
| CI-01..06 | ci.yml + commit-lint.yml + gitleaks on every push (verified by existing PR runs) | DONE |
| SEC-02 | egress-allowlist + D-79 grep in `.github/workflows/ci.yml` | DONE |
| SEC-05 | `gh api .../branches/main/protection` shows signatures + checks + linear history | pending CP-2 |
| DOC-01..04 | `README.de.md` exists with Inoffizielle-Extensions guide + GoBD-Hinweis + 18-section structure | DONE |
| DOC-05 | `CONTRIBUTING.md` exists with dev loop + release process | DONE |
| DOC-06 | 8 ADRs under `docs/adr/` (0001..0008, all MADR-formatted) | DONE |
| DOC-07 | `head -3 LICENSE` shows MIT + Yves Vogl 2026 | DONE (pre-existing) |
| DOC-08..09 | `gh repo view --json description,topics` shows D-82 description + 7 topics | pending CP-3 |
| DOC-10 | `CHANGELOG.md` has `[1.0.0]` section in Keep-a-Changelog format with footnote link | DONE |

---

## If anything fails

- **release.yml job 1 fails at `gpg --import`:** the `MAINTAINER_GPG_PUBKEY` secret is unset. Re-run the one-liner from "CP-4 prerequisites".
- **release.yml job 1 fails at the `VALIDSIG` grep:** the tag was signed with a different key. Re-tag with the correct key: `git tag -d v1.0.0 && git push --delete origin v1.0.0` then `git tag -s v1.0.0 -m "..."` with the maintainer key.
- **release.yml job 2 fails at the BUILD-03 sanity grep:** the tag name and the substituted version disagree. Verify the regex in `tools/build.lua` matches the tag (e.g., a `v1.10.0` tag yields `1.10`; a `v1.0.0-rc.1` tag yields `1.00`). If a future tag pattern changes, update the substitution and the sanity grep in lockstep.
- **release.yml job 3 fails at `softprops` with "Resource not accessible by integration":** the publish job's permissions are mis-scoped. Verify job 3 has `permissions: contents: write` (workflow-level remains `contents: read`).
- **Branch protection blocks the first PR after CP-2:** Pitfall 4 — the `CHECKS` array in `tools/setup-branch-protection.sh` must match the workflows' job `name:` fields byte-for-byte. Compare `gh api .../branches/main/protection | jq .required_status_checks.contexts` against the actual job `name:` strings in `.github/workflows/ci.yml` + `commit-lint.yml`. Update the script and re-run.
- **gitleaks flags an existing fixture:** add the specific fingerprint (line-by-line, never blanket) to `.gitleaksignore`; re-run the PR check.

---

## Phase 6.1 unblocked

After v1.0.0 ships and stabilises for ~2 weeks (per ROADMAP), Phase 6.1 (OpenSSF Scorecard hardening) becomes the next planning candidate. Reference: `.planning/research/openssf-scorecard-sprint-proposal.md`. Expected jump from baseline Scorecard ~5.2 → 8.5+ via pinned action SHAs, SLSA-style provenance, and `permissions:` minimisation across remaining workflows.

---

## Cross-reference

The release process recipe in this runbook is the source of truth for tag publication. `CONTRIBUTING.md`'s "Cutting a release" + "First-time setup" sections mirror this content for general contributors; if the two ever drift, this file (06-HANDOFF.md) is authoritative for v1.0.0; `CONTRIBUTING.md` is authoritative for v1.0.1+.
