# Phase 5: Resilience & Error Handling — Research

**Researched:** 2026-06-21
**Domain:** Adversarial-condition handling in the MoneyMoney WebBanking sandbox (Lua 5.4, no LuaSocket, no LuaRocks)
**Confidence:** HIGH (all D-61..D-69 implementation paths are mappable to existing code; one CONTEXT-naming error corrected — see §1)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-61..D-69)

- **D-61** ERR-01 invalid_grant ⇒ `LoginFailed`. Verify path is structurally gated; extend `spec/auth_spec.lua` with explicit ERR-01 test using the existing `auth_invalid_grant.json` fixture.
- **D-62** ERR-02 5xx retry-with-backoff. Max 3 attempts (1 original + 2 retries). Sleep durations: 1s, 2s, 4s (exponential, base 2). Each attempt logged INFO with `attempt=N/3 status=503`. If all 3 fail → `error.server_busy`.
- **D-63** ERR-03 429. Honor `Retry-After` (seconds; `tonumber`); cap at 60s. Without `Retry-After`, default 30s then return `error.rate_limit`. Single retry per refresh.
- **D-64** ERR-04 post-mint 401. ONE silent re-mint via `M_auth.exchange_assertion` and retry. If retry also 401s → `error.token_revoked` (NEW i18n key — German "Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen"). NOT `LoginFailed`.
- **D-65** ERR-05 network failures. The Phase-2 design REJECTS pcall around `Connection():request` (Pitfall 3, ADR-0003 Q8). Surface network failures via the existing empty-body / nil-status path; returns `error.network`. Queue `Mocks.push_response({ content = "" })` to simulate.
- **D-66** ERR-06 fail-whole-refresh. Any error inside RefreshAccount returns immediately. The `since` parameter is NEVER mutated. Gating spec: queue successful purchase fetch + 500 on finance fetch; assert (a) German error string returned, (b) `Mocks._captured_requests` shows purchase happened, (c) no transactions, (d) second refresh with same `since` succeeds.
- **D-67** Sleep mechanism. **Recommendation: `MM.sleep(seconds)` (NOT `MM.os.sleep`)** — documented in MoneyMoney WebBanking API. Q9 probe optional (capability is documented; probe only confirms version-specific behavior). Test harness already mocks `MM.sleep` as no-op at `spec/helpers/mm_mocks.lua:233`.
- **D-68** Retry log discipline. Each retry attempt emits exactly ONE INFO log: `"HTTP retry: attempt=2/3 status=503 url=... after_ms=1000"`. Bearer redacted by existing `M_log.redact`. SEC-03 spec extended.
- **D-69** Extend `M_errors.from_http_status` central truth source with 4 entries. Never bypass.

### Claude's Discretion

- Retry logic location: `M_http.get_json` inline (vs sibling helper) — recommendation: **inline**, every caller wants it.
- 401 silent re-mint location: `M_auth.with_retry(orgUuid, callback)` wrapper — recommendation: **in M_auth**, keeps M_http auth-agnostic.
- 429 retry vs immediate fail: **single retry as documented in D-63**.

### Deferred Ideas (OUT OF SCOPE)

- Persistent circuit-breaker / N-consecutive-failures account disable.
- User-configurable retry counts / backoff curves.
- Notification outside MoneyMoney account-row UI.
- Automatic API-key rotation on token-revoked.
- Health-check / liveness endpoint.
- Webhook / push delivery from PayPal POS.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ERR-01 | Token-mint `invalid_grant` returns `LoginFailed` constant | §1 — Phase 2 path is correct; M_errors maps 400 → LoginFailed; extend auth_spec.lua with explicit fixture-driven test |
| ERR-02 | 5xx triggers retry-with-backoff (max 3 attempts) | §3 — `M_http.get_json_with_retry` inline extension; §6 — `MM.sleep` durations 1s/2s/4s (sum ≤ 7s); §10 D-62 — `error.server_busy` German string |
| ERR-03 | 429 honors `Retry-After` header (sane cap) | §2 — `Retry-After` parsing matrix (integer-only); §4.b — header capture pathway from `conn:request` 5-tuple |
| ERR-04 | Post-token-mint 401 triggers ONE silent re-mint | §5 — `M_auth.with_retry(orgUuid, callback)` wrapper; §10 — `error.token_revoked` German string |
| ERR-05 | Network failure produces German error string, never Lua error | §4.a — Connection error surface matrix; existing empty-body → nil-status path covers DNS/TLS/timeout/refused |
| ERR-06 | Any failure inside RefreshAccount aborts whole refresh | §6 — fail-whole-refresh invariant audit of 16-step pipeline; §9 — gating-spec mock sequencing |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Retry/backoff for transient HTTP failures | M_http (transport layer) | — | Phase-2 contract: every caller wants retry; centralizing here means zero opt-in bugs |
| Sleep between retries | M_http (consumer) | `MM.sleep` (sandbox primitive) | Sandbox primitive; M_http calls it inside `_sleep_with_jitter` helper |
| Post-mint 401 silent re-mint | M_auth (token lifecycle) | M_http (consumer) | M_auth owns token cache; retry-with-re-mint belongs there to keep M_http auth-agnostic |
| Status code → German error string | M_errors (central dispatch) | M_i18n (string table) | D-69: never bypass; existing six-case dispatch grows by 4 entries |
| Fail-whole-refresh invariant enforcement | entry.lua RefreshAccount (orchestrator) | M_errors (early-return values) | Phase 4 made it implicit; Phase 5 makes it spec-gated |
| Retry-attempt logging | M_log.info (logger) | M_log.redact (Bearer safety) | SEC-03 invariant; redactor already covers any string concatenation |

## Summary

Phase 5 layers four distinct adversarial-condition handlers onto a Phase 2/3/4 pipeline that already centralizes errors through `M_errors.from_http_status` (D-43, D-69). The good news: every D-61..D-69 implementation hook lands on existing module seams — no new modules, no new external dependencies, no sandbox capabilities beyond `MM.sleep` (which is **documented in the MoneyMoney WebBanking API** under the `MM.*` helpers and **already stubbed in `spec/helpers/mm_mocks.lua:233`**).

**One CONTEXT-naming error to correct in PLAN files:** the function is `MM.sleep(seconds)`, **not** `MM.os.sleep(seconds)`. The MoneyMoney WebBanking API exposes the sleep helper under the `MM` table directly. The CONTEXT used `MM.os.sleep` in D-67 and the "Yves Blockers" Q9 row; the planner must reference `MM.sleep` throughout PLAN files and Q9 becomes a low-priority confirmation probe rather than a blocker.

The two structurally hardest items are not the retries themselves but: (1) capturing the `Retry-After` header value when `conn:request` returns the 5-tuple `(content, charset, mime, filename, headers)` — the existing M_http code discards the 5th return value (`resp_headers`); Phase 5 must wire it through (§4.b); and (2) the ERR-06 fail-whole-refresh gating spec — which has to assert that the SECOND refresh with the SAME `since` re-fetches everything, proving the watermark never advanced (§9).

**Primary recommendation:** Implement Phase 5 in **5 waves**: Wave 0 (i18n keys + ADR-0005 sleep mechanism), Wave 1 (extend `M_errors.from_http_status` + RED specs), Wave 2 (`M_http.get_json` + `post_form` retry-with-backoff for 5xx and 429), Wave 3 (`M_auth.with_retry` wrapper + entry.lua call-site rewiring), Wave 4 (`spec/refresh_fail_whole_spec.lua` gating + SEC-03 retry-log extension). Q9 sleep probe is **optional Wave 0 sub-task** (Yves can run during ADR drafting); it does not block subsequent waves because `MM.sleep` is documented and mocked.

## Standard Stack

### Core (already present; Phase 5 extends, does NOT add deps)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Lua | 5.4.x (MoneyMoney embeds 5.4.8) | Implementation | Sandbox constraint per CLAUDE.md |
| `MM.sleep(seconds)` | Built-in (documented) | Block for N seconds | The ONLY sandbox-sanctioned sleep primitive; no LuaSocket `socket.sleep` available |
| `MM.time()` | Built-in | Millisecond clock for backoff measurement | Already used for token cache |
| `M_http`, `M_auth`, `M_errors`, `M_i18n`, `M_log` | Phase 2 modules | All Phase-5 extensions land in these | No new modules — keeps surface area frozen |
| `busted` 2.3.0 + `luacov` 0.16.0 | Already pinned | Spec gating | No CI changes |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `MM.sleep` for backoff | Busy-wait via `os.clock()` loop | If Q9 ever reveals `MM.sleep` is broken on a future MM version, busy-wait at 100% CPU for 1-7s is acceptable; ADR-0005 documents the fallback |
| Inline retry in `M_http.get_json` | Sibling `M_http.get_json_with_retry` | Opting in is a bug-magnet — every Phase-2/3/4 caller wants the semantics; inline is the safe default per D-Discretion |
| `M_auth.with_retry` wrapper | Retry-on-401 inside `M_http` | Would force M_http to know about token lifecycle; violates Phase-2 thin-transport contract |
| `tonumber(retryAfter)` integer-only | Full HTTP-date parsing per RFC 7231 §7.1.3 | HTTP-date adds ~80 LoC of date parsing for a header Zettle has never been observed to use; integer-only is conservative and ADR-documented |
| Recursive retry | Iterative `for attempt = 1, 3 do` loop | Recursion hits Lua call-stack limit on persistent failures (Pitfall §10.a); iterative is bounded |

