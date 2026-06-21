-- src/mapping.lua
-- Ownership: SALE-01, SALE-02, SALE-03 (Phase 3 booked=false half per D-31),
--            SALE-04, SALE-08, I18N-01,
--            D-31 (booked=false, no valueDate),
--            D-32 (refund transaction with negative amount and zettle:refund: prefix),
--            D-34 (multi-line German bookkeeping purpose format),
--            D-35 (payment label with card brand + last-four via attributes.cardType/maskedPan),
--            D-36 (bookingDate as Berlin local time via inline DST table),
--            D-37 (non-EUR purchases silently skipped with INFO log),
--            D-38 (transactionCode = zettle:sale:<uuid> or zettle:refund:<uuid>).
-- Provides: M_mapping.purchase_to_transaction(p) -> table|nil
--           M_mapping.refund_to_transaction(p) -> table|nil
-- The M_mapping table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02).

-- ---------------------------------------------------------------------------
-- DST_TABLE: EU DST boundaries for years 2020-2050 (D-36, extended S-05/ME-03).
-- Each entry is {summer_start_utc, summer_end_utc} in POSIX seconds.
-- summer_start_utc = last Sunday of March at 01:00 UTC  => offset becomes +7200 (CEST)
-- summer_end_utc   = last Sunday of October at 01:00 UTC => offset reverts to +3600 (CET)
-- Values are pre-computed deterministically via last_sunday_utc(year, month, 1).
-- Verified: row 7 (index 7 = year 2026): {1774746000, 1792890000}
--   POSIX(2026-06-19T23:55Z) = 1781913300 is inside [1774746000, 1792890000) → +7200
--   POSIX(2026-01-31T23:55Z) = 1769903700 is before 1774746000 → +3600
-- Extended to 2050 to avoid silent wrong-offset for 2041+ purchases (S-05/ME-03).
-- ---------------------------------------------------------------------------
local DST_TABLE = {
  {1585443600, 1603587600},  -- 2020 (Mar 29 / Oct 25)
  {1616893200, 1635642000},  -- 2021 (Mar 28 / Oct 31)
  {1648342800, 1667091600},  -- 2022 (Mar 27 / Oct 30)
  {1679792400, 1698541200},  -- 2023 (Mar 26 / Oct 29)
  {1711846800, 1729990800},  -- 2024 (Mar 31 / Oct 27)
  {1743296400, 1761440400},  -- 2025 (Mar 30 / Oct 26)
  {1774746000, 1792890000},  -- 2026 (Mar 29 / Oct 25)
  {1806195600, 1824944400},  -- 2027 (Mar 28 / Oct 31)
  {1837645200, 1856394000},  -- 2028 (Mar 26 / Oct 29)
  {1869094800, 1887843600},  -- 2029 (Mar 25 / Oct 28)
  {1901149200, 1919293200},  -- 2030 (Mar 31 / Oct 27)
  {1932598800, 1950742800},  -- 2031 (Mar 30 / Oct 26)
  {1964048400, 1982797200},  -- 2032 (Mar 28 / Oct 31)
  {1995498000, 2014246800},  -- 2033 (Mar 27 / Oct 30)
  {2026947600, 2045696400},  -- 2034 (Mar 26 / Oct 29)
  {2058397200, 2077146000},  -- 2035 (Mar 25 / Oct 28)
  {2090451600, 2108595600},  -- 2036 (Mar 30 / Oct 26)
  {2121901200, 2140045200},  -- 2037 (Mar 29 / Oct 25)
  {2153350800, 2172099600},  -- 2038 (Mar 28 / Oct 31)
  {2184800400, 2203549200},  -- 2039 (Mar 27 / Oct 30)
  {2216250000, 2234998800},  -- 2040 (Mar 25 / Oct 28)
  {2248304400, 2266448400},  -- 2041 (Mar 31 / Oct 27)
  {2279754000, 2297898000},  -- 2042 (Mar 30 / Oct 26)
  {2311203600, 2329347600},  -- 2043 (Mar 29 / Oct 25)
  {2342653200, 2361402000},  -- 2044 (Mar 27 / Oct 30)
  {2374102800, 2392851600},  -- 2045 (Mar 26 / Oct 29)
  {2405552400, 2424301200},  -- 2046 (Mar 25 / Oct 28)
  {2437606800, 2455750800},  -- 2047 (Mar 31 / Oct 27)
  {2469056400, 2487200400},  -- 2048 (Mar 29 / Oct 25)
  {2500506000, 2519254800},  -- 2049 (Mar 28 / Oct 31)
  {2531955600, 2550704400},  -- 2050 (Mar 27 / Oct 30)
}

