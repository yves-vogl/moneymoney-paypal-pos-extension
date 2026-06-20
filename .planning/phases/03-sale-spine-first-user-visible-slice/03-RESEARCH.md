# Phase 3: Sale Spine (first user-visible slice) — Research

**Researched:** 2026-06-20
**Domain:** Zettle Purchase API ingestion, purchase-to-transaction mapping, cursor pagination, timezone conversion, idempotency
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-31** Phase 3 emits every sale with `booked = false` and no `valueDate`. Phase 4 closes the `booked=true` + `valueDate = payout_date` transition using the same `transactionCode`.
- **D-32** Refund purchases (`refund == true`) become their own negative transaction: `transactionCode = "zettle:refund:" .. purchaseUUID1` (refund's own UUID), `amount = -purchase.amount`, `purpose` starts with German "Rückerstattung zu Beleg #<purchaseNumber>" (or UUID fallback). Original sale is NOT modified.
- **D-33** `since` is clamped to `max(since_from_moneymoney, os.time() - 90 * 86400)` in `RefreshAccount` before passing to `M_purchases.fetch`. First refresh fetches max 90 days.
- **D-34** `purpose` is multi-line: line 1 = `Brutto: <amount> €` (always), line 2 = `MwSt: <vat_amount> €` (when vatAmount > 0), line 3 = `Trinkgeld: <tip_sum> €` (when tip > 0), line 4 = `Netto: <net> €` (always), final line = `Beleg #<purchaseNumber>`. Comma decimal separator, no thousands separator below 10000.
- **D-35** `name = "Kartenzahlung"` default. When `payments[1]` has card metadata, upgrade to `"<CardBrand> •••• <last_four>"` (U+2022). Brand map: VISA→Visa, MASTERCARD→Mastercard, AMEX→Amex, MAESTRO→Maestro, GIROCARD→girocard, UNIONPAY→UnionPay. Refunds append `" Rückerstattung"`.
- **D-36** `bookingDate` = Europe/Berlin local time via hardcoded DST rules table (2020–2040) inside `mapping.lua`. No `os.date`/`$TZ` dependence. DST starts last Sunday of March 01:00 UTC (+2h), ends last Sunday of October 01:00 UTC (+1h).
- **D-37** Non-EUR purchases are silently skipped with an INFO log line.
- **D-38** `transactionCode` formats: sales = `"zettle:sale:" .. purchaseUUID1`; refunds = `"zettle:refund:" .. purchaseUUID1`; reserved Phase 4: `"zettle:payout:<uuid>"`, `"zettle:fee:<uuid>"`.
- **D-39** Idempotency: `RefreshAccount` called twice on same backend state MUST return zero new transactions on second call. `spec/refresh_idempotency_spec.lua` is the gating spec (TEST-03).
- **D-40** Phase 3 fills: `src/purchases.lua`, `src/pagination.lua`, `src/mapping.lua`; rewires `src/entry.lua RefreshAccount`; adds 6 new keys to `src/i18n.lua`. No new `M_*` table declarations needed.
- **D-41** Phase 3 calls `M_auth.cached_token(orgUuid)` (Phase 2) for Bearer. If nil → return German `error.network` string. No re-auth from within RefreshAccount.
- **D-42** Phase 3 uses `M_http.get_json(url, headers)` (Phase 2) for all purchase fetches. No new HTTP surface.
- **D-43** Phase 3 uses `M_errors.from_http_status(status, body)` (Phase 2) for HTTP error mapping. No new error cases.
- **D-44** Required fixtures under `spec/fixtures/purchases/`: `purchase_simple_sale.json`, `purchase_with_vat_and_tip.json`, `purchase_refund.json`, `purchase_page1.json`, `purchase_page2.json`, `purchases_empty.json`, `purchase_non_eur.json`, `purchase_dst_boundary.json`, `purchase_with_card_metadata.json`.
- **D-45** SEC-03 redaction is NOT re-tested in Phase 3. No new log call sites that could leak Bearer.

### Claude's Discretion

- Internal helper-function signatures inside `mapping.lua` (private helpers only)
- Exact spec file partitioning under `spec/`
- Whether to inline the DST rules table in `mapping.lua` or hoist to a `src/timezone.lua` module
- Order of pagination loop checks (loop-then-check vs check-then-loop), subject to: empty `purchases[]` MUST terminate the loop unconditionally

### Deferred Ideas (OUT OF SCOPE)

- `booked=true` + `valueDate = payout_date` transition — Phase 4
- Per-purchase fee display (`payments[].commission.totalAmount`) — Phase 4/5
- VAT split by rate (`groupedVatAmounts` breakdown, e.g., 7%/19%) — Phase 5
- Receipt-copy URL and GPS coordinates in `purpose` — Phase 5/6
- Discounts breakdown (`purchase.discounts[]`) — Phase 5; Phase 3 trusts top-level `amount`
- Force-full-sync flag — Phase 5/6
- Multi-currency support — out of scope for v1.0.0; non-EUR purchases skipped
- Retry/backoff for 429 and 5xx — Phase 5
- Real TZ database — Phase 5/6
- Per-day or per-payout grouping — Phase 4
- Cancellation handling — not currently in the Zettle purchase schema
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SALE-01 | Each completed PayPal POS sale is returned as one positive MoneyMoney transaction with gross amount (VAT- and tip-inclusive) | Section 1: purchase.amount is the gross integer in minor units. Mapping divides by 100 to get EUR float. |
| SALE-02 | Sale transactions carry a stable `transactionCode = "zettle:sale:<purchaseUUID1>"` that does not change across refreshes | Section 2c: pure deterministic concatenation — same UUID always yields same code. |
| SALE-03 | Pending sales flagged `booked = false`; settled sales `booked = true` with `valueDate` = payout date (Phase 3 ships `booked=false` half) | D-31: Phase 3 always emits `booked = false`; Phase 4 closes dynamic half. |
| SALE-04 | `bookingDate` reflects sale timestamp converted from UTC ISO-8601 to POSIX local time | Section 2b: hardcoded DST table for Europe/Berlin 2020–2040. |
| SALE-05 | Double-refresh produces zero duplicate transactions (idempotency invariant) | Section 2c + Validation Architecture SALE-05. |
| SALE-06 | Incremental refresh respects MoneyMoney's `since` parameter — only purchases after `since` are fetched | Section 2a: `startDate` query param set to ISO-8601 from clamped `since` POSIX. |
| SALE-08 | `name` field carries German customer-facing payment label | D-35 + Section 1: card metadata lives in `payments[].attributes.cardType` + `maskedPan`. |
| I18N-01 | All user-facing strings in German | Section 4: 6 new i18n keys added to `src/i18n.lua`. |
| TEST-03 | Double-refresh idempotency test fails build when sales are duplicated | Section 2c: gating spec `spec/refresh_idempotency_spec.lua`. |
| TEST-04 | Golden-file schema test fails build when returned transaction is missing required fields | Section 2d: `spec/mapping_schema_spec.lua` asserts all 7 mandatory fields. |
</phase_requirements>

---

## Summary

Phase 3 wires three Phase-1 empty stubs (`src/purchases.lua`, `src/pagination.lua`, `src/mapping.lua`) and rewires `RefreshAccount` in `src/entry.lua` to deliver the first user-visible result: real card sales from Zettle's Purchase API appearing in MoneyMoney as stable, deduplicated, German-labelled transactions. The transport layer (Phase 2's `M_http.get_json`), auth layer (`M_auth.cached_token`), and error layer (`M_errors.from_http_status`) are fully consumed as-is — Phase 3 adds zero new HTTP surface.

The dominant technical challenges are (a) the idempotency gate: MoneyMoney's own `transactionCode` dedup only works if our mapping function produces identical codes on every call for the same purchase — a pure deterministic string transformation that the gating spec must prove; and (b) the `bookingDate` timezone conversion, which must be deterministic across UTC-based CI runs and Europe/Berlin-zoned production environments, solved by a small hardcoded DST rules table rather than `os.date` (which depends on `$TZ`).