**No new installs.** Phase 5 ships zero new LuaRocks deps — `MM.sleep` is sandbox-built-in and `tonumber` is stdlib.

## Package Legitimacy Audit

> **Not required for Phase 5** — no external packages installed. All retry/backoff/sleep functionality is implemented in pure Lua using existing modules + `MM.sleep` (sandbox built-in).

## Architecture Patterns

### System Architecture Diagram

```
RefreshAccount(account, since)        [entry.lua — fail-whole-refresh boundary]
        │
        ├─ Step 2:  M_auth.cached_token(orgUuid)
        │           └→ nil? → return error.network    [Phase-2 path; ERR-05 covered]
        │
        ├─ Step 4:  M_auth.with_retry(orgUuid, function(bearer)        [NEW Wave 3]
        │              return M_purchases.fetch_all(effective_since, bearer)
        │           end)
        │           │
        │           └→ inside with_retry:
        │              callback(bearer) → returns (data, err)
        │              if err == LoginFailed (post-mint 401):
        │                 ONE re-mint via M_auth.exchange_assertion
        │                 callback(new_bearer) → returns (data, err2)
        │                 if err2 still LoginFailed:
        │                    return nil, error.token_revoked
        │              return data, nil
        │           if err → return err                                 [ERR-06 fail-whole]
        │
        ├─ Step 7:  M_auth.with_retry(orgUuid, function(bearer)
        │              return M_finance.fetch_account_state(bearer)
        │           end)
        │           if err → return err                                 [ERR-06 fail-whole]
        │
        ├─ Step 8:  M_auth.with_retry(orgUuid, function(bearer)
        │              return M_finance.fetch_all(effective_since, bearer)
        │           end)
        │           if err → return err                                 [ERR-06 fail-whole]
        │
        └─ Steps 9-16: pure-logic mapping; no network; no error paths to extend
```

Inside `M_http.get_json` (and `post_form`), per-call retry loop:

```
M_http.get_json(url, headers):
        for attempt = 1, MAX_ATTEMPTS do                             [3 attempts]
           (raw, ..., resp_headers) = conn:request(...)              [5-tuple captured]
           parsed = JSON-parse-with-pcall
           status = _infer_status(parsed) or _infer_status_from_headers(resp_headers)

           if status == 200 → return data
           if status == 429:
              if attempt == 1:
                 sleep_s = min(parse_retry_after(resp_headers) or 30, 60)
                 M_log.info("HTTP retry: attempt=1/2 status=429 after_ms=" .. sleep_s*1000)
                 MM.sleep(sleep_s)
                 continue
              else:
                 return data, status   [exhausted single retry budget; caller maps to error.rate_limit]
           if status >= 500 and status <= 599:
              if attempt < 3:
                 sleep_s = 2 ^ (attempt - 1)            [1, 2, 4]
                 M_log.info("HTTP retry: attempt=" .. attempt .. "/3 status=" .. status .. " after_ms=" .. sleep_s*1000)
                 MM.sleep(sleep_s)
                 continue
              else:
                 return data, status   [exhausted retries; caller maps to error.server_busy]
           otherwise → return data, status                            [no retry; caller decides]
        end
```

### Recommended Project Structure (no changes)

```
src/
├── http.lua              # EXTEND: retry-with-backoff inside get_json/post_form
├── auth.lua              # EXTEND: M_auth.with_retry(orgUuid, callback) wrapper
├── errors.lua            # EXTEND: 4 new branches (rate_limit, server_busy, network, token_revoked)
├── i18n.lua              # EXTEND: error.server_busy + error.token_revoked (new keys, de + en)
├── entry.lua             # EXTEND: wrap Step 4 / 7 / 8 in M_auth.with_retry
├── log.lua               # NO CHANGE (redact already covers retry log lines)
spec/
├── errors_spec.lua       # EXTEND: new status-code mappings
├── auth_spec.lua         # EXTEND: ERR-01 LoginFailed assertion using token_invalid_grant fixture
├── http_spec.lua         # EXTEND: retry loop + 429 Retry-After + backoff durations
├── refresh_fail_whole_spec.lua    # NEW — ERR-06 gate
├── http_retry_spec.lua            # NEW — fine-grained retry behavior
├── log_redaction_spec.lua # EXTEND: assert retry log lines contain no "Bearer "
```

### Pattern 1: Retry-with-backoff inside a transport function

**What:** Wrap the existing thin `conn:request` call in a `for attempt = 1, MAX_ATTEMPTS do … end` loop. Sleep between attempts using `MM.sleep`. Surface header status (429 retry hint) via a side channel.

**When to use:** Every transport-layer HTTP call that targets an idempotent endpoint (all Zettle GETs are idempotent; the OAuth POST is also retry-safe — re-minting the same assertion grant yields the same access_token within the 7200s TTL window).

**Example:**
```lua
-- Source: derived from src/http.lua Phase 2; sleep call mirrors MM.sleep docs.
local MAX_RETRY_ATTEMPTS = 3  -- 1 initial + 2 retries
local BACKOFF_SECONDS    = { 1, 2, 4 }  -- exponential, base 2 (D-62)
local RATE_LIMIT_DEFAULT = 30  -- seconds without Retry-After (D-63)
local RATE_LIMIT_CAP     = 60  -- seconds upper bound (D-63)

local function _parse_retry_after(resp_headers)
  -- D-63: integer seconds only; HTTP-date silently degrades to default (Pitfall §10.d).
  -- Negative values rejected (Pitfall §10.d).
  if type(resp_headers) ~= "table" then return nil end
  local ra = resp_headers["Retry-After"] or resp_headers["retry-after"]
  if ra == nil then return nil end
  local n = tonumber(ra)
  if n == nil or n < 0 then return nil end
  return math.min(math.floor(n), RATE_LIMIT_CAP)
end

local function _sleep(seconds, url, attempt, status)
  -- M_log.info: structured key=value; Bearer never present (defense-in-depth).
  M_log.info("HTTP retry: attempt=" .. attempt .. "/" .. MAX_RETRY_ATTEMPTS ..
             " status=" .. tostring(status) ..
             " url=" .. url ..
             " after_ms=" .. (seconds * 1000))
  MM.sleep(seconds)
end
```

### Pattern 2: M_auth.with_retry wrapper for post-mint 401

**What:** Take a callback that returns `(data, err)` where `err` is the German string from `M_errors.from_http_status`. If `err == LoginFailed` (post-mint 401), perform exactly ONE re-mint and retry. If retry also returns `LoginFailed`, return `error.token_revoked` (NOT `LoginFailed`, per D-64).

**When to use:** Every entry.lua call site that hits a Bearer-authenticated endpoint (purchases, finance state, finance transactions).

**Example:**
```lua
-- Source: derived from D-64 + existing M_auth surface.
-- NOTE: M_auth.with_retry does NOT take api_key as a parameter — it reads the
-- cache entry (which stores client_id) and re-uses MoneyMoney's credentials
-- callback via interactive=true to obtain a fresh assertion when needed.
-- ALTERNATIVE: cache the api_key in module-local (NOT LocalStorage; SEC-03)
-- for the duration of the RefreshAccount call so re-mint is silent.
function M_auth.with_retry(orgUuid, callback)
  local bearer = M_auth.cached_token(orgUuid)
  if not bearer then
    return nil, M_i18n.t("error.network", "\xe2\x80\x94")
  end
  local data, err = callback(bearer)
  if err ~= LoginFailed then
    return data, err  -- success, or non-auth error (network, 5xx, rate-limit)
  end
  -- Post-mint 401: ONE silent re-mint attempt (D-64).
  -- See §10.c pitfall: re-mint itself must NOT recurse into with_retry.
  local entry = _cache_read(orgUuid)
  if not entry or not entry.client_id then
    return nil, M_i18n.t("error.token_revoked")
  end
  -- The api_key is NOT in the cache (SEC-03 / AUTH-05); we cannot silently
  -- re-mint without it. Return token_revoked so MoneyMoney prompts re-entry.
  -- (See Open Questions §1 — this is the load-bearing design decision.)
  return nil, M_i18n.t("error.token_revoked")
end
```

