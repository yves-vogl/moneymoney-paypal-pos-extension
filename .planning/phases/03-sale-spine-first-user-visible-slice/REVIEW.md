# Phase 3: Code Review Report

**Reviewed:** 2026-06-20T01:30:00Z
**Depth:** deep
**Branch:** phase-3/sale-spine-first-user-visible-slice
**Commit range:** ec64b19..98c194b
**Files Reviewed:** 17
**Status:** issues_found

---

## Summary

Phase 3 delivers the sale-ingestion pipeline: `src/mapping.lua`, `src/pagination.lua`, `src/purchases.lua`, a rewired `src/entry.lua::RefreshAccount`, seven new i18n keys in `src/i18n.lua`, and eight spec files with 10 JSON fixtures.

The core data path — cursor pagination, EUR gate, DST conversion, purpose formatting, transactionCode assignment — is structurally sound. The DST table values were independently verified against Python's `calendar` module for all 21 years (2020–2040): every entry is correct. The since-clamp arithmetic, the `%%.` pattern in `_format_amount`, the nil-guard cascade in `_format_label`, and the pagination dual-termination logic all hold under adversarial tracing.

Two genuine defects were found, one affecting bookkeeping correctness for real merchants:

1. **HIGH** — Refund purpose text suppresses the VAT (MwSt) breakdown line because the condition `vat > 0` fails for negative `vatAmount` on refunds. The Netto value is arithmetically correct, but the line-item that a German accountant needs for VAT-return filing is absent. No test covers a refund with non-zero `vatAmount`.

2. **HIGH** — The test that claims to cover DST boundaries for all years 2020–2040 (`dst_table_spec.lua` test "DST table covers years 2020..2040 boundaries") executes a loop that does nothing but suppress luacheck warnings. Only the single 2026 boundary is actually asserted. The test name is a false guarantee.

Three MEDIUM findings (missing guard, dead keys, future DST cliff) and three LOW findings (stale comment, wrong unicode codepoint in comment, unguarded nil UUID in transactionCode) round out the picture.

---

## Critical Issues

None.

---

## HIGH Issues

### HI-01: Refund purpose silently drops MwSt breakdown when `vatAmount` is negative

**File:** `src/mapping.lua:189-192`
**Issue:** `_format_purpose` shows the MwSt line only when `vat > 0`. For refund records, Zettle delivers `vatAmount` as a negative integer (e.g. `-159` for a -9.95 EUR refund). The condition `if vat > 0` is `false` for `-159`, so the VAT line is omitted. The Netto value is computed correctly as `amount - vat = -995 - (-159) = -836`, but the MwSt component is invisible in the purpose text.

A German merchant's bookkeeper will see:
```
Rückerstattung zu Beleg #UUID
Brutto: -9,95 €
Netto: -8,36 €
Beleg #1003
```
without the `MwSt: -1,59 €` line that is required to separate the net refund amount from the VAT refund for the Umsatzsteuer-Voranmeldung.

The issue is compounded by a test gap: `mapping_spec.lua` and `mapping_schema_spec.lua` never assert the Netto value or MwSt presence for `purchase_refund.json` (which has `vatAmount: -159`), so the silent behaviour is not caught.

**Fix:** Change the MwSt guard to test absolute value, or use a separate refund condition:

```lua
-- In _format_purpose, replace:
if vat > 0 then
    lines[#lines + 1] = M_i18n.t("account.purpose.vat", _format_amount(vat))
end

-- With:
if vat ~= 0 then
    lines[#lines + 1] = M_i18n.t("account.purpose.vat", _format_amount(vat))
end
```

Add the following assertion to `spec/mapping_spec.lua` alongside the existing refund tests:
```lua
it("refund purpose shows negative MwSt line when vatAmount < 0 (D-34 refund VAT breakdown)", function()
  local p = load_first("purchase_refund")  -- vatAmount=-159
  local txn = M_mapping.refund_to_transaction(p)
  assert.is_string(txn.purpose)
  assert.is_truthy(txn.purpose:find("MwSt: %-1,59 \xe2\x82\xac", 1, true),
    "refund purpose must contain 'MwSt: -1,59 €', got:\n" .. txn.purpose)
  assert.is_truthy(txn.purpose:find("Netto: %-8,36 \xe2\x82\xac", 1, true),
    "refund Netto must be -8,36, got:\n" .. txn.purpose)
end)
```

