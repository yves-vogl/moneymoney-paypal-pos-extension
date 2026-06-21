#!/usr/bin/env bash
# tools/probe-finance.sh
# Q3 closure probe — exercises the Finance API host live and prints a
# redacted response shape ready to paste into ADR-0003 Q3 row.
#
# Plan: .planning/phases/04-enrichment-refunds-fees-payouts/04-01-PLAN.md
# Research:  .planning/phases/04-enrichment-refunds-fees-payouts/04-RESEARCH.md §1.1, §1.3, §1.6, §8.4
#
# Usage:
#   1. Source your sandbox bearer:
#        export ZETTLE_BEARER="eyJhbGciOiJSUzI1NiIs…"   # NEVER commit
#      Easiest extraction paths (pick whichever is faster for you):
#        - macOS Keychain / 1Password where you saved the sandbox key
#        - Re-mint via curl against oauth.zettle.com (`/token` jwt-bearer grant)
#        - Read the LocalStorage plist where MoneyMoney caches the token
#   2. Run:
#        ./tools/probe-finance.sh
#   3. The script prints (a) HTTP status, (b) top-level wrapper shape,
#      (c) bare field names of first record, (d) probe date — all the
#      values ADR-0003 Q3 needs. Verifies *both* the transactions
#      endpoint AND the two balance endpoints (RESEARCH §1.2 — Plan 04-03
#      will issue these two calls per refresh).
#
# Security:
#   - The bearer is read from env only. The script never writes it to disk.
#   - The response body is filtered through a tee that redacts UUIDs / org
#     IDs / names before printing — pasting the printed output into the ADR
#     is safe.
#   - Curl uses --no-progress-meter and --tlsv1.2 minimum (Phase-1 Q8).

set -euo pipefail

if [[ -z "${ZETTLE_BEARER:-}" ]]; then
  cat >&2 <<'EOF'
ERROR: $ZETTLE_BEARER not set.

Set it to your sandbox PayPal POS access_token, then re-run:

  export ZETTLE_BEARER="eyJ…"
  ./tools/probe-finance.sh

The token never touches disk — the script reads env only.
EOF
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required but not on PATH." >&2
  exit 2
fi

# Date window: last 20 days (matches Plan 04-01 Task 1 guidance).
# macOS date and GNU date have different flags — handle both.
if date -u -v-20d +%Y-%m-%d >/dev/null 2>&1; then
  START_DATE="$(date -u -v-20d +%Y-%m-%d)"
  END_DATE="$(date -u +%Y-%m-%d)"
else
  START_DATE="$(date -u -d '20 days ago' +%Y-%m-%d)"
  END_DATE="$(date -u +%Y-%m-%d)"
fi

# RESEARCH §1.3 — no Z, no millis in the Finance API date params
START_PARAM="${START_DATE}T00:00:00"
END_PARAM="${END_DATE}T00:00:00"

HOST="https://finance.izettle.com"
TXN_URL="${HOST}/v2/accounts/liquid/transactions?start=${START_PARAM}&end=${END_PARAM}&limit=1&includeTransactionType=PAYMENT"
LIQUID_BAL_URL="${HOST}/v2/accounts/liquid/balance"
PRELIM_BAL_URL="${HOST}/v2/accounts/preliminary/balance"

# Redaction filter — replaces UUID-shaped, email-shaped, and obvious
# merchant-name fields with placeholders so the printed body is ADR-safe.
redact() {
  sed -E \
    -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<UUID-REDACTED>/g' \
    -e 's/("(merchantName|userDisplayName|organizationName|name|email|displayName)"\s*:\s*)"[^"]*"/\1"<REDACTED>"/g' \
    -e 's/("(organizationId|userId|orgId)"\s*:\s*)"[^"]*"/\1"<REDACTED>"/g'
}

