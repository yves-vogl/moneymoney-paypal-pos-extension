#!/usr/bin/env bash
# tools/setup-repo-metadata.sh
#
# Phase 6 / D-82 — one-time admin setup for repo description + topics.
#
# Prerequisites:
#   - `gh` CLI authenticated with a PAT that has repo-metadata write access.
#     Yves' standard PAT typically covers this scope; only Administration:write
#     (branch protection — see setup-branch-protection.sh) is the stricter one.
#
# Behaviour:
#   - Sets the repo description via `gh repo edit --description "..."` (PATCH-
#     idempotent — re-running with the same string is a no-op).
#   - Replaces the topic list via `PUT /repos/.../topics` with EXACTLY the
#     7 D-82 topics in their canonical display order. This uses the REST
#     topics endpoint with PUT-semantics — re-runs OVERWRITE the topic list,
#     guaranteeing exact-set semantics.
#
#     Note: `gh repo edit --add-topic` is intentionally NOT used here. That
#     subcommand is ADDITIVE — it appends to the existing list and never
#     removes topics. Over multiple invocations the topic set would drift
#     (e.g. a renamed or deleted topic would linger). The REST PUT endpoint
#     replaces the list atomically and is the safer pattern for an
#     idempotent maintenance script.
#
# Yves runs this once post-merge as CP-3.
# Re-runs are safe (PUT is idempotent).
#
# Usage:
#   bash tools/setup-repo-metadata.sh

set -euo pipefail

OWNER_REPO="yves-vogl/moneymoney-paypal-pos-extension"

# D-82 verbatim — German description.
DESCRIPTION="MoneyMoney-Extension für PayPal POS — Karten-Umsätze, Refunds, Gebühren und Auszahlungen direkt in MoneyMoney. Open Source, MIT, GPG-signiert."

# D-82 verbatim — 7 topics in canonical order. The PUT endpoint will replace
# the existing topic list with EXACTLY these values.
TOPICS=(
  moneymoney
  moneymoney-extension
  paypal-pos
  zettle
  lua
  germany
  accounting
)

if ! command -v gh >/dev/null 2>&1; then
  echo "FAIL: gh CLI is required (https://cli.github.com)" >&2
  exit 2
fi

echo "Setting description on ${OWNER_REPO} ..."
gh repo edit "${OWNER_REPO}" --description "${DESCRIPTION}"

echo "Replacing topics on ${OWNER_REPO} (PUT — exact-set semantics) ..."
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

echo "OK: description and topics set on ${OWNER_REPO}."
echo "    Topics (${#TOPICS[@]}): ${TOPICS[*]}"
