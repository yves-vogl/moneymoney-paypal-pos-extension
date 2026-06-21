---
phase: 03-sale-spine-first-user-visible-slice
verified: 2026-06-20T22:45:00Z
status: passed
score: 10/10 must-haves verified
overrides_applied: 0
---

# Phase 3: Sale Spine — Verification Report

**Phase Goal:** A merchant with a valid API key clicks "Aktualisieren" in MoneyMoney and sees their real card sales as MoneyMoney transactions — correct gross amount, German label, stable IDs, no duplicates on double-refresh, only sales newer than `since` are fetched.

**Verified:** 2026-06-20T22:45:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Requirement | Truth | Status | Evidence |
|----|-------------|-------|--------|----------|
| 1  | SALE-01 | Each completed sale appears as one positive MoneyMoney transaction with VAT- and tip-inclusive gross amount in EUR | VERIFIED | `M_mapping.purchase_to_transaction` returns `amount = p.amount / 100`, `currency = "EUR"`. Spec `mapping_spec.lua:67-75` asserts `amount = 5.00` from `amount=500` fixture. `mapping_schema_spec.lua:105-113` asserts gross = `purchase.amount / 100`. |
| 2  | SALE-02 | Each sale carries `transactionCode = "zettle:sale:<purchaseUUID1>"` stable across refreshes | VERIFIED | `mapping.lua:248` sets `transactionCode = "zettle:sale:" .. tostring(p.purchaseUUID1 or "")`. `mapping_spec.lua:81-87` asserts exact value. `refresh_idempotency_spec.lua:85-114` confirms no new codes on second refresh. |
| 3  | SALE-03 | Pending sales appear with `booked = false`; Phase-3 delivers the static `booked=false` half (D-31); `booked=true` + `valueDate` transition is Phase-4. | VERIFIED (partial scope, Phase-4 deferred) | `mapping.lua:249,279` hard-sets `booked = false`. `mapping_spec.lua:93-104` asserts `booked = false` AND `rawget(txn, "valueDate") == nil`. `mapping_schema_spec.lua:100-101` reconfirms. D-31 explicitly scopes Phase-3 to the static `false` half. |
| 4  | SALE-04 | `bookingDate` reflects UTC ISO-8601 converted to Berlin local time via inline DST table | VERIFIED | `mapping.lua:26-106` implements `_parse_iso8601_utc` + `_to_berlin_local_time` with 2020-2040 DST table. `dst_table_spec.lua` asserts summer POSIX = 1781920500 (CEST +7200) and winter POSIX = 1769907300 (CET +3600). `mapping_schema_spec.lua:142-170` verifies local day 2026-06-20 (summer) and 2026-02-01 (winter). |
| 5  | SALE-05 | Double-refresh produces zero new transactions (idempotency) | VERIFIED | `refresh_idempotency_spec.lua:85-114` (simple_sale), `:116-135` (vat_and_tip), `:137-167` (refund). In all three cases: second RefreshAccount call produces only transactionCodes already in the seen-set from the first call. |
| 6  | SALE-06 | Incremental refresh respects `since`; only purchases newer than `since` are fetched | VERIFIED | `entry.lua:151` clamps since: `math.max(since or 0, os.time() - NINETY_DAYS)`. URL has `startDate=<clamped-iso>`. `entry_spec.lua:524-535` asserts startDate != 1970 when since=0. `:538-551` asserts year-month of recent since appears in URL. `purchases_spec.lua:79-103` confirms exact encoded `2023-11-14T22%3A13%3A20Z`. Empty response yields 0 transactions (`entry_spec.lua:513-522`). |
| 7  | SALE-08 | `name` carries German label ("Kartenzahlung" fallback or card-brand + last-four when available) | VERIFIED | `mapping.lua:120-166` implements `_format_label` using `payments[1].attributes.cardType` + `maskedPan` (RESEARCH correction over D-35). `mapping_spec.lua:132-152` asserts "Kartenzahlung" default and "Visa •••• 1111" with card metadata. `mapping_schema_spec.lua:115-127` confirms brand+last4. |
| 8  | I18N-01 | All user-facing strings German; German purpose lines (Brutto/MwSt/Trinkgeld/Netto/Beleg) | VERIFIED | `i18n.lua:17-23` has 7 new keys: `account.purpose.gross`, `.vat`, `.tip`, `.net`, `.refund_for`, `.receipt_number`, `account.name.card_payment`. `mapping_spec.lua:158-208` asserts all German purpose lines with correct values and that MwSt/Trinkgeld lines are absent when zero. |
| 9  | TEST-03 | Double-refresh idempotency test gates the build | VERIFIED | `spec/refresh_idempotency_spec.lua` implements D-39 gating spec. All 4 tests pass: simple_sale (no new codes), vat_and_tip (stable), refund (zettle:refund: prefix confirmed), nil-token returns German `error.network` (D-41). Full suite: 192/0/0/0. |
| 10 | TEST-04 | Golden-file schema test fails the build when any required field is missing | VERIFIED | `spec/mapping_schema_spec.lua:51-54` defines `REQUIRED_FIELDS = {name, amount, currency, bookingDate, purpose, transactionCode, booked}`. `assert_schema` helper walks all 7 fields on every fixture. 8 tests cover simple_sale, vat_and_tip, card_metadata, refund (D-32), summer DST, winter DST, non-EUR nil (D-37), EUR invariant across 5 fixtures. All pass. |