A critical API discrepancy requires the planner's attention: CLAUDE.md and CONTEXT.md D-35 reference `payments[].cardBrand` and `payments[].cardLastFour` as direct payment fields, but the authoritative `purchase.adoc` documents card data under `payments[].attributes.cardType` and `payments[].attributes.maskedPan`. Phase 3 fixtures and mapping code must handle the `attributes` sub-object; the `_format_label` helper must extract card metadata from `payments[1].attributes` (not `payments[1]` directly). See Section 1 for full citation and Section 6 for the risk register entry.

**Primary recommendation:** Implement `M_pagination.iterate` first (Wave 1, RED spec then GREEN), then `M_mapping.purchase_to_transaction` (Wave 2), then wire `RefreshAccount` in `entry.lua` (Wave 3). The idempotency gating spec and schema spec both belong to Wave 1 and must run RED against empty stubs before implementation fills them.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Cursor pagination over Purchase API | `src/pagination.lua` (M_pagination) | `src/purchases.lua` (calls iterator) | Pagination is a reusable concern orthogonal to purchase-specific params |
| Single page fetch (HTTP + auth header) | `src/purchases.lua` (M_purchases) | `src/http.lua` (transport) | Purchases module owns URL construction and param encoding; HTTP module owns wire |
| Purchase → transaction mapping | `src/mapping.lua` (M_mapping) | `src/i18n.lua` (German strings) | Pure transformation; all side-effect-free so it is independently testable |
| Timezone conversion | Inside `src/mapping.lua` (or `src/timezone.lua`) | — | Used only during mapping; no other module needs it in Phase 3 |
| `since` clamp + RefreshAccount orchestration | `src/entry.lua` | `src/purchases.lua` (passes clamped value) | Entry point is the natural boundary for MoneyMoney's contract surface |
| German string templates | `src/i18n.lua` (M_i18n) | — | Single source of truth for all user-facing strings per I18N-02 |
| Error surfacing | `src/errors.lua` (M_errors, Phase 2) | — | Phase 3 makes no new error cases — calls existing `from_http_status` |

---

## Standard Stack

### Core (shipped in `dist/paypal-pos.lua`)

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Lua 5.4 | 5.4.8 (MoneyMoney embed) | Implementation language | MoneyMoney's embedded interpreter; matches CI pin |
| `Connection():request` | MoneyMoney built-in | HTTP via `M_http.get_json` (Phase 2) | Only sanctioned HTTPS client in the sandbox |
| `JSON()` | MoneyMoney built-in (dkjson mock in tests) | `JSON(raw):dictionary()` to parse purchase list | No C deps; mocked via `spec/helpers/mm_mocks.lua` |
| `M_http.get_json` | Phase 2 `src/http.lua` | GET /purchases/v2 per page | Bearer header passed; body logged via M_log.redact |
| `M_auth.cached_token` | Phase 2 `src/auth.lua` | Obtain Bearer for purchase requests | Called once per RefreshAccount |
| `M_errors.from_http_status` | Phase 2 `src/errors.lua` | HTTP error mapping | 401/429/5xx all handled; Phase 3 passes through |

### Supporting (test/CI only)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `busted` | 2.3.0 | Test runner | All spec files |
| `dkjson` | 2.7+ | JSON parsing in tests (backs `JSON()` mock) | Fixture loading + mm_mocks |
| `luacov` | 0.16.0 | Line coverage | CI gate ≥85% |
| `luacheck` | 1.2.0 | Lint | CI; runs on Lua 5.4 (5.5 broken on local, CI is correct) |

**No new packages to install.** Phase 3 consumes existing toolchain only.

### Package Legitimacy Audit

Not applicable — Phase 3 introduces no new external packages. All dependencies were audited and approved in Phase 1 and Phase 2.

---

## Section 1: Zettle Purchase API Surface

### Endpoint

```
GET https://purchase.izettle.com/purchases/v2
Authorization: Bearer <access_token>
Accept: application/json
```

[CITED: github.com/iZettle/api-documentation/purchase.adoc]

### Query Parameters

| Parameter | Type | Required | Default | Phase 3 Usage |
|-----------|------|----------|---------|--------------|
| `startDate` | string (UTC ISO-8601 or date) | No | 3 years back | Set to `os.date("!%Y-%m-%dT%H:%M:%SZ", clamped_since)` |
| `endDate` | string (UTC ISO-8601 or date) | No | now | Not set in Phase 3 (fetch to present) |
| `limit` | integer 1–1000 | No | Not documented; practitioner default is typically 200 [ASSUMED] | Use `limit=200` as conservative page size |
| `descending` | boolean | No | false (ascending = oldest first) | Use `false` for incremental refresh — ascending order ensures cursor always moves forward |
| `lastPurchaseHash` | string | No | — | Omitted on first page; set to response value on subsequent pages |

**`descending=false` (ascending) is the safe default for incremental refresh** [CITED: purchase.adoc pagination section]. Ascending order means the cursor always moves chronologically forward, avoiding re-seeing records already processed.

**`startDate` format:** The API accepts both `YYYY-MM-DD` and `YYYY-MM-DDTHH:MM` [CITED: purchase.adoc]. Use the full ISO-8601 UTC form (`!%Y-%m-%dT%H:%M:%SZ` from `os.date`) to avoid day-boundary ambiguity.

### Response Shape

```json
{
  "purchases": [ ... ],
  "firstPurchaseHash": "string",
  "lastPurchaseHash": "string",
  "linkUrls": [ ... ]
}
```

[CITED: github.com/iZettle/api-documentation/purchase.adoc]

### Pagination Semantics

**Termination condition:** The authoritative `purchase.adoc` states "Repeat...until the response is empty" — meaning an empty `purchases[]` array is the definitive terminal signal. [CITED: purchase.adoc]

Defensive implementation: check BOTH conditions:
1. `purchases` array is empty or absent → terminal
2. `lastPurchaseHash` absent from response → also terminal (belt-and-suspenders)

**Why both:** If Zettle ever returns a page with records but omits `lastPurchaseHash` (undocumented edge case), checking only empty-array would loop forever. If Zettle returns `lastPurchaseHash` on the last page alongside an empty array (different edge), checking only the hash would miss termination.

**Empty response on `since` past all purchases:** Expected response is `{"purchases": [], ...}` — the empty array. [ASSUMED based on standard REST API behavior; no explicit doc confirmation found.] Treat as terminal.

**Max guard:** Implement a `MAX_PAGES = 50` guard to prevent infinite loops on malformed responses (50 pages × 200 records = 10,000 purchases, far above any 90-day window for typical German merchants). Log a WARNING if the guard is hit.

### Purchase JSON Object Shape (Per Field)

All fields below [CITED: github.com/iZettle/api-documentation/purchase.adoc] unless noted.

