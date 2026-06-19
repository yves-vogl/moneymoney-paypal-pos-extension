---
phase: 02-authenticated-network-layer
reviewed: 2026-06-19T00:00:00Z
depth: deep
files_reviewed: 10
files_reviewed_list:
  - src/auth.lua
  - src/http.lua
  - src/errors.lua
  - src/entry.lua
  - spec/auth_spec.lua
  - spec/http_spec.lua
  - spec/errors_spec.lua
  - spec/entry_spec.lua
  - spec/log_redaction_spec.lua
  - spec/helpers/mm_mocks.lua
findings:
  blocker: 2
  high: 1
  medium: 2
  low: 2
  total: 7
status: issues_found
---

# Phase 02: Code Review Report — Authenticated Network Layer

**Reviewed:** 2026-06-19
**Depth:** deep (cross-file call-chain tracing)
**Files Reviewed:** 10
**Status:** issues_found

---

## Summary

The Phase-2 implementation covers `src/auth.lua`, `src/http.lua`, `src/errors.lua`, `src/entry.lua`, their tests, and the `mm_mocks` harness extension. Architecture is well-structured: the module-table pattern is consistent, the pcall discipline for attacker-controlled JSON is correctly applied, the D-25 single-Connection lifecycle is sound, and the SEC-03 log-redaction invariants hold end-to-end. No egress to out-of-allowlist hosts was found.

Two **blockers** exist in `src/entry.lua`: unchecked nil fields on the success path of the two-call D-21 probe. A **high** defect makes the D-24 case-4 rate-limit branch permanently dead. Two **medium** findings flag the missing negative test coverage that would have caught the blockers. Two **low** findings are test quality nits.

---

## BLOCKER Findings

### B-01: Nil `access_token` causes runtime crash before the second D-21 leg

**File:** `src/entry.lua:62`

**Issue:**
After `exchange_assertion` returns, the code guards against error status:

```lua
local token_table, status, raw_body = M_auth.exchange_assertion(api_key, client_id)
local err = M_errors.from_http_status(status, raw_body)
if err then return err end
-- status is 200 and token_table is a non-nil table here
local profile, p_status, p_raw = M_auth.fetch_profile(token_table.access_token)  -- line 62
```

`_infer_status` returns 200 whenever the JSON response body contains no `.error` field, regardless of whether `.access_token` is present. A 200-shaped response without `access_token` (e.g. a truncated reply, a CDN health-check proxy injecting an empty JSON object, or any future Zettle API change) produces `token_table = {}`. Then `token_table.access_token` is `nil`, and `fetch_profile(nil)` immediately errors with `attempt to concatenate a nil value` at `src/auth.lua:88`:

```lua
{ Authorization = "Bearer " .. access_token }  -- access_token == nil
```

This Lua runtime error propagates uncaught: there is no `pcall` wrapping the D-21 sequence in `entry.lua`, and MoneyMoney will surface a generic interpreter error to the user instead of a meaningful login-failure message.

**Fix:**
Add an explicit guard after the error-status check:

```lua
local token_table, status, raw_body = M_auth.exchange_assertion(api_key, client_id)
local err = M_errors.from_http_status(status, raw_body)
if err then return err end
if type(token_table) ~= "table" or type(token_table.access_token) ~= "string"
    or #token_table.access_token == 0 then
  return M_i18n.t("error.invalid_grant")
end
```

---

### B-02: Nil `organizationUuid` causes "table index is nil" crash in `_cache_write`

**File:** `src/entry.lua:67` (via `src/auth.lua:98-101`)

**Issue:**
After the second D-21 leg succeeds:

```lua
local profile, p_status, p_raw = M_auth.fetch_profile(token_table.access_token)
local p_err = M_errors.from_http_status(p_status, p_raw)
if p_err then return p_err end

M_auth.persist_session(token_table, profile, client_id)  -- line 67
```

`from_http_status` returns `nil` for any 200 body with no `.error` field, including a `/users/self` 200 response that lacks `organizationUuid`. `persist_session` then calls:

```lua
_cache_write(profile.organizationUuid, entry)  -- profile.organizationUuid == nil
```

Inside `_cache_write`:

```lua
LocalStorage.zettle[orgUuid] = entry            -- Lua: table index is nil -> ERROR
LocalStorage["zettle:" .. orgUuid] = ...        -- also errors if reached
```

Lua raises `table index is nil` on the first line; the error is uncaught.

