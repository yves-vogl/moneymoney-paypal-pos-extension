# Phase 5: Resilience & Error Handling - Context

**Gathered:** 2026-06-21 (autonomous draft within Yves' full-backlog mandate; every gray area below carries a recommended answer the planner can lock immediately)
**Status:** Ready for planning — no Yves-blockers expected (Phase 5 layers error handling onto existing code; no new API integrations, no new modules, no credential setup, no Pay/Compliance touchpoints beyond what Phase 4's ADR-0004 already covered)

<domain>
## Phase Boundary

Layer adversarial-condition handling onto the Phase 2 + 3 + 4 pipeline so every failure mode — token-mint refusal, mid-refresh token revocation, rate limiting, transient 5xx, network timeouts, partial-pipeline failure — produces a clear German error string returned from `RefreshAccount` / `InitializeSession2`, **never** a Lua error, **never** a partial result, and **never** a silently-advanced `since` watermark. The fail-whole-refresh invariant (already implicit in Phase 3/4) becomes explicit and spec-gated. Retry semantics land at the `M_http` layer so no caller has to know about them. The existing `M_errors.from_http_status` is the central truth source — Phase 5 extends it, never bypasses it.

**In scope:**
- `M_http.get_json` + `M_http.post_form`: retry-with-backoff for 5xx (up to 3 attempts, exponential backoff 1s/2s/4s) and rate-limit honoring (`Retry-After` header up to 60s cap; default 30s when absent)
- `M_auth.cached_token` + `M_auth.exchange_assertion`: silent re-mint on a single post-mint 401, then bubble up second-401 as a non-`LoginFailed` error (ERR-04 — token revoked mid-refresh ≠ bad credentials)
- `M_errors.from_http_status`: extend with `error.rate_limit`, `error.server_busy`, `error.network`, `error.token_revoked` German strings (i18n keys already in `src/i18n.lua` from Phase 2/4; verify all 5 exist and add the missing ones)
- `RefreshAccount` (`src/entry.lua`): wrap each pipeline step (purchases fetch, finance fetch, finance balance fetch, mapping pass, promotion pass) in the existing fail-fast pattern; explicit acceptance criterion that ANY error returns immediately and the `since` parameter is byte-identically passed to MoneyMoney on the next call
- `InitializeSession2` (`src/entry.lua`): the profile-ping uses the same retry semantics so a transient 5xx at add-account time doesn't bounce a legitimate API key
- Sleep mechanism for backoff: use `MM.os.sleep(seconds)` if it exists in the MoneyMoney sandbox (Q9-class probe required — see Yves-blockers below); fall back to a busy-wait pattern that respects MoneyMoney's per-call timeout budget (under 30s total per refresh per CLAUDE.md constraint)
- Logging: every retry attempt emits an INFO log with attempt-count + status-code; the Bearer is NEVER logged (SEC-03 already gates this — extend the gating spec to cover the new retry log lines)
- Spec: `spec/errors_spec.lua` (extend) + `spec/http_retry_spec.lua` (new) + `spec/refresh_fail_whole_spec.lua` (new — ERR-06 gate)

**Out of scope:**
- Persistent error-state across refreshes (e.g., circuit-breaker that disables the account after N consecutive failures) — too aggressive for v1.0.0, would surprise users; revisit if real users report support burden
- User-configurable retry counts / backoff curves — out of scope for v1.0.0
- Notification mechanism to surface errors outside MoneyMoney's normal account-row UI — not available in the sandbox
- Automatic API-key rotation on token-revoked — user must manually regenerate per ADR-0001 and CLAUDE.md self-hosted-app contract
- Health-check endpoint / liveness probe — not relevant for a read-only sync extension
- Deferred items remain deferred: S-03, S-08..S-10, S-12, I-01, I-02 from Phase-4's `04-07-FIX-SUMMARY.md` (Phase 5 may opportunistically pick up I-02 since it's a one-line scope-specific German error in `M_errors`)

</domain>

<decisions>
## Implementation Decisions

Numbering continues from Phase 4 (D-46..D-60). Phase 5 = D-61..D-69.

- **D-61** ERR-01 invalid_grant ⇒ `LoginFailed`. Already partially in place in Phase 2; verify the path is structurally gated (`spec/auth_spec.lua` asserts the `LoginFailed` string return) and extend with an explicit ERR-01 test using the existing `auth_invalid_grant.json` fixture.
- **D-62** ERR-02 5xx retry-with-backoff. Max 3 attempts (1 original + 2 retries). Sleep durations: 1s, 2s, 4s (exponential, base 2). Each attempt logged INFO with `attempt=N/3 status=503`. If all 3 attempts fail, return `error.server_busy` German string.
- **D-63** ERR-03 429 rate-limiting. Honor `Retry-After` header (seconds; integer parse with `tonumber`); cap at 60s to stay within MoneyMoney's per-call timeout budget. Without `Retry-After`, default to 30s sleep then return `error.rate_limit`. Single retry per refresh (no infinite backoff on continuous 429s — that would breach the 30s per-call budget).
- **D-64** ERR-04 post-mint 401. On 401 received from any resource endpoint (Purchase, Finance) after a successful token-mint, perform ONE silent re-mint via `M_auth.exchange_assertion` and retry the failing call. If the retry also 401s, return `error.token_revoked` (NEW i18n key — German "Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen"). Do NOT return `LoginFailed`; that constant is reserved for ERR-01 (`invalid_grant` at mint time).
- **D-65** ERR-05 network failures. Existing Phase-2 pcall wrap around `Connection():request` catches Lua-level errors; verify it covers DNS / TLS / connect-timeout (the three documented failure modes). Returns `error.network` German string. New regression test queues `Mocks.push_response(nil, "ENETDOWN")` and asserts the error string surfaces verbatim.
- **D-66** ERR-06 fail-whole-refresh. The invariant: any error inside RefreshAccount returns immediately. The `since` parameter is NEVER mutated. Phase 4 already follows this implicitly (the `purchases_by_uuid` / `payments_by_uuid` builds happen inside RefreshAccount and disappear on early return). New gating spec: queue a successful purchase fetch, then queue a 500 on finance fetch; assert (a) RefreshAccount returns the German error string, (b) `Mocks._captured_requests` shows the purchase call happened, (c) no transactions are returned to MoneyMoney, (d) a second RefreshAccount call with the SAME `since` re-runs from scratch and (assuming finance now succeeds) emits all transactions.
- **D-67** Sleep mechanism. Two paths under evaluation: (a) `MM.os.sleep(seconds)` if MoneyMoney's sandbox exposes it (Q9 below); (b) busy-wait via `os.clock` loop. Recommendation: use `MM.os.sleep` if Q9 confirms it exists; otherwise document the limitation in ADR-0005 and use a `socket.sleep`-equivalent pure-Lua implementation if it doesn't breach the sandbox. The CI test harness mocks `MM.os.sleep` to be a no-op so tests don't actually wait.
- **D-68** Retry log discipline. Each retry attempt emits exactly ONE INFO log: `M_log.info("HTTP retry: attempt=2/3 status=503 url=https://finance.izettle.com/v2/accounts/liquid/balance after_ms=1000")`. The Bearer is redacted by the existing `M_log.redact` — extend the SEC-03 gating spec to assert the new log lines contain no `Bearer eyJ` substring.
- **D-69** Extend `M_errors.from_http_status` central truth source. Add the new German strings via existing i18n keys (`error.rate_limit`, `error.server_busy`, `error.network`, `error.token_revoked`); the function dispatch table grows by 4 entries. Never bypass — every error path in the codebase routes through this function.

### Claude's Discretion
- Whether the retry logic lives inside `M_http.get_json` (intrusive, breaks the existing thin-wrapper contract) or as a sibling `M_http.get_json_with_retry` that the resilience-aware callers opt into. **Recommendation: extend `get_json` inline** since EVERY caller wants the retry semantics; opting in would be a bug-magnet.
- Whether the 401 silent re-mint lives in `M_http` or in `M_auth`. **Recommendation: in `M_auth.with_retry(bearer, callback)` wrapper** that callers (RefreshAccount + InitializeSession2 profile-ping) wrap their HTTP calls in. Keeps `M_http` agnostic of auth and `M_auth` the single owner of token lifecycle.
- Whether to retry on 429 with `Retry-After` honoring vs always return error.rate_limit immediately. **Recommendation: single retry as documented in D-63** — gives a transient 429 a chance to clear without breaching the per-call budget.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 5 inputs
- `.planning/ROADMAP.md` §"Phase 5: Resilience & Error Handling" — 6 ERR requirements + 6 success criteria
- `.planning/REQUIREMENTS.md` — ERR-01..ERR-06 verbatim
- `.planning/PROJECT.md` §"Non-goals" — no telemetry; no third-party error reporting; read-only contract preserved
- `.planning/STATE.md` §"Current Position" — Phase 4 merged via PR #11 (`74f644c` on main)

### Phase-4 inheritances (still authoritative)
- `D-43` errors routed via `M_errors.from_http_status` in pagination loops (Phase 3)
- `D-45` Bearer never logged (SEC-03)
- `D-49` D-49 Option B fee-fallback (Phase 4) — error paths inside fee classification still surface via `M_errors`
- `D-56` SALE-03 promotion is best-effort; errors during the promotion sweep return the German error string and abort the refresh per the new ERR-06 contract

### MoneyMoney WebBanking API
- `moneymoney.app/api/webbanking/` §`RefreshAccount` return contract — error string vs `{...}` table; the `LoginFailed` constant for ERR-01 specifically
- `moneymoney.app/api/webbanking/` §`MM.os.sleep` — verify in the API docs whether this exists, what its precision is, and whether it counts against the per-call timeout

### Phase-2 / 3 / 4 source files (closest analogs)
- `src/http.lua` — Phase-2 thin wrapper; extends here with retry-with-backoff
- `src/auth.lua` — Phase-2 token cache; extends with `with_retry` wrapper
- `src/errors.lua` — Phase-2 status-code-to-i18n-key dispatch; grows by 4 entries
- `src/entry.lua RefreshAccount` — Phase-4 14-step sequence; each step gets the auth.with_retry wrapper
- `src/i18n.lua` — verify `error.rate_limit`, `error.server_busy`, `error.network` exist; add `error.token_revoked`
- `spec/errors_spec.lua` (Phase 2) — extend with new status-code mappings
- `spec/auth_spec.lua` (Phase 2) — extend ERR-01 LoginFailed assertion
- `spec/http_spec.lua` (Phase 2) — extend with retry + backoff + 429 tests
- `spec/refresh_idempotency_spec.lua` (Phases 3+4) — extend with ERR-06 fail-whole gating cases

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `M_http.get_json(url, headers)` — Phase 2 HTTP transport. Phase 5 extends inline with retry semantics.
- `M_auth.cached_token(orgUuid)` + `M_auth.exchange_assertion(...)` — Phase 2 token cache. Phase 5 adds `M_auth.with_retry(orgUuid, callback)` wrapper that handles the silent re-mint on 401.
- `M_errors.from_http_status(status, body)` — Phase 2 dispatch. Phase 5 adds 4 entries.
- `M_log.redact` + `M_log.info` — Phase 1/2. Phase 5 adds 1 retry log line; redaction covers it byte-identically.
- `MM.os.sleep` — needs sandbox verification (Q9 — see Yves-blockers below if this fails).
- `Mocks.push_response` queue (`spec/helpers/mm_mocks.lua`) — Phase 2; Phase 5 extends with the `nil, error_string` pair queuing for network-failure fixture cases.

### Established Patterns
- Thin-wrapper HTTP, fat-orchestrator entry — Phase 2 contract; Phase 5 preserves.
- Fail-whole-refresh invariant — Phase 4 implicit; Phase 5 makes explicit.
- All errors through `M_errors.from_http_status` — D-43 from Phase 3; Phase 5 extends, never bypasses.
- SEC-03 Bearer redaction — Phase 2; Phase 5 extends gating spec to retry log lines.
- TDD discipline: RED spec before GREEN impl, every wave.

### Integration Points
- `M_http.get_json` is the choke-point — adding retry-with-backoff here propagates to every Phase 2/3/4 caller transparently.
- `M_auth.with_retry` is new — callers in `entry.lua RefreshAccount` (Phase 4 14-step sequence) and `entry.lua InitializeSession2` (Phase 2 profile-ping) wrap their HTTP calls in it.
- `M_errors.from_http_status` is the central truth — every new German error string lives in i18n.lua and is reached only via this function.

</code_context>

<specifics>
## Specific Ideas

- **The fail-whole-refresh invariant (D-66) is the load-bearing acceptance criterion.** Success criterion 6 (ERR-06) gates this. If a 5xx mid-refresh leaks partial transactions to MoneyMoney, the `since` watermark advances and the missing transactions become permanently lost. The gating spec MUST queue a failure mid-pipeline and assert the watermark/dedup contract holds across the failed and retry refreshes.
- **D-67 sleep mechanism is the only Yves-class blocker.** If `MM.os.sleep` doesn't exist in the sandbox (Q9), Phase 5 either uses a busy-wait (CPU spin during backoff — acceptable for 1-4 second windows) or accepts that retry-with-backoff degrades to retry-without-backoff. ADR-0005 documents the choice.
- **ERR-01 + ERR-04 distinction** is documented per D-61 + D-64: `LoginFailed` is reserved for token-mint `invalid_grant` (the user's API key is bad); `error.token_revoked` is for post-mint 401 retry-failed (the token was valid but got revoked mid-refresh). Both surface as German strings to the user but only `LoginFailed` triggers MoneyMoney's "credentials prompt" UI affordance.
- **Coverage stays at 99%+.** Phase 4 landed 100%; Phase 5 adds branches (retry loops) and acceptance branches that genuinely exercise them via fixtures.

</specifics>

<deferred>
## Deferred Ideas

- Persistent circuit-breaker / account-disable on N consecutive failures — Phase 6+ if real users report support burden.
- User-configurable retry curves — out of scope for v1.0.0.
- Health-check / liveness endpoint — not relevant for read-only sync.
- Notification mechanism outside MoneyMoney UI — sandbox prohibits.
- Automatic API-key rotation on token-revoked — ADR-0001 self-hosted-app contract requires manual regen.
- Webhook / push delivery from PayPal POS — Phase 8+ if it ever materialises (Zettle does not currently offer this).

</deferred>

---

## Yves Blockers (autonomous-window pauses)

**One probe required** before locking the retry-with-backoff implementation. Plan 05-01 (Wave 0) will be Q9.

| ID | Item | Type | Recommended | What Yves Needs to Do |
|----|------|------|-------------|------------------------|
| **Q9** | `MM.os.sleep(seconds)` availability in MoneyMoney's Lua sandbox | Sandbox capability probe | Use `MM.os.sleep` if it exists; busy-wait fallback otherwise | Add a 3-line probe to `tools/probe.lua` (Phase 1's tool), reinstall the probe extension in MoneyMoney, observe whether `MM.os.sleep(1)` blocks 1 second or errors. Record in ADR-0003 as Q9. |

Q9 is genuinely orthogonal to the other 5 waves of Phase 5 — they all proceed under the assumption that EITHER mechanism works. Only the `M_http.retry_with_backoff` helper's INTERNAL implementation depends on Q9's answer; the callers and the contract are unchanged.

---

*Phase: 05-resilience-error-handling*
*Context gathered: 2026-06-21*
