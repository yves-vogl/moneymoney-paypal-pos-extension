# Phase 2 — Authenticated Network Layer: Security Review

**Reviewed:** 2026-06-19
**Reviewer role:** Adversarial security engineer (report-only)
**Scope:** `src/auth.lua`, `src/http.lua`, `src/errors.lua`, `src/entry.lua`, `src/log.lua`, `spec/log_redaction_spec.lua`, `spec/auth_spec.lua`, `spec/http_spec.lua`, `spec/entry_spec.lua`, `.github/workflows/ci.yml`, `tools/build.lua`, `tools/manifest.txt`
**Method:** Five adversarial passes. Dry condition met at Pass 4 + Pass 5 (k=2 consecutive passes with no new findings).

---

## Severity Histogram

| Severity | Count |
|----------|-------|
| Critical | 0     |
| High     | 0     |
| Medium   | 2     |
| Low      | 5     |

## Class Histogram

| Class           | Count |
|-----------------|-------|
| OWASP-A06 (Vulnerable Components / Robustness) | 2 |
| OWASP-A02 (Crypto / Redaction)                 | 2 |
| Supply-Chain / CI                              | 1 |
| OPSEC (PII Disclosure)                         | 1 |
| Crypto / Robustness                             | 1 |

---

## Per-Threat Verdicts

| Threat | Description | Verdict | Evidence |
|--------|-------------|---------|----------|
| T1 | API key leaks to stdout/log/Console.app | MITIGATED | `src/log.lua:21-34` (four redaction rules); `assertion=` caught by rule 3; DEBUG=false gating; SEC-03 spec gate |
| T2 | API key leaks to MoneyMoney LocalStorage | MITIGATED | `src/auth.lua:133-144` (`persist_session` structurally excludes `api_key`); `spec/log_redaction_spec.lua:250-287` (LocalStorage walk) |
| T3 | Access token (Bearer) leaks via error string or log | PARTIAL | `src/errors.lua:15` (body param unused); `src/http.lua:121` (headers absent from GET log); gap: non-JWT opaque tokens in JSON response body not redacted (see S-03, S-04); gated by DEBUG=false in production |
| T4 | HTTP body echoed into error string | MITIGATED | `src/errors.lua:15` (`body` is `luacheck: ignore`d, structurally unused); all returned strings built from `M_i18n.t` templates only |
| T5 | Egress to host outside allowlist | MITIGATED | All URLs hardcoded (`src/auth.lua:75,88`); CI grep gate enforces allowlist; no URL construction from user input |
| T6 | Multi-merchant cache pollution | PARTIAL | Cache keyed by `orgUuid` (correct isolation); gap: nil/non-string `orgUuid` from `/users/self` causes `table index is nil` crash (see S-01) |
| T7 | Replay/timing on `cached_token` 60s guard | MITIGATED | Clock-backward scenario worst case: one failed API call (token appears fresh → Zettle rejects with 401 → re-auth triggered next session); no security amplification |
| T8 | `pcall` swallowing `Connection()` SSL errors | MITIGATED | `src/http.lua:86,118` — no `pcall` around `conn:request`; comment explicitly documents ADR-0003 Pitfall 3; SSL errors propagate correctly to MoneyMoney |
| T9 | Manifest concat-order forward-reference bug | MITIGATED | `tools/manifest.txt`: all cross-module calls happen at invocation time, not load time; `webbanking_header.lua` pre-declares all module tables; verified against `tools/build.lua` `do...end` wrapping |
| T10 | Build-time sandbox URL / production URL substitution leak | MITIGATED | D-27 (no sandbox toggle); no sandbox URLs found in `src/`; CI egress grep gate enforces allowlist in `dist/` |

---

## Findings

---

### S-01 — Missing guard for nil `profile.organizationUuid` before cache write

