---
phase: 02-authenticated-network-layer
plan: "06"
subsystem: entry
tags: [entry, integration, initializesession2, listaccounts, endsession, lua, auth, localstorage, cache]
dependency_graph:
  requires:
    - phase: 02-05
      provides: "M_auth.exchange_assertion, M_auth.fetch_profile, M_auth.persist_session, M_auth.cached_token, M_auth._extract_client_id"
    - phase: 02-04
      provides: "M_http.post_form, M_http.get_json, M_http.shutdown"
    - phase: 02-02
      provides: "M_errors.from_http_status"
    - phase: 02-03
      provides: "M_auth._decode_jwt_payload"
  provides:
    - "InitializeSession2 D-21 two-call probe (exchange_assertion -> fetch_profile -> persist_session)"
    - "InitializeSession2 D-22 client_id extraction with synchronous malformed-JWT error (zero network)"
    - "ListAccounts cache-read multi-merchant (D-23a/b: orgUuid accountNumber, publicName label)"
    - "EndSession M_http.shutdown + AUTH-06 LocalStorage preservation"
  affects: [02-07, phase-3, phase-4]
tech-stack:
  added: []
  patterns:
    - "D-21 two-call probe composition: M_auth.exchange_assertion -> M_errors.from_http_status -> M_auth.fetch_profile -> M_errors.from_http_status -> M_auth.persist_session"
    - "Pattern 4 malformed-JWT early-exit: _extract_client_id returns nil -> German error string -> zero network calls"
    - "ListAccounts empty-cache fallback: Phase-1 fixture retained when LocalStorage.zettle is nil or empty"
    - "orgUuid-prefix fallback for empty publicName: orgUuid:sub(1,8) so ACCT-04 labels are always distinguishable"
    - "entry_spec before_each reload pattern: Mocks.setup() + dofile() per test for fresh module-local _conn and clean LocalStorage"
key-files:
  created: []
  modified:
    - src/entry.lua
    - spec/entry_spec.lua
key-decisions:
  - "Switched entry_spec from setup()-once to before_each reload so module-local _conn inside M_http resets between tests (required for queued-response isolation)"
  - "Updated Phase-1 credential-shape tests that expected nil from non-JWT strings: malformed JWT now correctly returns error.invalid_grant without network calls"
  - "ListAccounts empty-cache fallback retained as Phase-1 placeholder (paypal-pos-fixture-001) so MoneyMoney always receives at least one account record before first successful auth"
  - "em-dash in account label encoded as literal UTF-8 bytes \\xe2\\x80\\x94 to avoid Lua source encoding ambiguity"
  - "TDD gate: RED commit staged spec only, GREEN commit staged src/entry.lua only"
patterns-established:
  - "Pattern: entry_spec.lua uses before_each reload (not setup-once) when tests need per-test HTTP response isolation"
  - "Pattern: orgUuid:sub(1,8) is the canonical fallback label suffix — reuse in Plan 02-07 SEC-03 assertions"
  - "Pattern: InitializeSession2 returns: nil (success) | LoginFailed (400/401/403 from either leg) | M_i18n.t('error.invalid_grant') (malformed JWT or empty key)"
requirements-completed: [AUTH-01, AUTH-03, AUTH-06, ACCT-01, ACCT-02, ACCT-04]
duration: 35min
completed: "2026-06-19"
---

# Phase 2 Plan 06: Entry Integration Summary

**InitializeSession2 wired to D-21 two-call probe (token + /users/self), ListAccounts reads LocalStorage.zettle per-merchant, EndSession calls M_http.shutdown — first user-visible Phase-2 slice**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-06-19T13:00:00Z
- **Completed:** 2026-06-19T13:35:00Z
- **Tasks:** 3 (all TDD)
- **Files modified:** 2 (src/entry.lua, spec/entry_spec.lua)

## Accomplishments

- InitializeSession2 second-call path implements D-22 client_id extraction + D-21 two-call probe. Valid JWT key: token exchange -> profile fetch -> persist_session -> nil (success). Malformed JWT: error.invalid_grant with zero network calls (Mocks._last_request confirmed nil). 400/401/403 on either leg: LoginFailed literal.
- ListAccounts iterates LocalStorage.zettle; emits one record per orgUuid with label "PayPal POS — " + publicName (falls back to orgUuid:sub(1,8) on empty publicName). Empty cache retains Phase-1 fixture.
- EndSession calls M_http.shutdown() — verified by Connection() invocation counter test; LocalStorage NOT cleared (AUTH-06 confirmed by flat-fallback restart simulation test).
- spec/entry_spec.lua: 24 tests (up from 14), zero pending, zero failures. Full Phase-2 suite: 100/0/0/0.
- src/entry.lua: 135 LoC (target ~130). Egress hosts: 0. pcall: 0. LocalStorage clearing ops: 0.

## InitializeSession2 Return Sequences (for Plan 02-07 SEC-03)

