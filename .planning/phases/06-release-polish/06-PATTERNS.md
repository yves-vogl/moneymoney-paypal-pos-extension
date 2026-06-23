# Phase 6: Release & Polish — File Pattern Map

**Mapped:** 2026-06-22
**Companion to:** `06-RESEARCH.md`
**Purpose:** For each file Phase 6 creates or modifies, identify the closest analog in the existing codebase and recommend the implementation approach. The planner uses this map to write granular plan tasks with concrete file references.

---

## Index

| # | Path | Role | Status | Wave | Analog |
|---|------|------|--------|------|--------|
| 1 | `.github/workflows/release.yml` | workflow | NEW | W2 | `.github/workflows/scorecard.yml` (workflow shape); `ci.yml` (lua+luarocks setup) |
| 2 | `.github/workflows/ci.yml` | workflow | MODIFY | W1 | self (extend with gitleaks + commit-lint + `print(` grep) |
| 3 | `.github/workflows/commit-lint.yml` | workflow | NEW (optional split) | W1 | none — can also fold into ci.yml as a job |
| 4 | `.github/dependabot.yml` | config | NO-OP (already correct) | — | self |
| 5 | `tools/build.lua` | source | MODIFY (~30 LoC) | W1 | self — add `resolve_version_string()` + `version_to_number_string()` + `__VERSION__` gsub in `build()` |
| 6 | `tools/setup-branch-protection.sh` | tool (shell) | NEW | W2 | `tools/probe-finance.sh` (shell helper shape) |
| 7 | `tools/setup-repo-metadata.sh` | tool (shell) | NEW | W2 | `tools/probe-finance.sh` |
| 8 | `src/webbanking_header.lua` | source | MODIFY (1 line) | W1 | self — `version = 0.00,` → `version = __VERSION__,` |
| 9 | `README.md` | doc | REWRITE (English pointer) | W2 | self (German content moves to README.de.md); D-70 |
| 10 | `README.de.md` | doc | NEW (from current README.md) | W2 | current `README.md` (German engineering-draft, 196 lines) |
| 11 | `CONTRIBUTING.md` | doc | NEW | W2 | none in-repo — model on `docs/adr/0005-resilience-invariants.md` style (English, MADR-clean prose) |
| 12 | `LICENSE` | doc | NO-OP (already correct) | — | self — verified `head LICENSE` shows "MIT License / Copyright (c) 2026 Yves Vogl" |
| 13 | `CHANGELOG.md` | doc | MODIFY (v1.0.0 entry) | W3 (pre-tag) | self — extend with `[1.0.0] - YYYY-MM-DD` section |
| 14 | `docs/adr/0002-localstorage-token-cache.md` | adr | NEW | W2 | `docs/adr/0001-amalgamator-design.md` (MADR template) |
| 15 | `docs/adr/0006-jwt-bearer-only-auth.md` | adr | NEW | W2 | `docs/adr/0001` |
| 16 | `docs/adr/0007-no-tls-pinning.md` | adr | NEW | W2 | `docs/adr/0003-sandbox-probe-results.md` (cross-references Q8) |
| 17 | `docs/adr/0008-string-return-error-pattern.md` | adr | NEW | W2 | `docs/adr/0005-resilience-invariants.md` (string-return pattern is core to ERR-01..06) |
| 18 | `docs/img/inoffizielle-extensions-erlauben.png` | asset | NEW (placeholder) | W2 | none — 1×1 transparent PNG OR 600×400 placeholder with `<!-- screenshot: pending -->` marker |
| 19 | `docs/img/help-menu-extensions-folder.png` | asset | NEW (placeholder) | W2 | same |
| 20 | `docs/img/README.md` | doc | NEW | W2 | none — short note listing placeholder→real-image queue for CP-5 |
| 21 | `spec/meta_no_tax_classification_spec.lua` | spec | MODIFY (target list) | W1 | self — extend `targets` array to include markdown files |
| 22 | `spec/build_version_substitution_spec.lua` | spec | NEW | W1 | `spec/build_spec.lua` (existing build spec; mirror its shape) |
| 23 | `.gitleaksignore` (conditional) | config | NEW only if W1 reveals fixture false positives | W1 | none |

**Total: 23 files** (15 new + 6 modify + 2 no-op).

---

## File-by-File Detail

### 1. `.github/workflows/release.yml` (NEW, W2)

**Role:** Tag-triggered workflow with 3 sequential jobs: verify-signed-tag → build-test-coverage-repro → publish.

**Closest analog:**
- `.github/workflows/scorecard.yml` — workflow shape (jobs + permissions + concurrency).
- `.github/workflows/ci.yml` — setup steps (`leafo/gh-actions-lua@v13`, `leafo/gh-actions-luarocks@v6.1.0`, `luarocks install busted luacheck luacov dkjson`, `lua tools/build.lua --verify`).

**Recommended approach:** Compose by stitching the analog patterns. Three jobs:
1. `verify-signed-tag` — RESEARCH §2 verbatim recipe.
2. `build-test-coverage-repro` — mirrors `ci.yml`'s `test` job (lint + busted + coverage gate + build --verify + egress allowlist + `print(` grep) BUT additionally exports the artifact + computes the `.sha256` file and extracts the release-notes from the tag annotation.
3. `publish` — RESEARCH §1 softprops invocation.

**Trigger:**
```yaml
on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'
      - 'v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+'
```

**Env:** `LC_ALL: C` (same as ci.yml).
**Permissions:** workflow-level `permissions: contents: read`; only the `publish` job escalates to `contents: write`.
**Secrets:** `MAINTAINER_GPG_PUBKEY` (must be set by Yves before first release per CP-4 prerequisite).

