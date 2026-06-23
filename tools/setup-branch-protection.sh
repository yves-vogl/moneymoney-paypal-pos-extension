#!/usr/bin/env bash
# tools/setup-branch-protection.sh
#
# Phase 6 / D-74 — one-time admin setup for main-branch protection.
#
# Prerequisites:
#   - `gh` CLI authenticated with a Fine-Grained PAT that has
#       Administration: write   on yves-vogl/moneymoney-paypal-pos-extension
#     (`gh auth status` confirms scope).
#   - `jq` for JSON composition (preinstalled on macOS via Homebrew; bundled
#     on most Linux distros).
#
# Behaviour:
#   - Composes a branch-protection payload pinning:
#       * pull-request required (0 reviewers — solo-maintainer repo)
#       * three required CI check contexts (must match ci.yml + commit-lint.yml
#         job `name:` declarations byte-identically — see ARRAY below)
#       * enforce_admins: true (Yves cannot bypass either — matches the
#         "never commit to main" memory)
#       * required_linear_history: true (no merge commits)
#       * allow_force_pushes / allow_deletions: false
#       * required_conversation_resolution: true
#   - PUTs the payload to /repos/.../branches/main/protection (idempotent —
#     PUT REPLACES; re-runs overwrite the same state).
#   - SEPARATELY PUTs /repos/.../branches/main/protection/required_signatures
#     because GitHub's classic protection schema does NOT accept
#     `required_signatures` inline — it is a distinct sub-resource toggle.
#   - Gracefully degrades when the PAT lacks `Administration: write`: prints
#     the manual GitHub UI steps and exits 0 (not a failure — CP-2 may be
#     deferred until Yves rotates his token).
#
# Yves runs this once post-merge as CP-2.
# Re-runs are safe (PUT is idempotent).
#
# Usage:
#   bash tools/setup-branch-protection.sh

set -euo pipefail

OWNER="yves-vogl"
REPO="moneymoney-paypal-pos-extension"
BRANCH="main"

# Required CI status check contexts. These strings must match the `name:`
# declarations on the gating jobs across .github/workflows/*.yml byte-for-byte:
#   - ci.yml :: test job             -> "Lint + tests + reproducible build"
#   - ci.yml :: secret-scan job      -> "gitleaks secret scan"
#   - commit-lint.yml :: lint job    -> "Commit-message lint"
# Adding a new required check?  Update this array AND the job `name:` in lockstep.
declare -a CHECKS=(
  "Lint + tests + reproducible build"
  "gitleaks secret scan"
  "Commit-message lint"
  "Scorecard analysis"      # added by 06.1-04 — matches scorecard.yml line 22 job name byte-exact
  "Semgrep SAST"             # added by 06.1-04 — matches sast.yml job name byte-exact (Plan 06.1-03)
)

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required (brew install jq / apt-get install jq)" >&2
  exit 2
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "FAIL: gh CLI is required (https://cli.github.com)" >&2
  exit 2
fi

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
TMP_ERR=$(mktemp)
trap 'rm -f "${TMP_ERR}"' EXIT

# Capture the gh exit code WITHOUT wrapping in `if ! cmd; then RC=$?; fi` —
# that idiom captures `!`'s exit code (always 0/1), not the underlying
# command's. Standard pattern: temporarily disable set -e, run the
# command, capture $? immediately, restore set -e.
set +e
gh api -X PUT "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" \
    -H "Accept: application/vnd.github+json" \
    --input - <<< "${PAYLOAD}" >/dev/null 2>"${TMP_ERR}"
RC=$?
set -e

if [ "${RC}" -ne 0 ]; then
  if grep -Eq '403|insufficient|Resource not accessible|Must have admin' "${TMP_ERR}"; then
    cat <<'EOF'

