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

if ! gh api -X PUT "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" \
    -H "Accept: application/vnd.github+json" \
    --input - <<< "${PAYLOAD}" >/dev/null 2>"${TMP_ERR}"; then
  RC=$?
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
# branch-protection schema — toggle on independently.
echo "Enabling required_signatures sub-resource ..."
if ! gh api -X PUT "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection/required_signatures" \
    -H "Accept: application/vnd.github+json" >/dev/null 2>"${TMP_ERR}"; then
  echo "WARNING: required_signatures sub-resource toggle failed:" >&2
  cat "${TMP_ERR}" >&2
  echo "Branch protection (PR + checks + linear history) IS applied; signed-commit" >&2
  echo "enforcement must be enabled manually via the UI checkbox 'Require signed commits'." >&2
  exit 0
fi

echo "OK: branch protection applied (PR + checks + signatures + linear history)."
