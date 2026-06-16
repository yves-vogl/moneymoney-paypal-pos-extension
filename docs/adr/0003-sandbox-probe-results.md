# ADR-0003: MoneyMoney Sandbox Probe Results

## Status

PROPOSED

## Date

2026-06-16
Updated: <YYYY-MM-DD>

## Deciders

Yves Vogl

## Context

Phase 1 probe extension (`tools/probe.lua`) was installed in MoneyMoney and
`RefreshAccount` was triggered on the probe account. Results below are transcribed from
MoneyMoney's Protokoll panel.

## Results

| # | Probe | Method | Result | Decision | Phase Impact |
|---|-------|--------|--------|----------|--------------|
| Q1 | Sandbox globals (`require`, `io`, `os`, `debug`, …) | Enumerate `_G` via probe extension | FILL IN | Hard rule: shipped artifact uses zero `require`/`dofile`; confirmed safe | Phase 1 gates on this |
| Q2 | `Connection():request` 302-redirect behavior on `oauth.zettle.com/token` | Phase 2 auth spike — observe actual redirect handling | FILL IN (Phase 2) | If NO auto-follow: add max-3-hop redirect loop in http.lua | Phase 2 design |
| Q3 | `finance.izettle.com` host for `/v2/accounts/liquid/transactions` | First live Finance API call in Phase 4 | FILL IN (Phase 4) | Lock host constant in http.lua; update D12 confidence to HIGH | Phase 4 design |
| Q4 | JSON integer round-trip with `{amount=995}` | `JSON():set(t):json()` + `JSON(s):dictionary()` | FILL IN | If decoded.amount is not the integer 995: use `string.format("%d", v)` for all minor-unit amounts | Phase 3 mapping |
| Q5 | LocalStorage cross-restart persistence | probe_counter increments across MoneyMoney restarts | FILL IN | If counter resets: design token cache as session-local only; document cache miss behaviour | Phase 2 auth |
| Q6 | PayPal POS first-party client_id | developer.zettle.com → My Apps → app settings | FILL IN (Phase 2) | Ship constant in auth.lua; if region-specific: constants table, EU default | Phase 2 auth |
| Q7 | `services = {"PayPal POS"}` label in MoneyMoney add-account UI | User observes "Konto hinzufügen" bank list | FILL IN | If different: update services string and SupportsBank bankCode | Phase 2 design |
| Q8 | `Connection()` TLS verification default | Connection to expired.badssl.com — observe accept/reject | FILL IN | If TLS NOT verified: blocking issue; raise with MoneyMoney community | Phase 2 blocker if NOT verified |

## Consequences

- Q1: design constraint on shipped artifact (no `require`/`dofile`) confirmed from live
  sandbox; if any dangerous global is present, review the H8 gate in `tools/build.lua`.
- Q2: determines whether `http.lua` needs a manual redirect-follow loop (up to 3 hops) or
  can rely on `Connection()` auto-following 302 responses.
- Q3: finalises the `finance.izettle.com` host constant in `http.lua`; promotes ARCHITECTURE.md
  D12 confidence from MEDIUM to HIGH.
- Q4: determines the minor-unit integer strategy in `mapping.lua` — direct Lua number or
  `string.format("%d", v)` guard for JSON round-trips.
- Q5: determines whether the OAuth access token can be cached across MoneyMoney restarts
  via `LocalStorage`, or must be re-requested on every session start.
- Q6: provides the `client_id` constant to embed in `auth.lua`; if region-specific values
  are found, a constants table with EU default is required.
- Q7: confirms whether `"PayPal POS"` is the exact label that appears in MoneyMoney's
  "Konto hinzufügen" UI; drives the `services` string and `SupportsBank` bankCode.
- Q8: confirms TLS posture; a NO result is a Phase 2 blocking issue that must be raised
  with the MoneyMoney community before any live credentials are used.
