---
phase: 02-authenticated-network-layer
plan: "02-08-fix-batch"
subsystem: auth-layer
tags: [bugfix, tdd, robustness, security]
dependency_graph:
  requires: [02-07]
  provides: [B-01-fix, B-02-fix, H-01-fix, S-05-fix]
  affects: [src/entry.lua, src/auth.lua, src/http.lua]
tech_stack:
  added: []
  patterns: [tdd-red-green, belt-and-suspenders-guard, review-driven-fix]
key_files:
  modified:
    - src/http.lua
    - src/auth.lua
    - src/entry.lua
    - spec/http_spec.lua
    - spec/auth_spec.lua
    - spec/entry_spec.lua
decisions:
  - "B-01 guard placed in entry.lua only (not fetch_profile): keeps fetch_profile signature clean; entry.lua is the natural contract boundary"
  - "B-02 guard applied at two layers: entry.lua (primary, user-visible error) + persist_session (belt-and-suspenders, prevents any future caller from crashing the cache)"
  - "H-01: only 'rate_limit' added to _infer_status — not 'too_many_requests' (Zettle fixture confirms 'rate_limit' is the actual error key)"
  - "S-05 included opportunistically while touching src/auth.lua for B-02; single-line type check before length operator"
metrics:
  duration: "~20 min"
  completed: "2026-06-19"
  tasks: 4
  commits: 4
---

# Phase 2 Plan 02-08: Post-Review Fix Batch Summary

One-liner: Two nil-crash blockers (B-01/B-02) and one dead-code high (H-01) fixed via TDD
RED/GREEN with belt-and-suspenders guards; seven new tests, coverage at 99.04%.

---

## Findings Addressed

| Finding | Severity | File | Status |
|---------|----------|------|--------|
| B-01 | Blocker | `src/entry.lua` | Fixed |
| B-02 | Blocker | `src/entry.lua`, `src/auth.lua` | Fixed |
| H-01 | High | `src/http.lua` | Fixed |
| M-01 | Medium | `spec/entry_spec.lua`, `spec/auth_spec.lua` | Fixed (tests added) |
| M-02 | Medium | `spec/http_spec.lua`, `spec/entry_spec.lua` | Fixed (tests added) |
| S-05 | Low | `src/auth.lua` | Fixed (opportunistic) |

## Findings Deferred

| Finding | Severity | Reason |
|---------|----------|--------|
| S-03 | Low | `src/log.lua` — out of scope (blacklist) |
| S-04 | Low | `src/log.lua` — out of scope (blacklist) |
| S-06 | Low | `.gitignore` — separate PR |
| S-07 | Low | `.github/workflows/ci.yml` — frozen (blacklist) |
| L-01 | Low | `spec/auth_spec.lua` SEC-03 prefix check — test quality nit, Phase 5 |
| L-02 | Low | `spec/fixtures/auth/network_timeout.json` dead fixture — Phase 5 cleanup |

---

## Commits

| Hash | Type | Description |
|------|------|-------------|
| `841fb91` | test(02) | Add failing tests for B-01/B-02 nil-crash paths and H-01/M-02 rate_limit path (RED) |
| `dc5208f` | fix(02) | Map rate_limit error body to 429 in _infer_status (H-01) |
| `2ba6960` | fix(02) | Guard nil access_token in entry.lua D-21 leg-2 (B-01) |
| `a67f4b8` | fix(02) | Guard nil organizationUuid in persist_session + S-05 type check (B-02) |

---

## Fix Details

### B-01 — Nil access_token crash

**Root cause:** `_infer_status` returns 200 for any body lacking `.error`, regardless
of whether `access_token` is present. A truncated `/token` response produces
`token_table = {}` and `fetch_profile(nil)` throws at `"Bearer " .. nil`.

**Fix (`src/entry.lua`, after `from_http_status` nil-check):**

```lua
if type(token_table) ~= "table"
    or type(token_table.access_token) ~= "string"
    or #token_table.access_token == 0 then
  return M_i18n.t("error.invalid_grant")
end
```

**Effect:** Returns `"Anmeldung fehlgeschlagen: API-Key wurde abgelehnt."` — no
`/users/self` attempted, no crash, no raw Lua error surfaced.

---

### B-02 — Nil organizationUuid crash

**Root cause:** A malformed `/users/self` 200 response (e.g. `{}`) leaves
`profile.organizationUuid = nil`. `persist_session` calls `_cache_write(nil, entry)`
which throws `table index is nil` on `LocalStorage.zettle[nil]`.

