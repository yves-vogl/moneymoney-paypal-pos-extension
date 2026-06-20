-- src/entry.lua
-- MoneyMoney callbacks. Phase 1: SupportsBank/InitializeSession2/ListAccounts/EndSession.
-- Phase 3: RefreshAccount rewired to drive the real sale-ingestion pipeline.
-- Emitted verbatim (top-level) by tools/build.lua so these functions land at global scope.

-- D-33: clamp to no more than 90 days of history on first refresh.
-- Visible at the entry boundary per RESEARCH Pitfall 5 (not buried inside M_purchases.fetch).
local NINETY_DAYS = 90 * 86400

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

  -- B-01 / S-02: a 200-shaped /token response may still lack access_token
  -- (e.g. truncated reply or future API change). Concatenating nil into the
  -- Bearer header would throw "attempt to concatenate a nil value". Return
  -- error.invalid_grant so MoneyMoney shows a clean German message.
  if type(token_table) ~= "table"
      or type(token_table.access_token) ~= "string"
      or #token_table.access_token == 0 then
    return M_i18n.t("error.invalid_grant")
  end

  -- Step 5 (D-21 leg 2): GET /users/self
  local profile, p_status, p_raw = M_auth.fetch_profile(token_table.access_token)
  local p_err = M_errors.from_http_status(p_status, p_raw)
  if p_err then return p_err end

  -- B-02 / S-01: a 200-shaped /users/self response may lack organizationUuid
  -- (e.g. empty JSON object from CDN or API change). persist_session's own
  -- guard also catches this, but the entry.lua layer returns a user-visible
  -- error before any cache write is attempted.
  if type(profile) ~= "table"
      or type(profile.organizationUuid) ~= "string"
      or #profile.organizationUuid == 0 then
    return M_i18n.t("error.invalid_grant")
  end

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

-- Phase 3 — RefreshAccount: drives the real sale-ingestion pipeline.
-- Steps: 1 orgUuid guard, 2 cached_token (D-41), 3 since clamp (D-33),
--        4 fetch_all (M_purchases), 5 map (M_mapping), 6 return.
-- The four other callbacks (SupportsBank, InitializeSession2, ListAccounts,
-- EndSession) are FROZEN per Phase-2 surface contract.
function RefreshAccount(account, since) -- luacheck: ignore 431
  -- Step 1: resolve orgUuid from account.accountNumber (D-23a).
  -- T-03-W4-02: guard against missing / non-string / empty accountNumber.
  local orgUuid = account and account.accountNumber
  if type(orgUuid) ~= "string" or orgUuid == "" then
    return M_i18n.t("error.network", "missing_account")
  end

  -- Step 3 (before Step 2 so effective_since is ready for the log line):
  -- Clamp since to max(since_from_moneymoney, now - 90 days) per D-33.
  -- Clamp is at the entry boundary (not inside M_purchases.fetch) per
  -- RESEARCH Pitfall 5 — keeps it visible for debugging.
  local effective_since = math.max(since or 0, os.time() - NINETY_DAYS)

  -- Log line: only first 8 chars of orgUuid (ACCT-04 multi-merchant privacy)
  -- and the effective_since integer. Bearer is NEVER logged (T-03-W4-01 / SEC-03).
  M_log.info("RefreshAccount called for org=" .. tostring(orgUuid):sub(1, 8) ..
    " since=" .. tostring(effective_since))

  -- Step 2: obtain Bearer token from cache (D-41 nil-token guard).
  -- No re-auth from RefreshAccount — if the token is absent or expired,
  -- return German error.network so MoneyMoney shows a clean message.
  local bearer = M_auth.cached_token(orgUuid)
  if not bearer then
    return M_i18n.t("error.network", "\xe2\x80\x94")
  end

  -- Step 4: fetch all purchases via paginated cursor loop.
  -- M_purchases.fetch_all drives M_pagination.iterate (Plan 03-04/05).
  -- ERR-06 fail-whole-refresh: if fetch_err is non-nil, return it immediately.
  -- Partial transactions are NEVER returned alongside an error (T-03-W4-03).
  local purchases, fetch_err = M_purchases.fetch_all(effective_since, bearer)
  if fetch_err then return fetch_err end

  -- Step 5: map each purchase to a MoneyMoney transaction.
  -- D-32: refund records (p.refund == true) use refund_to_transaction.
  -- D-37: non-EUR purchases return nil from M_mapping — silently skip them.
  -- Any future skip conditions also return nil — the nil check covers all cases.
  local transactions = {}
  for _, p in ipairs(purchases or {}) do
    local txn
    if p.refund == true then
      txn = M_mapping.refund_to_transaction(p)
    else
      txn = M_mapping.purchase_to_transaction(p)
    end
    if txn ~= nil then
      transactions[#transactions + 1] = txn
    end
  end

  -- Step 6: return result.
  -- D-31: balance unchanged in Phase 3 (Finance API is Phase 4 ACCT-03).
  -- booked=false on every transaction — M_mapping enforces this invariant.
  return { balance = account.balance, transactions = transactions }
end

function EndSession()
  M_log.info("EndSession called")
  M_http.shutdown()
  return nil
end
