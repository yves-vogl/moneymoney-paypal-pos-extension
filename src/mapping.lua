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
-- DST_TABLE: EU DST boundaries for years 2020-2040 (D-36).
-- Each entry is {summer_start_utc, summer_end_utc} in POSIX seconds.
-- summer_start_utc = last Sunday of March at 01:00 UTC  => offset becomes +7200 (CEST)
-- summer_end_utc   = last Sunday of October at 01:00 UTC => offset reverts to +3600 (CET)
-- Values are pre-computed deterministically via last_sunday_utc(year, month, 1).
-- Verified: row 7 (index 7 = year 2026): {1774746000, 1792890000}
--   POSIX(2026-06-19T23:55Z) = 1781913300 is inside [1774746000, 1792890000) → +7200
--   POSIX(2026-01-31T23:55Z) = 1769903700 is before 1774746000 → +3600
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
  local brand = BRAND_MAP[card_type]
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

  -- MwSt (only when vatAmount > 0)
  local vat = type(p.vatAmount) == "number" and p.vatAmount or 0
  if vat > 0 then
    lines[#lines + 1] = M_i18n.t("account.purpose.vat", _format_amount(vat))
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

  -- Beleg #<purchaseNumber> (always — final line)
  lines[#lines + 1] = M_i18n.t("account.purpose.receipt_number", tostring(p.purchaseNumber or ""))

  return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Public functions
-- ---------------------------------------------------------------------------

-- M_mapping.purchase_to_transaction(p) -> table|nil
-- Map a Zettle purchase JSON object to a MoneyMoney transaction table.
-- Returns nil when:
--   - p is not a table
--   - p.currency is not "EUR" (D-37: non-EUR silently skipped with INFO log)
-- Sets booked = false; does NOT set valueDate (D-31).
-- transactionCode = "zettle:sale:" .. p.purchaseUUID1 (D-38).
function M_mapping.purchase_to_transaction(p)
  if type(p) ~= "table" then return nil end
  -- D-37: skip non-EUR purchases silently
  if type(p.currency) ~= "string" or p.currency ~= "EUR" then
    M_log.info("M_mapping.purchase_to_transaction: skipping non-EUR purchase currency=" ..
      tostring(p.currency))
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
    transactionCode = "zettle:sale:" .. tostring(p.purchaseUUID1 or ""),
    booked         = false,
  }
end

-- M_mapping.refund_to_transaction(p) -> table|nil
-- Map a Zettle refund purchase (refund == true) to a MoneyMoney transaction.
-- Zettle delivers negative amount on refund records (D-32) — do NOT negate.
-- transactionCode = "zettle:refund:" .. p.purchaseUUID1 (refund's own UUID, D-38).
-- name appends " Rückerstattung" suffix.
function M_mapping.refund_to_transaction(p)
  if type(p) ~= "table" then return nil end
  -- Refunds are always EUR (original was EUR), but guard defensively
  if type(p.currency) ~= "string" or p.currency ~= "EUR" then
    M_log.info("M_mapping.refund_to_transaction: skipping non-EUR refund currency=" ..
      tostring(p.currency))
    return nil
  end
  local utc = _parse_iso8601_utc(p.timestamp)
  local booking_date = utc and _to_berlin_local_time(utc) or os.time()
  -- Name: label + " Rückerstattung" suffix
  local label = _format_label(p.payments)
  -- U+00DC U+0063 ... "Rückerstattung" in UTF-8
  local name = label .. " R\xc3\xbcckerstattung"
  return {
    name           = name,
    amount         = (p.amount or 0) / 100,
    currency       = "EUR",
    bookingDate    = booking_date,
    purpose        = _format_purpose(p, {kind = "refund"}),
    transactionCode = "zettle:refund:" .. tostring(p.purchaseUUID1 or ""),
    booked         = false,
  }
end
