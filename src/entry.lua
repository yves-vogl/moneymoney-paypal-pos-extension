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
  -- S-04: upper-bound at os.time() to prevent:
  --   (a) math.huge crashing os.date() ("number has no integer representation")
  --   (b) future timestamps producing a startDate that returns zero purchases.
  effective_since = math.min(effective_since, os.time())

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

  -- -------------------------------------------------------------------------
  -- Plan 04-03 — Phase-4 wiring (RESEARCH §2.1, §3.1, §4.2, §4.3).
  -- Steps 5-14 below extend Phase-3's mapping loop with: cross-refresh
  -- indexes (purchases_by_uuid + payments_by_uuid), Finance API state +
  -- transactions fetch (ERR-06 fail-whole-refresh on either), SALE-03
  -- promotion (D-56 temporal-inference rule), D-49 Option B fee
  -- classification, and payout mapping.
  -- -------------------------------------------------------------------------

  -- Step 5: D-50 / REF-02 — index purchases by purchaseUUID1 for refund lookup.
  -- The refund's `refundsPurchaseUUID1` field points at the original sale's
  -- purchaseUUID1. When the original is in the SAME refresh window, the refund
  -- purpose cites "Beleg #<original purchaseNumber>" instead of the UUID.
  local purchases_by_uuid = {}
  for _, p in ipairs(purchases or {}) do
    if type(p) == "table" and type(p.purchaseUUID1) == "string" and #p.purchaseUUID1 > 0 then
      purchases_by_uuid[p.purchaseUUID1] = p
    end
  end

  -- Step 6: D-49 / FEE-01 — index payments by payments[].uuid for fee join.
  -- CRITICAL (RESEARCH §3.1): the link key is `payments[].uuid`, NOT
  -- `purchaseUUID1`. One purchase can carry multiple payment legs; each leg
  -- has its own UUID, and Finance API PAYMENT_FEE records use that leg-UUID
  -- as `originatingTransactionUuid`. The CONTEXT D-50 wording said
  -- "purchaseUUID1" — that was incorrect; the corrected join key is
  -- payments[].uuid per the FEE-01 end-to-end spec.
  local payments_by_uuid = {}
  for _, purchase in ipairs(purchases or {}) do
    if type(purchase) == "table" and type(purchase.payments) == "table" then
      for _, payment in ipairs(purchase.payments) do
        if type(payment) == "table"
            and type(payment.uuid) == "string"
            and #payment.uuid > 0 then
          payments_by_uuid[payment.uuid] = purchase
        end
      end
    end
  end

  -- Step 7: ACCT-03 / D-52 / RESEARCH §1.4 — fetch balance + pendingBalance.
  -- Two sequential GETs (liquid then preliminary); ERR-06 fail-whole-refresh
  -- on either-leg error per RESEARCH §Pitfall 5.
  local account_state, state_err = M_finance.fetch_account_state(bearer)
  if state_err then return state_err end

  -- Step 8: fetch all Finance API transaction records (paginated via offset).
  local fin_records_raw, fin_err = M_finance.fetch_all(effective_since, bearer)
  if fin_err then return fin_err end

  -- Step 9: parse + split into PAYMENT / PAYMENT_FEE / PAYOUT buckets.
  -- M_finance.parse_transaction silently filters out non-Phase-4 types
  -- (ADJUSTMENT, CASHBACK, etc.) per RESEARCH §1.3.
  local fin_payments, fin_fees, fin_payouts = {}, {}, {}
  for _, raw in ipairs(fin_records_raw or {}) do
    local rec = M_finance.parse_transaction(raw)
    if rec then
      if     rec.kind == "PAYMENT"     then fin_payments[#fin_payments + 1] = rec
      elseif rec.kind == "PAYMENT_FEE" then fin_fees[#fin_fees + 1]         = rec
      elseif rec.kind == "PAYOUT"      then fin_payouts[#fin_payouts + 1]   = rec
      end
    end
  end

  -- Step 10: sort payouts ascending by timestamp for the temporal-inference rule
  -- (RESEARCH §4.2) — the SALE-03 promotion sweep walks this list to find the
  -- earliest PAYOUT whose timestamp >= a PAYMENT's timestamp.
  table.sort(fin_payouts, function(a, b) return a.timestamp_posix < b.timestamp_posix end)

  -- Helper: find earliest covering PAYOUT for a given PAYMENT timestamp.
  -- Pure local closure; never escapes RefreshAccount's scope.
  local function _find_covering_payout(payment_posix)
    for _, po in ipairs(fin_payouts) do
      if po.timestamp_posix >= payment_posix then return po end
    end
    return nil
  end

  -- Step 11: index Finance PAYMENT records by their originatingTransactionUuid
  -- (which equals the originating purchase's payments[].uuid per RESEARCH §3.2).
  local fin_payments_by_uuid = {}
  for _, fp in ipairs(fin_payments) do
    fin_payments_by_uuid[fp.originatingTransactionUuid] = fp
  end

  -- Step 12: map purchases -> sale / refund transactions.
  -- D-50: refunds use M_mapping.refund_to_transaction(p, opts) with
  --       opts.original_receipt set from the purchases_by_uuid lookup.
  -- D-37: non-EUR purchases return nil from M_mapping (silently skip).
  -- sale_to_purchase tracks the parent purchase per sale txn so the SALE-03
  -- promotion sweep below can resolve payments[].uuid -> Finance PAYMENT.
  local transactions = {}
  local sale_to_purchase = {}
  for _, p in ipairs(purchases or {}) do
    if type(p) == "table" then
      local txn
      if p.refund == true then
        local original_receipt = nil
        if type(p.refundsPurchaseUUID1) == "string" and #p.refundsPurchaseUUID1 > 0 then
          local original = purchases_by_uuid[p.refundsPurchaseUUID1]
          if original and original.purchaseNumber then
            original_receipt = original.purchaseNumber
          end
        end
        txn = M_mapping.refund_to_transaction(p, { original_receipt = original_receipt })
      else
        txn = M_mapping.purchase_to_transaction(p)
        if txn then sale_to_purchase[txn] = p end
      end
      if txn ~= nil then
        transactions[#transactions + 1] = txn
      end
    end
  end

  -- Step 13: D-56 / SALE-03 promotion sweep (RESEARCH §4.2 + §4.3).
  -- For each sale txn, walk parent purchase's payments[], look up matching
  -- Finance PAYMENT via payment.uuid -> fin_payments_by_uuid, find earliest
  -- covering PAYOUT, call M_mapping.promote_to_booked. Idempotent — same
  -- purchase + same finance fixture set always produces the same valueDate.
  -- transactionCode is NEVER mutated; MoneyMoney's dedup updates the row in place.
  for _, sale_txn in ipairs(transactions) do
    local purchase = sale_to_purchase[sale_txn]
    if purchase and type(purchase.payments) == "table" then
      for _, pmt in ipairs(purchase.payments) do
        if type(pmt) == "table" and type(pmt.uuid) == "string" then
          local fin_payment = fin_payments_by_uuid[pmt.uuid]
          if fin_payment then
            local covering = _find_covering_payout(fin_payment.timestamp_posix)
            if covering then
              -- BL-01: convert covering payout's UTC POSIX -> Berlin-local POSIX
              -- so sale.valueDate uses the SAME convention as sale.bookingDate
              -- (D-36) and matches payout_to_transaction's bookingDate (D-PAYOUT-03).
              -- covering.timestamp_posix is pure UTC seconds (M_finance.parse_transaction).
              local valueDate_local = M_mapping.to_berlin_local_time(covering.timestamp_posix)
              M_mapping.promote_to_booked(sale_txn, valueDate_local)
              break  -- one matching payment leg is enough; further legs would
                     -- only re-promote to the same (or later) valueDate.
            end
          end
        end
      end
    end
  end

  -- Step 14: D-49 / FEE-01 / FEE-03 / RESEARCH §3.5 (Option B): cluster fees
  -- by Berlin-local date. For each date, if ANY fee on that date is unlinked
  -- (no payments_by_uuid match), aggregate ALL fees for that date via
  -- fee_aggregate_to_transaction. Otherwise emit per-sale fee_to_transaction
  -- rows. This is the load-bearing simplification per CONTEXT D-49 + RESEARCH
  -- §3.5: per-refresh date clustering with no persistent state (D-59).
  --
  -- Yves-blocker D-49 Option A vs B is documented in 04-03-PLAN.md <objective>;
  -- if a later phase needs Option A (LocalStorage-persistent date set), replan
  -- via /gsd-plan-phase 4 --gaps to amend D-59.
  local fees_by_date = {}
  for _, fee in ipairs(fin_fees) do
    local date_iso = M_mapping.berlin_local_date(fee.timestamp_iso)
    if date_iso then
      if not fees_by_date[date_iso] then
        fees_by_date[date_iso] = { fees = {}, any_unlinked = false }
      end
      local bucket = fees_by_date[date_iso]
      bucket.fees[#bucket.fees + 1] = fee
      local originating = payments_by_uuid[fee.originatingTransactionUuid]
      if not originating then bucket.any_unlinked = true end
    end
  end

  for date_iso, bucket in pairs(fees_by_date) do
    if bucket.any_unlinked then
      M_log.warn("RefreshAccount: aggregating " .. tostring(#bucket.fees)
        .. " fees for date " .. date_iso
        .. " (at least one missing payments_by_uuid link; D-49 Option B per refresh)")
      local agg = M_mapping.fee_aggregate_to_transaction(bucket.fees, date_iso, #bucket.fees)
      if agg then transactions[#transactions + 1] = agg end
    else
      for _, fee in ipairs(bucket.fees) do
        local originating = payments_by_uuid[fee.originatingTransactionUuid]
        local fee_txn = M_mapping.fee_to_transaction(fee, originating)
        if fee_txn then transactions[#transactions + 1] = fee_txn end
      end
    end
  end

  -- Step 15: map payouts via payout_to_transaction.
  for _, po in ipairs(fin_payouts) do
    local po_txn = M_mapping.payout_to_transaction(po)
    if po_txn then transactions[#transactions + 1] = po_txn end
  end

  -- Step 16: return result with the Phase-4 three-field shape.
  -- balance / pendingBalance from Finance API state; fallback to account.balance
  -- when account_state.balance is nil (covers the R-4 non-EUR-liquid case).
  return {
    balance        = (account_state and account_state.balance) or (account and account.balance),
    pendingBalance = account_state and account_state.pendingBalance or nil,
    transactions   = transactions,
  }
end

function EndSession()
  M_log.info("EndSession called")
  M_http.shutdown()
  return nil
end
