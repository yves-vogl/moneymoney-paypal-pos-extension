-- src/i18n.lua
-- Ownership: I18N-02 (German primary string table), I18N-03 (English parity table).
-- Locale is hard-coded to "de" in v1. M_i18n.t(key, ...) is the sole access point.

local STRINGS = {
  de = {
    ["account.name"]              = "PayPal POS — %s",
    ["transaction.name.sale"]     = "Kartenzahlung",
    ["transaction.name.refund"]   = "Rückerstattung",
    ["transaction.name.fee"]      = "Gebühr",
    ["transaction.name.payout"]   = "Auszahlung",
    ["purpose.gross"]             = "Brutto %.2f EUR",
    ["purpose.vat_line"]          = "USt %d%%: %.2f EUR",
    ["purpose.tip"]               = "Trinkgeld: %.2f EUR",
    ["purpose.uuid"]              = "UUID %s",
    ["purpose.refund_of"]         = "Erstattung zu Beleg %s",
    ["account.purpose.gross"]         = "Brutto: %s €",
    ["account.purpose.vat"]           = "MwSt: %s €",
    ["account.purpose.tip"]           = "Trinkgeld: %s €",
    ["account.purpose.net"]           = "Netto: %s €",
    ["account.purpose.refund_for"]    = "Rückerstattung zu Beleg #%s",
    ["account.purpose.receipt_number"]= "Beleg #%s",
    ["account.name.card_payment"]     = "Kartenzahlung",
    -- Plan 04-02: fee / payout names + fee purpose templates (D-49, FEE-01..03, PAYOUT-02)
    ["account.name.fee"]                              = "Geb\xc3\xbchr",
    ["account.name.fee_aggregate"]                    = "PayPal POS Transaktionsgeb\xc3\xbchren",
    ["account.name.payout"]                           = "Auszahlung an Bankkonto",
    ["account.purpose.fee_label"]                     = "Geb\xc3\xbchr",
    ["account.purpose.fee_for_receipt"]               = "Geb\xc3\xbchr f\xc3\xbcr Beleg #%s",
    ["account.purpose.fee_aggregate"] =
      "Tagesaggregat \xe2\x80\x94 %d Einzelgeb\xc3\xbchren \xe2\x80\x94"
      .. " Detail-Verkn\xc3\xbcpfung nicht verf\xc3\xbcgbar",
    -- Plan 04-02: payment-method German labels for the SALE-07 card-tail line (Plan 04-04 consumes)
    ["account.purpose.payment_method.kontaktlos"]     = "kontaktlos",
    ["account.purpose.payment_method.chip"]           = "Chip",
    ["account.purpose.payment_method.swipe"]          = "Magnetstreifen",
    ["account.purpose.payment_method.ecommerce"]      = "Online",
    ["account.purpose.payment_method.manual"]         = "Manuell",
    ["account.purpose.payment_method.unknown"]        = "unbekannt",
    ["error.invalid_grant"]       = "Anmeldung fehlgeschlagen: API-Key wurde abgelehnt.",
    ["error.network"]             = "Netzwerkfehler: %s",
    ["error.rate_limit"]          = "Anfragelimit erreicht — bitte später erneut versuchen.",
    ["credential.api_key.label"]  = "API-Key",
  },
  en = {
    ["account.name"]              = "PayPal POS — %s",
    ["transaction.name.sale"]     = "Card payment",
    ["transaction.name.refund"]   = "Refund",
    ["transaction.name.fee"]      = "Fee",
    ["transaction.name.payout"]   = "Payout",
    ["purpose.gross"]             = "Gross %.2f EUR",
    ["purpose.vat_line"]          = "VAT %d%%: %.2f EUR",
    ["purpose.tip"]               = "Tip: %.2f EUR",
    ["purpose.uuid"]              = "UUID %s",
    ["purpose.refund_of"]         = "Refund of receipt %s",
    ["account.purpose.gross"]         = "Gross: %s €",
    ["account.purpose.vat"]           = "VAT: %s €",
    ["account.purpose.tip"]           = "Tip: %s €",
    ["account.purpose.net"]           = "Net: %s €",
    ["account.purpose.refund_for"]    = "Refund for receipt #%s",
    ["account.purpose.receipt_number"]= "Receipt #%s",
    ["account.name.card_payment"]     = "Card payment",
    -- Plan 04-02: fee / payout names + fee purpose templates
    ["account.name.fee"]                              = "Fee",
    ["account.name.fee_aggregate"]                    = "PayPal POS Transaction Fees",
    ["account.name.payout"]                           = "Payout to Bank Account",
    ["account.purpose.fee_label"]                     = "Fee",
    ["account.purpose.fee_for_receipt"]               = "Fee for receipt #%s",
    ["account.purpose.fee_aggregate"]                 =
      "Daily aggregate \xe2\x80\x94 %d individual fees \xe2\x80\x94 per-sale linkage unavailable",
    -- Plan 04-02: payment-method labels (English fallback)
    ["account.purpose.payment_method.kontaktlos"]     = "contactless",
    ["account.purpose.payment_method.chip"]           = "Chip",
    ["account.purpose.payment_method.swipe"]          = "Magstripe",
    ["account.purpose.payment_method.ecommerce"]      = "Online",
    ["account.purpose.payment_method.manual"]         = "Manual",
    ["account.purpose.payment_method.unknown"]        = "unknown",
    ["error.invalid_grant"]       = "Login failed: API key was rejected.",
    ["error.network"]             = "Network error: %s",
    ["error.rate_limit"]          = "Rate limit reached — please retry later.",
    ["credential.api_key.label"]  = "API key",
  },
}

local LOCALE = "de"

-- M_i18n.t(key, ...): look up the key in the active locale, fall back to "en",
-- then fall back to the key literal. When varargs are present, apply string.format.
M_i18n.t = function(key, ...)
  local template = (STRINGS[LOCALE] and STRINGS[LOCALE][key])
               or STRINGS.en[key]
               or key
  if select("#", ...) > 0 then
    return string.format(template, ...)
  end
  return template
end

-- Read-only markers exposed for tests (T06 asserts these).
M_i18n._locale  = LOCALE
M_i18n._strings = STRINGS
