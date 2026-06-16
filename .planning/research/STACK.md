# Stack Research

**Domain:** MoneyMoney community extension (Lua) wrapping the PayPal POS / Zettle Public API
**Researched:** 2026-06-16
**Confidence:** HIGH for shipped Lua artifact, HIGH for test/CI toolchain, HIGH for Zettle auth, HIGH for Purchase API shape, MEDIUM for Finance API base host, HIGH for install path.

---

## Executive Recommendation

Ship a **single hand-written `Extension.lua`** authored against **MoneyMoney's embedded Lua 5.4 interpreter**, distributed as one file via GitHub Releases. Build/test/CI runs **outside** MoneyMoney on stock Lua 5.4 plus a thin mock of MoneyMoney's global helpers (`Connection`, `JSON`, `MM.*`). Auth is the **Zettle assertion-grant OAuth2 flow** (`POST https://oauth.zettle.com/token`, `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`, `assertion=<API_KEY>`, `client_id=<client_id>`); data comes from the **Purchase API** (`https://purchase.izettle.com/purchases/v2`) and the **Finance API** (`/v2/accounts/liquid/transactions`).

**Hard rule confirmed by the spec:** zero non-stdlib Lua in the shipped `.lua`. No `require`, no LuaRocks, no `lua-cjson`, no `lua-resty-http`. Only `Connection()`, `JSON()`, `HTML()`, `PDF()`, `MM.*` and Lua 5.4 stdlib.

---

## Recommended Stack

### Core Technologies (shipped in `Extension.lua`)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Lua | **5.4.x** (matches MoneyMoney's embedded interpreter; current MoneyMoney update bundles Lua 5.4.8) | Implementation language of the extension | MoneyMoney runs every extension inside its sandboxed embedded Lua 5.4 interpreter. Using 5.4 idioms (integer `//`, bitwise `&|~`, `goto`) is therefore safe — but should be used sparingly to keep the file readable and to ease external CI execution. **Confidence: HIGH.** Sources: lunarmodules/luabinaries discussion, lua.org 5.4 manual, MoneyMoney 2026 release notes (Lua 5.4.8 bump). |
| MoneyMoney `Connection()` | Built-in | HTTP/S client + cookie jar + HTML/XHR session | Only sanctioned way to make HTTPS calls from an extension. Signature: `connection:request(method, url[, postContent, postContentType, headers]) -> content, charset, mimeType, filename, headers`; shortcuts `connection:get(url)` and `connection:post(url, body[, contentType])`. Use `connection.useragent` / `connection.language` for headers. |
| MoneyMoney `JSON()` | Built-in | JSON parse + serialise | `JSON(rawString):dictionary()` returns a Lua table; `JSON():set(table):json()` serialises. Means we never need `lua-cjson` in the shipped file. |
| MoneyMoney `MM.*` helpers | Built-in | base64, hex digests (`MM.sha256` etc.), HMAC, encoding conversion, `MM.localizeText`, `MM.printStatus`, `MM.time()` | All needed primitives (JWT decode pre-checks, currency-minor-unit math, ISO-8601 manipulation) are covered. No need to ship a hashing library. |
| `WebBanking{}` registration table | Built-in | Registers the extension with MoneyMoney | Required fields: `version` (number), `country` (e.g. `"de"`), `url`, `services = {"PayPal POS"}`, `description`. Bank code matching is done in `SupportsBank(protocol, bankCode)`. |

### Required Entry Points (in `Extension.lua`)

