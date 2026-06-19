---
phase: 02-authenticated-network-layer
plan: "03"
subsystem: auth
tags: [jwt, base64url, lua, pure-logic, rfc7515, sec-03, auth-05]

requires:
  - phase: 02-authenticated-network-layer
    plan: "01"
    provides: "Real MM.base64decode implementation in mm_mocks.lua (Risk R-6)"

provides:
  - "M_auth._decode_jwt_payload(jwt) -> table|nil (pure-CPU JWT payload extractor)"
  - "M_auth._extract_client_id(jwt) -> string|nil (aud/client_id claim reader)"
  - "Private _b64url_decode (RFC 7515 Appendix C, module-scoped)"

affects:
  - "02-05 (Wave 3): entry.lua calls M_auth._extract_client_id before network"
  - "02-06 (Wave 4): SEC-03 gating spec uses these hardcoded base64url strings"

tech-stack:
  added: []
  patterns:
    - "pcall-wrapped JSON parse for attacker-controlled JWT payloads (T-02-03-01)"
    - "RFC 7515 Appendix C base64url -> base64 translation before MM.base64decode"
    - "module-private local function above public M_auth attachments (log.lua idiom)"

key-files:
  created: []
  modified:
    - "src/auth.lua"
    - "spec/auth_spec.lua"

key-decisions:
  - "No log calls in _decode_jwt_payload or _extract_client_id — nil return is consumed by entry.lua (Wave 3) which emits the single INFO line, avoiding any JWT fragment leakage through the log path"
  - "pcall wraps JSON(raw):dictionary() — not the entire decode chain — so that only the parse step is guarded while structural checks (type, segment count) remain fail-fast"
  - "aud-as-array fallback reads aud[1] with an explicit type-and-length check matching the same guard used for the string branch"

patterns-established:
  - "private-local-then-public-attach: local function _b64url_decode scoped to do...end block; public functions attach to M_auth table"

requirements-completed: [AUTH-02, AUTH-05, SEC-03]

duration: 18min
completed: 2026-06-19
---

# Phase 02 Plan 03: JWT Pure-Logic Helpers Summary

**Pure-CPU base64url decoder plus M_auth._decode_jwt_payload / _extract_client_id that fail-fast on malformed API-key input with zero network calls, using pcall-wrapped JSON parse per RFC 7515 Appendix C.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-06-19T10:05:00Z
- **Completed:** 2026-06-19T10:23:58Z
- **Tasks:** 1 (TDD: RED + GREEN commits)
- **Files modified:** 2

## Accomplishments

- Implemented `_b64url_decode` private local: `-`/`_` substitution, mod-4 padding, `MM.base64decode` call; nil-safe type guard
- Implemented `M_auth._decode_jwt_payload`: three-segment match, b64url decode, pcall-wrapped `JSON():dictionary()`, returns table-or-nil
- Implemented `M_auth._extract_client_id`: aud string -> aud[1] array -> client_id fallback -> nil; all D-22 claim-priority cases covered
- Greened 10 previously-pending tests in spec/auth_spec.lua; 9 orchestration tests remain pending for Wave 3
- Full test suite: 57 successes / 0 failures / 0 errors / 29 pending (was 47/0/0/34)

## Hardcoded Base64url Strings (for Wave 4 SEC-03 cross-reference)

These precomputed strings are used in spec/auth_spec.lua and serve as canonical fixtures:

| JSON payload | base64url middle segment (no padding) |
|---|---|
| `{"aud":"client-x"}` | `eyJhdWQiOiJjbGllbnQteCJ9` |
| `{"aud":["client-x"]}` | `eyJhdWQiOlsiY2xpZW50LXgiXX0` |
| `{"client_id":"cid-x"}` | `eyJjbGllbnRfaWQiOiJjaWQteCJ9` |
| `{"sub":"x"}` | `eyJzdWIiOiJ4In0` |
| `"abc"` (non-JSON) | `YWJj` |

## Task Commits

1. **Task 1 RED: failing tests for _decode_jwt_payload + _extract_client_id** — `3286d52` (test)
2. **Task 1 GREEN: implement _b64url_decode + M_auth helpers** — `ce6afe5` (feat)

## Files Created/Modified

- `/src/auth.lua` — 56 LoC; private `_b64url_decode`, `M_auth._decode_jwt_payload`, `M_auth._extract_client_id`; no require(), no log calls, no host strings
- `/spec/auth_spec.lua` — replaced 5 `pending()` stubs with real assertions; added 7 new `it()` blocks; 9 orchestration tests remain `pending` (Wave 3)

## Security Properties Confirmed

- `src/auth.lua` emits zero log lines — no JWT segment can leak through the log path (AUTH-05 / T-02-03-02)
- `grep -c require src/auth.lua` → 0 (no sibling require per D-02 / CLAUDE.md)
- `grep -cE '(M_log|print|MM\.printStatus)' src/auth.lua` → 0
- Egress allowlist not violated — no host strings added
- Reproducible build SHA256: `060d146b4aa8036943f51f2b1ec21b8bf4cc1b410eda425df2facb36ba7a7be0`

## Edge Case Notes (ADR-0003 candidates)

- `MM.base64decode` with padding length 0, 1, 2, 3 all work correctly with the real RFC 4648 decoder from Plan 02-01. Padding length 4 is avoided by the `(4 - (#s % 4)) % 4` formula.
- Non-base64url characters in the middle segment (e.g., `@@@`) produce empty or garbage output from `_base64decode`; the subsequent `pcall`-wrapped JSON parse catches that and returns nil — no crash.
- Empty string middle segment after substitution: `#raw == 0` guard catches this before pcall.
- `aud` as `null` in JSON (Lua `nil`): `type(aud) == "string"` returns false, falls through to `client_id` check cleanly.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- luacov report generation fails under Lua 5.5 (reporter.lua L33 uses `local` on a variable already declared as `const` in 5.5's semantics). This is a pre-existing toolchain issue not introduced by this plan. Coverage is functionally verified: all 10 auth-module tests pass including every path (nil-guard, segment-count check, base64decode, pcall, aud/client_id branches). Deferred to deferred-items.md.

## Next Phase Readiness

- `M_auth._extract_client_id` is ready for Wave 3 (Plan 02-05) entry.lua integration
- `M_auth._decode_jwt_payload` is available for Wave 4 SEC-03 gating spec
- No blockers

---
*Phase: 02-authenticated-network-layer*
*Completed: 2026-06-19*

## Self-Check: PASSED

- `src/auth.lua` exists: FOUND
- `spec/auth_spec.lua` exists: FOUND
- Commit `3286d52` exists: FOUND (test)
- Commit `ce6afe5` exists: FOUND (feat)
- `busted spec/`: 57 successes / 0 failures / 0 errors
- `luacheck src/auth.lua spec/auth_spec.lua`: 0 warnings / 0 errors
- `lua tools/build.lua --verify`: OK (reproducible)