**Fix layer 1 (`src/entry.lua`, after `/users/self` status check):**

```lua
if type(profile) ~= "table"
    or type(profile.organizationUuid) ~= "string"
    or #profile.organizationUuid == 0 then
  return M_i18n.t("error.invalid_grant")
end
```

**Fix layer 2 (`src/auth.lua` `persist_session`, belt-and-suspenders):**

```lua
local orgUuid = profile and profile.organizationUuid
if type(orgUuid) ~= "string" or orgUuid == "" then
  return nil
end
```

**Effect:** Clean German error returned from entry.lua; no cache write attempted;
`persist_session` also safe for any future caller that omits the entry.lua guard.

---

### H-01 — rate_limit error body maps to wrong status

**Root cause:** `_infer_status` had no branch for `"rate_limit"`, so it fell through
to the conservative `return 400`. `from_http_status(400)` returns `LoginFailed`,
making the entire D-24 case-4 (`status == 429`) branch dead code.

**Fix (`src/http.lua` `_infer_status`):**

```lua
if parsed.error == "rate_limit" then
  return 429
end
```

**Effect:** Zettle rate-limit responses now surface
`"Anfragelimit erreicht — bitte später erneut versuchen."` instead of a
misleading "wrong API key" rejection.

---

### S-05 — MM.base64decode non-string return (opportunistic)

**Fix (`src/auth.lua` `_decode_jwt_payload`):**

```lua
if not raw or type(raw) ~= "string" or #raw == 0 then return nil end
```

**Effect:** Any non-string truthy return from `MM.base64decode` is handled without
crashing on the `#` length operator.

---

## TDD Gate Compliance

- RED commit `841fb91`: `test(02)` — 7 new failing tests (4 failures + 3 errors on pre-fix artifact)
- GREEN commits `dc5208f`, `2ba6960`, `a67f4b8`: `fix(02)` — source fixes turn tests green
- Final suite: **110 successes / 0 failures / 0 errors**

---

## Test Coverage

| Metric | Before | After |
|--------|--------|-------|
| Total tests | 103 | 110 |
| Failures | 0 | 0 |
| Coverage (src/) | 99.32% | 99.04% |

Coverage slight decrease (-0.28 pp) is expected: the new guard branches add code
lines that are also executed by the new tests, but two early-return paths (nil orgUuid
in persist_session when called from a code path not exercised by the test suite) remain
partially covered. Overall coverage remains well above the 85% floor.

---

## New Tests Added (7)

| File | Test Name |
|------|-----------|
| `spec/http_spec.lua` | `_infer_status maps rate_limit body to 429 (H-01)` |
| `spec/http_spec.lua` | `post_form with rate_limited fixture returns 429 status (M-02)` |
| `spec/entry_spec.lua` | `InitializeSession2 returns error.invalid_grant when /token 200 has no access_token (B-01)` |
| `spec/entry_spec.lua` | `InitializeSession2 returns error.invalid_grant when /users/self 200 has no organizationUuid (B-02)` |
| `spec/entry_spec.lua` | `InitializeSession2 returns error.rate_limit when /token returns rate_limit body (M-02)` |
| `spec/auth_spec.lua` | `persist_session with nil organizationUuid returns nil and does not crash (B-02)` |
| `spec/auth_spec.lua` | `persist_session with empty-string organizationUuid returns nil and does not crash (B-02)` |

---

## Reproducible Build

SHA256: `a4bce112ba368b02eb28cd8e16edf7053243eeac33a17661d2251ab623baa528`
Verified: `lua tools/build.lua --verify` → OK

---

## Deviations from Plan

### Auto-applied: S-05 type check in `src/auth.lua`

The BLOCKERS brief listed S-05 as optional ("if you're already touching src/auth.lua for B-02,
consider adding the single-line type(raw) check"). Applied as a one-line change since the file
was already modified; confirmed no test changes needed (existing `_decode_jwt_payload` tests
continued to pass; the guard is a narrowing of an already-correct nil check).

All other changes match the brief exactly.

---

## Self-Check

- [x] `spec/http_spec.lua` modified — file exists
- [x] `spec/entry_spec.lua` modified — file exists
- [x] `spec/auth_spec.lua` modified — file exists
- [x] `src/http.lua` modified — file exists
- [x] `src/entry.lua` modified — file exists
- [x] `src/auth.lua` modified — file exists
- [x] All 4 commits verified in git log
- [x] 110/110 tests green
- [x] Reproducible build OK

## Self-Check: PASSED