| Function | Signature | Returns | Mandatory |
|----------|-----------|---------|-----------|
| `SupportsBank` | `(protocol, bankCode)` | `boolean` | YES — gate the extension on `protocol == ProtocolWebBanking` and `bankCode == "PayPal POS"` (chosen service identifier shown in MoneyMoney's "Add account" UI). |
| `InitializeSession2` | `(protocol, bankCode, step, credentials, interactive)` | `nil` on success, `LoginFailed`, error string, or challenge object | YES — preferred over `InitializeSession` because PayPal POS uses an API-key model (single named credential field), and `InitializeSession2`'s `credentials` array gives full control over labels (German: "API-Key"). |
| `ListAccounts` | `(knownAccounts)` | `{account, ...}` array or error string | YES — returns one `AccountTypeGiro` with `accountNumber` derived from the Zettle `userId` / organisation UUID and `currency = "EUR"`. |
| `RefreshAccount` | `(account, since)` | `{ balance=…, transactions={…} }` or error string | YES — `since` is a POSIX timestamp; respect it and request purchases with `startDate` set to that moment so MoneyMoney's incremental refresh works correctly. |
| `EndSession` | `()` | `nil` or error string | YES — close the `Connection` and discard the access token from module state. |

### Supporting Libraries (test/CI only — NEVER in the shipped `.lua`)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `busted` | **2.3.0** (latest LuaRocks, ~5 months old as of 2026-06) | Unit-test framework. Supports Lua 5.4. | Mandatory for the test sandbox. Tests `require` the extension source after injecting a `MoneyMoneyMocks` module that defines `Connection`, `JSON`, `HTML`, `PDF`, `MM`, `WebBanking`, `ProtocolWebBanking`, `AccountTypeGiro` etc. |
| `luacheck` | **1.2.0** (latest LuaRocks, released by lunarmodules; predecessor 1.1.x line still common) | Static analyser/linter. Native Lua 5.4 support. | Mandatory CI step. Provide `.luacheckrc` declaring MoneyMoney globals as `read-globals` so they don't show as undefined. |
| `luacov` | **0.16.0** (latest LuaRocks) | Line coverage | Mandatory. Threshold floor in CI: 85 % overall, 100 % on pure logic modules (formatters, mappers). Coverage measured against the *unconcatenated* sources for readability of reports. |
| `lua-cjson` | n/a — **do NOT ship** | Fast JSON encoder/decoder | Only needed if a test fixture loader wants to mutate JSON outside the extension's own code. Prefer using MoneyMoney's `JSON()` mock backed by `dkjson` or a hand-rolled fixture loader to stay portable. |
| `dkjson` | 2.7+ | Pure-Lua JSON, used by the test harness's `JSON()` mock | Cleaner than `lua-cjson` because it has no C dependency — keeps `apt-get install` step minimal on GitHub-hosted runners. |
| `mocha` / `nock`-style HTTP recorder | n/a | We do **not** mock at the HTTP-socket level — we mock at the `Connection()` boundary. | Recorded fixtures live as JSON files under `spec/fixtures/`. |

### Development Tools / Tooling Chain

| Tool | Purpose | Notes |
|------|---------|-------|
| **`leafo/gh-actions-lua@v13`** (Apr 2026) | Provisions a chosen Lua release in GitHub Actions | Supports 5.1.5 / 5.2.4 / 5.3.5 / 5.4.1 / 5.5.0 + LuaJIT variants. Pin `luaVersion: "5.4"` to match MoneyMoney. |
| **`leafo/gh-actions-luarocks@v6.1.0`** (Apr 2026) | Installs LuaRocks paired with the action above | Used in CI to `luarocks install busted luacheck luacov dkjson`. |
| **`softprops/action-gh-release@v2`** (latest stable as of 2026-06) | Publishes the release with attached `.lua` + `SHA256SUMS` | Use `prerelease`/`draft` flags driven by tag pattern (`vX.Y.Z` vs `vX.Y.Z-rc.N`). |
| **GPG / git** | Sign commits and tags (`git tag -s`) | Maintainer's key `FDE07046A6178E89ADB57FD3DE300C53D8E18642` configured. Enable branch protection rule: `Require signed commits`. |
| **Conventional Commits + commitlint** | Pre-merge enforcement | A `commitlint.yml` workflow on PRs is sufficient — no husky / Node toolchain inside the repo, just the GitHub Action. |
| **Dependabot** | Bump tooling deps | Targets: GitHub Action versions and `.github/workflows`. LuaRocks pinning is done in `.luarocks.lock` analogue (a `Rockfile`-style list under `spec/`). |
| **Markdown only for docs** | README, CONTRIBUTING, ADRs | No static-site generator. MADR-format ADRs under `docs/adr/`. German README primary, English README and contributor docs alongside. |

---

## Installation (toolchain on a developer's machine)

```bash
# macOS — Lua 5.4 + LuaRocks
brew install lua@5.4 luarocks

# Test framework + linter + coverage
luarocks --lua-version=5.4 install busted
luarocks --lua-version=5.4 install luacheck
luarocks --lua-version=5.4 install luacov
luarocks --lua-version=5.4 install dkjson

# Optional but recommended for local linting parity with CI
luarocks --lua-version=5.4 install argparse
```

**Project layout (proposed — not yet on disk):**

```
.
├── src/
│   └── Extension.lua        # the shipped artifact (single file)
├── spec/
│   ├── support/
│   │   └── moneymoney_mocks.lua   # Connection/JSON/HTML/PDF/MM mocks
│   ├── fixtures/
│   │   ├── purchases_v2_page1.json
│   │   ├── purchases_v2_page2.json
│   │   ├── finance_liquid_transactions.json
│   │   └── oauth_token_ok.json
│   ├── support_spec.lua
│   ├── auth_spec.lua
│   ├── purchases_spec.lua
│   ├── finance_spec.lua
│   └── integration_spec.lua
├── docs/
│   ├── adr/
│   │   ├── 0001-record-architecture-decisions.md
│   │   └── 000N-…
│   ├── README.de.md
│   └── README.md
├── .luacheckrc
├── .busted
├── .github/
│   └── workflows/
│       ├── ci.yml           # lint + test + coverage on push/PR
│       └── release.yml      # on vX.Y.Z tag: build + SHA256 + GH release
├── LICENSE
└── README.md → symlink/copy of docs/README.de.md
```

---

## PayPal POS / Zettle API surface (verified)

| Concern | Value | Confidence |
|---------|-------|------------|
| Token endpoint | `POST https://oauth.zettle.com/token` | **HIGH** — confirmed by `iZettle/api-documentation/authorization.md` and current `developer.zettle.com` portal. |
| Grant type | `urn:ietf:params:oauth:grant-type:jwt-bearer` | **HIGH** — same source. |
| Required form params | `grant_type`, `client_id`, `assertion` (the API key, which is itself a JWT) | **HIGH** |
| Content-Type | `application/x-www-form-urlencoded` | HIGH |
| Token TTL | `expires_in: 7200` seconds (2 h); **no refresh token** for assertion grant — re-request when expired | HIGH |
| Auth header for resource calls | `Authorization: Bearer <access_token>` | HIGH |
| Purchase API base | `https://purchase.izettle.com` (NOT `purchase.zettle.com` — host kept under the iZettle domain post-rebrand) | **HIGH** — confirmed by community references and current Zettle docs portal example URLs. |
| List purchases | `GET /purchases/v2` | HIGH |
| Purchase query params | `startDate` (UTC, inclusive — accepts `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM`), `endDate` (exclusive), `limit` (1–1000, default smaller), `descending` (bool), `lastPurchaseHash` (opaque cursor returned in the previous page) | HIGH |
| Pagination | Cursor-based via `lastPurchaseHash`; iterate until the response's `purchases` array is empty or shorter than `limit` | HIGH |
| Purchase JSON top-level fields | `purchaseUUID1`, `amount` (minor units, integer), `vatAmount`, `country`, `currency`, `timestamp` (ISO-8601), `created`, `purchaseNumber`, `globalPurchaseNumber`, `userDisplayName`, `userId`, `organizationId`, `refund` (bool), `refunded` (bool), `refundsPurchaseUUID1`, `refundedByPurchaseUUIDs1`, `products[]`, `discounts[]`, `serviceCharge`, `payments[]`, `groupedVatAmounts`, `gpsCoordinates`, `receiptCopyAllowed`, `references`, `cashRegister` | HIGH |
| Per-purchase tip | Per the spec, **tip lives inside `payments[].gratuityAmount`** (integer minor units), **not** as a top-level field on the purchase | HIGH — important: aggregate across payments to render a per-sale tip line in `purpose`. |
| Per-purchase VAT | `vatAmount` top-level + per-line `products[].vatPercentage`/`rowTaxableAmount` + breakdown in `groupedVatAmounts` | HIGH |
| Per-purchase fee | Per the spec the Zettle commission for each payment is in `payments[].commission.totalAmount` (and `commission.vatAmount`, `commission.vatRate`); however, the **per-payout fee booking** is most cleanly modelled via the Finance API's `PAYMENT_FEE` transaction type | HIGH — both paths exist; pick Finance API for booking, Purchase API for display metadata. |
| Finance API base host | `https://finance.izettle.com` (parallel to `purchase.izettle.com`) | **MEDIUM** — strongly implied by Zettle's documented host convention and confirmed in multiple third-party integrations, but the official developer.zettle.com portal currently quotes only relative paths. Verify in Phase 1 with a real call. |
| Finance: list account transactions | `GET /v2/accounts/liquid/transactions?start={ISO}&end={ISO}&limit={1..1000}&offset={N}&includeTransactionType=PAYMENT&includeTransactionType=PAYMENT_FEE&includeTransactionType=PAYOUT` | HIGH for path + params, MEDIUM for host as above. |
| Finance pagination | Offset-based (`offset += limit` until response is shorter than `limit` or empty) | HIGH |
| Finance timestamp format | ISO-8601 with milliseconds + offset, e.g. `2020-09-10T09:27:28.590+0000` | HIGH |
| Finance transaction shape | `{ timestamp, amount (minor units, signed), originatorTransactionType ∈ {PAYMENT, PAYMENT_FEE, PAYOUT, …}, originatingTransactionUuid }` | HIGH |
| Rate limits | Not publicly documented in detail. Practical guidance: keep concurrent requests = 1, back off on HTTP 429, retry with jitter. | MEDIUM |
| TLS | TLS 1.2+ enforced by Zettle; `Connection()` handles this | HIGH |

---

## Existing extensions inspected (to validate idioms)

| Extension | Repo | Findings |
|-----------|------|----------|
| Payback (`payback.lua`) | `jgoldhammer/moneymoney-payback` | Classic single-file shape. `WebBanking{}` table, `SupportsBank → ProtocolWebBanking + bankCode == "Payback-Punkte"`, `InitializeSession(protocol, bankCode, username, customer, password)` form (the **5-arg legacy variant**, not the credentials-array variant). Lua 5.1-compatible idioms only — no 5.4 features needed for a simple flow. Validates that single-file shipping is the convention. |
| Trading 212 (`moneymoney-ext-trading212`) | `teal-bauer/moneymoney-ext-trading212` | Single-file `Trading212.lua` released via GitHub Actions (`release.yml` + `softprops/action-gh-release@v1`). No build/concat step — they hand-maintain the single file. Has `-- SIGNATURE:` marker that the release workflow verifies exists before publishing. Good template for our release pipeline; we will add SHA256 + GPG-signed tag verification on top. |
| Trading 212 release workflow | same repo | Pattern to follow: tag-triggered workflow, version extraction from `GITHUB_REF`, autogenerated changelog from `git log PREV..TAG`, attaches the `.lua` to the release. We extend it with: (a) reproducible build (concat from `src/`), (b) `sha256sum Extension.lua > Extension.lua.sha256`, (c) verification that the tag is GPG-signed before publishing. |
| Shoop, Qonto, Trading 212 | various | All confirm `services = {"<Display Name>"}` is what surfaces in the MoneyMoney add-account UI as the bank-code identifier. We will use `services = {"PayPal POS"}` (display the German market name). |

**No existing PayPal extension found** — neither for consumer PayPal nor for PayPal POS / Zettle — in the public MoneyMoney extensions directory (`moneymoney.app/extensions/`) nor on GitHub via topic search. This project fills a real gap. **Confidence: HIGH** for the gap claim; happy to be proven wrong by a German-language forum thread, but as of this research nothing indexable exists.

---

## Distribution / Install Path

`~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/` is correct for the **App Store / sandboxed retail build** of MoneyMoney on current macOS (15.x / 26.x). **Confidence: HIGH.**

Caveats to mention in the README:
- The MoneyMoney maintainer's recommended path is to use **Hilfe → Datenbank im Finder zeigen** (or the equivalent menu item, which on recent builds is "Erweiterungen im Finder zeigen") rather than typing the path by hand — that always opens the right folder regardless of sandbox vs non-sandbox build.
- A non-sandboxed direct-from-website build of MoneyMoney historically lived under `~/Library/Application Support/MoneyMoney/Extensions/` (no `Containers/com.moneymoney-app.retail/Data/` prefix). The German user base is overwhelmingly on the retail/App Store build, so we document the sandboxed path as primary and mention the alternative in a footnote.
- After dropping the file the user must enable **MoneyMoney → Einstellungen → Erweiterungen → "Inoffizielle Extensions erlauben"** (or equivalent current label). README must spell this out.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Hand-maintained single `Extension.lua` | Multi-file source under `src/`, concatenated to one file by a build step | If/when the extension grows past ~1500 LoC and PR diff-review starts to suffer. Then introduce a deterministic Lua concat builder (a 30-line Lua script — no Node/Python toolchain). Until then, single file = lowest cognitive overhead and simplest reproducibility. |
| `busted` 2.3 | `luaunit` | Only if you need test runs inside MoneyMoney itself (you don't — CI runs outside). `busted` has the better assertion library and BDD-style describe/it. |
| `dkjson` for the test-harness JSON mock | `lua-cjson` | Use `lua-cjson` only if you discover real performance issues parsing very large purchase fixtures. Pure-Lua `dkjson` is plenty for unit-test JSON loading and avoids a C-extension dependency on CI. |
| `leafo/gh-actions-lua` v13 | Building Lua from source in CI | Only if `leafo` ever goes unmaintained. As of Apr 2026 it released v13 — actively maintained. |
| `softprops/action-gh-release@v2` | `actions/upload-release-asset` (deprecated) + manual `gh release create` | The `softprops` action is the de-facto standard in the Lua/MoneyMoney extension ecosystem. Sticking with it gives free body-rendering, asset hashing, and Markdown changelog handling. |
| Assertion grant (jwt-bearer) | OAuth2 Authorisation-Code flow | Only if the user wants to install once and connect multiple Zettle merchants under one OAuth app. **Explicitly out of scope per PROJECT.md** — assertion grant matches "one extension instance = one merchant + paste API key once". |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Any external Lua module (`require "socket.http"`, `require "ssl.https"`, `require "cjson"`, `require "resty.http"`, …) **in the shipped file** | MoneyMoney's embedded interpreter has no LuaRocks, no `package.path` for non-stdlib modules, no LuaSocket. Calls will error at load time. | `Connection()`, `JSON()`, `HTML()`, `PDF()`, `MM.*` exclusively. |
| Lua C modules / native deps in the shipped file | MoneyMoney's sandbox does not load `.so`/`.dylib` from extensions. | Same — built-ins only. |
| `os.execute`, `io.popen`, raw `socket` | Not available / will be blocked by the sandbox. | `Connection()`. |
| OAuth2 browser flow (authorization code grant) | The extension cannot open a browser, host a callback, or redirect. The MoneyMoney credentials dialog is the only UI surface. | Assertion grant with pre-issued API key. |
| Lua `goto` and bitwise operators "because we can" | They work on Lua 5.4 but make the source unfamiliar to MoneyMoney community contributors used to 5.1-style code. | Plain control flow. Reserve 5.4-specific features for places where they materially improve readability. |
| `lua-cjson` or any other JSON lib **inside `Extension.lua`** | Same loader issue as above. | `JSON()` built-in. |
| Logging the API key (even at DEBUG) | Security constraint in PROJECT.md. The Lua source must never `MM.printStatus` or `print` the key. | Pass through to `Connection()` only; rely on `tostring(creds)` redaction in tests. |
| `node` / `npm` / `python` / Rust in CI for the shipped artifact | Out of scope. | Pure Lua + LuaRocks via `leafo/gh-actions-{lua,luarocks}`. (Markdown-only docs; the `commitlint` GitHub Action runs in its own container.) |
| Live integration tests against production Zettle in CI | Explicitly out of scope per PROJECT.md. Burns merchant data, risks leaking secrets in logs. | Recorded fixtures + Zettle sandbox tenant. |
| Bundling `signature` field that pretends to be MRH-signed | The MoneyMoney RSA signature is maintainer-controlled; faking it would break trust and likely violate MM's distribution policy. | Ship unsigned; users enable "Inoffizielle Extensions erlauben". GPG-signed tags + reproducible build + SHA256 are the trust chain we control. |

---

## Stack Patterns by Variant

**If the project grows past ~1500 LoC of `Extension.lua`:**
- Split source under `src/` (e.g. `auth.lua`, `purchase.lua`, `finance.lua`, `mapper.lua`, `main.lua`).
- Introduce a tiny pure-Lua concat builder (`tools/build.lua`) that emits `dist/Extension.lua` by inlining each `src/*.lua` between `-- BEGIN MODULE` markers, wrapped in local `do…end` blocks, with cross-module references resolved through a single top-of-file `local M = {}` table.
- Keep CI reproducibility: the GH Actions workflow runs `lua tools/build.lua` and asserts a deterministic SHA256 against `dist/Extension.lua.sha256`.

**If a Zettle sandbox account becomes available:**
- Add a non-blocking nightly workflow that targets the sandbox with a stored secret (never the prod key) and asserts the response *shape* still matches our fixtures. Failure → open an issue, not a release block.

**If MoneyMoney's Lua interpreter ever downgrades to 5.3 in a future release:**
- Re-pin the test toolchain to Lua 5.3 (`leafo/gh-actions-lua` already supports both). Avoid Lua 5.4-only features in shipped code defensively from day one.

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `busted@2.3.0` | Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 2.x | Use 5.4 in CI to match MoneyMoney runtime semantics. |
| `luacheck@1.2.0` | Lua 5.1 – 5.4 | Configure `std = "lua54+busted"` plus `read_globals` for MoneyMoney built-ins (`Connection`, `JSON`, `HTML`, `PDF`, `MM`, `WebBanking`, `ProtocolWebBanking`, `ProtocolFinTS`, `AccountTypeGiro`, `AccountTypeCreditCard`, …). |
| `luacov@0.16.0` | Lua 5.1 – 5.4 | Run via `busted --coverage`; emit LCOV with `luacov-reporter-lcov` if you later want Codecov. |
| `leafo/gh-actions-lua@v13` | Lua 5.1.5 – 5.5.0, LuaJIT 2.0/2.1 | Pin `luaVersion: "5.4"` in workflow. |
| `leafo/gh-actions-luarocks@v6.1.0` | Pairs with the action above | Use to install busted/luacheck/luacov. |
| `softprops/action-gh-release@v2` | GitHub Actions runner ubuntu-latest / macos-latest | Either runner works; pick `ubuntu-latest` for cost + speed. |
| Zettle access token | TTL = 7200 s | Re-request when ≤60 s remain. Keep token in module-level local, cleared in `EndSession`. |
| `Connection()` timeouts | Default ~60 s per request | Stay well under the conservative 30 s "total refresh" budget from PROJECT.md by paginating eagerly and avoiding sleeping. |

---

## Sources

- MoneyMoney WebBanking API reference — https://moneymoney.app/api/webbanking/ — **HIGH** (entry points, helpers, account/transaction shapes verified directly).
- MoneyMoney official extensions directory — https://moneymoney.app/extensions/ — **HIGH** (confirmed no PayPal/Zettle entry as of 2026-06).
- iZettle/api-documentation OAuth flow — https://github.com/iZettle/api-documentation/blob/master/authorization.md — **HIGH** (token endpoint, grant_type, assertion, 7200 s TTL).
- iZettle/api-documentation API-key setup — https://github.com/iZettle/api-documentation/blob/master/oauth-api/user-guides/create-an-app/create-a-self-hosted-app/create-an-api-key.md — **HIGH**.
- Zettle Developer Portal — Purchase API list endpoint — https://developer.zettle.com/docs/api/purchase/user-guides/fetch-purchases/fetch-a-list-of-purchases — **HIGH** (query params, pagination via `lastPurchaseHash`, host `purchase.izettle.com`).
- Zettle Developer Portal — Purchase API reference / `purchase.adoc` — https://github.com/iZettle/api-documentation/blob/master/purchase.adoc — **HIGH** (JSON shape including `payments[].gratuityAmount`, `vatAmount`, `payments[].commission`).
- Zettle Developer Portal — Finance API account transactions — https://github.com/iZettle/api-documentation/blob/master/finance-api/user-guides/fetch-account-transactions-v2.md — **HIGH** for path + transaction-type filters; **MEDIUM** for the explicit host `finance.izettle.com` (verify on first live call).
- Zettle Developer Portal — Finance API overview — https://developer.zettle.com/docs/api/finance/overview — **HIGH**.
- `jgoldhammer/moneymoney-payback` — https://github.com/jgoldhammer/moneymoney-payback/blob/master/payback.lua — **HIGH** (idiomatic single-file extension shape).
- `teal-bauer/moneymoney-ext-trading212` — https://github.com/teal-bauer/moneymoney-ext-trading212 — **HIGH** (release workflow pattern, single-file shipping).
- `lunarmodules/busted` — https://luarocks.org/modules/lunarmodules/busted — **HIGH** (2.3.0 current).
- `lunarmodules/luacheck` — https://luarocks.org/modules/lunarmodules/luacheck — **HIGH** (1.2.0 current).
- `keplerproject/luacov` — https://luarocks.org/modules/hisham/luacov — **HIGH** (0.16.0 current).
- `leafo/gh-actions-lua` — https://github.com/leafo/gh-actions-lua — **HIGH** (v13.0.0, Apr 2026).
- `leafo/gh-actions-luarocks` — https://github.com/leafo/gh-actions-luarocks — **HIGH** (v6.1.0, Apr 2026).

---

## Open Items to Verify in Phase 1 (Hello-World call)

1. Confirm `finance.izettle.com` as the live host for `/v2/accounts/liquid/transactions` (or pivot to whatever DNS the developer portal currently emits in its Postman bundle). **MEDIUM** → **HIGH** after the first real call.
2. Confirm whether `Connection():request` follows redirects automatically when Zettle issues an interim 302 on the OAuth token endpoint (legacy behaviour suggests yes, but verify).
3. Confirm the exact display-name in the MoneyMoney "Add account" dialog for `services = {"PayPal POS"}` — the user-facing label should be unambiguous in German UI.
4. Confirm whether MoneyMoney's `JSON():set(t):json()` round-trips integer-typed amounts faithfully (Zettle uses minor-unit integers; misclassification as floats would be a bookkeeping bug).

---

*Stack research for: MoneyMoney community extension wrapping the PayPal POS / Zettle Public API*
*Researched: 2026-06-16*