-- ---------------------------------------------------------------------------
-- Private helpers (local to this do...end block, not exported on M_mapping)
-- ---------------------------------------------------------------------------

-- Month day-of-year offsets (non-leap): cumulative days before each month.
local _MONTH_DAYS = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334}

-- _is_leap(y) -> boolean
local function _is_leap(y)
  return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

-- _parse_iso8601_utc(s) -> integer|nil
-- Parse ISO-8601 UTC timestamp string to POSIX seconds (TZ-independent).
-- Uses pure calendar arithmetic — no os.time(). This avoids the pitfall where
-- os.time() interprets component tables as LOCAL time on non-UTC machines.
-- Handles both "+0000" and "Z" suffixes, optional ".SSS" fractional seconds.
-- Returns nil for malformed or non-matching input.
local function _parse_iso8601_utc(s)
  if type(s) ~= "string" then return nil end
  local Y, M, D, H, Mi, S = s:match(
    "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)%.?%d*[Z+]"
  )
  if not Y then return nil end
  Y, M, D, H, Mi, S = tonumber(Y), tonumber(M), tonumber(D),
                       tonumber(H), tonumber(Mi), tonumber(S)
  if not (Y and M and D and H and Mi and S) then return nil end
  -- S-02: guard against out-of-range month/day to prevent nil-arithmetic crash
  -- in _MONTH_DAYS[M] (index 0 and 13+ are nil in Lua, causing hard errors).
  if M < 1 or M > 12 then return nil end
  if D < 1 or D > 31 then return nil end
  -- Days from 1970-01-01 to the start of year Y (Gregorian calendar arithmetic)
  local y = Y
  local days = (y - 1970) * 365
             + (math.floor((y - 1) / 4)   - math.floor(1969 / 4))
             - (math.floor((y - 1) / 100)  - math.floor(1969 / 100))
             + (math.floor((y - 1) / 400)  - math.floor(1969 / 400))
  -- Add days for completed months in year Y
  days = days + _MONTH_DAYS[M]
  -- Leap-year correction: if M > February and Y is a leap year, add 1 day
  if M > 2 and _is_leap(Y) then days = days + 1 end
  -- Add days in current month (D is 1-indexed, subtract 1)
  days = days + (D - 1)
  -- Convert to POSIX seconds and add intra-day time
  return days * 86400 + H * 3600 + Mi * 60 + S
end

-- _to_berlin_local_time(utc_posix) -> integer
-- Convert a UTC POSIX timestamp to Berlin local time by adding the Berlin offset.
-- Uses DST_TABLE to determine summer (CEST +7200) vs winter (CET +3600) offset.
-- Linear scan is O(21) — acceptable for a 21-row table.
local function _to_berlin_local_time(utc_posix)
  local offset = 3600  -- CET default (winter)
  for _, entry in ipairs(DST_TABLE) do
    if utc_posix >= entry[1] and utc_posix < entry[2] then
      offset = 7200  -- CEST (summer)
      break
    end
  end
  return utc_posix + offset
end

-- _format_amount(minor_units) -> string
-- Convert integer minor units to German-formatted amount string.
-- Examples: 995 -> "9,95"  |  500 -> "5,00"  |  -995 -> "-9,95"
-- No thousands separator (D-34: below 10000 euros, revisit if needed).
local function _format_amount(minor_units)
  local euros = minor_units / 100
  local s = string.format("%.2f", euros)
  return s:gsub("%.", ",")
end

-- _format_label(payments) -> string
-- Build the `name` field for a transaction (D-35).
-- Default: "Kartenzahlung" (via M_i18n.t).
-- Upgrade to "<Brand> •••• <last4>" when payments[1].attributes.cardType
-- and payments[1].attributes.maskedPan are both present.
-- Card metadata lives under payments[].attributes (NOT direct fields) per RESEARCH §1.
local BRAND_MAP = {
  VISA        = "Visa",
  MASTERCARD  = "Mastercard",
  AMEX        = "Amex",
  MAESTRO     = "Maestro",
  GIROCARD    = "girocard",
  UNIONPAY    = "UnionPay",
}

-- U+2022 BULLET = "\xe2\x80\xa2" (UTF-8)
local BULLET = "\xe2\x80\xa2"

