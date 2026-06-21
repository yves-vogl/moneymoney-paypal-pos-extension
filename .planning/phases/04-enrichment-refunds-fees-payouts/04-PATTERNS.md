# Phase 4: Enrichment — Refunds, Fees, Payouts, Balance, VAT, Tips — Pattern Map

**Mapped:** 2026-06-21
**Files analyzed:** 17 (5 source new/modified, 1 doc/CI, 8 spec new/modified, 9 fixtures, 1 i18n extension)
**Analogs found:** 14 / 17 strong (3 genuinely new patterns flagged)

> **Planner note — module naming:** CONTEXT/RESEARCH refer to `src/finance.lua` as the new module, but the Phase-1 stubs currently in repo are `src/balance.lua` + `src/payouts.lua`. Wave-1 must reconcile: either (a) consolidate into a single `src/finance.lua` and delete the two stubs (recommended — matches the Finance API surface), or (b) keep two modules and split (`M_balance` for `/v2/accounts/*/balance`, `M_payouts` for `/v2/accounts/liquid/transactions`). Option (a) is the dominant analog shape (one module per upstream API host, c.f. `src/purchases.lua` for the Purchase API). The webbanking_header manifest order in `03-PATTERNS.md` Metadata must be updated accordingly.

---

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `src/finance.lua` (NEW; replaces balance.lua + payouts.lua stubs) | data-fetcher | request-response + dual-fetch | `src/purchases.lua` (single-host fetch + fetch_all driver) | **exact** for `fetch`/`fetch_all`; **new pattern** for `fetch_account_state` dual-GET |
| `src/pagination.lua` (EXTEND; add `offset_iterate` sibling) | utility / iterator | offset-loop | `src/pagination.lua` `M_pagination.iterate` (same file, cursor sibling) | **role-match** (sibling iterator; D-48 explicitly mandates parallel, NOT modify) |
| `src/mapping.lua` (EXTEND; +4 functions, extend `_format_purpose`) | pure mapper | transform | `src/mapping.lua` `purchase_to_transaction` / `refund_to_transaction` (same file) | **exact** |
| `src/entry.lua` (EXTEND `RefreshAccount` only) | orchestrator | request-response + cross-ref | `src/entry.lua` `RefreshAccount` Phase 3 body (lines 139–198) | **exact** |
| `src/i18n.lua` (EXTEND; +12 keys) | config/locale | transform | `src/i18n.lua` Phase-3 additions | **exact** |
| `spec/finance_spec.lua` (NEW) | spec | request-response | `spec/purchases_spec.lua` (HTTP mock + Bearer header capture) | **exact** |
| `spec/pagination_offset_spec.lua` (NEW) | spec | offset-loop | `spec/pagination_spec.lua` (multi-push_response, terminal-empty) | **exact** |
| `spec/mapping_spec.lua` (EXTEND; +fee/payout/promote cases) | spec | transform | `spec/mapping_spec.lua` (same file, pure-logic + fixture-driven) | **exact** |
| `spec/mapping_schema_spec.lua` (EXTEND; cover fee+payout txns) | spec (invariant gate) | transform | `spec/mapping_schema_spec.lua` `REQUIRED_FIELDS` walk (same file) | **exact** |
| `spec/refresh_idempotency_spec.lua` (EXTEND; +4 D-58 cases) | spec (integration gate) | request-response | `spec/refresh_idempotency_spec.lua` Phase-3 body (same file) | **exact** |
| `spec/refresh_log_redaction_spec.lua` (EXTEND; new prefixes + Finance fixtures) | spec (invariant gate) | transform | `spec/refresh_log_redaction_spec.lua` Phase-3 body (same file) | **exact** |
| `spec/meta_no_tax_classification_spec.lua` (NEW; META-03) | spec (invariant gate) | static-walk | `spec/refresh_log_redaction_spec.lua` `walk_storage` + filesystem read pattern | **role-match** (extends pattern to read `src/*.lua` text) |
| `spec/meta_purpose_lines_spec.lua` (NEW; META-02 promotion) | spec | transform | `spec/mapping_spec.lua` zero-suppression sub-cases | **exact** |
| `spec/finance_account_state_spec.lua` (NEW) | spec | request-response | `spec/purchases_spec.lua` (single GET assertion shape) | **role-match** (dual-GET — new) |
| `spec/fixtures/finance/*.json` (NEW; 6 fixtures) | fixture | — | `spec/fixtures/purchases/*.json` (Fixtures.load path + dkjson decode) | **exact** |
| `spec/fixtures/purchases/purchase_vat_split_19_7.json` + `purchase_with_card_metadata_kontaktlos.json` + `purchase_umlauts_purpose.json` (NEW) | fixture | — | existing `spec/fixtures/purchases/purchase_with_card_metadata.json` shape | **exact** |
| CI egress allowlist update (`.github/workflows/*` grep or `tests/repro_build_spec.lua`) | config | — | existing SEC-02 allowlist for `oauth.zettle.com` + `purchase.izettle.com` | **exact** (add `finance.izettle.com` host) |