**Fix:**
Add a guard in `entry.lua` after the profile-status check, and/or a defensive check in `persist_session`:

In `entry.lua`:
```lua
if p_err then return p_err end
if type(profile) ~= "table"
    or type(profile.organizationUuid) ~= "string"
    or #profile.organizationUuid == 0 then
  return M_i18n.t("error.invalid_grant")
end
M_auth.persist_session(token_table, profile, client_id)
```

Alternatively (defense-in-depth, in `src/auth.lua` `persist_session`):
```lua
function M_auth.persist_session(token_table, profile, client_id)
  if type(profile.organizationUuid) ~= "string" then return nil end
  ...
end
```

---

## HIGH Findings

### H-01: `_infer_status` missing `rate_limit` entry — D-24 case 4 is unreachable dead code

**File:** `src/http.lua:65-76`

**Issue:**
`_infer_status` derives a synthetic HTTP status from the Zettle JSON response body because `Connection():request` does not surface the actual HTTP status code (Risk R-1). The current mapping is:

| `parsed.error` | Inferred status |
|---|---|
| `invalid_grant`, `invalid_request` | 400 |
| `invalid_client`, `unauthorized_client` | 401 |
| anything else (including `rate_limit`) | 400 (conservative fallback) |
| no `.error` field | 200 |

The Zettle API returns `{"error":"rate_limit",...}` when the rate limit is exceeded (evidenced by `spec/fixtures/auth/token_rate_limited.json`). `_infer_status` has no branch for `"rate_limit"`, so it falls through to the conservative `return 400`. `from_http_status(400, ...)` then returns `LoginFailed`.

Consequence: a rate-limited user sees a "wrong API key" rejection (`LoginFailed`) instead of the "please retry later" message that `M_i18n.t("error.rate_limit")` and `D-24 case 4` exist to provide. The entire `status == 429` branch in `from_http_status` (`src/errors.lua:33-34`) is dead code — no code path can produce `status = 429`.

**Fix — add `rate_limit` to `_infer_status`:**

```lua
function M_http._infer_status(parsed)
  if parsed.error then
    if parsed.error == "invalid_grant" or parsed.error == "invalid_request" then
      return 400
    end
    if parsed.error == "invalid_client" or parsed.error == "unauthorized_client" then
      return 401
    end
    if parsed.error == "rate_limit" then
      return 429
    end
    return 400  -- conservative: unknown error names
  end
  return 200
end
```

Also add a spec case to `http_spec.lua`:
```lua
assert.equals(429, M_http._infer_status({ error = "rate_limit" }))
```

And an integration test in `entry_spec.lua` that pushes `Fixtures.load("auth/token_rate_limited")` and asserts the result equals `M_i18n.t("error.rate_limit")`.

---

## MEDIUM Findings

### M-01: No test covers the B-01 crash path (200 /token with missing `access_token`)

**File:** `spec/entry_spec.lua` (missing test)

**Issue:**
The entry_spec suite tests all cases where `/token` returns a recognizable error body (`token_invalid_grant.json`), but never tests a 200-status response where the JSON body lacks `access_token`. This means the B-01 crash path goes untested and undetected in CI. A test is straightforward to add:

```lua
it("InitializeSession2 returns error when token response is 200 but missing access_token", function()
  -- Push a 200-shaped body with no access_token field
  Mocks.push_response({ content = '{"token_type":"Bearer","expires_in":7200}' })
  local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                    { { value = VALID_JWT } }, false)
  assert.equals(M_i18n.t("error.invalid_grant"), result)
  assert.is_nil(LocalStorage.zettle)
end)
```

A parallel test should be added for the B-02 path (200 `/users/self` with missing `organizationUuid`).

---

### M-02: `token_rate_limited.json` fixture is dead — the rate-limit path is never exercised

**File:** `spec/fixtures/auth/token_rate_limited.json` + all spec files (missing usage)

**Issue:**
`spec/fixtures/auth/token_rate_limited.json` exists as the recorded fixture for a rate-limited token exchange, but `grep` finds zero references to it across all spec files. This means:

1. The H-01 defect (wrong user message on rate limit) was never caught in testing.
2. The fixture and `from_http_status`'s rate-limit branch were written in anticipation of a test that was never added.

Once H-01 is fixed (adding `rate_limit -> 429` to `_infer_status`), add an integration test in `entry_spec.lua` that uses this fixture and asserts the correct error string, and a unit test in `http_spec.lua` that asserts `_infer_status({error="rate_limit"}) == 429`.

