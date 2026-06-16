# Architecture Research

**Domain:** MoneyMoney community extension (single concatenated Lua script) integrating PayPal POS / Zettle for German merchants
**Researched:** 2026-06-16
**Confidence:** HIGH

This document covers the ARCHITECTURE dimension only. The STACK, FEATURES, PITFALLS, and SUMMARY dimensions live in sibling files.

---

## 1. Standard Architecture

### System Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                       MoneyMoney runtime (macOS)                       │
│                                                                        │
│   ┌──────────────────────────────────────────────────────────────┐    │
│   │  Extension entry points (callbacks invoked by MoneyMoney)    │    │
│   │  WebBanking{} | SupportsBank | InitializeSession2 |          │    │
│   │  ListAccounts | RefreshAccount | EndSession                  │    │
│   └────────────────────────────┬─────────────────────────────────┘    │
│                                │                                       │
│   ┌────────────────────────────▼─────────────────────────────────┐    │
│   │                  Internal modules (concatenated)             │    │
│   │  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │    │
│   │  │  i18n   │  │  errors  │  │  log     │  │   model      │   │    │
│   │  └─────────┘  └──────────┘  └──────────┘  └──────────────┘   │    │
│   │  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │    │
│   │  │  auth   │  │ purchases│  │ payouts  │  │   balance    │   │    │
│   │  └─────────┘  └──────────┘  └──────────┘  └──────────────┘   │    │
│   │  ┌─────────┐  ┌──────────┐  ┌──────────┐                     │    │
│   │  │ mapping │  │   http   │  │ pagination│                    │    │
│   │  └─────────┘  └──────────┘  └──────────┘                     │    │
│   └──────────────────┬─────────────────┬─────────────────────────┘    │
│                      │                 │                              │
│   ┌──────────────────▼──┐    ┌─────────▼──────────┐                   │
│   │ MoneyMoney globals  │    │  LocalStorage      │                   │
│   │ Connection, JSON,   │    │  (per-extension    │                   │
│   │ MM.base64, MM.local │    │   persistent KV)   │                   │
│   │ -izeText, print     │    │                    │                   │
│   └──────────┬──────────┘    └────────────────────┘                   │
└──────────────┼─────────────────────────────────────────────────────────┘
               │ HTTPS
               ▼
   ┌─────────────────────────────────────────────────────┐
   │              Zettle / PayPal POS API                │
   │   oauth.zettle.com/token         (auth)             │
   │   purchase.izettle.com/purchases/v2   (sales)       │
   │   finance.izettle.com/v2/accounts/liquid/...        │
   │      (balance, payouts, account transactions)       │
   └─────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Source file in dev tree |
