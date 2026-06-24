-- src/webbanking_header.lua
-- Emitted verbatim at the top of dist/paypal-pos.lua by tools/build.lua.
-- This file must declare all module tables and DEBUG before any other module
-- references them (all subsequent modules are wrapped in do...end blocks that
-- close over these top-level globals).

-- Module tables predeclared so every do...end block can reference them.
M_log        = {}
M_errors     = {}
M_i18n       = {}
M_model      = {}
M_http       = {}
M_auth       = {}
M_pagination = {}
M_purchases  = {}
M_finance    = {}
M_mapping    = {}

-- SEC-04: DEBUG must be false in every shipped artifact.
-- tools/build.lua aborts the build if any non-comment line contains DEBUG = true.
DEBUG = false

WebBanking{
  version     = __VERSION__,
  country     = "de",
  url         = "https://oauth.zettle.com",
  services    = {"PayPal POS"},
  description = "PayPal POS / Zettle Umsätze, Gebühren und Auszahlungen",
  -- D-19: API-key model uses InitializeSession2's credentials array; the
  -- declaration below names the field "API-Key" in the MoneyMoney login
  -- dialog (replacing the default Benutzername/Passwort fallback). Single
  -- masked field; description points users at the Zettle API-Key page.
  credentials = {
    {
      label       = "API-Key",
      description = "JWT-Bearer Token (Scopes: READ:PURCHASE + READ:FINANCE)",
      secret      = true,
    },
  },
}