---

## Pattern Assignments

### `src/finance.lua` — data-fetcher, request-response + dual-fetch

**Primary analog:** `src/purchases.lua` (whole file, 97 lines).

**Module preamble** — copy shape from `src/purchases.lua` L1-10:

```lua
-- src/purchases.lua L1-7:
-- src/purchases.lua
-- Ownership: SALE-06 / D-33 / D-42 / D-43.
-- Provides: M_purchases.fetch(clamped_since, bearer, cursor) -- single-page GET
--           M_purchases.fetch_all(clamped_since, bearer) -- drives M_pagination.iterate
-- The M_purchases table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02: amalgamator resolves cross-module
-- refs at build time via the shared module-table globals).
```

Phase-4 `src/finance.lua` preamble: Ownership = ACCT-03 / FEE-01..03 / PAYOUT-01..03 / D-46..D-49 / D-52. Provides four functions: `fetch`, `fetch_all`, `fetch_account_state`, `parse_transaction`.

**Single-page GET pattern** — copy `src/purchases.lua` L57-81 (`M_purchases.fetch`) verbatim shape:

```lua
-- src/purchases.lua L57-81 — exact shape to mirror for M_finance.fetch:
function M_purchases.fetch(clamped_since, bearer, cursor)
  assert(type(bearer) == "string" and #bearer > 0,
    "M_purchases.fetch: bearer must be a non-empty string")
  local q = {
    descending = "false",
    limit      = "200",
    startDate  = _iso8601_utc(clamped_since),
  }
  if type(cursor) == "string" and #cursor > 0 then
    q.lastPurchaseHash = cursor
  end
  local url = "https://purchase.izettle.com/purchases/v2?" .. _url_encode_query(q)
  local headers = { Authorization = "Bearer " .. tostring(bearer) }
  return M_http.get_json(url, headers)
end
```

Phase-4 `M_finance.fetch(clamped_since, bearer, offset)` adapts:
- replace cursor param with integer `offset` (default 0); always include `offset` + `limit` in `q`
- `start` + `end` are **required** per RESEARCH §1.3 → both always built; date format is `YYYY-MM-DDThh:mm:ss` (no `Z`, no millis) — distinct from Phase-3 helper. Either add a `_iso8601_utc_no_z(posix)` local helper or pass a `with_z` flag.
- URL: `"https://finance.izettle.com/v2/accounts/liquid/transactions?" .. _url_encode_query(q)`
- query must repeat `includeTransactionType=` three times. **`_url_encode_query` cannot emit repeated keys** (table key dedup) — encode as an explicit suffix string appended after `_url_encode_query`, e.g. `url .. "&includeTransactionType=PAYMENT&includeTransactionType=PAYMENT_FEE&includeTransactionType=PAYOUT"`.

**`fetch_all` driver pattern** — copy `src/purchases.lua` L91-97 (`M_purchases.fetch_all`):

```lua
-- src/purchases.lua L91-97 — driver shape:
function M_purchases.fetch_all(clamped_since, bearer)
  local fetch_page_fn = function(params)
    return M_purchases.fetch(clamped_since, bearer, params.lastPurchaseHash)
  end
  return M_pagination.iterate(fetch_page_fn, {})
end
```

Phase-4 `M_finance.fetch_all(clamped_since, bearer)`: same closure shape, but call `M_pagination.offset_iterate(fetch_page_fn, { offset = 0, limit = 1000 })`; the closure reads `params.offset` rather than `params.lastPurchaseHash`.

**`fetch_account_state(bearer)` — NEW PATTERN (no Phase-3 analog)**