| Field | Type | Notes |
|-------|------|-------|
| `purchaseUUID1` | string (UUID v1) | Source for `transactionCode`. Stable across re-fetches. |
| `amount` | integer (minor units, signed) | Gross amount inc VAT. Negative for refund purchases. Divide by 100.0 for EUR float. Q4 confirmed integer round-trip in ADR-0003. |
| `vatAmount` | integer (minor units) | Total VAT for the purchase. Can be 0. |
| `currency` | string (ISO 4217) | Usually "EUR" for German merchants. Non-EUR → skip (D-37). |
| `timestamp` | string (ISO-8601 UTC) | Sale creation timestamp, UTC. NOT local time — see D-36. Example: `"2020-09-10T09:27:28.590+0000"`. |
| `purchaseNumber` | integer | Incremental receipt number. Used in `purpose` as "Beleg #<N>". |
| `globalPurchaseNumber` | integer | Differs from `purchaseNumber` only when multiple cash registers used. Phase 3 uses `purchaseNumber`. |
| `refund` | boolean | `true` = this purchase record IS a refund. Per D-32, these become separate negative transactions. |
| `refunded` | boolean | `true` = the original sale has been refunded (by a separate refund record). Does NOT make Phase 3 skip it. |
| `refundsPurchaseUUID1` | string (UUID v1) | On refund records: UUID of the original sale that was refunded. Used in refund `purpose`. |
| `refundedByPurchaseUUIDs1` | array of strings | On original sales: list of refund record UUIDs. Phase 3 does not use this for display. |
| `products[]` | array | Line items. Phase 3 trusts top-level `amount` — discounts are already reflected there. |
| `payments[]` | array | See payment sub-object below. May be empty for non-card payment types. |
| `groupedVatAmounts` | object | VAT breakdown by rate. Phase 3 uses `vatAmount` top-level only; per-rate breakdown is Phase 5. |
| `serviceCharge` | object | Service fee (distinct from tip). Skip in Phase 3 — see Open Questions. |
| `userDisplayName` | string | Merchant employee name. Not used in Phase 3 `purpose`. |
| `userId` | integer | Employee ID. Not used in Phase 3. |
| `organizationId` | integer | Merchant org ID. Not used in Phase 3 (auth uses `organizationUuid` from Phase 2 cache). |

### Payment Sub-Object Shape

**Important discrepancy:** CONTEXT.md D-35 references `payments[].cardBrand` and `payments[].cardLastFour` as direct fields. The authoritative `purchase.adoc` documents these under `payments[].attributes` as `cardType` and `maskedPan`. [CITED: github.com/iZettle/api-documentation/purchase.adoc]

| Path | Type | Notes |
|------|------|-------|
| `payments[i].uuid` | string | Payment UUID |
| `payments[i].type` | string | `IZETTLE_CARD`, `IZETTLE_CASH`, `SWISH`, `KLARNA`, etc. |
| `payments[i].amount` | integer | Payment amount in minor units |
| `payments[i].gratuityAmount` | integer | Tip amount for this payment leg. Aggregate across all payments for total tip. |
| `payments[i].attributes.cardType` | string | Card brand: `"MASTERCARD"`, `"VISA"`, `"AMEX"`, `"MAESTRO"`, `"UNIONPAY"` etc. [CITED: purchase.adoc] |
| `payments[i].attributes.maskedPan` | string | Masked card number, e.g., `"535583******0000"`. Last 4 chars = `cardLastFour` equivalent. [CITED: purchase.adoc] |
| `payments[i].attributes.cardPaymentEntryMode` | string | e.g., `"ICC"` (chip), `"MSR"` (swipe). Used in Phase 4 (SALE-07). |
| `payments[i].commission` | object | Only present for Klarna; fields: `totalAmount`, `vatAmount`, `vatRate`. Per-payout fee via Finance API preferred. Phase 4 concern. |
| `payments[i].references.refundsPayment` | string | UUID of original payment, on refund legs. |

**Card metadata extraction for D-35:**
```lua
local cardType   = payments[1] and payments[1].attributes and payments[1].attributes.cardType
local maskedPan  = payments[1] and payments[1].attributes and payments[1].attributes.maskedPan
local last_four  = maskedPan and maskedPan:sub(-4)  -- last 4 chars
```

`maskedPan` for Girocard may use a different format [ASSUMED]; guard with `type(last_four) == "string" and #last_four == 4` before using.

**Recognized `cardType` values to display name map (D-35):**

| cardType (API) | Display |
|----------------|---------|
| `"VISA"` | `Visa` |
| `"MASTERCARD"` | `Mastercard` |
| `"AMEX"` | `Amex` |
| `"MAESTRO"` | `Maestro` |
| `"GIROCARD"` | `girocard` |
| `"UNIONPAY"` | `UnionPay` |
| (other) | Capitalize literal (e.g., `"DISCOVER"` → `"Discover"`) |

### Status Code Handling

Phase 3 passes all HTTP errors through Phase 2's `M_errors.from_http_status(status, body)`:

| Status | M_errors result | Phase 3 action |
|--------|----------------|----------------|
| 200 | nil | Process body |
| 401 | LoginFailed | Propagate (unexpected mid-refresh; Phase 5 adds re-mint) |
| 404 | LoginFailed (conservative) | Propagate as error string |
| 429 | German rate-limit string | Propagate (Phase 5 adds retry) |
| 5xx | German network error string | Propagate |

Note: `M_http._infer_status` derives status from response body `.error` field, not from a real HTTP status code (Risk R-1 from Phase 2). Purchase API success returns `purchases` array, not an `.error` field, so `_infer_status` returns 200 correctly. Non-2xx purchase responses may or may not carry a structured `.error` body — for Phase 3, the conservative treatment (unknown body shape → nil parse → nil status → `error.network`) is correct and safe.

---

## Section 2: Patterns — Implementation Approaches

### 2a. Pagination — Cursor Loop

**Recommended pattern: `repeat…until` with explicit last-page detection.**

```lua
-- src/pagination.lua — M_pagination.iterate
-- fetch_page_fn(params) -> (page_table|nil, status, raw)
-- params: mutable table; iterate updates it with lastPurchaseHash between pages
M_pagination.iterate = function(fetch_page_fn, initial_params)
  local all_purchases = {}
  local params = {}
  for k, v in pairs(initial_params) do params[k] = v end
  local page_count = 0
  local MAX_PAGES = 50

  repeat
    page_count = page_count + 1
    if page_count > MAX_PAGES then
      M_log.warn("M_pagination.iterate: MAX_PAGES exceeded, aborting")
      break
    end

    local page, status, raw = fetch_page_fn(params)
    local err = M_errors.from_http_status(status, raw)
    if err then return nil, err end
    if not page or type(page.purchases) ~= "table" then
      return nil, M_i18n.t("error.network", "bad_page")
    end

    for _, p in ipairs(page.purchases) do
      all_purchases[#all_purchases + 1] = p
    end

    -- Termination: empty array OR no cursor
    local has_more = #page.purchases > 0 and type(page.lastPurchaseHash) == "string"
    if has_more then
      params.lastPurchaseHash = page.lastPurchaseHash
    else
      params.lastPurchaseHash = nil
    end

  until not (type(params.lastPurchaseHash) == "string" and params.lastPurchaseHash ~= "")

  return all_purchases, nil
end
```

[ASSUMED pattern; confirmed against purchase.adoc pagination semantics]

**Why not a `while true` loop:** The `repeat…until` form makes the termination condition syntactically visible and avoids the need for a `break` in the common path, which is idiomatic Lua 5.4.

**Typical page count:** A German merchant with 90 days of history and `limit=200` will typically complete in 1–5 pages (most active merchants process ~5–50 sales/day → 450–4500 records in 90 days). The `MAX_PAGES = 50` guard is a safety net, not a typical execution path.

**Alternative considered — link-following via `linkUrls`:** The response includes pre-constructed `linkUrls` with `rel="next"`. Rejected: parsing the URL string to extract `lastPurchaseHash` is brittle if Zettle changes URL format. Direct cursor copy is more robust. [ASSUMED: linkUrls are present but cursor-param approach is more stable]

### 2b. bookingDate Timezone Conversion (D-36)

**Recommended: hardcoded EU DST rules table — a flat list of pre-computed POSIX boundary timestamps.**

The table covers DST transitions (start and end of summer time in Europe/Berlin) for years 2020–2040. Each entry is a pair: `{summer_start_utc, summer_end_utc}` where:
- `summer_start_utc` = POSIX timestamp of "last Sunday of March at 01:00 UTC" for that year
- `summer_end_utc` = POSIX timestamp of "last Sunday of October at 01:00 UTC" for that year

**During summer (CEST, UTC+2):** `offset_seconds = 7200`
**During winter (CET, UTC+1):** `offset_seconds = 3600`

