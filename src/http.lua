-- src/http.lua
-- AUTH-02 / AUTH-05 / D-25 / Risk R-1 / Pitfall 1 ownership.
-- Provides: M_http.post_form, M_http.get_json, M_http.shutdown,
--           M_http._infer_status (plus private _get_connection, _form_encode,
--           _merge_headers).
-- The M_http table is predeclared in src/webbanking_header.lua.
-- NO require() of sibling modules (D-02: amalgamator resolves cross-module
-- refs at build time via the shared module-table globals).
--
-- Phase 5 (Plan 05-03): retry-with-backoff for 5xx (3 attempts, {1,2,4}s);
--   single-retry on 429 honoring Retry-After (integer-only, 60s cap, 30s default);
--   599 sentinel on 5xx exhaustion → M_errors maps to error.server_busy (Plan 05-02);
--   empty-body / nil-status preserved as Phase-2 ERR-05 path (error.network).
--   See ADR-0005 Invariants 2 + 3 + Carve-out 2.

-- Module-local Connection, reused across requests (D-25).
-- Created lazily on first call; released by shutdown() in EndSession.
local _conn = nil

-- Phase 5 (Plan 05-03) retry-with-backoff constants per ADR-0005 Invariants 2+3.
-- D-62: 5xx retry-with-backoff (3 attempts: 1 original + 2 retries; exponential base 2)
-- D-63: 429 single-retry honoring Retry-After (60s cap, 30s default)
local _MAX_ATTEMPTS           = 3
-- Sleep BEFORE attempt 2 (=1s), BEFORE attempt 3 (=2s); index 3 unused but kept for symmetry/audit.
local _BACKOFF_SECONDS        = { 1, 2, 4 }
local _RETRY_AFTER_CAP        = 60           -- D-63 upper bound on Retry-After honoring
local _RATE_LIMIT_DEFAULT     = 30           -- D-63 default when Retry-After absent / unparseable
local _SENTINEL_5XX_EXHAUSTED = 599          -- Phase-5-internal: M_errors maps to error.server_busy per Plan 05-02
-- 05-06 fix-batch (S-01 / WR-03): per-request wall-clock cap (seconds).
-- The shared attempt counter alone does not bound total wait time on a mixed
-- [429 Retry-After=60, empty, empty] sequence, which would otherwise consume
-- ~62s on a single endpoint and ~248s across the 4-endpoint RefreshAccount
-- pipeline — breaching MoneyMoney's per-call timeout (~30-60s per ADR-0003).
-- Before each _sleep_with_log we check that (elapsed + next_sleep) does not
-- exceed _WALL_CLOCK_CAP; if it would, we abort the loop and return the most
-- recent attempt's tuple so the caller sees a deterministic outcome.
local _WALL_CLOCK_CAP         = 60           -- Hard upper bound per _request_with_retry call

-- _get_connection() -> Connection
-- Returns the cached connection or creates one.
local function _get_connection()
  if _conn == nil then
    _conn = Connection()
    -- D-26 / SEC-02 reminder: the only hosts we ever pass to this connection
    -- are oauth.zettle.com / purchase.izettle.com / finance.izettle.com.
    -- No host strings are stored here; URLs arrive as function parameters.
  end
  return _conn
end