Issues TWO sequential `M_http.get_json` calls against `/v2/accounts/liquid/balance` and `/v2/accounts/preliminary/balance` (RESEARCH §1.4). Recommended shape: same `assert(bearer)` guard, then two sequential calls with error-routing after EACH per the Phase-3 idiom (entry.lua L62-64). Returns `{ balance, pendingBalance, error }` table OR `(nil, err)`. Document in code that two HTTP calls per refresh are by-design.

```lua
-- New pattern — sequential dual-fetch:
-- 1) M_http.get_json("https://finance.izettle.com/v2/accounts/liquid/balance", auth)
--    → route through M_errors.from_http_status; on err return nil, err
--    → extract .data.totalBalance / 100; currency guard per D-37 (RESEARCH §1.4)
-- 2) M_http.get_json("https://finance.izettle.com/v2/accounts/preliminary/balance", auth)
--    → same error-routing; same currency guard
-- Return { balance = <liquid>, pendingBalance = <preliminary> }
```

**`parse_transaction(raw)` — pure-logic** — copy shape from `src/mapping.lua` `_parse_iso8601_utc` (L79-106): nil-guards, type checks, return table on success / nil on malformed. The Finance API timestamp `2020-07-04T20:16:44.309+0000` reuses `M_mapping._parse_iso8601_utc` byte-identically (RESEARCH §1.6 confirms).

---

### `src/pagination.lua` — extend with `offset_iterate` sibling

**Analog:** `src/pagination.lua` `M_pagination.iterate` (same file, L30-88) — **clone-and-adapt**, do NOT modify per D-48.

**Loop body to mirror** — `src/pagination.lua` L30-88:

```lua
-- src/pagination.lua L30-66 — the exact pattern to clone:
M_pagination.iterate = function(fetch_page_fn, initial_params)
  local all_purchases = {}
  local params = {}
  for k, v in pairs(initial_params) do
    params[k] = v
  end
  local page_count = 0
  repeat
    page_count = page_count + 1
    if page_count > MAX_PAGES then
      M_log.warn("M_pagination.iterate: MAX_PAGES exceeded, aborting")
      return nil, M_i18n.t("error.network", "max_pages")
    end
    local page, status, raw = fetch_page_fn(params)
    local err = M_errors.from_http_status(status, raw)
    if err then return nil, err end
    if type(page) ~= "table" or type(page.purchases) ~= "table" then
      return nil, M_i18n.t("error.network", "bad_page")
    end
    for _, p in ipairs(page.purchases) do
      all_purchases[#all_purchases + 1] = p
    end
    ...
  until ...
end
```

`offset_iterate` adaptations (RESEARCH §1.6 termination: "empty OR shorter than limit"):
- Initial `params = { offset = 0, limit = 1000 }` (caller passes; closure preserves caller-table copy invariant per L33-37).
- Response field is `page.data` (Finance API), not `page.purchases`. The bad-page guard checks `type(page.data) == "table"`.
- Termination: `has_more = (#page.data == params.limit)` — when shorter or empty, stop.
- Cursor update: `params.offset = params.offset + params.limit`.
- Same `MAX_PAGES = 50` constant (already module-local; reuse).
- Same error-routing via `M_errors.from_http_status` (D-43 inheritance).

**Reuse the existing module-level `MAX_PAGES`** (L14) — do not duplicate.

---

### `src/mapping.lua` — extend with fee / payout / aggregate / promote mappers + `_format_purpose` extensions

**Analog:** `src/mapping.lua` `purchase_to_transaction` (L248-278) and `refund_to_transaction` (L285-314) — same file.

**Public-function pattern** — copy `src/mapping.lua` L248-278:

```lua
-- src/mapping.lua L248-278 — guard-then-build-table pattern:
function M_mapping.purchase_to_transaction(p)
  if type(p) ~= "table" then return nil end
  if type(p.currency) ~= "string" or p.currency ~= "EUR" then
    local cur = tostring(p.currency or "<nil>"):sub(1, 8)
    M_log.info("M_mapping.purchase_to_transaction: skipping non-EUR purchase currency=" .. cur)
    return nil
  end
  if type(p.purchaseUUID1) ~= "string" or #p.purchaseUUID1 == 0 then
    M_log.warn("M_mapping.purchase_to_transaction: skipping purchase with missing purchaseUUID1")
    return nil
  end
  local utc = _parse_iso8601_utc(p.timestamp)
  local booking_date = utc and _to_berlin_local_time(utc) or os.time()
  return {
    name           = _format_label(p.payments),
    amount         = (p.amount or 0) / 100,
    currency       = "EUR",
    bookingDate    = booking_date,
    purpose        = _format_purpose(p, {kind = "sale"}),
    transactionCode = "zettle:sale:" .. p.purchaseUUID1,
    booked         = false,
  }
end
```

