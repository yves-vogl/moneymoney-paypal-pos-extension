# Contributing

Thank you for considering a contribution to this MoneyMoney PayPal POS extension.
This guide covers the development loop, testing conventions, the amalgamator
architecture, the release process, and the commit/PR discipline this repository
enforces.

> The user documentation in [`README.md`](README.md) is German. This contributor
> guide is in English so non-German collaborators can read it without
> translation friction.

---

## Code of conduct

This project has adopted the Contributor Covenant v2.1 — see
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). In short: be respectful, discuss
code, not people, assume good intent. If you find a security issue, do not
open a public issue — follow the disclosure path in
[`SECURITY.md`](SECURITY.md). Project roles and decision-making are
documented in [`GOVERNANCE.md`](GOVERNANCE.md).

---

## Development loop

### Prerequisites

- **macOS** or Linux with a Lua 5.4 toolchain. On macOS:
  ```bash
  brew install lua@5.4 luarocks
  ```
- LuaRocks-installed development dependencies. Install them from the pinned
  manifest rather than by name, so you get the same versions CI uses:
  ```bash
  luarocks install --only-deps moneymoney-paypal-pos-extension-dev-1.rockspec
  ```
  [`moneymoney-paypal-pos-extension-dev-1.rockspec`](moneymoney-paypal-pos-extension-dev-1.rockspec)
  is a dev-only manifest — the shipped artifact has no runtime dependencies.
  It pins `busted`, `luacheck`, `luacov` and `dkjson` to exact
  version-revisions. Do not bump a pin by hand-installing a newer rock
  locally; change the manifest in a PR so CI validates it. LuaRocks is not
  covered by Dependabot, so
  [`.github/workflows/lua-toolchain-audit.yml`](.github/workflows/lua-toolchain-audit.yml)
  checks the pins against luarocks.org weekly and files an issue when they
  drift.
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
- [ ] No AI authorship attribution in commit messages or staged files.
      Specifically: do not include `Co-Authored-By` trailers naming AI
      assistants, do not include "Generated with" attributions, and do not
      include robot emojis as authorship markers. A CI gate scans the
      working tree for these patterns (see `.github/workflows/ci.yml` →
      "No-AI-attribution gate") and fails the workflow on any match.

---

## Coding style

This is the project's identified coding style (OpenSSF Best Practices
`coding_standards` / `coding_standards_enforced`):

- **2-space indentation**, no tabs.
- **snake_case** for locals, functions and table fields; the `M_*` prefix is
  reserved exclusively for the cross-module tables predeclared in
  `src/webbanking_header.lua` (`M_log`, `M_auth`, `M_http`, `M_mapping`, …) —
  never use it for anything else.
- **One file, one concern.** Each `src/*.lua` module owns a single
  responsibility (see the source-layout table above); do not fold unrelated
  logic into an existing module to avoid adding a file.
- **No cross-module `require()`.** The amalgamator resolves module
  boundaries at build time via the `M_*` globals (ADR-0001) — a sibling
  module is always referenced through its `M_*` table, never captured as a
  local across files.
- **No `require()`, `io.*`, `os.execute()`, `os.popen()`, or `DEBUG = true`
  in `src/*.lua`.** The sandbox exposes these globals, but the build's H8 /
  SEC gates reject their use as a code-discipline rule (ADR-0003).
- **Every `print()` goes through `M_log`.** Direct `print()` calls bypass
  the SEC-01 redactor and can leak a token into MoneyMoney's log; the sole
  exception is `M_log`'s own emission point, marked with the
  `-- D-79-allowed: M_log emission point` sentinel.

**Enforcement:** [`luacheck`](https://github.com/lunarmodules/luacheck) 1.2.0
runs against the ruleset in [`.luacheckrc`](.luacheckrc) (`std =
"lua54+busted"`, an explicit `read_globals` allowlist for every MoneyMoney
built-in, and an explicit `globals` list for the handful of top-level
callbacks/module tables the sandbox requires). It is a required, blocking
status check (`Lint + tests + reproducible build` in `.github/workflows/ci.yml`)
on every push and pull request — a PR with any luacheck warning cannot merge.
Style deviations that luacheck cannot express (the `M_*` prefix convention,
the no-`require()` rule, the `print()`-via-`M_log` rule) are additionally
enforced by the amalgamator's H8/SEC build gates (`tools/build.lua`) and by
review against this document.

---

## Testing conventions

### Test policy (binding)

This is the project's formal test policy (OpenSSF Best Practices
`test_policy_mandated` / `tests_documented_added` / `regression_tests_added50`):

1. **New functionality MUST ship with automated tests.** Any PR adding major
   new functionality is rejected unless it includes busted specs exercising
   the new behaviour (the 1:1 `spec/<module>_spec.lua` ↔ `src/<module>.lua`
   convention below).
2. **Bug fixes MUST include a regression test** that fails before the fix and
   passes after it (the RED → GREEN discipline below makes this auditable in
   the commit history).
3. **Coverage is enforced, not aspirational.** CI fails the build below
   **85 % statement coverage** (luacov, `ci.yml`) — above the 80 % the
   OpenSSF Silver tier requires.

- **TDD: RED → GREEN.** Write the failing spec first (commit type `test:`),
  then the implementation that makes it pass (commit type `feat:` or `fix:`).
  Each RED commit must show a failing test in `busted` output; each GREEN
  commit must show the test transitioning to passing.
- **mm_mocks.lua is the only mock boundary.** Tests stub MoneyMoney's globals
  (`Connection`, `JSON`, `LocalStorage`, `MM`, `WebBanking`, account types,
  `MM.sleep`) inside `spec/helpers/mm_mocks.lua`. Do not introduce ad hoc
  module-level monkey patches in individual spec files — keep the mock surface
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

## Developer Certificate of Origin (DCO)

Contributions are accepted under the
[Developer Certificate of Origin v1.1](https://developercertificate.org/).
By adding a `Signed-off-by` trailer you certify that you have the right to
submit the contribution under this repository's MIT license.

Every commit MUST carry a sign-off trailer matching the commit's author:

```
Signed-off-by: Your Name <your.email@example.org>
```

`git commit -s` adds it automatically. There is no CLA — the DCO sign-off
is the project's sole contribution-licensing mechanism.

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