**CRITICAL DESIGN TENSION:** D-64 says "perform one silent re-mint" but AUTH-05 / SEC-03 forbid storing the API key in LocalStorage. The api_key is only present during the `InitializeSession2` window. Two reconciliation paths:

  a. **Cache api_key in module-local Lua variable** (not LocalStorage, not on disk) for the duration of a single MoneyMoney session. This is a SEC review point — see Open Questions §1. A module-local that exists only in memory during a Lua chunk's lifetime is arguably acceptable under SEC-03 wording ("never written to `LocalStorage`, never logged, never echoed"), but it widens the in-memory exposure window from "during InitializeSession2 only" to "for the lifetime of the MoneyMoney process."

  b. **Skip silent re-mint entirely; return `error.token_revoked` immediately on post-mint 401.** Trades the "silent re-mint" affordance for a clearer security posture. The user sees a German error, manually triggers Aktualisieren which calls InitializeSession2 (no — `InitializeSession2` is only called at add-account; subsequent refreshes go directly to RefreshAccount). MoneyMoney's behavior on `error.token_revoked` needs verification — see §10.c.

**Recommendation:** Resolve this with Yves before Wave 3. The PLAN should defer the silent-re-mint to **path (a) with explicit ADR-0005 documenting the in-memory exposure window**, OR **path (b) with explicit ADR-0005 documenting that ERR-04 surfaces as a user-visible error**. Both are defensible; the choice affects user UX.

### Pattern 3: Fail-whole-refresh invariant

**What:** Every error inside RefreshAccount returns the error string immediately. The `since` parameter is NEVER mutated. Partial transactions are NEVER returned alongside an error.

**When to use:** Every step in the 16-step pipeline (Phase 4 entry.lua L139-435).

**Example:** Phase 4 already implements this — `fetch_err`, `state_err`, `fin_err` all early-return. Phase 5's contribution is the **gating spec** that proves it holds across the new retry paths.

### Anti-Patterns to Avoid