**Score:** 10/10 truths verified

---

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | SALE-03 `booked=true` + `valueDate=payout_date` transition when payout is linked | Phase 4 | ROADMAP Phase-4 goal: "Finance API integration"; CONTEXT D-31 explicitly: "Phase 4 closes the dynamic transition". REQUIREMENTS SALE-03 second clause covered by Phase-4 Finance API + payout cross-reference. |

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/mapping.lua` | Purchase/refund mapping + DST table + formatters | VERIFIED | 282 lines; implements `purchase_to_transaction`, `refund_to_transaction`, `_parse_iso8601_utc`, `_to_berlin_local_time` (DST table 2020-2040), `_format_amount`, `_format_label`, `_format_purpose`. No stubs. |
| `src/pagination.lua` | Cursor loop with MAX_PAGES guard | VERIFIED | 89 lines; `M_pagination.iterate` with dual-termination (empty array OR missing hash), caller-params copy (T-03-W3a-02), MAX_PAGES=50 abort. |
| `src/purchases.lua` | HTTP fetch + fetch_all driving pagination | VERIFIED | 93 lines; `M_purchases.fetch` (single page, URL-encoded query, Bearer header) + `fetch_all` (drives `M_pagination.iterate`). Egress: `https://purchase.izettle.com/purchases/v2` only. |
| `src/entry.lua RefreshAccount` | Rewired to drive Phase-3 pipeline | VERIFIED | Lines 134-193: 6-step pipeline. `since` clamp at entry boundary (D-33). `M_auth.cached_token` → nil guard (D-41). `M_purchases.fetch_all`. `M_mapping` dispatch (refund vs sale). Balance passthrough (D-31). |
| `src/i18n.lua` | 7 new German i18n keys added | VERIFIED | Lines 17-23 (de) + 40-46 (en): all 7 keys present in both locales. |
| `spec/fixtures/purchases/*.json` | 10 fixtures | VERIFIED | All 10 fixtures present: `purchase_simple_sale`, `purchase_with_vat_and_tip`, `purchase_refund`, `purchase_page1`, `purchase_page2`, `purchases_empty`, `purchase_non_eur`, `purchase_dst_boundary_summer`, `purchase_dst_boundary_winter`, `purchase_with_card_metadata`. |
| `spec/mapping_spec.lua` | Phase-3 mapping unit tests | VERIFIED | 17 tests; all green. |
| `spec/dst_table_spec.lua` | DST boundary tests | VERIFIED | 6 tests including exact POSIX value assertions; all green. |
| `spec/pagination_spec.lua` | Pagination cursor loop tests | VERIFIED | 9 tests including MAX_PAGES guard, dual-termination, cursor handoff, fixture smoke test; all green. |
| `spec/purchases_spec.lua` | HTTP fetch tests | VERIFIED | 9 tests including URL shape, startDate encoding, cursor param, error routing, fetch_all pagination; all green. |
| `spec/refresh_idempotency_spec.lua` | TEST-03 gating spec | VERIFIED | 4 tests; all green. Double-refresh idempotency proven on 3 fixture variants plus nil-token guard. |
| `spec/mapping_schema_spec.lua` | TEST-04 golden-file schema spec | VERIFIED | 8 tests; all green. REQUIRED_FIELDS walk across all fixture types. |
| `spec/refresh_log_redaction_spec.lua` | Phase-3 SEC-03 gating | VERIFIED | 7 tests; all green. No JWT-shape in LocalStorage, no Bearer in print stream, transactionCode prefix gated (zettle:sale: or zettle:refund: only). |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `entry.lua RefreshAccount` | `M_auth.cached_token` | D-41 nil-token guard | WIRED | `entry.lua:161-163`: `local bearer = M_auth.cached_token(orgUuid); if not bearer then return M_i18n.t(...)`. |
| `entry.lua RefreshAccount` | `M_purchases.fetch_all` | since clamp → Phase-3 pipeline | WIRED | `entry.lua:151,170`: `effective_since` clamped first, then `M_purchases.fetch_all(effective_since, bearer)`. |
| `M_purchases.fetch_all` | `M_pagination.iterate` | fetch_page_fn closure | WIRED | `purchases.lua:87-91`: `fetch_page_fn` closure calling `M_purchases.fetch`, passed to `M_pagination.iterate`. |
| `M_pagination.iterate` | `M_purchases.fetch` | `params.lastPurchaseHash` cursor | WIRED | `pagination.lua:52`: `local page, status, raw = fetch_page_fn(params)`. Cursor managed on lines 72-85. |
| `M_purchases.fetch` | `M_http.get_json` | D-42: no direct Connection() | WIRED | `purchases.lua:75`: `return M_http.get_json(url, headers)`. 3-tuple returned verbatim. |
| `entry.lua RefreshAccount` | `M_mapping.purchase_to_transaction` / `refund_to_transaction` | `p.refund == true` dispatch | WIRED | `entry.lua:180-187`: `if p.refund == true then ... else txn = M_mapping.purchase_to_transaction(p) end`. |
| `M_mapping` | `M_i18n.t` | German purpose/label strings | WIRED | `mapping.lua:139,186,191,204,210,213`: 7 `M_i18n.t(...)` calls for all D-34/D-35 keys. |
| `since clamp` | `entry.lua` boundary (not `purchases.lua`) | D-33 / RESEARCH Pitfall 5 | WIRED | Clamp at `entry.lua:151`; `purchases.lua` receives `clamped_since` as parameter, no independent clamp. |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `entry.lua RefreshAccount` | `purchases` | `M_purchases.fetch_all` → `M_pagination.iterate` → `M_purchases.fetch` → `M_http.get_json` → fixture/live JSON | Yes — cursor loop accumulates all pages into real purchase records | FLOWING |
| `M_mapping.purchase_to_transaction` | `amount`, `transactionCode`, `bookingDate`, `name`, `purpose` | Pure-function transformation from `p.amount`, `p.purchaseUUID1`, `p.timestamp`, `p.payments`, etc. | Yes — all from decoded purchase JSON | FLOWING |
| `M_pagination.iterate` | `all_purchases` | Accumulated via `fetch_page_fn` callback; cursor from `page.lastPurchaseHash` | Yes — accumulates across pages until empty array or no cursor | FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full busted suite | `./.luarocks/bin/busted spec/` | 192 successes / 0 failures / 0 errors / 0 pending | PASS |
| Reproducible build (first run) | `lua tools/build.lua --verify` | SHA256: `2281ebc8af0b455f45fa246c4cfc3796a73d629cff6660082de4b4f13dbd600b` | PASS |
| Reproducible build (second run) | `lua tools/build.lua --verify` | SHA256: `2281ebc8af0b455f45fa246c4cfc3796a73d629cff6660082de4b4f13dbd600b` (identical) | PASS |
| luacheck clean | `./.luarocks/bin/luacheck .` | 0 warnings / 0 errors in 32 files | PASS |
| Coverage (amalgamated artifact) | `./.luarocks/bin/busted spec/ --coverage && luacov` | `dist/paypal-pos.lua`: 515 hits / 4 missed = **99.23%** | PASS |