-- _form_encode(t) -> string
-- Pure-Lua x-www-form-urlencoded body builder.
-- Deterministic sorted-key ordering for reproducible SEC-03 assertions.
local function _form_encode(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = MM.urlencode(k) .. "=" .. MM.urlencode(t[k])
  end
  return table.concat(parts, "&")
end

-- _merge_headers(user_headers) -> table
-- Forces Accept: application/json unconditionally (Pitfall 1 / T-02-04-03).
-- Without this header MoneyMoney aborts the entire Lua chunk on any non-2xx
-- response, preventing D-24's error-routing logic from ever running.
-- NEVER concatenate the returned table into any log line (defense-in-depth;
-- T-02-04-02: Bearer values in Authorization headers must never reach logs).
local function _merge_headers(user_headers)
  local h = {}
  for k, v in pairs(user_headers or {}) do h[k] = v end
  h["Accept"] = "application/json"
  return h
end

-- _parse_retry_after(resp_headers) -> integer|nil
-- ADR-0005 Carve-out 2 + RESEARCH §2 + Pitfall §6:
--   Integer seconds only (HTTP-date silently degrades to default).
--   Negative values rejected (Pitfall §1 — "Retry-After: -5" must not become MM.sleep(-5)).
--   Capped at _RETRY_AFTER_CAP (60s) to stay within MM per-call timeout.
--   Checks BOTH "Retry-After" and "retry-after" casing (server middleware varies).
local function _parse_retry_after(resp_headers)
  if type(resp_headers) ~= "table" then return nil end
  local raw = resp_headers["Retry-After"] or resp_headers["retry-after"]
  if raw == nil then return nil end
  local n = tonumber(raw)
  -- NaN guard (n ~= n is true only for NaN); negative guard; non-numeric guard
  if type(n) ~= "number" or n ~= n or n < 0 then return nil end
  if n > _RETRY_AFTER_CAP then n = _RETRY_AFTER_CAP end
  return math.floor(n)
end

-- _sleep_with_log(seconds, url, attempt, status)
-- D-68: ONE INFO log line per retry attempt (Bearer-safe format — headers NEVER
-- concatenated; only url, attempt, status, after_ms appear).
-- Pitfall §10 defensive: pcall-wrap MM.sleep so a runtime error on a future
-- MoneyMoney version falls through to no-backoff continuation rather than
-- aborting RefreshAccount with a Lua error.
local function _sleep_with_log(seconds, url, attempt, status)
  M_log.info("HTTP retry: attempt=" .. attempt .. "/" .. _MAX_ATTEMPTS ..
             " status=" .. tostring(status) ..
             " url=" .. url ..
             " after_ms=" .. (seconds * 1000))
  -- pcall guard: MM.sleep is the documented primitive; if it ever errors,
  -- skip the sleep and continue to the next attempt (degraded behavior is
  -- better than aborting RefreshAccount per Pitfall §10).
  local ok, err = pcall(function()
    if type(MM) == "table" and type(MM.sleep) == "function" then
      MM.sleep(seconds)
    end
  end)
  if not ok then
    M_log.info("HTTP retry: MM.sleep error (degraded; continuing): " .. tostring(err))
  end
end

-- M_http._infer_status(parsed) -> integer
--
-- Risk R-1: MoneyMoney's Connection():request returns five values
-- (content, charset, mimeType, filename, headers) and does NOT include a
-- separate HTTP status code. This function derives a status-equivalent integer
-- from the decoded response body so M_errors.from_http_status can route errors.
--
-- Contract (in priority order):
--   parsed.error == "invalid_grant"   | "invalid_request"             -> 400
--   parsed.error == "invalid_client"  | "unauthorized_client"          -> 401
--   parsed.error == "rate_limit"                                       -> 429 (H-01)
--   parsed.error == "service_unavailable" | "temporarily_unavailable"  -> 503 (Phase-5 fix-batch S-02)
--   parsed.error == "server_error" | "internal_error" | "backend_error"-> 500 (Phase-5 fix-batch S-02)
--   parsed.error == "server_busy"                                      -> 599 (Phase-5 fix-batch S-02)
--   parsed.error non-nil (unknown)                                     -> 400 (conservative; Pitfall 5)
--   otherwise                                                          -> 200
--
-- 05-06 fix-batch (S-02 / WR-01 / S-05): the 5xx body-shape branch makes the
-- retry loop's 5xx branch + 599 sentinel emission live. Any 5xx-classified
-- response triggers the retry-with-backoff path; exhaustion emits the 599
-- sentinel which M_errors.from_http_status routes to error.server_busy.
-- S-05 (sentinel collision) is mitigated: an upstream `{"error":"server_busy"}`
-- body classifies as 599 directly, which also routes to error.server_busy —
-- both paths converge on the same German user-facing string with no semantic
-- ambiguity. See ADR-0005 §Implementation Pin "599 sentinel emission contract".
function M_http._infer_status(parsed)
  if parsed.error then
    if parsed.error == "invalid_grant" or parsed.error == "invalid_request" then
      return 400
    end
    if parsed.error == "invalid_client" or parsed.error == "unauthorized_client" then
      return 401
    end
    if parsed.error == "rate_limit" then
      return 429
    end
    if parsed.error == "service_unavailable" or parsed.error == "temporarily_unavailable" then
      return 503
    end
    if parsed.error == "server_error" or parsed.error == "internal_error"
       or parsed.error == "backend_error" then
      return 500
    end
    if parsed.error == "server_busy" then
      return _SENTINEL_5XX_EXHAUSTED  -- 599 — converges with retry-exhaust sentinel (S-05 mitigation)
    end
    return 400  -- conservative: unknown error names treated as 400 (Pitfall 5)
  end
  return 200
end

-- _request_with_retry(method, url, body, contentType, h)
--   -> (parsed_table|nil, status:integer|nil, raw_body:string)
--
-- Shared retry loop body for get_json + post_form. Centralises the 5xx-retry
-- (D-62, ADR-0005 Invariant 2), 429-honoring (D-63, Invariant 3), and
-- empty-body / nil-status branch (ERR-05, Invariant 5) so both transport
-- verbs share the SAME contract.
--
-- Retry decision matrix (per attempt):
--   empty body          → retry up to MAX (treat as 5xx-equivalent per RESEARCH §4.b);
--                         exhausted → return (nil, nil, raw) so M_errors maps to error.network
--   429 (from _infer_status)  → single retry honoring Retry-After, then return (parsed, 429, raw)
--                         caller maps 429 → error.rate_limit
--   5xx (from _infer_status)  → retry up to MAX; exhausted → return (parsed, 599, raw)
--                         caller maps 599 → error.server_busy via Plan 05-02 dispatch
--   200 or other        → return immediately; no sleep, no log
--
-- Invariants:
--   * NO pcall around conn:request (Pitfall §10 / ADR-0003 Q8 — pcall does NOT
--     catch SSL handshake errors; MM aborts the chunk regardless).
--   * pcall ONLY around JSON parse (Phase-2 invariant).
--   * Iterative loop (Pitfall §2 — recursive retry blows 200-frame stack).
local function _request_with_retry(method, url, body, contentType, h)
  local conn = _get_connection()
  local raw, parsed, status, resp_headers
  local last_attempt_was_5xx = false
  -- 05-06 fix-batch (S-01 / WR-03): track elapsed wall-clock time across the
  -- loop so the next sleep can be skipped (and the loop aborted with the most
  -- recent tuple) when the cap would be breached. os.time() is sufficient
  -- here: all sleeps are documented integer-seconds (ADR-0005 §Sleep mech).
  local _start_time = os.time()
  -- _budget_would_breach(seconds) -> bool
  -- True iff adding `seconds` of sleep would push total elapsed wall-clock
  -- beyond _WALL_CLOCK_CAP. Uses a captured start_time so retries spread
  -- across mixed 429+5xx+empty sequences share the same bound.
  local function _budget_would_breach(seconds)
    return (os.time() - _start_time) + seconds > _WALL_CLOCK_CAP
  end
  for attempt = 1, _MAX_ATTEMPTS do
    -- 5-tuple capture per Risk R-1 / ADR-0003 Q8 (NO pcall around conn:request).
    local _charset, _mime, _filename -- luacheck: ignore 211 _charset _mime _filename
    raw, _charset, _mime, _filename, resp_headers = conn:request(method, url, body, contentType, h)
    raw = raw or ""

    if #raw == 0 then
      -- Empty body: 5xx-without-body OR DNS/connect/timeout (RESEARCH §4.b).
      last_attempt_was_5xx = false  -- nil-status path, not 599 sentinel
      if attempt < _MAX_ATTEMPTS then
        local next_sleep = _BACKOFF_SECONDS[attempt]
        if _budget_would_breach(next_sleep) then
          -- S-01 / WR-03: wall-clock abort. Return the most recent tuple
          -- (empty body → ERR-05) so the caller sees a deterministic outcome
          -- rather than silently retrying past MM's per-call timeout.
          M_log.info("HTTP retry: wall-clock cap reached (" .. _WALL_CLOCK_CAP ..
                     "s); aborting before next sleep url=" .. url)
          return nil, nil, raw
        end
        _sleep_with_log(next_sleep, url, attempt, "nil")
      else
        -- Final attempt: surface (nil, nil, raw) — ERR-05 inheritance from Phase 2.
        return nil, nil, raw
      end
    else
      -- Parse JSON inside pcall (Phase-2 invariant: pcall ONLY around JSON).
      local ok, p = pcall(function()
        return JSON(raw):dictionary()
      end)
      if not ok or type(p) ~= "table" then
        -- Malformed JSON: surface as nil-status (treats as ERR-05); no retry.
        return nil, nil, raw
      end
      parsed = p
      status = M_http._infer_status(parsed)

      if status == 429 then
        if attempt == 1 then
          -- D-63: single retry honoring Retry-After.
          local wait = _parse_retry_after(resp_headers) or _RATE_LIMIT_DEFAULT
          if _budget_would_breach(wait) then
            -- S-01 / WR-03: cap aborts the 429 retry; surface the 429 now so
            -- the caller maps to error.rate_limit instead of stalling.
            M_log.info("HTTP retry: wall-clock cap reached (" .. _WALL_CLOCK_CAP ..
                       "s); skipping 429 Retry-After sleep url=" .. url)
            return parsed, status, raw
          end
          _sleep_with_log(wait, url, attempt, status)
          -- continue loop (attempt becomes 2)
        else
          -- D-63: single-retry budget exhausted; return 429 so caller maps to error.rate_limit.
          return parsed, status, raw
        end
      elseif status >= 500 and status <= 599 then
        last_attempt_was_5xx = true
        if attempt < _MAX_ATTEMPTS then
          local next_sleep = _BACKOFF_SECONDS[attempt]
          if _budget_would_breach(next_sleep) then
            -- S-01 / WR-03: cap aborts the 5xx retry; surface the 599 sentinel
            -- now (5xx-classified tuple) so the caller maps to error.server_busy.
            M_log.info("HTTP retry: wall-clock cap reached (" .. _WALL_CLOCK_CAP ..
                       "s); emitting 599 sentinel early url=" .. url)
            return parsed, _SENTINEL_5XX_EXHAUSTED, raw
          end
          _sleep_with_log(next_sleep, url, attempt, status)
          -- continue loop
        else
          -- D-62: 3-attempt budget exhausted; emit the 599 sentinel.
          return parsed, _SENTINEL_5XX_EXHAUSTED, raw
        end
      else
        -- 200 or other non-retry-able status → return immediately.
        return parsed, status, raw
      end
    end
  end
  -- Loop exhausted without returning (defensive — shouldn't reach here).
  if last_attempt_was_5xx then
    return parsed, _SENTINEL_5XX_EXHAUSTED, raw or ""
  end
  return parsed, status, raw or ""
end

-- M_http.post_form(url, body_table, headers)
--   -> (decoded_table|nil, status:integer|nil, raw_body:string)
--
-- Sends an x-www-form-urlencoded POST. Accept: application/json is always set
-- (see _merge_headers). Request and response bodies are passed through
-- M_log.redact before any DEBUG log (D-25 / T-02-04-01).
-- Phase 5 (Plan 05-03): wraps request in retry-with-backoff per _request_with_retry.
-- POST is idempotent for OAuth assertion-grant (RESEARCH §10.b: same JWT
-- assertion within TTL yields the same access_token per RFC 7521 §4.1).
function M_http.post_form(url, body_table, headers)
  local body = _form_encode(body_table)
  local h = _merge_headers(headers)
  M_log.debug("POST " .. url .. " body=" .. M_log.redact(body))
  local parsed, status, raw =
    _request_with_retry("POST", url, body, "application/x-www-form-urlencoded", h)
  M_log.debug("POST " .. url .. " response=" .. M_log.redact(raw))
  return parsed, status, raw
end

-- M_http.get_json(url, headers)
--   -> (decoded_table|nil, status:integer|nil, raw_body:string)
--
-- Sends a GET request. Accept: application/json always set.
-- The DEBUG request log is JUST "GET " .. url -- headers are NEVER concatenated
-- into any log line (T-02-04-02: defense-in-depth against Bearer leakage).
-- Phase 5 (Plan 05-03): wraps request in retry-with-backoff per _request_with_retry.
function M_http.get_json(url, headers)
  local h = _merge_headers(headers)
  M_log.debug("GET " .. url)  -- headers intentionally absent from log (Bearer safety)
  local parsed, status, raw = _request_with_retry("GET", url, nil, nil, h)
  M_log.debug("GET " .. url .. " response=" .. M_log.redact(raw))
  return parsed, status, raw
end

-- M_http.shutdown()
-- Closes the module-local Connection (D-25 EndSession contract).
-- Idempotent: safe to call with _conn == nil or if close is absent.
function M_http.shutdown()
  if _conn and _conn.close then _conn:close() end
  _conn = nil
end
