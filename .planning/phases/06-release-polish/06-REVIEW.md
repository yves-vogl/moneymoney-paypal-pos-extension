---
phase: 06-release-polish
reviewed: 2026-06-23T00:00:00Z
depth: deep
files_reviewed: 18
files_reviewed_list:
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - .github/workflows/commit-lint.yml
  - tools/build.lua
  - tools/setup-branch-protection.sh
  - tools/setup-repo-metadata.sh
  - spec/build_version_substitution_spec.lua
  - spec/meta_no_tax_classification_spec.lua
  - spec/http_retry_spec.lua
  - src/log.lua
  - src/webbanking_header.lua
  - .luacheckrc
  - .gitleaksignore
  - docs/adr/0002-localstorage-token-cache.md
  - docs/adr/0006-jwt-bearer-only-auth.md
  - docs/adr/0007-no-tls-pinning.md
  - docs/adr/0008-string-return-error-pattern.md
  - CHANGELOG.md
  - README.de.md
  - README.md
  - CONTRIBUTING.md
findings:
  critical: 1
  high: 3
  medium: 4
  low: 3
  info: 4
  total: 15
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-06-23
**Depth:** deep
**Branch base:** main @ 9bc6c8f
**Branch tip:** phase-6/release-polish @ 1468018
**Status:** issues_found — 1 CRITICAL release-blocking defect + 3 HIGH-severity

## Summary

Phase 6 lands the release-polish surface: GPG-tag-verified release pipeline,
`__VERSION__` substitution, bilingual docs (README split), four backfilled
ADRs, gitleaks + commit-lint CI gates, branch-protection / repo-metadata
admin scripts, and CHANGELOG [1.0.0] cut. The work is structurally sound and
well documented, but one CRITICAL defect makes the release pipeline fail for
the most common future tag shape (any single-digit minor > 0, e.g. v1.5.0).
There are also three HIGH-severity issues: a placeholder `2026-MM-DD` in the
shipping CHANGELOG entry, an ADR documenting a pcall-firewall that does not
exist in the code, and a stale module-name in two ADRs.

The CRITICAL must be fixed before tagging v1.0.0. The HIGH items should be
fixed before tagging or accepted explicitly with a follow-up issue.

---

## Critical Issues

### P6-R-01: release.yml version-sanity-check formula contradicts build.lua and will fail for most future tags  [CRITICAL / BLOCKER]

**File:** `.github/workflows/release.yml:132-143`
**Issue:**

The "BUILD-03 sanity" gate computes the expected version literal with:

```yaml
EXPECTED=$(echo "${GITHUB_REF_NAME}" | sed -E 's/^v([0-9]+)\.([0-9]+).*/\1.\2/' | awk -F. '{printf "%d.%02d", $1, $2}')
```

This produces a **zero-PADDED** minor (`%02d`). But `tools/build.lua` /
`version_to_number_string` produces a zero-SUFFIXED minor (single-digit minor
gets a trailing zero appended — `"2" -> "20"`). These are not the same
mapping:

| Tag        | release.yml EXPECTED | build.lua produces | Match? |
|------------|----------------------|--------------------|--------|
| v1.0.0     | 1.00                 | 1.00               | yes    |
| v0.10.0    | 0.10                 | 0.10               | yes    |
| v1.2.3     | 1.02                 | 1.20               | NO     |
| v1.5.0     | 1.05                 | 1.50               | NO     |
| v2.3.0     | 2.03                 | 2.30               | NO     |
| v1.0.0-rc.1| 1.00                 | 1.00               | yes    |

Verified by reproducing the shell pipeline locally:

```
$ echo "v1.2.3" | sed -E 's/^v([0-9]+)\.([0-9]+).*/\1.\2/' | awk -F. '{printf "%d.%02d", $1, $2}'
1.02
```

Whereas `tools/build.lua` line 142-147:

```lua
if #minor == 1 then
  minor_str = minor .. "0"   -- "2" -> "20"
```

The two algorithms agree only when minor == 0 (gives "00") or when minor has
≥ 2 digits (both truncate / format identically: "10" -> "10"). For any
single-digit non-zero minor (v1.1.x, v1.2.x, v1.3.x ... v1.9.x, v2.1.x, ...),
the release publish pipeline aborts at this gate.

