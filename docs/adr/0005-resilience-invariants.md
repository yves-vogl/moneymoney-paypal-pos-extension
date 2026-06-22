# ADR-0005: Resilience & Error-Handling Invariants

## Status

ACCEPTED

## Date

2026-06-22

## Deciders

Yves Vogl

## Context

Phase 5 (v0.3.0) layers adversarial-condition handling onto the Phase 2/3/4
pipeline so that every failure mode produces a clear German error string
returned from `RefreshAccount` / `InitializeSession2`, never a raw Lua error,
never a partial result, and never a silently-advanced `since` watermark.

Six requirements (`ERR-01`..`ERR-06`) per
[`.planning/REQUIREMENTS.md`] drive the design. They cover the full failure
surface a real PayPal POS merchant can hit:

1. Token-mint failure (bad API key, revoked key, expired key).
2. Transient server-side failures (5xx) on `oauth.zettle.com`,
   `purchase.izettle.com`, `finance.izettle.com`.
3. Rate-limiting responses (HTTP 429) from any of the three hosts.
4. Mid-refresh session loss (HTTP 401 on a resource call after the token
   was successfully minted).
5. Network failures (DNS failure, connect-refused, socket timeout).
6. Partial refresh outcomes — where one of N sequential endpoint calls
   fails and earlier successful calls have already produced in-memory
   state.

The decision is split into six invariants (one per requirement) plus two
explicit carve-outs (SSL handshake failures bypass `ERR-05`; HTTP-date
`Retry-After` falls through to a 30-second default) plus a documented
sleep-mechanism choice (`MM.sleep` — the nested `MM.os` variant referenced
in earlier CONTEXT drafts does not exist as an API surface).

References:
- Phase-5 research plan:
  `.planning/phases/05-resilience-error-handling/05-RESEARCH.md`
  — §1 (sleep-mechanism correction), §2 (Retry-After integer-only),
  §Pattern-2 (D-64 collapse rationale), §5 (`ERR-06` fail-whole audit),
  §Pitfall 10 (SSL bypass), §9 (worst-case timing budget).
- Phase-5 context plan:
  `.planning/phases/05-resilience-error-handling/05-CONTEXT.md`
  — D-61..D-69 verbatim source of the invariants.
- ADR-0003 (sandbox probe results) — Q8 bonus finding (`pcall` does NOT
  catch SSL handshake failures).
- ADR-0004 (Finance API scope + fee-fallback) — the 401-on-first-Finance
  call already documented there feeds into `ERR-04` framing.
- CLAUDE.md — Token TTL 7200 s, no refresh token under assertion-grant.

## Decision

### Invariant 1 — ERR-01 token-mint `invalid_grant` → `LoginFailed` (D-61)

Already shipped in Phase 2: `src/errors.lua` D-24 dispatch maps an
`oauth.zettle.com/token` HTTP 400 response with
`error == "invalid_grant"` to MoneyMoney's built-in `LoginFailed`
constant. Plan 05-02 only extends `spec/auth_spec.lua` with an explicit
fixture-driven `ERR-01` test using the existing
`spec/fixtures/auth/auth_invalid_grant.json` fixture. No source change
this plan.

`LoginFailed` is reserved for **token-mint** failures and is
distinguished from `ERR-04` (post-mint 401), which surfaces the German
`error.token_revoked` string instead. The split matters because the user
remediation is different: `LoginFailed` means "the API key MoneyMoney
holds is wrong"; `error.token_revoked` means "the API key was valid at
mint time but the session has since been invalidated server-side".

### Invariant 2 — ERR-02 5xx retry-with-backoff (D-62)

Inside `M_http.get_json` and `M_http.post_form` the request is wrapped in
`for attempt = 1, 3 do`. Between attempts the extension sleeps `{1, 2,
4}` seconds (exponential, base 2) via `MM.sleep`. On exhausted retries
the surfaced status is whatever the body-shape inference yielded
(typically `nil` → routes through `M_errors.from_http_status` to
`error.network` — see Invariant 5).

Each attempt emits exactly ONE `INFO` log line via `M_log.info` with
format:

```
HTTP retry: attempt=N/3 status=NNN url=URL after_ms=NNNN
```

Bearer tokens are redacted by `M_log.redact` AND structurally absent
because request headers are never concatenated into the log string in
the first place.