probe_one() {
  local label="$1"
  local url="$2"

  echo "────────────────────────────────────────"
  echo "▸ ${label}"
  echo "  URL:    ${url}"

  local tmp_body tmp_hdr status
  tmp_body="$(mktemp -t probe-finance.body.XXXXXX)"
  tmp_hdr="$(mktemp -t probe-finance.hdr.XXXXXX)"
  trap 'rm -f "${tmp_body}" "${tmp_hdr}"' EXIT

  # --fail-with-body keeps the body on non-2xx so we can inspect 401 vs 404
  # --max-time 30 keeps the probe well under MoneyMoney's per-call budget
  set +e
  curl --silent --show-error --tlsv1.2 --max-time 30 \
       --output "${tmp_body}" --dump-header "${tmp_hdr}" \
       --write-out 'HTTP_STATUS=%{http_code}\n' \
       --header "Authorization: Bearer ${ZETTLE_BEARER}" \
       --header "Accept: application/json" \
       "${url}" > /tmp/probe-finance.status 2>&1
  curl_exit=$?
  set -e

  status="$(grep -E '^HTTP_STATUS=' /tmp/probe-finance.status | tail -1 | cut -d= -f2)"
  echo "  Status: ${status:-<curl-exit-${curl_exit}>}"

  if [[ -s "${tmp_body}" ]]; then
    # Pretty-print if jq is available; fall back to raw otherwise
    if command -v jq >/dev/null 2>&1; then
      echo "  Body (redacted, top-level keys only):"
      jq -r 'if type == "object" then keys else "(array of " + (length|tostring) + " items)" end' "${tmp_body}" 2>/dev/null \
        | sed 's/^/    /' || echo "    (jq parse failed — raw body below)"
      echo "  Body (redacted shape — first 30 lines):"
      jq '.' "${tmp_body}" 2>/dev/null | redact | head -30 | sed 's/^/    /' \
        || cat "${tmp_body}" | redact | head -30 | sed 's/^/    /'
    else
      echo "  Body (redacted, raw — install jq for nicer output):"
      cat "${tmp_body}" | redact | head -30 | sed 's/^/    /'
    fi
  else
    echo "  Body: (empty)"
  fi

  rm -f "${tmp_body}" "${tmp_hdr}"
  trap - EXIT

  echo
}

cat <<EOF
═══════════════════════════════════════════════════════
Q3 LIVE PROBE — Finance API host verification
═══════════════════════════════════════════════════════
Date:           $(date -u +%Y-%m-%dT%H:%M:%SZ)
Window:         ${START_PARAM} → ${END_PARAM}
Bearer:         <REDACTED> (length=${#ZETTLE_BEARER})
═══════════════════════════════════════════════════════

EOF

probe_one "Transactions (paginated GET)"          "${TXN_URL}"
probe_one "Liquid balance (settled)"              "${LIQUID_BAL_URL}"
probe_one "Preliminary balance (pending/in-flight)" "${PRELIM_BAL_URL}"

cat <<'EOF'
═══════════════════════════════════════════════════════
ADR-0003 Q3 row — paste this block (after substituting):
═══════════════════════════════════════════════════════

| Q3 | finance.izettle.com host for /v2/accounts/liquid/transactions | Live probe vs sandbox tenant | <PASS|FAIL> — HTTP <status>; response wrapper `<observed-wrapper>`; first-record fields `<observed-field-names-or-empty>` | <follow-up-if-any> | Phase 4 unblocked |

Suggested verdict logic:
  - Three 200s + JSON wrapper matches research expectation       → ACCEPTED
  - One or more 401s                                              → likely READ:FINANCE scope missing on the current bearer; re-mint with scope and re-run (Plan 04-06 will document this)
  - One or more 404s / DNS-error / TLS-error                      → REJECTED — replan Plans 04-02/04-03 via `/gsd-plan-phase 4 --gaps`

Then commit (on phase-4/enrichment branch) with GPG signature:

  git add docs/adr/0003-sandbox-probe-results.md
  git commit -S -m "docs(adr-0003): close Q3 — Finance API host PASS via live probe"

EOF