**Severity:** Medium
**Class:** OWASP-A06 (Robustness / Input Validation)
**Gap:** In `src/entry.lua:67`, `M_auth.persist_session(token_table, profile, client_id)` is called after `M_errors.from_http_status` returns nil (status 200). If `/users/self` returns a 200 with a JSON body that omits the `organizationUuid` field (e.g. `{}`), `profile.organizationUuid` is nil. `persist_session` calls `_cache_write(nil, entry)` at `src/auth.lua:143`, which attempts `LocalStorage.zettle[nil] = entry`. Lua raises a runtime error `table index is nil` that propagates uncaught to MoneyMoney, which will show the raw Lua error to the user instead of a clean German error message. No API key or token data is exposed, but the auth session ends in an unhandled error.
**Mitigation:** Add a guard in either `persist_session` or `entry.lua` before calling `_cache_write`. Example approach: if `profile.organizationUuid == nil or type(profile.organizationUuid) ~= "string" or #profile.organizationUuid == 0` then return a localized error string. Alternatively, treat a 200 with missing `organizationUuid` as a network/protocol error upstream in `entry.lua` before calling `persist_session`.
**Where to apply:** `src/auth.lua:133-144` (`persist_session`) or `src/entry.lua:62-67` (guard before persist call)
**Proof:** Call `InitializeSession2` with mock `/users/self` response `{}` (empty JSON object). After `from_http_status` returns nil (200 success), `persist_session` is invoked. The subsequent `_cache_write(nil, ...)` call throws `table index is nil` rather than returning a German error string.

---

### S-02 — Missing guard for nil `token_table.access_token` before Bearer header construction

**Severity:** Medium
**Class:** OWASP-A06 (Robustness / Input Validation)
**Gap:** In `src/entry.lua:62`, after a successful `/token` response (status 200), `M_auth.fetch_profile(token_table.access_token)` is called. If the `/token` response is a 200 with no `access_token` field (e.g. `{"expires_in":7200,"token_type":"Bearer"}`), `token_table.access_token` is nil. In `src/auth.lua:88`, `{ Authorization = "Bearer " .. access_token }` throws a Lua runtime error `attempt to concatenate a nil value`, which propagates uncaught. No credentials are exposed in the error message, but the session ends in an unhandled error.
**Mitigation:** After the successful `/token` response check, add an explicit guard: if `not token_table or type(token_table.access_token) ~= "string" or #token_table.access_token == 0` then return `M_i18n.t("error.network", "no access_token")`. This converts a protocol-level anomaly into a user-visible localized error.
**Where to apply:** `src/entry.lua:57-59` (after `exchange_assertion` call, before `fetch_profile` call)
**Proof:** Push a mock response `{"expires_in":7200,"token_type":"Bearer"}` to the response queue (no `access_token` field). Call `InitializeSession2` with a valid JWT. `from_http_status(200, ...)` returns nil. `fetch_profile(nil)` then attempts string concatenation and throws rather than returning a localized error.

---

### S-03 — Bearer redaction pattern does not match tokens containing `=` or `+` characters

**Severity:** Low
**Class:** OWASP-A02 (Crypto / Redaction)
**Gap:** `src/log.lua:27` redacts Bearer tokens with `s:gsub("Bearer%s+[%w%-_%.]+", "Bearer <redacted>")`. The character class `[%w%-_.]` does not include `=` (base64 padding) or `+` (standard base64 alphabet). If a future Zettle token format includes these characters, the pattern truncates at the first unrecognized character, leaving a fragment of the token value in the debug log output. Real Zettle tokens are currently JWT-shaped (caught earlier by rule 1, `src/log.lua:21-24`) and production builds have `DEBUG=false` enforced by build gate, so the production blast radius is zero. The gap is a structural weakness that would surface if debugging with a non-JWT-shaped access token.
**Mitigation:** Broaden the Bearer character class to cover the full base64 and base64url alphabet: `s:gsub("Bearer%s+[%w%-_%.%+%/=%@]+", "Bearer <redacted>")`. Alternatively, match any non-whitespace after `Bearer `: `s:gsub("Bearer%s+%S+", "Bearer <redacted>")`. The second form is more robust but slightly more aggressive.
**Where to apply:** `src/log.lua:27`
**Proof:** Call `M_log.redact("Bearer tok+ending=x")` and assert the result is `"Bearer <redacted>"`. The current pattern stops at `+` and returns `"Bearer tok+ending=x"` unchanged (only the leading word chars before `+` match, leaving the token fragment in output).

---

### S-04 — `access_token=` redaction rule targets form-encoded syntax only; JSON key-value form is not covered