|-----------|----------------|--------------------------|
| `webbanking_entry` | Top-level callback shells (`SupportsBank`, `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `EndSession`); thin glue, no business logic. | `src/entry.lua` |
| `i18n` | Resource table `{ de = {...}, en = {...} }`; `t(key)` selects by `MM.localizeText` round-trip or by `os.getenv("LANG")` fallback. | `src/i18n.lua` |
| `errors` | Symbolic error constants, mapping HTTP/JSON errors to user-facing localized strings, masking of secrets in messages. | `src/errors.lua` |
| `log` | Wrapper around `print` with levels (`debug`, `info`, `warn`, `error`); enforces redaction of API keys, JWTs, refresh tokens. | `src/log.lua` |
| `auth` | OAuth2 JWT-assertion grant exchange against `oauth.zettle.com/token`; token lifecycle (cache, refresh, invalidation); persistence via `LocalStorage`. | `src/auth.lua` |
| `http` | Wrapper around `Connection():request()` returning `(body, status, headers)`; retries with exponential backoff on 5xx; injects `Authorization: Bearer`. | `src/http.lua` |
| `pagination` | Iterator helpers for cursor-based (`lastPurchaseHash`) and date-window pagination. | `src/pagination.lua` |
| `purchases` | Calls `GET /purchases/v2`, yields normalized purchase records (sale + refund + per-item fees + VAT breakdown). | `src/purchases.lua` |
| `payouts` | Calls finance API for payouts since `since`; returns normalized payout records. | `src/payouts.lua` |
| `balance` | Reads liquid account balance and pending balance from finance API. | `src/balance.lua` |
| `mapping` | Pure functions converting normalized records into MoneyMoney transaction tables (`{name, amount, currency, bookingDate, valueDate, purpose, bookingText, booked, ...}`). | `src/mapping.lua` |
| `model` | Internal record shapes (purchase, refund, fee, payout) — keeps the API surface of `mapping` and `purchases`/`payouts` decoupled from Zettle's JSON. | `src/model.lua` |

### MoneyMoney callback contracts (cited)

From <https://moneymoney.app/api/webbanking/>:

- `WebBanking { version, country, services = { ... }, description }` — module-level table registers the extension.
- `function SupportsBank(protocol, bankCode)` — returns boolean.
- `function InitializeSession2(protocol, bankCode, step, credentials, interactive)` — multi-step auth. The `credentials` array carries username/password fields declared in `services[].fields`. **Returns `nil` on success, `LoginFailed` (global constant) on auth failure, or a string for transient errors / challenges.**
- `function ListAccounts(knownAccounts)` — returns an array of account tables. **Only `accountNumber` is mandatory.** We also set `type = AccountTypeGiro`, `name`, `currency = "EUR"`, `portfolio = false`.
- `function RefreshAccount(account, since)` — `since` is a POSIX timestamp; the script need not return older transactions. **Returns either a table `{ balance = number, pendingBalance = number, transactions = { ... } }`, or an error message string.**
- `function EndSession()` — no-op for this extension.
- `MM.localizeText(str)` is a wrapper around `NSLocalizedString` and only translates strings that ship with MoneyMoney itself. **Do not rely on it for our own strings.** Use our own `i18n.t(key)` instead.
- `print(...)` output appears in MoneyMoney's log window.

---

## 2. Recommended Project Structure

```
.
├── src/                           # Modular development sources
│   ├── entry.lua                  # MoneyMoney callbacks (assembled last in build)
│   ├── webbanking_header.lua      # WebBanking { ... } declaration (assembled first)
│   ├── i18n.lua                   # German + English string tables, t(key)
│   ├── errors.lua                 # Error codes, secret-masking helpers
│   ├── log.lua                    # Leveled logging wrapper around print
│   ├── http.lua                   # Connection wrapper, retries, auth header injection
│   ├── auth.lua                   # JWT-assertion grant, token cache via LocalStorage
│   ├── pagination.lua             # Cursor + date-window iterators
│   ├── purchases.lua              # GET /purchases/v2
│   ├── payouts.lua                # Finance API payouts
│   ├── balance.lua                # Liquid balance + pending
│   ├── model.lua                  # Internal record shapes
│   └── mapping.lua                # Internal record -> MoneyMoney transaction
│
├── spec/                          # busted tests (mirrors src/)
│   ├── helpers/
│   │   ├── mm_mocks.lua           # Connection, JSON, MM.* mocks; LocalStorage stub
│   │   └── fixtures.lua           # Fixture loader
│   ├── fixtures/                  # Scrubbed real / sandbox JSON responses
│   │   ├── oauth_token.json
│   │   ├── purchases_page_1.json
│   │   ├── purchases_page_2.json
│   │   ├── payouts.json
│   │   ├── balance.json
│   │   └── error_invalid_grant.json
│   ├── auth_spec.lua
│   ├── http_spec.lua
│   ├── pagination_spec.lua
│   ├── purchases_spec.lua
│   ├── payouts_spec.lua
│   ├── balance_spec.lua
│   ├── mapping_spec.lua
│   ├── i18n_spec.lua
│   ├── errors_spec.lua
│   ├── log_redaction_spec.lua
│   └── e2e_refresh_account_spec.lua    # Whole RefreshAccount with mocked HTTP
│
├── build/                         # Amalgamation tool & output (gitignored)
│   └── PayPal POS.lua             # Concatenated release artifact
│
├── tools/
│   └── build.lua                  # Deterministic concatenator (see § 3)
│
├── .github/
│   └── workflows/
│       ├── ci.yml                 # lint + test on every push/PR
│       └── release.yml            # Tag-triggered: build + checksum + signed release
│
├── docs/
│   └── adr/                       # MADR-format Architecture Decision Records
│
├── .luacheckrc
├── .busted
├── README.md                      # German primary, English fallback
└── LICENSE                        # MIT
```

### Structure rationale

- **`src/` over `lib/`**: prevailing convention in the MoneyMoney community is a flat `.lua` at the repo root (Union Investment, BMW Bank, TrueLayer, Trading212 all do this). We diverge intentionally because none of those projects are amalgamated from modular sources — they are written as a single file. Putting modular sources under `src/` keeps a clean separation between *human-edited source* and *MoneyMoney-loadable artifact*.
- **One file per concern**: lowers diff surface in PRs, lets `spec/<module>_spec.lua` mirror `src/<module>.lua` 1:1, and makes amalgamation order deterministic and easy to reason about.
- **`build/` is gitignored**: the release artifact is generated, not authored. Only the **release** workflow attaches it to a GitHub Release.
- **`tools/build.lua` is the amalgamator**: see §3 for why we ship our own ~150-line tool instead of pulling in `amalg.lua`.

---

## 3. The amalgamator — concatenating `src/*.lua` into a single deliverable

### Why not `amalg.lua`?

[`siffiejoe/lua-amalg`](https://github.com/siffiejoe/lua-amalg) is the established prior-art tool in the Lua ecosystem. It works by:

1. Wrapping each module's source in `do ... end` and assigning a loader to `package.preload["module.name"]`.
2. Running the entrypoint script, which then resolves `require("module.name")` from `package.preload`.

This is excellent for embedded Lua and Redis (see `topfreegames/lua-amalg-redis`, `drauschenbach/lua-amalg-redis`) — but it has two problems for a MoneyMoney extension:

1. **MoneyMoney loads the script as a top-level file**, not as a module. The `WebBanking { ... }` declaration must appear at the top level. `amalg.lua`'s output expects a `require` chain.
2. **`package` may not be available** inside MoneyMoney's sandbox in the form Lua-on-CLI expects, and even if it is, the indirection adds risk for a sandbox we don't control.

### Decision

**Ship our own ~150-line `tools/build.lua`** that does a flat, ordered concatenation. This is the prevailing approach for any Lua project that targets a host expecting a single top-level script (LÖVE, OpenResty single-file deploys, Defold).

Prior-art references that informed the design:

- [`siffiejoe/lua-amalg`](https://github.com/siffiejoe/lua-amalg) — the canonical tool, studied for its scoping technique.
- [Exasol "Lua part 3: Handling modules"](https://exasol.my.site.com/s/article/Exasol-loves-Lua-part-3-Handling-modules) — host-specific amalgamation patterns.
- [Enapter Rockamalg](https://developers.enapter.com/docs/tutorial/lua-complex/rockamalg) — single-script delivery with luarocks deps inlined.

### Build algorithm (deterministic)

```
1. Read `tools/manifest.txt` (sorted list of source files in concatenation order)
2. For each file in manifest order:
   a. Read with explicit LF normalization (strip CRLF if present)
   b. Strip per-file shebang lines if any
   c. Wrap module body in `do ... end` to localize `local` declarations
      EXCEPT for src/webbanking_header.lua (must stay top-level for MoneyMoney)
      EXCEPT for src/entry.lua (callbacks must be at top level / globals)
   d. Inline-comment a `-- === src/<name>.lua === ` banner for readability
3. Resolve inter-module references via shared top-level locals:
   - Each module declares its public API as a top-level local table:
     `local M_auth = {}` ... `function M_auth.exchange_token(...) end`
   - All `M_<name>` locals are predeclared in `src/webbanking_header.lua`
     above the per-module `do ... end` blocks
4. Concatenate with single `\n` between sections
5. Append SHA256 sentinel as a comment for build-verification:
   `-- build-sha256: <hex>`
6. Write to `build/PayPal POS.lua`
```

### Determinism guarantees

- **No timestamps embedded** — no `os.date()`, no `os.time()` in the build output.
- **Stable file order** — explicit `tools/manifest.txt`, NOT a directory walk (filesystem ordering is non-portable).
- **LF only** — `tools/build.lua` normalizes line endings to `\n` regardless of host (matches `SOURCE_DATE_EPOCH` philosophy from [reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/)).
- **No git SHA in artifact** — the SHA goes in the **GitHub Release notes**, not in the file, so the same source produces the same bytes regardless of commit.
- **No environment leakage** — the build script does not read `$USER`, `$HOSTNAME`, paths beyond `src/`.

### Verification

`tools/build.lua --verify` re-runs the build and compares SHA256 of `build/PayPal POS.lua` against the sentinel. CI runs this on every push to catch non-determinism early.

### Manifest ordering (proposed)

```
src/webbanking_header.lua      # WebBanking{} + module-local predeclarations
src/log.lua                    # depended on by everything below
src/errors.lua
src/i18n.lua
src/model.lua
src/http.lua                   # depends on log, errors
src/auth.lua                   # depends on http, errors
src/pagination.lua             # depends on http
src/purchases.lua              # depends on http, pagination, model
src/payouts.lua                # depends on http, pagination, model
src/balance.lua                # depends on http, model
src/mapping.lua                # depends on model, i18n
src/entry.lua                  # the MoneyMoney callbacks; tail of file
```

---

## 4. Build & release pipeline

### `.github/workflows/ci.yml` — every push / PR

```
Trigger: push (any branch), pull_request
Jobs:
  1. setup:
     - actions/checkout@v4 with fetch-depth: 0
     - leafo/gh-actions-lua@v10  (Lua 5.4 — matches MoneyMoney runtime)
     - leafo/gh-actions-luarocks@v4
     - luarocks install busted luacov luacheck
  2. lint:    luacheck src/ spec/ tools/
  3. test:    busted --coverage spec/
              luacov  (generate coverage report)
              fail if coverage < 85% on src/  (excludes build/, spec/, tools/)
  4. build-verify:
              lua tools/build.lua
              lua tools/build.lua --verify    # second run, must hash-match
  5. status:  upload coverage XML as artifact (Codecov-compatible)
```

### `.github/workflows/release.yml` — tag-triggered

```
Trigger: push tag matching v*.*.*  (annotated, GPG-signed)
Jobs:
  1. verify-signed-tag:
     - git verify-tag $GITHUB_REF_NAME  (against committed allowed_signers)
  2. setup:    same as ci.yml
  3. lint+test: rerun CI to gate the release
  4. build:    lua tools/build.lua
  5. checksum: sha256sum "build/PayPal POS.lua" > "build/PayPal POS.lua.sha256"
  6. release:
     - softprops/action-gh-release@v2
     - files: build/PayPal POS.lua, build/PayPal POS.lua.sha256
     - body: auto-generated from CHANGELOG.md + git shortlog
     - draft: false
     - prerelease: based on tag suffix (e.g. -rc1)
```

### Hardening notes

- **Sign tags, not commits in the workflow** — the workflow only **verifies** the human-signed tag; we do not give Actions a GPG key.
- **Pin actions by SHA**, not by `@v4`, in `release.yml` (supply-chain hygiene).
- **`SOURCE_DATE_EPOCH`** is set to the tag's commit timestamp before build, even though our amalgamator does not embed timestamps — defense in depth for any future tooling.
- **No secrets in `ci.yml`** — only `release.yml` consumes `GITHUB_TOKEN` (default scope: just enough to create a release).

---

## 5. Auth & session lifecycle

### Where the access token lives

**Decision: `LocalStorage`** (MoneyMoney's per-extension persistent KV), not a module-level upvalue, not the `account` table.

Rationale:

- The `TrueLayer` extension ([code](https://github.com/miracle2k/moneymoney-truelayer/blob/master/TrueLayer.lua)) uses `LocalStorage.accessToken / refreshToken / expiresAt` — confirmed convention for OAuth2 extensions.
- A module-level local is **lost between MoneyMoney invocations**. Each refresh is a fresh interpreter context for the extension callbacks; module-level state cannot be relied on. (Trading212 and Union Investment also rely on per-invocation state but they keep the *connection cookie* in a local, then re-login each time — wasteful for OAuth2.)
- The `account` table is returned from `ListAccounts` and shown in MoneyMoney's UI. Stuffing secrets there risks leaking via UI export.

### Token cache shape (`LocalStorage`)

```lua
LocalStorage.zettle = {
  access_token  = "eyJraWQ...",     -- the bearer token
  expires_at    = 1718553600,       -- os.time() + expires_in - 60s safety margin
  obtained_at   = 1718546400,       -- for diagnostics in debug log (never logged in full)
  client_id     = "<uuid>",         -- public, not secret; published in PayPal POS dev portal
}
```

The **API key itself is NOT stored in `LocalStorage`** — MoneyMoney already persists it via its credentials store (the user typed it into the InitializeSession2 dialog). We re-derive `access_token` from the credentials array each time it expires.

### Token lifetime (cited)

From [iZettle API docs](https://github.com/iZettle/api-documentation/blob/master/authorization.md) and the [JWT-assertion-grant guide](https://github.com/iZettle/api-documentation/blob/master/oauth-api/user-guides/set-up-app-authorisation/set-up-authorisation-assertion-grant.md):

> "The access token is valid for 7200 seconds." (= 120 minutes = 2 hours)

Response shape:

```json
{ "access_token": "eyJ...", "expires_in": 7200 }
```

> "When you get a new access token, you might also get a new refresh token (invalidating any previously issued refresh token)."

### Grant type (cited)

```
POST https://oauth.zettle.com/token
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer
&client_id={client_id}
&assertion={API_KEY}
```

Important: **the API key IS the JWT assertion**. The extension does NOT sign anything itself; the merchant generates the API key in the PayPal POS developer portal and pastes it into MoneyMoney. This is the JWT-bearer grant defined in [RFC 7523](https://tools.ietf.org/html/rfc7523).

### Refresh strategy

**Cache aggressively. Re-authenticate on demand.**

```
function ensure_access_token():
  if LocalStorage.zettle and LocalStorage.zettle.expires_at > os.time() + 60:
    return LocalStorage.zettle.access_token

  # cache miss or near expiry
  body = POST oauth.zettle.com/token  (grant_type=jwt-bearer, assertion=API_KEY)
  if status == 200:
    LocalStorage.zettle = {
      access_token = body.access_token,
      expires_at   = os.time() + body.expires_in - 60,
      obtained_at  = os.time(),
      client_id    = client_id,
    }
    return LocalStorage.zettle.access_token
  elif status == 400 and body.error == "invalid_grant":
    LocalStorage.zettle = nil
    error(LoginFailed)   # global MoneyMoney constant; surfaces "Login failed" to user
  else:
    return localized_error_string  # transient — see § 7
```

We use the **JWT-bearer grant on every cache miss** rather than the refresh-token grant. Reasons:

- The API key is always available (MoneyMoney persists it), so we never need to chain refresh tokens.
- Avoids the refresh-token rotation footgun ("you might also get a new refresh token") which becomes a source of state-corruption bugs across concurrent refreshes.
- Equivalent in cost: both are a single POST.

### Auth failure vs transient failure

| Condition | Detection | Signal to MoneyMoney |
|-----------|-----------|----------------------|
| User pasted bad API key | `oauth.zettle.com/token` → 400 `invalid_grant` | `return LoginFailed` from `InitializeSession2` |
| Network down / DNS / TLS | `Connection():request()` raises or returns nil | `return localized("Network unavailable. Please try again.")` (a string from RefreshAccount) |
| 5xx from Zettle | http status ≥ 500 | retry with backoff (3 attempts), then return localized error string |
| 401 mid-refresh (token revoked) | http status == 401 | invalidate `LocalStorage.zettle`, retry token exchange once; on second 401 return `LoginFailed`-equivalent string from RefreshAccount |

---

## 6. Data flow per `RefreshAccount` call (textual diagram)

```
MoneyMoney calls RefreshAccount(account, since)
        │
        ▼
┌────────────────────────────────────────────────────────────────────┐
│ STEP 1 — Ensure access token                                       │
│   auth.ensure_access_token()                                       │
│     ├── LocalStorage.zettle.expires_at > now+60s ?                 │
│     │      └── HIT: return cached token                            │
│     └── MISS: POST oauth.zettle.com/token                          │
│           grant_type=jwt-bearer, assertion=<API key from creds>    │
│           store {access_token, expires_at} in LocalStorage         │
│           400 invalid_grant → return LoginFailed-equivalent string │
└────────────────────────────────────┬───────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────┐
│ STEP 2 — Fetch purchases since `since`                             │
│   purchases.fetch_since(token, since)                              │
│     loop:                                                          │
│       GET purchase.izettle.com/purchases/v2                        │
│         ?startDate=<iso(since)>                                    │
│         &limit=1000                                                │
│         &lastPurchaseHash=<cursor or nil>                          │
│       Authorization: Bearer <token>                                │
│       if 401 → invalidate token, restart STEP 1 once               │
│       if 5xx → retry up to 3x with exponential backoff             │
│       page.purchases : list of raw purchase records                │
│       cursor = page.lastPurchaseHash                               │
│       break when cursor == nil or page.purchases empty             │
│     yields: normalized [Sale, Refund, Fee] records                 │
└────────────────────────────────────┬───────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────┐
│ STEP 3 — Fetch payouts since `since`                               │
│   payouts.fetch_since(token, since)                                │
│     GET finance.izettle.com/v2/accounts/liquid/payouts             │
│         ?start=<iso(since)>&end=<iso(now)>                         │
│     paginate per Zettle finance API conventions                    │
│     yields: normalized [Payout] records                            │
└────────────────────────────────────┬───────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────┐
│ STEP 4 — Fetch current balance / pending balance                   │
│   balance.fetch_current(token)                                     │
│     GET finance.izettle.com/v2/accounts/liquid                     │
│     yields: { balance_settled, balance_pending }                   │
│                                                                    │
│   (NOTE: settlement model — confirm during implementation whether  │
│    liquid.balance maps to "settled" or includes pending. PITFALLS  │
│    flags this.)                                                    │
└────────────────────────────────────┬───────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────┐
│ STEP 5 — Map records into MoneyMoney transactions                  │
│   mapping.to_transactions(records, locale)                         │
│     for each Sale:   one transaction (gross, booked=true)          │
│                       purpose: VAT breakdown + tip if present      │
│     for each Refund: one negative transaction (refs original)      │
│     for each Fee:    one negative transaction                      │
│     for each Payout: one negative transaction                      │
│                       bookingText: t("payout_to_bank")             │
│   returns: list of {name, amount, currency, bookingDate,           │
│                     valueDate, purpose, bookingText, booked, ...}  │
└────────────────────────────────────┬───────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────┐
│ STEP 6 — Return result table                                       │
│   return {                                                         │
│     balance        = balance_settled,                              │
│     pendingBalance = balance_pending,                              │
│     transactions   = transactions,                                 │
│   }                                                                │
└────────────────────────────────────────────────────────────────────┘

Any uncaught failure along the way → return a localized error string
(NOT a Lua error; MoneyMoney's contract is string-return on failure)
```

---

## 7. Error handling

### MoneyMoney's contract (cited)

From <https://moneymoney.app/api/webbanking/>:

- `InitializeSession2` returns `LoginFailed` (a **predefined global constant**) for authentication failure, or a string for other failures, or `nil` on success.
- `RefreshAccount` returns either the result table or "eine String mit einer Fehlermeldung" — **an error message string**, displayed to the user in MoneyMoney's UI.

### Community evidence is mixed

Real extensions split between two patterns:

- **String-return** (per the spec): Union Investment uses `return LoginFailed`.
- **Throw / `error(...)`**: Trading212 uses `error(LoginFailed)` and `error("Internal server error...")`.

Both end up displaying a message to the user, but the spec is unambiguous: **return a string from `RefreshAccount`**. We follow the spec. Throwing works as a fallback (`error("...")` is caught by MoneyMoney) but bypasses our localization layer.

### Error categories & response

| Category | Source | What we return |
|----------|--------|----------------|
| Invalid API key | `oauth/token` → 400 `invalid_grant` | From `InitializeSession2`: `return LoginFailed`. From `RefreshAccount`: invalidate `LocalStorage.zettle`, then localized string `t("api_key_invalid")`. |
| Network down | `Connection:request()` raises | Localized string `t("network_unavailable")` from `RefreshAccount`. |
| Transient 5xx | After 3 retries with backoff still failing | Localized string `t("zettle_api_unavailable")`. |
| Rate limit (429) | http status == 429 | Honor `Retry-After` if present; otherwise localized string `t("rate_limited_retry_later")`. |
| Malformed JSON | `JSON():decode()` raises | Localized string `t("zettle_api_unexpected")`. PII-free; log details at `warn` level. |

### Partial-fetch policy

**Fail the whole refresh, do not return partial data.**

Rationale:

- MoneyMoney uses the `since` watermark to advance its view of "what's new." Returning a partial set on a successful refresh causes the watermark to advance past data we didn't deliver, **silently losing transactions**.
- The user-visible failure mode ("MoneyMoney shows an error and the account stays as it was") is correctable on the next refresh. The silent-loss mode is not.

Caveat: if Step 2 (purchases) succeeds and Step 3 (payouts) fails, we still abort. This is conservative; loosening to "purchases-only success" would require a more nuanced watermark, which MoneyMoney does not expose.

### Secret redaction

`log.redact(s)` is applied to **every** string before it reaches `print`:

- Removes anything matching `eyJ[A-Za-z0-9_\-\.]+` (JWT shape) — replaced with `<jwt:redacted>`.
- Removes anything matching `^[A-Za-z0-9_\-]{32,}$` token shapes from headers — replaced with `<token:redacted>`.
- Refuses to print full HTTP request bodies; only method, URL (no query params containing tokens), status code, and bytes-received.

Errors module wraps every user-facing string through `redact` too, even though it shouldn't carry secrets — defense in depth.

---

## 8. i18n module

### Decision

**Own table-driven i18n, not `MM.localizeText`.**

`MM.localizeText` only resolves keys that ship inside MoneyMoney's own bundle (per the API doc: "ein Wrapper für die Cocoa-Funktion `NSLocalizedString`"). Our own keys would return unchanged. Real extensions either accept that (Union Investment inlines German strings literally) or roll their own table.

### Module shape

```lua
local M_i18n = {}

local STRINGS = {
  de = {
    payout_to_bank        = "Auszahlung an Bankkonto",
    fee_label             = "PayPal POS Gebühr",
    refund_label          = "Erstattung",
    vat_purpose_fmt       = "%d%% MwSt: %.2f EUR",
    tip_purpose_fmt       = "Trinkgeld: %.2f EUR",
    api_key_invalid       = "PayPal POS API-Schlüssel ungültig...",
    network_unavailable   = "PayPal POS nicht erreichbar...",
    zettle_api_unavailable = "PayPal POS Server-Fehler...",
    rate_limited_retry_later = "Rate Limit erreicht...",
    zettle_api_unexpected = "Unerwartete Antwort vom PayPal POS Server...",
  },
  en = {
    payout_to_bank        = "Payout to bank account",
    fee_label             = "PayPal POS fee",
    -- ... mirror keys
  },
}

local function detect_locale()
  -- 1. honor MM.localizeText round-trip — if MM thinks the user is German,
  --    a known German MM string echoes back German; otherwise English.
  -- 2. fallback to "de" (our target audience)
  local probe = MM and MM.localizeText and MM.localizeText("OK") or ""
  if probe == "OK" or probe == "" then return "de" end   -- conservative default
  return "en"
end

function M_i18n.t(key)
  local loc = detect_locale()
  return (STRINGS[loc] and STRINGS[loc][key]) or STRINGS.de[key] or key
end
```

The default-to-German bias matches the project's primary user. A future contributor can add `fr`, `nl`, etc. by adding a key to `STRINGS`.

### Locale detection caveat

MoneyMoney does not expose `LANG` or system locale via documented API. The probe above is a heuristic; if it proves unreliable in practice, fall back to a hard-coded `"de"` and let users with non-German UIs file an issue. PITFALLS flags this.

---

## 9. Logging / debug

### Design

```lua
local M_log = {}

local LEVEL = { debug = 1, info = 2, warn = 3, error = 4 }
local active_level = LEVEL.info   -- default; debug only when env LOG_LEVEL set

local function redact(s)
  if type(s) ~= "string" then return s end
  s = s:gsub("eyJ[A-Za-z0-9_%-%.]+", "<jwt:redacted>")
  s = s:gsub("Bearer%s+[A-Za-z0-9_%-%.]+", "Bearer <redacted>")
  return s
end

local function emit(level, ...)
  if LEVEL[level] < active_level then return end
  local parts = {}
  for _, v in ipairs({...}) do parts[#parts+1] = tostring(v) end
  print(string.format("[paypal-pos][%s] %s", level, redact(table.concat(parts, " "))))
end

function M_log.debug(...) emit("debug", ...) end
function M_log.info (...) emit("info",  ...) end
function M_log.warn (...) emit("warn",  ...) end
function M_log.error(...) emit("error", ...) end
```

### When logging is acceptable

| OK to log | NEVER log |
|-----------|-----------|
| HTTP method + URL host + path | Query strings (may contain tokens or assertions) |
| HTTP status code, response size in bytes | Request/response bodies in full |
| Cursor values (e.g., `lastPurchaseHash`) | Authorization header value |
| Number of transactions mapped per category | API key (`assertion`) |
| Error categories (e.g., "invalid_grant") | `LocalStorage.zettle.access_token` |
| Module + function name on warn/error | User name, merchant ID beyond the last 4 chars |

### Default level

`info` in production, `debug` opt-in via a `WebBanking { ... debug = true }` flag (not yet decided; safer to default to `info` and document `LOG_LEVEL` env override for contributors).

---

## 10. Test architecture

### `spec/helpers/mm_mocks.lua`

Mocks MoneyMoney's globals so tests run in plain `busted`:

```lua
local M = {}

function M.setup()
  _G.MM = {
    base64       = function(s) return require("mime").b64(s) end,    -- via luarocks
    localizeText = function(s) return s end,                          -- pass-through
  }
  _G.LoginFailed = "LoginFailed"
  _G.LocalStorage = {}
  _G.Connection = function(...)
    return { request = function(self, method, url, body, headers)
      return M._next_response(method, url, body, headers)
    end }
  end
  _G.JSON = function(s)
    return { dictionary = function() return require("dkjson").decode(s) end }
  end
  _G.AccountTypeGiro = "AccountTypeGiro"
end

function M._next_response(...)
  -- per-test queue, set up by spec
end

return M
```

### Fixture strategy

- **Real responses** are captured with `mitmproxy` or a one-shot `curl` against the production API.
- **PII scrubbed before commit** via `tools/scrub_fixture.lua` — replaces merchant UUIDs with `00000000-0000-0000-0000-000000000001`, customer-card-last-4 with `0000`, names with `Test Merchant`.
- **Sandbox responses** are captured against PayPal/Zettle sandbox; committed as-is.
- Stored as JSON files under `spec/fixtures/`. Loader helper:

```lua
local function load(name)
  local f = assert(io.open("spec/fixtures/"..name..".json"))
  local s = f:read("*a") ; f:close()
  return s, require("dkjson").decode(s)
end
```

### Coverage target

**85% line coverage on `src/`** as the gate. Excluded from coverage:

- `build/` (generated)
- `spec/` (test code itself)
- `tools/` (build tooling)
- `src/entry.lua` `WebBanking{}` table literal (declarative, no branches to cover)

Tooling: `luacov` configured via `.luacov` to enforce the gate in CI:

```
include = { "src/.+%.lua$" }
exclude = { "src/webbanking_header%.lua$" }
threshold = 85
```

### Test categorization

| Tier | Speed | What | Example |
|------|-------|------|---------|
| **Unit** | <1ms each | Pure logic, no HTTP, no `LocalStorage` | `mapping_spec.lua`, `i18n_spec.lua`, `errors_spec.lua` |
| **Module** | <10ms each | Single module against `Connection` mock | `auth_spec.lua`, `purchases_spec.lua`, `pagination_spec.lua` |
| **Integration** | <100ms each | Full `RefreshAccount` end-to-end against mocked HTTP, real fixtures | `e2e_refresh_account_spec.lua` |
| **Build** | <1s | `lua tools/build.lua --verify` re-runs and hash-matches | `tools/build_spec.lua` |

No live-API tests in CI. A separate `make integration-live` target runs against the merchant's sandbox; it never runs in CI.

---

## 11. Architectural Patterns

### Pattern 1: Module-as-table-of-functions

**What:** Every `src/<name>.lua` file declares a top-level local table `M_<name>`, attaches its public functions to it, and references other modules' tables (predeclared in `webbanking_header.lua`).

**When to use:** Always, in this codebase. The amalgamator depends on it.

**Trade-offs:**
- **Pro:** No `require()` calls, so the amalgamated output Just Works in MoneyMoney's sandbox.
- **Pro:** Cross-module references are explicit (`M_http.get(...)`), making the dependency graph greppable.
- **Con:** No true module isolation — a buggy module can mutate another's table. Mitigated by `do ... end` wrapping at amalgamation time so internal locals don't leak.

**Example:**

```lua
-- src/auth.lua
function M_auth.ensure_token(api_key)
  if LocalStorage.zettle and LocalStorage.zettle.expires_at > os.time() + 60 then
    return LocalStorage.zettle.access_token
  end
  local body, status = M_http.post_form("https://oauth.zettle.com/token", {
    grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
    client_id  = M_auth.CLIENT_ID,
    assertion  = api_key,
  })
  if status == 400 then return nil, "invalid_grant" end
  if status ~= 200 then return nil, "transient" end
  local parsed = JSON(body):dictionary()
  LocalStorage.zettle = {
    access_token = parsed.access_token,
    expires_at   = os.time() + parsed.expires_in - 60,
  }
  return parsed.access_token
end
```

### Pattern 2: Pure mapping functions

**What:** `mapping.lua` contains only pure functions: `(internal_record, locale) -> moneymoney_transaction`. No I/O, no `LocalStorage`, no globals beyond what's passed in.

**When to use:** All format-conversion code. Anything that goes from "Zettle's view of the world" to "MoneyMoney's view of the world."

**Trade-offs:**
- **Pro:** Trivially testable — feed in JSON fixture, assert output table.
- **Pro:** No mocks needed for the bulk of the test suite.
- **Con:** Forces an intermediate `model.lua` shape, which costs one extra translation step compared to mapping Zettle JSON directly to MoneyMoney transactions. Worth it for testability.

### Pattern 3: Cursor iterator for pagination

**What:** `pagination.cursor_iter(fetch_page_fn, initial_cursor)` returns a Lua iterator that yields rows across page boundaries.

**When to use:** Any paginated endpoint (purchases for sure; payouts probably).

**Trade-offs:**
- **Pro:** `for sale in pagination.cursor_iter(...) do ... end` reads cleanly.
- **Pro:** Test in isolation by passing in a stub `fetch_page_fn`.
- **Con:** Lazy iteration means errors surface mid-loop. Caller must wrap in `pcall` if it needs to fail-fast.

### Pattern 4: `LocalStorage` as token cache only

**What:** Use `LocalStorage` exclusively for the access-token + expiry. Nothing else — no transaction caches, no settings, no debug counters.

**When to use:** Strict rule for this project.

**Trade-offs:**
- **Pro:** Reduces blast radius if MoneyMoney's `LocalStorage` semantics change.
- **Pro:** Easy to reason about persistent state: there's exactly one key.
- **Con:** Re-fetches `client_id` from a hard-coded constant each call (negligible cost).

---

## 12. Anti-Patterns

### Anti-Pattern 1: Storing the API key in `LocalStorage`

**What people do:** Cache the user's API key in `LocalStorage` for "performance."
**Why it's wrong:** MoneyMoney already persists it via the credentials store. Duplicating it in `LocalStorage` doubles the secret-leak surface (LocalStorage is per-extension on disk; the credentials store has tighter handling).
**Do this instead:** Read the API key from the `credentials` parameter to `InitializeSession2` each session, and pass it down to `auth.ensure_token` explicitly.

### Anti-Pattern 2: Returning partial transaction sets on Step-N failure

**What people do:** If Step 2 (purchases) succeeds but Step 3 (payouts) fails, return what we have so the user "sees something."
**Why it's wrong:** MoneyMoney advances its `since` watermark on a successful return. The missing payouts will never be re-fetched.
**Do this instead:** Any sub-step failure → return error string. Next refresh re-runs all steps with the same `since`.

### Anti-Pattern 3: Embedding the build timestamp in the artifact

**What people do:** Add a `-- built at: 2026-06-16 17:42:00` header for "traceability."
**Why it's wrong:** Breaks reproducible builds. Two CI runs on the same commit produce different bytes, defeating SHA256-attached releases.
**Do this instead:** No timestamps in the artifact. Provenance lives in the GitHub Release notes and the signed tag.

### Anti-Pattern 4: Using `MM.localizeText` for our own strings

**What people do:** `MM.localizeText("Payout to bank account")` expecting MoneyMoney to translate it.
**Why it's wrong:** `MM.localizeText` only knows strings that ship inside MoneyMoney's bundle. Our keys pass through unchanged — silently English-only.
**Do this instead:** Own `i18n.t(key)` with explicit `de`/`en` tables.

### Anti-Pattern 5: Refresh-token-grant chains

**What people do:** Use the `refresh_token` grant to renew access tokens, persisting both.
**Why it's wrong:** Zettle's docs warn that refresh-token rotation invalidates the previous refresh token. Across two near-simultaneous refreshes (e.g., user clicks "Refresh All" in MoneyMoney), one will lose the race and be left holding an invalid refresh token.
**Do this instead:** Use the JWT-bearer grant every time the cache expires. The API key is always available; no chained-token state to corrupt.

### Anti-Pattern 6: Single huge `.lua` file as the source of truth

**What people do:** Edit `PayPal POS.lua` directly (the way every other MoneyMoney extension does).
**Why it's wrong:** Defeats testability, makes per-concern PR review impossible, slows refactoring, and violates the project's CI/coverage requirements.
**Do this instead:** Source of truth is `src/*.lua`. The flat file is generated. README's "How to install" tells users to grab the artifact from GitHub Releases, never to copy from `src/`.

---

## 13. Integration Points

### External services

| Service | Endpoint | Integration pattern | Notes |
|---------|----------|---------------------|-------|
| Zettle OAuth | `https://oauth.zettle.com/token` | POST form-encoded JWT-bearer grant | Token valid 7200 s. Error `invalid_grant` → bad API key. |
| Zettle Purchase API | `https://purchase.izettle.com/purchases/v2` | GET with `lastPurchaseHash` cursor + `limit` (max 1000) + `startDate`/`endDate` | Up to 3 years of history. |
| Zettle Finance API | `https://finance.izettle.com/v2/accounts/liquid/...` | GET; balance + transactions + payouts on the liquid account | Liquid account = settled + about-to-be-paid-out. |

### Internal boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `entry.lua` ↔ everything | Direct function call to `M_*` tables | Only `entry.lua` sees MoneyMoney's call conventions. Pure adapter. |
| `auth` ↔ `LocalStorage` | Direct global access | The ONLY module allowed to read/write `LocalStorage`. |
| `http` ↔ `Connection` | Direct global access | The ONLY module allowed to call `Connection()`. All other modules go through `M_http`. |
| `purchases`/`payouts`/`balance` ↔ `http` | `M_http.get_json(token, url)` | Token passed explicitly, never via thread-local. |
| `mapping` ↔ `i18n` | `M_i18n.t(key)` only | `mapping` does NOT format dates or amounts; uses pure helpers from `model`. |
| `log` ↔ `print` | Wrapped only | Direct `print` outside `M_log` is a luacheck warning. |

---

## 14. Suggested Build Order (roadmapper input)

This dependency-ordered sequence gives early test feedback on the pure logic and defers MoneyMoney-integration until the supporting layers are stable.

```
Phase A — Foundation (no MoneyMoney, no HTTP):
  1. model.lua        — record shapes
  2. i18n.lua         — string tables
  3. errors.lua       — error constants
  4. log.lua + redact — redaction helpers
  5. tools/build.lua  — amalgamator (so we know the deliverable can build)
  6. spec/helpers/mm_mocks.lua — testing infrastructure
  → milestone: `busted` runs, redaction is covered, build produces a stub artifact.

Phase B — Network layer (mocked HTTP):
  7. http.lua         — Connection wrapper, retries, backoff
  8. pagination.lua   — cursor iterator
  9. auth.lua         — JWT-bearer grant against oauth.zettle.com (mocked)
  → milestone: full auth round-trip in tests with fixtures; cache hit/miss covered.

Phase C — API integration (still mocked HTTP):
  10. purchases.lua   — list + cursor
  11. payouts.lua     — finance payouts
  12. balance.lua     — liquid balance
  13. mapping.lua     — record → MoneyMoney transaction (PURE function, fixture-driven)
  → milestone: each module yields correctly shaped data from real (scrubbed) fixtures.

Phase D — MoneyMoney wiring:
  14. webbanking_header.lua — WebBanking{} declaration + predeclared module locals
  15. entry.lua             — callbacks (SupportsBank, InitializeSession2, ListAccounts,
                              RefreshAccount, EndSession)
  16. e2e_refresh_account_spec.lua — full RefreshAccount with mocked HTTP + LocalStorage
  → milestone: artifact loads in MoneyMoney; bad API key shows LoginFailed; good API key
    lists the account and returns transactions.

Phase E — CI/CD plumbing:
  17. .github/workflows/ci.yml      — lint + test + build-verify
  18. .luacheckrc, .busted, .luacov — tool configs
  19. .github/workflows/release.yml — tag-triggered release
  20. tools/build.lua --verify       — determinism check in CI

Phase F — Localization & docs:
  21. README.md (DE primary, EN fallback)
  22. docs/adr/0001-amalgamator.md, 0002-localstorage-token-cache.md, etc.
  23. CONTRIBUTING.md
  24. CHANGELOG.md
  25. First release: v0.1.0 (sandbox-verified, not yet production-validated)
```

Phases A–D are necessarily sequential (each depends on the previous). Within each phase, the listed items are roughly parallelizable, but watch for the noted cross-dependencies (e.g., `http` must exist before `auth` can call it).

---

## 15. Scaling Considerations

This is a per-user, single-account extension. "Scaling" here means **transaction volume per merchant per refresh**, not number of users.

| Scale | Adjustments needed |
|-------|---------------------|
| Hobby merchant: < 100 sales / month | Default `limit=1000` plus single page is fine. |
| Active merchant: ~1,000 sales / month | Still one or two pages. Default config OK. |
| Heavy merchant: ~10,000+ sales / month | Multiple pages of purchases per refresh. Confirm `lastPurchaseHash` works reliably; monitor refresh duration against MoneyMoney's ~30s soft timeout. |
| First-time refresh after 3-year `since=0` | Could be tens of thousands of records. Recommend documenting in README: "Erste Synchronisation kann mehrere Minuten dauern." |

### Scaling priorities

1. **First bottleneck:** HTTP round-trip count on first-ever refresh. Mitigation: use `limit=1000` (the API max). Cost: one POST per oauth + ceil(N/1000) GETs per refresh.
2. **Second bottleneck:** JSON parse memory if a single page has very large embedded receipts. Mitigation: stream-parse if MoneyMoney's `JSON()` supports it; otherwise document the limitation.
3. **Third bottleneck:** MoneyMoney's per-call timeout. Mitigation: if a refresh approaches 25s, return what we have for the *current* watermark only after fully completing the in-progress page (preserving the "fail whole refresh" invariant by NOT advancing `since` ourselves — MoneyMoney handles that based on the latest transaction's `bookingDate`).

---

## Sources

### MoneyMoney WebBanking API

- [MoneyMoney WebBanking API reference](https://moneymoney.app/api/webbanking/) — `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `EndSession`, `LoginFailed`, transaction field list, `MM.localizeText`, `print` semantics.

### MoneyMoney community extensions (architecture prior art)

- [`miracle2k/moneymoney-truelayer`](https://github.com/miracle2k/moneymoney-truelayer/blob/master/TrueLayer.lua) — OAuth2 token persistence via `LocalStorage.accessToken / refreshToken / expiresAt`. The canonical reference for our token-storage decision.
- [`teal-bauer/moneymoney-ext-trading212`](https://github.com/teal-bauer/moneymoney-ext-trading212/blob/main/Trading212.lua) — `error(LoginFailed)` pattern (alternative to `return LoginFailed`); HTTP retry conventions.
- [`joafeldmann/moneymoney-union-investment`](https://github.com/joafeldmann/moneymoney-union-investment/blob/master/Union%20Investment.lua) — Standard file structure for a single-file extension; `MM.localizeText` usage example; `return LoginFailed` pattern.

### Zettle / PayPal POS API

- [iZettle authorization.md](https://github.com/iZettle/api-documentation/blob/master/authorization.md) — `expires_in: 7200`; refresh-token rotation warning.
- [iZettle JWT-assertion-grant guide](https://github.com/iZettle/api-documentation/blob/master/oauth-api/user-guides/set-up-app-authorisation/set-up-authorisation-assertion-grant.md) — exact grant-type URI and request shape; "API key is a JWT assertion."
- [Zettle Purchase API — fetch list](https://developer.zettle.com/docs/api/purchase/user-guides/fetch-purchases/fetch-a-list-of-purchases) — `lastPurchaseHash` cursor; `limit` (max 1000); `startDate`/`endDate`; 3-year history.
- [Zettle Finance API overview](https://developer.zettle.com/docs/api/finance/overview) — liquid account, payouts, balance.
- [iZettle finance fetch-account-transactions-v2.md](https://github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-account-transactions-v2.md) — `GET /v2/accounts/liquid/transactions?start=…&end=…`.
- [RFC 7523 — JWT Profile for OAuth 2.0 Client Authentication and Authorization Grants](https://tools.ietf.org/html/rfc7523) — the grant type spec.

### Lua amalgamation prior art

- [`siffiejoe/lua-amalg`](https://github.com/siffiejoe/lua-amalg) — canonical Lua amalgamator. Studied; rejected for this project because the output expects `require`, while MoneyMoney loads as a top-level script.
- [`drauschenbach/lua-amalg-redis`](https://github.com/drauschenbach/lua-amalg-redis), [`topfreegames/lua-amalg-redis`](https://github.com/topfreegames/lua-amalg-redis) — variations for hosts that load Lua as a script, not as modules. Validates the "ship your own host-specific amalgamator" pattern.
- [Exasol — Lua part 3: Handling modules](https://exasol.my.site.com/s/article/Exasol-loves-Lua-part-3-Handling-modules) — discussion of host-loaded vs `require`-loaded Lua modules.
- [Enapter Rockamalg](https://developers.enapter.com/docs/tutorial/lua-complex/rockamalg) — single-script delivery patterns.

### Reproducible builds

- [reproducible-builds.org — SOURCE_DATE_EPOCH](https://reproducible-builds.org/docs/source-date-epoch/) — the standardized env var; we set it for defense in depth even though our amalgamator doesn't embed timestamps.
- [Docker — Reproducible builds with GitHub Actions](https://docs.docker.com/build/ci/github-actions/reproducible-builds/) — workflow-level pattern reference.

---

*Architecture research for: MoneyMoney PayPal POS / Zettle community extension.*
*Researched: 2026-06-16. Confidence: HIGH (all critical contracts cited from primary sources; amalgamation strategy supported by community prior art).*