This is an actual release-blocker: v1.0.0 itself happens to work, but the
next minor bump (v1.1.0) will fail in CI with no path forward except
hot-fixing the workflow.

The release.yml comment block at lines 136-137 even hints at the bug:
"v1.2.3 → 1.20" is what the author *intended* — but the awk format string
`%02d` does the opposite.

**Fix:** Reproduce the build.lua mapping verbatim. Two options:

(a) Replace the awk with a literal pad-on-the-right transformation:
```bash
EXPECTED=$(echo "${GITHUB_REF_NAME}" \
  | sed -E 's/^v([0-9]+)\.([0-9]+).*/\1.\2/' \
  | awk -F. '{
      minor=$2
      if (length(minor)==1) minor=minor "0"
      else minor=substr(minor,1,2)
      printf "%d.%s", $1, minor
    }')
```

(b) Better: have build.lua emit a side-car file (e.g.
`dist/paypal-pos.lua.version`) containing the resolved numeric literal, and
have release.yml read THAT file instead of re-deriving it. Eliminates the
two-implementations-must-agree footgun forever.

Either path should also extend
`spec/build_version_substitution_spec.lua` with a `v1.5.0 -> 1.50` and
`v2.3.0 -> 2.30` case so a regression is caught by the spec, not by the
release pipeline at tag-push time.

---

## High

### P6-R-02: CHANGELOG.md [1.0.0] entry ships placeholder date `2026-MM-DD`  [HIGH]

**File:** `CHANGELOG.md:12`
**Issue:**

```
## [1.0.0] - 2026-MM-DD
```

The release.yml fallback path (lines 159-170) extracts this section verbatim
into `dist/release-notes.md` when no annotated tag message exists, and the
GitHub Release body is published from that file. Users will see the literal
`2026-MM-DD` placeholder on the GitHub release page.

The `<!-- lektor-review: pending — CP-1; ... -->` HTML comment on line 14
also surfaces in the rendered release notes — it is GitHub-Flavored Markdown
that strips no comments. The comment will be present in raw form only when
viewers look at the source, but it still ends up in `dist/release-notes.md`
shipped with the release artifacts.

Same issue on line 79 for `[0.2.0] - 2026-MM-DD`.

**Fix:** Replace both date placeholders with real dates before tagging. Strip
or move the `<!-- lektor-review -->` comments to the planning tree so they
do not surface in published artifacts. Update the release runbook
(06-HANDOFF.md) to require dating CHANGELOG.md as a pre-tag step.

---

### P6-R-03: ADR-0008 "Implementation pin" code snippet references a module that does not exist  [HIGH]

**File:** `docs/adr/0008-string-return-error-pattern.md:82-93`
**Issue:**

The ADR documents the callback-boundary `pcall` firewall as the foundational
contract for the string-return error pattern:

```lua
function RefreshAccount(account, since)
  local ok, result_or_err = pcall(M_refresh.run, account, since)
  if not ok then
    M_log.error("internal", { module = "RefreshAccount", err = result_or_err })
    return M_i18n.t("error.internal_unexpected")
  end
  return result_or_err
end
```

Verified against the actual code:

- `M_refresh` does NOT exist (`grep -n "M_refresh" src/*.lua` returns nothing).
- There is NO top-level `pcall` in `src/entry.lua`'s `RefreshAccount`,
  `InitializeSession2`, `ListAccounts`, or `EndSession` callbacks
  (`grep -n "pcall" src/entry.lua` returns nothing).
- The i18n key `error.internal_unexpected` does not exist in `src/i18n.lua`
  (the actual error keys are `invalid_grant`, `network`, `rate_limit`,
  `server_busy`, `token_revoked`).
- `M_log.error` is also not currently called from any production codepath
  (`grep "M_log.error" src/*.lua` returns nothing — only `M_log.info` /
  `M_log.debug` are used).

The ADR sells "the top-level pcall is the safety net" as an accepted
invariant. Reality: there is no safety net. A genuine internal Lua error
(e.g. `M_purchases.fetch` doing `tostring(nil_value):sub(...)`) propagates as
a raw Lua traceback into MoneyMoney, defeating the user-facing UX guarantee
the ADR is built around.

Either (a) the ADR is aspirational and labelled "ACCEPTED" prematurely, or
(b) Phase 2-5 dropped the firewall during implementation and nobody noticed.
Either way, the ADR is a load-bearing claim that the code does not honour.