Phase-4 mappers (`fee_to_transaction`, `fee_aggregate_to_transaction`, `payout_to_transaction`) follow this exact shape:
1. `type(record) ~= "table"` → nil
2. Nil-guard the identifier used in `transactionCode` (per S-03/LO-03; for fees+payouts this is `record.originatingTransactionUuid`, per RESEARCH §3.4 which notes Finance records have no `uuid` field of their own)
3. Parse timestamp via `_parse_iso8601_utc` + `_to_berlin_local_time` (the DST_TABLE at L27-59 covers 2020-2050 — reuse byte-identically)
4. Return 7-field MoneyMoney transaction table (same `REQUIRED_FIELDS` schema as `mapping_schema_spec.lua` L51-54)
5. `booked = true` (Finance records ARE settled by definition — RESEARCH §3.4)
6. For payout: also set `valueDate = bookingDate` (the payout IS the settlement event)

**`promote_to_booked` mutator pattern** — copy private-helper shape from `src/mapping.lua` `_b64url_decode`-style guarded helpers (cf. `src/auth.lua` L11-21 referenced in 03-PATTERNS):

```lua
function M_mapping.promote_to_booked(txn, valueDate_posix_local)
  if type(txn) ~= "table" then return end
  txn.booked    = true
  txn.valueDate = valueDate_posix_local
end
```

Idempotent; pure-logic; mutates in place (RESEARCH §4.4).

**`_format_purpose` extension** — extend `src/mapping.lua` `_format_purpose` (L187-234) ADDITIVELY:

```lua
-- src/mapping.lua L200-209 — existing single-VAT line to fall through from:
local vat = type(p.vatAmount) == "number" and p.vatAmount or 0
if vat ~= 0 then
  lines[#lines + 1] = M_i18n.t("account.purpose.vat", _format_amount(vat))
end
```

Phase-4 D-53: before this `if vat ~= 0` block, check `groupedVatAmounts` count. If `>= 2` entries, emit per-rate lines (sorted DESC by rate, format `"%s%% MwSt: %s EUR"` per RESEARCH §5.2) AND skip the single-line `vat` branch. If `0` or `1` entries, fall through to existing L207-209 unchanged.

**Card-tail extension (D-57)** — append after the existing `Beleg #` line (L231) or as a separate line above it per Claude's-Discretion recommendation in CONTEXT. Emit only when `payments[1].attributes.cardType` AND `cardPaymentEntryMode` both present. Use `_format_label`'s existing `BRAND_MAP` (L139-146) for brand display; add a new `ENTRY_MODE_MAP` local table mapping `CONTACTLESS_EMV` / `ICC` / `ECOMMERCE` / `MSR` → i18n keys (RESEARCH §6.1).

---

### `src/entry.lua` — extend `RefreshAccount` only

**Analog:** `src/entry.lua` `RefreshAccount` (same file, L139-198) — extend in place; **do NOT touch the four FROZEN callbacks** (SupportsBank, InitializeSession2, ListAccounts, EndSession) per CONTEXT Specifics.

**Phase-3 sequential pattern to extend** — `src/entry.lua` L142-197:

```lua
-- src/entry.lua L142-175 — guard-and-fetch shape to preserve:
local orgUuid = account and account.accountNumber
if type(orgUuid) ~= "string" or orgUuid == "" then
  return M_i18n.t("error.network", "missing_account")
end
local effective_since = math.max(since or 0, os.time() - NINETY_DAYS)
effective_since = math.min(effective_since, os.time())
M_log.info("RefreshAccount called for org=" .. tostring(orgUuid):sub(1, 8) ..
  " since=" .. tostring(effective_since))
local bearer = M_auth.cached_token(orgUuid)
if not bearer then
  return M_i18n.t("error.network", "\xe2\x80\x94")
end
local purchases, fetch_err = M_purchases.fetch_all(effective_since, bearer)
if fetch_err then return fetch_err end
```

Phase-4 RefreshAccount inserts after the purchases fetch (`if fetch_err then return fetch_err end`):