Recursive retry implementation is REJECTED (Phase-5 RESEARCH §Pitfall 2:
blows Lua's 200-frame call-stack budget on pathological storms).

### Invariant 3 — ERR-03 429 rate-limiting (D-63)

Single retry per endpoint. Honor the `Retry-After` header (integer
seconds only — see Carve-out 2). Cap the wait at 60 s upper bound to
stay within MoneyMoney's per-call timeout envelope (~30-60 s per
ADR-0003 + community survey). Default to 30 s when `Retry-After` is
absent, missing, or unparseable.

Check BOTH the canonical-case `Retry-After` AND lower-case
`retry-after` header keys — server middleware varies on casing and the
MoneyMoney `Connection` 5-tuple's `headers` table preserves whatever
the server sent (Phase-5 RESEARCH §Pitfall 6).

After the single retry, if the response is still 429, surface
`error.rate_limit` via `M_errors.from_http_status`.

### Invariant 4 — ERR-04 post-mint 401 → `error.token_revoked` IMMEDIATELY (D-64 COLLAPSED)

CONTEXT D-64 originally said "perform exactly ONE silent token re-mint".
Phase-5 RESEARCH §Pattern-2 collapses this contract: the silent re-mint
is INFEASIBLE under the assertion-grant model combined with the
`SEC-03` / `AUTH-05` invariants. Specifically:

- The assertion-grant flow has NO refresh token (CLAUDE.md "Token TTL =
  7200 s; no refresh token"). Re-mint requires re-presenting the
  original JWT-bearer assertion (the API key).
- The API key (`assertion`) is ONLY present in memory during
  `InitializeSession2`. `SEC-03` and `AUTH-05` forbid persisting it to
  `LocalStorage`, the `account` table, or beyond the
  `InitializeSession2` invocation lifetime.
- The only re-mint path would require caching the API key in a
  module-local Lua variable across `RefreshAccount` calls, which widens
  the in-memory exposure window from "during `InitializeSession2`
  only" to "for the lifetime of the MoneyMoney process". That is
  incompatible with the spirit of `SEC-03`'s wording even though it
  does not technically write to `LocalStorage`.

Therefore Phase 5 ships the COLLAPSED contract: on a post-mint HTTP
401 received from ANY resource endpoint (Purchase, Finance), `M_http`
returns the 401 status to its caller; the resource-endpoint caller
(`M_purchases.fetch`, `M_finance.fetch`,
`M_finance.fetch_account_state`) translates the 401 into the German
`error.token_revoked` string IMMEDIATELY. NOT `LoginFailed` — that
constant is reserved for `ERR-01` token-mint failures per Invariant 1.

The user sees the German message
"Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen" and
manually re-enters the API key via MoneyMoney's account dialog, which
re-invokes `InitializeSession2` and produces a fresh token mint.

The reinterpretation preserves the user-facing intent of D-64 ("don't
return `LoginFailed`; the credentials are not bad — the session was
revoked") while strictly honoring `SEC-03` / `AUTH-05`.

**Future v2 path:** if/when Phase 7 (Optional OAuth
Authorization-Code flow per ROADMAP) ships, the refresh-token primitive
enables genuine silent re-mint and `ERR-04` can be revisited without
violating any current security invariant.

### Invariant 5 — ERR-05 network failure → `error.network` (D-65)

Phase 2's design REJECTS `pcall` around `Connection:request` (Phase-2
RESEARCH §Pitfall 3; ADR-0003 Q8 bonus finding). Phase 5 inherits this
posture: network failures (DNS resolution failure, connect-refused,
socket timeout) surface as `conn:request` returning an empty body,
which the existing `src/http.lua` L130-132 + L102-105 path catches and
returns as `(nil, nil, raw)` from `get_json` / `post_form`.

`M_errors.from_http_status(nil, "")` then returns `error.network` from
D-24 case 1. Plan 05-02 adds an explicit regression test queueing
`Mocks.push_response({ content = "" })` to gate this path, ensuring
that no future refactor of `http.lua` accidentally turns an empty-body
response into a `LoginFailed` or a Lua error.

### Invariant 6 — ERR-06 fail-whole-refresh (D-66)

Phase 4's 16-step `RefreshAccount` (`src/entry.lua` L139-435) ALREADY
implements the invariant: early returns at Steps 1, 2, 4, 7, 8 discard
all in-flight state because Lua's lexical scoping cleans up locals
automatically (`purchases_by_uuid`, `payments_by_uuid`,
`fees_by_date`, `transactions` are all `local`). Phase-5 RESEARCH §5
audit confirms structural correctness.

Plan 05-05 ships the GATING SPEC ONLY
(`spec/refresh_fail_whole_spec.lua`) — no source change. The spec
queues purchase success + finance 500-with-retries-exhausted and
asserts:

1. The German error string is returned (not partial result, not Lua
   error).
2. The Purchase API call happened (visible in `captured_requests`).
3. No transactions leaked out into the return value.
4. A second `RefreshAccount` invocation with the SAME `since` watermark
   re-runs from scratch and succeeds when the Finance API recovers.

## Carve-outs (known limitations)

### Carve-out 1 — SSL handshake failures bypass ERR-05

ADR-0003 Q8 bonus finding: `pcall` around `conn:request` does NOT catch
SSL handshake failures — MoneyMoney aborts the surrounding Lua chunk
and surfaces the failure through its own Protokoll panel.

`ERR-05`'s German-string contract therefore covers DNS resolution
failures, connect-refused, and socket timeouts; SSL handshake failures
(expired certificates, MITM-detected hostname mismatches, server cert
chain errors) BYPASS this contract.

**Mitigation strategy:**
- TLS 1.2+ is enforced by MoneyMoney's `Connection()` (ADR-0003 Q8 +
  CLAUDE.md "TLS — TLS 1.2+ enforced by Zettle; `Connection()` handles
  this").
- Certificate pinning is explicitly OUT OF SCOPE per `REQUIREMENTS.md`;
  the extension defers to OS-level certificate verification.
- User-facing remediation: open MoneyMoney's Protokoll panel to
  diagnose the underlying SSL error message.

This carve-out is intentional. Future phases SHOULD NOT attempt to
"fix" `ERR-05` to cover SSL handshakes — the underlying
MoneyMoney behaviour cannot be intercepted from Lua user code.

### Carve-out 2 — HTTP-date Retry-After silently degrades to 30 s default

RFC 7231 §7.1.3 allows `Retry-After` to be either delta-seconds
(integer) or HTTP-date. Phase 5 implements integer-only parsing via
`tonumber()` plus negative-value rejection. The HTTP-date format falls
through to the 30 s default.

**Rationale:**
- Zettle has never been observed to emit HTTP-date `Retry-After` in any
  community fixture or documented response.
- RFC 7231 §7.1.1.1 date-parsing requires ~80 lines of Lua for a code
  path that may never execute against the real Zettle API.
- The fallback is safe: a single 30 s sleep stays within the per-call
  timeout estimate, so the user never sees a `Connection` timeout
  caused by the fallback itself.

Verify on the first 429 observation in production. If HTTP-date
appears, either add a one-line `gsub` to extract a sensible delay or
escalate to a dedicated parser; do not block release on this carve-out.

## Sleep mechanism

Use `MM.sleep(seconds)`, the sandbox primitive documented in the
MoneyMoney WebBanking API
(https://moneymoney.app/api/webbanking/ — "Unterbricht die
Ausführung des Skripts für ein paar Sekunden"). The integer-seconds
contract is the documented signature; precision below one second is
undocumented and out of scope.

All Phase-5 sleep durations are integer seconds:
- 5xx exponential backoff: `{1, 2, 4}`.
- 429 honoring `Retry-After`: up to 60 (capped).
- 429 default fallback: 30.

**Important correction:** CONTEXT D-67 + the Q9 row use a nested
`MM.os` variant. This is INCORRECT. The documented name is `MM.sleep`,
under the top-level `MM.*` helpers, NOT under a nested `MM.os` table.
The CI test harness already stubs `_G.MM.sleep = function(s) end` as a
no-op at `spec/helpers/mm_mocks.lua` line 233, so unit tests do not
actually sleep.

**Q9 sandbox probe:** OPTIONAL confirmation per RESEARCH §1.
`tools/probe.lua` carries a Q9 block (added by Plan 05-01) so Yves can
run it inside MoneyMoney when convenient. The probe checks
`type(MM.sleep) == "function"` and measures `MM.sleep(1)` elapsed
time, classifying the result as `PASS` / `PRESENT-BUT-NOOP` /
`ABSENT` / `FAIL`. The outcome is recorded in `docs/adr/0003-sandbox-
probe-results.md` row Q9 (added by Yves AFTER running the probe;
Plan 05-01 does NOT pre-add the row).

If Q9 returns `ABSENT`, this ADR must be amended to use a busy-wait
fallback (`while os.time() < target do end`); the implementation
should `pcall`-wrap `MM.sleep` defensively so a runtime error on a
future MoneyMoney version falls through to no-backoff retry rather
than aborting `RefreshAccount`.

## Worst-case timing budget

Per Phase-5 RESEARCH §9:

- Single-endpoint 5xx storm: ~9 s
  (1 s + 2 s backoff + 3 × ~500 ms-2 s HTTP roundtrips).
- 3-endpoint 5xx storm (purchase + finance state + finance
  transactions): ~27 s.
- Single 429 with `Retry-After`: up to 60 s (capped).

The 3-endpoint 5xx worst case fits within MoneyMoney's per-call
timeout estimate (~30-60 s per ADR-0003 + community survey) but is
uncomfortably close. Mitigation strategies (NOT applied in v1.0.0):

- Reduce backoff curve to `{1, 2}` (saves 4 s per endpoint, ~12 s
  total for the 3-endpoint case).
- Reduce `MAX_ATTEMPTS` from 3 to 2.
- Implement a global `RefreshAccount` timeout that cancels remaining
  sleeps once a wall-clock budget is exceeded.

v1.0.0 ships the `{1, 2, 4}` 3-attempt curve. Monitor real-world
reports; tune in v1.0.x if observed timeout breaches occur.

## Cross-reference table

| Requirement | Source artifact                                                                       | Plan       | Status                  |
|-------------|---------------------------------------------------------------------------------------|------------|-------------------------|
| ERR-01      | `src/errors.lua` D-24 + `spec/auth_spec.lua` extension                                | 05-02      | Phase-2 path verified   |
| ERR-02      | `src/http.lua` `get_json` + `post_form` retry loop                                    | 05-03      | new                     |
| ERR-03      | `src/http.lua` `_parse_retry_after` + retry loop                                      | 05-03      | new                     |
| ERR-04      | `src/purchases.lua` + `src/finance.lua` 401-to-`token_revoked` translation            | 05-04      | new (collapsed)         |
| ERR-05      | `src/http.lua` existing empty-body path + new regression spec                         | 05-02 spec | Phase-2 path verified   |
| ERR-06      | `src/entry.lua` Phase-4 16-step pipeline + new gating spec                            | 05-05 spec | structurally enforced   |

`ERR-01` is referenced here because the contract is re-asserted in
this ADR's Invariant 1, even though no source change ships this
phase. Plan 05-02's spec-level coverage is the only new artifact for
`ERR-01`.

## Consequences

### Positive

- All six `ERR` requirements gated by automated tests; no manual QA
  required for failure-mode validation.
- Zero new external dependencies (`MM.sleep` is sandbox-built-in;
  `tonumber` is stdlib).
- `SEC-03` / `AUTH-05` invariants preserved end-to-end: the API key
  never extends in scope or lifetime beyond `InitializeSession2`.
- Worst-case timing fits MoneyMoney's per-call budget under realistic
  single-endpoint failure scenarios.

### Negative

- User must manually re-enter the API key on a post-mint 401 — no
  silent re-mint is possible under the assertion-grant model. Mitigated
  by Phase 7 (OAuth Authorization-Code flow) if/when it ships.
- SSL handshake failures bypass `ERR-05`'s German-string contract
  (Carve-out 1).
- HTTP-date `Retry-After` silently degrades to the 30 s default
  (Carve-out 2).
- 3-endpoint 5xx storm worst-case (~27 s) is uncomfortably close to
  the 30 s budget; future v1.0.x may need to tune the backoff curve.

### Neutral

- The retry log adds up to 3 new `INFO` lines per `RefreshAccount`
  under failure conditions. `SEC-03` redaction extends to cover them
  (Plan 05-05 gating spec verifies no Bearer or API-key material
  leaks into the log string).

## Sources

- MoneyMoney WebBanking API — https://moneymoney.app/api/webbanking/ —
  `MM.sleep` + `Connection()` 5-tuple contract.
- ADR-0003 (sandbox probe results) — Q8 bonus finding (`pcall` does
  NOT catch SSL handshake failures); Q9 row added by Yves after
  running the Plan 05-01 probe.
- `.planning/phases/05-resilience-error-handling/05-RESEARCH.md` —
  §1 (sleep-mechanism correction), §2 (Retry-After integer-only),
  §Pattern-2 (D-64 collapse rationale), §5 (`ERR-06` fail-whole audit),
  §Pitfall 10 (SSL bypass), §9 (worst-case timing budget).
- `.planning/phases/05-resilience-error-handling/05-CONTEXT.md` —
  D-61..D-69 verbatim source of the invariants.
- RFC 7231 §7.1.3 — `Retry-After` delta-seconds vs HTTP-date.
- CLAUDE.md — Token TTL 7200 s, no refresh token under
  assertion-grant; `SEC-03` / `AUTH-05` invariants.
- ADR-0004 (Finance API scope) — 401-on-first-Finance precedent that
  feeds into Invariant 4's framing.