**Computing "last Sunday of March at 01:00 UTC" in Lua:**
```lua
-- Tools run at build time; this is a helper to pre-compute the table values.
-- The table is then inlined as literals in mapping.lua (no runtime computation).
local function last_sunday_utc(year, month, hour)
  -- Find the last day of the month
  local next_month_first = os.time({year=year, month=month+1, day=1, hour=0, min=0, sec=0})
  local last_day_t = os.date("*t", next_month_first - 86400)
  -- Walk backward to Sunday (wday=1)
  local dow = last_day_t.wday  -- 1=Sun, 2=Mon, ...
  local offset_to_sunday = (dow - 1) % 7
  local last_sunday = next_month_first - 86400 - offset_to_sunday * 86400
  -- Add the target hour (01:00 UTC)
  return last_sunday + hour * 3600
end
```

**Alternative: at-runtime calendar arithmetic.** Rejected: adds complexity inside `mapping.lua` and is harder to test with boundary fixtures. A pre-computed table is trivially auditable — each row can be verified against `date(1)` or worldtimeapi.

**Inline vs separate `src/timezone.lua`:** If the table has 21 entries × 2 values = 42 integers plus the lookup function, it is compact enough (roughly 60 lines) to inline in `mapping.lua`. The planner may hoist to `timezone.lua` if readability suffers. The manifest order is fixed: `pagination → purchases → payouts → balance → mapping → entry` — a `timezone.lua` module would be inserted between `pagination` and `mapping`. [Claude's Discretion per D-40]

**Function signature for the helper:**

```lua
-- Returns POSIX timestamp adjusted to Europe/Berlin local time
-- Input: utc_posix (integer, seconds since epoch)
-- Output: integer, local POSIX timestamp (utc_posix + offset_seconds)
local function _to_berlin_local_time(utc_posix)
  -- DST_TABLE: {{summer_start, summer_end}, ...} one entry per year 2020-2040
  -- summer_start: last Sunday of March at 01:00 UTC
  -- summer_end:   last Sunday of October at 01:00 UTC
  local DST_TABLE = {
    {1585443600, 1603580400},  -- 2020
    {1616893200, 1635634800},  -- 2021
    {1648342800, 1667084400},  -- 2022
    {1679792400, 1698534000},  -- 2023
    {1711846800, 1729587600},  -- 2024
    {1743296400, 1761037200},  -- 2025
    {1774746000, 1792486800},  -- 2026
    {1806195600, 1824541200},  -- 2027
    {1837645200, 1855990800},  -- 2028
    {1869094800, 1887440400},  -- 2029
    {1901149200, 1919494800},  -- 2030
    -- ... continue to 2040
  }
  -- [ASSUMED: exact transition timestamps above — planner must generate from helper
  --  or verify against official EU DST schedule before committing]
  local offset = 3600  -- CET default (winter)
  for _, entry in ipairs(DST_TABLE) do
    if utc_posix >= entry[1] and utc_posix < entry[2] then
      offset = 7200  -- CEST (summer)
      break
    end
  end
  return utc_posix + offset
end
```

**Warning:** The DST timestamps above are [ASSUMED] — the planner MUST regenerate them using the `last_sunday_utc` helper or verify against an authoritative source before committing. The structure is correct; the exact integer values need generation/verification.

**Spec gate (D-36/SALE-04):**
- Fixture `purchase_dst_boundary.json` has `timestamp = "2026-06-19T23:55:00Z"` (summer, CEST +2h) → local = `2026-06-20T01:55:00` → `bookingDate` represents `2026-06-20`
- A second fixture (or a spec-local constant) has `timestamp = "2026-01-31T23:55:00Z"` (winter, CET +1h) → local = `2026-02-01T00:55:00` → `bookingDate` represents `2026-02-01`

### 2c. Idempotency Proof (TEST-03 / D-39 / SALE-05)

**MoneyMoney dedup contract:** MoneyMoney deduplicates transactions per account by `transactionCode`. If `RefreshAccount` returns a transaction with a `transactionCode` already seen in the account, MoneyMoney updates the existing record (for fields like `booked`) rather than creating a duplicate. [CITED: moneymoney.app/api/webbanking/ — implied by idempotency contract; ASSUMED for exact field-update behavior]

**What Phase 3 must prove:** That its own `mapping.purchase_to_transaction` function produces an identical `transactionCode` on every call for the same purchase UUID — not that MoneyMoney handles dedup correctly (we trust MoneyMoney).

**Gating spec shape (`spec/refresh_idempotency_spec.lua`):**

```lua
describe("RefreshAccount idempotency (TEST-03)", function()
  it("double-refresh produces no new transactionCodes on second call", function()
    -- Arrange: same single-page purchase fixture queued twice
    local raw, _ = Fixtures.load("purchases/purchase_simple_sale")
    Mocks.push_response({ content = raw })  -- first RefreshAccount
    Mocks.push_response({ content = raw })  -- second RefreshAccount

    -- Seed LocalStorage with a live token so cached_token returns non-nil
    LocalStorage["zettle:org-1"] = JSON():set({
      access_token = "AT-VALID",
      expires_at   = os.time() + 7200,
      obtained_at  = os.time(),
      client_id    = "client-x",
    }):json()
    local account = { accountNumber = "org-1", currency = "EUR", balance = 0 }

    -- Act
    local result1 = RefreshAccount(account, 0)
    local result2 = RefreshAccount(account, 0)

    -- Assert: both calls succeed
    assert.is_table(result1)
    assert.is_table(result2)
    assert.is_table(result1.transactions)
    assert.is_table(result2.transactions)

    -- Build set of codes from first run
    local seen = {}
    for _, t in ipairs(result1.transactions) do
      seen[t.transactionCode] = true
    end

    -- Second run: every code must already be in `seen`
    for _, t in ipairs(result2.transactions) do
      assert.is_true(seen[t.transactionCode] ~= nil,
        "NEW transactionCode on second refresh: " .. tostring(t.transactionCode))
    end
  end)
end)
```

**Why this proves idempotency:** The same fixture returns the same `purchaseUUID1`, and `transactionCode = "zettle:sale:" .. purchaseUUID1` is deterministic. If any implementation bug varies the code (e.g., appending a timestamp), the spec fails.

**Must run RED first:** Queue the spec in Wave 1 against empty `purchases.lua` stub — the call should fail or return no transactions, and the spec's assertion on an empty result1.transactions must be red (no transactions returned means the spec correctly exercises the path that would miss idempotency if mapping were wrong).

### 2d. Schema Gate (TEST-04)

**Golden-file schema spec shape (`spec/mapping_schema_spec.lua`):**

```lua
describe("transaction schema gate (TEST-04)", function()
  local REQUIRED_FIELDS = {
    "name", "amount", "currency", "bookingDate",
    "purpose", "transactionCode", "booked"
  }

  local function assert_schema(txn, label)
    for _, field in ipairs(REQUIRED_FIELDS) do
      assert.is_not_nil(txn[field],
        label .. ": missing required field '" .. field .. "'")
    end
  end

  it("purchase_simple_sale maps to a valid transaction schema", function()
    local _, purchase = Fixtures.load("purchases/purchase_simple_sale")
    local txn = M_mapping.purchase_to_transaction(purchase.purchases[1])
    assert_schema(txn, "simple_sale")
    assert.is_false(txn.booked, "Phase 3: booked must be false")
    assert.is_nil(txn.valueDate, "Phase 3: valueDate must be absent")
  end)

  it("purchase_with_vat_and_tip maps to valid schema with gross amount", function()
    local _, fixture = Fixtures.load("purchases/purchase_with_vat_and_tip")
    local p = fixture.purchases[1]
    local txn = M_mapping.purchase_to_transaction(p)
    assert_schema(txn, "vat_and_tip")
    -- SALE-01: gross amount = purchase.amount / 100
    assert.are.equal(p.amount / 100, txn.amount)
  end)

  it("refund maps to negative amount with zettle:refund: prefix", function()
    local _, fixture = Fixtures.load("purchases/purchase_refund")
    local p = fixture.purchases[1]
    local txn = M_mapping.refund_to_transaction(p)
    assert_schema(txn, "refund")
    assert.is_true(txn.amount < 0, "refund amount must be negative")
    assert.are.matches("^zettle:refund:", txn.transactionCode)
  end)
end)
```

**Pattern reference:** Analogous to Phase 2's `spec/log_redaction_spec.lua` walk-pattern (iterating over a set of invariants per entity). The `assert_schema` helper mirrors the `walk(LocalStorage, visit)` pattern from SEC-03.

---

## Section 3: Anti-Patterns to Avoid

1. **Assuming `lastPurchaseHash` is the ONLY termination signal.** The purchase.adoc says "repeat until response is empty" — the empty `purchases[]` array is the definitive terminal. Relying only on the absence of `lastPurchaseHash` could cause the loop to continue on a response that has no cursor but does have purchases (unlikely but defensive). Check both.

2. **Treating `purchase.timestamp` as local time.** The field is UTC (`"2020-09-10T09:27:28.590+0000"` format). Feeding it directly to `os.date("*t", ...)` without timezone adjustment produces a wrong local date for any sale between 22:00 and 23:59 UTC during CET, or between 21:00 and 23:59 UTC during CEST. Always apply `_to_berlin_local_time()` before setting `bookingDate`.

3. **Storing `amount` as a string.** ADR-0003 Q4 confirmed that `JSON():set({amount=995}):json()` round-trips to integer 995. Always store `purchase.amount` (and the derived transaction `amount = purchase.amount / 100`) as Lua numbers, not `tostring()` values. The MoneyMoney transaction table expects `amount` as a number.

4. **Relying on MoneyMoney's `since` watermark alone for dedup.** `since` filters at the API call level (startDate param) — it does not prevent MoneyMoney from re-processing a purchase that was returned on a previous refresh if `since` is re-set. The `transactionCode` is the dedup key. Both mechanisms must be correct independently.

5. **Assuming `refund == true` means the original sale was refunded.** The field `refund: true` means "this purchase record IS a refund transaction" (i.e., a negative settlement). The field `refunded: true` on a different purchase means "that sale has been refunded". Phase 3 correctly handles this: records where `refund == true` are mapped via `M_mapping.refund_to_transaction`; records where `refunded == true` (but `refund == false`) are ordinary sales that happen to have been refunded — map them normally. [CITED: purchase.adoc field descriptions]

6. **Using `pcall` around the `M_http.get_json` call.** ADR-0003 Q8 confirmed that `pcall` does NOT catch SSL/network errors — MoneyMoney surfaces those through its own channels. Phase 2's `M_http.get_json` is already written without a `pcall` wrapper. Phase 3 must not add one. Failure is signaled by `status == nil` (network) or by a non-2xx status, both routed through `M_errors.from_http_status`.

7. **Accessing `payments[1].cardBrand` directly.** The Zettle purchase.adoc places card brand under `payments[1].attributes.cardType`, not as a direct field. The D-35 field names (`cardBrand`, `cardLastFour`) are conceptual names for the mapping function's internal variables, not JSON field paths. Code must access `payments[1].attributes.cardType` and derive last-four from `payments[1].attributes.maskedPan:sub(-4)`.

8. **Nil-deref on absent `payments[]`.** Card metadata may be absent on cash payments, Swish payments, or older terminals. Guard every access: `payments[1] and payments[1].attributes and payments[1].attributes.cardType`.

9. **The concat order in `tools/manifest.txt` — silent breakage.** The current manifest order (confirmed in Phase 2 Plan 07 verification) is: `webbanking_header → log → errors → i18n → model → http → auth → pagination → purchases → payouts → balance → mapping → entry`. If `i18n` were placed after `mapping`, calls to `M_i18n.t` inside `mapping.lua` would reference an empty table at the moment the `do...end` block for `mapping.lua` executes — a load-time error in the amalgamated artifact. The existing order is correct and must not be changed. If a `timezone.lua` module is added, insert it between `balance` and `mapping`.

---

## Section 4: Module-by-Module File Inventory

### Source Files Modified/Filled in Phase 3

| File | Status | Phase 3 Change | Public Surface |
|------|--------|----------------|----------------|
| `src/pagination.lua` | Empty stub → filled | `M_pagination.iterate(fetch_page_fn, initial_params)` | Returns `(all_purchases_table|nil, error_string|nil)` |
| `src/purchases.lua` | Empty stub → filled | `M_purchases.fetch(account, clamped_since, bearer)` single-page GET; `M_purchases.fetch_all(account, clamped_since, bearer)` drives pagination | Returns `(purchases_table|nil, error_string|nil)` |
| `src/mapping.lua` | Empty stub → filled | `M_mapping.purchase_to_transaction(p)`, `M_mapping.refund_to_transaction(p)`, private helpers `_format_amount`, `_format_purpose`, `_format_label`, `_to_berlin_local_time` (or deferred to `timezone.lua`) | Returns MoneyMoney transaction table |
| `src/entry.lua` | Modify `RefreshAccount` only | Swap Phase-2 fixture for real pipeline: (1) orgUuid, (2) `M_auth.cached_token`, (3) clamp `since`, (4) `M_purchases.fetch_all`, (5) map each purchase, (6) return `{balance, transactions}` | `RefreshAccount(account, since)` signature unchanged |
| `src/i18n.lua` | Extend — add 6 new keys | Add `account.purpose.gross`, `account.purpose.vat`, `account.purpose.tip`, `account.purpose.net`, `account.purpose.refund_for`, `account.purpose.receipt_number`, `account.name.card_payment` to both `STRINGS.de` and `STRINGS.en` | Existing `M_i18n.t` interface unchanged |
| `src/webbanking_header.lua` | NO CHANGE | `M_purchases`, `M_pagination`, `M_mapping` already pre-declared as `{}` | — |
| `tools/manifest.txt` | NO CHANGE (unless timezone.lua added) | If `src/timezone.lua` is added: insert `timezone` between `balance` and `mapping` | — |

### Spec Files Created in Phase 3

| File | Covers | When Created |
|------|--------|-------------|
| `spec/refresh_idempotency_spec.lua` | TEST-03, SALE-05: double-refresh dedup gate | Wave 1 (RED first against stub) |
| `spec/mapping_schema_spec.lua` | TEST-04: 7-field schema gate on all fixture types | Wave 1 (RED first against stub) |
| `spec/purchases_spec.lua` | SALE-06: `startDate` URL capture; `M_purchases.fetch` unit tests | Wave 2 |
| `spec/pagination_spec.lua` | Pagination loop termination: empty array, cursor, MAX_PAGES guard | Wave 2 |
| `spec/mapping_spec.lua` | SALE-01, SALE-02, SALE-04, SALE-08, I18N-01: mapping unit tests per fixture | Wave 2 |
| `spec/entry_spec.lua` | Extend existing: new RefreshAccount integration tests, non-EUR skip (D-37), nil-token path (D-41) | Wave 3 |

### JSON Fixtures Created in Phase 3

Location: `spec/fixtures/purchases/`

| File | Purpose | Key Fields |
|------|---------|------------|
| `purchase_simple_sale.json` | Single sale, EUR, no VAT, no tip | `amount=500`, `vatAmount=0`, `currency="EUR"`, `payments=[]` |
| `purchase_with_vat_and_tip.json` | VAT-bearing, tip, groupedVatAmounts | `amount=1995`, `vatAmount=318`, tip via `payments[0].gratuityAmount=100` |
| `purchase_refund.json` | `refund=true`, negative amount, `refundsPurchaseUUID1` set | `amount=-995`, `refund=true`, `purchaseNumber=<original>` |
| `purchase_page1.json` | Pagination page 1: has records + `lastPurchaseHash` | `purchases=[...1 record...]`, `lastPurchaseHash="hash-abc"` |
| `purchase_page2.json` | Pagination page 2: terminal (empty or no cursor) | `purchases=[]`, no `lastPurchaseHash` |
| `purchases_empty.json` | Empty list (since past all purchases) | `purchases=[]` |
| `purchase_non_eur.json` | Non-EUR purchase to verify skip | `currency="USD"`, must be silently skipped |
| `purchase_dst_boundary.json` | DST spec fixture (SALE-04) | `timestamp="2026-06-19T23:55:00Z"` (summer CEST) |
| `purchase_with_card_metadata.json` | Card brand + maskedPan (SALE-08, D-35) | `payments[0].attributes.cardType="VISA"`, `maskedPan="411111******1111"` |

**All fixtures:** Root object wraps purchases in `{"purchases": [...]}` matching actual API response shape. Each fixture includes a `"_source"` comment field citing `purchase.adoc`.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | busted 2.3.0 |
| Config file | `.busted` (exists from Phase 1) |
| Quick run command | `busted spec/refresh_idempotency_spec.lua spec/mapping_schema_spec.lua` |
| Full suite command | `busted spec/` |
| Coverage command | `busted --coverage spec/ && luacov` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SALE-01 | Gross amount = `purchase.amount / 100` | unit | `busted spec/mapping_spec.lua` | ❌ Wave 2 |
| SALE-02 | `transactionCode == "zettle:sale:" .. purchaseUUID1` | unit | `busted spec/mapping_spec.lua` | ❌ Wave 2 |
| SALE-03 | Every Phase-3 transaction has `booked = false`, no `valueDate` | unit | `busted spec/mapping_schema_spec.lua` | ❌ Wave 1 |
| SALE-04 | `bookingDate` UTC→Berlin correct at DST boundary | unit | `busted spec/mapping_spec.lua` | ❌ Wave 2 |
| SALE-05 | Double-refresh produces zero new transactionCodes | integration | `busted spec/refresh_idempotency_spec.lua` | ❌ Wave 1 |
| SALE-06 | `startDate` query param = ISO-8601 of clamped `since` | unit | `busted spec/purchases_spec.lua` | ❌ Wave 2 |
| SALE-08 | `name = "Kartenzahlung"` default; card brand + last-four upgrade | unit | `busted spec/mapping_spec.lua` | ❌ Wave 2 |
| I18N-01 | German strings in purpose (Brutto/MwSt/Trinkgeld/Netto/Beleg) | unit | `busted spec/mapping_spec.lua` | ❌ Wave 2 |
| TEST-03 | Double-refresh idempotency — gating spec | integration | `busted spec/refresh_idempotency_spec.lua` | ❌ Wave 1 |
| TEST-04 | 7-field schema gate on all fixture types | unit | `busted spec/mapping_schema_spec.lua` | ❌ Wave 1 |

### Sampling Rate

- **Per task commit:** `busted spec/refresh_idempotency_spec.lua spec/mapping_schema_spec.lua` (the two gating specs)
- **Per wave merge:** `busted spec/` (full suite, must be green)
- **Phase gate:** Full suite green + coverage ≥85% before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `spec/fixtures/purchases/purchase_simple_sale.json` — covers SALE-01, TEST-04
- [ ] `spec/fixtures/purchases/purchase_with_vat_and_tip.json` — covers SALE-01, I18N-01
- [ ] `spec/fixtures/purchases/purchase_refund.json` — covers D-32, REF (Phase 4 preview)
- [ ] `spec/fixtures/purchases/purchase_page1.json` — covers pagination
- [ ] `spec/fixtures/purchases/purchase_page2.json` — covers pagination terminal
- [ ] `spec/fixtures/purchases/purchases_empty.json` — covers SALE-06 empty result
- [ ] `spec/fixtures/purchases/purchase_non_eur.json` — covers D-37 skip
- [ ] `spec/fixtures/purchases/purchase_dst_boundary.json` — covers SALE-04
- [ ] `spec/fixtures/purchases/purchase_with_card_metadata.json` — covers SALE-08
- [ ] `spec/refresh_idempotency_spec.lua` — TEST-03 gating spec (must run RED first)
- [ ] `spec/mapping_schema_spec.lua` — TEST-04 gating spec (must run RED first)

---

## Section 5: i18n Keys (Phase 3 Additions)

The following keys must be added to both `STRINGS.de` (primary) and `STRINGS.en` (fallback) in `src/i18n.lua`. The German strings are normative (D-34/D-35).

| Key | German value | English value | Usage |
|-----|-------------|---------------|-------|
| `account.purpose.gross` | `"Brutto: %s €"` | `"Gross: %s €"` | Line 1 of purpose, always |
| `account.purpose.vat` | `"MwSt: %s €"` | `"VAT: %s €"` | Line 2, when vatAmount > 0 |
| `account.purpose.tip` | `"Trinkgeld: %s €"` | `"Tip: %s €"` | Line 3, when tip > 0 |
| `account.purpose.net` | `"Netto: %s €"` | `"Net: %s €"` | Line 4, always |
| `account.purpose.refund_for` | `"Rückerstattung zu Beleg #%s"` | `"Refund for receipt #%s"` | Refund purpose line 1 |
| `account.purpose.receipt_number` | `"Beleg #%s"` | `"Receipt #%s"` | Last line of purpose |
| `account.name.card_payment` | `"Kartenzahlung"` | `"Card payment"` | Default `name` field |

**Note:** The existing `purpose.gross`, `purpose.vat_line`, `purpose.tip`, `purpose.uuid`, `purpose.refund_of` in `src/i18n.lua` use `%.2f` format for float formatting. The D-34 German convention (comma decimal separator) requires a custom `_format_amount(minor_units)` helper rather than `string.format("%.2f", ...)` which produces dot separators. The i18n templates use `%s` and receive a pre-formatted string.

**German amount format helper (D-34):**
```lua
local function _format_amount(minor_units)
  -- Convert minor units to float, format with comma decimal separator
  local euros = minor_units / 100
  local s = string.format("%.2f", euros)
  return s:gsub("%.", ",")  -- "9.95" -> "9,95"
end
```

For amounts ≥ 10,000 euros (minor units ≥ 1,000,000), thousands separator would be needed (D-34: "no thousands separator below 10000"). For Phase 3, omit the thousands separator entirely — revisit if a real user has a single transaction over €10,000 (very rare for POS).

---

## Section 6: Risk Register

### R-1 (HIGH): `tools/manifest.txt` concatenation order — `M_i18n` before `M_mapping`

**What:** The current manifest order places `i18n` before `mapping` (verified in Phase 2 Plan 07). If Phase 3 adds `timezone.lua`, it must be inserted between `balance` and `mapping` (after `purchases`, before `mapping`). Any reversal causes load-time error in the amalgamated artifact: `M_i18n.t` called inside `mapping.lua`'s `do...end` block would reference an empty table.

**Mitigation:** The existing `build_spec.lua` verifies module order. Add an assertion that `mapping` appears after `i18n` (and `timezone` if added). Confirmed current order: `webbanking_header → log → errors → i18n → model → http → auth → pagination → purchases → payouts → balance → mapping → entry`.

**Status:** Current order is correct [VERIFIED: Phase 2 Plan 07 verification output]. Risk is only introduced if someone edits manifest.txt.

### R-2 (MEDIUM): JSON minor-unit round-trip in live MoneyMoney runtime

**What:** ADR-0003 Q4 confirmed `JSON():set({amount=995}):json()` round-trips correctly on MoneyMoney 2.4.72. The Phase 3 mapping (`purchase.amount / 100` → stored as Lua number → returned in MoneyMoney transaction table) follows the same path. The reverse direction (MoneyMoney reading our `amount` field) is what matters for display — if MoneyMoney has a bug reading non-integer float amounts, display could be wrong.

**Mitigation:** Keep `amount` as Lua number (`purchase.amount / 100`). A smoke spec encodes and decodes a known purchase fixture through the mock `JSON()` and asserts the round-trip preserves the float value.

### R-3 (MEDIUM): EU DST table incorrect for specific year

**What:** The DST boundary timestamps in `_to_berlin_local_time` are [ASSUMED] in this research and must be generated or verified before commit. An off-by-one (e.g., wrong year for last-Sunday calculation) would cause a sale at the DST boundary to receive the wrong `bookingDate`.

**Mitigation:** Spec gate with fixtures at known DST transitions for 2026 (start: 2026-03-29 01:00 UTC, end: 2026-10-25 01:00 UTC), 2027, 2028. The `purchase_dst_boundary.json` fixture covers 2026-06 (summer). Add a second spec-local constant for a 2026-01 winter case.

**Generation tool:** The planner should include a Wave 0 task to run the `last_sunday_utc` helper for years 2020–2040 and embed the resulting table as a literal.

### R-4 (LOW): 90-day `since` clamp accidentally clips a recent purchase

**What:** If `os.time()` and `since_from_moneymoney` are both very recent (e.g., first refresh immediately after adding the account), `max(since, now - 90*86400)` should return `since`. The clamp logic is:
```lua
local NINETY_DAYS = 90 * 86400
local effective_since = math.max(since, os.time() - NINETY_DAYS)
```
If `since = 0` (fresh account), `effective_since = now - NINETY_DAYS` — correct. If `since = now - 3600` (recent refresh), `effective_since = since` — correct.

**Mitigation:** Unit spec testing both cases: `since=0` (first refresh), `since=os.time()-3600` (recent). Assert `effective_since` value in each case.

### R-5 (MEDIUM): Test fixture JSON shape drifts from actual Zettle production response

**What:** Hand-rolled fixtures under `spec/fixtures/purchases/` are based on `purchase.adoc` field definitions. If Zettle quietly adds required fields or changes the `payments[].attributes` sub-object format, fixtures may diverge from real responses.

**Mitigation:** Each fixture's `_source` field cites `purchase.adoc`. The `purchase_with_card_metadata.json` fixture exercises the `attributes.cardType` + `attributes.maskedPan` path. A Phase 4 follow-up should capture one sandbox fixture (`spec/fixtures/purchases/recorded/`) to verify the hand-rolled shape against a real response.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON encoding/decoding | Custom JSON parser | `JSON()` built-in + dkjson in tests | MoneyMoney's built-in; dkjson is the mock backing |
| URL percent-encoding | Custom urlencode | `MM.urlencode()` built-in | Already in mm_mocks; used in Phase 2 |
| ISO-8601 timestamp parsing | Regex + math | Parse with `timestamp:match(pattern)` and extract Y/M/D/H/M/S as integers, then `os.time({...})` to convert | Lua's `os.time` is available and safe (ADR-0003 Q1); no need for a date library |
| HTTP pagination | Custom retry/reconnect logic | `M_pagination.iterate` with `M_http.get_json` (Phase 2) | Phase 2's transport layer is already correct |
| String formatting | Custom printf | `string.format` + `gsub` for decimal separator | Already in the stdlib; correct and auditable |

---

## Open Questions

1. **Does `purchase.payments[]` always have at least one element on a card payment?**
   - What we know: the spec lists `payments` as an array; card payments would naturally have one entry of type `IZETTLE_CARD`.
   - What's unclear: cash payments, store credit, or gift cards may produce an empty array or a single non-card entry.
   - **Recommendation:** Treat `payments[1]` as optional everywhere. Default to `"Kartenzahlung"` when `payments[1]` is absent or when `payments[1].type ~= "IZETTLE_CARD"`.

2. **Is `serviceCharge` ever non-zero for standard card POS sales?**
   - What we know: `serviceCharge` is documented as a service fee object with `amount`, `title`, `vatPercentage`, `quantity`. It is distinct from `gratuityAmount` (tip).
   - What's unclear: Zettle's definition of "service charge" vs "tip" in the German market; whether this appears in typical German POS transactions.
   - **Recommendation:** Skip `serviceCharge` in Phase 3 `purpose`. Add a `TODO Phase 5` comment. If Yves captures a real fixture with non-zero `serviceCharge`, add to Phase 5 scope.

3. **Does Zettle ever return `currency: null` or omit the field on a successful payment?**
   - What we know: the spec documents `currency` as a string (ISO 4217).
   - What's unclear: whether malformed/test responses could omit the field.
   - **Recommendation:** Guard: `if type(p.currency) ~= "string" or p.currency ~= "EUR" then skip end`. A missing `currency` field defaults to "not EUR" and the purchase is skipped with INFO log.

4. **Phase 4 hand-off: does Phase 4 call `M_mapping.purchase_to_transaction` directly or inject `booked=true` + `valueDate` post-hoc?**
   - What we know: Phase 4 needs to update existing transactions (same `transactionCode`) with `booked=true` and `valueDate = payout_date`.
   - **Recommendation:** Post-hoc injection model. Phase 4 emits a transaction with the same `transactionCode` plus `booked=true` + `valueDate`. MoneyMoney's dedup updates the record in-place. Phase 3's `M_mapping.purchase_to_transaction` stays a pure function with no Phase-4 awareness. This keeps Phase 3's mapping testable in isolation and avoids coupling.

5. **What is Zettle's default `limit` value when not specified?**
   - What we know: value range is 1–1000 [CITED: purchase.adoc]. Default is undocumented.
   - **Recommendation:** Always specify `limit=200` explicitly. This is a conservative choice: small enough to stay well under any server-side limit, large enough that most 90-day windows fit in ≤5 pages for typical German merchants. Do not rely on the server default.

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — Phase 3 is purely Lua code + spec additions consuming Phase 2's existing HTTP layer. No new CLI tools, databases, or services required beyond what Phase 1 established.)

---

## Security Domain

Phase 3 scope: `security_enforcement = true`, `security_asvs_level = 1`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (tokens managed by Phase 2) | Phase 2's `M_auth.cached_token` |
| V3 Session Management | No | Phase 2 owns session lifecycle |
| V4 Access Control | No | Single-tenant extension |
| V5 Input Validation | Yes — purchase JSON from attacker-reachable API | `pcall` around `JSON(raw):dictionary()` in `M_http.get_json` (already present from Phase 2) |
| V6 Cryptography | No | Phase 3 introduces no new crypto |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed JSON in purchase API response | Tampering | `pcall` around `JSON():dictionary()` (Phase 2's `M_http.get_json`) |
| Very large `purchase.amount` value causing arithmetic overflow | Tampering | Lua numbers are IEEE 754 doubles; `amount / 100` for amounts up to ~9 quadrillion minor units is safe. No overflow risk for EUR amounts. |
| `purchaseUUID1` containing Lua pattern special chars used in string ops | Tampering | `transactionCode` uses `..` concatenation, not `string.format` with `%s`; safe against Lua pattern injection. |
| `purpose` lines containing German umlauts (UTF-8) truncated by `string.format` | Spoofing | Lua's `string.format` is byte-agnostic; UTF-8 multi-byte sequences are preserved intact. No risk. |
| Bearer token leaked into purchase fetch URL (query param) | Info Disclosure | Bearer is in the Authorization header, not the URL. `M_http.get_json` logs only the URL, not headers (Phase 2 guarantee). |

**Phase 3 does not introduce new auth, crypto, or user-input surfaces.** The primary security concern is input validation on the purchase JSON body, which is already handled by `M_http.get_json`'s `pcall`-wrapped `JSON()` parse. No new security measures required beyond following existing patterns.

---

## Common Pitfalls

### Pitfall 1: Empty `purchases[]` not treated as terminal

**What goes wrong:** Pagination loop checks only for absent `lastPurchaseHash` as terminal signal. When Zettle returns a page with `lastPurchaseHash` present but `purchases: []`, the loop makes one more unnecessary request.
**Why it happens:** The `purchase.adoc` explicitly says "empty response" is the terminal, not absence of cursor.
**How to avoid:** Check `#page.purchases == 0` first, regardless of cursor presence.
**Warning signs:** Infinite loop or MAX_PAGES hit on an account with no purchases in the window.

### Pitfall 2: `timestamp` fed to `os.date` without timezone correction

**What goes wrong:** `bookingDate` is off by 1 or 2 hours for sales near midnight UTC.
**Why it happens:** `purchase.timestamp` is UTC. `os.date("*t", ...)` uses the system TZ (UTC on CI).
**How to avoid:** Always apply `_to_berlin_local_time(utc_posix)` before computing `bookingDate`. Never use `os.date("!*t", ...)` directly for `bookingDate`.
**Warning signs:** SALE-04 spec fails; `purchase_dst_boundary.json` fixture maps to `2026-06-19` instead of `2026-06-20`.

### Pitfall 3: ISO-8601 timestamp with milliseconds not handled

**What goes wrong:** `purchase.timestamp` sometimes includes milliseconds (`"2020-09-10T09:27:28.590+0000"`). Simple pattern `"(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"` stops at the decimal point and gets the seconds correctly, but if the match is anchored to end-of-string it fails.
**Why it happens:** `os.time({...})` requires integer seconds; milliseconds must be discarded.
**How to avoid:** Use a pattern that optionally matches milliseconds: `"(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)%.?%d*"`.

### Pitfall 4: `balance` not updated in Phase 3 `RefreshAccount`

**What goes wrong:** `RefreshAccount` returns `{balance = account.balance, transactions = ...}` — it returns the EXISTING balance, not a fresh one from the API. This is correct and intentional for Phase 3 (Finance API is Phase 4), but could be mistaken for a bug.
**Why it happens:** Phase 3 scope explicitly excludes ACCT-03 (Finance API balance).
**How to avoid:** Clearly comment in `entry.lua`: `-- TODO Phase 4: replace with Finance API balance`.
**Warning signs:** User reports incorrect balance — expected, documented in Phase 3 README note.

### Pitfall 5: `since` clamp applied inside `M_purchases.fetch` instead of at `RefreshAccount` boundary

**What goes wrong:** If clamping happens inside `fetch`, it's invisible to unit tests for `RefreshAccount` and harder to debug.
**Why it happens:** Temptation to co-locate the clamp with the parameter that uses it.
**How to avoid:** Per CONTEXT.md specifics: clamp `since` in `RefreshAccount` before calling `M_purchases.fetch_all`. The fetch function receives an already-clamped value.

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| MoneyMoney single-file hand-maintained | Modular `src/` + amalgamator | Phase 1 established this |
| `InitializeSession` (5-arg) | `InitializeSession2` (credentials array) | Phase 2 established this |
| `RefreshAccount` returns fixture | `RefreshAccount` drives real Purchase API | Phase 3 ships this |
| `booked=true` for all transactions | `booked=false` (Phase 3) → `true` via Phase 4 Finance API | D-31 |

**Deprecated/outdated (Phase 3 context):**
- `RefreshAccount` fixture transaction (`entry.lua` lines 130–148): replaced entirely in Phase 3. The fixture return is removed; the Phase-3 pipeline takes its place.
- Existing `purpose.gross`, `purpose.uuid` etc. keys in `i18n.lua`: these are Phase-1 skeleton keys. Phase 3 adds the properly-formatted D-34 keys. The old keys may be left in place (they are used in the Phase-1 fixture that is now removed) or cleaned up — planner's decision.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Default `limit` for GET /purchases/v2 is undocumented; recommending explicit `limit=200` | Section 1 | If server has a lower default and we rely on it, pagination may return fewer records than expected. Mitigation: always specify explicitly. |
| A2 | Empty `purchases[]` on `since` past all purchases (no explicit doc confirmation) | Section 1 | If Zettle returns a non-empty structure even for empty windows, `M_pagination.iterate` would still terminate correctly on empty array. Low risk. |
| A3 | `payments[]` may be empty on non-card payment types | Section 2 | If `payments[1]` is always present, the defensive guard adds minor overhead only. No risk. |
| A4 | DST boundary timestamps in `_to_berlin_local_time` table are [ASSUMED] values | Section 2b | Wrong DST boundary causes wrong `bookingDate` for sales near DST transitions. Must be generated/verified in Wave 0. |
| A5 | MoneyMoney updates existing transactions in-place when `transactionCode` matches | Section 2c | If MoneyMoney creates duplicates instead, Phase 4's `booked=true` update would create a second record rather than updating the Phase-3 record. Workaround would require Phase 4 design change. Unlikely given API contract. |
| A6 | `maskedPan:sub(-4)` extracts last 4 digits correctly for all card formats | Section 1 | If some card issuers use a different masking format (e.g., shorter PAN), last-4 extraction may produce wrong chars. Guard: `#last_four == 4` check before using. |
| A7 | `MAX_PAGES = 50` is sufficient for any 90-day window | Section 2a | A merchant with >10,000 sales in 90 days (>111/day) would hit the guard. Extremely rare for small German merchants. If hit, logged WARNING is visible to maintainer. |

---

## Sources

### Primary (HIGH confidence)

- [CITED: github.com/iZettle/api-documentation/purchase.adoc] — Purchase object field definitions, payment sub-object, GET /purchases/v2 query params, pagination semantics
- [CITED: moneymoney.app/api/webbanking/] — `RefreshAccount(account, since)` return contract, `transactionCode` dedup behavior, transaction table field names
- [CITED: Phase 2 implementation in `src/`] — `M_http.get_json` signature and return contract; `M_auth.cached_token`; `M_errors.from_http_status`; `M_log.redact` patterns — verified by reading source files directly
- [CITED: docs/adr/0003-sandbox-probe-results.md] — Q4 (JSON integer round-trip PASS), Q8 (`pcall` does not catch SSL errors)
- [CITED: .planning/phases/03-sale-spine-first-user-visible-slice/03-CONTEXT.md] — D-31..D-45 locked decisions
- [CITED: .planning/phases/02-authenticated-network-layer/02-07-SUMMARY.md] — manifest order verified: `webbanking_header → log → errors → i18n → model → http → auth → pagination → purchases → payouts → balance → mapping → entry`
- [CITED: spec/helpers/mm_mocks.lua] — `Mocks.push_response`, `Mocks._last_request`, `Mocks.setup`/`teardown` API

### Secondary (MEDIUM confidence)

- [CITED: developer.zettle.com/docs/api/purchase/user-guides/fetch-purchases/fetch-a-list-of-purchases] — pagination cursor pattern, `linkUrls` structure (page could not be fetched; based on search result summaries)

### Tertiary (LOW / ASSUMED)

- A1: `limit=200` as recommended page size — based on common API practice, not documented Zettle default
- A4: DST boundary timestamps 2020–2040 — algorithmic [ASSUMED]; must be verified by executor
- A7: MAX_PAGES=50 sufficiency — based on typical German merchant transaction volume estimate

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 3 |
|-----------|-------------------|
| Lua 5.4 only; no C modules | All Phase-3 code: plain Lua 5.4; no `require` of external libs in shipped artifact |
| Single `.lua` artifact via `tools/build.lua` amalgamator | `src/purchases.lua`, `src/pagination.lua`, `src/mapping.lua` must each be `do...end` block compatible |
| No `require()` of sibling files in shipped code | Cross-module access via global `M_*` tables only |
| API keys never logged | Phase 3 adds no new log call sites; Bearer in auth header never reaches `M_log` |
| German primary user strings | All 6 new i18n keys have German as primary |
| Coverage gate ≥85% on `src/` | Phase 3 adds substantial new src/ coverage; must not drop overall below 85% |
| No Claude/AI attribution in any file | Not applicable to RESEARCH.md creation; implementors must follow this |
| GPG-signed commits | All Phase-3 commits must be signed with `FDE07046A6178E89ADB57FD3DE300C53D8E18642` |
| Conventional Commits | Commit messages: `feat(03):`, `test(03):`, `fix(03):` etc. |
| No `os.execute`, `io.popen`, raw `socket` in shipped artifact | `tools/build.lua` H8 gate enforces this; Phase-3 source must not add such calls |
