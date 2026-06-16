-- src/entry.lua
-- Walking-skeleton MoneyMoney callbacks (Phase 1). Zero network calls.
-- Emitted verbatim (top-level) by tools/build.lua so these functions land at global scope.

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "PayPal POS"
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive) -- luacheck: ignore 431
  -- First call with no credentials: declare the credential we want MoneyMoney
  -- to ask for. MM uses this to render an API-Key prompt; if MM does not honour
  -- the object it falls back to the default Username+Password UI, and the
  -- defensive extraction below still resolves the user input.
  if credentials == nil then
    return {
      title     = M_i18n.t("credential.api_key.label"),
      challenge = M_i18n.t("credential.api_key.label"),
      label     = M_i18n.t("credential.api_key.label"),
    }
  end

  -- Credential extraction handles every shape MM has been observed to pass:
  --   "x"                              single string
  --   {"x"} or {"x", "y"}              positional array of strings
  --   {{value = "x"}, ...}             challenge-style array of {label, value}
  --   {username = "x", password = "y"} default UI fallback
  local api_key
  if type(credentials) == "string" then
    api_key = credentials
  elseif type(credentials) == "table" then
    if credentials[1] then
      if type(credentials[1]) == "table" and credentials[1].value then
        api_key = credentials[1].value
      elseif type(credentials[1]) == "string" then
        api_key = credentials[1]
      end
    end
    if api_key == nil then
      api_key = credentials.password or credentials.username
    end
  end

  if api_key == nil or api_key == "" then
    return M_i18n.t("error.invalid_grant")
  end
  M_log.info("InitializeSession2: credential received (length=" .. #api_key .. ")")
  return nil
end

function ListAccounts(knownAccounts) -- luacheck: ignore 431
  return {
    {
      accountNumber = "paypal-pos-fixture-001",
      name          = M_i18n.t("account.name", "Test-Händler"),
      currency      = "EUR",
      portfolio     = false,
      type          = AccountTypeGiro,
    },
  }
end

function RefreshAccount(account, since) -- luacheck: ignore 431
  M_log.info("RefreshAccount called, since=" .. tostring(since))
  return {
    balance = 9.95,
    transactions = {
      {
        name           = M_i18n.t("transaction.name.sale"),
        amount         = 9.95,
        currency       = "EUR",
        bookingDate    = os.time(),
        valueDate      = os.time(),
        purpose        = M_i18n.t("purpose.gross", 9.95) .. "\n" ..
                         M_i18n.t("purpose.vat_line", 19, 1.59) .. "\n" ..
                         M_i18n.t("purpose.uuid", "fixture-0001"),
        bookingText    = M_i18n.t("transaction.name.sale"),
        booked         = true,
        transactionCode = "zettle:sale:fixture-0001",
      },
    },
  }
end

function EndSession()
  M_log.info("EndSession called")
  return nil
end