1. `local account_state, state_err = M_finance.fetch_account_state(bearer)` → `if state_err then return state_err end` (Phase-4 ERR-06 fail-whole-refresh, same idiom)
2. `local fin_records, fin_err = M_finance.fetch_all(effective_since, bearer)` → `if fin_err then return fin_err end`
3. Build `purchases_by_uuid` index (D-50; RESEARCH §2.1 exact code):
   ```lua
   local purchases_by_uuid = {}
   for _, p in ipairs(purchases or {}) do
     if type(p) == "table" and type(p.purchaseUUID1) == "string" and #p.purchaseUUID1 > 0 then
       purchases_by_uuid[p.purchaseUUID1] = p
     end
   end
   ```
4. Build `payments_by_uuid` index (D-49 / FEE-01, RESEARCH §3.1):
   ```lua
   local payments_by_uuid = {}
   for _, purchase in ipairs(purchases or {}) do
     if type(purchase) == "table" and type(purchase.payments) == "table" then
       for _, payment in ipairs(purchase.payments) do
         if type(payment) == "table"
             and type(payment.uuid) == "string"
             and #payment.uuid > 0 then
           payments_by_uuid[payment.uuid] = purchase
         end
       end
     end
   end
   ```
5. The existing Phase-3 `for _, p in ipairs(purchases or {})` loop (L182-192) stays UNCHANGED for sale/refund mapping. For refunds, plumb the new `opts` arg by looking up `purchases_by_uuid[p.refundsPurchaseUUID1]` and passing `{ original_receipt = original.purchaseNumber }`.
6. Split `fin_records` into `fin_payments` / `fin_fees` / `fin_payouts` (RESEARCH §4.3 code). Sort payouts ascending by timestamp.
7. SALE-03 promotion sweep (RESEARCH §4.3): for each sale txn, walk parent purchase's `payments[]`, look up matching finance PAYMENT, find earliest covering PAYOUT, call `M_mapping.promote_to_booked(txn, payout.timestamp_local)`.
8. Fee linkage classification (RESEARCH §3 + D-49): cluster fees by Berlin-local date; for each date, if ANY fee is unlinked, aggregate ALL fees for that date (recommendation: Option B from RESEARCH §3.5) — emit one `fee_aggregate_to_transaction` row; else emit per-sale `fee_to_transaction` rows.
9. Map payouts via `payout_to_transaction`.
10. Return `{ balance = account_state.balance, pendingBalance = account_state.pendingBalance, transactions = combined }`.

**Inheritance**: keep the `-- luacheck: ignore 431` annotation on L139 (callback args). Keep `M_log.info` redaction discipline (no Bearer in logs).

**Indexes-as-closures-inside-RefreshAccount** — CONTEXT Claude's-Discretion recommendation. Matches the pattern of `_iso8601_utc` / `_url_encode_query` as `local function` inside `src/purchases.lua` (L16-41).

---

### `src/i18n.lua` — extend STRINGS tables (+12 keys, de + en)

**Analog:** `src/i18n.lua` STRINGS tables (Phase-3 additions). Pattern is identical: add new keys alongside existing ones, both `de` (primary) and `en` (technical fallback).

New keys per CONTEXT D-57 + RESEARCH §6 + D-49:
- `account.purpose.fee_label`
- `account.purpose.fee_for_receipt`
- `account.purpose.fee_aggregate` (with `%d` count placeholder)
- `account.name.payout` → `"Auszahlung an Bankkonto"`
- `account.name.fee` → `"Geb\xc3\xbchr"` (UTF-8 ü)
- `account.name.fee_aggregate` → `"PayPal POS Transaktionsgeb\xc3\xbchren"`
- `account.purpose.payment_method.kontaktlos` / `.chip` / `.swipe` / `.magstripe` / `.unknown`

UTF-8 byte-escapes for umlauts follow Phase-3 conventions (cf. `src/entry.lua` L167 `"\xe2\x80\x94"` em-dash, `src/mapping.lua` L304 `"R\xc3\xbcckerstattung"`).

---

### `spec/finance_spec.lua` — HTTP mock spec

**Analog:** `spec/purchases_spec.lua` — exact preamble + URL/header capture pattern documented in 03-PATTERNS.md.