---

### HI-02: DST year-range coverage test is a no-op loop

**File:** `spec/dst_table_spec.lua:117-158`
**Issue:** The test "DST table covers years 2020..2040 boundaries" declares that it verifies multiple years, but the loop body at lines 138-148 creates a purchase with the string `"dummy"` as the timestamp (which fails to parse), assigns the result to `just_before`, then immediately suppresses it with `_ = just_before` and similar no-op assignments for `year`, `ss`, and `se`. No assertion is made against any of the five boundary rows in the `boundaries` table. The only actual assertion in the entire test (lines 151–157) covers only the single year 2026 — identical to the dedicated start-boundary test immediately below it.

If a DST table entry for, say, year 2032 or 2035 were corrupted to an incorrect value, this test would pass without detecting the error.

**Fix:** Replace the loop body with actual assertions. The POSIX timestamps for boundary years can be injected via a custom ISO-8601 string computed from the known `summer_start_utc` values (format them as `os.date("!%Y-%m-%dT%H:%M:%SZ", ss + 1)`):

```lua
it("DST table covers boundary timestamps for sampled years 2020..2040", function()
  local boundaries = {
    {2020, 1585443600, 1603587600},
    {2025, 1743296400, 1761440400},
    {2026, 1774746000, 1792890000},
    {2030, 1901149200, 1919293200},
    {2040, 2216250000, 2234998800},
  }
  for _, row in ipairs(boundaries) do
    local year = row[1]
    local ss   = row[2]  -- summer start UTC POSIX

    -- 1 second after summer_start -> CEST (+7200)
    local summer_str = os.date("!%Y-%m-%dT%H:%M:%SZ", ss + 1)
    local sp = make_purchase(summer_str)
    local st = M_mapping.purchase_to_transaction(sp)
    assert.is_table(st, year .. ": summer purchase must map to a table")
    assert.equals(ss + 1 + 7200, st.bookingDate,
      year .. ": summer offset must be +7200, got " .. tostring(st.bookingDate))

    -- 1 second before summer_start -> CET (+3600)
    local winter_str = os.date("!%Y-%m-%dT%H:%M:%SZ", ss - 1)
    local wp = make_purchase(winter_str)
    local wt = M_mapping.purchase_to_transaction(wp)
    assert.is_table(wt, year .. ": winter purchase must map to a table")
    assert.equals(ss - 1 + 3600, wt.bookingDate,
      year .. ": winter offset must be +3600, got " .. tostring(wt.bookingDate))
  end
end)
```

---

## MEDIUM Issues

### ME-01: `M_purchases.fetch` lacks a nil-bearer guard

**File:** `src/purchases.lua:73`
**Issue:** When `bearer` is `nil`, the expression `"Bearer " .. tostring(bearer)` produces `"Bearer nil"`, which is sent as the Authorization header value. This will result in a 401 from the Zettle API with no user-visible error message at the HTTP layer (the status is only inferred from the response body shape). The current caller — `RefreshAccount` — guards against nil bearer before calling `fetch_all`, so the production path is safe. However, `M_purchases.fetch` is a public module entry point and can be called directly from tests without that guard, creating a misleading silent failure mode.

**Fix:** Add an explicit guard at the top of `M_purchases.fetch`:
```lua
function M_purchases.fetch(clamped_since, bearer, cursor)
  if type(bearer) ~= "string" or #bearer == 0 then
    return nil, 401, '{"error":"unauthorized_client"}'
  end
  ...
end
```

---

### ME-02: Dead i18n keys bloat the shipped artifact

**File:** `src/i18n.lua:8-16` (STRINGS.de), `src/i18n.lua:31-39` (STRINGS.en)
**Issue:** Ten string keys are defined but have no call sites in any `src/*.lua` file:
`transaction.name.sale`, `transaction.name.refund`, `transaction.name.fee`,
`transaction.name.payout`, `purpose.gross`, `purpose.vat_line`, `purpose.tip`,
`purpose.uuid`, `purpose.refund_of` — all duplicated in both locales (20 dead entries total, 10 per locale). These ship in the amalgamated `Extension.lua` and consume space for no benefit. They also risk creating confusion if a future contributor mistakenly believes they are in active use.