---

## LOW Findings

### L-01: `auth_spec` SEC-03 LocalStorage walk uses weaker prefix check vs. the gating test

**File:** `spec/auth_spec.lua:314`

**Issue:**
The `auth_spec.lua` SEC-03 test ("persist_session never writes the api_key anywhere in LocalStorage", line 291-322) checks for the api_key by looking for the literal prefix `"hdr.eyJ"`:

```lua
assert.is_nil(v:find("hdr.eyJ", 1, true), ...)
```

The stronger approach (used in `log_redaction_spec.lua` Test 3, lines 279-286) iterates over every `.`-separated segment of the fake JWT and checks each independently. If the test JWT's prefix changes or a different synthetic key is used, the `"hdr.eyJ"` guard silently degrades (it would pass even if the payload segment leaked). This is a test maintainability concern, not a production bug.

**Fix:** Align with the segment-by-segment pattern from the gating test:
```lua
for seg in api_key:gmatch("[^.]+") do
  assert.is_nil(v:find(seg, 1, true),
    "LocalStorage must not contain JWT segment '" .. seg .. "'")
end
```

---

### L-02: `network_timeout.json` fixture is dead code

**File:** `spec/fixtures/auth/network_timeout.json`

**Issue:**
`spec/fixtures/auth/network_timeout.json` contains a JSON object `{"_source":"network anomaly — empty body case"}` and is never referenced by any spec. The empty-body network failure path is already tested in `http_spec.lua` via `Mocks.push_response({content=""})` directly. The fixture exists as documentation only but creates confusion (its JSON content means it could never simulate an actual empty-body scenario via `Fixtures.load`).

**Fix:** Either wire it into an `entry_spec` test for the network-failure path through `InitializeSession2`, or delete it. If kept, add a comment explaining it is documentation-only and not loadable as a mock response.

---

## Not Flagged (explicit non-findings)

The following areas were audited and found sound:

- **`_b64url_decode` padding arithmetic**: the `(4 - (#s % 4)) % 4` formula is correct for all input lengths 0–8 and general case. Empty-string input returns `""`, which `_decode_jwt_payload` correctly rejects via `#raw == 0`.
- **`_form_encode` sort and encoding**: keys are sorted alphabetically and `MM.urlencode` correctly leaves RFC 3986 unreserved chars (including `.`) unencoded. Assertion JWT dots pass through correctly.
- **JSON mock branching (`mm_mocks.lua`)**: `JSON(nil)` routes to encode path, `JSON(string)` routes to decode path — correctly matching MoneyMoney's real API.
- **5-tuple destructure in `M_http`**: `post_form` and `get_json` both name all five return values from `conn:request` (lines 94, 122). The `luacheck: ignore 211` annotations are appropriate for the unused trailing values.
- **Bearer header never logged**: `get_json` logs only `"GET " .. url` with headers intentionally absent (line 121). Confirmed by the `get_json never logs the Bearer header value` spec.
- **D-23c double-write**: `_cache_write` correctly writes to both `LocalStorage.zettle[orgUuid]` and `LocalStorage["zettle:" .. orgUuid]`. `_cache_read` correctly prioritises the nested path and falls back to the flat JSON string with pcall protection.
- **`cached_token` expiry guard**: `now >= expires_at - 60` correctly implements the 60-second pre-expiry margin (D-23d). Tested for both expired and near-expiry cases.
- **SEC-03 log redaction**: The four-pass `_redact` function correctly neutralises the assertion form field (pass 3 catches `assertion=<value>` even for short three-char signatures that elude the JWT pattern in pass 1). Confirmed end-to-end by `log_redaction_spec` and the SEC-03 gating suite.
- **`EndSession` does not clear LocalStorage**: Confirmed by `entry_spec` AUTH-06 test. `M_http.shutdown` sets `_conn = nil` without touching `LocalStorage`.
- **Egress host allowlist**: Only `oauth.zettle.com`, `purchase.izettle.com`, and `finance.izettle.com` URLs appear in Phase-2 source. No other host strings found.
- **No `pcall` around `conn:request`**: Correctly absent per Pitfall 3 / ADR-0003. The `pcall` discipline comment in `http.lua:84` is accurate.

---

_Reviewed: 2026-06-19_
_Reviewer: Claude (adversarial code review)_
_Depth: deep_
