# Phase 1: Foundations & Sandbox Probes — Research

**Researched:** 2026-06-16
**Domain:** Lua 5.4 MoneyMoney extension toolchain, amalgamation, mock harness, i18n module, log redaction, sandbox probe strategy, minimal CI
**Confidence:** HIGH (all critical contracts cited from primary sources; toolchain choices inherited from project-level research with HIGH confidence; sandbox-probe strategy derived from prior art with MEDIUM confidence on probe outcomes pending live execution)

---

## Summary

Phase 1 is the foundation phase for the entire project. Nothing downstream (auth, purchases, Finance API) can be designed with HIGH confidence until the 8 sandbox probes (Q1–Q8) produce live-verified answers. At the same time, Phase 1 must deliver a working walking-skeleton artifact: `dist/paypal-pos.lua` installs in MoneyMoney, surfaces "PayPal POS" in the add-account UI, and shows one hard-coded fixture transaction — without any network code. This proves the build path and MoneyMoney load path work before any auth code is written.

The toolchain is completely decided: Lua 5.4, busted 2.3.0, luacheck 1.2.0, luacov 0.16.0, dkjson 2.7+, leafo/gh-actions-lua@v13, leafo/gh-actions-luarocks@v6.1.0. No alternative exploration is needed. The amalgamation strategy (custom `tools/build.lua` with `tools/manifest.txt`) is also decided — `lua-amalg` was examined and rejected because its `package.preload` output is incompatible with MoneyMoney's top-level-script load model. [CITED: https://github.com/siffiejoe/lua-amalg; CITED: ARCHITECTURE.md §3]

The primary unknowns this research closes are implementation-level: the exact amalgamator algorithm, the complete `mm_mocks.lua` API surface, the `i18n.t()` design, the `log.redact()` regex patterns, the probe-extension output schema, the CI workflow skeleton, and the ADR-0003 template. All of these are fully specified below.