**Fix:** If these keys are reserved for Phase 4/5 (Finance API transactions), add a comment saying so:
```lua
-- RESERVED for Phase 4 Finance API transactions (not yet wired):
-- ["transaction.name.sale"] = "Kartenzahlung",
-- ...
```
If they are truly dead, remove them now.

---

### ME-03: DST table silently fails for dates after 2040

**File:** `src/mapping.lua:97-106`
**Issue:** `_to_berlin_local_time` defaults to CET (+3600) when no DST table entry matches. For any timestamp after 2040-10-27T01:00Z, summer-time dates will be converted with the CET offset instead of CEST (+7200), producing a bookingDate that is 1 hour early. This does not crash, but the bookingDate will be silently wrong for transactions received in 2041+ summer months.

The 90-day window constraint (D-33) means this will first affect the extension in approximately March 2041 (when summer 2041 begins), giving roughly 15 years of safe operation from today.

**Fix:** Add a log line (not an error) when the timestamp falls outside the table's range, so future maintainers can see when the table needs extending:
```lua
local function _to_berlin_local_time(utc_posix)
  local offset = 3600  -- CET default (winter)
  local matched = false
  for _, entry in ipairs(DST_TABLE) do
    if utc_posix >= entry[1] and utc_posix < entry[2] then
      offset = 7200
      matched = true
      break
    end
  end
  if not matched and utc_posix > DST_TABLE[#DST_TABLE][2] then
    M_log.warn("_to_berlin_local_time: timestamp beyond DST table range, defaulting to CET")
  end
  return utc_posix + offset
end
```

---

## LOW Issues

### LO-01: Wrong Unicode codepoint in comment for Rückerstattung suffix

**File:** `src/mapping.lua:270`
**Issue:** The comment reads `-- U+00DC U+0063 ... "Rückerstattung" in UTF-8`. U+00DC is **Ü** (uppercase U with umlaut, UTF-8: `C3 9C`). The actual byte sequence used is `\xc3\xbc` which is **ü** (lowercase, U+00FC). The code is correct; the comment is wrong and would mislead a future maintainer searching by codepoint.

**Fix:**
```lua
-- U+00FC ü = \xc3\xbc (UTF-8); prefix "R" + ü + "ckerstattung" = "Rückerstattung"
local name = label .. " R\xc3\xbcckerstattung"
```

---

### LO-02: Stale comment in `purchases_spec.lua` references removed `_inline_iterate`

**File:** `spec/purchases_spec.lua:5-8`
**Issue:** The module comment says "fetch_all driving M_pagination.iterate (or fallback _inline_iterate in parallel-plan window)". The `_inline_iterate` fallback was removed in Plan 03-06 per the comment in `src/purchases.lua:9-10`. The spec comment is stale and should not describe code that no longer exists.

**Fix:** Remove the parenthetical:
```lua
-- Covers: fetch URL shape (host allowlist, startDate query param, limit,
-- descending, lastPurchaseHash), Bearer header pass-through (D-42),
-- error routing via M_errors.from_http_status (D-43), fetch_all driving
-- M_pagination.iterate (Plan 03-04).
```

---

### LO-03: Nil `purchaseUUID1` produces a non-unique `transactionCode`

**File:** `src/mapping.lua:248` and `src/mapping.lua:278`
**Issue:** `transactionCode = "zettle:sale:" .. tostring(p.purchaseUUID1 or "")`. If `purchaseUUID1` is absent or nil (an API contract violation), both expressions produce `"zettle:sale:"` or `"zettle:refund:"` respectively. Multiple nil-UUID purchases would collide on the same transactionCode, causing MoneyMoney to deduplicate them incorrectly.

The Zettle API contract guarantees UUID uniqueness, making this a defensive-coding gap rather than an exploitable production bug. No test covers this case.

**Fix:** Log a warning and produce a fallback that preserves some uniqueness (e.g. include `purchaseNumber`):
```lua
local uuid = p.purchaseUUID1
if not uuid then
  M_log.warn("M_mapping.purchase_to_transaction: missing purchaseUUID1, fallback to purchaseNumber")
  uuid = "missing-" .. tostring(p.purchaseNumber or os.time())
end
transactionCode = "zettle:sale:" .. tostring(uuid),
```

---

## Findings Summary

