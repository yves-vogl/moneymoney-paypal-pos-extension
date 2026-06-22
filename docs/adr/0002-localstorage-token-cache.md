# ADR-0002: LocalStorage-backed token cache for the OAuth bearer

## Status

ACCEPTED

## Date

2026-06-22

## Deciders

Yves Vogl

## Context

Zettle's OAuth `jwt-bearer` assertion-grant flow returns a `Bearer` access
token with `expires_in: 7200` (two hours) and **no refresh token**. To stay
under that two-hour window, the extension must mint a new token by replaying
the same `assertion` (the user-provided API key) against
`https://oauth.zettle.com/token` whenever the cached token is missing or
nearly expired.

Re-minting on every single `RefreshAccount` invocation would:

- Add ~200 ms per refresh (HTTPS round-trip + OAuth handshake) for no
  cross-refresh value — the token is valid for two hours.
- Burn Zettle's `/token` rate budget unnecessarily — Zettle does not document
  per-merchant token-endpoint quotas precisely, and `MoneyMoney` users often
  trigger an account refresh manually multiple times per minute when
  reconciling.
- Make the user-visible failure mode of a revoked API key indistinguishable
  from a transient network failure (every refresh attempts a fresh mint).

Phase 1 Q5 (`docs/adr/0003-sandbox-probe-results.md`) confirmed MoneyMoney's
`LocalStorage` global table is available, is per-account, and survives
MoneyMoney restarts and quit/relaunch cycles. It is therefore the natural
cache substrate.

This ADR retroactively documents the Phase-2 decision (Plan 02-05; commits
landed 2026-06-16..18) so a future maintainer can read the cache schema and
invalidation rules in one place without spelunking the source.

References:

- Phase-1 ADR-0003 Q5 — LocalStorage availability + per-account scope.
- Phase-2 Plan 02-05 — token cache implementation in `src/auth.lua`.
- Phase-5 ADR-0005 §ERR-04 — token-revoked recovery layered on this cache.
- CLAUDE.md "Token TTL = 7200 s; re-request when ≤60 s remain."

## Decision

Cache the access token plus its provenance in `LocalStorage.zettle`, with the
following schema:

```lua
LocalStorage.zettle = {
  access_token = "<opaque-bearer-string>",   -- as returned by /token
  obtained_at  = <integer-epoch-seconds>,    -- os.time() at mint
  expires_at   = <integer-epoch-seconds>,    -- obtained_at + expires_in
  client_id    = "<jwt-claims-client_id>",   -- decoded from the assertion JWT
}
```

`M_auth.cached_token()` returns the cached `access_token` when
`os.time() < expires_at - 60` (60-second safety margin against clock skew and
in-flight TTL exhaustion) AND the `client_id` field matches the freshly
decoded assertion's `client_id` claim. Mismatch (the user pasted a different
API key into MoneyMoney's credentials dialog) discards the cache and re-mints.

When `cached_token()` returns `nil`, `M_auth.mint_token()` calls
`oauth.zettle.com/token`, on success writes the full record back to
`LocalStorage.zettle`, and returns the new bearer.

The `client_id` field is reserved for ADR-0006's Phase-7 forward-compat:
once a second auth flow (OAuth Authorization-Code grant) is added, a single
MoneyMoney instance may hold tokens for multiple clients; the field
distinguishes them. For v1.0.x (assertion-grant-only) the field is set but
never read for branching — the freshness check alone is sufficient.

## Consequences

**Positive:**

- Cross-`RefreshAccount` reuse — typical merchant runs 1–4 refreshes per
  business day, all served from cache.
- Cross-MoneyMoney-restart preservation — `LocalStorage` is persisted by
  MoneyMoney; a quit/relaunch the same morning still has a valid token.
- First-refresh-after-restart latency drops from ~250 ms to ~90 ms.
- Foundation for ERR-04 (token-revoked recovery): when a 401 surfaces
  mid-refresh, the layer above invalidates the cache, re-mints once, and
  retries — preserving the user's session.

**Negative:**

- A copy of the bearer token lives on disk inside MoneyMoney's encrypted
  database. The window of exposure is 7200 seconds. Mitigations:
  - The user-provided **API key** (the assertion JWT) is the durable
    credential and is NEVER cached — only the short-lived bearer is.
  - MoneyMoney encrypts its database at rest using the user's macOS
    Keychain-protected password.
  - The SEC-01 redactor strips `Bearer` and JWT shape from logs so the
    token never escapes via `M_log` (see `src/log.lua` D-79 sentinel).

**Schema migration constraint:**

- The schema is **frozen for v1.0.x**. Any future change (e.g. adding a
  `refresh_token` field for ADR-0006's Phase-7 OAuth-Code flow) MUST be
  read-compatible: a v1.0.x cache must be readable by the new code, with
  missing fields treated as cache-miss rather than parse-error. No
  migration is planned for v1.0.x.

## References

- `src/auth.lua` — `M_auth.cached_token()`, `M_auth.mint_token()`,
  `LocalStorage.zettle` writes.
- Phase-2 RESEARCH §JWT decoder (`spec/fixtures/auth/`) — JWT-shape test
  fixtures used to validate the `client_id` extraction.
- Phase-1 ADR-0003 Q5 — `LocalStorage` availability finding.
- Phase-5 ADR-0005 §ERR-04 — token-revoked recovery layered on this cache.
- CLAUDE.md — "Token TTL = 7200 s; re-request when ≤60 s remain."