**Dry-run strategy:** Land the workflow file, then push a `v1.0.0-rc.1` tag for end-to-end verification before pushing `v1.0.0`. The `rc.1` publishes as a prerelease (visible but flagged) and exercises the full pipeline without committing to "v1.0.0 first release".

### 2. `.github/workflows/ci.yml` (MODIFY, W1)

**Role:** Existing CI workflow extended with: gitleaks job + commit-lint job (or new file per §3) + `print(` grep step.

**Closest analog:** itself (lines 83–120 show the egress allowlist pattern that the new `print(` grep mirrors).

**Recommended approach:**
1. Add new `secret-scan` job (RESEARCH §4 snippet) as a sibling of the existing `test` job. Runs on `actions/checkout@v4` with `fetch-depth: 0`.
2. Add new step to the existing `test` job after "Egress allowlist gate": `D-79 — no raw print() calls in shipped artifact` (RESEARCH §12 snippet).
3. Either add a new `commit-lint` job in ci.yml OR create `.github/workflows/commit-lint.yml` (RESEARCH §11). **Recommend separate file** because the trigger (`on: pull_request`) is different from ci.yml's `on: push + pull_request`, and separation keeps each workflow focused.

**Caution:** Each new required CI check must be added to the `CHECKS` array in `tools/setup-branch-protection.sh` (RESEARCH §6) so branch protection enforces them.

### 3. `.github/workflows/commit-lint.yml` (NEW, W1)

**Role:** PR-only commit-message lint.

**Closest analog:** none — fresh file using RESEARCH §11 recipe.

**Recommended approach:** RESEARCH §11 snippet verbatim. ~30 LoC. Pure shell, no Node toolchain.

### 4. `.github/dependabot.yml` (NO-OP)

**Role:** Already configured for `github-actions` ecosystem with weekly Monday Berlin-time PRs.

**Verification:** the existing file has the right `commit-message.prefix: ci` + `labels` + `open-pull-requests-limit: 5`. No change needed.

**Note for planner:** when `release.yml` + `commit-lint.yml` (+ optional `secret-scan.yml`) land, Dependabot automatically picks up their action references the next scheduled scan. No config edit needed.

### 5. `tools/build.lua` (MODIFY ~30 LoC, W1)

**Role:** Phase-1 amalgamator + new `__VERSION__` substitution.

**Closest analog:** itself.

**Recommended approach:**
1. Add `resolve_version_string()` (3 fallback paths: `$GITHUB_REF_NAME` → `git describe --tags --exact-match` → `git rev-parse --short HEAD` prefixed with `dev-`) per RESEARCH §3.
2. Add `version_to_number_string(s)` that converts `v1.2.3` → `"1.20"` per RESEARCH §3.
3. At module scope (after `parse_manifest()` resolution): compute `local VERSION_NUMBER = version_to_number_string(resolve_version_string())`.
4. In `build()`, inside the `if mod == HEADER_MOD then` branch, before `parts[#parts + 1] = ensure_trailing_newline(content)`, insert `content = content:gsub("__VERSION__", VERSION_NUMBER)`.

**Test in:** `spec/build_version_substitution_spec.lua` (item 22 below).

**Reproducibility check:** existing `--verify` flag still works because the gsub is deterministic for a given env. CI release.yml will pass `GITHUB_REF_NAME=v1.0.0` env when invoking `lua tools/build.lua`.

**Dev-build banner (Pitfall 3 mitigation):** consider prepending the BANNER constant with a conditional `if VERSION_NUMBER == "0.00" then BANNER = BANNER .. "-- DEV BUILD — not for release\n" end`. Acceptance criteria: dist/paypal-pos.lua second comment line says "DEV BUILD" when no tag is present.

### 6. `tools/setup-branch-protection.sh` (NEW, W2)

**Role:** One-time admin script; gracefully degrades when PAT lacks `Administration:write`.

**Closest analog:** `tools/probe-finance.sh` — shell tool that performs an API call and prints helpful output. Same shape (set -euo pipefail, env-var prompts, helpful error messages).

**Recommended approach:** RESEARCH §6 snippet verbatim. ~80 LoC including the manual-fallback message block.

**Permissions:** declares no permissions itself; the user's `gh` CLI auth determines what works.

**Idempotency:** PUT replaces, so re-runs are safe.

**Documentation:** CONTRIBUTING.md `## Release process` section mentions this script and the CP-2 checkpoint.

### 7. `tools/setup-repo-metadata.sh` (NEW, W2)

**Role:** One-time admin script for description + 7 topics per D-82.

**Closest analog:** `tools/probe-finance.sh`.

**Recommended approach:** RESEARCH §7 snippet verbatim. ~40 LoC.

**Idempotency:** `gh repo edit --description` PATCH semantics + `PUT /repos/.../topics` replace-list semantics — both idempotent.

### 8. `src/webbanking_header.lua` (MODIFY 1 line, W1)

**Role:** Phase-1 header — predeclares modules, sets DEBUG, calls `WebBanking{}`.

**Recommended approach:**

Line 24, change:
```lua
version     = 0.00,
```
to:
```lua
version     = __VERSION__,
```

