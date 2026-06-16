-- .luacheckrc
std = "lua54+busted"
files["spec/**"] = { std = "lua54+busted" }
files["tools/**"] = { std = "lua54" }

-- MoneyMoney built-in globals (read-only for luacheck)
read_globals = {
  "WebBanking", "Connection", "JSON", "HTML", "PDF",
  "MM", "LocalStorage",
  "ProtocolWebBanking", "ProtocolFinTS",
  "AccountTypeGiro", "AccountTypeSavings", "AccountTypeFixedTermDeposit",
  "AccountTypeLoan", "AccountTypeCreditCard", "AccountTypePortfolio",
  "AccountTypeOther",
  "LoginFailed",
}

-- Extension callbacks are top-level globals (written once by entry.lua)
globals = {
  "SupportsBank", "InitializeSession2", "ListAccounts",
  "RefreshAccount", "EndSession",
}

-- Module tables predeclared in webbanking_header.lua
globals[#globals+1] = "M_log"
globals[#globals+1] = "M_errors"
globals[#globals+1] = "M_i18n"
globals[#globals+1] = "M_model"
globals[#globals+1] = "M_http"
globals[#globals+1] = "M_auth"
globals[#globals+1] = "M_pagination"
globals[#globals+1] = "M_purchases"
globals[#globals+1] = "M_payouts"
globals[#globals+1] = "M_balance"
globals[#globals+1] = "M_mapping"
globals[#globals+1] = "DEBUG"

ignore = { "212" }  -- 212: variable set but not accessed (acceptable for stubs)
