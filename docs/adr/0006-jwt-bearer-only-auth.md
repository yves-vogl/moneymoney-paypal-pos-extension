# ADR-0006: v1.0.x ships JWT-bearer assertion-grant only

## Status

ACCEPTED

## Date

2026-06-22

## Deciders

Yves Vogl

## Context

Zettle's OAuth implementation exposes two distinct grant types relevant to
this extension:

1. **`urn:ietf:params:oauth:grant-type:jwt-bearer`** — assertion grant. The
   user pre-mints a long-lived API key in the Zettle developer portal
   (`https://my.zettle.com/apps/api-keys`). The API key is itself a signed
   JWT. The extension POSTs that JWT as `assertion=` to `oauth.zettle.com/token`
   and receives a 7200-second bearer in return. No browser redirect, no
   client-side secret, no callback URL — one paste into MoneyMoney's
   credentials dialog, then fully offline.

2. **`authorization_code`** — standard OAuth 2.0 Authorization-Code flow.
   The user clicks "Connect with Zettle", is redirected to Zettle's consent
   page, logs in there, is redirected back to a registered callback URL with
   an authorization code, which the extension exchanges for a bearer +
   refresh token. Supports multi-tenant + refresh-token rotation.

CLAUDE.md's "Alternatives Considered" table explicitly rejects flow 2 for
v1.0:

> OAuth2 browser flow (authorization code grant) — The extension cannot
> open a browser, host a callback, or redirect. The MoneyMoney credentials
> dialog is the only UI surface.

The MoneyMoney sandbox has no browser-launch capability, no HTTP server
to host a callback URL, and no in-app web view. Adding flow 2 requires
either (a) an out-of-band redirect-helper page hosted somewhere by the
maintainer (out of scope per PROJECT.md), or (b) a non-trivial UI hack
where MoneyMoney's user pastes a code from a manually opened browser
session — worse UX than the assertion-grant paste.

This ADR retroactively documents the Phase-2 implementation choice
(`src/auth.lua` ships flow 1 only) and the forward-compat note for the
ROADMAP Phase-7 entry that adds flow 2.

References:

- CLAUDE.md → "Alternatives Considered" → row "Assertion grant (jwt-bearer)
  vs OAuth2 Authorization-Code flow".
- Phase-2 Plan 02-05 — auth implementation.
- `.planning/ROADMAP.md` Phase 7 entry — deferred OAuth-Code flow.
- iZettle/api-documentation/authorization.md — both flows documented.

## Decision

v1.0.x of this extension ships **flow 1 only**. The MoneyMoney credentials
dialog exposes a single field labelled `API-Key` (`InitializeSession2`'s
credentials array, single entry). `src/auth.lua` implements only the
`jwt-bearer` assertion grant against `https://oauth.zettle.com/token`.

The shipped `WebBanking{}` registration table does NOT declare any web-view
URL or redirect callback. The interactive flag in `InitializeSession2` is
honored solely to surface the standard "Anmeldung fehlgeschlagen" /
"Anmeldung blockiert" string-return error messages (see ADR-0008) — never to
launch external auth UI.

**Forward-compat for Phase 7 (deferred).** When OAuth Authorization-Code is
added (no Phase-7 schedule yet), the assertion-grant codepath in
`src/auth.lua` MUST be preserved byte-identically — that is, existing
v1.0.x users do not lose their already-pasted API key. The new flow becomes
an additional credentials-dialog option, not a replacement. The
`LocalStorage.zettle.client_id` field (see ADR-0002) is the
forward-compat hook: a future cache record for a flow-2 token would
co-exist with the flow-1 record, distinguished by `client_id`.

## Consequences

**Positive:**

- Zero partner-app registration burden. The maintainer never has to
  register an OAuth-Application with Zettle, request approval, or host a
  callback URL.
- Zero out-of-band redirect handling. The whole auth flow is one HTTP POST
  inside the sandbox.
- One-merchant-per-MoneyMoney-instance UX matches MoneyMoney's
  per-account-credential model. Adding flow 2 with multi-tenant would have
  introduced friction in MoneyMoney's account-list UI for no v1.0.x user
  benefit.
- Easier security audit surface — one auth path, one token type, one
  failure mode (`invalid_grant`).

**Negative:**

- Users must mint a JWT manually at `https://my.zettle.com/apps/api-keys`
  and paste it into MoneyMoney. The flow has friction; the Phase-4
  ADR-0004 "Inbetriebnahme bei bestehendem v0.1.0 API-Key" section in
  `README.de.md` walks users through it.
- No refresh-token rotation — every 7200-second TTL expiration is a fresh
  POST to `/token` against the user's API key. Mitigated by the
  `LocalStorage.zettle` cache (ADR-0002).
- If a real user complaint accumulates around the manual API-key step,
  the Phase-7 OAuth-Code flow becomes a higher priority — the architecture
  preserves that option without committing to it.

**Constraint:**

- Any Phase-7 implementation MUST keep the v1.0.x assertion-grant codepath
  byte-identical (the same Phase-4 surface-preservation discipline applied
  in the v0.1.x → v0.2.x migration). A v1.0.x user upgrading to a future
  v2.0.0 must not have to re-paste their API key. This is the contract
  that ADR-0002's `client_id` field protects.

## References

- `src/auth.lua` — single OAuth grant type wired.
- `.planning/ROADMAP.md` Phase 7 — deferred OAuth-Code flow.
- CLAUDE.md → "Alternatives Considered" → Authorization-Code row.
- Phase-2 Plan 02-05 — auth implementation.
- ADR-0002 — token cache + `client_id` forward-compat field.
- iZettle/api-documentation/authorization.md — both flows documented upstream.