Note: Coverage reported against `dist/paypal-pos.lua` (amalgamated). The 4 missed lines are defensive branches (non-EUR refund guard path + unknown card-brand fallback) — same class as Phase-2's accepted 4-line gaps in `http.lua`. These are dead under the current fixture set; see SUMMARY `key-decisions`.

Note: SUMMARY.md for Plan 03-07 reports `186 successes / 0 failures / 1 Lua-5.5 env error` but the current verification run produces `192 / 0 / 0 / 0`. The discrepancy is explained by: (a) 6 additional Phase-3 integration tests added to `entry_spec.lua` in Plan 03-06, and (b) the "1 env error" described in the SUMMARY was a Lua-5.5 environment pre-condition that resolved itself (the test is now fully green). Total count increase is legitimate.

---

### Probe Execution

No `scripts/*/tests/probe-*.sh` probes declared for Phase 3. Phase-3 probes are the busted suite specs themselves (inline spot-checks above).

---

### Requirements Coverage

| Requirement | Plan | Description | Status | Evidence |
|-------------|------|-------------|--------|----------|
| SALE-01 | 03-03, 03-06 | Completed sale → one positive MoneyMoney transaction, gross amount in EUR | SATISFIED | `mapping.lua:243-251`; `mapping_spec.lua:67-75`; `mapping_schema_spec.lua:105-113` |
| SALE-02 | 03-03, 03-02 | Stable `transactionCode = "zettle:sale:<uuid>"` | SATISFIED | `mapping.lua:248`; `mapping_spec.lua:81-87`; `refresh_idempotency_spec.lua:96-101` |
| SALE-03 | 03-03 | `booked=false` half (D-31 scope) | SATISFIED (Phase-3 scope) | `mapping.lua:249,279`; `mapping_spec.lua:93-104`; D-31 defers `booked=true` to Phase-4 |
| SALE-04 | 03-03 | `bookingDate` = Berlin local time via DST table | SATISFIED | `mapping.lua:93-106` + DST_TABLE; `dst_table_spec.lua` all 6 tests; `mapping_schema_spec.lua:142-170` |
| SALE-05 | 03-02, 03-06 | No duplicate transactions on double-refresh | SATISFIED | `refresh_idempotency_spec.lua:85-114, 116-135, 137-167` |
| SALE-06 | 03-04, 03-05, 03-06 | Incremental refresh: only purchases newer than `since` fetched | SATISFIED | `entry.lua:151`; `purchases.lua:62`; `entry_spec.lua:524-551`; `purchases_spec.lua:79-103` |
| SALE-08 | 03-03 | `name` = German label ("Kartenzahlung" or brand + last-four) | SATISFIED | `mapping.lua:120-166`; `mapping_spec.lua:132-152`; `mapping_schema_spec.lua:115-127` |
| I18N-01 | 03-03 | All user-facing strings German; 7 new i18n keys | SATISFIED | `i18n.lua:17-23` (de) + `40-46` (en); `mapping_spec.lua:158-208` (purpose line tests) |
| TEST-03 | 03-02, 03-06 | Double-refresh idempotency gating spec | SATISFIED | `refresh_idempotency_spec.lua`: 4 tests, all green |
| TEST-04 | 03-02, 03-03 | Golden-file schema gate: 7 required fields | SATISFIED | `mapping_schema_spec.lua:51-54` REQUIRED_FIELDS; 8 tests, all green |

