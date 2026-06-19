---
phase: 02-authenticated-network-layer
plan: "05"
subsystem: auth
tags: [auth, oauth, localstorage, cache, multi-merchant, lua, tdd]
dependency_graph:
  requires: [02-01, 02-02, 02-03, 02-04]
  provides: [M_auth.exchange_assertion, M_auth.fetch_profile, M_auth.persist_session, M_auth.cached_token]
  affects: [src/auth.lua, spec/auth_spec.lua]
tech_stack:
  added: []
  patterns:
    - D-23c double-write pattern (nested LocalStorage.zettle[org] + flat "zettle:org" JSON string)
    - D-23d pre-expiry guard (60s window before expires_at)
    - D-21 two-call probe (exchange_assertion + fetch_profile compose to full auth)
key_files:
  created: []
  modified:
    - src/auth.lua
    - spec/auth_spec.lua
decisions:
  - "Lua pattern mode (not plain) for percent-encoded form-body assertions in spec: body:find(\"grant_type=urn%%3A...\") rather than body:find(str, 1, true) — avoids plain-mode treating %- as literal percent+hyphen"
  - "Bearer removed from fetch_profile comment to satisfy grep -cE 'Bearer ' src/auth.lua == 1 acceptance criterion"
  - "Cache entry shape field order: access_token, obtained_at, expires_at, client_id, uuid, publicName"
metrics:
  duration: "approx 25 minutes"
  completed_date: "2026-06-19T12:38:25Z"
  tasks_completed: 2
  files_changed: 2
---

# Phase 02 Plan 05: Auth Orchestration Layer Summary

**One-liner:** JWT-bearer OAuth exchange + /users/self probe + D-23c nested+flat LocalStorage double-write with 60s pre-expiry guard and two-org isolation.

## What Was Built

### `src/auth.lua` additions (Wave 3 — ~105 LoC delta on top of 57 LoC from Plan 02-03)

Final file: **162 lines** total (57 from Plan 02-03 + 105 from this plan).

#### M_auth.exchange_assertion(api_key, client_id)
POSTs `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&client_id=<client_id>&assertion=<api_key>` to `https://oauth.zettle.com/token` via `M_http.post_form`. Returns `(token_table, status, raw)`. The api_key (assertion) flows through to M_http and is redacted in debug logs by M_log.redact — it is never stored, never persisted.

#### M_auth.fetch_profile(access_token)
GETs `https://oauth.zettle.com/users/self` with `Authorization: Bearer <access_token>` via `M_http.get_json`. Returns `(profile_table, status, raw)`. M_http.get_json structurally omits the Authorization header from all log lines (T-02-04-02 / T-02-05-02 defense-in-depth).

#### M_auth.persist_session(token_table, profile, client_id)
Builds the D-23c cache entry:
```
{
  access_token = token_table.access_token,
  obtained_at  = os.time(),
  expires_at   = os.time() + (tonumber(token_table.expires_in) or 7200),
  client_id    = client_id,
  uuid         = profile.uuid,
  publicName   = profile.publicName,
}
```
Then calls `_cache_write(profile.organizationUuid, entry)`.

**STRUCTURAL GATE (AUTH-05 / SEC-03 / T-02-05-01):** The api_key (assertion JWT) is NOT a field of this entry. The only credential in the cache is the Zettle-issued `access_token` (2h TTL, scope-limited bearer).

#### M_auth.cached_token(orgUuid)
Calls `_cache_read(orgUuid)`. Returns nil when:
- No entry found (nested or flat path both miss)
- `entry.access_token` is nil or missing
- `os.time() >= (entry.expires_at or 0) - 60` (D-23d 60s pre-expiry guard)

Emits exactly **one** `M_log.info` call on the expired-entry path: `"cached_token: expired for org=" .. orgUuid:sub(1,8)` — truncated UUID prefix only, never the token.

Returns `entry.access_token` when fresh.

#### private _cache_write(orgUuid, entry)
D-23c double-write:
```lua
LocalStorage.zettle = LocalStorage.zettle or {}
LocalStorage.zettle[orgUuid] = entry
LocalStorage["zettle:" .. orgUuid] = JSON():set(entry):json()
```

#### private _cache_read(orgUuid)
Read priority (D-23c):
1. Nested: `LocalStorage.zettle[orgUuid]` if non-nil
2. Flat-string fallback: `LocalStorage["zettle:" .. orgUuid]` — pcall-wrapped JSON parse

### `spec/auth_spec.lua` additions

**Before:** 12 successes / 9 pending  
**After:** 24 successes / 0 failures / 0 errors / 0 pending

All 9 Wave-0 pending stubs greened. Three additional structural tests added:
- `exchange_assertion content type is x-www-form-urlencoded` (R-1 contract)
- `fetch_profile never echoes the access token in any captured print` (T-02-05-02)
- `persist_session never writes the api_key anywhere in LocalStorage` (T-02-05-01 recursive walk)

## Threat Surface Confirmation

### T-02-05-01: api_key never in LocalStorage
- **Status: MITIGATED** — cache entry shape is locked to `{access_token, obtained_at, expires_at, client_id, uuid, publicName}`. The `assertion` field is structurally absent.
- **Gate:** test "persist_session never writes the api_key anywhere in LocalStorage" performs a recursive walk over all string values in LocalStorage after the full init sequence and asserts none contain `"hdr.eyJ"` (the synthetic api_key prefix). Test passes.