Tests cover (RESEARCH §1.3 + §1.7):
- happy path: queue `finance_single_page.json` fixture, call `M_finance.fetch`, assert URL contains `start=`, `end=`, `limit=`, `offset=`, three `includeTransactionType=` repetitions
- Bearer header capture: `Mocks._last_request.headers.Authorization` matches `"Bearer AT-VALID"`
- nil-bearer assertion fires (mirror `src/purchases.lua` L61-62 belt-and-suspenders pattern)
- error routing: 401 → LoginFailed; 429 → German rate-limit string; 5xx → German network string (table-driven, copy `spec/errors_spec.lua` shape)

---

### `spec/pagination_offset_spec.lua` — offset-loop spec

**Analog:** `spec/pagination_spec.lua` (Phase 3 cursor iterator spec).

Tests cover:
- single page (< limit) → terminates after 1 fetch (RESEARCH §1.6 termination rule)
- exact-limit page → second fetch, second returns empty → terminates
- error mid-pagination → return `(nil, err)` immediately
- MAX_PAGES guard → after 50 full-limit pages, log warn + return `(nil, error.network("max_pages"))`
- caller's `initial_params` table is NOT mutated (mirror `spec/pagination_spec.lua` invariant assertion)

Queue multiple `Mocks.push_response` calls per `03-PATTERNS.md` § `pagination_spec.lua` pattern.

---

### `spec/mapping_schema_spec.lua` — EXTEND to cover fee + payout transactions

**Analog:** same file (L51-67 `REQUIRED_FIELDS` walk + `assert_schema` helper). No new required fields per CONTEXT: same 7-field contract.

```lua
-- spec/mapping_schema_spec.lua L51-67 — REQUIRED_FIELDS + assert_schema:
local REQUIRED_FIELDS = {
  "name", "amount", "currency", "bookingDate",
  "purpose", "transactionCode", "booked",
}
local function assert_schema(txn, label)
  assert.is_table(txn, label .. ": ... must return a table, got: " .. tostring(txn))
  for _, field in ipairs(REQUIRED_FIELDS) do
    assert.is_not_nil(txn[field], label .. ": missing required field '" .. field .. "'")
  end
end
```

Phase-4 additions: one `it()` per new mapper (`fee_to_transaction`, `fee_aggregate_to_transaction`, `payout_to_transaction`, `promote_to_booked`), each calling `assert_schema(txn, "<name>")` plus mapper-specific assertions (e.g. `assert.is_true(txn.booked)` for fees+payouts; `assert.equals(bookingDate, txn.valueDate)` for payouts).

---

### `spec/refresh_idempotency_spec.lua` — EXTEND with D-58 cases

**Analog:** same file (L54-81 `seed_token` + `refresh_with_fixture` helpers; L85-167 double-call pattern).

Phase-4 adds four new `it()` blocks per D-58:
- simple_sale + payout-arrives-next-refresh → first run `booked=false`, second run **same transactionCode** with `booked=true` + `valueDate` (validates RESEARCH §4.5 byte-identical transactionCode)
- payout-only → `zettle:payout:<uuid>` stable across refreshes
- per-sale fee linked → `zettle:fee:<originatingTxnUuid>` stable
- aggregate fee → `zettle:fee:aggregate:<date_iso>` stable

`refresh_with_fixture` helper extends to queue BOTH Purchase API and Finance API fixture responses per refresh (3 push_response per RefreshAccount call: Purchase + 2× balance + Finance transactions = adjust to match the actual entry-layer fetch order from the implementation).

---

### `spec/refresh_log_redaction_spec.lua` — EXTEND with new prefixes + Finance fixtures

**Analog:** same file. **This is the closest analog for META-03 walk-pattern below.**

Phase-4 changes:
- Gate C (L108-127): expand allowed prefix set from `{zettle:sale:, zettle:refund:}` to `{zettle:sale:, zettle:refund:, zettle:fee:, zettle:fee:aggregate:, zettle:payout:}` (D-38 update)
- Add new `it()` blocks queuing Finance fixtures alongside purchase fixtures; walk LocalStorage + captured prints with same `eyJ` JWT-shape regex and `Bearer eyJ` literal check (L86-90, L100-105)

---

### `spec/meta_no_tax_classification_spec.lua` — META-03 invariant (NEW)

**Closest analog:** `spec/refresh_log_redaction_spec.lua` `walk_storage` recursion (L54-62) — but adapted to walk **source-file text** instead of LocalStorage.

