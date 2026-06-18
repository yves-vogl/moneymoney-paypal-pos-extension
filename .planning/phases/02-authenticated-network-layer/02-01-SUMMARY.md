---
phase: 02-authenticated-network-layer
plan: "01"
subsystem: test-infrastructure
tags: [test-infra, fixtures, mocks, base64, lua, wave-0]
dependency_graph:
  requires: []
  provides:
    - spec/fixtures/auth/token_ok.json
    - spec/fixtures/auth/token_invalid_grant.json
    - spec/fixtures/auth/users_self_ok.json
    - spec/fixtures/auth/users_self_unauthorized.json
    - spec/fixtures/auth/token_rate_limited.json
    - spec/fixtures/auth/network_timeout.json
    - MM.base64decode (real RFC 4648 decoder in mm_mocks.lua)
    - Mocks.push_response status field (test ergonomics only)
    - spec/auth_spec.lua (pending scaffold)
    - spec/http_spec.lua (pending scaffold)
    - spec/errors_spec.lua (pending scaffold)
  affects:
    - spec/helpers/mm_mocks.lua (extended)
tech_stack:
  added: []
  patterns:
    - pure-Lua RFC 4648 standard-base64 decoder (bitwise shift operators, Lua 5.4)
    - pending() test scaffold with before_each Mocks.setup + dofile pattern
    - spec/fixtures/auth/<name>.json nested path via Fixtures.load concat
key_files:
  created:
    - spec/fixtures/auth/token_ok.json
    - spec/fixtures/auth/token_invalid_grant.json
    - spec/fixtures/auth/users_self_ok.json
    - spec/fixtures/auth/users_self_unauthorized.json
    - spec/fixtures/auth/token_rate_limited.json
    - spec/fixtures/auth/network_timeout.json
    - spec/auth_spec.lua
    - spec/http_spec.lua
    - spec/errors_spec.lua
  modified:
    - spec/helpers/mm_mocks.lua
decisions:
  - "MM.base64decode replaced with real RFC 4648 decoder using bitwise shift; MM.base64 kept as identity (Phase 2 never encodes, SEC-03 uses hardcoded strings per Pitfall 8)"
  - "push_response status stored on entry.headers.status, NOT in 5-tuple return (Risk R-1 contract preserved)"
  - "Fixtures.load nested-path already works on macOS POSIX without code change (empirically verified by sanity test)"
metrics:
  duration: "~25 minutes"
  completed: "2026-06-18T12:34:00Z"
  tasks_completed: 3
  tasks_total: 3
  files_created: 9
  files_modified: 1
---

# Phase 2 Plan 01: Wave 0 Test Infrastructure Summary

Wave 0 test infrastructure established: six fixture files, a real base64 decoder mock, and three pending spec scaffolds unblock all Phase-2 implementation waves (M_errors Wave 1, M_auth Wave 2, M_http Wave 2).

## What Was Built

### Task 1: Six hand-rolled JSON fixtures under spec/fixtures/auth/

| File | Purpose | `_source` citation |
|------|---------|-------------------|
| `token_ok.json` | Successful token response with synthetic JWT shape | iZettle/api-documentation/authorization.md |
| `token_invalid_grant.json` | 400 error response for D-24 LoginFailed path | iZettle/api-documentation/authorization.md |
| `users_self_ok.json` | Merchant profile with UTF-8 `publicName` (Beispiel Café GmbH) | iZettle/api-documentation/faq.adoc |
| `users_self_unauthorized.json` | Scope-failure error for D-21 leg 2 failure path | iZettle/api-documentation/authorization.md |
| `token_rate_limited.json` | 429 inference test fixture for D-24 rate_limit mapping | iZettle/api-documentation/authorization.md |
| `network_timeout.json` | Empty-body sentinel for network anomaly (D-24 nil status) | network anomaly — empty body case |

All six fixtures:
- Parse as strict JSON via dkjson with no errors
- Carry a top-level string-valued `_source` key as citation
- Contain only synthetic data — no real merchant UUIDs, no real API key
- UTF-8 umlaut present in `users_self_ok.json` (`publicName: "Beispiel Café GmbH"`) to exercise UTF-8 round-trip

### Task 2: MM.base64decode real decoder + push_response status field

**MM.base64decode** is now a real RFC 4648 standard-base64 decoder (replaces the Phase-1 identity stub at L146). The decoder:

