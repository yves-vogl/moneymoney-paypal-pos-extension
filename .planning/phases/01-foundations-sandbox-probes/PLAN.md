# Phase 1 — Plan: Foundations & Sandbox Probes

**Phase:** 1 — Foundations & Sandbox Probes
**Mode:** mvp · Walking-Skeleton · granularity=standard · tdd_mode=off
**Requirements:** BUILD-01, BUILD-02, TEST-01, I18N-02, I18N-03, SEC-01, SEC-04
**Probe IDs owned:** Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8 (Phase 1 ships the probe extension; Q2/Q3/Q6 live answers obtained in Phase 2/4)
**Plan unit:** one ordered task list (no sub-plans); orchestrator executes top to bottom.

Pre-reads for every task: `CLAUDE.md` (repo root), `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/phases/01-foundations-sandbox-probes/RESEARCH.md`, `.planning/phases/01-foundations-sandbox-probes/CONTEXT.md`, `.planning/phases/01-foundations-sandbox-probes/SKELETON.md`.

Every commit: GPG-signed under key `FDE07046A6178E89ADB57FD3DE300C53D8E18642`, Conventional-Commits, English. No Claude / AI attribution anywhere.

---

## Task list

### T01 — Repo scaffold, root configs, license, gitignore

- **Requirement traceability:** scaffold (precondition for BUILD-01, BUILD-02, TEST-01, CI hygiene)
- **Probe traceability:** none
- **Files touched:**
  - `LICENSE` (MIT, "Copyright (c) 2026 Yves Vogl")
  - `.gitignore` (adds `dist/`, `luacov.*`, `.luacov.out`, `*.luac`, `.DS_Store`)
  - `.luacheckrc` (config per RESEARCH RQ-7: `std = "lua54+busted"`, `files["spec/**"]` and `files["tools/**"]` overrides, `read_globals` for MoneyMoney built-ins, `globals` for WebBanking callbacks + predeclared `M_*` tables + `DEBUG`, `ignore = {"212"}`)
  - `.busted` (config per RESEARCH RQ-7: verbose, coverage, `utfTerminal`)
  - `.luacov` (per RESEARCH RQ-7: `include = { "src/.+%.lua$" }`, `exclude = { "src/webbanking_header%.lua$" }`, `threshold = 85`)
  - `src/` (empty directory placeholder via `.gitkeep`)
  - `spec/` (`.gitkeep`)
  - `spec/helpers/` (`.gitkeep`)
  - `spec/fixtures/` (`.gitkeep`)
  - `tools/` (`.gitkeep`)
  - `docs/adr/` (`.gitkeep`)
  - `.github/workflows/` (`.gitkeep` — workflow lands in T11)
- **Acceptance criteria:**
  1. `luacheck --version` succeeds locally and `luacheck .` exits 0 against the empty tree (no Lua files yet).
  2. `LICENSE` file exists; first line is `MIT License`; `Copyright (c) 2026 Yves Vogl` present.
  3. `.gitignore` lines verified: `dist/`, `luacov.*` present.
  4. `git status` shows clean tracked tree; `dist/` is in `.gitignore` so any later test build is invisible.
- **Test / spec:** `luacheck . && test -f LICENSE && grep -q "Copyright (c) 2026 Yves Vogl" LICENSE && grep -q "^dist/$" .gitignore`
- **Estimated effort:** S
- **Dependencies:** none
- **Risk callouts:** none

---

### T02 — `tools/manifest.txt` and amalgamator `tools/build.lua` (with `--verify`, DEBUG gate, sandbox-call gate)

- **Requirement traceability:** BUILD-01, BUILD-02, SEC-04
- **Probe traceability:** none directly; underpins H8/H10 mitigations
- **Files touched:**
  - `tools/manifest.txt` (13 lines + header comment; order per RESEARCH RQ-1: `webbanking_header`, `log`, `errors`, `i18n`, `model`, `http`, `auth`, `pagination`, `purchases`, `payouts`, `balance`, `mapping`, `entry`)
  - `tools/build.lua` (~150 lines; algorithm per RESEARCH RQ-1):
    - CLI: no args → build; `--verify` → build + re-build + sha256 compare; `--help` → usage.
    - Read manifest line-by-line, skip blanks / `#` comments.
    - For each source file: read binary, normalise `\r\n`→`\n` and standalone `\r`→`\n`, strip trailing whitespace per line.
    - **Sandbox-call gate (H8):** for each `src/*.lua`, scan non-comment lines for `require%(`, `dofile%(`, `loadfile%(`, `io%.open%(`, `os%.execute%(`, `io%.popen%(`; on hit: `io.stderr:write` a message naming the file + line + offending token; `os.exit(1)`.
    - **DEBUG gate (SEC-04):** for each `src/*.lua`, scan non-comment lines for `DEBUG%s*=%s*true`; on hit: `io.stderr:write` a message naming the file + line; `os.exit(1)`.
    - Emit header banner comment `-- paypal-pos amalgamated artifact — do not edit by hand`.
    - Emit `src/webbanking_header.lua` verbatim.
    - For each subsequent module except `src/entry.lua`: emit `-- === MODULE: <basename> ===\n` then `do\n` + body + `\nend\n`.
    - Emit `src/entry.lua` verbatim (MoneyMoney callbacks must be top-level).
    - Emit closing sentinel `-- paypal-pos build: complete`.
    - Write to `dist/paypal-pos.lua` using LF endings (`io.open(path, "wb")`).
    - `--verify`: build to `dist/paypal-pos.lua`, build to `dist/paypal-pos.lua.tmp`, compute sha256 of each via a pure-Lua sha256 routine (~40 lines, public-domain reference; or shell out to `shasum -a 256` only on dev — but to keep determinism portable, prefer pure-Lua), compare; if mismatch: print diff hint and exit 1; if match: print `OK: reproducible` and remove `.tmp`.
    - Pure-Lua sha256: keep self-contained in `tools/build.lua` (acceptable since `tools/` does not ship). Reference: a single-file public-domain sha256 (~80 lines) is fine.
    - No `os.date`, no `os.time`, no env reads, no git invocations anywhere in `tools/build.lua`.
