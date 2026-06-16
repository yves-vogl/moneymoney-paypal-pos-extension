-- src/entry.lua
-- Walking-skeleton MoneyMoney callbacks (Phase 1). Zero network calls.
-- Emitted verbatim (top-level) by tools/build.lua so these functions land at global scope.

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "PayPal POS"
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive) -- luacheck: ignore 431
  local api_key
  if type(credentials) == "string" then
    api_key = credentials
  else
    api_key = credentials and credentials[1] and credentials[1].value
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
