# ADR-0003: MoneyMoney Sandbox Probe Results

## Status

ACCEPTED

## Date

2026-06-16
Updated: 2026-06-17

## Deciders

Yves Vogl

## Context

Phase 1 probe extension (`tools/probe.lua`) was installed in MoneyMoney and
`RefreshAccount` was triggered on the probe account. Results below are transcribed from
MoneyMoney's Protokoll panel.

## Results

| # | Probe | Method | Result | Decision | Phase Impact |
|---|-------|--------|--------|----------|--------------|
| Q1 | Sandbox globals (`require`, `io`, `os`, `debug`, …) | Enumerate `_G` via probe extension on MoneyMoney 2.4.72 (514), macOS 26.4.1 (ARM) | **All present** — `require`, `dofile`, `loadfile`, `io`, `os`, `debug`, `package` are exposed as functions/tables. MoneyMoney does **not** sandbox these away. Full `_G` listing in PR_DRAFT and SUMMARY. Bonus: MM-specific globals confirmed (`AccountTypePayPal`, `BankInfo`, `CurrencyCode`, `MerchantCode`, `NoTanRequired`, `PaymentType*`, `ProtocolAPI0-7`, `ProtocolPSD0-7`, `PurposeCode`, `TransactionCode`). | Amalgamator-level ban on `require`/`dofile`/`loadfile`/`io.open`/`os.execute`/`io.popen` in `src/` stays as a code-discipline rule (portability + auditability), not a sandbox enforcement. R2 dispelled: `os.time()` in `src/entry.lua` is safe. | Phase 1 gate met |
| Q2 | `Connection():request` 302-redirect behavior on `oauth.zettle.com/token` | Phase 2 auth spike — observe actual redirect handling | DEFERRED to Phase 2 first live token-exchange call | If NO auto-follow: add max-3-hop redirect loop in `http.lua` | Phase 2 design |
| Q3 | `finance.izettle.com` host for `/v2/accounts/liquid/transactions` | First live Finance API call in Phase 4 | DEFERRED to Phase 4 first live Finance call | Lock host constant in `http.lua`; update D12 confidence to HIGH on positive resolution | Phase 4 design |
| Q4 | JSON integer round-trip with `{amount=995}` | `JSON():set({amount=995}):json()` + `JSON(encoded):dictionary()` | **PASS** — encoded `{"amount":995}`; decoded `amount = 995` with `type = number`. Integer preserved end-to-end. | No `string.format("%d", v)` workaround required in `mapping.lua` (Phase 3); minor-unit amounts may be stored as Lua numbers. | Phase 3 unblocked |
| Q5 | LocalStorage cross-restart persistence | probe_counter increments across MoneyMoney restarts | **WRITABLE confirmed** — first run after install: `previous_counter = 0 → current_counter = 1`. Cross-restart-persistence observation deferred (the second restart was overtaken by the T13 walking-skeleton install). | Phase 2 token-cache designs **defensively** for both outcomes: cache that survives is a bonus, cache that resets re-requests a token on the next cold start. Either path keeps within the 7200-second token TTL budget and is observable by adding a single log line on cache miss. | Phase 2 design — defensive |
| Q6 | PayPal POS first-party client_id | developer.zettle.com → My Apps → app settings | DEFERRED to Phase 2 (maintainer-side lookup) | Ship constant in `auth.lua`; if region-specific: constants table with EU default | Phase 2 auth |
| Q7 | `services = {"PayPal POS"}` label in MoneyMoney add-account UI | User observes "Konto hinzufügen" bank list | **CONFIRMED** — both `"PayPal POS Probe"` (probe extension, services array) and `"PayPal POS"` (walking-skeleton artifact, services array) render selectably in the bank list; user successfully picked each and the corresponding extension loaded (Protokoll: `Web Banking Engine: Using user-supplied extension <name>.lua`). | Keep `services = {"PayPal POS"}` in `src/webbanking_header.lua` for v0.1.0. No fallback to `"PayPal POS (Zettle)"` required. | Phase 2 production label locked |
| Q8 | `Connection()` TLS verification default | `Connection():get("https://expired.badssl.com/")` in probe `RefreshAccount` | **TLS VERIFIED** — MoneyMoney rejected the expired certificate with `errSSLXCertChainInvalid` (`CFReadStream Error Domain=NSOSStatusErrorDomain Code=-9807`). No certificate-pinning needed; system trust store enforcement is active by default. **Bonus finding:** `pcall()` around `Connection():get()` does NOT catch the SSL rejection — MM surfaces it through its own UI / Protokoll channel and aborts the surrounding Lua function. | TLS posture is safe for production. Phase 2 `http.lua` must NOT rely on `pcall` to catch connection-level failures; failure paths must be modeled on MM's documented error channels (typically a return value or `nil + error string` pattern). | Phase 2 error-handling design note |

## Consequences

- **Q1 (resolved):** The H8 gate in `tools/build.lua` remains active despite the sandbox
  exposing the dangerous globals — discipline over enforcement. `os.time()` and similar
  benign uses in `src/entry.lua` are confirmed safe.
- **Q2 (deferred to Phase 2):** observed on first live token-exchange call against
  `oauth.zettle.com/token`. `http.lua` is written defensively (a manual redirect-follow
  loop is implementable in ≤ 20 LoC if the live call shows MoneyMoney does not auto-follow).
- **Q3 (deferred to Phase 4):** confirmed on first live Finance API call. ARCHITECTURE D12
  is promoted from MEDIUM to HIGH at that moment.
- **Q4 (resolved):** `mapping.lua` stores minor-unit amounts as plain Lua numbers; no
  `string.format("%d", v)` shielding is required.
- **Q5 (partially resolved — writability confirmed, persistence unobserved):** the Phase 2
  `auth.lua` cache treats `LocalStorage` as best-effort persistence. On cache-miss the
  extension re-mints a token (a single extra request per cold start at worst). A one-line
  log entry will surface the actual persistence behaviour in production for retroactive
  Q5 closure.
- **Q6 (deferred to Phase 2):** maintainer-side lookup on developer.zettle.com before
  the auth implementation begins. Constants table with EU default keeps the option open
  for regional variation.
- **Q7 (resolved):** `services = {"PayPal POS"}` is locked for v0.1.0; no label rewording
  required. `SupportsBank` bankCode matching stays as-is.
- **Q8 (resolved + bonus):** TLS verification is safe; no certificate pinning needed.
  Phase 2 error-handling explicitly does NOT rely on `pcall` for connection-level
  failures — `http.lua` uses MM's documented error-return pattern instead.