| Scenario | Return value |
|----------|-------------|
| credentials == nil | challenge object {title, challenge, label} (Phase-1, unchanged) |
| api_key == "" or nil | M_i18n.t("error.invalid_grant") (Phase-1 empty-key guard, unchanged) |
| Malformed JWT (no 3-segment aud/client_id) | M_i18n.t("error.invalid_grant") — zero network calls |
| 400/401/403 on POST /token | LoginFailed literal via M_errors.from_http_status |
| 400/401/403 on GET /users/self | LoginFailed literal via M_errors.from_http_status |
| Both legs 200, profile valid | nil — persist_session writes cache |

## Phase-1 Credential-Extraction Block Preservation

Lines 22-41 of src/entry.lua are bytewise identical to the Phase-1 original. The new D-22/D-21 code is inserted AFTER line 45 (the empty-key guard), replacing only lines 46-47. Verified via `sed -n '22,41p' src/entry.lua`.

## AUTH-06 LocalStorage Preservation

EndSession contains zero LocalStorage clearing operations (grep confirmed 0 occurrences of `LocalStorage.zettle = nil` in src/entry.lua). Test "cache survives EndSession + simulated restart via flat fallback (AUTH-06)" proves the flat-string path survives a simulated Q5 restart.

## orgUuid-prefix Fallback Label

`orgUuid:sub(1, 8)` — first 8 characters of the UUID, preceded by "PayPal POS — ". For ACCT-04 two-merchant coexistence, UUIDs with different first 8 chars always produce distinguishable labels even when both have empty publicName.

## Task Commits

1. **Tasks 1-3 RED: entry_spec.lua with failing tests** - `96cb0a2` (test)
2. **Tasks 1-3 GREEN: src/entry.lua implementation** - `fbdba46` (feat)

## Files Created/Modified

- `src/entry.lua` — 135 LoC; InitializeSession2 D-21 probe, ListAccounts cache-read, EndSession M_http.shutdown; Phase-1 credential block verbatim at L22-L41; RefreshAccount unchanged
- `spec/entry_spec.lua` — 24 tests; before_each reload pattern; covers D-21/D-22/D-23a/b/D-25/AUTH-06

## Decisions Made

- Switched entry_spec from setup()-once to before_each reload (required for per-test HTTP response isolation)
- Updated five Phase-1 credential-shape tests that expected nil from non-JWT strings — the new implementation correctly returns error.invalid_grant for any non-JWT input
- Retained Phase-1 walking-skeleton fallback in ListAccounts for empty cache (MoneyMoney must always receive at least one account record)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Phase-1 credential-shape tests expected nil from non-JWT strings**
- **Found during:** Task 1 (RED phase)
- **Issue:** Five old tests expected nil for inputs like "any-non-empty". Phase-2 implementation correctly returns M_i18n.t("error.invalid_grant") for any non-JWT string since _extract_client_id returns nil.
- **Fix:** Updated five tests to assert error.invalid_grant return + Mocks._last_request == nil (zero network calls).
- **Files modified:** spec/entry_spec.lua
- **Verification:** All 24 tests green; malformed-JWT tests confirm zero network calls.
- **Committed in:** `96cb0a2` (RED commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — test update to match correct new behavior)
**Impact on plan:** Required for correctness. No scope creep.

### Environment Deviation (pre-existing): luacheck binary broken on local Lua 5.5

- `luacheck 1.2.0-1` installed under Lua 5.5 has a `const variable` assignment error in `luacheck/standards.lua`.
- Code follows all project conventions: no undefined globals, all MM globals declared in `.luacheckrc`.
- CI runs on Lua 5.4 where luacheck works correctly.
- Pre-existing local environment issue first documented in Plan 02-05.

## Issues Encountered

None beyond the Phase-1 test update deviation documented above.

## Known Stubs

- `RefreshAccount` returns a hardcoded fixture transaction (Phase 3/4 owns real mapping). Intentional stub.
- `ListAccounts` returns `paypal-pos-fixture-001` placeholder when cache is empty. Removed automatically once first InitializeSession2 succeeds.

## Threat Flags

No new network endpoints, auth paths, or schema changes introduced. All trust-boundary crossings enumerated in the plan's threat model. No new flags.

## Self-Check: PASSED

- src/entry.lua exists: YES
- spec/entry_spec.lua exists: YES (24 tests, 0 failures)
- Commits exist: `96cb0a2` (test), `fbdba46` (feat) — verified via git log
- Egress hosts in entry.lua: 0
- LocalStorage clearing ops: 0
- Phase-1 credential block L22-L41: bytewise preserved
- Full suite: 100/0/0/0

## Next Phase Readiness

- Wave 4 complete. src/entry.lua is the complete MoneyMoney integration surface for Phase 2.
- Wave 5 (Plan 02-07) targets: SEC-03 redaction integration test through the full InitializeSession2 path now wired; log_redaction_spec.lua extension; final egress-grep CI gate.
- The "InitializeSession2 Return Sequences" table provides the exact fixture scenarios needed for SEC-03 assertions.

---
*Phase: 02-authenticated-network-layer*
*Completed: 2026-06-19*