-- D-57 / SALE-07: API value -> i18n key suffix for cardPaymentEntryMode (RESEARCH §6.2).
-- Any value not in the map falls through to "unknown" (-> "unbekannt" in DE per i18n.lua).
local ENTRY_MODE_MAP = {
  CONTACTLESS_EMV = "kontaktlos",
  ICC             = "chip",
  MSR             = "swipe",
  ECOMMERCE       = "ecommerce",
  MANUAL          = "manual",
}

local function _format_label(payments)
  -- Guard: payments must be a non-empty table with a first element
  if type(payments) ~= "table" then
    return M_i18n.t("account.name.card_payment")
  end
  local first = payments[1]
  if type(first) ~= "table" then
    return M_i18n.t("account.name.card_payment")
  end
  local attrs = first.attributes
  if type(attrs) ~= "table" then
    return M_i18n.t("account.name.card_payment")
  end
  local card_type  = attrs.cardType
  local masked_pan = attrs.maskedPan
  if type(card_type) ~= "string" or #card_type == 0 then
    return M_i18n.t("account.name.card_payment")
  end
  -- Require maskedPan to have at least 4 characters for last-four extraction
  if type(masked_pan) ~= "string" or #masked_pan < 4 then
    return M_i18n.t("account.name.card_payment")
  end
  -- S-11 (SEC R2 / R2-01 REVIEW): mirror S-04's 32-byte cardType cap from
  -- _format_purpose here in _format_label too. An unbounded `cardType` from a
  -- compromised CDN or adversarial response would otherwise balloon the
  -- transaction `name` field (which is the more user-visible surface than
  -- `purpose`). 32 bytes accommodates every published Zettle card brand
  -- (longest known: MASTERCARD = 10) with substantial headroom.
  card_type = card_type:sub(1, 32)
  -- WR-05 (REVIEW): normalise case before BRAND_MAP lookup so _format_label
  -- and _format_purpose's card-tail (which already does :upper() at line 286)
  -- produce byte-identical brand strings for the same purchase. Today Zettle
  -- delivers uppercase cardType values; this guards against a future API
  -- change that ships mixed-case (e.g. "Visa" or "visa").
  local card_type_upper = card_type:upper()
  local brand = BRAND_MAP[card_type_upper]
  if not brand then
    -- Unknown brand: capitalize literal (e.g. DISCOVER -> Discover)
    brand = card_type:sub(1, 1):upper() .. card_type:sub(2):lower()
  end
  local last_four = masked_pan:sub(-4)
  -- Bullet sequence: •••• (4 bullets)
  return brand .. " " .. BULLET .. BULLET .. BULLET .. BULLET .. " " .. last_four
end