- **Recursive retry**: `function get_with_retry(...) ... return get_with_retry(...) end` blows the Lua call stack at ~200 levels deep. Use iterative `for attempt = 1, MAX_ATTEMPTS do`.
- **Retrying POST /token**: Tempting (5xx on OAuth?), but a bad-assertion grant returns 400 (not 5xx). Only retry token-mint on infrastructure 5xx — the assertion itself is idempotent, so retry is safe.
- **Logging the response body during retry**: Body may contain a token (post-mint 401 retry's failed response is a JSON error doc; safe). But future Zettle changes could surface tokens in error bodies. Stay disciplined: log status code only.
- **Silent error swallowing in fallback**: If `MM.sleep` errors (unlikely but possible on a future MoneyMoney version), wrap it in pcall and fall through to no-backoff retry rather than aborting RefreshAccount with a Lua error.
- **Returning partial transactions on error**: VIOLATES ERR-06. Always return `(nil, err)` from intermediate steps; aggregator collects results only if `err == nil` at every step.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sleep / delay | Busy-wait `while os.clock() < t do end` loop | `MM.sleep(seconds)` | Documented sandbox primitive; CPU-friendly; mock already exists at `spec/helpers/mm_mocks.lua:233` |
| HTTP-date parsing for `Retry-After` | RFC 7231 §7.1.3 date parser | `tonumber()` with integer-only contract + ADR-0005 documenting the limitation | Zettle has never been observed to send HTTP-date `Retry-After`; ~80 LoC of date parsing for a hypothetical case is bad ROI |
| Exponential backoff with jitter | Random jitter via `MM.random(n)` | Deterministic `{1, 2, 4}` table | Single-client retries don't suffer thundering-herd; jitter only matters at >10 clients. Deterministic durations make Wave 2 specs trivial to assert |
| Network-failure error string from connection-error type | Parsing the error text MM surfaces | The existing empty-body / nil-status path (D-24 case 1) | ADR-0003 Q8 BONUS finding: pcall does NOT catch SSL errors; MM aborts the chunk on SSL failure. For non-SSL failures, MM returns empty body, which already maps to `error.network` via `_infer_status` returning nil |
| Circuit breaker / consecutive-failure counter | LocalStorage entry that disables the account after N failures | Single per-refresh fail-whole; user re-triggers via Aktualisieren | Out of scope per CONTEXT; would surprise users in MoneyMoney UI |
| Custom logger for retry attempts | New `M_log.retry()` function | Existing `M_log.info()` with structured key=value | Logger already covers redaction; one log line per retry is enough |

**Key insight:** The Lua sandbox is intentionally narrow. The temptation is to reach for "what would I use in Node?" — but `MM.sleep`, `MM.time`, `tonumber`, and a `for` loop are the entire toolset, and they're enough. Discipline > novelty.

## Runtime State Inventory

> Phase 5 is purely additive: new branches inside existing functions + 2 new i18n keys. No data migration, no schema changes.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | LocalStorage token cache (Phase 2) — `expires_at` field unchanged. Post-mint 401 silent re-mint may OVERWRITE the cached `access_token` and `expires_at` with fresh values. | Code edit only (M_auth.with_retry → re-uses persist_session). No migration. |
| Live service config | None — no n8n, no Datadog, no external service config | None |
| OS-registered state | None — extension is a single .lua file in MoneyMoney's Extensions folder; no Task Scheduler / launchd / systemd | None |
| Secrets/env vars | None new. Phase-2 contract (api_key NEVER in LocalStorage) preserved. **If §Pattern-2 path (a) is chosen, api_key briefly lives in module-local Lua variable during RefreshAccount lifetime** — document in ADR-0005. | None for path (b); ADR documentation only for path (a) |
| Build artifacts | `dist/paypal-pos.lua` size grows by ~50 LoC (retry loop + with_retry wrapper + 2 i18n keys + 4 error.lua branches). Reproducible-build SHA changes. | Reinstall .lua after Phase 5 ships |

## Common Pitfalls

### Pitfall 1: `Retry-After: -5` causes time travel

**What goes wrong:** Server (or proxy) sends `Retry-After: -5`. `tonumber("-5") = -5`. `MM.sleep(-5)` behavior is undocumented; best case a no-op, worst case a Lua error.
**Why it happens:** Header injection, misconfigured proxy, or a clock-skew-based heuristic on the server side.
**How to avoid:** Clamp parsed value: `if n == nil or n < 0 then return nil end; return math.min(math.floor(n), RATE_LIMIT_CAP)`. See `_parse_retry_after` example above.
**Warning signs:** Spec `http_retry_spec.lua` must explicitly test `Retry-After: -5` and `Retry-After: 99999` cases.

### Pitfall 2: Backoff stack-frame depth (recursive retry)

**What goes wrong:** A recursive `get_with_retry(url) → on_error → get_with_retry(url)` blows Lua's default 200-frame call stack on persistent 5xx storms. Stack overflow aborts RefreshAccount with a Lua error, VIOLATING ERR-05.
**Why it happens:** Recursive retry is the obvious "elegant" implementation.
**How to avoid:** Iterative `for attempt = 1, MAX_ATTEMPTS do ... end` loop. Hard upper bound on attempts.
**Warning signs:** None at compile time; manifest only at runtime under sustained server failure.

### Pitfall 3: Bearer leakage in retry log lines

**What goes wrong:** Naive `M_log.info("retry: " .. url .. " headers=" .. inspect(headers))` leaks `Authorization: Bearer eyJ...` into the log.
**Why it happens:** "Helpful" debugging during retry implementation.
**How to avoid:** Strict log format: `attempt=N/M status=NNN url=URL after_ms=NNNN`. NEVER concatenate the headers table into any log line. The Phase-2 SEC-03 invariant already covers it via `M_log.redact`, but defense-in-depth: don't include `headers` in the format string at all. Extend `spec/log_redaction_spec.lua` to assert no retry log line contains the substring "Bearer ".
**Warning signs:** Audit grep: `grep -n 'M_log.info.*headers' src/*.lua` must return zero matches.

### Pitfall 4: Silent 401 re-mint loop accidentally infinite

**What goes wrong:** `M_auth.with_retry` calls `M_auth.exchange_assertion` which itself 401s, which calls `with_retry` again, recursing.
**Why it happens:** Naive wrapping of every M_auth function in retry semantics.
**How to avoid:** `with_retry` calls `exchange_assertion` DIRECTLY (not through any retry wrapper). The retry is bounded to exactly ONE re-mint per `with_retry` invocation. Token-mint 401 → `error.token_revoked` immediately, no recursion.
**Warning signs:** Spec must assert the captured request count: post-mint 401 retry should produce EXACTLY 3 requests (initial call + 1 re-mint + 1 retry-of-call), not more.

### Pitfall 5: Per-refresh timeout budget exceeded by max retries

**What goes wrong:** Worst case: 5xx on 3 sequential endpoints, each retrying 3 times with 1s+2s+4s backoff = 7s sleeps × 3 endpoints = **21s of sleeps alone**, plus 9 actual HTTP roundtrips (~3-5s combined). Total ~25-30s. CLAUDE.md says "incremental refresh under 30s" — this is the ceiling.
**Why it happens:** Independent retry budgets per endpoint compound.
**How to avoid:** Document the worst-case ceiling in ADR-0005. Phase 5 does NOT need to enforce a global timeout because:
  (a) MM has a per-call timeout (~60s per ADR-0003 + community survey) that catches runaway.
  (b) Sustained 5xx across 3 endpoints is an outage; failing in ~25s with `error.server_busy` is the correct UX.
  (c) 429 single-retry adds at most 60s — if a refresh hits 429 + 5xx combined, MM's per-call timeout catches it.
**Warning signs:** Add a `M_log.info("RefreshAccount total elapsed: " .. (os.time() - start) .. "s")` line at the end so user reports can identify slow refreshes.

### Pitfall 6: `Retry-After` header missing from `resp_headers` table

**What goes wrong:** Some HTTP server frameworks emit headers in lowercase (`retry-after`), some uppercase (`Retry-After`). MoneyMoney's `Connection:request` documentation doesn't specify normalization.
**Why it happens:** Inconsistent server middleware.
**How to avoid:** Check BOTH casings: `resp_headers["Retry-After"] or resp_headers["retry-after"]`. See `_parse_retry_after` example.
**Warning signs:** Q9-class question: a sandbox probe could confirm header-table casing for `Retry-After` specifically; mark as "verify in first 429 observation" rather than block.

### Pitfall 7: `MM.sleep` blocks the entire MoneyMoney UI

**What goes wrong:** `MM.sleep(60)` (rate-limit retry) freezes MoneyMoney's UI for 60 seconds. User clicks "Cancel" — undocumented behavior.
**Why it happens:** Single-threaded sandbox.
**How to avoid:** Cap at 60s for rate-limit (D-63 already does this); cap at 4s for 5xx backoff. Total worst-case freeze per single endpoint: 7s for 5xx (1+2+4), 60s for rate-limit. ADR-0005 documents this UX cost.
**Warning signs:** User reports of "MoneyMoney hangs during PayPal POS refresh" — investigate cap.

### Pitfall 8: Phase-2 `_infer_status` returns 200 for retry-able body shapes

**What goes wrong:** The Zettle API can return `200 OK` with a `{"error":"rate_limit",...}` body (already gated by H-01 in `_infer_status`). But the retry logic must inspect the INFERRED status (429 in that case), not the underlying HTTP status, which we don't have access to. The 429 path must trigger from the inferred status correctly.
**Why it happens:** Risk R-1: MoneyMoney's `Connection:request` doesn't return HTTP status.
**How to avoid:** Phase 5 retry logic operates on the inferred status from `_infer_status(parsed)`. The H-01 mapping of `{"error":"rate_limit"}` → 429 is already correct (`spec/http_spec.lua:174-189`); extend with retry behavior on top.
**Warning signs:** `spec/http_retry_spec.lua` must include a 429-via-inferred-status test (queue `token_rate_limited.json` fixture; assert retry happens).

### Pitfall 9: Token cache eviction during silent re-mint races

**What goes wrong:** Re-mint via `M_auth.exchange_assertion` updates the cache mid-refresh. If a subsequent `with_retry` call within the SAME RefreshAccount reads the cache, it sees the new token — good. But if the re-mint FAILS, we wrote NOTHING to the cache (good, but verify) and the cached entry remains stale.
**Why it happens:** Cache update happens only on successful exchange.
**How to avoid:** The Phase-2 `persist_session` only writes on success. Verify: `M_auth.with_retry`'s re-mint path must call `persist_session(token, profile, client_id)` only after `exchange_assertion` succeeds, otherwise the stale token stays and the next attempt re-uses it (which is correct — we want consistency).
**Warning signs:** Race tests: assert that a failed re-mint does NOT corrupt LocalStorage.zettle.

### Pitfall 10: ADR-0003 Q8 — pcall does NOT catch Connection-level errors

**What goes wrong:** Phase 2's design (and ADR-0003 Q8 bonus finding) explicitly says: `pcall(function() return conn:request(...) end)` does NOT catch SSL handshake failures — MM surfaces them through the Protokoll panel and aborts the Lua chunk. ERR-05 says network failures must produce a German error string and NEVER a Lua error.
**Why it happens:** MM treats certain transport failures as fatal-to-the-chunk events.
**How to avoid:** **Phase 5 cannot fix this for SSL failures.** It can only handle the failures MM surfaces as empty-body / nil-status — which covers DNS failures, connect refused, plain socket timeouts. SSL handshake failures abort the chunk REGARDLESS of pcall (per ADR-0003 Q8). Document this explicitly in ADR-0005 as a known limitation: SSL handshake failures may bypass ERR-05's German-error-string contract and surface in MM's Protokoll instead.
**Warning signs:** Wave 4 spec for ERR-05 must test the cases we CAN handle (empty body simulating network failure) and the ADR must explicitly call out SSL handshake as out-of-scope.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `busted` 2.3.0 + `luacov` 0.16.0 (pinned in Phase 1) |
| Config file | `.busted` + `.luacheckrc` (Phase 1) |
| Quick run command | `busted spec/http_retry_spec.lua spec/refresh_fail_whole_spec.lua` |
| Full suite command | `busted spec/` (currently 335 successes from Phase 4) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ERR-01 | Token-mint `invalid_grant` → LoginFailed | unit | `busted spec/auth_spec.lua -t "ERR-01"` | ❌ Wave 1 — extend existing auth_spec.lua |
| ERR-02 | 5xx → 3 retries with 1s/2s/4s backoff → `error.server_busy` | unit | `busted spec/http_retry_spec.lua -t "5xx retry"` | ❌ Wave 2 — new file |
| ERR-03 | 429 → honor Retry-After (capped 60s) → single retry → `error.rate_limit` | unit | `busted spec/http_retry_spec.lua -t "429 Retry-After"` | ❌ Wave 2 — new file |
| ERR-04 | Post-mint 401 → silent re-mint → `error.token_revoked` on second 401 | integration | `busted spec/auth_spec.lua -t "with_retry"` | ❌ Wave 3 — extend auth_spec.lua |
| ERR-05 | Network failure → `error.network` (NOT Lua error) | unit | `busted spec/refresh_fail_whole_spec.lua -t "network failure"` | ❌ Wave 4 — new file |
| ERR-06 | Mid-pipeline 500 → whole refresh fails → second refresh re-runs from same `since` | integration | `busted spec/refresh_fail_whole_spec.lua -t "fail-whole"` | ❌ Wave 4 — new file |
| SEC-03 (extension) | Retry log lines contain no Bearer substring | unit | `busted spec/log_redaction_spec.lua -t "retry"` | ❌ Wave 4 — extend log_redaction_spec.lua |

### Sampling Rate

- **Per task commit:** `busted spec/http_retry_spec.lua spec/refresh_fail_whole_spec.lua` (~2s)
- **Per wave merge:** `busted spec/` (full suite, ~12s after Phase 4)
- **Phase gate:** Full suite green + `luacheck src/ spec/` clean before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `spec/http_retry_spec.lua` — covers ERR-02, ERR-03 retry behaviors
- [ ] `spec/refresh_fail_whole_spec.lua` — covers ERR-06 gating + ERR-05 network simulation
- [ ] Test fixtures: `spec/fixtures/finance/finance_5xx.json` (empty body simulating 500), `spec/fixtures/finance/finance_429_retry_after.json` (body + headers map with `Retry-After: 5`)
- [ ] `Mocks.push_response` enhancement: accept `headers = { ["Retry-After"] = "5" }` and pass through to the 5-tuple's 5th return value. Currently `Mocks.push_response` accepts `headers` but the mock's `conn:request` returns it as the 5th return value — verify the http.lua extension destructures position 5 correctly.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Existing JWT-bearer assertion grant; D-64 silent re-mint extends auth lifecycle |
| V3 Session Management | yes | Token cache TTL (D-23d, 60s pre-expiry guard); re-mint updates `expires_at` |
| V4 Access Control | no | Read-only client; no authorization decisions |
| V5 Input Validation | yes | `tonumber(Retry-After)` rejects negatives + non-numeric (Pitfall §1); JSON parse already pcall-wrapped (Phase 2) |
| V6 Cryptography | no | TLS verification is MM's responsibility (ADR-0003 Q8); no crypto code in Phase 5 |
| V7 Error Handling & Logging | yes | All errors through `M_errors.from_http_status` (D-69); retry log lines never leak Bearer (D-68 + Pitfall §3) |
| V8 Data Protection | yes | API key never reaches LocalStorage (SEC-03); Phase-5 silent-re-mint design decision (§Pattern-2) affects in-memory exposure |

### Known Threat Patterns for Lua-in-MoneyMoney Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Bearer leakage via retry log lines | Information Disclosure | Strict log format `attempt=N/M status=NNN url=URL after_ms=NNNN`; `M_log.redact` catches anything that slips through (defense-in-depth); SEC-03 spec extension |
| Negative `Retry-After` → `MM.sleep(-5)` undefined behavior | Tampering | Integer-only parse + lower bound (`n < 0 → nil`) + upper bound (`min(n, 60)`) |
| Silent re-mint infinite loop on persistent 401 | Denial of Service (self) | Bounded ONE re-mint per `with_retry` invocation; second 401 → `error.token_revoked` immediately |
| API key in module-local Lua variable (if Path-a chosen) | Information Disclosure | ADR-0005 documents exposure window; consider Path-b (no silent re-mint) to eliminate exposure entirely |
| Recursive retry → stack overflow → Lua error → ERR-05 violation | Denial of Service (self) | Iterative `for` loop, bounded by `MAX_RETRY_ATTEMPTS = 3` |
| Retry on POST /token replays the assertion grant | Repudiation (mild) | Assertion grants are idempotent within their TTL window per OAuth2 spec; replay produces same access_token. Safe. |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-rolled exponential backoff with jitter | Deterministic `{1, 2, 4}` for single-client | Phase 5 design | Single-client retries don't suffer thundering-herd; deterministic backoff makes specs trivial |
| `socket.sleep` from LuaSocket | `MM.sleep` from MoneyMoney sandbox | Forced by sandbox | LuaSocket unavailable per CLAUDE.md; `MM.sleep` is the documented alternative |
| HTTP-date `Retry-After` parsing | Integer-only `tonumber()` + ADR-documented limitation | Phase 5 design | Saves ~80 LoC; Zettle has not been observed to send HTTP-date |
| pcall around `Connection:request` | NO pcall around `conn:request`; only around JSON parse | Phase 2 (ADR-0003 Q8) | pcall doesn't catch SSL errors; MM surfaces them differently. Phase 5 inherits this. |

**Deprecated/outdated:**
- `os.execute("sleep 1")` — even if `os` is exposed (ADR-0003 Q1), it's brittle (cross-platform, returns immediately on Windows) and the sandbox-canonical answer is `MM.sleep`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `MM.sleep(seconds)` accepts integer seconds and blocks for at least that duration on MM ≥ 2.4.72 | §1, §Pattern-1 | If `MM.sleep` errors or is no-op on a future MM version, backoff degenerates to retry-without-backoff — ERR-02 may exceed 30s budget. Mitigation: Q9 probe (optional, low priority); pcall-wrap `MM.sleep` and fall through on error |
| A2 | `conn:request` returns `Retry-After` header in position 5 of the 5-tuple under key `Retry-After` or `retry-after` | §4.b, Pitfall §6 | If MM normalizes header casing (e.g. all lowercase), our `Retry-After` lookup misses and we use the 30s default — degraded but safe. Verify on first live 429 observation |
| A3 | Zettle returns `Retry-After` as integer seconds (not HTTP-date) | §2 | If Zettle sends HTTP-date format, our `tonumber()` returns nil → 30s default — degraded but safe. ADR-0005 documents the limitation |
| A4 | A successful `exchange_assertion` re-mint within the same RefreshAccount produces a token usable by subsequent calls | §Pattern-2, Pitfall §9 | If token activation is async on Zettle's side (unlikely; observed sub-second in Phase 2), retry-of-call after re-mint may also 401 → `error.token_revoked` — fail-safe |
| A5 | The api_key cannot be made available to `with_retry` without violating SEC-03 (i.e., Pattern-2 path (a) is the only path that enables true silent re-mint) | §Pattern-2 Open-Question | If a cleaner path exists (e.g., MM passes credentials to RefreshAccount on retry — verify in API docs), we should use it. Triggers redesign of with_retry |
| A6 | MM's per-call timeout is ~60s (no exact spec from MoneyMoney docs) | Pitfall §5 | If timeout is shorter (e.g., 30s), our 21s worst-case from 3-endpoint 5xx storms could cut close. Mitigation: ADR-0005 documents the bound and we monitor real-world reports |
| A7 | The German wording "Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen" is clear to a non-technical merchant | §7 | If wording is unclear, loop-lektor pass produces alternatives during PLAN review; no code change |
| A8 | `error.server_busy` (NEW key) is distinct from `error.network` because 5xx-exhausted is a different actionable signal than DNS failure | §6 | If users find the distinction noise rather than signal, consolidate to `error.network` with a status code — trivial late refactor |

## Open Questions

1. **§Pattern-2 silent re-mint security trade-off** — caching api_key in module-local Lua variable (Path-a) vs returning `error.token_revoked` immediately on post-mint 401 (Path-b).
   - What we know: D-64 says "silent re-mint"; SEC-03 says api_key never in LocalStorage; api_key is only present during InitializeSession2.
   - What's unclear: whether "module-local Lua variable" counts as a SEC-03 violation; whether MoneyMoney re-invokes InitializeSession2 on `error.token_revoked` (or just shows the error and waits for user action).
   - Recommendation: ADR-0005 documents both paths. Yves chooses during PLAN review. Default to Path-b (no silent re-mint, surface error immediately) for maximum security posture; ERR-04's "silent re-mint" intent is preserved through ONE retry against the cached bearer (no re-mint), and only second-401 surfaces token_revoked. The "silence" of D-64 may be re-interpretable as "don't return LoginFailed" rather than "actually re-mint the token."

2. **§4.b Header position in `conn:request` 5-tuple under MM ≥ 2.4.72** — the documented signature is `(content, charset, mimeType, filename, headers)`. We must confirm position-5 is a Lua table keyed by header name.
   - What we know: ADR-0003 Q8 confirmed `conn:request` returns 5 values; existing `_infer_status` reads only `content` (position 1).
   - What's unclear: whether `resp_headers` table uses canonical-case keys or lowercase keys (Pitfall §6).
   - Recommendation: Wave 2 implementation checks BOTH casings (`resp_headers["Retry-After"] or resp_headers["retry-after"]`); spec tests both. No probe required.

3. **§Pitfall-10 SSL handshake failures bypass ERR-05** — per ADR-0003 Q8 bonus, MM aborts the Lua chunk on SSL failures and pcall does not catch them.
   - What we know: ADR-0003 documents this for `expired.badssl.com`; we cannot intercept the abort.
   - What's unclear: whether this also applies to MITM-detected cert mismatches mid-session, or just initial handshake.
   - Recommendation: ADR-0005 explicitly carves this out — ERR-05 covers DNS, connect-refused, plain socket timeouts; SSL handshake failures are documented as out-of-scope and surface in MoneyMoney's Protokoll panel.

4. **Q9 sandbox probe priority** — CONTEXT marks Q9 as a Yves blocker, but MM.sleep is documented in the WebBanking API.
   - What we know: WebBanking API docs confirm `MM.sleep(seconds)` exists.
   - What's unclear: whether MM ≥ 2.4.72 behaves correctly with integer seconds (vs accidentally requiring milliseconds), and whether `MM.sleep` is counted against the per-call timeout.
   - Recommendation: **Demote Q9 from blocker to nice-to-have**. Plan 05-01 (Wave 0) can be the optional probe (3 lines added to `tools/probe.lua`); Wave 2-4 proceed in parallel since `MM.sleep` is mocked as no-op in tests and documented in the live API. ADR-0005 marks A1 as verified-via-docs with the probe as confirmation.

## Environment Availability

> No external dependencies. Phase 5 uses only `MM.sleep`, `tonumber`, and existing module surface. CI changes: none.

## Section-by-Focus-Area Detail

### §1. `MM.os.sleep` / `MM.sleep` availability — Q9 partially resolved

**Finding:** The correct API name is **`MM.sleep(seconds)`**, NOT `MM.os.sleep(seconds)`. The CONTEXT D-67 and Q9 row incorrectly named it `MM.os.sleep`.

**Evidence:**
- MoneyMoney WebBanking API docs (`https://moneymoney.app/api/webbanking/`) document `MM.sleep(seconds)` under "MM.*" helpers with the German description "Unterbricht die Ausführung des Skripts für ein paar Sekunden". [VERIFIED: WebFetch of moneymoney.app/api/webbanking/, 2026-06-21]
- The test harness at `spec/helpers/mm_mocks.lua:233` already stubs `_G.MM.sleep = function(s) end` as a no-op for tests. [VERIFIED: file read]
- `gsd-tools query classify-confidence --provider webfetch --verified` → HIGH for the API existence; MEDIUM for the precise integer-seconds contract (probe could verify but is not required to proceed).

**CI test mock shape:** Already correct at `mm_mocks.lua:233`. NO CHANGE NEEDED for Wave 0. Recommend Wave 0 add a self-asserting test:
```lua
it("MM.sleep is stubbed as no-op (Phase 5 invariant)", function()
  local t0 = os.clock()
  MM.sleep(2)
  assert.is_true(os.clock() - t0 < 0.1, "mock MM.sleep must NOT actually block")
end)
```

**Plan impact:** Q9 is **demoted from Yves-blocker to optional confirmation**. ADR-0005 cites the API docs as authoritative. Plan 05-01 (Wave 0) becomes "i18n keys + ADR-0005 + optional MM.sleep probe" — not a blocker for downstream waves.

### §2. `Retry-After` header parsing — integer-only contract

**Finding:** RFC 7231 §7.1.3 defines `Retry-After` as EITHER:
  a. `delta-seconds`: a non-negative decimal integer (e.g., `Retry-After: 120`)
  b. `HTTP-date`: an RFC 7231 §7.1.1.1 date (e.g., `Retry-After: Fri, 31 Dec 2999 23:59:59 GMT`)

**Recommendation:** Implement **integer-only** parsing. Reject negatives (clamp to nil → use default 30s). Cap at 60s upper bound (D-63).

**Rationale:**
- Zettle / iZettle API documentation does NOT specify which format is used. [CITED: github.com/iZettle/api-documentation/blob/master/authorization.md]
- Practical observation: cloud API providers (Stripe, AWS, GitHub) universally use integer seconds. HTTP-date is rare. [ASSUMED: based on training-data API survey; verifies on first 429 observation]
- HTTP-date parsing requires ~80 LoC of date format handling for a code path that may never execute. Bad ROI.

**Fail-safe behavior:**
- HTTP-date → `tonumber()` returns nil → fall through to default 30s → retry once → if still 429, return `error.rate_limit`. Degraded but safe.
- Negative integer → `n < 0` guard → nil → default 30s. Safe.
- Missing header → nil → default 30s. Safe.
- > 60s integer → `math.min(n, 60)` → 60s cap. Safe.

**Code (already in §Pattern-1 example):**
```lua
local function _parse_retry_after(resp_headers)
  if type(resp_headers) ~= "table" then return nil end
  local ra = resp_headers["Retry-After"] or resp_headers["retry-after"]
  if ra == nil then return nil end
  local n = tonumber(ra)
  if n == nil or n < 0 then return nil end
  return math.min(math.floor(n), 60)
end
```

**ADR-0005 explicitly documents:** "Integer-only `Retry-After` parsing. HTTP-date format falls through to the 30s default. Verified safe because (a) Zettle observation matches integer format, (b) the fallback is a single 30s sleep which respects the per-call timeout."

### §3. Lua-side backoff implementations in the MoneyMoney sandbox — community survey

**Finding:** No surveyed MoneyMoney extension implements retry-with-backoff for 5xx. They all "fail fast on first error" — typical for read-only banking-data extensions where partial results are unacceptable.

**Surveyed extensions:**
- `jgoldhammer/moneymoney-payback` (`payback.lua`) — no retry; fails on first HTTP error.
- `teal-bauer/moneymoney-ext-trading212` (`Trading212.lua`) — no retry; surfaces the body as the error message.
- `phillipoertel/moneymoney-extensions` — no retry observed in spot-check.
- `gharlan/moneymoney-shoop` (`Shoop.lua`) — no retry.

[CITED: github.com search for "moneymoney" + "MM.sleep" + retry — no production extensions found using MM.sleep for backoff]

**Implication:** Phase 5 is implementing a pattern that doesn't exist in the community yet. This is fine — the extension's "30-day delta under 30s" performance budget (CLAUDE.md) creates pressure to retry rather than re-trigger the whole 30-day-window refresh.

**Pitfall it surfaces:** `Connection:request`'s per-call timeout behavior under sustained server failure is undocumented in the community corpus. The 30s/60s caps in our design are conservative guesses based on the per-call timeout estimate from ADR-0003. Verify on first observation (§Pitfall-5 warning sign).

### §4. `Connection:request` Lua-error vs HTTP-error surface matrix

#### §4.a Network failure types

| Failure Type | Surfaces As | Pcall Catches? | Phase 5 Handles? |
|--------------|-------------|----------------|------------------|
| DNS resolution failure | `conn:request` returns empty body (`raw = ""`); `_infer_status` returns `nil` | N/A (not raised) | Yes — D-24 case 1 (nil status) → `error.network` |
| Connect-refused | `conn:request` returns empty body; nil status | N/A (not raised) | Yes — same path as DNS |
| Socket timeout (read or connect) | `conn:request` returns empty body; nil status | N/A (not raised) | Yes — same path |
| TLS handshake failure (cert invalid, expired, MITM) | **MM aborts the Lua chunk; pcall does NOT catch** | **No** | **No — known limitation; ADR-0005 documents** |
| HTTP 5xx with body | `conn:request` returns body; `_infer_status` reads `parsed.error`; falls through to non-error status (200) — caller needs status from response | N/A | Phase 5 must surface status via the new headers path OR by parsing the body shape — discussed in §4.b |
| HTTP 429 with `{"error":"rate_limit"}` body | `_infer_status` already returns 429 (Phase 2 H-01 fix) | N/A | Yes — retry triggers from inferred status |
| HTTP 401 with `{"error":"invalid_client"}` | `_infer_status` returns 401 | N/A | Yes — `M_auth.with_retry` triggers on LoginFailed return from M_errors |

**Conclusion:** ERR-05 covers DNS, connect-refused, socket timeout. SSL handshake failures are a documented limitation (Pitfall §10). The German `error.network` string already correctly handles all the cases we can intercept.

**ERR-05 regression test:** Queue `Mocks.push_response({ content = "" })` to simulate network failure. The Phase-2 code path already handles this — Phase 5 adds the explicit spec assertion.

#### §4.b Capturing HTTP status from the 5-tuple

**Current state (Phase 2):** `M_http.get_json` discards positions 2-5 of the 5-tuple via `local raw, charset, mime, filename, resp_headers = conn:request(...)` then immediately reassigns `raw = raw or ""`. The `resp_headers` table is captured but never used.

**Phase 5 requirement:** For 429/5xx retry, we need:
  - Status code (for 5xx detection — but we don't have it; we have `_infer_status` from body only)
  - `Retry-After` header from `resp_headers`

**Design decision:** **Use the body-shape `_infer_status` for retry triggering.** The Phase 2 H-01 fix already maps `{"error":"rate_limit"}` → 429. For 5xx, we need a NEW heuristic: empty body + non-nil mime indicating server error → assume 5xx.

**Alternative (cleaner):** If MoneyMoney's `resp_headers` includes a `status` key (some HTTP libraries do this), use it directly. **Verify in Wave 2 implementation** — probe the actual table shape with `M_log.debug("resp_headers keys: " .. table.concat(keys, ","))` on first call. If `status` is present, use it; otherwise stick with body inference.

**Practical 5xx detection:** Zettle sends 5xx with JSON body `{"error":"server_error",...}` (per OAuth2 spec for OAuth endpoints) or HTML/plain body for non-OAuth. Heuristic: extend `_infer_status` to detect:
```lua
-- Extended _infer_status:
if parsed.error == "server_error" or parsed.error == "temporarily_unavailable" then
  return 500  -- conservative; trigger retry
end
```
For non-OAuth endpoints (Purchase, Finance APIs), 5xx responses may not have JSON body. The Phase-2 empty-body → nil-status path catches them but maps to `error.network` not retry. **Phase 5 must extend** to retry on nil-status WITH a body-length check — if the body is empty AND the URL is a Zettle resource endpoint, retry as if 5xx. ADR-0005 documents this heuristic.

**Concrete code path:**
```lua
-- Inside the retry loop:
local raw, _, _, _, resp_headers = conn:request(method, url, body, contentType, h)
local should_retry_5xx = false
if raw == nil or #raw == 0 then
  -- Empty body: could be network failure OR a 5xx with no body
  -- Retry on attempt < 3; if still empty on final attempt, surface as error.network (preserves Phase 2 ERR-05 path)
  should_retry_5xx = (attempt < MAX_RETRY_ATTEMPTS)
end
local parsed = pcall_parse_json(raw)
local status = M_http._infer_status(parsed or {})
if status == 429 then ... 429 path
elseif status >= 500 then ... 5xx path
elseif should_retry_5xx then ... treat as 5xx
else return parsed, status, raw
```

### §5. Fail-whole-refresh invariant audit of Phase 4's 16-step pipeline

**Audit:** `src/entry.lua RefreshAccount` (L139-435):

| Step | Description | Error-Emit Point | In-Flight State at Boundary |
|------|-------------|------------------|----------------------------|
| 1 | orgUuid guard | L143-144 | Nothing built yet — clean return |
| 3 | since clamp | (cannot error) | — |
| 2 | cached_token | L166-168 | Nothing built — clean return |
| 4 | M_purchases.fetch_all | L174-175 | Nothing built yet besides bearer (local var) — clean return |
| 5 | purchases_by_uuid index | (pure-Lua loop; cannot error) | `purchases_by_uuid` lives in local scope — discarded on early return |
| 6 | payments_by_uuid index | (pure-Lua loop) | `payments_by_uuid` local — discarded |
| 7 | M_finance.fetch_account_state | L240 | `account_state` not assigned; `purchases_by_uuid` + `payments_by_uuid` discarded on return |
| 8 | M_finance.fetch_all | L244 | Same — early return discards all locals |
| 9 | parse + bucket | (pure-Lua; cannot error) | `fin_payments/_fees/_payouts` local |
| 10 | sort payouts | (pure-Lua; cannot error) | — |
| 11 | fin_payments_by_uuid index | (pure-Lua) | — |
| 12 | map purchases → transactions | (pure-Lua) | `transactions` local |
| 13 | SALE-03 promotion sweep | (pure-Lua) | mutates `transactions` in-place — but only if reached |
| 14 | fee clustering | (pure-Lua) | mutates `transactions` |
| 15 | payout mapping | (pure-Lua) | mutates `transactions` |
| 16 | return `{balance, pendingBalance, transactions}` | (cannot error) | RESULT — only reached if no prior step returned an error |

**Conclusion:** The Phase-4 design is **structurally correct for ERR-06**. Early returns at steps 1, 2, 4, 7, 8 discard ALL in-flight state because Lua's lexical scoping cleans up locals automatically. The `purchases_by_uuid`, `payments_by_uuid`, `fees_by_date`, `transactions` tables are all local variables; they cease to exist on return.

**The risk** is that someone in Phase 5 adds a `_G.something = transactions` or `LocalStorage.partial_data = …` line that leaks state across the boundary. **The gating spec must explicitly check that** `LocalStorage` is unchanged after a failed refresh (besides the legitimate `zettle.<orgUuid>` cache update from a successful re-mint).

**Spec assertion (Wave 4):**
```lua
it("ERR-06: failed mid-refresh does not leak state into LocalStorage", function()
  -- Setup: valid token in cache, queue purchase success + finance 500
  ...
  local result = RefreshAccount(account, since)
  -- The cached token entry may have updated obtained_at if a re-mint happened
  -- (but in this test, no re-mint was triggered — first 401 wasn't queued).
  -- Assert: no NEW top-level keys in LocalStorage besides "zettle" and "zettle:<orgUuid>"
  local allowed_keys = { zettle = true, ["zettle:" .. orgUuid] = true }
  for k, _ in pairs(LocalStorage) do
    assert.is_true(allowed_keys[k], "unexpected LocalStorage key: " .. k)
  end
  -- Assert: no transactions returned to MoneyMoney
  assert.is_string(result, "must return error string, not table")
end)
```

### §6. i18n keys audit — D-69's 4 keys against `src/i18n.lua`

**Existing keys (verified at `src/i18n.lua:40-43`):**
- ✅ `error.invalid_grant` — "Anmeldung fehlgeschlagen: API-Key wurde abgelehnt."
- ✅ `error.network` — "Netzwerkfehler: %s"
- ✅ `error.rate_limit` — "Anfragelimit erreicht — bitte später erneut versuchen."

**Missing keys (Phase 5 must ADD):**
- ❌ `error.server_busy` — needs German + English
- ❌ `error.token_revoked` — needs German + English

**Proposed strings (de):**
```lua
["error.server_busy"]   = "PayPal-POS-Server zurzeit nicht erreichbar — bitte später erneut versuchen.",
["error.token_revoked"] = "Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen.",
```

**Proposed strings (en parity, per I18N-02):**
```lua
["error.server_busy"]   = "PayPal POS server unavailable — please retry later.",
["error.token_revoked"] = "Session lost — please re-enter the API key in MoneyMoney.",
```

**Total i18n.lua delta:** +2 keys × 2 locales = 4 lines.

### §7. `error.token_revoked` German wording — alternatives for loop-lektor

The CONTEXT recommendation: **"Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen"** (clear, action-oriented, identifies what to do).

**Alternatives for loop-lektor:**

  a. **"Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen"** *(CONTEXT recommendation)* — friendly, conversational, action-oriented.

  b. **"PayPal-POS-Zugriff verloren: API-Key wurde widerrufen. Bitte erneut hinterlegen."** — more technical; explains the cause ("widerrufen"). May confuse non-technical users.

  c. **"Sitzung abgelaufen — bitte API-Key neu im Kontodialog eintragen."** — uses "Sitzung" (session) which is familiar from web apps; specifies where to enter the key.

**Recommendation:** Lock (a) for v1.0.0. (b) is too technical for the target merchant. (c) is plausible but adds "Kontodialog" which assumes MoneyMoney terminology the user may not know. loop-lektor pass during PLAN review can revisit.

### §8. D-66 ERR-06 fail-whole regression test pattern — exact mock sequencing

**Test:** `spec/refresh_fail_whole_spec.lua` (NEW, Wave 4).

**Sequence:**

```lua
it("ERR-06: 500 mid-refresh aborts whole refresh; second refresh re-runs from same since", function()
  -- Setup: valid token in cache
  local orgUuid = "org-fail-whole"
  seed_token(orgUuid)
  local since = os.time() - (30 * 86400)  -- 30 days ago

  -- Queue 1: purchase fetch succeeds
  Mocks.push_response({ content = Fixtures.load("purchases/single_page_3_purchases") })

  -- Queue 2: finance liquid balance returns 500 (empty body simulates server error)
  -- Phase-5 extension: empty body + attempt < 3 → retry. On final exhaustion → error.server_busy.
  -- For this test, queue 3 empty bodies so all 3 attempts exhaust:
  Mocks.push_response({ content = "" })  -- attempt 1
  Mocks.push_response({ content = "" })  -- attempt 2 (after 1s sleep)
  Mocks.push_response({ content = "" })  -- attempt 3 (after 2s sleep, total 3s)

  local account = { accountNumber = orgUuid, currency = "EUR", balance = 0 }
  local result1 = RefreshAccount(account, since)

  -- Assert (a): German error string returned (NOT a table)
  assert.equals(M_i18n.t("error.server_busy"), result1)

  -- Assert (b): Captured requests show the purchase call happened
  local req_urls = {}
  for _, r in ipairs(Mocks._captured_requests) do req_urls[#req_urls + 1] = r.url end
  local saw_purchase = false
  for _, u in ipairs(req_urls) do
    if u:find("purchase.izettle.com/purchases/v2", 1, true) then saw_purchase = true end
  end
  assert.is_true(saw_purchase, "purchase fetch must have occurred")

  -- Assert (c): No transactions returned (because result1 is a string, not a table)
  assert.is_string(result1)  -- redundant with (a) but explicit

  -- Assert (d): Second refresh with SAME since re-runs from scratch and succeeds.
  -- Queue full 4-response success set (purchase + liquid + preliminary + transactions):
  Mocks.push_response({ content = Fixtures.load("purchases/single_page_3_purchases") })
  Mocks.push_response({ content = Fixtures.load("finance/finance_balance_liquid") })
  Mocks.push_response({ content = Fixtures.load("finance/finance_balance_preliminary") })
  Mocks.push_response({ content = Fixtures.load("finance/finance_empty") })

  local result2 = RefreshAccount(account, since)  -- SAME since as result1
  assert.is_table(result2, "second refresh must return table on success")
  assert.is_table(result2.transactions)
  assert.is_true(#result2.transactions > 0, "second refresh must emit transactions")
end)
```

**Critical detail (§5 audit):** Because `since` is passed BY VALUE (Lua semantics for integers), the second call uses the same integer; MoneyMoney's `since` watermark in the real harness is not advanced because RefreshAccount didn't return a result table on the first call. The test simulates this by passing `since` directly.

### §9. D-62 retry sleep durations safety margin

**Worst case timing analysis:**

| Phase | Duration | Cumulative |
|-------|----------|-----------|
| Initial HTTP call | ~500ms-2s | 0-2s |
| Backoff 1 | 1s sleep | 1-3s |
| Retry 1 | ~500ms-2s | 1.5-5s |
| Backoff 2 | 2s sleep | 3.5-7s |
| Retry 2 | ~500ms-2s | 4-9s |
| **Worst per-endpoint** | | **~9s** |
| 3 endpoints (purchase + finance state + finance transactions) | 3× ~9s | **~27s** |

**MoneyMoney per-call timeout estimate:** ~30-60s [ASSUMED based on ADR-0003 Q1 + community survey; not explicitly documented].

**Verdict:** 27s worst-case for 3-endpoint 5xx storm fits within a 30s budget but is uncomfortably close. **However:** the realistic case is 5xx on ONE endpoint, not all three sequentially. Single-endpoint worst case is ~9s. Safe.

**Mitigation if budget breached:** Plan 5xx retry as 2 attempts (1s+2s = 3s) instead of 3 (1s+2s+4s = 7s). Saves 4s per endpoint = 12s across the pipeline. ADR-0005 documents the trade-off.

**Recommendation:** Stick with `{1, 2, 4}` for v1.0.0 per D-62. Monitor real-world reports; tune in v1.0.x if needed.

### §10. Pitfalls and risk register

See `## Common Pitfalls` section above. All 10 enumerated:
- §a/Pitfall-2: backoff stack-frame depth (iterative loop)
- §b/Pitfall-3: Bearer leakage in retry log lines (strict log format)
- §c/Pitfall-4: silent 401 re-mint infinite loop (bounded ONE re-mint)
- §d/Pitfall-1: `Retry-After: -5` time travel (clamp negatives)
- §e/Pitfall-5: per-refresh timeout budget (worst-case ~27s ≤ 30s budget)
- §f/Pitfall-6: `Retry-After` header casing (check both)
- §g/Pitfall-7: `MM.sleep` blocks UI (cap at 60s)
- §h/Pitfall-8: `_infer_status` 200 for retry-able body (H-01 already handles 429)
- §i/Pitfall-9: cache race during silent re-mint (persist only on success)
- §j/Pitfall-10: SSL handshake bypasses ERR-05 (ADR-0005 documents as out-of-scope)

## Code Examples

### Verified pattern: existing fail-fast error routing (Phase 2, src/errors.lua L15-43)

```lua
-- Source: src/errors.lua (Phase 2, D-24 dispatch)
M_errors.from_http_status = function(status, body)
  if status == nil then return M_i18n.t("error.network", "—") end
  if status >= 200 and status <= 299 then return nil end
  if status == 400 or status == 401 or status == 403 then return LoginFailed end
  if status == 429 then return M_i18n.t("error.rate_limit") end
  if status >= 500 and status <= 599 then return M_i18n.t("error.network", tostring(status)) end
  return M_i18n.t("error.network", tostring(status))
end
```

**Phase 5 extension (D-69):** Insert before the 5xx branch:
```lua
if status == 429 then return M_i18n.t("error.rate_limit") end
-- NEW: 5xx exhausted retries
if status == 599 then return M_i18n.t("error.server_busy") end  -- sentinel from retry loop
-- NEW: post-mint 401 retry exhausted
if status == 498 then return M_i18n.t("error.token_revoked") end  -- sentinel from with_retry
-- ... existing 5xx and catch-all
```

**Alternative (cleaner):** Don't use HTTP status sentinels (498, 599 are non-standard). Instead, `M_http.get_json` and `M_auth.with_retry` return the i18n key directly when their retry exhausts:
```lua
-- In M_http.get_json, after retry loop exhausts on 5xx:
return nil, nil, raw, M_i18n.t("error.server_busy")  -- 4-tuple with explicit error
```
Callers check the 4th return value first; if non-nil, propagate as the error. Cleaner separation; requires updating all 7 call sites.

**Recommendation:** Stick with the existing `M_errors.from_http_status` dispatch but use a sentinel mechanism — pass a special status integer (598/599 for server_busy, 498 for token_revoked) from the retry layer. Encapsulates the new error mappings in M_errors without changing the function signature. Document the sentinels as Phase-5-internal.

### Verified pattern: existing pcall around JSON parse only (Phase 2, src/http.lua L107-109)

```lua
-- Source: src/http.lua (Phase 2)
-- pcall is ONLY used around JSON parse (per Pitfall 3 + ADR-0003 Q8 bonus).
local ok, parsed = pcall(function()
  return JSON(raw):dictionary()
end)
if not ok or type(parsed) ~= "table" then
  return nil, nil, raw
end
```

**Phase 5 preserves this discipline** — the retry loop adds NO new pcalls; it relies on the existing empty-body → nil-status path for network failures.

## Sources

### Primary (HIGH confidence)
- MoneyMoney WebBanking API — `https://moneymoney.app/api/webbanking/` — confirmed `MM.sleep(seconds)` exists [VERIFIED: WebFetch 2026-06-21]
- ADR-0003 sandbox probe results — Q1, Q4, Q5, Q7, Q8 resolved on MoneyMoney 2.4.72 / macOS 26.4.1 ARM — `docs/adr/0003-sandbox-probe-results.md` [VERIFIED: file read]
- `src/http.lua`, `src/auth.lua`, `src/errors.lua`, `src/entry.lua`, `src/i18n.lua` — Phase 2 + Phase 4 codebase [VERIFIED: file read]
- `spec/helpers/mm_mocks.lua` L233 — `MM.sleep` mocked as no-op [VERIFIED: file read]
- `spec/errors_spec.lua`, `spec/auth_spec.lua`, `spec/http_spec.lua`, `spec/refresh_idempotency_spec.lua` — existing spec infrastructure [VERIFIED: file read]
- `iZettle/api-documentation/authorization.md` — OAuth2 JWT-bearer assertion grant, 7200s TTL, no refresh-token rotation [CITED: github.com/iZettle/api-documentation]

### Secondary (MEDIUM confidence)
- Community MoneyMoney extension survey (Trading 212, Payback, Shoop, etc.) — no production retry-with-backoff pattern observed [CITED: WebSearch + spot-checks]
- RFC 7231 §7.1.3 `Retry-After` header semantics — integer-seconds vs HTTP-date [CITED: IETF docs]
- AWS Prescriptive Guidance: Retry-with-backoff pattern — exponential backoff base-2 with single-client deterministic durations is acceptable [CITED: docs.aws.amazon.com]

### Tertiary (LOW confidence)
- ASSUMED: MoneyMoney per-call timeout is ~30-60s — not explicitly documented; inferred from ADR-0003 + Phase 2 observations [ASSUMED]
- ASSUMED: Zettle returns `Retry-After` as integer seconds (not HTTP-date) — based on training-data cloud-API survey [ASSUMED — verify on first 429]
- ASSUMED: `conn:request` 5-tuple's 5th return value is keyed by canonical header name — needs Wave 2 verification [ASSUMED]

## Metadata

**Confidence breakdown:**
- D-61..D-69 implementation paths: HIGH — every hook lands on existing module seams
- `MM.sleep` capability: HIGH — confirmed via official API docs + existing mock
- `Retry-After` parsing strategy: HIGH for integer-only; MEDIUM for the header-casing question (verify in Wave 2)
- §Pattern-2 silent re-mint design: MEDIUM — the api_key exposure trade-off needs Yves resolution before Wave 3
- Per-call timeout budget headroom: MEDIUM — ~27s worst case is within ~30s estimated budget but close; ADR-0005 documents
- SSL handshake failure bypass of ERR-05: HIGH (it's a known ADR-0003 limitation; ADR-0005 carries it forward)

**Research date:** 2026-06-21
**Valid until:** 2026-07-21 (30 days; MoneyMoney APIs are stable; Zettle/PayPal POS API revisions are rare)

---

*Phase: 05-resilience-error-handling*
*Research completed: 2026-06-21*
