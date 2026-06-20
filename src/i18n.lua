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