- Is implemented as `local function _base64decode(s)` defined above `Mocks.setup()` (~30 LoC)
- Uses Lua 5.4 bitwise shift operators (`<<`, `>>`, `|`, `&`) for the 6-bit accumulator loop
- Tolerates `=` padding (strips before processing), empty input (returns `""`), whitespace
- Accepts the standard alphabet `[A-Za-z0-9+/]`

Round-trip verification (Risk R-6 mandate):
- `MM.base64decode("YWJj")` → `"abc"` (plain 3-byte, no padding)
- `MM.base64decode("YWJjZA==")` → `"abcd"` (with `=` padding)
- `MM.base64decode("eyJhdWQiOiJjbGllbnQteCJ9")` → `'{"aud":"client-x"}'` (JWT payload round-trip that `_extract_client_id` depends on)
- `MM.base64decode("")` → `""` (empty input benign)

`MM.base64` (encode) kept as identity stub — Phase 2 production code never encodes; SEC-03 specs use hardcoded base64 strings per RESEARCH Pitfall 8.

**Mocks.push_response status field** (Risk R-1 contract):
- `opts.status` (integer, optional) is stored on the queue entry at `entry.headers.status`
- The `conn:request` 5-tuple return `(content, charset, mime, filename, headers)` is unchanged
- Production code MUST NOT read `headers.status` — M_http derives status from body shape via `_infer_status`
- A 3-line Risk R-1 contract comment was added above `push_response`
- Specs may inspect `Mocks._response_queue[i].headers.status` for assertions

### Task 3: Three pending spec scaffolds

All three files use the `before_each(Mocks.setup + dofile)` pattern from `spec/log_redaction_spec.lua`.

| Spec file | Sanity tests | Pending tests | Coverage targets |
|-----------|-------------|--------------|-----------------|
| `spec/auth_spec.lua` | 2 | 14 | AUTH-02/04/06, D-21/22/23c, ACCT-04 |
| `spec/http_spec.lua` | 1 | 10 | D-25, SEC-01/AUTH-05, Risk R-1, D-24 |
| `spec/errors_spec.lua` | 1 | 10 | D-24 six-case from_http_status mapping |

Sanity tests (non-pending, confirmed passing):
- `auth_spec.lua`: "M_auth module table is exposed" + "Fixtures.load reads auth/token_ok"
- `http_spec.lua`: "M_http module table is exposed"
- `errors_spec.lua`: "M_errors module table is exposed"

The `Fixtures.load("auth/token_ok")` sanity test in `auth_spec.lua` empirically confirms nested-path concat works on macOS POSIX without any code change to `spec/helpers/fixtures.lua`.

## Final Verification Results

```
lua tools/build.lua --verify
  OK: reproducible (sha256: 362b745159b33c557541ae7c6d4bcf0a62580f9be0b72f4f896537ddcafd0e23)

luacheck . (25 files)
  Total: 0 warnings / 0 errors

busted spec/
  47 successes / 0 failures / 0 errors / 34 pending
```

Baseline before this plan: 43 successes / 0 failures. Net additions: +4 sanity tests, +34 pending tests.

## Deviations from Plan

None — plan executed exactly as written. No structural changes, no new packages, no blocked tasks.

## Fixtures.load Nested-Path Discovery

No unexpected behavior found. `spec/helpers/fixtures.lua` concatenates `"spec/fixtures/" .. name .. ".json"` as a plain string; on macOS POSIX, `"auth/token_ok"` resolves correctly to `spec/fixtures/auth/token_ok.json` without any code change. Confirmed via `assert.is_string(raw)` in `auth_spec.lua` sanity test.

## Self-Check: PASSED

All created files verified to exist:
- `spec/fixtures/auth/token_ok.json` — FOUND
- `spec/fixtures/auth/token_invalid_grant.json` — FOUND
- `spec/fixtures/auth/users_self_ok.json` — FOUND
- `spec/fixtures/auth/users_self_unauthorized.json` — FOUND
- `spec/fixtures/auth/token_rate_limited.json` — FOUND
- `spec/fixtures/auth/network_timeout.json` — FOUND
- `spec/helpers/mm_mocks.lua` (modified) — FOUND
- `spec/auth_spec.lua` — FOUND
- `spec/http_spec.lua` — FOUND
- `spec/errors_spec.lua` — FOUND

All task commits verified in git log:
- `5a9fa17` — chore(02-01): add six hand-rolled JSON fixtures — FOUND
- `ef39d2a` — feat(02-01): real base64 decoder + push_response status field — FOUND
- `f2dbbaa` — test(02-01): add pending spec scaffolds for M_auth, M_http, M_errors — FOUND
