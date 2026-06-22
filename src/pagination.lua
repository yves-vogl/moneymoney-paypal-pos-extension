-- src/pagination.lua
-- Ownership: SALE-06 / D-43.
-- Provides: M_pagination.iterate(fetch_page_fn, initial_params)
--   Returns (all_purchases_table, nil) on success; (nil, error_string) on failure.
-- The M_pagination table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02: cross-module access via global M_* tables).
--
-- Transport is owned by the injected fetch_page_fn — this module makes ZERO
-- network calls. Plan 03-05 passes M_purchases.fetch as the callback.

-- Module-level constant: safety guard against infinite loops on malformed responses.
-- 50 pages x 200 records per page = 10,000 purchases — well above any 90-day window
-- for typical German merchants (D-33 clamps to 90 days, RESEARCH §1 "Typical page count").
local MAX_PAGES = 50

-- M_pagination.iterate(fetch_page_fn, initial_params)
--
-- fetch_page_fn(params) must return (page_table|nil, status_integer|nil, raw_string)
--   page_table: decoded JSON with at minimum a "purchases" array field
--   status:     HTTP status integer, or nil on network failure
--   raw:        raw response body string (forwarded to M_errors.from_http_status)
--
-- initial_params: table of query parameters for the first page (e.g. {startDate=..., limit=200})
--   The caller's table is NEVER mutated (T-03-W3a-02 / D-02 defence): a local copy is made.
--
-- Termination (RESEARCH §2a, both conditions, Anti-Pattern #1):
--   1. page.purchases is empty (authoritative terminal per purchase.adoc)
--   2. page.lastPurchaseHash is absent or empty (belt-and-suspenders)
-- Either condition independently terminates the loop.
M_pagination.iterate = function(fetch_page_fn, initial_params)
  local all_purchases = {}

  -- Copy initial_params so the caller's table is never mutated (T-03-W3a-02).
  local params = {}
  for k, v in pairs(initial_params) do
    params[k] = v
  end

  local page_count = 0

  repeat
    page_count = page_count + 1

    -- MAX_PAGES guard (T-03-W3a-01): prevents infinite loops on adversarial or
    -- malformed server responses. Log a German-safe WARN line (SEC-03: no PII/Bearer).
    if page_count > MAX_PAGES then
      M_log.warn("M_pagination.iterate: MAX_PAGES exceeded, aborting")
      return nil, M_i18n.t("error.network", "max_pages")
    end

    -- Call the injected page-fetcher (D-43: transport owned by fetch_page_fn).
    local page, status, raw = fetch_page_fn(params)

    -- Plan 05-04 / ERR-04 / ADR-0005 Invariant 4 / RESEARCH §Pattern-2:
    -- post-mint 401 from a resource endpoint means the bearer was VALID at
    -- mint time but invalidated mid-session (revoked / scope changed /
    -- merchant regenerated key in another tab). Surface immediately as
    -- error.token_revoked so the user re-enters the API key in MoneyMoney's
    -- account dialog. Justified exception to D-43 routing (intercept BEFORE
    -- M_errors.from_http_status would map 401 -> LoginFailed via D-24 case 3):
    -- the 401 -> token-revoked mapping is semantic (we know the mint succeeded
    -- because cached_token returned a bearer), not status-code-class generic.
    -- The exception applies ONLY to resource-endpoint iterators; token-mint
    -- (M_auth.exchange_assertion) never paginates and so never hits this path.
    if status == 401 then return nil, M_i18n.t("error.token_revoked") end

    -- Route HTTP errors through Phase-2's error mapper (D-43 / RESEARCH §1 Status table).
    local err = M_errors.from_http_status(status, raw)
    if err then return nil, err end

    -- Page-shape guard: protect against nil responses and non-table purchases fields.
    if type(page) ~= "table" or type(page.purchases) ~= "table" then
      return nil, M_i18n.t("error.network", "bad_page")
    end

    -- Accumulate this page's purchases into the result list.
    for _, p in ipairs(page.purchases) do
      all_purchases[#all_purchases + 1] = p
    end

    -- Dual-termination check (RESEARCH §2a, Anti-Pattern #1 defence):
    --   has_more is true ONLY when BOTH conditions hold:
    --   - this page returned at least one purchase (empty array = definitive terminal)
    --   - the response carries a non-empty lastPurchaseHash cursor
    local has_more = (#page.purchases > 0)
                  and (type(page.lastPurchaseHash) == "string")
                  and (page.lastPurchaseHash ~= "")

    if has_more then
      params.lastPurchaseHash = page.lastPurchaseHash
    else
      -- Explicitly clear the cursor so the until condition below terminates.
      params.lastPurchaseHash = nil
    end

  -- until: loop continues only while a valid (non-empty) cursor is present.
  -- Mirrors the has_more logic above: no cursor -> terminate.
  until not (type(params.lastPurchaseHash) == "string" and params.lastPurchaseHash ~= "")

  return all_purchases, nil
end

-- M_pagination.offset_iterate(fetch_page_fn, initial_params)
--
-- Sibling iterator for the Finance API (Plan 04-02 / D-48 / RESEARCH §1.6).
-- The Phase-3 cursor iterator above is intentionally NOT modified.
--
-- fetch_page_fn(params) must return (page_table|nil, status_integer|nil, raw_string)
--   page_table: decoded JSON with a "data" array field
--   status:     HTTP status integer, or nil on network failure
--   raw:        raw response body string (forwarded to M_errors.from_http_status)
--
-- initial_params: table of query parameters for the first page (e.g. {offset=0, limit=1000}).
--   The caller's table is NEVER mutated — a local copy is made.
--   Defensive defaults: missing offset -> 0, missing limit -> 1000 (RESEARCH §1.3).
--
-- Termination (RESEARCH §1.6 — "Repeat ... until the response is empty or it
-- contains fewer transactions than the limit"):
--   loop ends when #page.data == 0 OR #page.data < params.limit.
--
-- MAX_PAGES guard (T-03-W3a-01 reused): same 50-page cap as the cursor iterator.
-- Errors route through M_errors.from_http_status (D-43) — byte-identical to iterate.
M_pagination.offset_iterate = function(fetch_page_fn, initial_params)
  local all_records = {}

  -- Copy initial_params so the caller's table is never mutated (D-02 defence).
  local params = {}
  for k, v in pairs(initial_params or {}) do
    params[k] = v
  end
  -- Defensive defaults
  params.offset = params.offset or 0
  params.limit  = params.limit  or 1000

  local page_count = 0

  repeat
    page_count = page_count + 1

    if page_count > MAX_PAGES then
      M_log.warn("M_pagination.offset_iterate: MAX_PAGES exceeded, aborting")
      return nil, M_i18n.t("error.network", "max_pages")
    end

    local page, status, raw = fetch_page_fn(params)

    -- Plan 05-04 / ERR-04 / ADR-0005 Invariant 4 / RESEARCH §Pattern-2:
    -- mirror of the post-mint 401-direct-check from M_pagination.iterate.
    -- Both M_finance.fetch and M_finance.fetch_all flow through this
    -- offset iterator, so the single check covers both call sites. See
    -- M_pagination.iterate above for the full justified-exception rationale.
    if status == 401 then return nil, M_i18n.t("error.token_revoked") end

    local err = M_errors.from_http_status(status, raw)
    if err then return nil, err end

    if type(page) ~= "table" or type(page.data) ~= "table" then
      return nil, M_i18n.t("error.network", "bad_page")
    end

    for _, r in ipairs(page.data) do
      all_records[#all_records + 1] = r
    end

    local got = #page.data
    params.offset = params.offset + params.limit

  -- Terminate on empty page (got=0) OR short page (got < limit).
  until got < params.limit

  return all_records, nil
end
