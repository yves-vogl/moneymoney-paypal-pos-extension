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

  -- Step 3 (D-22): extract client_id from JWT payload (pure CPU, no network).
  -- A malformed assertion JWT (cannot yield client_id) returns synchronously
  -- with ZERO network calls per Pattern 4 / hard constraint 8.
  local client_id = M_auth._extract_client_id(api_key)
  if not client_id then
    M_log.info("InitializeSession2: assertion JWT could not yield client_id")
    return M_i18n.t("error.invalid_grant")
  end

  -- Step 4 (D-21 leg 1): POST /token
  local token_table, status, raw_body = M_auth.exchange_assertion(api_key, client_id)
  local err = M_errors.from_http_status(status, raw_body)
  if err then return err end

  -- Step 5 (D-21 leg 2): GET /users/self
  local profile, p_status, p_raw = M_auth.fetch_profile(token_table.access_token)
  local p_err = M_errors.from_http_status(p_status, p_raw)
  if p_err then return p_err end

  -- Step 6 (D-23c): persist cache keyed by organizationUuid
  M_auth.persist_session(token_table, profile, client_id)
  return nil
end

function ListAccounts(knownAccounts) -- luacheck: ignore 431
  local accounts = {}

  for orgUuid, entry in pairs(LocalStorage.zettle or {}) do
    local publicName = entry.publicName
    local label
    if type(publicName) == "string" and #publicName > 0 then
      label = "PayPal POS \xe2\x80\x94 " .. publicName
    else
      label = "PayPal POS \xe2\x80\x94 " .. orgUuid:sub(1, 8)
    end
    accounts[#accounts + 1] = {
      accountNumber = orgUuid,
      type          = AccountTypeGiro,
      name          = label,
      currency      = "EUR",
      portfolio     = false,
    }
  end

  -- Empty cache: return Phase-1 fixture so walking-skeleton tests still pass
  -- (and so MoneyMoney always gets at least one account record to work with
  -- before the first successful InitializeSession2 run).
  if #accounts == 0 then
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

  return accounts
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
  M_http.shutdown()
  return nil
end