```lua
-- spec/refresh_log_redaction_spec.lua L54-62 — recursive walker pattern:
local function walk_storage(t, visit)
  for _, v in pairs(t) do
    if type(v) == "table" then
      walk_storage(v, visit)
    elseif type(v) == "string" then
      visit(v)
    end
  end
end
```

Phase-4 META-03 spec adapts: open each `src/*.lua` via `io.open(path, "r"):read("*a")` (cf. `spec/helpers/fixtures.lua` L19-34 file-read pattern), then walk a forbidden-strings list (CONTEXT D-55 — 13 phrases) asserting `assert.is_falsy(content:lower():find(phrase:lower(), 1, true), ...)`. Also walk the built `dist/paypal-pos.lua` artifact (the spec preamble already builds it — see `spec/refresh_idempotency_spec.lua` L23-28).

```lua
local FORBIDDEN = {
  "USt-frei", "USt frei", "steuerfrei", "steuerlich",
  "GoBD-konform", "GoBD konform", "DATEV-fähig", "DATEV fähig",
  "VAT-exempt", "VAT exempt", "tax-free", "tax exempt", "non-taxable",
}
-- For each src/*.lua + dist/paypal-pos.lua, for each phrase: assert.is_falsy(...)
```

Companion CI grep (Plan 04-06 or equivalent) lives alongside the existing SEC-02 egress-allowlist grep — same workflow surface.

---

### `spec/meta_purpose_lines_spec.lua` — META-02 (NEW; promote zero-suppression from mapping_spec)

**Analog:** `spec/mapping_spec.lua` existing zero-tip and zero-vat sub-cases (Phase 3) — pure-logic, no Mocks.

Pattern: inline fixture-as-table inputs (cf. `spec/auth_spec.lua` table-driven style); call `M_mapping.purchase_to_transaction(p)`; assert `txn.purpose:find("Trinkgeld", 1, true) == nil` when `gratuityAmount == 0`.

---

### `spec/finance_account_state_spec.lua` — dual-GET spec (NEW)

**Closest analog:** `spec/purchases_spec.lua` single-GET assertion shape. **New pattern**: two sequential `Mocks.push_response` calls (one per balance endpoint), then assert both URLs were captured (`Mocks._captured_requests` or equivalent — verify available in `spec/helpers/mm_mocks.lua`). Currency-guard test mirrors `src/mapping.lua` L251-257 currency-skip pattern: queue non-EUR balance JSON, assert fallback behaviour.

---

### `spec/fixtures/finance/*.json` and new `purchases/*.json` — JSON fixtures

**Analog:** `spec/fixtures/purchases/*.json` (path convention, dkjson decode, Fixtures.load two-return shape — `spec/helpers/fixtures.lua` L19-34).

Phase-4 fixtures wrap finance records in the documented `{"data": [...]}` envelope (RESEARCH §1.6) rather than purchases' `{"purchases": [...], "lastPurchaseHash": ...}`. File-naming convention matches Phase-3 (`<name>.json`, snake_case, descriptive). Add `_source` comment field at root matching Phase-3 fixture convention (`spec/fixtures/purchases/*.json` `_source` field referenced in 03-PATTERNS L666-670).

New finance fixtures (CONTEXT TEST-02):
- `finance_single_page.json`
- `finance_multi_page_1.json` + `_2.json` (offset boundary)
- `finance_payment_with_fee_linkage.json` (PAYMENT + PAYMENT_FEE sharing `originatingTransactionUuid`)
- `finance_payment_fee_unlinked.json` (drives D-49 fallback)
- `finance_payout.json`
- `finance_empty.json`
- `finance_balance_liquid.json` + `finance_balance_preliminary.json` (single-record `{"data": {...}}` shape per RESEARCH §1.4)

New purchase fixtures:
- `purchase_vat_split_19_7.json` (`groupedVatAmounts: {"19.0": ..., "7.0": ...}` — note RESEARCH §5.1 cites the existing `purchase_with_vat_and_tip.json` has a **bug** using integer-string `"19"` key; regenerate to decimal-string)
- `purchase_with_card_metadata_kontaktlos.json` (`payments[1].attributes.cardPaymentEntryMode = "CONTACTLESS_EMV"`)
- `purchase_umlauts_purpose.json` (Beispiel Café etc., validates UTF-8 through full pipeline)

---

## Shared Patterns

### Module preamble (applies to `src/finance.lua`)

