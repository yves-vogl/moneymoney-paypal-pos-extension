---
phase: 02-authenticated-network-layer
plan: "02"
subsystem: errors
tags: [lua, errors, i18n, status-mapping, sec-03, auth-03, d-24, tdd]

requires:
  - phase: 02-authenticated-network-layer/02-01
    provides: test infrastructure (mm_mocks, fixtures, build toolchain, spec scaffolds)

provides:
  - M_errors.from_http_status(status, body) — six-case D-24 HTTP status mapping
  - SEC-03 structural invariant: body parameter never echoed in returned strings
  - AUTH-03 synchronous fail surface: 400/401/403 → LoginFailed literal

affects:
  - 02-03 (M_auth will call from_http_status for token exchange errors)
  - 02-05 (M_http._infer_status feeds status codes to from_http_status)
  - Wave 3 / 02-entry (InitializeSession2 calls from_http_status twice per D-21)
  - Phase 5 (additive extension of from_http_status with retry hints, unchanged signature)

tech-stack:
  added: []
  patterns:
    - "Module-attachment idiom: M_errors.from_http_status = function(...) end (no local function M_errors pattern)"
    - "SEC-03 pattern: accept body param for forward-compat but never reference it in function body; luacheck: ignore comment suppresses unused-var warning cleanly"
    - "i18n-only error strings: all user-facing text via M_i18n.t, no hardcoded German text in logic modules"
    - "TDD: RED commit (test(02-02)) followed by GREEN commit (feat(02-02)) — gate sequence verified"

key-files:
  created: []
  modified:
    - src/errors.lua
    - spec/errors_spec.lua

key-decisions:
  - "body param accepted but unused (SEC-03): accepted as second parameter for Phase-5 forward-compatibility, structurally unused inside function body — no pcall, no log, no concat. luacheck: ignore comment on function signature line."
  - "catch-all branch mirrors 5xx: D-24 specifies unknown status codes route to error.network with tostring(status), same as 5xx, rather than returning nil (which would silently pass an error through)"
  - "luacheck for Lua 5.4: installed luacheck 1.2.0 into ~/.luarocks (Lua 5.4 target) separately from the system luacheck (Lua 5.5 compat broken in 1.2.0). CI uses leafo/gh-actions-lua@v13 which pins 5.4 and installs its own luacheck."

patterns-established:
  - "SEC-03: every errors.lua function must accept body/response as parameter but never reference it on a return RHS"
  - "D-24 branch order: nil-check first, then 2xx, then specific auth codes, then 429, then 5xx range, then catch-all"

requirements-completed: [AUTH-03, SEC-03]

duration: 25min
completed: 2026-06-19
---

# Phase 2 Plan 02: M_errors.from_http_status — D-24 Six-Case HTTP Status Mapping Summary

**`M_errors.from_http_status(status, body)` implemented per D-24 with SEC-03 body-redaction structural guarantee; 12/12 tests green including AUTH-03 LoginFailed gate and SEC-03 invariant test; 100% line coverage on pure-logic module.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-06-19T09:55:00Z
- **Completed:** 2026-06-19T10:21:54Z
- **Tasks:** 1 (TDD: RED + GREEN commits)
- **Files modified:** 2

## Accomplishments

- Replaced Phase-1 stub in `src/errors.lua` with full D-24 six-case mapping (43 LoC including header comments)
- SEC-03 structural guarantee: `body` parameter is accepted but never referenced inside the function body; all returned strings come exclusively from `M_i18n.t` templates
- Greened all 10 D-24 pending test cases in `spec/errors_spec.lua` plus added 1 SEC-03 structural-invariant gate test (11 total + 1 pre-existing sanity test = 12 tests)
- Full Phase-2 suite: 58 successes / 0 failures / 0 errors / 24 pending (pending tests are Wave 0 scaffolds for Plans 02-03/02-05, untouched)
- luacheck clean on both modified files (Lua 5.4 target)
- Reproducible build holds: `lua tools/build.lua --verify` passes with deterministic SHA256

## Task Commits

TDD gate sequence:

1. **RED — spec/errors_spec.lua** - `0182b9d` (test(02-02): add failing assertions for M_errors.from_http_status D-24 cases)
2. **GREEN — src/errors.lua + spec/errors_spec.lua** - `46d3ebb` (feat(02-02): implement M_errors.from_http_status per D-24 (six cases))

## Files Created/Modified

- `src/errors.lua` — `M_errors.from_http_status(status, body)` implementation, 43 LoC; replaces 3-line Phase-1 stub
- `spec/errors_spec.lua` — 12 active tests (was 10 pending + 1 active sanity); added SEC-03 structural-invariant test