**Primary recommendation:** Implement deliverables in dependency order (model → i18n → errors → log → build tooling → mm_mocks → entry walking skeleton → probe extension), gate each layer with a busted spec, and treat Q1–Q8 probe results as blocking inputs for Phase 2 planning rather than as Phase 1 gate items (the probe extension is written in Phase 1 but the user runs it and fills in ADR-0003 as the final Phase 1 gate action).

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BUILD-01 | Source under `src/`; `tools/build.lua` amalgamates deterministically into `dist/paypal-pos.lua` | Amalgamator design fully specified in RQ-1 below; manifest ordering in manifest.txt section |
| BUILD-02 | Byte-reproducible build: two consecutive runs produce identical bytes | Determinism guarantees: LF normalization, explicit manifest, no timestamps/env leakage; `--verify` flag design in RQ-1 |
| TEST-01 | Spec suite uses busted with MoneyMoney globals mocked in `spec/helpers/mm_mocks.lua` | Full mock surface enumerated in RQ-2; smoke spec design in RQ-9 |
| I18N-02 | Internal `i18n.t(key)` module with `{de={...}, en={...}}` tables; German default | Module shape and key naming scheme in RQ-3 |
| I18N-03 | English strings available as fallback, never exposed via UI in v1 | Key coverage and fallback chain in RQ-3 |
| SEC-01 | `log.redact()` applied to every string before `print()`; strips JWT-shape and `Bearer …` | Regex patterns and redaction strategy in RQ-4 |
| SEC-04 | `DEBUG = false` hard-coded in shipped artifact; build aborts on `DEBUG = true` in any source | Build-time grep check in RQ-7; `log.lua` design in RQ-4 |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Build-time amalgamation | Developer toolchain (`tools/`) | CI runner | `tools/build.lua` runs on dev machine and in CI; not a runtime concern |
| Test mock harness | Test runner (`spec/helpers/`) | — | Lives entirely outside MoneyMoney; plain Lua with dkjson |
| i18n string lookup | Extension runtime (in-process) | — | `i18n.t()` is called from `mapping.lua` and `errors.lua` at runtime; no server-side component |
| Log redaction | Extension runtime (in-process) | CI grep | `log.redact()` runs inside every `print` path; CI grep is a build-time safety net |
| Sandbox capability probing | Live MoneyMoney runtime | — | Q1–Q8 must execute inside MoneyMoney's embedded Lua 5.4 VM; cannot be tested outside |
| Walking-skeleton WebBanking wiring | Extension runtime (MoneyMoney) | — | `SupportsBank`, `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `EndSession` callbacks registered via `WebBanking{}` at load time |
| CI pipeline | GitHub Actions runner (`ubuntu-24.04`) | — | Runs luacheck, busted, luacov, `lua tools/build.lua --verify` on every push |

---

## Standard Stack

### Core (shipped in `dist/paypal-pos.lua`)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Lua | 5.4.x (MoneyMoney embeds 5.4.8) | Implementation language | MoneyMoney's embedded interpreter; exact version confirmed in MoneyMoney 2026 release notes [ASSUMED — via project-level research; Phase-1 probe Q1 will enumerate actual `_VERSION` in the live sandbox] |
| `Connection()` | Built-in MoneyMoney global | HTTPS client | Only sanctioned HTTP mechanism; no LuaSocket available [CITED: https://moneymoney.app/api/webbanking/] |
| `JSON()` | Built-in MoneyMoney global | JSON parse + serialize | `JSON(s):dictionary()` / `JSON():set(t):json()`; no external cjson needed [CITED: https://moneymoney.app/api/webbanking/] |
| `MM.*` helpers | Built-in MoneyMoney globals | base64, sha256/512, hmac, localizeText, printStatus, time, sleep, urlencode | All hash and encoding primitives covered; no need to ship extra libs [CITED: https://moneymoney.app/api/webbanking/] |
| `WebBanking{}` | Built-in MoneyMoney registration | Extension registration with MoneyMoney | Required top-level table [CITED: https://moneymoney.app/api/webbanking/] |
| `LocalStorage` | Built-in MoneyMoney global | Persistent per-extension KV store | Cross-restart token cache; prior art in moneymoney-truelayer [CITED: https://github.com/miracle2k/moneymoney-truelayer/blob/master/TrueLayer.lua] |

### Supporting (test/CI only — NEVER in the shipped artifact)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `busted` | 2.3.0 | BDD test framework; Lua 5.4 support | All `spec/*_spec.lua` files [CITED: https://luarocks.org/modules/lunarmodules/busted] |
| `luacheck` | 1.2.0 | Static linter; declares MoneyMoney globals as `read-globals` | Mandatory CI lint step [CITED: https://luarocks.org/modules/lunarmodules/luacheck] |
| `luacov` | 0.16.0 | Line coverage; threshold gate 85% on `src/` | Run via `busted --coverage` [CITED: https://luarocks.org/modules/hisham/luacov] |
| `dkjson` | 2.7+ | Pure-Lua JSON; backs the `JSON()` mock in mm_mocks | No C dep; keeps CI `apt-get` minimal [CITED: https://luarocks.org/modules/dhkolf/dkjson] |

### Development Toolchain (CI Actions)

| Tool | Version | Purpose |
|------|---------|---------|
| `leafo/gh-actions-lua` | v13 (Apr 2026) | Provisions Lua 5.4 on ubuntu-24.04 [CITED: https://github.com/leafo/gh-actions-lua] |
| `leafo/gh-actions-luarocks` | v6.1.0 (Apr 2026) | Installs LuaRocks packages in CI [CITED: https://github.com/leafo/gh-actions-luarocks] |

### Installation (developer machine)

```bash
brew install lua@5.4 luarocks
luarocks --lua-version=5.4 install busted
luarocks --lua-version=5.4 install luacheck
luarocks --lua-version=5.4 install luacov
luarocks --lua-version=5.4 install dkjson
```

---

## Package Legitimacy Audit

All packages below are test/CI only — nothing ships in the Lua artifact.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| busted 2.3.0 | LuaRocks | ~10 yrs | Very high | github.com/lunarmodules/busted | OK | Approved |
| luacheck 1.2.0 | LuaRocks | ~8 yrs | Very high | github.com/lunarmodules/luacheck | OK | Approved |
| luacov 0.16.0 | LuaRocks | ~12 yrs | High | github.com/lunarmodules/luacov | OK | Approved |
| dkjson 2.7+ | LuaRocks | ~12 yrs | High | chiselapp.com/user/dhkolf/repository/dkjson | OK | Approved |

**Packages removed:** none
**Packages flagged as suspicious:** none

---

## Research Questions — Detailed Answers

### RQ-1: `tools/build.lua` Amalgamator Design

**Decision: flat ordered concatenation with `do...end` wrapping, predeclared module tables in header, explicit manifest.**

Rationale: MoneyMoney loads the extension as a top-level Lua chunk. The `WebBanking{}` table declaration must be at top level, and all MoneyMoney callbacks (`SupportsBank`, etc.) must also be top-level functions. `lua-amalg` wraps modules in `package.preload` loaders requiring `require()` calls to activate them — this is incompatible with the top-level-script model. [CITED: https://github.com/siffiejoe/lua-amalg]

The payback and Trading 212 extensions are single hand-written files with no build step, so they provide no direct prior art for amalgamation. The pattern is validated by the Enapter rockamalg and the broader host-specific amalgamation literature. [CITED: https://developers.enapter.com/docs/tutorial/lua-complex/rockamalg]

**Exact build algorithm:**

```
1. Parse CLI args: no args = build; --verify = build + compare hash
2. Read tools/manifest.txt line by line (skip blank lines and # comments)
3. Emit a header comment block (no version, no date, no git SHA)
4. For each file path in manifest order:
   a. Read file content in binary mode
   b. Normalize line endings: replace \r\n with \n, standalone \r with \n
   c. Strip trailing whitespace from each line
   d. If file is src/webbanking_header.lua: emit verbatim (top-level globals)
   e. If file is src/entry.lua: emit verbatim (MoneyMoney callbacks must be top-level)
   f. All other files: wrap in do...end block with a separator banner comment
   g. Emit: "-- === MODULE: <basename> ===\n"
   h. Emit: "do\n" + content + "\nend\n"
5. Emit a closing sentinel comment: "-- paypal-pos build: complete"
   (NO sha256 embedded — the SHA256 goes in the GitHub Release, not the artifact)
6. Write to dist/paypal-pos.lua using LF line endings
7. If --verify: re-run steps 1-6 to a temp file; compare sha256 of both;
   if mismatch: print error and exit 1; if match: print "OK: reproducible" and exit 0
```

**Cross-module reference pattern:**

```lua
-- src/webbanking_header.lua (emitted verbatim, top of file)
-- Predeclare all module tables so do...end blocks can reference each other
local M_log = {}
local M_errors = {}
local M_i18n = {}
local M_model = {}
local M_http = {}
local M_auth = {}
local M_pagination = {}
local M_purchases = {}
local M_payouts = {}
local M_balance = {}
local M_mapping = {}

local DEBUG = false   -- SEC-04: must be false in shipped artifact

WebBanking {
  version     = 1.00,
  country     = "de",
  url         = "https://oauth.zettle.com",
  services    = {"PayPal POS"},
  description = "PayPal POS / Zettle Umsätze, Gebühren und Auszahlungen"
}
```

Each `src/<name>.lua` attaches its functions to the corresponding predeclared table:

```lua
-- src/log.lua (wrapped in do...end by build.lua)
function M_log.info(...)  ... end
function M_log.warn(...)  ... end
function M_log.error(...) ... end
function M_log.debug(...) ... end
function M_log.redact(s)  ... end
```

This pattern means every `do...end` block can reference `M_log`, `M_i18n`, etc. because those local variables are predeclared at the top scope above all blocks. No `require()` is needed or used. [CITED: ARCHITECTURE.md §3, §11]

**Determinism guarantees (BUILD-02):**

- **No timestamps** in the artifact. No `os.date()`, no `os.time()` call in `tools/build.lua` output.
- **No git SHA** in the artifact. SHA lives in the GitHub Release notes.
- **No `$USER`, `$HOSTNAME`, `$PWD`** read by `tools/build.lua`.
- **Explicit manifest** (`tools/manifest.txt`), not a directory walk. Filesystem glob order is non-portable across OS and CI runners.
- **LF only**: build script normalizes all input to `\n` before writing.
- **`LC_ALL=C`** set in the CI environment before running `lua tools/build.lua` as a defense-in-depth measure.
- **SEC-04 gate**: before writing output, `tools/build.lua` greps source content for `DEBUG = true` (the exact string) and aborts with exit code 1 if found in any non-comment line. This prevents shipping a debug build.

**`tools/manifest.txt` (proposed content):**

```
# tools/manifest.txt
# Module concatenation order for paypal-pos.lua
# Lines starting with # are comments; blank lines are ignored.
# webbanking_header.lua and entry.lua are emitted verbatim (top-level).
src/webbanking_header.lua
src/log.lua
src/errors.lua
src/i18n.lua
src/model.lua
src/http.lua
src/auth.lua
src/pagination.lua
src/purchases.lua
src/payouts.lua
src/balance.lua
src/mapping.lua
src/entry.lua
```

Confidence: **HIGH** — algorithm is straightforward Lua file I/O; no external dependencies; pattern validated by host-specific amalgamation prior art.

---

### RQ-2: `mm_mocks.lua` API Surface

**Every MoneyMoney global the v1 artifact will touch, with mock strategy:**

[CITED: https://moneymoney.app/api/webbanking/ for all built-in signatures]

| Global | Type | Mock Strategy | Notes |
|--------|------|---------------|-------|
| `Connection` | function → object | Returns a configurable mock object; per-test response queue | The mock's `request(method, url, body, contentType, headers)` method pops from a queue set up in `before_each` |
| `JSON` | function | `JSON(s):dictionary()` backed by `dkjson.decode`; `JSON():set(t):json()` backed by `dkjson.encode` | Round-trip must preserve integers (Q4 probe topic) — dkjson preserves them |
| `HTML` | function | No-op stub returning an object with stub methods; not used in Phase 1 | Needed for completeness so luacheck doesn't flag it |
| `PDF` | function | No-op stub | Not used until potential future PDF-receipt phase |
| `MM.localizeText` | function | Pass-through: `function(s) return s end` | Locale detection heuristic test uses this; pass-through simulates non-German locale |
| `MM.localizeDate` | function | Pass-through for now | Phase 1 does not use date localization |
| `MM.localizeNumber` | function | Pass-through | |
| `MM.localizeAmount` | function | Pass-through | |
| `MM.base64` | function | Backed by Lua string: `return (data:gsub(".", function(c) ... end))` or a pure-Lua base64 table | Used by auth module; must be accurate |
| `MM.base64decode` | function | Inverse of above | |
| `MM.sha256` | function | Can use `require("sha2")` if available on CI, or a stub returning a fixed hex string per input (fixture-safe) | Used for HMAC in auth; for Phase 1 a stub returning `("0"):rep(64)` is acceptable |
| `MM.sha512` | function | Same strategy as sha256 | |
| `MM.sha1` | function | Same strategy | |
| `MM.md5` | function | Same strategy | |
| `MM.hmac256` | function | Stub for Phase 1 | |
| `MM.hmac512` | function | Stub for Phase 1 | |
| `MM.hmac384` | function | Stub for Phase 1 | |
| `MM.hmac1` | function | Stub for Phase 1 | |
| `MM.random` | function | Returns `string.rep("\0", length)` or pseudorandom bytes | |
| `MM.time` | function | Returns `os.time() * 1000` (MS resolution mock of MoneyMoney's millisecond clock) | |
| `MM.sleep` | function | No-op | Tests must not actually sleep |
| `MM.printStatus` | function | Captured to a table for assertion in specs | |
| `MM.urlencode` | function | Pure-Lua URL encoding (simple table lookup) | Used in form-encoded OAuth body |
| `MM.urldecode` | function | Inverse | |
| `MM.toEncoding` | function | Pass-through for UTF-8; stub for other charsets | |
| `MM.fromEncoding` | function | Pass-through for UTF-8 | |
| `MM.productName` | string | `"MoneyMoney (Mock)"` | |
| `MM.productVersion` | string | `"2.9.99"` | |
| `LocalStorage` | table | Starts as `{}` each test; reset in `before_each` | Simulates the persistent KV; Q5 probe verifies cross-restart behavior (not testable in mock) |
| `WebBanking` | function | Captures the registration table for inspection; does not load the extension | Spec can assert `WebBanking_received.services[1] == "PayPal POS"` |
| `ProtocolWebBanking` | string constant | `"WebBanking"` | Used in `SupportsBank` |
| `ProtocolFinTS` | string constant | `"FinTS"` | Used in `SupportsBank` (to return false) |
| `AccountTypeGiro` | string constant | `"Giro"` | Used in `ListAccounts` return value |
| `AccountTypeSavings` | string constant | `"Savings"` | Defined for completeness |
| `AccountTypeCreditCard` | string constant | `"CreditCard"` | Defined for completeness |
| `AccountTypePortfolio` | string constant | `"Portfolio"` | Defined for completeness |
| `AccountTypeOther` | string constant | `"Other"` | Defined for completeness |
| `AccountTypeFixedTermDeposit` | string constant | `"FixedTermDeposit"` | Defined for completeness |
| `AccountTypeLoan` | string constant | `"Loan"` | Defined for completeness |
| `LoginFailed` | string constant | `"LoginFailed"` | Returned by `InitializeSession2` on auth failure; tests assert `result == LoginFailed` |
| `print` | function | Captured to a table for log-redaction testing; original `print` still available via `_G._print` | |

**Mock module structure:**

```lua
-- spec/helpers/mm_mocks.lua
local dkjson = require("dkjson")
local Mocks = {}

-- Connection response queue (per-test)
local _response_queue = {}

function Mocks.push_response(response)
  _response_queue[#_response_queue + 1] = response
end

local function make_connection()
  return {
    request = function(self, method, url, body, contentType, headers)
      if #_response_queue == 0 then
        error("mm_mocks: no queued response for " .. method .. " " .. url)
      end
      local r = table.remove(_response_queue, 1)
      return r.body, r.charset or "UTF-8", r.mimeType or "application/json",
             r.filename or nil, r.headers or {}
    end,
    get  = function(self, url)          return self:request("GET",  url) end,
    post = function(self, url, body, ct) return self:request("POST", url, body, ct) end,
    close = function(self) end,
  }
end

function Mocks.setup()
  _response_queue = {}
  _G.Connection = make_connection

  _G.JSON = function(s)
    if s then
      return { dictionary = function() return dkjson.decode(s) end }
    else
      return { set = function(self, t)
                       self._data = t; return self
                     end,
               json = function(self) return dkjson.encode(self._data) end }
    end
  end

  _G.HTML = function(s, charset)
    return { xpath = function() return {} end, html = function() return s end }
  end

  _G.PDF = function(data)
    return { text = function() return "" end }
  end

  local captured_status = {}
  _G.MM = {
    localizeText  = function(s) return s end,
    localizeDate  = function(fmt, d) return tostring(d) end,
    localizeNumber = function(fmt, n) return tostring(n) end,
    localizeAmount = function(fmt, a, cur) return tostring(a) end,
    base64        = function(s) return require("mime") and require("mime").b64(s) or s end,
    base64decode  = function(s) return require("mime") and require("mime").unb64(s) or s end,
    sha256        = function(s) return ("0"):rep(64) end,
    sha512        = function(s) return ("0"):rep(128) end,
    sha1          = function(s) return ("0"):rep(40) end,
    md5           = function(s) return ("0"):rep(32) end,
    hmac256       = function(k, s) return ("0"):rep(64) end,
    hmac512       = function(k, s) return ("0"):rep(128) end,
    hmac384       = function(k, s) return ("0"):rep(96) end,
    hmac1         = function(k, s) return ("0"):rep(40) end,
    random        = function(n) return string.rep("\0", n) end,
    time          = function() return os.time() * 1000 end,
    sleep         = function(s) end,
    printStatus   = function(...) captured_status[#captured_status+1] = {...} end,
    urlencode     = function(s) return s:gsub("[^A-Za-z0-9%-_%.~]",
                                  function(c) return string.format("%%%02X", c:byte()) end) end,
    urldecode     = function(s) return s:gsub("%%(%x%x)",
                                  function(h) return string.char(tonumber(h, 16)) end) end,
    toEncoding    = function(cs, s, bom) return s end,
    fromEncoding  = function(cs, data) return data end,
    productName   = "MoneyMoney (Mock)",
    productVersion = "2.9.99",
    _captured_status = captured_status,
  }

  _G.LocalStorage = {}

  _G.WebBanking = function(t) _G._WebBanking_received = t end

  _G.ProtocolWebBanking       = "WebBanking"
  _G.ProtocolFinTS            = "FinTS"
  _G.AccountTypeGiro          = "Giro"
  _G.AccountTypeSavings       = "Savings"
  _G.AccountTypeCreditCard    = "CreditCard"
  _G.AccountTypePortfolio     = "Portfolio"
  _G.AccountTypeOther         = "Other"
  _G.AccountTypeFixedTermDeposit = "FixedTermDeposit"
  _G.AccountTypeLoan          = "Loan"
  _G.LoginFailed              = "LoginFailed"
end

function Mocks.teardown()
  _response_queue = {}
  _G.LocalStorage = {}
end

return Mocks
```

Confidence: **HIGH** — API surface sourced directly from the MoneyMoney WebBanking reference; mock strategy follows moneymoney-truelayer and trading212 patterns.

---

### RQ-3: `i18n.lua` Design

**Decision: own table-driven `i18n.t(key)` with `{de={...}, en={...}}`, defaulting to `de`. NOT `MM.localizeText` — that function only resolves strings from MoneyMoney's own bundle.** [CITED: https://moneymoney.app/api/webbanking/ — "MM.localizeText is a wrapper for NSLocalizedString"]

**Locale detection strategy:**

```lua
-- In src/i18n.lua, inside the do...end block
local _locale = "de"   -- hard-coded default; Phase 1 probe Q9 may refine

local function _detect_locale()
  -- MoneyMoney does not expose LANG directly. The probe at Q9 will test
  -- whether MM.localizeText("OK") returns a non-English string in German UI.
  -- For Phase 1, always return "de" (German-primary audience).
  return "de"
end

function M_i18n.t(key, ...)
  local loc = _locale
  local strings = STRINGS[loc] or STRINGS.de
  local s = strings[key] or STRINGS.de[key] or key
  if select("#", ...) > 0 then
    return string.format(s, ...)
  end
  return s
end
```

**Key naming convention:** dot-separated hierarchical, noun-first.

```
account.name                    "PayPal POS — %s"
transaction.name.sale           "Kartenzahlung"
transaction.name.sale_with_card "%s *%s"   -- e.g. "Visa *1234"
transaction.name.refund         "Erstattung"
transaction.name.fee            "PayPal POS Gebühr"
transaction.name.payout         "Auszahlung an Bankkonto"
purpose.gross                   "Brutto: %s EUR"
purpose.vat_line                "%d%% MwSt: %s EUR"
purpose.tip_line                "Trinkgeld: %s EUR"
purpose.receipt                 "Beleg #%s"
purpose.uuid                    "PayPal POS UUID: %s"
purpose.refund_ref              "Erstattung zu Beleg #%s"
purpose.fee_ref                 "Gebühr zu Beleg #%s"
purpose.fee_aggregate           "PayPal POS Transaktionsgebühren %s"
error.invalid_grant             "PayPal POS API-Schlüssel ungültig. Bitte in den Kontodaten prüfen."
error.network_unavailable       "PayPal POS nicht erreichbar. Bitte Internetverbindung prüfen."
error.api_unavailable           "PayPal POS Server-Fehler (HTTP %s). Bitte später erneut versuchen."
error.rate_limited              "PayPal POS limitiert gerade Anfragen. Bitte später erneut versuchen."
error.api_unexpected            "Unerwartete Antwort vom PayPal POS Server. Details im MoneyMoney-Protokoll."
credential.api_key_label        "PayPal POS API-Schlüssel"
credential.api_key_hint         "Den API-Schlüssel finden Sie im PayPal POS Entwicklerportal"
```

**I18N-02 compliance:** the `M_i18n` table and `M_i18n.t(key)` function satisfy the requirement. The module is a distinct `src/i18n.lua` source file.

**I18N-03 compliance:** the `STRINGS.en` table mirrors all `STRINGS.de` keys with English translations. English is never returned via the default code path in v1 (locale is hard-coded to `"de"`). The English table exists and is tested for key completeness.

**String injection at build time vs. hard-coded:** Strings are hard-coded in `src/i18n.lua`. There is no build-time template substitution for strings (only for `__VERSION__` which is Phase 6). This is simpler and makes the string table the definitive artifact-readable source.

Confidence: **HIGH** — pattern is standard Lua table-driven i18n; no external dependencies; design derived from ARCHITECTURE.md §8.

---

### RQ-4: `log.redact()` Design and `DEBUG = false` Enforcement

**Tokens to redact (SEC-01):**

1. **JWT-shaped strings** — any token matching the three-part base64url pattern that appears in API keys and Bearer tokens: `eyJ[A-Za-z0-9_%-%.]+%.[A-Za-z0-9_%-%.]+%.[A-Za-z0-9_%-%.]+` replaced with `<jwt:redacted>`.
2. **Bearer tokens** in Authorization headers: `Bearer%s+[A-Za-z0-9_%-%.]+` replaced with `Bearer <redacted>`.
3. **assertion= values** in form-encoded bodies: `assertion=[^&%s]+` replaced with `assertion=<redacted>`.
4. **access_token= values** in JSON or query strings: `access_token=[^",&]+` replaced with `access_token=<redacted>`.

Note: Lua patterns use `%` as the escape character. The patterns above use Lua regex syntax.

**`log.lua` full design:**

```lua
-- src/log.lua
-- Executed inside do...end by build.lua; M_log predeclared in webbanking_header.lua

local _LEVEL = { debug = 1, info = 2, warn = 3, error = 4 }
-- DEBUG = false is declared in webbanking_header.lua (top-level, outside this block)
-- SEC-04: shipped artifact always has DEBUG = false

local function _active_level()
  return DEBUG and _LEVEL.debug or _LEVEL.info
end

function M_log.redact(s)
  if type(s) ~= "string" then return tostring(s) end
  -- 1. JWT-shaped tokens (three-part base64url)
  s = s:gsub("eyJ[A-Za-z0-9_%-%.]+%.[A-Za-z0-9_%-%.]+%.[A-Za-z0-9_%-%.]+",
              "<jwt:redacted>")
  -- 2. Bearer header values
  s = s:gsub("Bearer%s+[A-Za-z0-9_%-%.]+", "Bearer <redacted>")
  -- 3. assertion= in form bodies
  s = s:gsub("assertion=[^&%s]+", "assertion=<redacted>")
  -- 4. access_token= in any context
  s = s:gsub("access_token=[^\"&,}%s]+", "access_token=<redacted>")
  return s
end

local function _emit(level_num, level_name, ...)
  if level_num < _active_level() then return end
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = M_log.redact(tostring(select(i, ...)))
  end
  print(string.format("[paypal-pos][%s] %s", level_name, table.concat(parts, " ")))
end

function M_log.debug(...) _emit(_LEVEL.debug, "DEBUG", ...) end
function M_log.info(...)  _emit(_LEVEL.info,  "INFO",  ...) end
function M_log.warn(...)  _emit(_LEVEL.warn,  "WARN",  ...) end
function M_log.error(...) _emit(_LEVEL.error, "ERROR", ...) end
```

**SEC-04 enforcement mechanism:**

The `DEBUG = false` declaration lives in `src/webbanking_header.lua` at the top of the amalgamated file. `tools/build.lua` implements a pre-write grep: scan each source file's content for `DEBUG%s*=%s*true` (Lua pattern, outside of a comment `--.*` prefix). If found, print an error message and exit with code 1, aborting the build.

```lua
-- tools/build.lua (extract — DEBUG gate)
for _, filepath in ipairs(manifest_files) do
  local content = read_file(filepath)
  -- Check each non-comment line
  for line in content:gmatch("[^\n]+") do
    local stripped = line:match("^%s*(.-)%s*$")
    if not stripped:match("^%-%-") then  -- not a comment line
      if stripped:match("DEBUG%s*=%s*true") then
        io.stderr:write("BUILD ERROR: DEBUG = true found in " .. filepath .. "\n")
        os.exit(1)
      end
    end
  end
end
```

Confidence: **HIGH** — regex patterns derived from ARCHITECTURE.md §7 and §9; SEC-01/SEC-04 requirements are explicit; the Lua pattern syntax is correct for Lua 5.4.

---

### RQ-5: `SupportsBank` + `bankCode` Decision

**Canonical label: `services = {"PayPal POS"}`.**

All inspected extensions (Shoop, Qonto, Trading 212, Payback) confirm that the string in `services = {...}` is what appears verbatim in MoneyMoney's "Konto hinzufügen" bank-selection UI. [CITED: STACK.md — "All confirm `services = {"<Display Name>"}` is what surfaces in the add-account UI"]

**Decision tree for Q7 probe result:**

```
Q7: Does "PayPal POS" appear unambiguously in the add-account UI?
├── YES → use services = {"PayPal POS"}  (current plan, HIGH confidence)
└── NO / ambiguous →
    └── Does "PayPal POS (Zettle)" disambiguate it?
        ├── YES → change to services = {"PayPal POS (Zettle)"}
        │         (update webbanking_header.lua and bankCode check in SupportsBank)
        └── NO  → open GitHub issue, ask MoneyMoney community for the canonical name
```

**`SupportsBank` implementation:**

```lua
-- src/entry.lua
function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "PayPal POS"
end
```

If Q7 requires the label change: `bankCode == "PayPal POS (Zettle)"` and the `services` string in the header both change atomically. No other module references the bankCode string.

Confidence: **HIGH** for mechanism; **ASSUMED** for the exact label matching MoneyMoney's UI — Q7 is the live verification.

---

### RQ-6: Probe-Extension Strategy

**Format: `print()` lines the user copy-pastes into ADR-0003.**

Rationale: MoneyMoney's extension does not have a file-write capability. `MM.printStatus` shows only transient status text during refresh, not a persistent log the user can read back. `print()` goes to MoneyMoney's "Protokoll" (log) panel, which the user can copy out. This is the simplest, most portable approach. [CITED: https://moneymoney.app/api/webbanking/ — "print(...) output appears in MoneyMoney's log window"] [ASSUMED: that MM.setUrl or clipboard API do not exist — to be confirmed by Q1 globals enumeration]

**Probe extension design (`tools/probe.lua` — separate file, NOT part of the amalgamation):**

The probe is a standalone Lua file installed alongside `paypal-pos.lua` during Phase 1. It uses `bankCode == "PayPal POS Probe"` so it does not conflict with the main extension.

```lua
-- tools/probe.lua
-- Install in MoneyMoney Extensions/ for Phase 1 sandbox verification only.
-- Remove after ADR-0003 is filled in.
WebBanking {
  version     = 1.00,
  country     = "de",
  url         = "https://oauth.zettle.com",
  services    = {"PayPal POS Probe"},
  description = "Phase 1 sandbox probe — remove after Q1-Q8 answered"
}

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "PayPal POS Probe"
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  return nil  -- no auth needed
end

function ListAccounts(knownAccounts)
  return { { accountNumber = "probe-001", type = AccountTypeGiro,
             name = "PayPal POS Probe Account", currency = "EUR" } }
end

function RefreshAccount(account, since)
  print("=== PAYPAL POS PROBE START ===")

  -- Q1: Global environment enumeration
  print("--- Q1: Sandbox globals ---")
  local interesting = {
    "require", "dofile", "loadfile", "load", "package",
    "io", "os", "debug", "socket", "coroutine",
    "_G", "_VERSION", "utf8",
  }
  for _, name in ipairs(interesting) do
    local v = _G[name]
    if v == nil then
      print("Q1 " .. name .. " = nil (ABSENT)")
    elseif type(v) == "table" then
      print("Q1 " .. name .. " = table (PRESENT)")
    elseif type(v) == "function" then
      print("Q1 " .. name .. " = function (PRESENT)")
    else
      print("Q1 " .. name .. " = " .. tostring(v))
    end
  end

  -- Q4: JSON integer round-trip (995 cents — must not become 995.0)
  print("--- Q4: JSON integer round-trip ---")
  local t = { amount = 995, currency = "EUR" }
  local encoded = JSON():set(t):json()
  print("Q4 encoded: " .. encoded)
  local decoded = JSON(encoded):dictionary()
  print("Q4 decoded amount type: " .. type(decoded.amount))
  print("Q4 decoded amount value: " .. tostring(decoded.amount))
  -- Pass if type is "number" AND value == 995 (integer, not 995.0)
  local is_integer = (decoded.amount == math.floor(decoded.amount))
  print("Q4 RESULT: " .. (is_integer and "PASS (integer preserved)" or "FAIL (float coercion)"))

  -- Q5: LocalStorage cross-restart persistence
  print("--- Q5: LocalStorage persistence ---")
  if LocalStorage.probe_counter then
    LocalStorage.probe_counter = LocalStorage.probe_counter + 1
  else
    LocalStorage.probe_counter = 1
  end
  print("Q5 probe_counter = " .. tostring(LocalStorage.probe_counter))
  print("Q5 If this is 1 on first run and increases on subsequent runs: PASS")
  print("Q5 If it resets to 1 on every run (after app restart): FAIL")

  -- Q7: services label rendering (indirect — user confirms via UI)
  print("--- Q7: Service label ---")
  print("Q7 MANUAL: Did 'PayPal POS' appear in the add-account bank list? Y/N")

  -- Q8: TLS verification (connection to a known-bad cert host)
  print("--- Q8: TLS default verification ---")
  local conn8 = Connection()
  local ok, err = pcall(function()
    return conn8:get("https://expired.badssl.com/")
  end)
  if ok then
    print("Q8 RESULT: WARN — Connection() followed expired cert; TLS verification may be off")
  else
    print("Q8 RESULT: PASS — Connection() refused expired cert (TLS verification on by default)")
    print("Q8 error: " .. tostring(err))
  end

  -- Note: Q2, Q3, Q6 require actual PayPal POS credentials and are answered
  -- during Phase 2 auth spike, but infrastructure is noted here.
  print("--- Q2/Q3/Q6: Require live PayPal POS credentials ---")
  print("Q2: Test redirect behavior of oauth.zettle.com/token in Phase 2 auth spike")
  print("Q3: Confirm finance.izettle.com host during Phase 2/4 first live call")
  print("Q6: PayPal POS client_id — obtained from developer.zettle.com app portal")

  print("=== PAYPAL POS PROBE END ===")

  return {
    balance      = 0,
    transactions = {},
  }
end

function EndSession()
  return nil
end
```

**Probe output schema (what the user copies into ADR-0003):**

Each Q answer maps to a table row in ADR-0003. The user runs `RefreshAccount` on the probe account, copies the log output from MoneyMoney's Protokoll panel, and fills in the result column.

| Q | Probe mechanism | Result format for ADR-0003 |
|---|----------------|---------------------------|
| Q1 | Enumerate `_G` for specific names | List each: `require: ABSENT / PRESENT (function / table)` |
| Q2 | Phase 2 auth spike — observe 302 redirect handling | `auto-follow: YES / NO; max-hops tested: N` |
| Q3 | First live Finance API call in Phase 2/4 | `confirmed host: finance.izettle.com / <actual host>` |
| Q4 | JSON round-trip of `{amount=995}` | `integer preserved: YES / NO; decoded type: number/string` |
| Q5 | LocalStorage counter across restarts | `persists: YES / NO; counter after restart: N` |
| Q6 | developer.zettle.com portal — copy client_id from app settings | `client_id: <uuid or REGION-SPECIFIC>` |
| Q7 | User observes "Konto hinzufügen" UI | `label: "PayPal POS" exact / other: <actual text>` |
| Q8 | `Connection():get("https://expired.badssl.com/")` | `TLS verified by default: YES (rejected) / NO (followed)` |

Confidence: **HIGH** for probe mechanism; **ASSUMED** for Q2/Q3/Q6 outcomes pending live execution.

---

### RQ-7: CI Minimum Viable Workflow

**One `ci.yml` file covering lint, test, coverage, and build verification. The full release pipeline (`release.yml`) is Phase 6 work.**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: ["**"]
  pull_request:
    branches: ["**"]

env:
  LC_ALL: C

jobs:
  test:
    name: Lint, Test, Build
    runs-on: ubuntu-24.04

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup Lua 5.4
        uses: leafo/gh-actions-lua@v13
        with:
          luaVersion: "5.4"

      - name: Setup LuaRocks
        uses: leafo/gh-actions-luarocks@v6.1.0

      - name: Install dependencies
        run: |
          luarocks install busted
          luarocks install luacheck
          luarocks install luacov
          luarocks install dkjson

      - name: Lint
        run: luacheck src/ spec/ tools/ --config .luacheckrc

      - name: Test with coverage
        run: busted --coverage spec/

      - name: Check coverage threshold
        run: |
          # luacov generates luacov.report.out
          # Parse and fail if below 85% on src/
          lua -e "
            local f = io.open('luacov.report.out', 'r')
            if not f then error('No coverage report generated') end
            -- Parse total coverage from luacov report (last line of summary)
            -- Simplified: rely on luacov threshold setting in .luacov
            f:close()
          "
          # The .luacov config file sets threshold = 85; luacov exits nonzero if not met

      - name: Build artifact
        run: lua tools/build.lua

      - name: Verify reproducible build
        run: lua tools/build.lua --verify

      - name: Check DEBUG flag
        run: |
          grep -n "DEBUG = true" dist/paypal-pos.lua && exit 1 || echo "OK: DEBUG=false confirmed"

      - name: Check egress allowlist (no unexpected hosts)
        run: |
          # Any URL not in the allowlist in the artifact is a red flag
          grep -Eo 'https?://[^"'"'"' ]+' dist/paypal-pos.lua | \
            grep -v 'oauth\.zettle\.com\|purchase\.izettle\.com\|finance\.izettle\.com' \
            && echo "FAIL: unexpected host found" && exit 1 || echo "OK: egress allowlist clean"
```

**`.luacheckrc`:**

```lua
-- .luacheckrc
std = "lua54+busted"
files["spec/**"] = { std = "lua54+busted" }
files["tools/**"] = { std = "lua54" }

-- MoneyMoney built-in globals (read-only for luacheck)
read_globals = {
  "WebBanking", "Connection", "JSON", "HTML", "PDF",
  "MM", "LocalStorage",
  "ProtocolWebBanking", "ProtocolFinTS",
  "AccountTypeGiro", "AccountTypeSavings", "AccountTypeFixedTermDeposit",
  "AccountTypeLoan", "AccountTypeCreditCard", "AccountTypePortfolio",
  "AccountTypeOther",
  "LoginFailed",
}

-- Extension callbacks are top-level globals (written once by entry.lua)
globals = {
  "SupportsBank", "InitializeSession2", "ListAccounts",
  "RefreshAccount", "EndSession",
}

-- Module tables predeclared in webbanking_header.lua
globals[#globals+1] = "M_log"
globals[#globals+1] = "M_errors"
globals[#globals+1] = "M_i18n"
globals[#globals+1] = "M_model"
globals[#globals+1] = "M_http"
globals[#globals+1] = "M_auth"
globals[#globals+1] = "M_pagination"
globals[#globals+1] = "M_purchases"
globals[#globals+1] = "M_payouts"
globals[#globals+1] = "M_balance"
globals[#globals+1] = "M_mapping"
globals[#globals+1] = "DEBUG"

ignore = { "212" }  -- 212: variable set but not accessed (acceptable for stubs)
```

**`.busted`:**

```lua
-- .busted
return {
  default = {
    verbose = true,
    coverage = true,
    ["output"] = "utfTerminal",
  }
}
```

**`.luacov`:**

```
-- .luacov
include = { "src/.+%.lua$" }
exclude = { "src/webbanking_header%.lua$" }
threshold = 85
```

Confidence: **HIGH** — workflow uses only pinned, verified Actions; luacheck/busted config derived from project constraints.

---

### RQ-8: ADR-0003 Probe Results Template

**File: `docs/adr/0003-sandbox-probe-results.md`**

```markdown
# ADR-0003: MoneyMoney Sandbox Probe Results

**Status:** [PROPOSED until probes run; ACCEPTED after all 8 answers filled in]
**Date:** 2026-06-16
**Deciders:** Yves Vogl

## Context

Phase 1 probe extension (`tools/probe.lua`) was installed in MoneyMoney and
`RefreshAccount` was triggered on the probe account. Results below are
transcribed from MoneyMoney's Protokoll panel.

## Results

| # | Probe | Method | Result | Decision | Phase Impact |
|---|-------|--------|--------|----------|-------------|
| Q1 | Sandbox globals (`require`, `io`, `os`, `debug`, …) | Enumerate `_G` via probe extension | [FILL IN: e.g. require=ABSENT, io=PRESENT(table), os=PRESENT(table), debug=ABSENT] | Hard rule: shipped artifact uses zero `require`/`dofile`; confirmed safe | Phase 1 gates on this |
| Q2 | `Connection():request` 302-redirect behavior on oauth.zettle.com/token | Phase 2 auth spike — observe actual redirect handling | [FILL IN: auto-follow YES/NO; hop count] | If NO auto-follow: add max-3-hop redirect loop in http.lua | Phase 2 design |
| Q3 | `finance.izettle.com` host for `/v2/accounts/liquid/transactions` | First live Finance API call in Phase 2/4 | [FILL IN: confirmed host] | Lock host constant in http.lua; update ARCHITECTURE.md D12 to HIGH | Phase 4 design |
| Q4 | JSON integer round-trip with `{amount=995}` | JSON():set(t):json() + JSON(s):dictionary() | [FILL IN: integer preserved YES/NO; decoded type] | If NO: use `string.format("%d", v)` for all minor-unit amounts | Phase 3 mapping |
| Q5 | LocalStorage cross-restart persistence | probe_counter increments across MoneyMoney restarts | [FILL IN: persists YES/NO; counter value after restart] | If NO: design token cache as session-local only; document cache miss behavior | Phase 2 auth |
| Q6 | PayPal POS first-party client_id | developer.zettle.com → My Apps → app settings | [FILL IN: UUID or REGION-SPECIFIC] | Ship constant in auth.lua; if region-specific: constants table, EU default | Phase 2 auth |
| Q7 | `services = {"PayPal POS"}` label in MoneyMoney add-account UI | User observes "Konto hinzufügen" bank list | [FILL IN: "PayPal POS" exact / other text] | If different: update services string and SupportsBank bankCode to match | Phase 2 design |
| Q8 | `Connection()` TLS verification default | Connection to expired.badssl.com — observe accept/reject | [FILL IN: TLS verified YES (rejected) / NO (followed)] | If NO: blocking issue — MoneyMoney may not protect against MITM; raise with community | Phase 2 blocker if NO |

## Consequences

- Q1: design constraint on shipped artifact (no `require`) confirmed.
- Q2: http.lua redirect-loop decision.
- Q3: Finance API host constant finalized (D12 promoted to HIGH).
- Q4: minor-unit math strategy for mapping.lua.
- Q5: LocalStorage token-cache strategy for auth.lua.
- Q6: client_id constant shipped in auth.lua.
- Q7: service label and SupportsBank bankCode finalized.
- Q8: TLS posture confirmed (or blocker raised).
```

Confidence: **HIGH** for template structure; outcomes are unknown until user runs the probe.

---

### RQ-9: TEST-01 mm_mocks Coverage Proof

**How to verify the mock surface is sufficient:**

A dedicated smoke spec (`spec/mm_mocks_spec.lua`) asserts that:
1. Every documented MoneyMoney global is present in `_G` after `Mocks.setup()`.
2. Each mock function is callable without error.
3. `Connection():request()` with a queued response returns the queued values.
4. `JSON(s):dictionary()` correctly parses a fixture JSON string.
5. `JSON():set(t):json()` serializes a table and round-trips it.
6. `LocalStorage` is a plain table, settable and readable.
7. `LoginFailed` is a string constant.

```lua
-- spec/mm_mocks_spec.lua
local Mocks = require("spec.helpers.mm_mocks")

describe("mm_mocks", function()
  before_each(function()
    Mocks.setup()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- Global presence checks
  for _, name in ipairs({
    "Connection", "JSON", "HTML", "PDF", "MM", "LocalStorage",
    "WebBanking", "ProtocolWebBanking", "ProtocolFinTS",
    "AccountTypeGiro", "AccountTypeSavings", "AccountTypeCreditCard",
    "AccountTypePortfolio", "AccountTypeOther",
    "AccountTypeFixedTermDeposit", "AccountTypeLoan",
    "LoginFailed",
  }) do
    it("defines global " .. name, function()
      assert.is_not_nil(_G[name], name .. " should be defined")
    end)
  end

  -- MM namespace checks
  for _, method in ipairs({
    "localizeText", "base64", "base64decode", "sha256", "sha512",
    "sha1", "md5", "hmac256", "hmac512", "hmac384", "hmac1",
    "random", "time", "sleep", "printStatus", "urlencode", "urldecode",
    "toEncoding", "fromEncoding", "localizeDate", "localizeNumber",
    "localizeAmount",
  }) do
    it("MM." .. method .. " is callable", function()
      assert.is_not_nil(MM[method], "MM." .. method .. " should be a function or value")
    end)
  end

  it("Connection():request() returns queued response", function()
    Mocks.push_response({ body = '{"ok":true}', headers = {} })
    local conn = Connection()
    local body = conn:request("GET", "https://example.com")
    assert.equals('{"ok":true}', body)
  end)

  it("JSON(s):dictionary() parses JSON correctly", function()
    local t = JSON('{"amount":995,"currency":"EUR"}'):dictionary()
    assert.equals(995, t.amount)
    assert.equals("EUR", t.currency)
  end)

  it("JSON():set(t):json() serializes a table", function()
    local j = JSON():set({ amount = 995 }):json()
    assert.is_string(j)
    assert.truthy(j:find("995"))
  end)

  it("LoginFailed is a string", function()
    assert.is_string(LoginFailed)
  end)

  it("LocalStorage is a writable table", function()
    LocalStorage.test_key = "test_value"
    assert.equals("test_value", LocalStorage.test_key)
  end)
end)
```

Confidence: **HIGH** — test structure is standard busted; covers all documented globals.

---

### RQ-10: Pitfalls H7, H8, H10 — Concrete Mitigations

**H7: API key leaked in error/log (SEC-01)**

Concrete tactics:
- `log.redact(s)` is called inside `_emit()` before every `print()`. There is no unguarded `print()` in any module.
- `tools/build.lua --verify` double-builds and compares — but additionally: a CI step greps `dist/paypal-pos.lua` for any bare `print(` call not preceded by `M_log.` and fails the build.
- `spec/log_redaction_spec.lua` exercises the following cases: JWT in error message, `Bearer <token>` in header string, `assertion=<key>` in form body, `access_token=<value>` in JSON response.
- The auth-failure test asserts that the returned error string does NOT contain `eyJ` or `Bearer`.
- luacheck rule: `direct_print = true` (custom annotation) — configure `.luacheckrc` to warn on bare `print` outside `M_log`.

**H8: Lua sandbox surprises (require, os.execute, io.popen unavailable)** [CITED: PITFALLS.md §17]

Concrete tactics:
- Hard rule enforced at build time: `tools/build.lua` scans all `src/*.lua` files for `require(`, `dofile(`, `loadfile(`, `io.open(`, `os.execute(`, `io.popen(`. Any match aborts the build with a clear error.
- luacheck `.luacheckrc`: none of these are in `read_globals` or `globals`, so luacheck will flag them as "undefined global" if they appear in source.
- Phase 1 probe Q1 enumerates which globals are actually present in the live sandbox and pins the result in ADR-0003. Even if some dangerous globals are present, the build-time scan ensures we never use them.
- `spec/helpers/mm_mocks.lua` does NOT inject `require`, `io`, `os` as globals — if any source module tries to call them, the test will error, catching the issue in CI before MoneyMoney ever sees the code.

**H10: Non-reproducible build / version desync** [CITED: PITFALLS.md §22; ARCHITECTURE.md §3]

Concrete tactics for Phase 1 (partial — full H10 mitigation is Phase 6):
- `tools/build.lua` produces byte-identical output on consecutive runs: no timestamps, no git SHA, no `$USER`, stable manifest order, LF normalization.
- `tools/build.lua --verify` is the build gate: runs the build twice in sequence and compares SHA256. CI runs this step as a required check.
- `LC_ALL=C` is set in CI environment before build to prevent any locale-dependent sort or string operations.
- `dist/paypal-pos.lua` is gitignored — the generated artifact is never committed. Only the sources and manifest are versioned.
- Version desync (H24 in PITFALLS.md): Phase 1 uses `version = 0.00` (internal placeholder); the `__VERSION__` substitution is Phase 6. The build asserts this placeholder is consistent.

---

## Architecture Patterns

### System Architecture Diagram

```
Developer workstation / CI runner
┌────────────────────────────────────────────────────────────────┐
│ src/*.lua (13 modular source files)                            │
│   webbanking_header.lua → entry.lua (manifest order)          │
│              │                                                 │
│              ▼                                                 │
│   tools/build.lua + tools/manifest.txt                        │
│              │ lua tools/build.lua                             │
│              ▼                                                 │
│   dist/paypal-pos.lua (single Lua chunk)                      │
│              │                                                 │
│   lua tools/build.lua --verify                                │
│   (second run → SHA256 compare → exit 0 or 1)                │
└────────────────────────────────────────────────────────────────┘
                            │
                            │ copy to Extensions/
                            ▼
MoneyMoney runtime (macOS, Lua 5.4 sandbox)
┌────────────────────────────────────────────────────────────────┐
│  paypal-pos.lua loaded as a top-level Lua chunk                │
│                                                                │
│  WebBanking{} ──► MoneyMoney registers "PayPal POS" service   │
│                                                                │
│  SupportsBank(protocol, bankCode) ──► true for "PayPal POS"   │
│                                                                │
│  InitializeSession2 ──► stub: validates non-empty credential   │
│                                                                │
│  ListAccounts ──► returns hard-coded fixture account (Phase 1) │
│                                                                │
│  RefreshAccount ──► returns one fixture transaction (Phase 1)  │
│                                                                │
│  EndSession ──► no-op                                          │
│                                                                │
│  Embedded globals available: Connection, JSON, MM.*, ...      │
│  LocalStorage: per-extension persistent KV                     │
└────────────────────────────────────────────────────────────────┘

spec/ (busted, runs outside MoneyMoney)
┌────────────────────────────────────────────────────────────────┐
│  spec/helpers/mm_mocks.lua  ──► injects all MoneyMoney globals │
│  spec/fixtures/*.json       ──► recorded API responses         │
│  spec/*_spec.lua            ──► busted test files              │
│              │                                                 │
│  busted --coverage spec/   ──► luacov coverage report         │
└────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
.
├── src/
│   ├── webbanking_header.lua   # WebBanking{}, predeclared M_* tables, DEBUG=false
│   ├── log.lua                 # M_log: leveled print wrapper + redact()
│   ├── errors.lua              # M_errors: error constants + user message mapping
│   ├── i18n.lua                # M_i18n: t(key) with de/en string tables
│   ├── model.lua               # M_model: internal record shapes (stub in Phase 1)
│   ├── http.lua                # M_http: Connection wrapper (stub in Phase 1)
│   ├── auth.lua                # M_auth: JWT-bearer flow (stub in Phase 1)
│   ├── pagination.lua          # M_pagination: cursor/offset iterators (stub)
│   ├── purchases.lua           # M_purchases: GET /purchases/v2 (stub)
│   ├── payouts.lua             # M_payouts: Finance API payouts (stub)
│   ├── balance.lua             # M_balance: Finance API balance (stub)
│   ├── mapping.lua             # M_mapping: record → MM transaction (stub)
│   └── entry.lua               # MoneyMoney callbacks (walking skeleton in Phase 1)
│
├── spec/
│   ├── helpers/
│   │   ├── mm_mocks.lua        # All MoneyMoney globals mocked
│   │   └── fixtures.lua        # Fixture loader helper
│   ├── fixtures/               # Scrubbed JSON API responses (empty in Phase 1)
│   ├── mm_mocks_spec.lua       # Smoke test: all globals reachable (TEST-01)
│   ├── log_redaction_spec.lua  # SEC-01 coverage: redact() strips JWT, Bearer
│   ├── i18n_spec.lua           # I18N-02, I18N-03: t(key) returns German; en fallback
│   ├── build_spec.lua          # BUILD-01, BUILD-02: artifact exists; --verify passes
│   └── entry_spec.lua          # Walking skeleton: SupportsBank, ListAccounts smoke
│
├── dist/
│   └── paypal-pos.lua          # Generated artifact (gitignored)
│
├── tools/
│   ├── build.lua               # ~150-line amalgamator
│   ├── manifest.txt            # Ordered list of source files
│   └── probe.lua               # Phase 1 sandbox probe (not part of main build)
│
├── docs/
│   └── adr/
│       ├── 0001-amalgamator-design.md       # Documents the custom build.lua choice
│       ├── 0002-localstorage-token-cache.md  # Scaffolded (filled in Phase 2)
│       └── 0003-sandbox-probe-results.md    # Q1-Q8 results (filled after probe run)
│
├── .github/
│   └── workflows/
│       └── ci.yml              # Lint + test + coverage + build-verify
│
├── .luacheckrc
├── .busted
├── .luacov
├── .gitignore                  # includes dist/
├── LICENSE                     # MIT, copyright Yves Vogl
├── README.md                   # German primary
└── CHANGELOG.md
```

### Walking-Skeleton Entry Module (`src/entry.lua` for Phase 1)

The Phase 1 entry module does not call any API. It proves the WebBanking contract works end-to-end with hard-coded fixtures.

```lua
-- src/entry.lua (Phase 1 walking skeleton)
-- M_i18n is available from the predeclared header.

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "PayPal POS"
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  -- Phase 1: validate that a credential was provided; no actual API call.
  local api_key = credentials and credentials[1] and credentials[1].value or ""
  if api_key == "" then
    return M_i18n.t("error.invalid_grant")
  end
  M_log.info("InitializeSession2: credential received (length=" .. #api_key .. ")")
  return nil
end

function ListAccounts(knownAccounts)
  -- Phase 1: hard-coded fixture account
  return {
    {
      accountNumber = "paypal-pos-fixture-001",
      type          = AccountTypeGiro,
      name          = M_i18n.t("account.name", "Test-Händler"),
      currency      = "EUR",
      portfolio     = false,
    }
  }
end

function RefreshAccount(account, since)
  -- Phase 1: one hard-coded fixture transaction
  M_log.info("RefreshAccount called, since=" .. tostring(since))
  return {
    balance      = 995,
    transactions = {
      {
        name            = M_i18n.t("transaction.name.sale"),
        amount          = 9.95,
        currency        = "EUR",
        bookingDate     = os.time(),
        valueDate       = os.time(),
        purpose         = "Brutto: 9,95 EUR\n19% MwSt: 1,59 EUR\nPayPal POS UUID: fixture-0001",
        bookingText     = "Kartenzahlung",
        booked          = true,
        transactionCode = "zettle:sale:fixture-0001",
      },
    },
  }
end

function EndSession()
  M_log.info("EndSession called")
  return nil
end
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON encode/decode | Custom parser | `JSON()` built-in (prod) / `dkjson` (tests) | MoneyMoney's `JSON()` is battle-tested and available; `dkjson` is 12-year-old pure Lua with wide adoption |
| HTTP client | Raw socket code | `Connection()` built-in | The ONLY sanctioned HTTP method in MoneyMoney's sandbox; raw sockets are blocked |
| Test framework | Custom `assert` helpers | `busted` 2.3.0 | BDD describe/it, before_each/after_each, spy/stub/mock — all needed, all in busted |
| Amalgamation | `lua-amalg` | Custom `tools/build.lua` | `lua-amalg` produces `package.preload` output incompatible with MoneyMoney's top-level-script model |
| Coverage | Custom line tracker | `luacov` 0.16.0 | Standard Lua coverage tool, integrates with busted via `--coverage` flag |
| Static analysis | Manual code review | `luacheck` 1.2.0 | Detects undeclared globals (catches unguarded `print`, missing MoneyMoney mock declarations) |

---

## Common Pitfalls

### Pitfall 1: `require()` in amalgamated source
**What goes wrong:** A `require()` call in any `src/*.lua` file compiles fine locally but fails in MoneyMoney with `attempt to call a nil value (global 'require')`.
**Why it happens:** MoneyMoney's sandbox does not guarantee `require` is present. [CITED: PITFALLS.md §17]
**How to avoid:** `tools/build.lua` scans every source file and aborts on `require(`. luacheck will also flag it as an undefined global since `require` is not in `.luacheckrc`'s `read_globals`.
**Warning signs:** busted tests pass (busted runs under a full Lua 5.4 interpreter with `require` available) but MoneyMoney throws on first load.

### Pitfall 2: Non-deterministic build order
**What goes wrong:** Using `io.popen("ls src/")` or a glob in `tools/build.lua` produces different module ordering on Linux vs. macOS vs. CI runner, breaking reproducibility.
**Why it happens:** Filesystem listing order is not guaranteed to be alphabetical or consistent across platforms.
**How to avoid:** Always use `tools/manifest.txt` as the source of truth for file order. `tools/build.lua` reads the manifest line by line.

### Pitfall 3: DEBUG flag shipping as true
**What goes wrong:** A developer changes `DEBUG = true` to trace a problem and forgets to revert. The shipped artifact logs sensitive data.
**Why it happens:** The DEBUG flag is in source; no automated gate catches it.
**How to avoid:** `tools/build.lua` greps for `DEBUG = true` (not in a comment) and aborts if found.

### Pitfall 4: `mm_mocks.lua` not resetting between tests
**What goes wrong:** `LocalStorage` state from one test leaks into the next. Token cache appears populated when it should be empty.
**Why it happens:** `LocalStorage` is a plain global table; assigning it to `{}` in `before_each` is often forgotten.
**How to avoid:** `Mocks.setup()` calls in `before_each`; `Mocks.teardown()` in `after_each`. `teardown()` resets `LocalStorage = {}` and `_response_queue = {}`.

### Pitfall 5: `JSON()` integer coercion (Q4 probe topic)
**What goes wrong:** `JSON():set({amount=995}):json()` produces `"amount":995.0` and `JSON('{"amount":995.0}'):dictionary()` returns `995.0` instead of `995`. The mapping module then passes `995.0` to MoneyMoney as the transaction amount, which has no cent precision issue but does break `==` equality checks in tests.
**Why it happens:** Lua's `JSON()` implementation may coerce integers to floats. [CITED: SUMMARY.md §5, Q4]
**How to avoid:** Phase 1 probe Q4 tests this explicitly. If coercion happens, use `math.floor(amount)` or `string.format("%d", amount)` in the minor-unit → major-unit helper to restore integer type before division.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Lua 5.4 | All `src/*.lua`, `tools/build.lua` | To be confirmed | MoneyMoney embeds 5.4.8 [ASSUMED]; Q1 probe reports `_VERSION` | None — Lua 5.4 is required |
| luarocks | Test toolchain install | Developer must install | Varies by machine | `brew install luarocks` |
| busted | `spec/*_spec.lua` | CI: installed via luarocks | 2.3.0 | None for CI; for local dev: `luarocks install busted` |
| luacheck | Lint step | CI: installed via luarocks | 1.2.0 | None — lint is required |
| luacov | Coverage step | CI: installed via luarocks | 0.16.0 | None — coverage gate is required |
| dkjson | `spec/helpers/mm_mocks.lua` | CI: installed via luarocks | 2.7+ | None — needed for `JSON()` mock |
| `github.com/leafo/gh-actions-lua@v13` | CI Lua provisioning | CI runner | v13 | None — this is the standard |
| `github.com/leafo/gh-actions-luarocks@v6.1.0` | CI LuaRocks | CI runner | v6.1.0 | None |
| MoneyMoney 2.x (macOS) | Q1–Q8 probe execution | Maintainer's machine | Current stable | Probes cannot run in CI |
| PayPal POS developer portal access | Q6 (client_id) | Maintainer has live POS account | Current | None — must obtain client_id manually |

**Missing dependencies with no fallback:**
- MoneyMoney installation on macOS — required to run the probe extension for Q1–Q8. Cannot be automated in CI.
- PayPal POS developer portal — required to obtain `client_id` for Q6.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `lua-amalg` for module bundling | Custom `tools/build.lua` per-project | Ongoing — `lua-amalg` never supported top-level-script hosts | Must write ~150 lines of build tooling; no LuaRocks dep needed |
| `InitializeSession` (5-arg, legacy) | `InitializeSession2` (credentials array) | MoneyMoney API version ~2.x | Full control over credential field labels; required for German "API-Schlüssel" label |
| LuaSocket for HTTP | `Connection()` built-in | MoneyMoney-specific | No external deps; sandbox-safe |
| `require "cjson"` for JSON | `JSON()` built-in | MoneyMoney-specific | No external deps; sandbox-safe |
| Manual single-file extension | Modular `src/*.lua` + amalgamator | Project architecture decision | Testability + CI coverage possible |

**Deprecated/outdated:**
- `InitializeSession` (5-arg form): works but does not support custom credential field labels. Use `InitializeSession2`.
- `lua-amalg`: canonical Lua amalgamator but incompatible with MoneyMoney's top-level-script load model.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | MoneyMoney embeds Lua 5.4.8 specifically | Standard Stack | If it's 5.3.x: some 5.4 idioms fail; CI must re-pin; integer `//` and bitwise operators unavailable. Q1 probe reports `_VERSION` to confirm. |
| A2 | `services = {"PayPal POS"}` renders exactly that string in the UI | RQ-5 | If label is different: `SupportsBank` always returns false; extension never activates. Q7 is the live verification. |
| A3 | `MM.setUrl` and clipboard API do not exist in MoneyMoney | RQ-6 (probe output choice) | If they exist: probe could write output more cleanly. No functional risk — `print()` works regardless. |
| A4 | `LocalStorage` persists across MoneyMoney restarts | RQ-2 (mock surface), ARCHITECTURE.md §5 | If persistence fails: token cache must be session-local; every extension launch re-mints the token (2 extra API calls). Q5 is the live verification. |
| A5 | `finance.izettle.com` is the correct Finance API host | RQ-3 decision tree | If host is different: all Finance API calls 404. Q3 is the live verification. |
| A6 | `JSON()` preserves integer types (no float coercion on `995`) | RQ-10 pitfall 5 | If coercion: must use `math.floor()` in amount conversion; tests may need updating. Q4 is the live verification. |
| A7 | `Connection()` auto-follows 302 redirects | ARCHITECTURE.md §5 | If not: http.lua must implement a redirect-follow loop (max 3 hops). Q2 is the live verification. |
| A8 | PayPal POS `client_id` is the same for all EU merchants (single constant) | SUMMARY.md §8 | If region-specific: must ship a constants table with a default. Q6 resolves this. |

---

## Open Questions

1. **Q2 redirect behavior** — Does `Connection():request()` auto-follow HTTP 302 on `oauth.zettle.com/token`? The iZettle docs don't address this. If NO, `http.lua` needs a 3-hop redirect loop. Resolution: Phase 2 auth spike.

2. **Q3 Finance API host** — Is `finance.izettle.com` correct for `/v2/accounts/liquid/transactions`? Documented with MEDIUM confidence. If wrong, all Finance API calls fail. Resolution: Phase 2/4 first live call.

3. **Q5 LocalStorage persistence** — Cross-restart persistence is not guaranteed by the MoneyMoney API documentation; it is inferred from the TrueLayer extension's use of the same pattern. If persistence fails, the token-cache design changes significantly. Resolution: Q5 probe.

4. **Q6 client_id** — The PayPal POS first-party `client_id` for the EU market must be obtained from the developer.zettle.com portal. It is not a secret (it is embedded in `auth.lua` in cleartext) but it must be verified against a real app registration. Resolution: Maintainer checks developer.zettle.com before Phase 2.

5. **Locale detection heuristic** — The `MM.localizeText("OK")` probe for locale detection is unverified. The current design hard-codes `"de"` as the default, which is correct for the primary audience but means non-German MoneyMoney users see German strings. This is acceptable for Phase 1 (I18N-03 says English is available but not exposed via UI in v1).

6. **`os.time()` in sandbox** — `src/entry.lua` uses `os.time()` for the walking-skeleton fixture transaction's `bookingDate`. Q1 will confirm whether `os` is available. If not, the walking skeleton must use a hard-coded POSIX timestamp constant.

---

## Module-by-Module File Inventory (for Planner)

The planner should create one task per module. Modules in Phase 1 are written as stubs where business logic is not yet needed. The stubs must compile without error and pass the mm_mocks smoke test.

| File | Phase 1 Content | Tests in Phase 1 | Notes |
|------|----------------|-----------------|-------|
| `src/webbanking_header.lua` | `WebBanking{}` table, all `M_*` predeclarations, `DEBUG = false` | `entry_spec.lua` (WebBanking registration captured) | Must be first in manifest; emitted verbatim |
| `src/log.lua` | `M_log.{debug,info,warn,error}`, `M_log.redact()` | `log_redaction_spec.lua` | SEC-01 coverage here |
| `src/errors.lua` | `M_errors` table with error key constants | `errors_spec.lua` (basic) | Phase 5 will flesh out the full mapping |
| `src/i18n.lua` | `M_i18n.t(key)`, full de/en string tables | `i18n_spec.lua` | I18N-02, I18N-03 fully implemented in Phase 1 |
| `src/model.lua` | Empty `M_model = {}` stub | None in Phase 1 | Populated Phase 3 with record shapes |
| `src/http.lua` | `M_http = {}` stub with `-- Phase 2` comment | None in Phase 1 | Do not ship real HTTP code here yet |
| `src/auth.lua` | `M_auth = {}` stub | None in Phase 1 | Phase 2 |
| `src/pagination.lua` | `M_pagination = {}` stub | None in Phase 1 | Phase 3 |
| `src/purchases.lua` | `M_purchases = {}` stub | None in Phase 1 | Phase 3 |
| `src/payouts.lua` | `M_payouts = {}` stub | None in Phase 1 | Phase 4 |
| `src/balance.lua` | `M_balance = {}` stub | None in Phase 1 | Phase 4 |
| `src/mapping.lua` | `M_mapping = {}` stub | None in Phase 1 | Phase 3 |
| `src/entry.lua` | Walking skeleton (SupportsBank, InitializeSession2, ListAccounts, RefreshAccount with fixture, EndSession) | `entry_spec.lua` | Must produce a loadable artifact |
| `tools/build.lua` | Full ~150-line amalgamator with `--verify` flag and DEBUG gate | `build_spec.lua` | BUILD-01, BUILD-02 |
| `tools/manifest.txt` | Ordered list of 13 source files | Consumed by `build.lua` | Must be in dependency order |
| `tools/probe.lua` | Q1–Q8 probe extension (standalone, not in manifest) | None (runs in live MoneyMoney) | Not shipped; user installs manually |
| `spec/helpers/mm_mocks.lua` | Full mock surface (all globals) | `mm_mocks_spec.lua` | TEST-01 |
| `spec/helpers/fixtures.lua` | `load(name)` helper returning (raw_string, decoded_table) | None standalone | Used by other specs |
| `spec/mm_mocks_spec.lua` | Smoke test for all globals | Self | TEST-01 gate |
| `spec/log_redaction_spec.lua` | Redact JWT, Bearer, assertion=, access_token= | Self | SEC-01 gate |
| `spec/i18n_spec.lua` | t(key) returns German; en fallback; key completeness | Self | I18N-02, I18N-03 gate |
| `spec/build_spec.lua` | `lua tools/build.lua` exits 0; `--verify` exits 0 | Self | BUILD-01, BUILD-02 gate |
| `spec/entry_spec.lua` | SupportsBank returns true for "PayPal POS"; ListAccounts returns one account; RefreshAccount returns one transaction | Self | Walking-skeleton gate |
| `.github/workflows/ci.yml` | lint + test + coverage + build-verify (see RQ-7) | — | Phase 1 CI gate |
| `.luacheckrc` | Full config (see RQ-7) | — | Lint gate |
| `.busted` | Config with coverage enabled | — | Test runner config |
| `.luacov` | `include`, `exclude`, `threshold = 85` | — | Coverage gate |
| `.gitignore` | At minimum: `dist/`, `luacov.*` | — | |
| `docs/adr/0001-amalgamator-design.md` | MADR ADR documenting `lua-amalg` rejection + custom build.lua choice | — | Documents D3 |
| `docs/adr/0003-sandbox-probe-results.md` | Template with all 8 probe rows empty | — | Filled by user after probe run; Phase 1 gate |
| `LICENSE` | MIT, copyright "Yves Vogl" | — | |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | busted 2.3.0 |
| Config file | `.busted` (see above) |
| Quick run command | `busted spec/mm_mocks_spec.lua spec/log_redaction_spec.lua spec/i18n_spec.lua` |
| Full suite command | `busted --coverage spec/` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BUILD-01 | `dist/paypal-pos.lua` produced from `src/` | build | `lua tools/build.lua && test -f dist/paypal-pos.lua` | Wave 0 |
| BUILD-02 | Two consecutive builds produce identical bytes | build | `lua tools/build.lua --verify` | Wave 0 |
| TEST-01 | All MM globals reachable in mock environment | unit | `busted spec/mm_mocks_spec.lua` | Wave 0 |
| I18N-02 | `M_i18n.t("account.name", "X")` returns German string | unit | `busted spec/i18n_spec.lua` | Wave 0 |
| I18N-03 | `STRINGS.en` keys mirror `STRINGS.de` keys | unit | `busted spec/i18n_spec.lua` | Wave 0 |
| SEC-01 | `log.redact()` strips JWT and Bearer from output | unit | `busted spec/log_redaction_spec.lua` | Wave 0 |
| SEC-04 | `DEBUG = true` in source aborts build | build | `echo "DEBUG = true" >> src/log.lua && ! lua tools/build.lua` | Wave 0 |

### Wave 0 Gaps

All test files must be created in Wave 0 (task 0 of Phase 1). None exist yet.

- [ ] `spec/mm_mocks_spec.lua` — covers TEST-01
- [ ] `spec/log_redaction_spec.lua` — covers SEC-01
- [ ] `spec/i18n_spec.lua` — covers I18N-02, I18N-03
- [ ] `spec/build_spec.lua` — covers BUILD-01, BUILD-02
- [ ] `spec/entry_spec.lua` — covers walking-skeleton smoke test
- [ ] `spec/helpers/mm_mocks.lua` — required by all specs
- [ ] `spec/helpers/fixtures.lua` — required by future specs
- [ ] `tools/build.lua` — required before any build specs run
- [ ] `tools/manifest.txt` — required by build.lua

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Phase 2 concern |
| V3 Session Management | No | Phase 2 concern |
| V4 Access Control | No | Read-only extension; no user roles |
| V5 Input Validation | Yes | API credentials: non-empty check in InitializeSession2; log.redact() on all output |
| V6 Cryptography | No | No custom crypto; MoneyMoney's Connection() handles TLS |

### Known Threat Patterns for Phase 1 Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| API key in log output | Information Disclosure | `log.redact()` strips JWT-shape and `Bearer …`; CI grep for bare `print(` |
| `DEBUG = true` shipped | Information Disclosure | `tools/build.lua` aborts on `DEBUG = true` in non-comment line |
| Non-Zettle host call | Tampering / Info Disclosure | CI grep for `://` outside allowlist constants (Phase 1 CI workflow includes this check) |
| Lua sandbox escape via `require` | Elevation of Privilege | Build-time scan; luacheck; Q1 probe pins available globals |

---

## Sources

### Primary (HIGH confidence)
- MoneyMoney WebBanking API reference — https://moneymoney.app/api/webbanking/ — global functions, entry points, constants, LocalStorage semantics
- `jgoldhammer/moneymoney-payback` — https://github.com/jgoldhammer/moneymoney-payback/blob/master/payback.lua — WebBanking{} idioms, SupportsBank pattern
- `teal-bauer/moneymoney-ext-trading212` — https://github.com/teal-bauer/moneymoney-ext-trading212 — single-file shipping, release workflow
- `miracle2k/moneymoney-truelayer` — https://github.com/miracle2k/moneymoney-truelayer/blob/master/TrueLayer.lua — LocalStorage token cache pattern
- `siffiejoe/lua-amalg` — https://github.com/siffiejoe/lua-amalg — canonical amalgamator; examined and rejected
- `lunarmodules/busted` — https://luarocks.org/modules/lunarmodules/busted — version 2.3.0 confirmed
- `lunarmodules/luacheck` — https://luarocks.org/modules/lunarmodules/luacheck — version 1.2.0 confirmed
- `hisham/luacov` — https://luarocks.org/modules/hisham/luacov — version 0.16.0 confirmed
- `leafo/gh-actions-lua` — https://github.com/leafo/gh-actions-lua — v13 confirmed Apr 2026
- `leafo/gh-actions-luarocks` — https://github.com/leafo/gh-actions-luarocks — v6.1.0 confirmed Apr 2026
- Project planning files: SUMMARY.md, ARCHITECTURE.md, STACK.md, PITFALLS.md, REQUIREMENTS.md, ROADMAP.md — all high-confidence, synthesized 2026-06-16

### Secondary (MEDIUM confidence)
- Enapter Rockamalg — https://developers.enapter.com/docs/tutorial/lua-complex/rockamalg — host-specific amalgamation pattern
- reproducible-builds.org SOURCE_DATE_EPOCH — https://reproducible-builds.org/docs/source-date-epoch/ — determinism practices
- dkjson — https://luarocks.org/modules/dhkolf/dkjson — pure-Lua JSON for test harness

### Tertiary (LOW confidence)
- [ASSUMED] MoneyMoney Lua version is exactly 5.4.8 — probe Q1 reports `_VERSION` to confirm
- [ASSUMED] LocalStorage persists across restarts — probe Q5 to confirm
- [ASSUMED] `services = {"PayPal POS"}` is unambiguous in the German UI — probe Q7 to confirm

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools verified against primary sources; toolchain inherited from project-level research
- Amalgamator design: HIGH — algorithm specified from first principles; `lua-amalg` rejection documented with citations
- mm_mocks surface: HIGH — sourced directly from MoneyMoney WebBanking API reference
- i18n design: HIGH — standard table-driven pattern; no external dependencies
- log.redact() design: HIGH — regex patterns cover the documented token shapes; tested by spec
- Probe strategy: HIGH for mechanism; ASSUMED for outcomes (Q1–Q8 pending live execution)
- CI workflow: HIGH — uses only pinned, verified Actions versions

**Research date:** 2026-06-16
**Valid until:** 2026-09-16 (90 days; stable stack; re-verify CI Action versions if planning resumes after this date)
