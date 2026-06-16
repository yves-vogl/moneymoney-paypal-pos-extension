# Phase 2: Authenticated Network Layer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-17
**Phase:** 2 — Authenticated Network Layer
**Areas discussed:** Fail-fast probe, client_id resolution, Multi-account identity, Error handoff to Phase 5

---

## A. Fail-fast probe inside `InitializeSession2`

Context: AUTH-03 demands that a wrong API key fails synchronously in MoneyMoney's add-account dialog rather than silently hours later on first refresh. The orchestrator presented three probe strategies grounded in the iZettle `authorization.md` flow and the Zettle Purchase / Finance API host conventions.

| Option | Description | Selected |
|--------|-------------|----------|
| 1. Token-fetch only | `POST oauth.zettle.com/token`; 200 → success, 4xx → `LoginFailed`. One round-trip, but merchant profile remains unknown for ACCT-02. | |
| 2. Token + `/users/self` | After successful token exchange, `GET oauth.zettle.com/users/self` with `Bearer <token>`. Two round-trips, but yields merchant name + `organizationUuid` immediately and makes 401-on-token vs 401-on-profile distinguishable. | ✓ |
| 3. Token + Purchases-smoke-test | Token + `GET purchase.izettle.com/purchases/v2?limit=1` — overkill, exercises a billing-relevant endpoint just for validation. | |

**User's choice:** Option 2.
**Notes:** Trade-off accepted: +1 round-trip in add-account flow buys (a) merchant name + orgUuid for ACCT-02/ACCT-04 without a second fetch later and (b) distinguishable auth-failure modes (key rejected vs scope mismatch).

---

## B. `client_id` resolution

Context: The OAuth POST requires `client_id=<UUID>`. Phase-1 ADR-0003 question Q6 ("PayPal POS first-party `client_id`") was still open.

| Option | Description | Selected |
|--------|-------------|----------|
| 1. JWT-payload decode | Decode the assertion's middle base64url segment, JSON-parse, read `aud`/`client_id` claim. No hardcoded constants. | ✓ |
| 2. Hardcoded Zettle-partner UUID | One constant in `src/auth.lua`, sourced via probe or developer portal. Risk of silent rot if Zettle rotates. | |
| 3. Second credential field | User pastes both API key and `client_id`. Robust but bad UX, violates PROJECT.md `paste-once`. | |

**User's choice:** Option 1.
**Notes:** Closes ADR-0003 Q6 as *"client_id is read from the assertion JWT's `aud`/`client_id` claim; no constant is shipped"*. JWT-payload decoding is needed in any case for `obtained_at`/`expires_at` defensive checks, so the implementation cost is shared.

---

## C. Multi-account identity (ACCT-04)

Context: ACCT-04 lets the merchant install the extension multiple times for multiple PayPal POS accounts. Three sub-decisions hang on the `/users/self` payload chosen in Area A.

| Option | Description | Selected |
|--------|-------------|----------|
| Set as recommended | `accountNumber = organizationUuid`, `name = "PayPal POS — " .. publicName` (with orgUuid prefix fallback), `LocalStorage.zettle[orgUuid] = {...}` nested with flat-key JSON fallback gated on Phase-1 probe Q5. | ✓ |
| Identity ok, token-cache flat from day one | Skip the nested-table experiment, use `LocalStorage["zettle:" .. orgUuid] = JSON-string` directly. Less elegant but probe-independent. | |
| Anders — adjust label and/or accountNumber separately | Sub-by-sub decision. | |

**User's choice:** Set as recommended.
**Notes:** Caveat preserved in CONTEXT.md D-23c: if Phase-1 probe Q5 reports that nested `LocalStorage` tables do **not** survive restart, the flat-key fallback already designed in (`LocalStorage["zettle:" .. orgUuid] = JSON-encoded`) is the contingency path. The planner must check ADR-0003 Q5 status before committing to nested-or-flat.

---

## D. Error handoff to Phase 5

Context: Phase 1 shipped `src/errors.lua` as `M_errors = {}` with the understanding that full categorization belongs to Phase 5. Phase 2 still needs HTTP error semantics for the auth path.

| Option | Description | Selected |
|--------|-------------|----------|
| 1. Inline mapping in `auth.lua` | Hardcoded `if status == 401 then return LoginFailed elseif ...` inside `auth.lua`. Errors.lua stays a stub. | |
| 2. Minimal `M_errors.from_http_status(status, body)` in `errors.lua` | Generic mapping function with a stable signature. Phase 2 fills auth-relevant cases; Phase 5 extends additively. Single source of truth. | ✓ |

**User's choice:** Option 2.
**Notes:** Phase 5 expansion (retry/backoff, 5xx body parsing, refund-specific cases) is additive without touching the signature. Forward-compatibility chosen over strictest scope-isolation reading of Phase-1 CONTEXT.

---

## Claude's Discretion

- Exact Lua module layout inside `src/auth.lua` / `src/http.lua` (helper ordering, internal naming).
- Log-line placement and DEBUG-vs-INFO classification, subject to the never-log-the-key invariant.
- Test file granularity under `spec/` (one consolidated spec vs split per concern).

## Deferred Ideas

- Retry/backoff and 429 throttling at the call layer → Phase 5.
- Recorded sandbox fixtures under `spec/fixtures/auth/recorded/` → optional follow-up after Phase 2.
- `/users/self` cache invalidation on profile change → Phase 5/6.
- Sandbox/dev-mode toggle in shipped artifact → out (D-27).
- One-shot `tools/probe.lua` extension for Q2 (token-endpoint redirect behavior) → optional pre-plan-phase enrichment.
