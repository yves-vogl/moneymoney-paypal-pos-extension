---
phase: 02-authenticated-network-layer
plan: "04"
subsystem: http-transport
tags: [http, oauth, connection, redaction, lua, security]
dependency_graph:
  requires: [02-01, 02-02]
  provides: [M_http.post_form, M_http.get_json, M_http.shutdown, M_http._infer_status]
  affects: [02-05]
tech_stack:
  added: []
  patterns:
    - Single module-local Connection, lazy-created and reused (D-25)
    - Accept: application/json unconditionally injected by _merge_headers (Pitfall 1)
    - Body-shape status inference via _infer_status (Risk R-1)
    - M_log.redact on all POST/GET bodies before DEBUG log (T-02-04-01)
    - Headers structurally excluded from all log lines (T-02-04-02)
    - No pcall around conn:request (Pitfall 3)
    - pcall only around JSON parse
key_files:
  created:
    - path: src/http.lua
      description: M_http module — Connection wrapper per D-25 (144 LoC)
  modified:
    - path: spec/helpers/mm_mocks.lua
      description: Added Mocks._last_request capture for HTTP introspection
    - path: spec/http_spec.lua
      description: Converted 10 pending Wave-0 stubs to real assertions; all green
decisions:
  - "_infer_status unknown error names mapped to 400 (conservative; Pitfall 5)"
  - "Bearer-non-leakage enforced structurally: GET log line is method+URL only"
  - "With-debug helper pattern used in specs to avoid DEBUG=true bleed"
metrics:
  duration: "~30 minutes"
  completed: "2026-06-19"
  tasks_completed: 2
  files_modified: 3
---

# Phase 2 Plan 04: M_http Connection Wrapper Summary

**One-liner:** `Connection()` transport wrapper with unconditional `Accept: application/json`, body-shape status inference, JWT/Bearer redaction-before-log, and idempotent shutdown.

## What Was Built

### src/http.lua (144 LoC)

Full implementation of the D-25 HTTP transport seam:

- `M_http.post_form(url, body_table, headers)` — x-www-form-urlencoded POST; sorted-key body via `_form_encode`; `_merge_headers` forces `Accept: application/json`; 5-tuple destructure; `M_log.redact` on request and response bodies before DEBUG log; `pcall` only around JSON parse (never around `conn:request`); returns `(parsed, inferred_status, raw)` or `(nil, nil, raw)`.
- `M_http.get_json(url, headers)` — GET with same Accept-injection; DEBUG request log is structurally `"GET " .. url` only (headers never concatenated); returns same triple.
- `M_http._infer_status(parsed)` — body-shape status derivation per Risk R-1: `invalid_grant` / `invalid_request` → 400; `invalid_client` / `unauthorized_client` → 401; unknown error → 400 (conservative); no error field → 200.
- `M_http.shutdown()` — closes `_conn` if non-nil and has `close` method; sets `_conn = nil`; idempotent.
- Private: `_get_connection()`, `_form_encode(t)`, `_merge_headers(user_headers)`.

### spec/helpers/mm_mocks.lua

Wave-2 addition: `Mocks._last_request` captures `{method, url, body, contentType, headers}` from the most recent `conn:request` call for spec introspection. Reset in `Mocks.setup()` and `Mocks.teardown()`. 5-tuple return contract unchanged. Risk R-1 comment added: production code must not read this field.

### spec/http_spec.lua

All 10 Wave-0 pending stubs converted to real assertions:

| Test | Behavior Verified |
|------|-------------------|
| post_form constructs sorted form body | Keys sorted alphabetically; MM.urlencode applied; colons → %3A |
| post_form always sends Accept: application/json | `Mocks._last_request.headers["Accept"] == "application/json"` |
| post_form returns 5-tuple destructured correctly | Returns `(decoded_table, 200, raw_json)` |
| post_form passes raw body through M_log.redact | JWT-shaped body redacted to `<redacted>` in DEBUG log |
| post_form returns nil status for empty body | `(nil, nil, "")` when content="" |
| _infer_status maps invalid_grant body to 400 | 400 for invalid_grant/invalid_request; 401 for invalid_client/unauthorized_client; 400 for unknown |
| _infer_status maps success body to 200 | 200 for {access_token="AT"} and {uuid="u"} |
| get_json never logs the Bearer header value | No captured print contains "SECRET_TOKEN_XYZ" or "Bearer" |
| shutdown nils the module-local Connection | Connection() call count increments after shutdown confirms fresh _conn |
| shutdown is idempotent | Double-shutdown without error |

## Test Results