## Exact German Strings Returned (for Wave 3 / entry integration test authors)

| Case | Input | Return value |
|------|-------|-------------|
| nil status | `(nil, "")` | `"Netzwerkfehler: —"` |
| 2xx | `(200, ...)` | `nil` |
| 400/401/403 | `(400, ...)` | `"LoginFailed"` (MoneyMoney literal from `_G.LoginFailed`) |
| 429 | `(429, "")` | `"Anfragelimit erreicht — bitte später erneut versuchen."` |
| 5xx | `(500, "")` | `"Netzwerkfehler: 500"` |
| catch-all | `(999, "")` | `"Netzwerkfehler: 999"` |

Note: `LoginFailed` is a MoneyMoney runtime global; mocked as the string `"LoginFailed"` in `spec/helpers/mm_mocks.lua:274`. Production runtime receives the actual MoneyMoney `LoginFailed` signal object.

## busted / luacheck / coverage Numbers

- **busted spec/errors_spec.lua:** 12 successes / 0 failures / 0 errors / 0 pending
- **busted spec/ (full suite):** 58 successes / 0 failures / 0 errors / 24 pending
- **luacheck src/errors.lua spec/errors_spec.lua:** 0 warnings / 0 errors (Lua 5.4 target via `~/.luarocks/bin/luacheck`)
- **coverage src/errors.lua:** 100% — every branch executed by the 12 tests

## Decisions Made

1. **`body` accepted but unused (SEC-03):** The parameter is included in the function signature to establish the Phase-5 stable surface. A `-- luacheck: ignore body` annotation on the function signature line satisfies luacheck without removing the forward-compat parameter.

2. **catch-all mirrors 5xx branch:** D-24 case 6 (unrecognised status codes) routes to `error.network` with `tostring(status)` rather than `nil`. This closes the "silent passthrough" pitfall (RESEARCH §Pitfall 5): if `_infer_status` produces an unknown integer, `from_http_status` still surfaces an error string rather than returning nil and masking the failure.

3. **luacheck Lua 5.4 installation:** The system luacheck is installed under Lua 5.5 and fails with a const-variable error in luacheck 1.2.0's love.lua builtin standard. Installed `luacheck 1.2.0` into `~/.luarocks` via `luarocks --lua-version=5.4 --lua-dir=/opt/homebrew/opt/lua@5.4 install luacheck`. CI is unaffected (uses `leafo/gh-actions-lua@v13` which provisions Lua 5.4 and its own luarocks environment).

## Deviations from Plan

None — plan executed exactly as written. The `luacheck` toolchain issue is a local developer environment matter (Lua 5.5 vs 5.4 luacheck conflict), not a plan deviation.

## Issues Encountered

- **luacheck Lua 5.5 incompatibility:** `luacheck 1.2.0` installed under Lua 5.5 fails with `attempt to assign to const variable 'field_name'`. Resolved by installing luacheck into the Lua 5.4 luarocks tree. CI is not affected.
- **busted binary not found initially:** Test tools were not pre-installed on this developer machine. Installed `busted`, `luacheck`, `luacov`, `dkjson` via `luarocks install` before running tests. CI is not affected.
- **dist/ not present in worktree:** The worktree does not inherit `dist/` from the main repo (gitignored). Created `dist/` in the worktree and ran the build from the worktree root so the spec's `dofile("dist/paypal-pos.lua")` resolves correctly.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Known Stubs

None — `from_http_status` is fully implemented for all D-24 cases. No placeholder text, no hardcoded empty returns, no TODO markers.

## Next Phase Readiness

- `M_errors.from_http_status` is the stable public surface Plan 02-03 (M_auth) and Plan 02-05 (M_http) will call
- Signature `(status:integer|nil, body:string?) -> string|nil` is locked for Phase 2 through Phase 5
- Wave 3 (Plan 02-entry) can wire `from_http_status(status, body)` in `InitializeSession2` legs 1 and 2 per D-21
- Phase 5 can extend additively (new status codes, retry metadata) without changing the signature

## Self-Check: PASSED

- `src/errors.lua` exists and contains `M_errors.from_http_status`: confirmed
- `spec/errors_spec.lua` exists with 12 active tests: confirmed
- Commit `0182b9d` (RED) exists: confirmed
- Commit `46d3ebb` (GREEN) exists: confirmed
- `busted spec/errors_spec.lua` exits 0: confirmed (12/0/0/0)
- `luacheck src/errors.lua spec/errors_spec.lua` exits 0: confirmed
- `lua tools/build.lua --verify` reproducible: confirmed

---
*Phase: 02-authenticated-network-layer*
*Completed: 2026-06-19*