**Fix:** Decide and act:

- If the firewall is intended: open a follow-up issue to add the
  callback-boundary `pcall` to every callback in `src/entry.lua`, add the
  `error.internal_unexpected` i18n key, and add a spec asserting that a
  forced `error()` inside `M_purchases.fetch` surfaces the localized string.
- If the firewall is deferred: edit ADR-0008's "Implementation pin" section
  to say "deferred to v1.1.0 / tracked in #N" with a TODO marker, and
  remove the misleading code snippet. The decision text itself can still
  document the intent.

Do not ship v1.0.0 with an ADR claiming a safety net that does not exist.

---

### P6-R-04: ADR-0001 and ADR-0008 reference module names `M_payouts`, `M_balance`, `M_refresh` that were never created  [HIGH]

**File:** `docs/adr/0001-amalgamator-design.md:37-38` (and `docs/adr/0008-string-return-error-pattern.md:96-99`)
**Issue:**

ADR-0001 enumerates the predeclared cross-module tables:

> `M_log`, `M_errors`, `M_i18n`, `M_model`, `M_http`, `M_auth`,
> `M_pagination`, `M_purchases`, `M_payouts`, `M_balance`, `M_mapping`

But `src/webbanking_header.lua` actually declares 10 tables, and the manifest
matches:

```
M_log, M_errors, M_i18n, M_model, M_http, M_auth,
M_pagination, M_purchases, M_finance, M_mapping
```

`M_payouts` and `M_balance` do not exist (presumably collapsed into
`M_finance` in Phase 4). ADR-0008 line 96-99 similarly references
`M_payouts` and `M_balance` as "internal modules that must return strings".

The actual src/ tree (`auth.lua`, `entry.lua`, `errors.lua`, `finance.lua`,
`http.lua`, `i18n.lua`, `log.lua`, `mapping.lua`, `model.lua`,
`pagination.lua`, `purchases.lua`, `webbanking_header.lua`) matches the
manifest, not the ADRs. The ADRs are stale.

This is HIGH and not MEDIUM because ADR-0001 is the load-bearing reference
that the CI gates (luacheck globals, build.lua manifest, webbanking_header
predeclarations) are kept consistent with. A future contributor reading
ADR-0001 will declare a global called `M_payouts` and then spend an hour
hunting down why luacheck rejects it.

**Fix:** Update ADR-0001 line 37-38 and ADR-0008 line 96-99 (and the
similar reference in ADR-0008 line 121) to enumerate the real module names:
replace `M_payouts, M_balance` with `M_finance` (and `M_refresh` does not
exist anywhere — drop it). Add a brief note that Phase 4's Finance API
consolidation merged payouts + balance under `M_finance`.

---

## Medium

### P6-R-05: setup-branch-protection.sh always exits 0 on failure (RC=$? captures inverted exit code)  [MEDIUM]

**File:** `tools/setup-branch-protection.sh:88-124`
**Issue:**

```bash
if ! gh api -X PUT "..." ... 2>"${TMP_ERR}"; then
  RC=$?
  if grep -Eq '403|insufficient|...' "${TMP_ERR}"; then
    # graceful-degrade branch
    exit 0
  fi
  echo "FAIL: branch-protection PUT failed with exit ${RC}:" >&2
  cat "${TMP_ERR}" >&2
  exit "${RC}"     # <-- always 0
fi
```