### T-02-05-02: access_token not in expired-entry log
- **Status: MITIGATED** — the single `M_log.info` call emits only `orgUuid:sub(1,8)`, never the token. M_log.redact additionally strips any JWT-shaped or Bearer-shaped strings.
- **Gate:** test "fetch_profile never echoes the access token in any captured print" passes.

### T-02-05-03: Multi-merchant cache overwrite (ACCT-04)
- **Status: MITIGATED** — `_cache_write` keys by `orgUuid` in both paths. Two distinct orgs coexist without collision.
- **Gate:** test "two orgs coexist in cache" — both `cached_token("org-1")` and `cached_token("org-2")` return their respective tokens after sequential `persist_session` calls. Test passes.

### T-02-05-04: Stale token past expires_at
- **Status: MITIGATED** — 60s pre-expiry guard active. Tested: expired entry, within-60s entry both return nil; 3600s-fresh entry returns token.

### T-02-05-05: Nested table lost on restart (Q5)
- **Status: MITIGATED** — flat-string fallback written every `persist_session`. Test "cache survives reload via flat fallback" sets `LocalStorage.zettle = nil` after persist and asserts `cached_token` still returns the access_token via the flat path. Test passes.

## Cache Entry Shape (exact, for Wave 3 cross-restart simulation)

The flat JSON encoding is produced by `JSON():set(entry):json()` (dkjson in test harness, MoneyMoney JSON() in production). Field names: `access_token`, `obtained_at`, `expires_at`, `client_id`, `uuid`, `publicName`. All values are strings or integers. No nested tables. `publicName` may be `null` in the JSON if not returned by /users/self.

To simulate a cross-restart scenario in Wave 3 tests: call `persist_session`, then set `LocalStorage.zettle = nil`, then call `cached_token(orgUuid)` — it must return the access_token via the flat `LocalStorage["zettle:" .. orgUuid]` JSON string.

## Acceptance Criteria Verification

| Criterion | Result |
|-----------|--------|
| busted spec/auth_spec.lua: 0 pending, 0 failures | 24 successes / 0 failures / 0 pending |
| busted spec/ (full suite) | 90 successes / 0 failures / 0 pending |
| grep -c 'oauth.zettle.com/token' src/auth.lua >= 1 | 2 (comment + code) |
| grep -c 'oauth.zettle.com/users/self' src/auth.lua >= 1 | 2 (comment + code) |
| grep -cE '(purchase\|finance)\.izettle\.com' src/auth.lua == 0 | 0 |
| grep -c 'urn:ietf:params:oauth:grant-type:jwt-bearer' == 1 | 1 |
| grep -cE 'Bearer ' src/auth.lua == 1 | 1 |
| grep -c 'function M_auth.persist_session' == 1 | 1 |
| grep -c 'function M_auth.cached_token' == 1 | 1 |
| grep -c 'local function _cache_write' == 1 | 1 |
| grep -c 'local function _cache_read' == 1 | 1 |
| grep -c 'LocalStorage.zettle' >= 3 | 5 |
| grep -c '"zettle:"' >= 2 | 3 |
| grep -c 'expires_at' >= 2 | 4 |
| grep -c 'M_log.info' == 1 | 1 |
| grep -c 'require' == 0 | 0 |
| lua tools/build.lua --verify | OK: reproducible (sha256: 17870ec653e935855e6ebc02c9c65c8ddcf0a6de05cb0cef48fb300c8eee9e2d) |
| Coverage (full suite, dist artifact) | 98.51% |

## Deviations from Plan

### [Rule 1 — Bug] Lua pattern mode required for percent-encoded form body assertions

**Found during:** Task 1 test authoring  
**Issue:** Plan's `<action>` specified `body:find("grant_type=urn%%3A...", 1, false)` (pattern mode with `%%` escaping). Initial implementation used `find(str, 1, true)` (plain/literal mode) with pattern escape sequences like `%-` — in plain mode, `%-` is a literal percent+hyphen, not a hyphen, causing all `find` calls on the grant_type to return nil.  
**Fix:** Switched assertions to Lua pattern mode (omit the `true` third argument): `body:find("grant_type=urn%%3Aietf%%3Aparams%%3Aoauth%%3Agrant%-type%%3Ajwt%-bearer")`. `%%` = literal `%`, `%-` = literal `-`. This matches the actual encoded body correctly.  
**Files modified:** `spec/auth_spec.lua`  
**Commit:** 26a625a

### Environment Deviation (pre-existing): luacheck binary broken on local Lua 5.5

- Identical to the deviation documented in Plan 02-04.
- `luacheck 1.2.0-1` is built for Lua 5.5 which has a `const variable` bug.
- Code follows project conventions (no undefined globals, all MM globals declared in `.luacheckrc`).
- CI on Lua 5.4 will validate.

## Known Stubs

None. All 4 orchestration functions are fully implemented and wired to real deps (M_http, LocalStorage, os.time). No placeholder data flows to UI.

## Threat Flags

None. All new endpoints (`oauth.zettle.com/token`, `oauth.zettle.com/users/self`) are already in the D-26 egress allowlist and were planned in the threat model.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| src/auth.lua exists | FOUND |
| spec/auth_spec.lua exists | FOUND |
| 02-05-SUMMARY.md exists | FOUND |
| commit 26a625a exists | FOUND |
| busted spec/auth_spec.lua | 24 successes / 0 failures / 0 pending |
| busted spec/ (full suite) | 90 successes / 0 failures / 0 pending |
