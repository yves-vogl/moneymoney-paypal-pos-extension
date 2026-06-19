-- src/auth.lua
-- Ownership: AUTH-02 (jwt-bearer grant body), AUTH-05 (no key leakage),
--            D-22 (extract client_id from assertion payload), SEC-03 (key safe).
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