-- _format_purpose(p, opts) -> string
-- Build the multi-line German bookkeeping purpose string (D-34).
-- opts.kind = "sale" | "refund"
-- opts.original_receipt = integer|nil (for refund: the original sale's purchaseNumber)
local function _format_purpose(p, opts)
  local lines = {}
  local kind = opts and opts.kind or "sale"

  if kind == "refund" then
    -- Line 1: "Rückerstattung zu Beleg #<original>" or UUID fallback
    local ref = opts and opts.original_receipt
    if ref == nil then
      ref = p.refundsPurchaseUUID1
    end
    lines[#lines + 1] = M_i18n.t("account.purpose.refund_for", tostring(ref or ""))
  end

  -- Brutto (always)
  lines[#lines + 1] = M_i18n.t("account.purpose.gross", _format_amount(p.amount or 0))

  -- D-53 / META-01: per-rate VAT block when groupedVatAmounts has >=2 entries.
  -- Else fall through to Phase-3 single MwSt line (preserves byte-identity for
  -- single-rate / empty-map / no-VAT fixtures per RESEARCH §Pitfall 8).
  local vat = type(p.vatAmount) == "number" and p.vatAmount or 0
  local gva = type(p.groupedVatAmounts) == "table" and p.groupedVatAmounts or {}
  local rate_entries = {}
  for k, v in pairs(gva) do
    -- tonumber accepts both "19.0" decimal-string AND "19" integer-string (R-5 defensive).
    local rate_num = tonumber(k)
    -- S-01 (SEC HIGH): range-guard rate_num to [0..100]. Attacker-controlled
    -- keys like "1e308" parse to a finite float with no integer representation
    -- which crashes string.format("%d", rate_num) downstream. No real-world
    -- tax regime carries a VAT rate outside this range, so the cap is safe.
    if rate_num and type(v) == "number"
        and rate_num >= 0 and rate_num <= 100 then
      rate_entries[#rate_entries + 1] = { rate = rate_num, amount = v }
    end
  end
  if #rate_entries >= 2 then
    -- META-01 multi-rate path: sort descending by rate, emit one line per rate.
    -- Format: "<rate>% MwSt: <amount_de> EUR" (literal EUR, distinct from
    -- the Phase-3 single-line "MwSt: <amount> €" to make the per-rate path greppable).
    table.sort(rate_entries, function(a, b) return a.rate > b.rate end)
    for _, e in ipairs(rate_entries) do
      local rate_display
      if e.rate == math.floor(e.rate) then
        rate_display = string.format("%d", e.rate)
      else
        rate_display = string.format("%g", e.rate)
      end
      lines[#lines + 1] = rate_display .. "% MwSt: " .. _format_amount(e.amount) .. " EUR"
    end
  else
    -- Phase-3 single-VAT fallback (HI-01: ~= 0 so negative refund VAT also renders).
    if vat ~= 0 then
      lines[#lines + 1] = M_i18n.t("account.purpose.vat", _format_amount(vat))
    end
  end

  -- Trinkgeld (only when sum of payments[].gratuityAmount > 0)
  local tip_sum = 0
  if type(p.payments) == "table" then
    for _, pay in ipairs(p.payments) do
      if type(pay) == "table" and type(pay.gratuityAmount) == "number" then
        tip_sum = tip_sum + pay.gratuityAmount
      end
    end
  end
  if tip_sum > 0 then
    lines[#lines + 1] = M_i18n.t("account.purpose.tip", _format_amount(tip_sum))
  end

  -- Netto (always): amount - vat - tip_sum
  -- For refunds: p.amount is already negative; vat may be negative too.
  -- We compute net as: amount - vat - tip_sum regardless of sign.
  local net = (p.amount or 0) - vat - tip_sum
  lines[#lines + 1] = M_i18n.t("account.purpose.net", _format_amount(net))

  -- D-57 / SALE-07: card-brand + entry-mode tail line (between Netto and Beleg).
  -- Both fields present  -> "Zahlart: <brand_de> (<entry_mode_de>)"
  -- Only cardType        -> "Zahlart: <brand_de>"
  -- Only entry-mode      -> "Zahlart: Kartenzahlung (<entry_mode_de>)"
  -- Neither              -> line OMITTED entirely (no "unbekannt (unbekannt)" noise).
  do
    local first_payment = type(p.payments) == "table" and p.payments[1] or nil
    local attrs = type(first_payment) == "table" and first_payment.attributes or nil
    local card_type, entry_mode
    if type(attrs) == "table" then
      -- S-04 (SEC MEDIUM): cap attacker-controllable cardType /
      -- cardPaymentEntryMode at 32 bytes before concatenation into purpose.
      -- All documented Zettle values (VISA, MASTERCARD, GIROCARD,
      -- CONTACTLESS_EMV, ICC, MSR, ECOMMERCE, MANUAL) fit comfortably under
      -- 32 chars; a 100KB cardType from a compromised response would bloat
      -- the purpose field accordingly without this cap.
      if type(attrs.cardType) == "string" and #attrs.cardType > 0 then
        card_type = attrs.cardType:sub(1, 32)
      end
      if type(attrs.cardPaymentEntryMode) == "string" and #attrs.cardPaymentEntryMode > 0 then
        entry_mode = attrs.cardPaymentEntryMode:sub(1, 32)
      end
    end
    if card_type or entry_mode then
      local brand_de
      if card_type then
        brand_de = BRAND_MAP[card_type:upper()]
        if not brand_de then
          -- Unknown brand: capitalize literal (Phase-3 BRAND_MAP fallback convention).
          brand_de = card_type:sub(1, 1):upper() .. card_type:sub(2):lower()
        end
      else
        -- Entry-mode only: fall back to generic "Kartenzahlung" brand label.
        brand_de = M_i18n.t("account.name.card_payment")
      end
      if entry_mode then
        local mode_key = ENTRY_MODE_MAP[entry_mode:upper()] or "unknown"
        local mode_de = M_i18n.t("account.purpose.payment_method." .. mode_key)
        lines[#lines + 1] = "Zahlart: " .. brand_de .. " (" .. mode_de .. ")"
      else
        lines[#lines + 1] = "Zahlart: " .. brand_de
      end
    end
  end

  -- Beleg #<purchaseNumber> (always — final line)
  lines[#lines + 1] = M_i18n.t("account.purpose.receipt_number", tostring(p.purchaseNumber or ""))

  return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Public wrappers (Plan 04-02): expose private helpers so M_finance.parse_transaction
-- and the entry-layer cross-refresh logic can reuse them without violating the
-- no-require()-of-siblings invariant (D-02 / RESEARCH §Pitfall 10).
-- ---------------------------------------------------------------------------

function M_mapping.parse_iso8601_utc(s)
  return _parse_iso8601_utc(s)
end

function M_mapping.to_berlin_local_time(utc_posix)
  return _to_berlin_local_time(utc_posix)
end

-- _berlin_local_date(iso_ts) -> "YYYY-MM-DD"|nil
-- Pitfall 4: cluster fees by Berlin-local DATE not UTC date (a fee at
-- 2026-06-15T23:45:00Z = local 2026-06-16 01:45 CEST must aggregate under "2026-06-16").
local function _berlin_local_date(iso_ts)
  local utc = _parse_iso8601_utc(iso_ts)
  if not utc then return nil end
  local berlin_posix = _to_berlin_local_time(utc)
  return os.date("!%Y-%m-%d", berlin_posix)
end

-- _berlin_date_to_posix(date_iso) -> integer|nil
-- Returns a POSIX timestamp that, when decomposed via os.date("!*t", ...), yields
-- year/month/day = date_iso, hour=0, min=0. This matches the Phase-3 bookingDate
-- convention (D-36): bookingDate POSIX is "Berlin wall-clock seconds treated as
-- if UTC" — parsing date_iso .. "T00:00:00Z" as UTC gives exactly that value.
-- No DST offset is added here: the offset is already baked into the date-component
-- choice by the caller (a fee with Berlin-local date "2026-06-15" was clustered
-- via _berlin_local_date, which already applied _to_berlin_local_time once).
local function _berlin_date_to_posix(date_iso)
  if type(date_iso) ~= "string" then return nil end
  if not date_iso:match("^%d%d%d%d%-%d%d%-%d%d$") then return nil end
  return _parse_iso8601_utc(date_iso .. "T00:00:00Z")
end

function M_mapping.berlin_local_date(iso_ts)
  return _berlin_local_date(iso_ts)
end

-- ---------------------------------------------------------------------------
-- Public functions
-- ---------------------------------------------------------------------------

-- M_mapping.purchase_to_transaction(p) -> table|nil
-- Map a Zettle purchase JSON object to a MoneyMoney transaction table.
-- Returns nil when:
--   - p is not a table
--   - p.currency is not "EUR" (D-37: non-EUR silently skipped with INFO log)
--   - p.purchaseUUID1 is nil or empty (S-03: would cause transactionCode collision)
-- Sets booked = false; does NOT set valueDate (D-31).
-- transactionCode = "zettle:sale:" .. p.purchaseUUID1 (D-38).
function M_mapping.purchase_to_transaction(p)
  if type(p) ~= "table" then return nil end
  -- D-37: skip non-EUR purchases silently
  if type(p.currency) ~= "string" or p.currency ~= "EUR" then
    -- S-01: cap currency string at 8 chars (ISO 4217 = 3 chars; 8 provides margin)
    -- to prevent unbounded attacker-controlled strings reaching the log sink.
    local cur = tostring(p.currency or "<nil>"):sub(1, 8)
    M_log.info("M_mapping.purchase_to_transaction: skipping non-EUR purchase currency=" .. cur)
    return nil
  end
  -- S-03/LO-03: guard against nil or empty purchaseUUID1 to prevent transactionCode
  -- collision. Two nil-UUID purchases would both yield "zettle:sale:" and one would
  -- be silently de-duplicated by MoneyMoney's idempotency logic.
  if type(p.purchaseUUID1) ~= "string" or #p.purchaseUUID1 == 0 then
    M_log.warn("M_mapping.purchase_to_transaction: skipping purchase with missing purchaseUUID1")
    return nil
  end
  -- bookingDate: parse UTC ISO-8601 timestamp and convert to Berlin local time
  local utc = _parse_iso8601_utc(p.timestamp)
  local booking_date = utc and _to_berlin_local_time(utc) or os.time()
  -- Build transaction table (D-31: no valueDate key written)
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

-- M_mapping.refund_to_transaction(p, opts) -> table|nil
-- Map a Zettle refund purchase (refund == true) to a MoneyMoney transaction.
-- Zettle delivers negative amount on refund records (D-32) — do NOT negate.
-- transactionCode = "zettle:refund:" .. p.purchaseUUID1 (refund's own UUID, D-38).
-- name appends " Rückerstattung" suffix.
--
-- Plan 04-02 (D-50 / REF-02): opts is an optional second argument. When
-- opts.original_receipt is non-nil truthy, the purpose text cites that receipt
-- number ("Rückerstattung zu Beleg #<original_receipt>"). When opts is nil OR
-- opts.original_receipt is nil, falls through to the Phase-3 D-32 fallback
-- (purpose cites refundsPurchaseUUID1). Existing Phase-3 callers passing only
-- (p) continue to work byte-identically.
function M_mapping.refund_to_transaction(p, opts)
  if type(p) ~= "table" then return nil end
  -- Refunds are always EUR (original was EUR), but guard defensively
  if type(p.currency) ~= "string" or p.currency ~= "EUR" then
    -- S-01: cap currency string at 8 chars to prevent unbounded log lines.
    local cur = tostring(p.currency or "<nil>"):sub(1, 8)
    M_log.info("M_mapping.refund_to_transaction: skipping non-EUR refund currency=" .. cur)
    return nil
  end
  -- S-03/LO-03: guard against nil or empty purchaseUUID1 (same reasoning as purchase path).
  if type(p.purchaseUUID1) ~= "string" or #p.purchaseUUID1 == 0 then
    M_log.warn("M_mapping.refund_to_transaction: skipping refund with missing purchaseUUID1")
    return nil
  end
  local utc = _parse_iso8601_utc(p.timestamp)
  local booking_date = utc and _to_berlin_local_time(utc) or os.time()
  -- Name: label + " Rückerstattung" suffix
  local label = _format_label(p.payments)
  -- U+00FC ü = \xc3\xbc (UTF-8); prefix "R" + ü + "ckerstattung" = "Rückerstattung"
  local name = label .. " R\xc3\xbcckerstattung"
  return {
    name           = name,
    amount         = (p.amount or 0) / 100,
    currency       = "EUR",
    bookingDate    = booking_date,
    purpose        = _format_purpose(p, {
      kind = "refund",
      original_receipt = opts and opts.original_receipt or nil,
    }),
    transactionCode = "zettle:refund:" .. p.purchaseUUID1,
    booked         = false,
  }
end

-- ---------------------------------------------------------------------------
-- Plan 04-02: Phase-4 mappers — fee_to_transaction, fee_aggregate_to_transaction,
-- payout_to_transaction, promote_to_booked.
-- All pure-logic; no I/O. Each returns the 7-field MoneyMoney transaction table
-- or nil on malformed input. RESEARCH §3.4 / §4.4.
-- ---------------------------------------------------------------------------

-- M_mapping.fee_to_transaction(fee_record, originating_purchase) -> table|nil
-- fee_record: { kind="PAYMENT_FEE", amount, timestamp_iso, timestamp_posix,
--               originatingTransactionUuid } — typically produced by
--               M_finance.parse_transaction. Also tolerates a raw record with
--               `timestamp` instead of `timestamp_iso`.
-- originating_purchase: purchase record (looked up via payments_by_uuid in
--   entry.lua); must have purchaseNumber. May be nil for orphaned fees (but
--   then the entry layer routes through fee_aggregate_to_transaction instead).
-- transactionCode = "zettle:fee:" .. fee_record.originatingTransactionUuid
--   (RESEARCH §3.4: Finance records have no `uuid` field of their own — the only
--   stable identifier is originatingTransactionUuid which is unique per payment leg).
function M_mapping.fee_to_transaction(fee_record, originating_purchase)
  if type(fee_record) ~= "table" then return nil end
  local fee_uuid = fee_record.originatingTransactionUuid
  if type(fee_uuid) ~= "string" or #fee_uuid == 0 then
    M_log.warn("M_mapping.fee_to_transaction: skipping fee with missing originatingTransactionUuid")
    return nil
  end
  local iso = fee_record.timestamp_iso or fee_record.timestamp
  local utc = _parse_iso8601_utc(iso)
  local booking_date = utc and _to_berlin_local_time(utc) or os.time()
  local amount_minor = fee_record.amount or 0
  local receipt_no
  if type(originating_purchase) == "table" and originating_purchase.purchaseNumber ~= nil then
    receipt_no = tostring(originating_purchase.purchaseNumber)
  else
    receipt_no = "?"
  end
  local purpose = M_i18n.t("account.purpose.fee_for_receipt", receipt_no)
                   .. "\nBetrag: " .. _format_amount(amount_minor) .. " EUR"
  return {
    name           = M_i18n.t("account.name.fee"),
    amount         = amount_minor / 100,
    currency       = "EUR",
    bookingDate    = booking_date,
    purpose        = purpose,
    transactionCode = "zettle:fee:" .. fee_uuid,
    booked         = true,
  }
end

-- M_mapping.fee_aggregate_to_transaction(fees_for_date, date_iso, count) -> table|nil
-- fees_for_date: array of fee_records all on the same Berlin-local date
-- date_iso: "YYYY-MM-DD" Berlin-local date string
-- count: integer; defaults to #fees_for_date when omitted (purpose text)
-- transactionCode = "zettle:fee:aggregate:" .. date_iso (D-49 idempotency anchor)
function M_mapping.fee_aggregate_to_transaction(fees_for_date, date_iso, count)
  if type(fees_for_date) ~= "table" then return nil end
  if type(date_iso) ~= "string" or not date_iso:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return nil
  end
  local booking_date = _berlin_date_to_posix(date_iso)
  if not booking_date then return nil end
  local sum_minor = 0
  for _, f in ipairs(fees_for_date) do
    if type(f) == "table" and type(f.amount) == "number" then
      sum_minor = sum_minor + f.amount
    end
  end
  local n = count or #fees_for_date
  return {
    name           = M_i18n.t("account.name.fee_aggregate"),
    amount         = sum_minor / 100,
    currency       = "EUR",
    bookingDate    = booking_date,
    purpose        = M_i18n.t("account.purpose.fee_aggregate", n),
    transactionCode = "zettle:fee:aggregate:" .. date_iso,
    booked         = true,
  }
end

-- M_mapping.payout_to_transaction(payout_record) -> table|nil
-- payout_record: { kind="PAYOUT", amount, timestamp_iso, timestamp_posix,
--                  originatingTransactionUuid } (PAYOUT carries its own UUID as
--                  originatingTransactionUuid per RESEARCH §3.4).
-- amount already negative per API (PAYOUT-01); name = "Auszahlung an Bankkonto"
-- (PAYOUT-02); bookingDate = Berlin local (PAYOUT-03); valueDate = bookingDate
-- (the PAYOUT itself IS the settlement event — RESEARCH §3.4).
function M_mapping.payout_to_transaction(payout_record)
  if type(payout_record) ~= "table" then return nil end
  local po_uuid = payout_record.originatingTransactionUuid
  if type(po_uuid) ~= "string" or #po_uuid == 0 then
    M_log.warn("M_mapping.payout_to_transaction: skipping payout with missing originatingTransactionUuid")
    return nil
  end
  local iso = payout_record.timestamp_iso or payout_record.timestamp
  local utc = _parse_iso8601_utc(iso)
  local booking_date = utc and _to_berlin_local_time(utc) or os.time()
  local amount_minor = payout_record.amount or 0
  local date_de = os.date("!%d.%m.%Y", booking_date)
  local purpose = "Auszahlung an Bankkonto am " .. date_de
                   .. "\nBetrag: " .. _format_amount(amount_minor) .. " EUR"
  return {
    name           = M_i18n.t("account.name.payout"),
    amount         = amount_minor / 100,
    currency       = "EUR",
    bookingDate    = booking_date,
    purpose        = purpose,
    transactionCode = "zettle:payout:" .. po_uuid,
    booked         = true,
    valueDate      = booking_date,
  }
end

-- M_mapping.promote_to_booked(txn, valueDate_posix_local)
-- Mutates txn in place: sets booked=true, valueDate=valueDate_posix_local.
-- transactionCode UNCHANGED — MoneyMoney's dedup updates the row in place
-- (D-56 / RESEARCH §4.4). Idempotent. No-op on non-table input.
function M_mapping.promote_to_booked(txn, valueDate_posix_local)
  if type(txn) ~= "table" then return end
  txn.booked    = true
  txn.valueDate = valueDate_posix_local
end