**Severity:** Low
**Class:** OWASP-A02 (Crypto / Redaction)
**Gap:** `src/log.lua:33` redacts `access_token=[^%s&]+`, which matches form-encoded format (`access_token=VALUE`). The `/token` success response body, which contains `"access_token":"VALUE"` (JSON), is logged at DEBUG level in `src/http.lua:97` after `M_log.redact`. If the access token is not JWT-shaped (rule 1 miss) or has a short third segment that does not meet the 4-character minimum, the JSON form `"access_token":"VALUE"` passes through all four redaction rules unredacted. Production impact is zero because `DEBUG=false` is enforced, but a developer who enables `DEBUG=true` locally for troubleshooting would see the real access token in their Console.app or terminal.
**Mitigation:** Add a fifth redaction rule targeting the JSON key-value form: `s:gsub('"access_token"%s*:%s*"[^"]+"', '"access_token":"<redacted>"')`. Apply it in `_redact` after the existing four rules.
**Where to apply:** `src/log.lua:33` (add new rule immediately after)
**Proof:** Call `M_log.redact('{"access_token":"short_tok","expires_in":7200}')` and assert that `short_tok` does not appear in the result. With the current implementation, the JSON body passes through all four rules unchanged when `short_tok` is not JWT-shaped and fewer than 4 chars would match the JWT pattern.

---

### S-05 — `MM.base64decode` returning a non-string value causes `#raw` length error outside pcall

**Severity:** Low
**Class:** Crypto / Robustness
**Gap:** In `src/auth.lua:20`, `_b64url_decode` returns `MM.base64decode(s)`. If MoneyMoney's `base64decode` implementation returns a non-string value (e.g. `false`, `nil`, or an integer error code) for a malformed input, the return value is assigned to `raw` at `src/auth.lua:32`. The guard at line 33 (`if not raw or #raw == 0`) would throw `attempt to get length of a <type> value` for any non-string truthy return, because the `#` operator is not inside the `pcall` block that starts at line 36. This error propagates uncaught out of `_decode_jwt_payload` and through `_extract_client_id` into `InitializeSession2`, displaying a raw Lua error to the user instead of the German `error.invalid_grant` message.
**Mitigation:** Add a type check before the length check: `if not raw or type(raw) ~= "string" or #raw == 0 then return nil end`. This ensures that any unexpected return type from `MM.base64decode` is handled gracefully.
**Where to apply:** `src/auth.lua:33`
**Proof:** Replace `MM.base64decode` in the test mock temporarily with a function returning `false`. Call `M_auth._decode_jwt_payload("hdr.AAAA.sig")`. The current code throws at `#raw`; with the fix it returns nil cleanly.

---

### S-06 — macOS Finder alias file `Extensions` untracked and missing from `.gitignore`

**Severity:** Low
**Class:** OPSEC / PII Disclosure
**Gap:** `Extensions` is an untracked macOS Bookmark file (visible in `git status` as `?? Extensions`) that is not listed in `.gitignore`. The file contains the developer's username (`yves`), the macOS volume name (`Macintosh HD`), and a volume UUID (`1D6ED5AC-B400-4273-A1B1-A3DC8F1A9ADF`). If the file is accidentally included in a `git add .` or `git add -A` operation and pushed to a public repository, it discloses partial filesystem layout information about the developer's machine. It does not expose credentials or affect the extension's runtime behavior.
**Mitigation:** Add `Extensions` to `.gitignore` to prevent accidental commitment. The file is a developer convenience alias for the MoneyMoney extensions folder; the README's installation instructions already document the path, so no documentation change is needed.
**Where to apply:** `.gitignore` (add `Extensions` entry)
**Proof:** `git status` at session start shows `?? Extensions`. `grep "Extensions" .gitignore` returns nothing.

---

### S-07 — CI workflow `contents: write` permission is declared at job level rather than step level