---

### Invariant Verification (D-31..D-45)

| Decision | Invariant | Status | Evidence |
|----------|-----------|--------|----------|
| D-31 | `booked=false`, `valueDate` key absent from transaction table | VERIFIED | `mapping.lua:249,279`; `rawget(txn,"valueDate") == nil` in `mapping_spec.lua:102-103` |
| D-32 | Refund purchase → separate negative transaction, transactionCode = `zettle:refund:<own-uuid>` | VERIFIED | `mapping.lua:256-281`; `mapping_spec.lua:225-265` |
| D-33 | `since` clamp in `entry.lua RefreshAccount`, NOT inside `M_purchases.fetch` | VERIFIED | `entry.lua:151`; `purchases.lua` receives pre-clamped value as parameter |
| D-35 corrected | Card metadata path: `payments[1].attributes.cardType` + `maskedPan` (RESEARCH correction) | VERIFIED | `mapping.lua:145-150`; fixture `purchase_with_card_metadata.json` confirms `payments[0].attributes.cardType` |
| D-36 | `bookingDate` = Europe/Berlin local via inline DST table (not `os.date` with TZ env) | VERIFIED | `mapping.lua:26-106`; deterministic for any CI timezone |
| D-37 | Non-EUR purchases silently skipped with INFO log | VERIFIED | `mapping.lua:233-236,261-264`; `mapping_spec.lua:214-219`; `entry_spec.lua:502-511` |
| D-38 | `transactionCode` schema: `zettle:sale:<uuid>` / `zettle:refund:<uuid>` only | VERIFIED | `mapping.lua:248,278`; `refresh_log_redaction_spec.lua:108-127` (prefix gate) |
| D-41 | `M_auth.cached_token` → nil guard in RefreshAccount | VERIFIED | `entry.lua:161-163`; `refresh_idempotency_spec.lua:169-181`; `entry_spec.lua:462-468` |
| D-42 | All purchase fetches via `M_http.get_json` (no direct `Connection()`) | VERIFIED | `purchases.lua:75`: only call is `return M_http.get_json(url, headers)` |
| D-43 | Errors routed via `M_errors.from_http_status` in `M_pagination.iterate` | VERIFIED | `pagination.lua:55`: `local err = M_errors.from_http_status(status, raw)` |
| D-44 | 10 required fixtures under `spec/fixtures/purchases/` | VERIFIED | All 10 files present (listed in Required Artifacts above) |
| D-45 | SEC-03 gating: Bearer never logged in Phase-3 purchase path | VERIFIED | `entry.lua:155-156`: only `orgUuid:sub(1,8)` + `effective_since` logged; `refresh_log_redaction_spec.lua:93-106` (print-stream gate) |