WARNING: gh PAT lacks `Administration: write` scope on this repo.
Branch protection NOT applied automatically.  Configure manually:

  1. Open: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/settings/branches
  2. Add a classic branch-protection rule for `main`.
  3. Enable:
       [x] Require a pull request before merging
            - Required approving reviews: 0 (solo maintainer)
            - [x] Dismiss stale pull-request approvals when new commits are pushed
       [x] Require status checks to pass before merging
            - [x] Require branches to be up to date before merging
            - Add: "Lint + tests + reproducible build"
            - Add: "gitleaks secret scan"
            - Add: "Commit-message lint"
            - Add: "Scorecard analysis"      # NEW 06.1-04
            - Add: "Semgrep SAST"             # NEW 06.1-04
       [x] Require signed commits
       [x] Require linear history
       [x] Require conversation resolution before merging
       [x] Do not allow bypassing the above settings (enforce_admins)
       [ ] Allow force pushes — leave OFF
       [ ] Allow deletions  — leave OFF
  4. Save.

Exit 0 — script proceeds gracefully so subsequent CI runs are unaffected.
EOF
    exit 0
  fi
  echo "FAIL: branch-protection PUT failed with exit ${RC}:" >&2
  cat "${TMP_ERR}" >&2
  exit "${RC}"
fi

# required_signatures lives at a separate sub-resource per GitHub's classic
# branch-protection schema — toggle on independently. Same RC-capture
# pattern as the main PUT above.
echo "Enabling required_signatures sub-resource ..."
set +e
gh api -X PUT "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection/required_signatures" \
    -H "Accept: application/vnd.github+json" >/dev/null 2>"${TMP_ERR}"
RC=$?
set -e

if [ "${RC}" -ne 0 ]; then
  echo "WARNING: required_signatures sub-resource toggle failed (exit ${RC}):" >&2
  cat "${TMP_ERR}" >&2
  echo "Branch protection (PR + checks + linear history) IS applied; signed-commit" >&2
  echo "enforcement must be enabled manually via the UI checkbox 'Require signed commits'." >&2
  exit 0
fi

# -------------------------------------------------------------------------
# Idempotent post-condition check — GET the protection state and verify
# the load-bearing fields are actually set. Guards against silent partial
# applies (e.g. the GitHub API accepting the PUT but ignoring one of the
# sub-fields) by reading back and asserting.
# -------------------------------------------------------------------------
echo "Post-condition: re-read protection state and verify required fields ..."
set +e
PROTECTION_JSON=$(gh api "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" \
    -H "Accept: application/vnd.github+json" 2>"${TMP_ERR}")
RC=$?
set -e

if [ "${RC}" -ne 0 ]; then
  echo "FAIL: post-condition GET returned exit ${RC}:" >&2
  cat "${TMP_ERR}" >&2
  exit 1
fi

# Field 1: enforce_admins.enabled must be true.
# `if-then-else MISSING` pattern (P6.1-R-04): distinguish "field set to false"
# from "field absent" so a silently-dropped API response surfaces explicitly.
ENFORCE_ADMINS=$(echo "${PROTECTION_JSON}" | jq -r 'if .enforce_admins then .enforce_admins.enabled else "MISSING" end')
if [ "${ENFORCE_ADMINS}" != "true" ]; then
  echo "FAIL: post-condition: enforce_admins.enabled is '${ENFORCE_ADMINS}', expected true" >&2
  exit 1
fi

# Field 2: all three required contexts must be present (set-equal — order
# does not matter; extras are tolerated).
for ctx in "${CHECKS[@]}"; do
  if ! echo "${PROTECTION_JSON}" | jq -e \
      --arg c "${ctx}" '.required_status_checks.contexts | index($c)' >/dev/null; then
    echo "FAIL: post-condition: required status check missing: '${ctx}'" >&2
    echo "Observed contexts:" >&2
    echo "${PROTECTION_JSON}" | jq -r '.required_status_checks.contexts[]' >&2
    exit 1
  fi
done

