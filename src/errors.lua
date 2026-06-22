-- src/errors.lua
-- Ownership: AUTH-03 (synchronous fail surface), SEC-03 (body redaction invariant), D-24.
-- Implements the six-case HTTP-status-to-error mapping defined in D-24.
-- Phase 5 will extend this module additively (new status codes / retry hints)
-- without changing the public signature: from_http_status(status, body) -> string|nil.
--
-- Phase 5 (Plan 05-02): added 599 sentinel branch for retry-exhausted 5xx
-- per ADR-0005 Invariant 2. The 401-after-mint translation to the
-- session-lost surface lives at the resource-endpoint caller layer
-- (src/purchases.lua + src/finance.lua, Plan 05-04) — NOT in this dispatch —
-- because from_http_status cannot distinguish "401 from token mint"
-- (LoginFailed) vs "401 from resource call after successful mint"
-- without additional context per ADR-0005 Invariant 4 + RESEARCH §Pattern-2
-- collapse. The corresponding i18n key is intentionally NOT referenced here.

-- M_errors.from_http_status(status, body)
--   status : integer|nil  — HTTP status code returned by Connection:request, or nil on timeout/network error
--   body   : string?      — raw response body (accepted for Phase-5 forward-compat; NEVER referenced below)
--   returns: string|nil   — German error string for MoneyMoney UI, or nil (no error, 2xx success)
--
-- SEC-03: `body` is intentionally unused inside this function body. All returned
-- strings are built exclusively from M_i18n.t templates, so no attacker-controlled
-- response body content can surface in user-visible error messages.
M_errors.from_http_status = function(status, body) -- luacheck: ignore body
  -- D-24 case 1: nil status — network failure or timeout
  if status == nil then
    return M_i18n.t("error.network", "—")
  end

  -- D-24 case 2: 2xx — success, caller handles the body; no error
  if status >= 200 and status <= 299 then
    return nil
  end

  -- D-24 case 3: 400/401/403 — auth rejection → synchronous MoneyMoney login failure
  if status == 400 or status == 401 or status == 403 then
    return LoginFailed
  end

  -- D-24 case 4: 429 — rate limit; Phase-5 retry scheduler will inspect this
  if status == 429 then
    return M_i18n.t("error.rate_limit")
  end

  -- D-24 case 5 + Phase-5 D-62 / ADR-0005 Invariant 2: 5xx server errors.
  -- The integer 599 is a Phase-5-internal SENTINEL set by M_http.get_json /
  -- post_form when 5xx retry attempts exhaust (Plan 05-03). Callers route
  -- to M_i18n.t("error.server_busy") so users see a distinct "server unavailable"
  -- message vs. a generic "network error <status>". Real 500-598 codes from
  -- body-shape inference (e.g. {"error":"server_error"} → 500) still route
  -- through the generic D-24 case 5 message preserving backward compat.
  if status == 599 then
    return M_i18n.t("error.server_busy")
  end
  if status >= 500 and status <= 598 then
    return M_i18n.t("error.network", tostring(status))
  end

  -- D-24 case 6: catch-all — unrecognised status code treated as network error
  return M_i18n.t("error.network", tostring(status))
end