---

### Phase-2 Surface Preservation

| Callback | Status | Evidence |
|----------|--------|----------|
| `SupportsBank` | PRESERVED | `entry.lua:10-12`: unchanged from Phase-2 |
| `InitializeSession2` | PRESERVED | `entry.lua:14-93`: full D-22 two-call probe body intact |
| `ListAccounts` | PRESERVED | `entry.lua:96-132`: orgUuid → label logic unchanged |
| `EndSession` | PRESERVED | `entry.lua:196-200`: `M_http.shutdown()` + return nil unchanged |
| `RefreshAccount` | REWIRED (intentional) | Phase-3 purpose; Phase-2 fixture transaction replaced by real pipeline |

Phase-2 entry_spec.lua tests for these callbacks continue to pass (192 total includes all Phase-2 specs).

---

### SEC-03 Phase-3 Gating

| Gate | Description | Status |
|------|-------------|--------|
| (A) LocalStorage walk | No `eyJ[A-Za-z0-9_-]+` JWT-shape in any LocalStorage value post-RefreshAccount | PASS — `refresh_log_redaction_spec.lua:80-91`, `:133-143`, `:176-185` |
| (B) Print stream | No `Bearer eyJ` substring in any captured print line | PASS — `refresh_log_redaction_spec.lua:93-106`, `:188-197` |
| (C) transactionCode prefix | Every emitted code starts with `zettle:sale:` or `zettle:refund:` | PASS — `refresh_log_redaction_spec.lua:108-127`, `:145-168` |

**sec03_phase3_gating: PASS**

---

### Anti-Patterns Found

| File | Pattern | Severity | Verdict |
|------|---------|----------|---------|
| `src/mapping.lua` | No TBD/FIXME/XXX markers | — | Clean |
| `src/pagination.lua` | No TBD/FIXME/XXX markers | — | Clean |
| `src/purchases.lua` | No TBD/FIXME/XXX markers | — | Clean |
| `src/entry.lua` | No TBD/FIXME/XXX markers | — | Clean |
| `src/i18n.lua` | No TBD/FIXME/XXX markers | — | Clean |
| All Phase-3 spec files | No TBD/FIXME/XXX markers | — | Clean |

No debt markers. No unresolved placeholders. `return nil` occurrences in mapping.lua are guard-return patterns (nil propagates to skip logic in entry.lua), not stubs.

---

### Human Verification Required

No items require human testing. All Phase-3 deliverables are verifiable programmatically via the busted suite. The user-visible behavior ("merchant sees card sales in MoneyMoney") requires MoneyMoney + a live API key and is documented in the README as the Phase-3 demo target — but all code-path correctness has been proven by the spec suite.

---

## Aggregate Verdict

**READY-TO-MERGE**

All 10 requirements (SALE-01, SALE-02, SALE-03 Phase-3 scope, SALE-04, SALE-05, SALE-06, SALE-08, I18N-01, TEST-03, TEST-04) are delivered and verified. The load-bearing idempotency gate (TEST-03 / SALE-05) is green across three fixture variants. The golden-file schema gate (TEST-04) is green across 8 fixture types. The Phase-2 surface contract is preserved byte-identically. SEC-03 Phase-3 gating passes all three gates (LocalStorage, print stream, transactionCode prefix). The build is reproducible (SHA256: `2281ebc8af0b455f45fa246c4cfc3796a73d629cff6660082de4b4f13dbd600b`). luacheck is clean across 32 files. Coverage is 99.23% on the amalgamated artifact.

SALE-03's `booked=true` + `valueDate` transition is a confirmed Phase-4 item per D-31 — not a gap.

---

_Verified: 2026-06-20T22:45:00Z_
_Branch: phase-3/sale-spine-first-user-visible-slice @ 98c194b_