| ID    | Severity | File                          | Issue                                             |
|-------|----------|-------------------------------|---------------------------------------------------|
| HI-01 | HIGH     | src/mapping.lua:189-192       | Refund purpose drops MwSt breakdown line          |
| HI-02 | HIGH     | spec/dst_table_spec.lua:117-158 | Year-range DST test is a no-op loop             |
| ME-01 | MEDIUM   | src/purchases.lua:73          | nil bearer produces "Bearer nil" header silently  |
| ME-02 | MEDIUM   | src/i18n.lua:8-16, 31-39      | 20 dead i18n entries ship in artifact             |
| ME-03 | MEDIUM   | src/mapping.lua:97-106        | DST table silently wrong for dates after 2040     |
| LO-01 | LOW      | src/mapping.lua:270           | Wrong codepoint (U+00DC vs U+00FC) in comment     |
| LO-02 | LOW      | spec/purchases_spec.lua:5-8   | Stale reference to removed _inline_iterate        |
| LO-03 | LOW      | src/mapping.lua:248, 278      | Nil purchaseUUID1 yields non-unique transactionCode |

**Total:** 7 findings (2 HIGH, 3 MEDIUM, 2 LOW, 0 BLOCKER)

---

## Explicit Verifications (No Finding)

The following items were specifically called out in the review brief and are confirmed **correct**:

- **DST table values 2020–2040:** All 21 rows independently verified against Python `calendar.monthrange`. Every entry matches.
- **Pagination dual-termination:** The `has_more` logic and the `until` condition are consistent and correct. The guard fires before the 51st fetch, returning `nil,err` (not partial data), satisfying ERR-06.
- **`since` clamp:** `math.max(since or 0, os.time() - NINETY_DAYS)` handles nil, 0, past-epoch, and recent values correctly. `since=nil` and `since=0` both produce `now - 90d`.
- **`_format_amount` gsub pattern:** `s:gsub("%%.", ",")` in Lua source is the pattern `%.` which matches a literal dot. This is correct. The function produces `9,95` for `995`, not `,,,,`.
- **`_format_label` nil guards:** All guard branches (`type(payments) ~= "table"`, `type(first) ~= "table"`, `type(attrs) ~= "table"`, empty `cardType`, short `maskedPan`) are present and in the correct order.
- **ISO-8601 parser:** The pattern `[Z+]` correctly handles both `Z` and `+0000` suffixes as used by Zettle. Negative offsets (`-0500`) cause a nil match which triggers the `os.time()` fallback; this is acceptable given the API contract.
- **`transactionCode` collision risk for distinct valid UUIDs:** None. `zettle:sale:X` and `zettle:refund:X` always differ. The Zettle API guarantees UUID uniqueness.
- **Bearer / API-key logging:** No log line, LocalStorage write, or return value in any reviewed file surfaces the Bearer token or raw API key. The `org` prefix truncation at line 155 of `entry.lua` is correctly scoped (`tostring(orgUuid):sub(1, 8)`).
- **Egress host:** The only HTTP call in `src/purchases.lua` targets `https://purchase.izettle.com`. No new egress host was introduced.
- **`pcall` placement:** No `pcall` wraps `conn:request`. `pcall` is used only around `JSON(raw):dictionary()` in `src/http.lua`. This is correct per D-45.
- **`_inline_iterate` removal:** The function is absent from `src/purchases.lua`. Only the comment in the module header (LO-02) is stale.

---

## Recommendation

**FIX-HIGH-RECOMMENDED**

HI-01 is a bookkeeping correctness defect that will be visible to the first merchant who processes a VAT-bearing refund. It does not crash, but it produces a purpose text that an accountant cannot use for VAT filing. Fixing it (a one-character change from `> 0` to `~= 0`) plus the companion test is strongly recommended before merge.

HI-02 is a test-coverage gap masquerading as a guarantee: the test passes today because it contains no assertions, not because the DST table is correct. The table IS correct (verified independently), but the CI gate should not claim coverage it doesn't provide.

No BLOCKERs were found. The architecture is clean, the security invariants hold, and the pagination logic is correct. The MEDIUM and LOW items are housekeeping.

---

_Reviewed: 2026-06-20_
_Reviewer: adversarial code review (gsd-code-review workflow)_
_Depth: deep_
_Branch: phase-3/sale-spine-first-user-visible-slice_