Inside an `if ! cmd; then` block, bash sets `$?` to **0** (the inverted
result of `cmd`'s failure that caused the `if` to enter the `then` branch).
`RC=$?` therefore captures `0`, not the gh CLI's real exit code.
`exit "${RC}"` consequently exits 0 — the script silently reports success
to its caller even though the API call failed and the graceful-degrade
fallthrough did not match.

Reproduced locally:
```
$ if ! false; then echo "rc=$?"; fi
rc=0
```

Impact: a transient gh CLI failure (network blip, rate limit, expired
token) on the branch-protection PUT call masquerades as success — Yves
believes branch protection is configured when it is not. This is a SECURITY
defect because the script is the documented mechanism for enforcing the
"never commit to main" memory.

**Fix:** Capture the exit code BEFORE entering the `then` branch:

```bash
set +e
gh api -X PUT "..." ... >/dev/null 2>"${TMP_ERR}"
RC=$?
set -e
if [ "${RC}" -ne 0 ]; then
  if grep -Eq '403|insufficient|Resource not accessible|Must have admin' "${TMP_ERR}"; then
    cat <<'EOF'
WARNING: gh PAT lacks `Administration: write` scope ...
EOF
    exit 0
  fi
  echo "FAIL: branch-protection PUT failed with exit ${RC}:" >&2
  cat "${TMP_ERR}" >&2
  exit "${RC}"
fi
```

Or use `gh api ... || RC=$?; ...` pattern. Add a test that asserts the
script exits non-zero when gh is unauthenticated (mock gh via PATH override).

---

### P6-R-06: release.yml release-notes extraction includes the GPG signature block in the GitHub release body  [MEDIUM]

**File:** `.github/workflows/release.yml:159-171`
**Issue:**

```yaml
git for-each-ref "refs/tags/${TAG}" --format='%(contents)' > dist/release-notes.md
```

`git for-each-ref`'s `%(contents)` atom emits the ENTIRE tag message
including the trailing PGP signature block. For a signed tag (which Job 1
just verified), the resulting `dist/release-notes.md` will contain:

```
Release v1.0.0

... user-readable changelog ...

-----BEGIN PGP SIGNATURE-----

iQIzBAAB...
-----END PGP SIGNATURE-----
```

That entire block is then published as the GitHub release body via
`softprops/action-gh-release@v2` — users opening the release see an inline
PGP signature ASCII block instead of clean release notes.

**Fix:** Use `%(contents:body)` (which omits subject AND signature) and
prepend `%(contents:subject)` as an H2:

```bash
SUBJECT=$(git for-each-ref "refs/tags/${TAG}" --format='%(contents:subject)')
BODY=$(git for-each-ref "refs/tags/${TAG}" --format='%(contents:body)')
{
  echo "## ${SUBJECT}"
  echo ""
  echo "${BODY}"
} > dist/release-notes.md
```

Alternatively use `git tag -l --format='%(contents)' "${TAG}" | sed
'/-----BEGIN PGP SIGNATURE-----/,$d'` — explicit signature strip.

Verify by running locally on an existing signed tag and inspecting the
output before tagging v1.0.0.

---

### P6-R-07: commit-lint.yml rejects valid Conventional Commits subjects with breaking-change marker (`feat!:`)  [MEDIUM]

**File:** `.github/workflows/commit-lint.yml:33`
**Issue:**

```yaml
REGEX='^(feat|fix|docs|test|refactor|chore|ci|build|perf|style|revert)(\([^)]+\))?: .+'
```

Conventional Commits 1.0.0 spec defines the breaking-change marker as `!`
appended to the type (optionally after the scope):

- `feat!: drop Node 8 support`
- `feat(api)!: send an email when a product is shipped`

The current regex requires `:` immediately after either the type or the
scope-closing `)`, with no `!` slot. Any maintainer using the canonical
breaking-change syntax will be rejected with no actionable error message
(the failure just says "Conventional Commits required" without explaining
why a syntactically valid Conventional Commit was rejected).

**Fix:**

```yaml
REGEX='^(feat|fix|docs|test|refactor|chore|ci|build|perf|style|revert)(\([^)]+\))?!?: .+'
```

(The `!?` slot allows `feat:`, `feat!:`, `feat(scope):`, `feat(scope)!:`).

Optionally also reject overly-long subjects (`.+` is unbounded). Common
practice: cap at ~100 chars; warn at 72.

---

### P6-R-08: tools/build.lua dist/ existence side-effect makes test-runner ordering load-bearing  [MEDIUM]

**File:** `tools/build.lua:275-276`
**Issue:**

```lua
local function write_output(path, content)
  os.execute("mkdir -p dist")
  ...
```

`tools/build.lua` shells out to `mkdir -p dist`. This is a build-time
write to the working directory from inside a function that several specs
invoke via `os.execute("lua tools/build.lua")` in their `before_each` or
preamble (`meta_no_tax_classification_spec.lua` line 19,
`http_retry_spec.lua` line 18, `build_version_substitution_spec.lua` lines
38-40). The `mkdir -p` is harmless (idempotent), but the fact that running
the spec suite mutates `dist/` is a load-bearing side effect:

- `dist/paypal-pos.lua` gets rewritten between every spec that invokes
  `lua tools/build.lua`. If a downstream consumer (e.g. a manual
  `busted spec/some_other_spec.lua` followed by `cp dist/paypal-pos.lua
  /Library/.../MoneyMoney/Extensions/`) is interleaved, they will install a
  build that lacks `__VERSION__` substitution (because the spec invocation
  had no `GITHUB_REF_NAME` env var) — silently shipping a `0.00` version
  literal with the DEV-BUILD banner.
- The spec suite is no longer side-effect-free; CI runners that cache
  `dist/` between jobs may serve a stale artifact.

**Fix:** Either:

(a) Add a `--out PATH` flag to `tools/build.lua` so specs can write to a
    test-scoped tmpdir instead of `dist/`.
(b) Have the specs explicitly delete `dist/paypal-pos.lua` after they're
    done so a subsequent `lua tools/build.lua` (without the env override)
    rebuilds a fresh dev version, making the mutation visible.
(c) At minimum, document the foot-gun in `CONTRIBUTING.md` so a maintainer
    knows that `busted` invocations clobber `dist/`.

LOW-medium severity because the failure is "user accidentally installs a
dev-banner build", not a security or data-loss event. The DEV-BUILD banner
emitted by `build.lua` (the W1 fix per Pitfall 3) helps detect this on
inspection, but does not prevent installation.

---

## Low

### P6-R-09: setup-repo-metadata.sh hardcodes 7 indices into the topics array — silently truncates if extended  [LOW]

**File:** `tools/setup-repo-metadata.sh:60-69`
**Issue:**

```bash
gh api -X PUT "repos/${OWNER_REPO}/topics" \
  -f "names[]=${TOPICS[0]}" \
  -f "names[]=${TOPICS[1]}" \
  -f "names[]=${TOPICS[2]}" \
  -f "names[]=${TOPICS[3]}" \
  -f "names[]=${TOPICS[4]}" \
  -f "names[]=${TOPICS[5]}" \
  -f "names[]=${TOPICS[6]}" \
```

If a maintainer adds an 8th topic to the `TOPICS=( ... )` array, the new
topic is silently dropped — the script only sends the first 7. Worse, if
someone removes a topic from the array (say, dropping `accounting` so the
list is 6 items), `${TOPICS[6]}` expands to empty under `set -u`-with-array
quirk, sending an empty topic name.

**Fix:** Build the `-f` args dynamically:

```bash
declare -a F_ARGS=()
for t in "${TOPICS[@]}"; do
  F_ARGS+=(-f "names[]=${t}")
done
gh api -X PUT "repos/${OWNER_REPO}/topics" \
  -H "Accept: application/vnd.github+json" \
  "${F_ARGS[@]}" \
  >/dev/null
```

---

### P6-R-10: spec/meta_no_tax_classification_spec.lua case-sensitive find misses "GoBD-Konform" capitalization variants  [LOW]

**File:** `spec/meta_no_tax_classification_spec.lua:48-62, 77-83`
**Issue:**

The forbidden phrases include lowercase forms like `"GoBD-konform"` and
`"GoBD konform"`, and `scan_file` uses `content:find(phrase, 1, true)` which
is **case-sensitive** plain-text find. A doc that writes "Wir gewährleisten
GoBD-Konformität" (capital K, the natural German form) will NOT trip the
gate. README.de.md line 82 already uses "GoBD-Konformität" — it slips past
the walker only by being phrased as "erhebt KEINEN Anspruch auf
GoBD-Konformität" (a negation).

The 13-phrase list is locked per CONTEXT D-55, so case-sensitivity is by
design and adjusting the gate would require reopening D-55. But the
walker's blast radius is narrower than it appears: a positive claim using
the capitalized form would slip through.

**Fix (optional, requires D-55 re-open):** Lowercase both `content` and
`phrase` before `find` — `content:lower():find(phrase:lower(), 1, true)`.
This makes the gate case-insensitive without expanding the 13-phrase list.

If the D-55 contract is "exactly these byte sequences and no others", leave
this as-is and document the limitation in a comment explicitly so a future
maintainer doesn't assume the walker is case-insensitive.

---

### P6-R-11: src/log.lua DEBUG-gate uses Lua truthiness, not strict false-check — assignment to `0` or `""` would still emit DEBUG  [LOW]

**File:** `src/log.lua:53`
**Issue:**

```lua
local threshold = DEBUG and _LEVEL.DEBUG or _LEVEL.INFO
```

This evaluates DEBUG via Lua truthiness. In Lua, only `nil` and `false` are
falsy — `DEBUG = 0` or `DEBUG = ""` would still activate DEBUG-level
logging. The SEC-04 build-gate (`grep -q 'DEBUG = false'`) verifies the
literal `DEBUG = false` line is present in the artifact, but does NOT
verify that a maintainer hasn't ALSO added a second assignment somewhere
(`DEBUG = 0` in src/entry.lua) that would resurrect debug logging.

Realistic probability: low (the convention is enforced in code review and
the CI gate). But the pattern is footgun-shaped — if SEC-04 future work
wants to allow runtime DEBUG toggle (e.g. via `LocalStorage.debug`), the
truthiness check accepts unexpected truthy values.

**Fix:**

```lua
local threshold = (DEBUG == true) and _LEVEL.DEBUG or _LEVEL.INFO
```

Strict equality removes the toggle-via-truthy-value attack surface.
Cost: zero (one extra `==`); benefit: alignment with the SEC-04 grep that
explicitly looks for the literal `true`.

---

## Info

### P6-R-12: ADR-0007 "HSTS on *.izettle.com" mitigation claim is unverified  [INFO]

**File:** `docs/adr/0007-no-tls-pinning.md:136-137`
**Issue:**

The "Mitigations summary" claims:

> HSTS on `*.izettle.com` (preloaded; downgrade protection at the
> browser-PKI ecosystem level).

HSTS preloading is browser-specific and doesn't apply to the Lua
`Connection()` client at all — `Connection()` is not a browser and does not
consult the Chromium HSTS preload list. The claim is misleading mitigation
inventory; the actual transport security for this extension is the macOS
trust-store TLS validation that `Connection()` defaults to (already item 1
in the same list).

**Fix:** Either drop the HSTS bullet or rephrase as "HSTS at the wider PKI
ecosystem level (not directly consulted by `Connection()`, but reduces the
realistic CA-confusion attack surface upstream)" — clearly disclaiming
its relevance to the extension's own code path.

---

### P6-R-13: ADR-0002 references "ADR-0006's Phase-7 forward-compat" — a circular dependency between two ADRs landing in the same Phase 6 batch  [INFO]

**File:** `docs/adr/0002-localstorage-token-cache.md:75-79`
**Issue:**

ADR-0002 says the `client_id` field is "reserved for ADR-0006's Phase-7
forward-compat". ADR-0006 says "v1.0.x ships flow 1 only" — flow 2 is
deferred to Phase 7 (no schedule yet). The cross-reference is correct but
creates a load-bearing "Phase 7" link that is not yet on the ROADMAP.

Acceptable for now; flag it so when Phase 7 is planned, the ADR-0002 +
ADR-0006 cross-link is reviewed for accuracy (and the
`LocalStorage.zettle.client_id` field's actual reading is implemented).

**Fix:** No code change. Add a TODO comment in ADR-0002 / ADR-0006:
"this forward-compat hook is tracked in ROADMAP Phase 7 — confirm the
client_id branching is wired before merging Phase 7's first PR."

---

### P6-R-14: release.yml job names not pinned to setup-branch-protection.sh CHECKS array by any automated assertion  [INFO]

**File:** `tools/setup-branch-protection.sh:50-54` + `.github/workflows/{ci,commit-lint}.yml`
**Issue:**

The CHECKS array in setup-branch-protection.sh hardcodes three job-name
strings ("Lint + tests + reproducible build", "gitleaks secret scan",
"Commit-message lint") that MUST match `name:` declarations across two
workflow files. The comment at lines 44-49 warns about this load-bearing
coupling but nothing enforces it: renaming a workflow `name:` without
updating CHECKS silently weakens branch protection (the renamed check is
no longer required).

**Fix:** Add a tiny CI step that greps the workflow files for the exact
strings in CHECKS and fails if any are absent. Or add a comment-line
sentinel inside each workflow file (`# branch-protection-check-name`)
and assert that CHECKS = grepped-sentinel-set.

Not blocking; this is a sustainability hygiene item.

---

### P6-R-15: Several specs invoke `lua tools/build.lua` without isolating cwd or version env — cross-spec contamination risk  [INFO]

**File:** `spec/build_version_substitution_spec.lua` (each `it()`), `spec/meta_no_tax_classification_spec.lua:19-23,114`, `spec/http_retry_spec.lua:17-22`
**Issue:**

Specs serially overwrite `dist/paypal-pos.lua` with different version
literals (`v1.0.0`, `v1.2.3`, `v0.10.0`, `v1.0.0-rc.1`, `dev-test`,
unset). The last-write-wins state of `dist/` after the suite ends depends
on Busted's spec execution order, which is alphabetic by default:

```
build_version_substitution_spec.lua  -- writes various versions
http_retry_spec.lua                  -- writes default (dev fallback)
meta_no_tax_classification_spec.lua  -- writes default
... others ...
```

After the suite ends, `dist/paypal-pos.lua` carries whatever the last
spec wrote — undefined from a contract perspective. If a `make`
target chains `busted && cp dist/paypal-pos.lua ...`, the user installs
an arbitrary spec-side-effect artifact.

See also P6-R-08 (same root cause from the source side).

**Fix:** Document at the top of CONTRIBUTING.md: "After running the
spec suite, `lua tools/build.lua` MUST be re-invoked before any
distribution / installation step." Or, ideally, fix P6-R-08 (give
build.lua a `--out` flag) so specs never touch `dist/`.

---

## What was checked but found clean

- The release.yml verify-signed-tag job correctly greps for
  `VALIDSIG <FINGERPRINT>` (not relying on `git verify-tag` exit code
  alone). Pitfall 8 mitigation holds.
- Tags `v[0-9]+.[0-9]+.[0-9]+` and `-rc.[0-9]+` patterns at release.yml
  line 21-22 correctly scope the workflow to release tags only (Pitfall 10).
- The egress allowlist gate (ci.yml 83-120) correctly excludes the i18n
  key prefixes that incidentally end in TLD-shaped suffixes (`account.`,
  `purpose.`, `error.`, `credential.`, `transaction.`, plus module-name
  prefixes). Hand-traced against `src/i18n.lua`'s actual key inventory.
- The D-79 raw-print gate (ci.yml 122-144) correctly allows the single
  sentinel-marked `print(` in `src/log.lua:61` and would reject any new
  raw print().
- The SEC-04 DEBUG-false build-time check in `tools/build.lua:199-205`
  correctly fires on `DEBUG = true` while not false-positiving on
  `DEBUG ~= true` or commented lines.
- The pure-Lua SHA-256 implementation in build.lua has correct padding
  logic across the 55/56-byte boundary (verified manually).
- META-03 walker (`spec/meta_no_tax_classification_spec.lua`) correctly
  scans `src/`, `dist/`, and every doc target including ADRs added in
  this phase. README.de.md / README.md / CONTRIBUTING.md / CHANGELOG.md
  passed manual inspection against all 13 forbidden phrases.
- `.gitleaksignore` entries all reference real commits (verified via
  `git cat-file -t`). The format matches gitleaks-action's expected
  fingerprint format.
- http_retry_spec.lua `os.time` stubbing in before_each correctly
  prevents wall-clock-budget false-fires on slow runners (the WR-03 fix
  recap on line 47-50 is accurate).
- README.de.md GoBD-Hinweis (line 82) matches D-71-style wording: "Sie
  erhebt KEINEN Anspruch auf GoBD-Konformität, DATEV-Export oder
  steuerrechtliche Bewertung."
- ADR-0002 / 0006 / 0007 / 0008 all carry the required MADR sections
  (Status, Date, Deciders, Context, Decision, Consequences, References)
  in the same order as ADR-0001 / 0003 / 0005.
- CHANGELOG.md structure is Keep-a-Changelog 1.1.0 compliant (Unreleased
  section, semantic version order, `### Hinzugefügt` / `### Sicherheit`
  / `### Bekannte Grenzen` subsections, version-comparison link footers
  at the bottom).
- CONTRIBUTING.md no-AI-attribution checklist (line 92-96) phrases the
  rule without tripping the CI gate's grep (verified by running the gate
  locally).

---

_Reviewed: 2026-06-23_
_Reviewer: Claude (Opus 4.7 — adversarial code review)_
_Depth: deep (full file read + cross-reference between ADRs, manifest, src/, specs, CI workflows)_
