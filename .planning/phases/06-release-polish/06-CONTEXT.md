# Phase 6: Release & Polish — Reproducible Build, CI/CD, German Docs - Context

**Gathered:** 2026-06-22 (autonomous draft within Yves' full-backlog mandate)
**Status:** Ready for planning — Yves checkpoints expected for (1) loop-lektor pass on German README + GoBD-Hinweis wording, (2) `gh repo edit` admin permissions for branch protection + topics + description, (3) initial GPG-signed tag publication

<domain>
## Phase Boundary

Make the extension installable, verifiable, and trustworthy for a stranger landing on GitHub. Reproducible-build SHA256-attached release from a GPG-signed tag; bilingual docs with German-primary `README.de.md` carrying the "Inoffizielle Extensions erlauben" screenshot guide + GoBD-Hinweis that explicitly does NOT claim conformance; CONTRIBUTING.md (English) for contributor onboarding; MADR ADRs for every locked architectural decision (amalgamator, LocalStorage cache, JWT-bearer-only, fee modeling, no-TLS-pinning, string-return errors, sandbox probes); MIT LICENSE; Dependabot + gitleaks + CI matrix on Lua 5.4. Phase 6 closes v1.0.0 — the artifact ships from `softprops/action-gh-release@v2` with `paypal-pos.lua` + `paypal-pos.lua.sha256` attached.

**In scope:**
- `.github/workflows/release.yml` — tag-triggered release pipeline (verify GPG tag signature; run lint+test+coverage+reproducible-build-diff; substitute `__VERSION__` from tag into the artifact; build twice in clean checkouts and assert byte-identity; attach `.lua` + `.sha256` via softprops/action-gh-release@v2)
- `.github/workflows/ci.yml` extensions — coverage gate (≥85% on src/ excluding webbanking_header.lua; regression fails the pipeline) + gitleaks (or equivalent) + commitlint-style commit-message check on PRs
- `.github/dependabot.yml` — track GitHub Actions versions + LuaRocks tooling (busted / luacheck / luacov / dkjson) via custom ecosystem config OR fall back to a periodic-review note
- `tools/build.lua` extension — `__VERSION__` substitution from `git describe --tags` or `$GITHUB_REF_NAME`; CI passes the tag name as env var so the build is deterministic per-tag
- `README.de.md` (NEW; German-primary) — sections: was die Extension macht / Installation step-by-step with "Inoffizielle Extensions erlauben" screenshot + macOS sandboxed vs non-sandboxed paths / Konto hinzufügen step-by-step (API-Key generieren + READ:FINANCE scope; Phase-2/4 ADR-0004 already covers re-paste path) / Was die Extension nicht macht / Bekannte Grenzen (D-49 cross-refresh fee re-classification + ERR-04 re-enter-API-key UX; pre-existing in current README.md) / GoBD-Hinweis (explicitly NOT a conformance claim per META-03; "Diese Extension stellt Rohdaten dar — Klassifizierung obliegt der Steuerberatung") / Lizenz + Mitwirken
- `README.md` (English; secondary) — abbreviated version pointing to README.de.md as the canonical install guide; the same Bekannte Grenzen / GoBD-Hinweis sections in English; CONTRIBUTING.md link
- `CONTRIBUTING.md` (English) — dev loop (busted + luacheck locally; CI gates); testing conventions (TDD RED→GREEN; spec/helpers/mm_mocks.lua boundary); amalgamator (tools/build.lua + tools/manifest.txt; no `require()` of siblings); release process (GPG-signed tag; manual `gh release create` if CI bypass needed); commit conventions (Conventional Commits; GPG-signed; no AI attribution)
- `LICENSE` (MIT; copyright "Yves Vogl")
- `CHANGELOG.md` — Keep-a-Changelog format already in place from Phase 4; Phase 6 finalizes the [0.x.y] structure and the unreleased→released transition
- ADR backfill: `docs/adr/0002-localstorage-token-cache.md`, `docs/adr/0006-jwt-bearer-only-auth.md` (Phase 7 forward-compat note), `docs/adr/0007-no-tls-pinning.md` (out-of-scope rationale; mitigations from Phase-1 Q8), `docs/adr/0008-string-return-error-pattern.md` (Phase-2 decision retro-documented). ADRs 0001 (amalgamator), 0003 (sandbox probes), 0004 (Finance scope + fee fallback), 0005 (resilience) already exist.
- GPG-signed-commits branch protection on `main` (via `gh api` or manual; documented in CONTRIBUTING.md if Yves' API token lacks Administration:write — Plan tasks degrade gracefully)
- Repo metadata via `gh repo edit`: description (German per ROADMAP) + 7 topics (`moneymoney`, `moneymoney-extension`, `paypal-pos`, `zettle`, `lua`, `germany`, `accounting`)
- v1.0.0 SemVer tag: GPG-signed `git tag -s v1.0.0`; release artifact published via the new release.yml workflow; LICENSE file shipped

**Out of scope:**
- The v0.2.x cleanup items deferred from Phase 5 (`Retry-After: 0` no-op; ADR-0005 inferred-400 carve-out wording; stylistic IN-01..04) — pick up in a v1.0.1 cleanup PR if time remains
- Actual Q3 sandbox probe execution by Yves (Plan 04-01 — still queued; doesn't block v1.0.0 ship since `finance.izettle.com` is OpenAPI-confirmed and CI egress allowlist gates it)
- Q9 `MM.sleep` probe execution (Plan 05-01 optional; doesn't block)
- loop-lektor full pass on every German string in the repo — bundled into a Yves-checkpoint task; Phase 6 lands engineering-grade text with `<!-- lektor-review: pending -->` markers so Yves can refine before tagging
- Multi-language docs beyond DE + EN — out of scope for v1.0.0 per PROJECT.md
- ZUGFeRD / DATEV export integration — Phase 8+ if it ever lands
- Telemetry of any kind — explicit non-goal per PROJECT.md
- Phase 6.1 OpenSSF Scorecard hardening — separate roadmap phase, depends on Phase 6 ship

</domain>

<decisions>
## Implementation Decisions

Numbering continues from Phase 5 (D-69). Phase 6 = D-70..D-82.

- **D-70** README structure: `README.de.md` is the German-primary canonical install/usage guide; `README.md` (English) is a short pointer to `README.de.md` for technical visitors + the same Bekannte Grenzen / GoBD-Hinweis sections. GitHub's repo page defaults to `README.md` so the English pointer is the first impression for non-German visitors; the German file is one click away and is the primary user surface.
- **D-71** GoBD-Hinweis exact wording (subject to loop-lektor refinement; engineering placeholder): "Hinweis zur Buchhaltung: Diese Extension liest Rohdaten aus der PayPal POS API und stellt sie in MoneyMoney dar. Sie erhebt KEINEN Anspruch auf GoBD-Konformität, DATEV-Export oder steuerrechtliche Bewertung. Die Klassifizierung der Umsätze (Erlöse, Aufwendungen, Vorsteuer, etc.) obliegt der Buchhaltung bzw. der Steuerberatung. Die Extension ersetzt keine Buchhaltungssoftware." — META-03-compliant (no use of the 13 forbidden phrases; explicitly disclaims classification). Loop-lektor finalizes for v1.0.0.
- **D-72** GPG-signed-tag release flow: `.github/workflows/release.yml` triggers on tags matching `v[0-9]+.[0-9]+.[0-9]+` (and `v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+` for pre-releases). Job 1 verifies the tag is GPG-signed by importing the maintainer's public key from a workflow secret (`MAINTAINER_GPG_PUBKEY`) and asserting `git verify-tag $GITHUB_REF_NAME` exits 0. Job 2 runs lint+test+coverage+reproducible-build-diff (mirrors ci.yml). Job 3 substitutes `__VERSION__` → `$GITHUB_REF_NAME` (without the `v` prefix) into the built `dist/paypal-pos.lua`; computes `sha256sum`; publishes via `softprops/action-gh-release@v2` with `prerelease: contains(github.ref_name, '-rc.')`. Maintainer's GPG key fingerprint `FDE07046A6178E89ADB57FD3DE300C53D8E18642` is the only accepted signature.
- **D-73** `__VERSION__` substitution: `tools/build.lua` reads the tag name from `$GITHUB_REF_NAME` (CI) or `git describe --tags --exact-match 2>/dev/null` (local). If neither is available, falls back to `dev-${short_sha}`. The substitution replaces a literal `__VERSION__` token in `src/webbanking_header.lua`'s `WebBanking{version = __VERSION__}` line (currently `version = 0.00` placeholder per Phase-1). Build is deterministic per tag — same tag = same SHA across runners.
- **D-74** Branch protection on `main`: requires (a) PR before merge, (b) GPG-signed commits, (c) CI green (Lint+tests+reproducible-build + coverage + gitleaks + commit-lint), (d) linear history (no merge commits). Configured via `gh api` in a setup script under `tools/setup-branch-protection.sh` that Yves runs once with a Fine-Grained PAT (`Administration: write` scope). If Yves' token lacks that scope, the script prints the manual GitHub UI steps and exits 0 (degradation, not failure).
- **D-75** Coverage gate: ≥85% line coverage on `src/` excluding `webbanking_header.lua` (placeholder file); enforced via `luacov` + a custom assertion script that exits non-zero if the threshold is missed. Phase-3 + Phase-4 + Phase-5 landed at 99-100%; the 85% floor is the regression bound, not the target.
- **D-76** Secret scanning: gitleaks v8 (action `gitleaks/gitleaks-action@v2`) on push + PR; configured to scan history + working tree for JWT shape, AWS keys, GitHub PATs, Zettle assertion-grant patterns. Failure blocks the PR. The action is free for public repos.
- **D-77** Dependabot: `.github/dependabot.yml` tracks `github-actions` ecosystem (weekly); LuaRocks tooling versions are pinned in CI via the leafo actions' version field (not Dependabot-tracked — LuaRocks is not a Dependabot-supported ecosystem). A weekly issue-creation workflow could be added later to remind manually checking LuaRocks for `busted` / `luacheck` / `luacov` updates; out of scope for v1.0.0.
- **D-78** Commit-message lint: GitHub Action enforcing Conventional Commits on PR titles (no commitlint Node toolchain needed; a 30-line shell-based regex assertion in `.github/workflows/commit-lint.yml` matches the `(feat|fix|docs|test|refactor|chore|ci|build|perf|style)(\(.+\))?: .+` pattern on every commit in the PR's range).
- **D-79** Egress allowlist hardening (extends Phase-4 CI gate): the `dist/paypal-pos.lua` artifact MUST contain only `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com` URLs. CI greps via regex + TLD-pattern complementary check (Phase-4 S-05 fix), fails the build on any unauthorized host. Also greps for `print` calls bypassing `M_log` (D-27 inheritance — should be zero in shipped src/, only in tools/ which isn't amalgamated).
- **D-80** ADR backfill: every locked architectural decision gets a MADR. Phase 6 adds: ADR-0002 (LocalStorage cache contract per Phase-2), ADR-0006 (JWT-bearer-only auth + Phase-7 OAuth-Code forward-compat per Yves' 2026-06-21 checkpoint), ADR-0007 (no TLS pinning rationale + mitigations), ADR-0008 (string-return error pattern per WebBanking API contract). ADR-0001/0003/0004/0005 already exist.
- **D-81** CHANGELOG.md finalization: v0.2.0 entry from Phase 4 stays; v0.2.x cleanup deferrals listed under [Unreleased]; v1.0.0 entry added on tag with explicit "First stable release" notice + the full feature set + the documented limitations (D-49 fee re-classification + ERR-04 token-revoked UX + 90-day initial sync clamp + non-EUR skip).
- **D-82** Repo metadata (`gh repo edit` invocation): description = "MoneyMoney-Extension für PayPal POS — Karten-Umsätze, Refunds, Gebühren und Auszahlungen direkt in MoneyMoney. Open Source, MIT, GPG-signiert."; topics = `moneymoney moneymoney-extension paypal-pos zettle lua germany accounting`. Configured via `gh repo edit yves-vogl/moneymoney-paypal-pos-extension --description "..." --add-topic ...` in `tools/setup-repo-metadata.sh` — Yves runs once with his PAT.

### Claude's Discretion
- README.de.md screenshot — placeholder image `docs/img/inoffizielle-extensions-erlauben.png` referenced; Yves captures the actual screenshot in MoneyMoney (or uses an existing community screenshot if license permits). Plan task creates the placeholder + `<!-- screenshot: pending -->` marker.
- ADR-0006 wording for the Phase-7 forward-compat: cross-reference the existing ROADMAP Phase 7 entry; brief enough to not duplicate but precise enough that a future Phase-7 implementer understands the v1.0.0 baseline.
- Coverage threshold 85% vs 90% — recommend 85% per ROADMAP success-criterion 2 wording; tighter is a v1.0.x ratchet decision, not a Phase-6 one.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap + Requirements
- `.planning/ROADMAP.md` §"Phase 6: Release & Polish" — 6 success criteria + 22 requirement IDs
- `.planning/REQUIREMENTS.md` — BUILD-03..06, CI-01..06, SEC-02, SEC-05, DOC-01..10 verbatim
- `.planning/PROJECT.md` — no telemetry; MIT license; German-primary docs; SemVer

### MoneyMoney
- `moneymoney.app/api/webbanking/` — `WebBanking{version=...}` field semantics
- `https://moneymoney.app/extensions/` — community extensions index (Phase 6 doc-wise reference; the README pointer to the canonical install path uses MoneyMoney's documented "Hilfe → Erweiterungen im Finder zeigen" menu)

### Existing ADRs (preserve unchanged unless explicitly amended)
- `docs/adr/0001-amalgamator-design.md` (Phase 1 — amalgamator decision)
- `docs/adr/0003-sandbox-probe-results.md` (Phase 1 — Q1..Q8 closed; Q3 + Q9 OPTIONAL/DEFERRED)
- `docs/adr/0004-finance-api-scope-and-fee-fallback.md` (Phase 4 — READ:FINANCE migration + D-49)
- `docs/adr/0005-resilience-invariants.md` (Phase 5 — ERR-01..06 contracts + carve-outs)

### CI/CD action references
- `softprops/action-gh-release@v2` — already in CLAUDE.md research as the de-facto standard
- `leafo/gh-actions-lua@v13` + `leafo/gh-actions-luarocks@v6.1.0` — Phase-1 CI baseline
- `gitleaks/gitleaks-action@v2` — secret scan (free for public repos)
- `dependabot.yml` schema — `version: 2` with `package-ecosystem: github-actions`

### Phase-2/3/4/5 inheritances
- D-27 redactor; D-29 hardcoded production URLs; D-31..D-69 all preserved
- Phase-4 ADR-0004 README "Inbetriebnahme bei bestehendem v0.1.0 API-Key" section — Phase 6 promotes to README.de.md primary surface
- Phase-4 META-03 13-phrase forbidden-strings list — Phase 6 docs MUST avoid all 13

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tools/build.lua` — Phase-1 amalgamator; extends in D-73 with `__VERSION__` substitution
- `tools/manifest.txt` — Phase-1; unchanged
- `.github/workflows/ci.yml` — Phase-1+2+4 baseline; extends in D-75/D-76/D-78/D-79
- `CHANGELOG.md` — Phase-4 v0.2.0 entry already in Keep-a-Changelog format
- `README.md` — Phase-4 v0.2.0 sections (engineering-grade German); Phase 6 promotes content to README.de.md and reduces README.md to a pointer
- `spec/meta_no_tax_classification_spec.lua` — Phase-4 META-03 walker; Phase 6 extends to walk README.de.md + README.md + CONTRIBUTING.md + every docs/adr/*.md

### Established Patterns
- Conventional Commits (`(scope):` prefix) — Phase 6 adds CI lint
- GPG-signed commits + tags — Phase 6 enforces via branch protection
- TDD RED→GREEN — Phase 6's spec extensions (META-03 walker) follow
- No `require()` of siblings — Phase 6 doesn't touch src/ except `src/webbanking_header.lua` for the `__VERSION__` placeholder

### Integration Points
- `tools/build.lua` reads `$GITHUB_REF_NAME` → substitutes `__VERSION__` in `src/webbanking_header.lua` during the build pass; no other source change
- `.github/workflows/release.yml` (NEW) consumes tag → invokes build with the version env → uploads artifact
- `tools/setup-branch-protection.sh` + `tools/setup-repo-metadata.sh` (NEW) are one-time Yves-run scripts; documented in CONTRIBUTING.md as part of release process

</code_context>

<specifics>
## Specific Ideas

- **GoBD-Hinweis precision is load-bearing.** A German merchant's Steuerberater reading the README must not infer any classification claim. The D-71 wording explicitly says "stellt Rohdaten dar" and "obliegt der Steuerberatung" — these are facts, not classifications. META-03 forbidden-strings walker MUST extend to README.de.md + README.md so a future PR can't accidentally drift into forbidden phrasing.
- **The GPG-signed-tag workflow is the trust chain.** D-72 must verify the signature BEFORE the build step runs — a malformed or unsigned tag should fail the workflow at job 1 without consuming CI minutes. The maintainer key fingerprint is recorded in CLAUDE.md and STATE.md memory.
- **Reproducible-build-diff in CI** already exists per Phase-1 D-31. Phase 6 ensures the diff runs on every release-workflow invocation too (not just CI), and the diff output is published as a release asset alongside the artifact.
- **The "Inoffizielle Extensions erlauben" screenshot is non-negotiable for German user trust.** Even an engineering-grade placeholder image with the German UI labels overlay is acceptable for v1.0.0; loop-lektor + Yves can replace with a real screenshot for v1.0.1.
- **Branch protection enforcement is a Yves-blocker.** The Phase-6 plan task creates the helper script but cannot actually configure branch protection without admin permissions on the repo. Plan task acceptance criterion is "script exists and prints either success or the manual UI steps" — not "branch protection is verifiably enabled".
- **Coverage gate enforcement** uses a custom Lua script (~30 lines) reading `luacov.report.out` and exiting non-zero if any `src/*.lua` (except webbanking_header.lua) drops below 85%. Phase-3/4/5 landed 99-100% so the gate is regression-protection, not target-setting.

</specifics>

<deferred>
## Deferred Ideas

- LuaRocks dependency-update bot — out of scope for v1.0.0 (Dependabot doesn't support LuaRocks; weekly manual review is fine)
- ZUGFeRD / DATEV export — far-future (Stretch Goal in ROADMAP)
- Multi-language docs (FR / ES / IT) — Stretch Goal; v1.0.x if real user demand
- Automated screenshot capture (Playwright + MoneyMoney UI automation) — way out of scope
- Hosted documentation site (docs.paypal-pos-plugin.org or similar) — not needed for a single-file extension; README.de.md is the doc site
- v0.2.x cleanup items deferred from Phase 5 — bundle into v1.0.1 cleanup PR after v1.0.0 ships
- Plan 04-01 Q3 sandbox probe + Plan 05-01 Q9 `MM.sleep` probe — both still queued for Yves; don't block v1.0.0

</deferred>

---

## Yves Blockers (autonomous-window pauses)

Phase 6 has fewer technical blockers than Phase 4/5 but more admin-permission / wording checkpoints:

| ID | Item | Type | Recommended | Yves Action |
|----|------|------|-------------|------------------|
| **CP-1** | loop-lektor pass on README.de.md + GoBD-Hinweis (D-71 wording) | Pay/Compliance + brand voice | Engineering placeholder lands now; lektor finalizes pre-v1.0.0-tag | One pass through README.de.md + CHANGELOG.md + ADR-0004 + ADR-0005 strings |
| **CP-2** | Branch protection on `main` (D-74) | Admin permissions | Helper script lands; Yves runs with PAT | `bash tools/setup-branch-protection.sh` with `Administration:write` PAT |
| **CP-3** | Repo metadata (D-82 description + topics) | Admin permissions | Helper script lands; Yves runs with PAT | `bash tools/setup-repo-metadata.sh` |
| **CP-4** | First GPG-signed v1.0.0 tag publication | Release ceremony | All workflows + CHANGELOG entry land in this PR; Yves tags post-merge | `git tag -s v1.0.0 -m "Release v1.0.0"` + `git push origin v1.0.0` |
| **CP-5** | `inoffizielle-extensions-erlauben.png` screenshot (D-70) | Asset capture | Placeholder image lands with `<!-- screenshot: pending -->` | Capture in MoneyMoney + replace placeholder |

CP-1 + CP-5 are pre-tag; CP-2 + CP-3 + CP-4 are post-merge. Nothing blocks the Phase-6 PR from opening.

---

*Phase: 06-release-polish*
*Context gathered: 2026-06-22*
