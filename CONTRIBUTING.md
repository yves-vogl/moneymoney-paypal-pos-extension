# Contributing

Thank you for considering a contribution to this MoneyMoney PayPal POS extension.
This guide covers the development loop, testing conventions, the amalgamator
architecture, the release process, and the commit/PR discipline this repository
enforces.

> The primary user documentation is German (`README.de.md`). This contributor
> guide is English so it is approachable for non-German collaborators.

---

## Code of conduct

Be respectful. Discuss code, not people. Assume good intent. If you find a
security issue, do not open a public issue — follow the disclosure path in
[`SECURITY.md`](SECURITY.md).

---

## Development loop

### Prerequisites

- **macOS** or Linux with a Lua 5.4 toolchain. On macOS:
  ```bash
  brew install lua@5.4 luarocks
  ```
- LuaRocks-installed development dependencies:
  ```bash
  luarocks install busted
  luarocks install luacheck
  luarocks install luacov
  luarocks install dkjson
  ```
- `gpg` (for signing commits and tags) and a published GPG public key
  associated with your committer email.

### Source layout

```
src/                  one concern per file; the amalgamator concatenates these
  webbanking_header.lua   WebBanking{...} registration + cross-module M_* locals
  log.lua                 M_log + SEC-01 redactor
  i18n.lua                German error/account/transaction strings
  errors.lua / model.lua / http.lua / auth.lua / ...
  entry.lua               MoneyMoney callbacks (top-level globals)
tools/
  build.lua             pure-Lua amalgamator (see ADR-0001)
  manifest.txt          ordered module list — DO NOT edit lightly
  setup-branch-protection.sh   one-time admin (CP-2)
  setup-repo-metadata.sh       one-time admin (CP-3)
spec/                 busted specs, 1:1 with src/<module>.lua
  fixtures/             JSON fixtures recorded from real / sandbox responses
  helpers/mm_mocks.lua  Connection() / JSON() / LocalStorage / MM.* mocks
docs/adr/             MADR-format Architecture Decision Records
.planning/            phase plans, research, context — read-only during impl
```

### Test loop

```bash
# Single spec (fastest feedback)
./.luarocks/bin/busted spec/log_spec.lua

# Full suite with coverage
./.luarocks/bin/busted --coverage spec/

# Static analysis
./.luarocks/bin/luacheck .

# Amalgamate + reproducible-build check
lua tools/build.lua
lua tools/build.lua --verify    # builds twice, asserts byte-identical SHA-256
```

`--verify` is the gate CI runs on every push. If it fails locally, your source
introduces non-determinism (a `print` of a timestamp, an `os.time()` call, an
env-var read) — fix it before submitting a PR.

### Pre-commit checklist

Before pushing, verify each of the following:

- [ ] `busted spec/` green (`N successes / 0 failures / 0 errors / 0 pending`).
- [ ] `luacheck .` clean (0 warnings, 0 errors).
- [ ] `lua tools/build.lua --verify` prints `OK: reproducible (sha256: ...)`.
- [ ] Commit message follows [Conventional Commits](https://www.conventionalcommits.org).
- [ ] Commit is GPG-signed: `git commit -S -m "..."` (or globally enabled via
      `git config commit.gpgsign true`).
- [ ] No AI attribution in commit message or staged files — explicitly: no
      `Co-Authored-By: Claude`, no `Generated with Claude`, no robot-emoji.
      A CI gate scans for these patterns and fails the workflow.

---

## Testing conventions

- **TDD: RED → GREEN.** Write the failing spec first (commit prefix `test:`),
  then the implementation that makes it pass (commit prefix `feat:` or `fix:`).
  Each RED commit must show a failing test in `busted` output; each GREEN
  commit must show the test transitioning to passing.
- **mm_mocks.lua is the only mock boundary.** Tests stub MoneyMoney's globals
  (`Connection`, `JSON`, `LocalStorage`, `MM`, `WebBanking`, account types,
  `MM.sleep`) inside `spec/helpers/mm_mocks.lua`. Do not introduce ad-hoc
  module-level monkey-patches in individual spec files — keep the mock surface
  in one auditable place.
- **Fixtures under `spec/fixtures/`.** Record realistic JSON responses from the
  Zettle sandbox (NEVER production) and commit them. Tests load fixtures via a
  helper rather than embedding multi-line JSON literally.
- **Negative-path coverage matters.** Every error path returning a localized
  error string must have a spec asserting the exact string — that lock-in is
  the contract with the user (see ADR-0008).

---

## Architecture

### Amalgamator (ADR-0001)

The shipped artifact is a single `dist/paypal-pos.lua` file. `tools/build.lua`
reads `tools/manifest.txt` to determine module order, concatenates each
`src/*.lua` module wrapped in a `do … end` block (with a
`-- === MODULE: <name> ===` banner), and emits `src/webbanking_header.lua`
verbatim at the top + `src/entry.lua` verbatim at the bottom (MoneyMoney
requires the registration table and the callback functions at top scope).

Cross-module references go through the predeclared `M_*` global tables in
`src/webbanking_header.lua` — **you cannot `require()` a sibling**. The
sandbox does not expose `package.path` for non-stdlib modules.

The build is deterministic. Same input + same `$GITHUB_REF_NAME` produces
byte-identical output (verified by `--verify`). See `docs/adr/0001-amalgamator-design.md`
for the full rationale.

### Error pattern (ADR-0008)

Every MoneyMoney callback (`InitializeSession2`, `ListAccounts`,
`RefreshAccount`, `EndSession`) returns either `nil` / a success value (per
the WebBanking API contract) or a **localized German error string** via
`M_i18n.t("error.<key>")`. The raw Lua `error()` mechanism is reserved for
truly unrecoverable internal failures (caught by `pcall` at the callback
boundary). See `docs/adr/0008-string-return-error-pattern.md`.

### Logging (SEC-01)

Use `M_log.info / warn / error` — never `print()` directly. `M_log` runs every
emission through the SEC-01 redactor which strips JWT shape and `Bearer`
tokens before the line reaches MoneyMoney's stdout. The single legitimate raw
`print(` call (M_log's emission point in `src/log.lua`) is marked with the
inline sentinel `-- D-79-allowed: M_log emission point`; CI fails the build
if any other `print(` slips into the artifact.

---

## Release process

### Cutting a release (maintainer)

```bash
# 1. Update CHANGELOG.md — move [Unreleased] entries under a new [X.Y.Z] header
#    with today's date.
$EDITOR CHANGELOG.md

# 2. Commit on main via PR (branch protection requires PR + green CI).
git checkout -b release/vX.Y.Z
git add CHANGELOG.md
git commit -S -m "docs(release): cut vX.Y.Z"
gh pr create --base main --title "release: vX.Y.Z" --body "$(cat <<EOF
Cuts CHANGELOG entry for vX.Y.Z. Tag will be pushed after merge.
EOF
)"
# … review, merge …

# 3. Once main is updated, sign-tag from main:
git checkout main && git pull
git tag -s vX.Y.Z -m "Release vX.Y.Z

$(awk "/^## \\[X.Y.Z\\]/{flag=1;next} /^## \\[/{flag=0} flag" CHANGELOG.md)"
git push origin vX.Y.Z

# 4. .github/workflows/release.yml fires automatically:
#    - Job 1 verifies the tag was signed by the maintainer key.
#    - Job 2 lints, tests, builds with __VERSION__ substitution, computes SHA256.
#    - Job 3 publishes the GitHub Release with paypal-pos.lua + .sha256 attached.
```

### First-time setup (maintainer)

These three one-liners are run once after the initial repo setup or after
rotating the maintainer GPG key. They are documented in
`tools/setup-branch-protection.sh` and `tools/setup-repo-metadata.sh`.

```bash
# Upload the maintainer's public key as a workflow secret (release.yml uses it
# to verify the signed tag). Public key only — never the private key.
gpg --armor --export FDE07046A6178E89ADB57FD3DE300C53D8E18642 \
  | gh secret set MAINTAINER_GPG_PUBKEY

# Apply branch protection to main (requires PAT with Administration: write).
# Script degrades gracefully — prints the manual UI steps if scope is missing.
bash tools/setup-branch-protection.sh

# Set the repo description + 7 topics (idempotent; uses PUT for exact-set).
bash tools/setup-repo-metadata.sh
```

### Dry-running a release

Push an `rc.N` tag first; `release.yml` publishes it as a GitHub prerelease
(based on the dynamic `prerelease: ${{ contains(github.ref_name, '-rc.') }}`
expression). Verify `paypal-pos.lua` + `paypal-pos.lua.sha256` attach
successfully before pushing the stable tag:

```bash
git tag -s v1.0.0-rc.1 -m "Release v1.0.0-rc.1 (dry run)"
git push origin v1.0.0-rc.1
# … inspect the prerelease on GitHub …
# … then later …
git tag -s v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

---

## Commit conventions

This repository enforces [Conventional Commits 1.0.0](https://www.conventionalcommits.org)
on every commit subject. Allowed type prefixes:

```
feat | fix | docs | test | refactor | chore | ci | build | perf | style | revert
```

Optional scope in parentheses: `feat(03-02): add foo`. A CI workflow
(`commit-lint.yml`) walks every commit in the PR's range and fails on the
first non-conforming subject.

Examples:

```
feat(auth): JWT-bearer assertion-grant flow
fix(http): handle 429 Retry-After across pagination cursor
docs(adr): backfill ADR-0007 no-TLS-pinning rationale
test(05-02): RED for ERR-04 token-revoked recovery
```

All commits and tags MUST be GPG-signed. Branch protection on `main`
enforces this serverside — unsigned commits cannot be merged.

---

## ADRs

Architectural decisions are recorded as MADR-format documents under
`docs/adr/`, numbered sequentially:

```
docs/adr/0001-amalgamator-design.md
docs/adr/0002-localstorage-token-cache.md
docs/adr/0003-sandbox-probe-results.md
docs/adr/0004-finance-api-scope-and-fee-fallback.md
docs/adr/0005-resilience-invariants.md
docs/adr/0006-jwt-bearer-only-auth.md
docs/adr/0007-no-tls-pinning.md
docs/adr/0008-string-return-error-pattern.md
```

If your contribution locks in a new architectural choice — anything that
constrains future PRs (e.g. a new module boundary, a new ERR-`*` invariant,
a new dependency, a new file under `src/`) — open a new ADR alongside the
implementing commits. Use ADR-0001 as the section-shape template
(`Status / Date / Deciders / Context / Decision / Consequences / References`).

---

Questions? Open a [Discussion](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/discussions).