- **Acceptance criteria:**
  1. `lua tools/build.lua` exits 0 once T03+ have produced minimal `src/*.lua` files (depends on T03 for first green run).
  2. `lua tools/build.lua --verify` exits 0 with stdout containing `OK: reproducible`.
  3. Inserting `DEBUG = true` on its own line in `src/log.lua` makes `lua tools/build.lua` exit non-zero with stderr containing `DEBUG = true found in src/log.lua`.
  4. Inserting `local x = require("dkjson")` in `src/log.lua` makes `lua tools/build.lua` exit non-zero with stderr naming `require(` and `src/log.lua`.
  5. `tools/build.lua` source contains no `os.date`, no `os.time`, no `os.getenv` (grep gate inside T05 spec).
- **Test / spec:** Covered by `spec/build_spec.lua` (created in T05). Pre-merge sanity: after T03 lands, `lua tools/build.lua && lua tools/build.lua --verify && test -f dist/paypal-pos.lua` (run by orchestrator manually). T05 codifies the negative gates.
- **Estimated effort:** L (largest task — the amalgamator + pure-Lua sha256)
- **Dependencies:** T01
- **Risk callouts:** R3 (LF normalisation must be airtight; `LC_ALL=C` set in CI; build must run identically on macOS and ubuntu-24.04). Keep the pure-Lua sha256 in a clearly-marked block at the bottom of `tools/build.lua` with attribution to the public-domain source — no external dep.

---

### T03 — Infra modules: `webbanking_header.lua`, `log.lua`, `i18n.lua`, plus 9 empty stubs

- **Requirement traceability:** SEC-01, SEC-04, I18N-02, I18N-03 (also implicitly BUILD-01 by giving `tools/build.lua` real input)
- **Probe traceability:** none
- **Files touched:**
  - `src/webbanking_header.lua` — Emitted verbatim by the amalgamator. Top-of-file local-declared module tables: `local M_log, M_errors, M_i18n, M_model, M_http, M_auth, M_pagination, M_purchases, M_payouts, M_balance, M_mapping` each initialised to `{}`. `local DEBUG = false` (SEC-04 anchor). `WebBanking{}` call with `version = 0.00`, `country = "de"`, `url = "https://oauth.zettle.com"`, `services = {"PayPal POS"}`, `description = "PayPal POS / Zettle Umsätze, Gebühren und Auszahlungen"` (per CONTEXT D-06 and D-20).
  - `src/log.lua` — Inside the `do … end` wrapper (added by build.lua). Implements `M_log.redact(s)` with the four `gsub` patterns from RESEARCH RQ-4 (JWT three-part, `Bearer …`, `assertion=…`, `access_token=…`). Implements `_emit(level_num, level_name, ...)` that maps every vararg through `M_log.redact(tostring(v))`, formats `[paypal-pos][<LEVEL>] <text>`, and calls `print(...)`. Implements `M_log.debug`, `M_log.info`, `M_log.warn`, `M_log.error`. Level filtering uses the locally-declared `_LEVEL` table; effective level reads the top-level `DEBUG` to decide debug-vs-info threshold. No bare `print()` calls in this module (or anywhere else in `src/`).
  - `src/i18n.lua` — Inside `do … end`. Two table literals `STRINGS.de` and `STRINGS.en`, key set per RESEARCH RQ-3 (account, transaction.name.*, purpose.*, error.*, credential.*). `M_i18n.t(key, ...)` returns `STRINGS.de[key]`; if absent, falls back to `STRINGS.en[key]`; if both absent, returns the key literal. When varargs are present, applies `string.format`. Locale variable hard-coded `"de"`.
  - `src/errors.lua`, `src/model.lua`, `src/http.lua`, `src/auth.lua`, `src/pagination.lua`, `src/purchases.lua`, `src/payouts.lua`, `src/balance.lua`, `src/mapping.lua` — Each file is exactly:
    ```
    -- src/<name>.lua
    -- Phase <N> stub. Implementation lands in Phase <N>; see ROADMAP.md.
    -- The M_<name> table is predeclared in src/webbanking_header.lua.
    ```
    No code lines beyond the comment header — the predeclared `M_<name> = {}` from the header is sufficient. Phase numbers per CONTEXT D-14.