**Severity:** Low
**Class:** Supply-Chain / CI
**Gap:** `ci.yml:10` declares `permissions: contents: write` for the entire `test` job. The write permission is only needed by the `Push coverage badge to coverage-badge branch` step, which itself is already gated by `if: success() && github.ref == 'refs/heads/main' && github.event_name == 'push'`. All lint, test, build, and verification steps run with write-capable credentials even though they only need read access. In GitHub Actions, a compromised action dependency in any non-badge step would inherit write access to the repository contents.
**Mitigation:** Move the badge push to a separate job with `permissions: contents: write` and set the main test job to `permissions: contents: read`. Alternatively, use `permissions: {}` at the workflow level and declare `contents: write` only on the badge push step (step-level permissions were introduced in GitHub Actions and are supported).
**Where to apply:** `.github/workflows/ci.yml:9-10`
**Proof:** Review `ci.yml:10`. The `test` job declares `permissions: contents: write` at the job level. Steps 1-9 (lint, test, coverage, build, verify, SEC-04 gate, egress gate, AI attribution gate) do not require write access.

---

## Test Coverage Assessment

SEC-03 (`spec/log_redaction_spec.lua:160-288`) correctly covers the API key non-leakage invariant at the integration level. Three scenarios are tested: malformed JWT (no network call), valid JWT with invalid_grant response, and successful full round-trip with LocalStorage walk.

Gap: No SEC-03 test exercises the `DEBUG=true` response body log path. If a developer enables `DEBUG=true` locally and Zettle returns a non-JWT-shaped opaque token, S-04 would surface. The existing tests run with `DEBUG=false` (default) and thus do not catch redaction gaps in the response body debug log.

Recommendation for a follow-on test: Add a `with_debug(fn)` test in `spec/log_redaction_spec.lua` that asserts `M_log.redact` of a realistic `/token` response body (including a non-JWT `access_token` value) produces no unredacted token material in the output.

---

## Pre-Launch Gate Assessment

No CRITICAL or HIGH findings. Phase 2 is **conditionally clear** for merge subject to the two MEDIUM findings being addressed or explicitly accepted.

| Finding | Gate Recommendation |
|---------|---------------------|
| S-01 (Medium) | Held-for-review PR — add nil/type guard on `profile.organizationUuid` before `_cache_write` |
| S-02 (Medium) | Held-for-review PR — add nil/type guard on `token_table.access_token` before `fetch_profile` |
| S-03 (Low) | Normal sec-PR batch — widen Bearer character class |
| S-04 (Low) | Normal sec-PR batch — add JSON `access_token` redaction rule |
| S-05 (Low) | Normal sec-PR batch — add `type(raw) == "string"` guard |
| S-06 (Low) | Normal sec-PR batch — add `Extensions` to `.gitignore` |
| S-07 (Low) | Normal sec-PR batch — narrow CI permissions scope |

---

<orchestrator_handoff>
{
  "verdict": "FINDINGS",
  "pass_count": 5,
  "dry_state": "Pass 4 and Pass 5 consecutive clean passes — dry condition met (k=2)",
  "sec03_compliant": "yes",
  "critical_findings_count": 0,
  "high_findings_count": 0,
  "medium_findings_count": 2,
  "low_findings_count": 5,
  "total_findings": 7,
  "threat_model_mitigated": ["T1", "T2", "T4", "T5", "T7", "T8", "T9", "T10"],
  "threat_model_partial": ["T3", "T6"],
  "top_findings": [
    "S-01 (Medium): nil profile.organizationUuid in /users/self 200 response causes table-index-is-nil Lua crash — add type guard before _cache_write call in src/auth.lua:143 / src/entry.lua:67",
    "S-02 (Medium): nil token_table.access_token from /token 200 response causes string concat crash in fetch_profile — add type guard in src/entry.lua before fetch_profile call at line 62",
    "S-03 (Low): Bearer redaction pattern src/log.lua:27 misses = and + chars in opaque tokens — widen character class; impact gated by DEBUG=false in production"
  ],
  "held_for_review_prs": ["S-01", "S-02"],
  "normal_sec_pr_batch": ["S-03", "S-04", "S-05", "S-06", "S-07"],
  "yves_decision_required": false,
  "recommendation": "Phase 2 is clear for merge with held-for-review PRs for S-01 and S-02. No blocking security findings. SEC-03 gating spec is correctly scoped and passes. The two Medium findings are robustness gaps (malformed server responses produce uncaught Lua errors instead of localized messages) rather than credential leakage or auth bypass issues."
}
</orchestrator_handoff>