**Source:** `src/purchases.lua` L1-10 — covered in 03-PATTERNS.md Shared Patterns. Apply the same 7-line preamble shape with D-46..D-49 ownership citation.

### Error routing (applies to `src/finance.lua` every HTTP call)

**Source:** `src/entry.lua` L62-64 + `src/pagination.lua` L54-56:

```lua
local err = M_errors.from_http_status(status, raw)
if err then return err end  -- or: return nil, err  in fetch_all contexts
```

Inherited from Phase 3 D-43 unchanged. No new error cases in Phase 4 — retry/backoff is Phase 5.

### Log redaction (applies to `src/finance.lua` and extended `entry.lua`)

**Source:** `src/http.lua` L125-130 (Bearer never in logs) + `src/entry.lua` L159-160 (orgUuid:sub(1,8) only).

`M_http.get_json` already structurally omits headers from log output — Phase-4 finance.lua calls inherit this. Any new INFO/WARN line in entry.lua's cross-reference step uses `M_log.redact(...)` for any payload it logs.

### luacheck annotations (applies to extended `RefreshAccount`)

**Source:** `src/entry.lua` L139 `-- luacheck: ignore 431`. Keep on the extended function signature.

### Spec preamble (applies to all new spec files)

**Source:** `spec/refresh_idempotency_spec.lua` L19-32 — exact preamble (Mocks + Fixtures require + build invocation + load_artifact helper). Replicate verbatim with file-specific error string.

### Fixture loading (applies to all new fixture-driven specs)

**Source:** `spec/helpers/fixtures.lua` L19-34 — two-return `Fixtures.load(name)` → `(raw, decoded)`. Phase 4 callers use:
- `local raw, fixture = Fixtures.load("finance/finance_single_page")` — `raw` for `Mocks.push_response`, `fixture` for direct-table assertions.

### Mocks queue (applies to multi-fetch specs)

**Source:** `spec/entry_spec.lua` L122-128 (referenced in 03-PATTERNS.md) — queue N `Mocks.push_response` calls in sequence. Phase-4 RefreshAccount drives 4+ HTTP calls per refresh (1× purchases pagination + 2× balance + 1+× finance pagination), so each idempotency test queues at least 4 responses per RefreshAccount call.

---

## No Analog Found (genuinely new patterns)

| File / Capability | Role | Data Flow | Reason |
|---|---|---|---|
| `M_finance.fetch_account_state` dual-GET | data-fetcher | sequential-dual-fetch | Phase 3 has no helper aggregating multiple HTTP calls into a single return — every Phase-3 fetcher is one URL. Plan must establish the sequential-fetch-with-shared-error-routing pattern. Conceptual reference: `src/entry.lua` InitializeSession2 L62-79 (two sequential API calls with fail-fast per call); adapt to a return-table aggregator. |
| `M_pagination.offset_iterate` body | utility / iterator | offset-loop | Cursor iterator `M_pagination.iterate` is the structural reference, but the termination semantics differ (offset-arithmetic + short-page detection vs. dual-cursor-and-array). Use cursor iterator as the boilerplate shell (preamble, error routing, MAX_PAGES, caller-table-copy invariant); body is genuinely new. |
| `M_finance` cross-refresh index sweep (sales-payment-payout matching) | orchestrator | event-driven-join | No Phase-3 analog for in-refresh cross-API joins. RESEARCH §4.3 provides the recommended implementation; closure scope inside RefreshAccount per CONTEXT Claude's-Discretion. Document explicitly that Zettle publishes no payout-to-payment link field (RESEARCH §4.1) — temporal-ordering inference is the v0.2.0 contract. |

For these three, the planner uses RESEARCH.md sections as the implementation reference; surrounding scaffolding (preamble, error routing, luacheck annotations, spec preamble) copies directly from the analogs above.

---

## Metadata

**Analog search scope:** `src/*.lua`, `spec/*.lua`, `spec/helpers/*.lua`, `spec/fixtures/**/*.json`, `03-PATTERNS.md`
**Files read:** 8 (Phase-3 src + spec) + 1 helper + 03-PATTERNS index
**Pattern extraction date:** 2026-06-21
**Manifest order (to update in webbanking_header):** `webbanking_header → log → errors → i18n → model → http → auth → pagination → purchases → finance → mapping → entry` (collapse `balance.lua` + `payouts.lua` stubs into `finance.lua` per planner-note above).
