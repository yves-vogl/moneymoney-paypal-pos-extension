-- src/auth.lua
-- Ownership: AUTH-02 (jwt-bearer grant body), AUTH-04 (cached_token expiry guard),
--            AUTH-05 (no key leakage), AUTH-06 (flat-fallback cache),
--            D-21 (two-call probe), D-22 (extract client_id from assertion payload),
--            D-23c (nested + flat double-write), D-23d (60s pre-expiry guard),
--            D-25 (transport via M_http), SEC-03 (key safe), ACCT-04 (multi-merchant).
-- The M_auth table is predeclared in src/webbanking_header.lua.
-- All functions in this file run inside the do...end block that tools/build.lua
-- wraps around each non-header/non-entry module (see tools/build.lua L164).

-- _b64url_decode(s) -> string|nil (private, scoped to this do...end block)
-- RFC 7515 Appendix C: translate base64url alphabet to standard base64,
-- restore padding to mod-4 boundary, then decode via MM.base64decode.
-- Returns nil when s is not a string.
local function _b64url_decode(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("-", "+"):gsub("_", "/")
  local pad = (4 - (#s % 4)) % 4
  s = s .. string.rep("=", pad)
  return MM.base64decode(s)
end

-- M_auth._decode_jwt_payload(jwt) -> table|nil
-- Split jwt on '.', verify three segments, base64url-decode the middle segment,
-- JSON-parse inside pcall (input is attacker-controlled per threat T-02-03-01).
-- Returns the decoded payload table, or nil on any structural failure.
-- Never emits log lines; never leaks JWT segments in return values.
function M_auth._decode_jwt_payload(jwt)
  if type(jwt) ~= "string" or #jwt == 0 then return nil end
  local h, p, sig = jwt:match("^([^.]+)%.([^.]+)%.([^.]+)$")
  if not h or not p or not sig then return nil end
  local raw = _b64url_decode(p)
  if not raw or #raw == 0 then return nil end
  -- pcall is mandatory: the payload is attacker-controlled; JSON() will call
  -- Lua error() on malformed input, which would otherwise abort the chunk.
  local ok, parsed = pcall(function()
    return JSON(raw):dictionary()
  end)
  if not ok or type(parsed) ~= "table" then return nil end
  return parsed
end

-- M_auth._extract_client_id(jwt) -> string|nil
-- Read the client identity from the JWT's own public payload (D-22).
-- Priority order: aud (string) -> aud[1] (array) -> client_id (string) -> nil.
-- Runs synchronously, zero network calls; a malformed key returns nil so
-- InitializeSession2 (Wave 3) can fail fast with error.invalid_grant.
function M_auth._extract_client_id(jwt)
  local payload = M_auth._decode_jwt_payload(jwt)
  if not payload then return nil end
  local aud = payload.aud
  if type(aud) == "string" and #aud > 0 then return aud end
  if type(aud) == "table" and type(aud[1]) == "string" and #aud[1] > 0 then
    return aud[1]
  end
  local cid = payload.client_id
  if type(cid) == "string" and #cid > 0 then return cid end
  return nil
end

-- M_auth.exchange_assertion(api_key, client_id)
--   -> (token_table|nil, status:integer|nil, raw_body:string)
--
-- POSTs the JWT-bearer assertion grant to oauth.zettle.com/token (AUTH-02 / D-25).
-- The api_key (assertion) is the user-supplied JWT API key; it is forwarded as
-- the assertion form field and NEVER persisted — only the returned access_token
-- enters the cache (AUTH-05 / SEC-03 / T-02-05-01).
-- Transport is fully delegated to M_http.post_form; no log lines emitted here.
function M_auth.exchange_assertion(api_key, client_id)
  local body = {
    grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
    client_id  = client_id,
    assertion  = api_key,
  }
  return M_http.post_form("https://oauth.zettle.com/token", body, {})
end

-- M_auth.fetch_profile(access_token)
--   -> (profile_table|nil, status:integer|nil, raw_body:string)
--
-- GETs oauth.zettle.com/users/self with Authorization header (D-21 leg 2).
-- Returns {uuid, organizationUuid, publicName, ...} on success.
-- Transport delegated to M_http.get_json; Authorization header never logged
-- (T-02-04-02 / T-02-05-02 — M_http.get_json structurally omits headers from logs).
function M_auth.fetch_profile(access_token)
  return M_http.get_json(
    "https://oauth.zettle.com/users/self",
    { Authorization = "Bearer " .. access_token }
  )
end

-- _cache_write(orgUuid, entry) — private
-- D-23c double-write: always writes to BOTH the nested LocalStorage.zettle[orgUuid]
-- table AND the flat LocalStorage["zettle:"..orgUuid] JSON-string path.
-- The flat path ensures cache survival across MoneyMoney session restarts (AUTH-06 /
-- T-02-05-05) when Q5 prevents the nested table from persisting.
-- ACCT-04: keys by orgUuid; multiple merchants coexist without collision.
local function _cache_write(orgUuid, entry)
  LocalStorage.zettle = LocalStorage.zettle or {}
  LocalStorage.zettle[orgUuid] = entry
  LocalStorage["zettle:" .. orgUuid] = JSON():set(entry):json()
end

-- _cache_read(orgUuid) -> entry_table|nil — private
-- D-23c read priority: nested first; flat-string fallback on miss.
-- pcall-wraps the JSON parse of the flat string (T-02-05-05: flat value may be
-- corrupted or absent; we must not abort the chunk on parse failure).
local function _cache_read(orgUuid)
  -- 1. Nested path (fast path; available in-session)
  if LocalStorage.zettle and LocalStorage.zettle[orgUuid] ~= nil then
    return LocalStorage.zettle[orgUuid]
  end
  -- 2. Flat-string fallback (cross-restart persistence per D-23c / AUTH-06)
  local raw = LocalStorage["zettle:" .. orgUuid]
  if type(raw) == "string" and #raw > 0 then
    local ok, parsed = pcall(function()
      return JSON(raw):dictionary()
    end)
    if ok and type(parsed) == "table" then
      return parsed
    end
  end
  return nil
end

-- M_auth.persist_session(token_table, profile, client_id)
-- Assembles and writes the D-23c cache entry for one merchant session.
-- Cache entry shape (strings + integers only — no function values):
--   { access_token, obtained_at, expires_at, client_id, uuid, publicName }
-- The api_key/assertion is STRUCTURALLY ABSENT from this entry (AUTH-05 / SEC-03 /
-- T-02-05-01). Only the Zettle-issued access_token lives in LocalStorage.
-- publicName may be nil if /users/self did not return it; ListAccounts handles fallback.
function M_auth.persist_session(token_table, profile, client_id)
  local now = os.time()
  local entry = {
    access_token = token_table.access_token,
    obtained_at  = now,
    expires_at   = now + (tonumber(token_table.expires_in) or 7200),
    client_id    = client_id,
    uuid         = profile.uuid,
    publicName   = profile.publicName,
  }
  _cache_write(profile.organizationUuid, entry)
  return nil
end

-- M_auth.cached_token(orgUuid) -> string|nil
-- Returns the cached access_token when fresh, nil otherwise (D-23d).
-- Pre-expiry guard: returns nil when now >= expires_at - 60, giving caller
-- 60 seconds to complete in-flight requests before the token actually expires
-- (T-02-05-04). Emits one info log line on expiry for forensic tracing
-- (only orgUuid prefix, never the token — T-02-05-02).
function M_auth.cached_token(orgUuid)
  local entry = _cache_read(orgUuid)
  if not entry or not entry.access_token then return nil end
  local now = os.time()
  if now >= (entry.expires_at or 0) - 60 then
    M_log.info("cached_token: expired for org=" .. tostring(orgUuid):sub(1, 8))
    return nil
  end
  return entry.access_token
end