# Field 3: required_signatures.enabled must be true.
# `if-then-else MISSING` pattern (P6.1-R-04) — see Field 1 comment.
REQUIRED_SIGS=$(echo "${PROTECTION_JSON}" | jq -r 'if .required_signatures then .required_signatures.enabled else "MISSING" end')
if [ "${REQUIRED_SIGS}" != "true" ]; then
  echo "FAIL: post-condition: required_signatures.enabled is '${REQUIRED_SIGS}', expected true" >&2
  exit 1
fi

# S-R2-L-01 / P6.1-R-04 — assert allow_force_pushes and allow_deletions are
# explicitly false. The PUT payload at line 79-80 declares both as false, but
# defense-in-depth verification catches silent partial-apply by the GitHub API.
# NOTE: `.allow_force_pushes.enabled // false` would silently mask field
# absence — if the API ever drops the field, the post-condition would
# spuriously pass. Use the `if-then-else MISSING` pattern so a missing
# field is flagged as a distinct failure mode (P6.1-R-04).
ALLOW_FORCE=$(echo "${PROTECTION_JSON}" | jq -r 'if .allow_force_pushes then .allow_force_pushes.enabled else "MISSING" end')
if [ "${ALLOW_FORCE}" != "false" ]; then
  echo "FAIL: post-condition: allow_force_pushes.enabled is '${ALLOW_FORCE}', expected false (S-R2-L-01 / P6.1-R-04)" >&2
  exit 1
fi
ALLOW_DEL=$(echo "${PROTECTION_JSON}" | jq -r 'if .allow_deletions then .allow_deletions.enabled else "MISSING" end')
if [ "${ALLOW_DEL}" != "false" ]; then
  echo "FAIL: post-condition: allow_deletions.enabled is '${ALLOW_DEL}', expected false (S-R2-L-01 / P6.1-R-04)" >&2
  exit 1
fi

# S-03 — re-assert the remaining load-bearing fields that the PUT payload
# at line 67-84 declares. Without these checks the post-condition silently
# accepts a state where the GitHub API persisted enforce_admins +
# required_signatures + force/delete flags but dropped linear-history,
# dismiss-stale-reviews, or conversation-resolution.
# Same `if-then-else MISSING` pattern as above — distinguish "field set to
# false by API" from "field absent in API response" (P6.1-R-04).

# Field 4: required_linear_history.enabled must be true.
LINEAR_HISTORY=$(echo "${PROTECTION_JSON}" | jq -r 'if .required_linear_history then .required_linear_history.enabled else "MISSING" end')
if [ "${LINEAR_HISTORY}" != "true" ]; then
  echo "FAIL: post-condition: required_linear_history.enabled is '${LINEAR_HISTORY}', expected true (S-03)" >&2
  exit 1
fi

# Field 5: required_pull_request_reviews.dismiss_stale_reviews must be true.
DISMISS_STALE=$(echo "${PROTECTION_JSON}" | jq -r 'if .required_pull_request_reviews then .required_pull_request_reviews.dismiss_stale_reviews else "MISSING" end')
if [ "${DISMISS_STALE}" != "true" ]; then
  echo "FAIL: post-condition: required_pull_request_reviews.dismiss_stale_reviews is '${DISMISS_STALE}', expected true (S-03)" >&2
  exit 1
fi

# Field 6: required_conversation_resolution.enabled must be true.
CONV_RESOLUTION=$(echo "${PROTECTION_JSON}" | jq -r 'if .required_conversation_resolution then .required_conversation_resolution.enabled else "MISSING" end')
if [ "${CONV_RESOLUTION}" != "true" ]; then
  echo "FAIL: post-condition: required_conversation_resolution.enabled is '${CONV_RESOLUTION}', expected true (S-03)" >&2
  exit 1
fi

echo "OK: branch protection applied (PR + checks + signatures + linear history)."
echo "OK: post-condition verified (enforce_admins, ${#CHECKS[@]} contexts, required_signatures, allow_force_pushes=false, allow_deletions=false, required_linear_history=true, dismiss_stale_reviews=true, required_conversation_resolution=true)."