- **Acceptance criteria:**
  1. `luacheck src/` exits 0 (the predeclared `M_*` globals + `DEBUG` are in `.luacheckrc`'s `globals` list from T01).
  2. After T02, `lua tools/build.lua` exits 0 and writes `dist/paypal-pos.lua`.
  3. The amalgamated artifact contains the literal line `DEBUG = false` (sanity: `grep -q '^local DEBUG = false' dist/paypal-pos.lua` succeeds).
  4. The amalgamated artifact contains the literal line `services    = {"PayPal POS"}` (or formatting-equivalent — the key + value substring is present).
  5. None of the stub files contains a `function` declaration (grep-sanity: `! grep -E '^function' src/{errors,model,http,auth,pagination,purchases,payouts,balance,mapping}.lua`).
- **Test / spec:** Behavior-level tests for `log.lua` land in T05 (`spec/log_redaction_spec.lua`) and for `i18n.lua` in T06 (`spec/i18n_spec.lua`). T03 is the production-code creation task; T05/T06 are the gating tests.
- **Estimated effort:** M
- **Dependencies:** T01, T02. Logically T02 is not a hard precondition (sources can be authored before `tools/build.lua` exists), but the orchestrator runs T02 before T03 so the SEC-04 / sandbox-call gates are active the moment any code is committed.
- **Risk callouts:** R5 — `M_log` must be the only `print()` path. The Phase-6 CI grep that enforces this is not in Phase 1, but `.luacheckrc` keeping `print` outside `read_globals` for `src/` files is sufficient gate for now: any future `print()` in a source file other than `src/log.lua` (which intentionally calls `print` from inside `_emit`) will trip lint.

---

### T04 — `spec/helpers/mm_mocks.lua` + `spec/helpers/fixtures.lua`

- **Requirement traceability:** TEST-01
- **Probe traceability:** none
- **Files touched:**
  - `spec/helpers/mm_mocks.lua` — full mock surface per RESEARCH RQ-2. `Mocks.setup()` populates `_G` with: `Connection` (returns a per-call object whose `request/get/post/close` pop from `_response_queue`), `JSON` (backed by `dkjson`; both parse and serialise forms), `HTML`, `PDF`, `MM` (every method enumerated in RQ-2 — `localizeText` is pass-through; `base64`/`base64decode` via `mime.b64` if available else identity; `sha256/sha512/sha1/md5/hmac*` return fixed-length zero-strings; `time` returns `os.time() * 1000`; `urlencode/urldecode` pure-Lua; `printStatus` captures into `MM._captured_status`), `LocalStorage = {}`, `WebBanking = function(t) _G._WebBanking_received = t end`, the seven `ProtocolWebBanking` / `ProtocolFinTS` / `AccountType*` / `LoginFailed` string constants, and `Mocks.push_response`. `Mocks.teardown()` resets the response queue and `LocalStorage`. Captures any `print` calls into a `Mocks._captured_prints` table by wrapping `print = function(...) table.insert(_captured_prints, table.concat({...}, " ")) end` so `spec/log_redaction_spec.lua` can assert on output.
  - `spec/helpers/fixtures.lua` — minimal `load(name)` helper that reads `spec/fixtures/<name>.json` and returns the raw string and the decoded table (via `dkjson.decode`). Phase 1 does not yet have fixtures; the helper exists so later phases can use it without revisiting the helpers directory.
- **Acceptance criteria:**
  1. `luacheck spec/helpers/` exits 0.
  2. `require("spec.helpers.mm_mocks")` works from a busted run (orchestrator runs `busted spec/helpers/` with no specs — must not error).
  3. `Mocks.setup(); Mocks.teardown()` runs without error and leaves `_G.LocalStorage` as `{}`.
- **Test / spec:** Behavior-level coverage lands in T05 (`spec/mm_mocks_spec.lua`).
- **Estimated effort:** M
- **Dependencies:** T01 (`.luacheckrc` declares the mocked globals as `read_globals`, so the mock module itself is allowed to set them via `_G.* = …`).
- **Risk callouts:** none

---

### T05 — Specs for build pipeline, mock surface, redactor

- **Requirement traceability:** BUILD-01, BUILD-02, TEST-01, SEC-01, SEC-04
- **Probe traceability:** none
- **Files touched:**
  - `spec/build_spec.lua` — `before_each` removes `dist/paypal-pos.lua` if present. Test cases:
    1. `it("produces dist/paypal-pos.lua")` — `os.execute("lua tools/build.lua")` returns 0; `io.open("dist/paypal-pos.lua", "rb")` is non-nil. (BUILD-01)
    2. `it("--verify confirms byte-identical second build")` — `os.execute("lua tools/build.lua --verify")` returns 0. (BUILD-02)
    3. `it("aborts when DEBUG = true exists outside a comment")` — write a temp source file `src/_debug_probe.lua` containing `DEBUG = true` (appended to manifest via a temp manifest); invoke `lua tools/build.lua` with that manifest; assert exit code non-zero AND stderr contains `DEBUG = true`. (SEC-04)
    4. `it("aborts when a source calls require()")` — same pattern with `require("dkjson")`. (H8)
    5. `it("aborts when a source calls os.execute()")` — same pattern. (H8)
    6. `it("artifact contains DEBUG = false")` — after a normal build, `grep -q 'DEBUG = false' dist/paypal-pos.lua`. (SEC-04 positive case)
  - `spec/mm_mocks_spec.lua` — per RESEARCH RQ-9, asserts every documented global is defined after `Mocks.setup()`, every `MM.*` method is callable, `Connection():request` returns the queued response, `JSON(s):dictionary()` parses a sample, `JSON():set(t):json()` serialises, `LocalStorage` is a writable table, `LoginFailed` is a string. (TEST-01)
  - `spec/log_redaction_spec.lua` — four positive cases (one per redaction pattern) and one negative case (a string with neither pattern is unchanged). Each test calls `Mocks.setup()`, invokes `M_log.info("…<secret>…")`, then asserts the captured `print` string (a) contains the `[paypal-pos][INFO]` prefix, (b) contains the `<redacted>` placeholder, and (c) does NOT contain the secret substring (e.g. `eyJ`, the raw JWT, the raw `assertion=`-value). To make `M_log` visible to the spec, the spec `dofile("dist/paypal-pos.lua")`-equivalent is not used (entry-point side effects would run); instead, the spec loads `src/log.lua` against a manually-constructed `M_log` table (Phase 1 acceptable shortcut — the redactor is pure and does not depend on `WebBanking()`'s side effect). (SEC-01)
- **Acceptance criteria:**
  1. `busted spec/build_spec.lua spec/mm_mocks_spec.lua spec/log_redaction_spec.lua` exits 0.
  2. Each negative-gate test (T05.3, T05.4, T05.5) leaves the working tree clean — temp files / temp manifests are removed in `after_each`.
- **Test / spec:** self.
- **Estimated effort:** L (most behaviour-rich task in the phase; three specs and the SEC-04 / H8 negative-gate harness)
- **Dependencies:** T02 (`tools/build.lua` must exist), T03 (`src/log.lua` must exist), T04 (`mm_mocks.lua` must exist)
- **Risk callouts:** R3 — `build_spec.lua` tests must invoke the build via `os.execute("lua tools/build.lua")` rather than `dofile` so the build runs in its own process and the spec captures real exit codes.

---

### T06 — `i18n_spec.lua` + `entry.lua` walking skeleton + `entry_spec.lua`

- **Requirement traceability:** I18N-02, I18N-03 (i18n_spec); walking-skeleton gate (entry + entry_spec)
- **Probe traceability:** none directly; Q1 (`os.time` availability) is exercised by the walking-skeleton inside MoneyMoney during T13
- **Files touched:**
  - `spec/i18n_spec.lua`:
    1. `it("returns German strings by default")` — `M_i18n.t("transaction.name.sale")` returns `"Kartenzahlung"`.
    2. `it("interpolates positional arguments via string.format")` — `M_i18n.t("account.name", "Test-Händler")` returns `"PayPal POS — Test-Händler"`.
    3. `it("falls back to the key literal for missing keys")` — `M_i18n.t("nonexistent.key")` returns `"nonexistent.key"`.
    4. `it("STRINGS.en covers every STRINGS.de key")` — iterates `STRINGS.de` and asserts each key is present in `STRINGS.en` (I18N-03).
    5. `it("STRINGS.de covers every STRINGS.en key")` — symmetric (catches dropped DE keys).
  - `src/entry.lua` — Emitted verbatim by the amalgamator. Defines the five MoneyMoney callbacks per RESEARCH §Walking-Skeleton Entry Module and CONTEXT D-10:
    - `SupportsBank(protocol, bankCode)` — `return protocol == ProtocolWebBanking and bankCode == "PayPal POS"`.
    - `InitializeSession2(protocol, bankCode, step, credentials, interactive)` — read `credentials[1].value` defensively; if nil or empty: `return M_i18n.t("error.invalid_grant")`; else `M_log.info("InitializeSession2: credential received (length=" .. #api_key .. ")")` and `return nil`.
    - `ListAccounts(knownAccounts)` — return one `AccountTypeGiro` with `accountNumber = "paypal-pos-fixture-001"`, `name = M_i18n.t("account.name", "Test-Händler")`, `currency = "EUR"`, `portfolio = false`.
    - `RefreshAccount(account, since)` — `M_log.info("RefreshAccount called, since=" .. tostring(since))`; return `{ balance = 9.95, transactions = { <one transaction> } }`. The transaction has `name = M_i18n.t("transaction.name.sale")`, `amount = 9.95`, `currency = "EUR"`, `bookingDate = os.time()`, `valueDate = os.time()`, `purpose` built via three `M_i18n.t(...)` calls joined with `\n` (gross + VAT line + UUID line), `bookingText = "Kartenzahlung"`, `booked = true`, `transactionCode = "zettle:sale:fixture-0001"`.
    - `EndSession()` — `M_log.info("EndSession called"); return nil`.
  - `spec/entry_spec.lua`:
    1. `it("SupportsBank true for ProtocolWebBanking + 'PayPal POS'")` — assert true.
    2. `it("SupportsBank false for ProtocolFinTS + 'PayPal POS'")` — assert false.
    3. `it("SupportsBank false for ProtocolWebBanking + 'Other Bank'")` — assert false.
    4. `it("InitializeSession2 returns German error string on empty credential")` — `assert.equals(M_i18n.t("error.invalid_grant"), InitializeSession2(ProtocolWebBanking, "PayPal POS", 1, { { value = "" } }, false))`.
    5. `it("InitializeSession2 returns nil on non-empty credential")` — pass a credential with any non-empty value; assert `nil`.
    6. `it("ListAccounts returns one AccountTypeGiro with EUR")` — accounts table has length 1, `accounts[1].type == AccountTypeGiro`, `accounts[1].currency == "EUR"`.
    7. `it("RefreshAccount returns one transaction with EUR + zettle:sale prefix")` — `result.transactions` length 1, `result.transactions[1].currency == "EUR"`, `result.transactions[1].transactionCode:match("^zettle:sale:")` truthy.
    8. `it("RefreshAccount transaction name comes from i18n")` — `result.transactions[1].name == M_i18n.t("transaction.name.sale")`.
    9. `it("EndSession returns nil")` — assert `nil`.
  - To make the entry callbacks visible to busted: the spec uses `Mocks.setup()` (which defines `ProtocolWebBanking`, `AccountTypeGiro`, `LoginFailed`, the `WebBanking` capture, etc.), then `dofile("dist/paypal-pos.lua")` to load the amalgamated artifact (this is the cleanest path because the artifact's top-level `WebBanking{}` call is captured by the mock). After `dofile`, `SupportsBank`, `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `EndSession` are present as globals.
  - The spec's `before_each` runs `os.execute("lua tools/build.lua")` to ensure a fresh artifact is loaded. (Acceptable runtime cost — the artifact builds in well under a second.)
- **Acceptance criteria:**
  1. `busted spec/i18n_spec.lua spec/entry_spec.lua` exits 0.
  2. The DE/EN parity assertions catch any future drift (verified by temporarily removing one EN key in a scratch branch and confirming the spec fails — orchestrator does not need to commit this experiment).
- **Test / spec:** self.
- **Estimated effort:** M
- **Dependencies:** T03 (i18n.lua), T02 (build.lua to produce dist artifact for the dofile load), T04 (mm_mocks for the protocol/account-type constants)
- **Risk callouts:** R2 — if Q1 reveals `os` is absent in MoneyMoney's sandbox, `bookingDate = os.time()` in `src/entry.lua` is replaced with a hard-coded POSIX integer constant in a Phase-1 follow-up before the maintainer runs the walking-skeleton install (T13).

---

### T07 — Coverage gate verification

- **Requirement traceability:** CI-02 (Phase-6 hardening), but the threshold is enforced in Phase 1 to surface gaps early.
- **Probe traceability:** none
- **Files touched:** none (this task is a verification step that runs the existing tooling).
- **Acceptance criteria:**
  1. `busted --coverage spec/` exits 0.
  2. `luacov` runs and writes `luacov.report.out`.
  3. The aggregate line coverage on `src/` (excluding `src/webbanking_header.lua`) is ≥85%.
  4. If the gate fails: the offending module is identified and either (a) tests are added in this task, or (b) the orchestrator opens a follow-up — Phase 1 does not declare success below 85%.
- **Test / spec:** `lua -e "local f=io.open('luacov.report.out','r'); local s=f:read('*a'); f:close(); local total = s:match('Total%s+%d+%s+%d+%s+([%d%.]+)%%'); assert(tonumber(total) >= 85, 'coverage ' .. total .. '%% < 85%%')"`
- **Estimated effort:** S
- **Dependencies:** T05, T06
- **Risk callouts:** the stub modules (`errors`, `model`, `http`, `auth`, `pagination`, `purchases`, `payouts`, `balance`, `mapping`) have **zero** executable lines, so they neither raise nor lower the percentage (luacov ignores files with no source lines, but if it counts them as 0/0 they are filtered out via the `.luacov` `include`). The only modules contributing executable lines are `log`, `i18n`, and `entry` — all three are exercised by T05/T06 specs.

---

### T08 — `tools/probe.lua` standalone probe extension

- **Requirement traceability:** none (probe outputs feed Phase-2/4 design)
- **Probe traceability:** Q1, Q4, Q5, Q7 (indirect), Q8 — Q2/Q3/Q6 noted in the probe output but obtained live in Phase 2/4
- **Files touched:**
  - `tools/probe.lua` — verbatim per RESEARCH RQ-6. Stands alone (NOT in `tools/manifest.txt`, NOT loaded by `tools/build.lua`). Declares `WebBanking{ services = {"PayPal POS Probe"}, … }`, `SupportsBank` matching `bankCode == "PayPal POS Probe"`, `InitializeSession2` returning `nil`, `ListAccounts` returning one fixture account, `RefreshAccount` emitting the Q1/Q4/Q5/Q7/Q8 print blocks, `EndSession` returning `nil`. Uses only `print`, `_G`, `JSON()`, `LocalStorage`, `Connection()` — exactly the surface available inside MoneyMoney's sandbox.
- **Acceptance criteria:**
  1. `tools/probe.lua` exists and contains the literal `services    = {"PayPal POS Probe"}`.
  2. `tools/probe.lua` is NOT referenced anywhere in `tools/manifest.txt` (grep gate: `! grep -q probe.lua tools/manifest.txt`).
  3. `luacheck tools/probe.lua` exits 0 (the probe file declares its globals correctly).
- **Test / spec:** `luacheck tools/probe.lua && grep -q 'PayPal POS Probe' tools/probe.lua && ! grep -q probe.lua tools/manifest.txt`
- **Estimated effort:** S
- **Dependencies:** T01 (`.luacheckrc` for the lint gate)
- **Risk callouts:** the probe deliberately calls `Connection():get("https://expired.badssl.com/")` for Q8. This is the ONLY non-allowlist host we deliberately hit, and only from the probe extension — never from `src/`. The probe is uninstalled after ADR-0003 is filled in (D-11). Note this in `tools/probe.lua` as a comment so future readers do not think this is a leak.

---

### T09 — `docs/adr/0001-amalgamator-design.md` (filled) + `docs/adr/0003-sandbox-probe-results.md` (template)

- **Requirement traceability:** none (Phase 6 owns DOC-06); these two ADRs land in Phase 1 because the amalgamator decision is being made here and the probe template is needed before the maintainer runs the probe.
- **Probe traceability:** Q1–Q8 (template)
- **Files touched:**
  - `docs/adr/0001-amalgamator-design.md` — MADR format. Status: ACCEPTED. Context: MoneyMoney loads extensions as top-level Lua chunks; `WebBanking{}` and the five callbacks must be top-level. Decision: custom `tools/build.lua` driven by `tools/manifest.txt`; `lua-amalg` rejected. Rationale: `lua-amalg` emits `package.preload`/`require`-bootstrap output incompatible with the load model. Consequences: ~150 lines of build tooling; zero LuaRocks dep; deterministic output verified by `--verify`. Citations: `https://github.com/siffiejoe/lua-amalg`, `https://moneymoney.app/api/webbanking/`.
  - `docs/adr/0003-sandbox-probe-results.md` — verbatim template per RESEARCH RQ-8: status `PROPOSED until probes run`, the 8-row table with empty result cells, the "Consequences" section listing each probe's decision branch. The maintainer fills in the result cells in T13.
- **Acceptance criteria:**
  1. Both files exist; `head -1` of each starts with `# ADR-`.
  2. ADR-0001 status line says `ACCEPTED`; ADR-0003 status line says `PROPOSED`.
  3. ADR-0003 contains rows for Q1 through Q8 (grep: `grep -c '^| Q' docs/adr/0003-sandbox-probe-results.md` returns ≥8).
- **Test / spec:** `test -f docs/adr/0001-amalgamator-design.md && test -f docs/adr/0003-sandbox-probe-results.md && grep -q 'ACCEPTED' docs/adr/0001-amalgamator-design.md && grep -q 'PROPOSED' docs/adr/0003-sandbox-probe-results.md && [ "$(grep -c '^| Q' docs/adr/0003-sandbox-probe-results.md)" -ge 8 ]`
- **Estimated effort:** S
- **Dependencies:** none (can run in parallel with T02–T08, but the orchestrator schedules it after T08 because T08 establishes the probe extension that ADR-0003 documents)
- **Risk callouts:** none

---

### T10 — End-to-end local verification on a clean checkout

- **Requirement traceability:** BUILD-01, BUILD-02, TEST-01, SEC-01, SEC-04, I18N-02, I18N-03 (composite gate)
- **Probe traceability:** none
- **Files touched:** none (this is a verification gate; no new files)
- **Acceptance criteria (run in this order, all must pass):**
  1. `git clean -fdx -e .planning -e .git` (or in a fresh worktree) — re-installs nothing yet committed.
  2. `luarocks --lua-version=5.4 install --tree=.luarocks busted luacheck luacov dkjson` (or `luarocks install ...` if global tree is acceptable on the orchestrator's machine).
  3. `luacheck .` exits 0.
  4. `lua tools/build.lua` exits 0; `test -f dist/paypal-pos.lua`.
  5. `lua tools/build.lua --verify` exits 0; stdout contains `OK: reproducible`.
  6. `busted --coverage spec/` exits 0; final summary line says no failures.
  7. `lua -e "<inline coverage threshold check from T07>"` exits 0.
  8. `grep -q 'DEBUG = false' dist/paypal-pos.lua`.
  9. `! grep -E 'https?://[^\"'\''[:space:]]+' dist/paypal-pos.lua | grep -v 'oauth\.zettle\.com\|purchase\.izettle\.com\|finance\.izettle\.com'` (no off-allowlist URL in the artifact; Phase-1 artifact has only `oauth.zettle.com` from `WebBanking.url` field, but the grep is forward-compatible).
- **Test / spec:** the sequence above is the test. The orchestrator runs it; failures route back to the preceding task that owns the failing gate.
- **Estimated effort:** S
- **Dependencies:** T01–T09
- **Risk callouts:** R3 — the verify step is the canary. If `OK: reproducible` ever flakes between two consecutive runs, do not paper over; fix the determinism source (likely candidates: locale, line endings, sha256 routine).

---

### T11 — `.github/workflows/ci.yml`

- **Requirement traceability:** scaffold for CI-01/CI-02/CI-03/CI-04 (full CI hardening is Phase 6; Phase 1 ships the minimum-viable workflow)
- **Probe traceability:** none
- **Files touched:**
  - `.github/workflows/ci.yml` — verbatim structure per RESEARCH RQ-7. Triggers: `push` and `pull_request` on `["**"]`. Runner: `ubuntu-24.04`. Env: `LC_ALL: C`. Steps in order:
    1. `actions/checkout@v4` with `fetch-depth: 0`.
    2. `leafo/gh-actions-lua@v13` with `luaVersion: "5.4"`.
    3. `leafo/gh-actions-luarocks@v6.1.0`.
    4. `luarocks install busted luacheck luacov dkjson` (one step).
    5. `luacheck .`.
    6. `busted --coverage spec/`.
    7. Coverage threshold check (inline `lua -e ...` parsing `luacov.report.out`).
    8. `lua tools/build.lua`.
    9. `lua tools/build.lua --verify`.
    10. DEBUG grep: `! grep -q "DEBUG = true" dist/paypal-pos.lua` (positive: confirms shipped artifact has `DEBUG = false`).
    11. Egress allowlist grep: same pattern as T10 step 9.
- **Acceptance criteria:**
  1. File parses as valid YAML (`python -c 'import yaml,sys; yaml.safe_load(sys.stdin)' < .github/workflows/ci.yml` — only used as a local sanity check; not a project dependency).
  2. When the orchestrator pushes the feature branch, GitHub Actions runs the workflow and every step is green.
  3. If `act` is available on the orchestrator's machine: `act -W .github/workflows/ci.yml` runs end-to-end green. (Optional local gate.)
- **Test / spec:** GitHub Actions UI shows the run as green on the Phase-1 feature branch.
- **Estimated effort:** S
- **Dependencies:** T01–T10 (everything must be green locally first; CI is the second-line gate)
- **Risk callouts:** Phase-1 workflow intentionally omits `gitleaks`, Dependabot config, tag-triggered release, GPG-tag verification, two-checkout reproducibility diff, branch-protection enforcement — all owned by Phase 6 per CONTEXT scope-out.

---

### T12 — Probe extension install + ADR-0003 transcription (maintainer-driven)

- **Requirement traceability:** none (Phase-1 human gate)
- **Probe traceability:** Q1, Q4, Q5, Q7, Q8 (live results); Q2, Q3, Q6 cells left empty (owned by Phase 2/4)
- **Files touched:** `docs/adr/0003-sandbox-probe-results.md` (cells filled by the maintainer based on the probe's Protokoll output)
- **Acceptance criteria:**
  1. Maintainer copies `tools/probe.lua` into MoneyMoney's `Extensions/` folder (path per PROJECT context: sandboxed App-Store build → `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/`).
  2. Maintainer enables "Inoffizielle Extensions erlauben" in MoneyMoney settings (one-time setting).
  3. Maintainer adds a new account using the "PayPal POS Probe" bank code; the credential field can be any non-empty string.
  4. Maintainer triggers `Aktualisieren` on the probe account.
  5. Maintainer opens MoneyMoney's Protokoll panel, copies the `=== PAYPAL POS PROBE START ===` … `=== PAYPAL POS PROBE END ===` block.
  6. Maintainer transcribes into ADR-0003: Q1 result columns (each global PRESENT/ABSENT), Q4 result (PASS/FAIL + decoded type), Q5 result (counter value; restart MoneyMoney, refresh again, observe whether counter increments), Q7 result (confirm "PayPal POS Probe" appeared in "Konto hinzufügen" — Q7 verifies the labeling mechanism; the production "PayPal POS" label is observed in T13), Q8 result (TLS verified YES/NO).
  7. ADR-0003 status flips from `PROPOSED` to `ACCEPTED` once the five owned cells are filled.
  8. Maintainer deletes the probe extension from `Extensions/` and removes the probe account in MoneyMoney to keep the user's installation clean.
- **Test / spec:** post-fill, `grep -c 'FILL IN' docs/adr/0003-sandbox-probe-results.md` ≤ 3 (Q2, Q3, Q6 may still show `FILL IN`); `grep -q 'ACCEPTED' docs/adr/0003-sandbox-probe-results.md` succeeds.
- **Estimated effort:** M (10–15 minutes of manual MoneyMoney clicks plus a MoneyMoney restart for Q5)
- **Dependencies:** T08 (probe extension exists), T09 (ADR-0003 template exists)
- **Risk callouts:** R1 — if Q7 shows `"PayPal POS Probe"` does not render unambiguously in the UI, ADR-0003's Q7 column captures the actual label and a follow-up task in Phase 2 swaps the production `services` string to `"PayPal POS (Zettle)"` per RESEARCH RQ-5 decision tree. **Key handling:** the probe extension does NOT receive a real PayPal POS API key — any non-empty string suffices to satisfy MoneyMoney's credential UI. There is no risk of leaking a real key during T12.

---

### T13 — Walking-skeleton manual install + observation (maintainer-driven)

- **Requirement traceability:** Walking-Skeleton exit criterion (SKELETON.md §"alive")
- **Probe traceability:** none directly; consumes Q1 result (e.g. `os.time` availability) and Q7 result (label rendering) from T12
- **Files touched:** none. If Q1 (T12) revealed `os` is absent, this task may include a one-line edit to `src/entry.lua` (swap `os.time()` for a hard-coded POSIX integer) followed by a re-run of T02/T05/T06/T10.
- **Acceptance criteria:**
  1. Maintainer runs `lua tools/build.lua` to produce a fresh `dist/paypal-pos.lua`.
  2. Maintainer copies `dist/paypal-pos.lua` into MoneyMoney's `Extensions/` folder.
  3. Maintainer opens MoneyMoney → `Konto hinzufügen` → confirms `PayPal POS` appears in the bank-selection list (Q7 production verification — if the label differs from `"PayPal POS"`, the maintainer updates the `services` string per the RESEARCH RQ-5 decision tree and re-runs from T02).
  4. Maintainer selects `PayPal POS`, pastes any non-empty string into the API-key credential field, completes the add-account flow without error.
  5. The account appears in MoneyMoney's sidebar with the label `PayPal POS — Test-Händler`.
  6. The account view shows the single fixture transaction with `name = "Kartenzahlung"`, `amount = 9.95 EUR`, and a multi-line `purpose` containing the German VAT line and the UUID line.
  7. Maintainer removes the test account from MoneyMoney before declaring the phase complete (housekeeping).
- **Test / spec:** human observation; outcome recorded by the maintainer in `STATE.md` (orchestrator updates `STATE.md` after this task succeeds).
- **Estimated effort:** S
- **Dependencies:** T12 (probe results inform Q1 / Q7 follow-ups; if Q7 forces a label change, T02/T05/T06/T10 re-run before T13 retries)
- **Risk callouts:** R1 (label drift), R2 (`os.time` absence). Both have one-line mitigations pre-defined in RESEARCH.

---

## Task dependency graph

```
T01 ── T02 ─────────────────────────────────┐
   │      │                                  │
   ├── T03 ┘                                  │
   │   │                                      │
   │   ├── T04 ──┐                             │
   │             │                             │
   │             ├── T05 ──┐                    │
   │             │         │                    │
   │             │         ├── T06 ──┐           │
   │             │                    │           │
   │             │                    ├── T07     │
   │             │                                │
   │             └────────── T08 ───────────┐    │
   │                                          │    │
   ├──────────────────────── T09 ─────────────┤    │
   │                                          │    │
   │                                          ├── T10
   │                                          │
   │                                          └── T11
   │
   T08 + T09 ──── T12 ──── T13
```

Ordering enforced by the orchestrator: T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08 → T09 → T10 → T11 → T12 → T13.

T03–T08 can in principle parallelise across separate executor processes, but the orchestrator runs them serially in `mode=yolo` to keep commit history readable and avoid `.luacheckrc` / amalgamator edits racing each other.

CI workflow (T11) is intentionally last in the automation chain because it is meaningful only against a tree where every other gate is already green; it is the second-line enforcer, not the discovery surface.

T12 and T13 are maintainer-driven (Yves), gated by green local CI (T10) and a pushed feature branch with green GitHub Actions (T11).

## Phase exit

Phase 1 is complete when:
- T01–T11 commits land on the Phase-1 feature branch with green local `luacheck`, `busted --coverage`, `lua tools/build.lua --verify`, and a green CI run on GitHub Actions.
- T12 ADR-0003 has Q1, Q4, Q5, Q7, Q8 result cells filled and status flipped to `ACCEPTED`.
- T13 walking-skeleton manual verification has happened and is logged in `.planning/STATE.md`.
- No file under the repo contains AI-attribution patterns: literal `Co-Authored-By: Claude`, `Generated with Claude`, `🤖`, or comparable authorship trailers. Bare mentions of `Claude` / `Anthropic` inside rule statements or the project `CLAUDE.md` instruction file do not count as attribution. (Grep gate the orchestrator runs before merging the feature branch into `main`.)