**Caveats:**
- The file is Lua-syntactically INVALID after this edit (`__VERSION__` is an undefined global at parse time). This is OK because:
  - The file is never loaded directly; only `dist/paypal-pos.lua` is loaded (by MoneyMoney or by busted's `require` in specs after a build).
  - `tools/build.lua` always runs `gsub("__VERSION__", VERSION_NUMBER)` before emitting the header.
  - All existing tests build before loading the artifact.
- The `tools/build.lua` `check_source()` sandbox-banned-call check operates on the raw file content; `__VERSION__` is not in the BANNED_CALLS list, so this passes silently.
- `luacheck` will flag `__VERSION__` as an undefined global on `src/webbanking_header.lua`. Fix by adding to `.luacheckrc` `read_globals`:
  ```lua
  files["src/webbanking_header.lua"] = {
    read_globals = { "__VERSION__" },
  }
  ```
  OR more simply: add `__VERSION__` to global `read_globals` list — it's harmless elsewhere.

### 9. `README.md` (REWRITE → English pointer, W2)

**Role:** GitHub default-rendered README; per D-70, becomes a short English pointer to `README.de.md` for international visitors plus the same Bekannte Grenzen + GoBD-Hinweis sections in English.

**Closest analog:** none in-repo (current README is German). Model on the structure used by other internationalized OSS projects: short intro → "Primary documentation is in German" → quick links → English-translated risk-relevant sections (Bekannte Grenzen + GoBD-Hinweis) → badges (top) + License (bottom).

**Recommended sections:**

```markdown
# MoneyMoney PayPal POS Extension

> Community extension for [MoneyMoney](https://moneymoney.app) that adds PayPal POS (formerly Zettle) card transactions, refunds, fees, and payouts to MoneyMoney.

<badges row — same as current README.md lines 5–14>

## Primary documentation

**This extension's primary user documentation is German.** German is the only
language MoneyMoney supports natively, and the merchant base is exclusively
in DE/AT. See **[README.de.md](README.de.md)** for:

- Installation guide (with screenshot)
- Setup walkthrough
- GoBD note for German accounting
- Privacy & security guarantees

## What this extension is and isn't (English summary)

**It is:** a read-only adapter that pulls your PayPal POS card transactions,
refunds, fees, and payouts into MoneyMoney for visibility and bookkeeping
hand-off.

**It is not:** an accounting tool. It does NOT classify revenue, does NOT
claim GoBD or DATEV conformance, does NOT replace a tax advisor.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) — copyright Yves Vogl <yves@kadenz.live>.

## Disclaimer

Unofficial community project. Neither MoneyMoney GmbH nor PayPal / Zettle
are publishers or sponsors. All trademarks belong to their respective owners.
```

**Estimated size:** ~50 lines (vs current 196).

**META-03 check:** zero of the 13 forbidden phrases. "GoBD" appears in "does NOT claim GoBD or DATEV conformance" — but the forbidden phrases are "GoBD-konform" / "GoBD konform" specifically, NOT the unmodified word "GoBD". Verify in W1.

### 10. `README.de.md` (NEW, W2)

**Role:** Primary German user-facing README per D-70.

**Closest analog:** current `README.md` (German engineering-draft, 196 lines).

**Recommended approach:** Move the current README.md content verbatim to README.de.md. Then:
1. Promote the "Inoffizielle Extensions erlauben" enablement to the first major section (DOC-02 — currently it's embedded inside "Installation" line 122; needs to be a top-level `## Inoffizielle Extensions erlauben` section with the screenshot).
2. Add the GoBD-Hinweis section verbatim from D-71.
3. Add the screenshot references per RESEARCH §8.
4. Add `<!-- lektor-review: pending — CP-1 -->` HTML comment markers around D-71 wording and the screenshot-illustrated install steps.
5. Update internal links to point to `CONTRIBUTING.md` (not `(folgt mit Phase 6)`).

**Section order (recommended):**
1. Title + badges (from current README.md head)
2. Status (current "Status" section, updated for v1.0.0)
3. **Inoffizielle Extensions erlauben** (NEW — RESEARCH §8 content)
4. Was die Extension jetzt kann (existing)
5. Was die Extension nicht macht (existing — META-03 disclaimer prose already in place)
6. **GoBD-Hinweis** (NEW — D-71 verbatim)
7. Inbetriebnahme bei bestehendem v0.1.0 API-Key (existing — Phase-4 ADR-0004 section)
8. Bekannte Grenzen (existing — D-49 fee re-classification + ERR-04 token-revoked)
9. Warum diese Extension (existing)
10. Voraussetzungen (existing, update for v1.0.0)
11. Installation (existing, update post-screenshot)
12. Verifikation signierter Releases (existing — GPG block)
13. Datenschutz & Sicherheit (existing)
14. Unterstützen (existing — Sponsors)
15. Beitragen (existing — link to CONTRIBUTING.md)
16. Roadmap (existing)
17. Lizenz (existing)
18. Disclaimer (existing)

**META-03 check before merge:** run `lua -e "<META-03 walker code from spec>"` on README.de.md draft.

### 11. `CONTRIBUTING.md` (NEW, W2)

**Role:** English-language contributor onboarding per DOC-05.

**Closest analog:** none in-repo. Model on the structure used by Phase-1..5 ADRs (MADR-clean English prose with section headers).

**Recommended sections:**

```markdown
# Contributing

Thank you for considering a contribution to the MoneyMoney PayPal POS Extension.

## Code of conduct

Be kind, be technical, be specific.

## Development loop

### Prerequisites
- macOS or Linux with Lua 5.4 installed (`brew install lua@5.4` on macOS).
- LuaRocks (`brew install luarocks`).
- Dev dependencies: `luarocks install busted luacheck luacov dkjson`.

### Source layout
- `src/<module>.lua` — Lua source, one module per file.
- `tools/manifest.txt` — module concatenation order (do not edit lightly).
- `tools/build.lua` — amalgamator. Run `lua tools/build.lua` to produce `dist/paypal-pos.lua`.
- `spec/<module>_spec.lua` — tests mirroring `src/` 1:1.

### Test loop
```bash
busted spec/<your_changed_spec>.lua  # quick run
busted spec/                          # full suite
luacheck .                            # lint
lua tools/build.lua --verify          # reproducible build sanity
```

### Pre-commit checklist
- [ ] `busted spec/` is green.
- [ ] `luacheck .` is clean.
- [ ] `lua tools/build.lua --verify` reports `OK: reproducible`.
- [ ] Commit message follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
- [ ] Commit is GPG-signed (`git commit -S`).
- [ ] No `Co-Authored-By: Claude` / `Generated with Claude` / `🤖` in commit message or files.

## Testing conventions

- **TDD red-then-green.** Write a failing `pending` test first; implement until it passes.
- **`spec/helpers/mm_mocks.lua` is the only mock surface for MoneyMoney built-ins.** Do not mock at the HTTP-socket level; mock at the `Connection()` boundary.
- **Fixtures live under `spec/fixtures/`** as JSON files. Loaded via `dkjson` in the test harness.

## Architecture

### Amalgamator (ADR-0001)
The shipped artifact is a single `.lua` file. `tools/build.lua` concatenates `src/` modules in the order declared by `tools/manifest.txt`. `src/webbanking_header.lua` and `src/entry.lua` are emitted verbatim at top and tail; everything else is wrapped in `do...end` blocks. **You cannot `require()` sibling modules.** Cross-module references go via top-level `M_*` tables declared in `webbanking_header.lua`.

### Error pattern (ADR-0008)
Every MoneyMoney callback returns either `nil`/success-table on success OR a localized German error string. Never `error()` — that would surface as raw Lua error in the MM UI.

### Logging (SEC-01)
Use `M_log.info` / `M_log.warn` / `M_log.error`. Never `print(` directly. The logger redacts JWT shape and `Bearer` substrings.

## Release process

Releases are triggered by pushing a GPG-signed tag. The maintainer's fingerprint is `FDE07046A6178E89ADB57FD3DE300C53D8E18642`.

### Cutting a release (maintainer)
```bash
# 1. Update CHANGELOG.md with the new version's entry (Keep-a-Changelog format).
# 2. Commit the CHANGELOG update on main:
git commit -S -m "docs(changelog): release vX.Y.Z"
# 3. Tag with annotation (the annotation becomes the release notes):
git tag -s vX.Y.Z -m "Release vX.Y.Z

<changelog entry verbatim or summary>
"
# 4. Push:
git push origin main
git push origin vX.Y.Z
# 5. release.yml runs automatically:
#    - verifies the tag signature against MAINTAINER_GPG_PUBKEY
#    - runs lint+test+coverage+reproducible-build
#    - substitutes __VERSION__ from the tag
#    - publishes via softprops/action-gh-release@v2 with the .lua + .sha256
```

### First-time setup (maintainer)
1. Export public key + upload to CI secrets:
   ```bash
   gpg --armor --export FDE07046A6178E89ADB57FD3DE300C53D8E18642 \
     | gh secret set MAINTAINER_GPG_PUBKEY
   ```
2. Apply branch protection:
   ```bash
   bash tools/setup-branch-protection.sh
   ```
3. Set repo metadata:
   ```bash
   bash tools/setup-repo-metadata.sh
   ```

### Dry-running a release
Push a `vX.Y.Z-rc.N` tag first; release.yml publishes it as a prerelease (visible separately in the GitHub Releases UI). Confirm the artifact + sha256 attach correctly before pushing the stable `vX.Y.Z` tag.

## Commit conventions

Conventional Commits 1.0.0:
```
<type>(<scope>): <subject>
```

Allowed types: `feat fix docs test refactor chore ci build perf style revert`.

A GitHub Actions workflow (`commit-lint.yml`) enforces the grammar on every PR.

## ADRs

Architectural decisions are recorded under `docs/adr/` in MADR format. Numbered sequentially. See existing 0001..0008 for examples. If your change locks in a new decision (e.g., a library choice, an invariant, a trade-off), open a new ADR.
```

**Estimated size:** ~150 lines. English throughout.

**META-03 check:** the word "GoBD" does not appear; the word "DATEV" does not appear; the file should pass the extended walker.

### 12. `LICENSE` (NO-OP)

**Verification:** `head -3 LICENSE` shows:
```
MIT License

Copyright (c) 2026 Yves Vogl <yves@kadenz.live>
```

DOC-07 satisfied. No change needed.

### 13. `CHANGELOG.md` (MODIFY, W3 pre-tag)

**Role:** Add v1.0.0 entry following Keep-a-Changelog format.

**Recommended structure:**

```markdown
## [1.0.0] - YYYY-MM-DD

**First stable release.**

### Hinzugefügt
- Reproducible release pipeline (`release.yml`): GPG-signed-tag-triggered, builds the artifact deterministically, attaches `paypal-pos.lua` + `paypal-pos.lua.sha256` to the GitHub Release.
- `__VERSION__` substitution in `tools/build.lua` derived from the Git tag — the shipped `WebBanking{version}` matches the published version.
- Bilingual documentation: `README.de.md` (German-primary) with screenshot-illustrated install guide + GoBD-Hinweis + privacy/security guarantees; `README.md` (English pointer) for international visitors.
- `CONTRIBUTING.md` documenting the dev loop, testing conventions, amalgamator architecture, release process, and GPG-signed-tag requirement.
- 4 new MADR ADRs (0002 LocalStorage cache, 0006 JWT-bearer-only auth, 0007 no TLS pinning, 0008 string-return error pattern) backfilling architectural decisions locked in Phases 2–5.
- gitleaks secret scanning on push + PR; commit-message-lint GitHub Action enforcing Conventional Commits.
- Branch protection on `main`: PR required, GPG-signed commits required, CI green required, linear history required.
- Repo metadata: German description + 7 topics (`moneymoney`, `moneymoney-extension`, `paypal-pos`, `zettle`, `lua`, `germany`, `accounting`).

### Bekannte Grenzen (unverändert seit v0.2.0)
- Verzögerte Buchung von Auszahlungen (1–2 Refreshes bei wöchentlichem/monatlichem Auszahlungsrhythmus) — siehe ADR-0004.
- Tagesaggregat von Gebühren bei nachgereichter Verknüpfung — siehe README.de.md.
- 90-Tage-Erstabgleich-Klammer; ältere Umsätze nicht sichtbar.
- Nicht-EUR-Transaktionen werden übergangen.
- Nach Token-Revocation: API-Key erneut einfügen (ERR-04 dokumentiert in ADR-0005).

### Sicherheit
- Keine Telemetrie, keine Drittparteien. Egress ausschließlich an `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com` — CI-Gate erzwingt das pro Release.
- API-Keys werden ausschließlich über MoneyMoneys Anmelde-Daten-Verwaltung gespeichert.
- Alle Tags GPG-signiert; Reproducible-Build-Verifikation pro Release; SHA256-Prüfsumme als Release-Asset.

[1.0.0]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases/tag/v1.0.0
```

**Wave-3 sequencing:** This entry is written AFTER the W2 PR merges to main and BEFORE Yves runs `git tag -s v1.0.0`. The CHANGELOG commit lands on main as a regular commit (Conventional Commits: `docs(changelog): release v1.0.0`), then Yves tags from that commit.

**META-03 check:** German text uses "GoBD-Hinweis" (not "GoBD-konform") and "Steuerberatung" (not "steuerlich"). Verify via dry-run walker before commit.

### 14. `docs/adr/0002-localstorage-token-cache.md` (NEW, W2)

**Role:** Retro-document the Phase-2 LocalStorage token cache contract per D-80.

**Closest analog:** `docs/adr/0001-amalgamator-design.md` (MADR template, ACCEPTED status).

**Recommended sections** (per RESEARCH §9):

```markdown
# ADR-0002: LocalStorage Token Cache

## Status
ACCEPTED

## Date
2026-06-22 (retro-documented; decision shipped in Phase 2)

## Deciders
Yves Vogl

## Context
Phase 2 (v0.1.0) wired the PayPal POS JWT-bearer assertion grant against `oauth.zettle.com/token`. The token has a 7200-second TTL and the assertion-grant flow returns no refresh token — every expiry requires a fresh exchange against the API key. Without a cache, every `RefreshAccount` would re-mint a token: wastes the assertion-grant rate budget, adds 200–500ms latency, and probes the auth endpoint more often than necessary.

MoneyMoney's embedded interpreter exposes a `LocalStorage` global (verified in ADR-0003 Q5) — a per-extension key-value store that survives MoneyMoney process restarts.

## Decision

Cache the access token in `LocalStorage.zettle` with this schema:

```lua
LocalStorage.zettle = {
  access_token = "<bearer token string>",
  obtained_at  = <POSIX seconds>,
  expires_at   = <POSIX seconds — obtained_at + expires_in>,
  client_id    = "<the constant PayPal-POS client_id used at mint time>",
}
```

`M_auth.cached_token()` returns the cached token if `os.time() < expires_at - 60` (60s safety margin); otherwise re-mints.

The `client_id` field is recorded so a future Phase-7 (OAuth Authorization-Code) can detect cache entries minted by the assertion-grant path and invalidate them on grant-flow change without colliding.

## Consequences
- **Positive:** Cross-restart token reuse; fewer auth-endpoint hits; first-refresh latency drops from ~500ms to ~10ms.
- **Positive:** Foundation for ERR-04 (Phase 5) — post-mint 401 means token is stale OR revoked; cache invalidation is the recovery path.
- **Negative:** Cached token is recoverable from MoneyMoney's `LocalStorage` if the device is compromised. Mitigations: MoneyMoney's own encryption-at-rest; the API key (not in cache) is the load-bearing credential; tokens expire in 2h.
- **Negative:** A schema change requires a one-time cache wipe in the migration. Documented in the migration ADR if it ever happens (no such change planned for v1.0.x).

## References
- Phase-2 RESEARCH (D-22..D-26)
- ADR-0003 Q5 (LocalStorage cross-restart verification)
- ADR-0005 ERR-04 (cache invalidation on post-mint 401)
- CLAUDE.md §"PayPal POS / Zettle API surface" (token TTL = 7200s, no refresh token)
```

**Estimated size:** ~80 lines.

### 15. `docs/adr/0006-jwt-bearer-only-auth.md` (NEW, W2)

**Role:** Lock in the v1.0.x auth surface; note the Phase-7 forward-compat plan.

**Closest analog:** ADR-0001.

**Recommended outline:**
- **Context:** Two PayPal POS auth flows exist — JWT-bearer assertion grant (one-time API key paste, no browser) and OAuth Authorization-Code (browser redirect, public-app registration with Zettle). For v1.0.0 we ship only the former.
- **Decision:** v1.0.x `src/auth.lua` implements assertion grant only. The MoneyMoney credentials dialog exposes a single `API-Key` field. ROADMAP Phase 7 (deferred to post-v1) adds a dual-path that preserves the assertion-grant surface byte-identically and adds OAuth Auth-Code beside it.
- **Consequences:**
  - **Positive:** No partner-app registration burden; no review process; no OOB redirect handling; no Zettle approval gate. v1.0.0 ships independently.
  - **Positive:** Single-merchant-per-extension-instance model matches MoneyMoney's account-add UX.
  - **Negative:** Users must visit `my.zettle.com/apps/api-keys` and manually mint a JWT. UX friction. Phase 7 mitigates if users complain.
  - **Constraint:** Phase 7 implementation MUST preserve byte-identical assertion-grant codepath (matches the surface-preservation spec from Phase 4).
- **References:** ROADMAP Phase 7 entry; CLAUDE.md §"Alternatives Considered → Authorization Code flow"; Phase-2 plan 02-05.

**Estimated size:** ~70 lines.

### 16. `docs/adr/0007-no-tls-pinning.md` (NEW, W2)

**Role:** Document the explicit non-decision to pin TLS certificates, with mitigations.

**Closest analog:** ADR-0003 (sandbox probes — cross-reference Q8).

**Recommended outline:**
- **Context:** TLS certificate pinning is a defense-in-depth control against CA compromise / MITM. Standard for high-value crypto apps. Phase 1 Q8 verified that MoneyMoney's `Connection()` does TLS verification by default (system root store).
- **Decision:** Rely on `Connection()` default TLS verification. Do NOT bundle a pin set or CA bundle.
- **Reasons:**
  1. MoneyMoney's Lua sandbox does NOT expose a way to inject a custom CA bundle or pin a specific cert.
  2. Zettle's TLS chain rotates; a static pin would break the extension at the rotation moment with no graceful path.
  3. The Phase-2 redactor + Phase-1 egress allowlist + reproducible build + GPG-signed releases form an independent trust chain that is NOT TLS-dependent.
- **Consequences:**
  - **Positive:** Zero maintenance burden on TLS rotations.
  - **Negative:** If a CA in the user's root store is compromised AND the attacker can MITM `*.izettle.com`, the extension would talk to the attacker. Acceptable risk given the data sensitivity (read-only access to merchant's own transaction history) and Zettle's TLS posture.
  - **Mitigations:** Egress allowlist (CI gate) ensures the artifact only talks to the three allowed hosts; redactor strips bearer/JWT from logs; signed releases + reproducible build give the user an out-of-band way to verify the binary.
- **References:** ADR-0003 Q8 (TLS default verification verified); CLAUDE.md §"What NOT to Use".

**Estimated size:** ~60 lines.

### 17. `docs/adr/0008-string-return-error-pattern.md` (NEW, W2)

**Role:** Document the MoneyMoney-WebBanking-API-mandated error contract.

**Closest analog:** ADR-0005 (resilience invariants, which depend on this pattern).

**Recommended outline:**
- **Context:** MoneyMoney's `RefreshAccount`, `InitializeSession2`, `ListAccounts`, `EndSession` callbacks return either `nil` / success-value OR an error STRING. Lua `error()` would surface as raw "Lua error" in the MM UI — useless to a non-technical merchant.
- **Decision:** Every callback returns a localized German error string sourced via `M_i18n.t("error.<key>")`. No `error()` calls escape the callback boundary. Internal `pcall`/`xpcall` is used where appropriate (Phase-5 `MM.sleep` pcall — ADR-0005 Carve-out 3).
- **Consequences:**
  - **Positive:** Users see actionable German error text directly in the MM UI ("API-Key abgelaufen. Bitte neu einfügen." rather than "attempt to index nil value").
  - **Positive:** Tests assert specific strings; locks the user-visible UX.
  - **Negative:** Stack traces are not exposed to users. Debug logs (DEBUG=true in dev only) carry the traces.
  - **Constraint:** New error states require a new i18n key + spec assertion. Phase-5 added `error.server_busy` + `error.token_revoked` per ERR-03 + ERR-04.
- **References:** MoneyMoney WebBanking API (`https://moneymoney.app/api/webbanking/`); ADR-0005 §Invariants 1–6; `src/i18n.lua` `error.*` table.

**Estimated size:** ~70 lines.

### 18. `docs/img/inoffizielle-extensions-erlauben.png` (NEW placeholder, W2; CP-5 for real)

**Role:** Visual aid for DOC-02 (screenshot-illustrated guide).

**Recommended approach for W2:** Create a small placeholder PNG (either 1×1 transparent or 600×400 with overlay text "Screenshot pending — Yves to capture per CP-5"). Keeps the markdown image reference valid; PR can render without broken-image icon.

**Add accompanying HTML comment** in `README.de.md` near each image:
```markdown
![Schalter in den Einstellungen](docs/img/inoffizielle-extensions-erlauben.png)
<!-- screenshot: pending — Yves to capture per CP-5 in MoneyMoney v2.4.x -->
```

A future PR (or post-merge commit) replaces the placeholder file. Markdown reference unchanged.

### 19. `docs/img/help-menu-extensions-folder.png` (NEW placeholder, W2)

Same approach as #18. Visual aid for the `Hilfe → Erweiterungen im Finder zeigen` menu step.

### 20. `docs/img/README.md` (NEW, W2)

**Role:** Track placeholder→real-image work queue.

**Recommended content:**

```markdown
# Screenshots queue

Placeholder images pending real capture (CP-5 in Phase 6 plan).

| Filename | Captures | Status |
|---|---|---|
| inoffizielle-extensions-erlauben.png | Toggle in MoneyMoney Einstellungen → Erweiterungen | placeholder |
| help-menu-extensions-folder.png | "Hilfe → Erweiterungen im Finder zeigen" menu item | placeholder |

To replace: capture in current-stable MoneyMoney (target version 2.4.x per ADR-0003); save at the same path; commit with `docs(img): capture <filename>`.
```

### 21. `spec/meta_no_tax_classification_spec.lua` (MODIFY, W1)

**Role:** META-03 invariant gate; Phase 6 extends scan target list to cover markdown docs.

**Closest analog:** itself.

**Recommended change:** Replace the `io.popen("ls src/*.lua")` enumeration with an explicit list that also includes documentation files. Pattern:

```lua
-- Replace the current src/*.lua-only enumeration with:
local SOURCE_TARGETS = {}
do
  local handle = io.popen("ls src/*.lua")
  if handle then
    for path in handle:lines() do
      SOURCE_TARGETS[#SOURCE_TARGETS + 1] = path
    end
    handle:close()
  end
end

local DOC_TARGETS = {
  "README.md",
  "README.de.md",
  "CONTRIBUTING.md",
  "CHANGELOG.md",
}
-- Also enumerate docs/adr/*.md
do
  local handle = io.popen("ls docs/adr/*.md 2>/dev/null")
  if handle then
    for path in handle:lines() do
      DOC_TARGETS[#DOC_TARGETS + 1] = path
    end
    handle:close()
  end
end
```

Then change the spec body:

```lua
describe("META-03: forbidden tax-classification phrases (D-55)", function()
  it("none of src/*.lua contains a forbidden phrase", function()
    for _, path in ipairs(SOURCE_TARGETS) do
      local hits = scan_file(path)
      assert.equals(0, #hits, format_hits(path, hits))
    end
    assert.is_true(#SOURCE_TARGETS >= 1)
  end)

  it("none of the documentation files contains a forbidden phrase", function()
    for _, path in ipairs(DOC_TARGETS) do
      -- Files MAY be absent at scan time (early in W2 before README.de.md
      -- lands); tolerate file-not-found.
      local f = io.open(path, "rb")
      if f then
        f:close()
        local hits = scan_file(path)
        assert.equals(0, #hits, format_hits(path, hits))
      end
    end
  end)

  it("dist/paypal-pos.lua contains no forbidden phrase (built artifact gate)", function()
    -- existing — unchanged
  end)
end)
```

**Wave-1 sequencing:** Land this spec extension EARLY in W1 — before W2 writes new doc content. The extended walker runs in CI on every push, so the W2 doc-writing tasks get instant feedback if they accidentally land a forbidden phrase.

**Caveat:** The current spec's `os.execute("lua tools/build.lua 2>/dev/null")` preamble already builds the artifact; the extension doesn't change that.

### 22. `spec/build_version_substitution_spec.lua` (NEW, W1)

**Role:** Verify the `__VERSION__` substitution per RESEARCH §3.

**Closest analog:** `spec/build_spec.lua` (existing — verifies the amalgamator's basic output).

**Recommended outline:**

```lua
-- spec/build_version_substitution_spec.lua
-- BUILD-03: __VERSION__ substituted from $GITHUB_REF_NAME

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local c = f:read("*a")
  f:close()
  return c
end

describe("BUILD-03: __VERSION__ substitution", function()

  it("substitutes from GITHUB_REF_NAME=v1.0.0 → version = 1.00", function()
    os.execute("GITHUB_REF_NAME=v1.0.0 lua tools/build.lua >/dev/null 2>&1")
    local content = read_file("dist/paypal-pos.lua")
    assert.matches("version%s*=%s*1%.00,", content)
    assert.is_nil(content:find("__VERSION__"), "__VERSION__ token still present")
  end)

  it("substitutes from GITHUB_REF_NAME=v1.2.3 → version = 1.20 (patch dropped)", function()
    os.execute("GITHUB_REF_NAME=v1.2.3 lua tools/build.lua >/dev/null 2>&1")
    local content = read_file("dist/paypal-pos.lua")
    assert.matches("version%s*=%s*1%.20,", content)
  end)

  it("substitutes from GITHUB_REF_NAME=v0.10.0 → version = 0.10", function()
    os.execute("GITHUB_REF_NAME=v0.10.0 lua tools/build.lua >/dev/null 2>&1")
    local content = read_file("dist/paypal-pos.lua")
    assert.matches("version%s*=%s*0%.10,", content)
  end)

  it("substitutes from GITHUB_REF_NAME=v1.0.0-rc.1 → version = 1.00 (rc suffix ignored)", function()
    os.execute("GITHUB_REF_NAME=v1.0.0-rc.1 lua tools/build.lua >/dev/null 2>&1")
    local content = read_file("dist/paypal-pos.lua")
    assert.matches("version%s*=%s*1%.00,", content)
  end)

  it("falls back to 0.00 when no tag and no GITHUB_REF_NAME (dev build)", function()
    -- Use env -i to scrub GITHUB_REF_NAME without affecting the parent test env.
    os.execute("env -u GITHUB_REF_NAME lua tools/build.lua >/dev/null 2>&1")
    local content = read_file("dist/paypal-pos.lua")
    -- Either 0.00 (no tag) or actual tag value (if local has a tag at HEAD).
    -- Tolerate both for portability of test env.
    assert.is_true(
      content:match("version%s*=%s*0%.00,") ~= nil
      or content:match("version%s*=%s*%d+%.%d+,") ~= nil,
      "expected either dev-build 0.00 or numeric version, got neither"
    )
    assert.is_nil(content:find("__VERSION__"), "__VERSION__ token still present")
  end)

  it("two consecutive builds with same env are byte-identical", function()
    os.execute("GITHUB_REF_NAME=v1.0.0 lua tools/build.lua --verify >/dev/null 2>&1")
    -- exit 0 = reproducible; assert via os.execute's return code on a re-run
    local ok = os.execute("GITHUB_REF_NAME=v1.0.0 lua tools/build.lua --verify >/dev/null 2>&1")
    assert.is_truthy(ok)
  end)
end)
```

**Caveats:**
- The `env -u` syntax may not be portable; macOS BSD `env` supports `-u`, GNU coreutils `env` supports `-u`. Both CI ubuntu-24.04 and macOS dev runs are covered.
- The spec needs `dkjson` and the standard mock layer — already provided by `spec/helpers/mm_mocks.lua` indirectly; the spec only invokes `tools/build.lua` and reads the output, so no MoneyMoney mocks are needed at all.

### 23. `.gitleaksignore` (CONDITIONAL, W1)

**Role:** Allowlist for legitimate JWT-shaped strings in test fixtures.

**Trigger:** Created ONLY if W1's first gitleaks dry-run flags fixtures. Otherwise omit entirely.

**Recommended format** (per RESEARCH §4):

```
# .gitleaksignore — line-by-line fingerprint allowlist
# Format: <fingerprint>:<path>:<line>
# Fingerprints come from `gitleaks detect` output's `Fingerprint:` field.

# Example (replace with real fingerprints from W1 dry-run):
# abc123def456:spec/fixtures/auth/jwt_sample.json:5
```

**Rule:** NEVER add a blanket `paths` exclusion (would defeat the gate). One line per false positive, with a comment explaining why.

---

## Wave Sequencing (recommended)

### Wave 1 — Scaffolding (no user-facing artifacts)
- File 5: `tools/build.lua` `__VERSION__` substitution
- File 8: `src/webbanking_header.lua` token replacement
- File 22: `spec/build_version_substitution_spec.lua` (RED-then-GREEN with file 5+8)
- File 2: `ci.yml` extensions (`print(` grep)
- File 3: `commit-lint.yml`
- File 2 or new: `gitleaks` job (with file 23 conditional)
- File 21: `spec/meta_no_tax_classification_spec.lua` walker extension
- (File 23 conditional)

**W1 acceptance:** all CI jobs green on a Phase-6 W1 PR; full suite (including new BUILD-03 spec) passes; gitleaks clean (with `.gitleaksignore` if needed); commit-lint passes; reproducible-build holds.

### Wave 2 — Trust-chain artifacts (user-facing + admin scripts)
- File 1: `release.yml`
- File 6: `tools/setup-branch-protection.sh`
- File 7: `tools/setup-repo-metadata.sh`
- File 9: `README.md` (English pointer rewrite)
- File 10: `README.de.md` (NEW)
- File 11: `CONTRIBUTING.md`
- Files 14, 15, 16, 17: 4 new ADRs
- Files 18, 19, 20: image placeholders + img README

**W2 acceptance:** extended META-03 walker stays green over the new docs; META-03 walker covers README.de.md; CONTRIBUTING.md; CHANGELOG.md; all 8 ADRs. Reproducible build still green. release.yml NOT triggered (no tag yet).

### Wave 3 — Cut v1.0.0 (post-merge to main)
- File 13: CHANGELOG.md v1.0.0 entry → commit on main
- CP-1: loop-lektor pass on README.de.md + CHANGELOG German wording
- CP-2: Yves runs `bash tools/setup-branch-protection.sh`
- CP-3: Yves runs `bash tools/setup-repo-metadata.sh`
- CP-5: Yves captures real screenshots
- CP-4: Yves runs `git tag -s v1.0.0 -m "Release v1.0.0\n\n<changelog excerpt>"` + `git push origin v1.0.0`
- release.yml fires; publishes v1.0.0 release with `.lua` + `.sha256`

**W3 acceptance:** GitHub Release v1.0.0 visible; artifact downloadable; sha256 verifies; tag annotation matches release notes; `WebBanking{version}` in the artifact equals `1.00`.

---

## Cross-cutting notes for the planner

- **Sequencing constraint:** W2's release.yml file SHOULD land WITHOUT pushing a stable tag. Yves does an `rc.1` dry-run before the v1.0.0 tag.
- **CP-4 prerequisite:** before any tag push, the `MAINTAINER_GPG_PUBKEY` secret must be uploaded (Yves task; one-liner in CONTRIBUTING.md). The release.yml would otherwise fail at job 1.
- **Idempotency property:** every Phase-6 tool script (branch-protection, repo-metadata) is idempotent. Re-running them is safe.
- **No new runtime code:** `src/*.lua` modifications are limited to `webbanking_header.lua` (1 line). The shipped runtime behavior is byte-identical to Phase 5 except for the `version` field literal.
- **META-03 surface area** EXPANDS in this phase (walker now covers ~10 markdown files instead of just `src/*.lua` + `dist/paypal-pos.lua`). Pre-merge audit of every new doc against the 13-phrase list is W1/W2's gating discipline.
- **No new external dependencies in the shipped artifact.** Only new GitHub Actions deps + Lua substitution logic in `tools/build.lua`. Sandboxing posture unchanged.

---

*Phase: 06-release-polish*
*Patterns mapped: 2026-06-22*