- `busted spec/http_spec.lua`: **11 successes / 0 failures / 0 errors / 0 pending**
- `busted spec/` (full suite): **78 successes / 0 failures / 0 errors / 9 pending**
- Coverage (dist/paypal-pos.lua, full suite): **99.56%** (227/228 lines hit)
- The single missed line is the JSON parse-failure `return nil, nil, raw` branch in both `post_form` and `get_json` (covered by 4 pcall invocations; the failure path requires a malformed JSON fixture not exercised in current suite).
- `lua tools/build.lua --verify`: **OK: reproducible** (sha256: 5b75122aed447cd5cdded80079cbbcc4ca08364c39e05e31d6d0deb98d46f30a)

## Canonical Form Body for Plan 02-05

The exact body emitted by `M_http.post_form` for the canonical OAuth token call
(assertion + client_id + grant_type, sorted alphabetically) is:

```
assertion=<JWT>&client_id=<UUID>&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer
```

Colons encoded as `%3A`. Keys in alphabetical order: `assertion` < `client_id` < `grant_type`.
Plan 02-05's `exchange_assertion` test can assert this body byte-for-byte.

## Security Verification

| Constraint | Status | Evidence |
|------------|--------|---------|
| No host strings in http.lua | PASS | Comment-only mention of domains; no strings in non-comment code |
| No pcall around conn:request | PASS | `grep -v '^--' src/http.lua | grep 'pcall.*conn:request'` → 0 matches |
| Headers never concatenated into log lines | PASS | `grep -E '(headers|user_headers)\s*\.\.' src/http.lua` → 0 matches |
| Bodies redacted before log | PASS | 4 `M_log.redact` calls; test asserts JWT-shape → `<redacted>` |
| No require() in shipped code | PASS | Only in comment line |
| Accept: application/json always set | PASS | `_merge_headers` unconditional; test asserts header value |

## Threat Register Coverage

| Threat ID | Disposition | Test Gate |
|-----------|-------------|-----------|
| T-02-04-01 (DEBUG body leak) | mitigated | "post_form passes raw body through M_log.redact" |
| T-02-04-02 (GET Bearer leak) | mitigated | "get_json never logs the Bearer header value" |
| T-02-04-03 (missing Accept) | mitigated | "post_form always sends Accept: application/json header" |
| T-02-04-04 (status misclassification) | accepted | unknown errors → 400; documented in Pitfall 5 |
| T-02-04-05 (pcall hiding SSL errors) | mitigated | acceptance criterion verified |

## Deviations from Plan

### Environment Deviation: luacheck binary broken on local machine

- **Found during:** Task 1 / Task 2 verification
- **Issue:** The installed `luacheck 1.2.0-1` is built for Lua 5.5 and fails at startup with `attempt to assign to const variable 'field_name'` in `luacheck/standards.lua` — a Lua 5.5 compatibility bug in luacheck 1.2.0-1. No Lua 5.4 luarocks installation exists on this machine to provide a working luacheck binary.
- **Impact:** Cannot run `luacheck src/ spec/` locally. Prior wave summaries showed `luacheck 0 warnings` — those were CI runs. Local luacheck was already broken before this plan executed (pre-existing env issue).
- **Mitigation:** `luacheck` inline annotations (`-- luacheck: ignore 211`) were added following project conventions. The CI workflow (`luacheck .`) will validate on push. No code changes required.
- **Classification:** Pre-existing environment issue; not a code deviation.

### Minor Spec Deviation: _infer_status test merged into one it() block

- **Found during:** Task 2 implementation
- **Issue:** The plan named two separate pending tests ("_infer_status maps invalid_grant body to 400" and "_infer_status maps success body to 200"). Both are implemented in those exact test names, but the invalid_grant test also covers `invalid_request`, `invalid_client`, `unauthorized_client`, and unknown error cases inline (rather than separate `it()` blocks per case).
- **Rationale:** Inline sub-cases are idiomatic busted practice; they all pass; the spec is more complete than the plan specified.
- **Classification:** [Rule 2 - Enhancement] — extra coverage, not a reduction.

## Known Stubs

None. `src/http.lua` is fully wired: `_get_connection` uses the real `Connection()` global (mocked in tests), `_form_encode` uses `MM.urlencode`, `JSON()` is called directly.

## Self-Check: PASSED

- src/http.lua: EXISTS (144 LoC)
- spec/http_spec.lua: EXISTS (11 tests, 0 pending)
- spec/helpers/mm_mocks.lua: EXISTS (Mocks._last_request in 5 locations)
- .planning/phases/02-authenticated-network-layer/02-04-SUMMARY.md: EXISTS
- Commit 502ceed (feat(02-04): extend mm_mocks): EXISTS
- Commit b1d0505 (feat(02-04): implement M_http): EXISTS
- busted spec/ 78/0/0/9: VERIFIED
- lua tools/build.lua --verify: OK reproducible
