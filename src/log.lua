-- src/log.lua
-- SEC-01: All log output passes through M_log.redact() before print().
-- SEC-04: Reads top-level DEBUG flag (declared in webbanking_header.lua).
-- Ownership: SEC-01 (redaction), SEC-04 (debug gate).

-- Level table (private to this do...end block)
local _LEVEL = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

-- _redact(s): apply redaction passes and return the sanitised string.
-- Over-redacts by design — better to redact too much than to leak credentials.
local function _redact(s)
  s = tostring(s)

  -- 1. JWT-shaped tokens: three dot-separated segments. The first two segments
  --    are base64url ([%w%-_]) — strict so hostnames like "oauth.zettle.com"
  --    do not match. The third segment (the signature) additionally admits
  --    '+' and '=' per G-03 because JWTs in the wild are sometimes emitted
  --    with standard-base64 chars instead of strict url-safe encoding. We
  --    deliberately do NOT extend the third segment to include '/' even
  --    though it is in the standard-base64 alphabet — otherwise URLs like
  --    'finance.izettle.com/v2/accounts/...' would match the pattern (3
  --    dot-separated word-like runs followed by a '/'-rich tail) and the
  --    redactor would clobber legitimate log lines. Each segment is at
  --    least 4 characters.
  s = s:gsub(
    "[%w%-_][%w%-_][%w%-_][%w%-_]+%.[%w%-_][%w%-_][%w%-_][%w%-_]+%.[%w%-_.+=][%w%-_.+=][%w%-_.+=][%w%-_.+=]+",
    "<redacted>"
  )

  -- 2. Bearer header values — %S+ matches any non-whitespace run, covering
  --    standard base64 (+, /) and padding (=) chars. Case-insensitive on
  --    the scheme keyword ('bearer' / 'BEARER' / 'Bearer') per G-03: PayPal
  --    docs sample lowercase 'bearer' in some headers.
  s = s:gsub("[Bb][Ee][Aa][Rr][Ee][Rr]%s+%S+", "Bearer <redacted>")

  -- 3a. assertion= in OAuth form-encoded bodies
  s = s:gsub("assertion=[^%s&]+", "assertion=<redacted>")

  -- 3b. assertion in JSON key:value form ("assertion":"VALUE").
  --     Optional whitespace around the colon per JSON spec.
  s = s:gsub('"assertion"%s*:%s*"[^"]+"', '"assertion":"<redacted>"')

  -- 4a. access_token in JSON key:value form ("access_token":"VALUE").
  --     Applied before the form-encoded rule so both forms are caught.
  --     Handles optional whitespace around the colon per JSON spec (S-04).
  s = s:gsub('"access_token"%s*:%s*"[^"]+"', '"access_token":"<redacted>"')

  -- 4b. access_token= in form-encoded bodies or query strings
  s = s:gsub("access_token=[^%s&]+", "access_token=<redacted>")

  -- 5. Additional OAuth/OpenID token JSON keys per G-03 — refresh_token,
  --    id_token, client_secret. The Zettle OAuth flow does not currently use
  --    refresh_token or id_token (per ADR-0006 it is JWT-bearer only), but
  --    redacting them defensively guards against future API changes and
  --    against a misconfigured key surfacing such fields in a response body.
  s = s:gsub('"refresh_token"%s*:%s*"[^"]+"', '"refresh_token":"<redacted>"')
  s = s:gsub('"id_token"%s*:%s*"[^"]+"',      '"id_token":"<redacted>"')
  s = s:gsub('"client_secret"%s*:%s*"[^"]+"', '"client_secret":"<redacted>"')

  return s
end

-- Public redact wrapper (accepts non-string inputs defensively)
M_log.redact = function(s)
  return _redact(tostring(s))
end

-- _emit: format and print a log line if the level is active.
local function _emit(name, ...)
  local level_num = _LEVEL[name] or _LEVEL.INFO
  local threshold = DEBUG and _LEVEL.DEBUG or _LEVEL.INFO
  if level_num < threshold then return end

  local parts = {}
  local n = select("#", ...)
  for i = 1, n do
    parts[i] = _redact(tostring(select(i, ...)))
  end
  print("[paypal-pos][" .. name .. "] " .. table.concat(parts, " ")) -- D-79-allowed: M_log emission point
end

M_log.debug = function(...) _emit("DEBUG", ...) end
M_log.info  = function(...) _emit("INFO",  ...) end
M_log.warn  = function(...) _emit("WARN",  ...) end
M_log.error = function(...) _emit("ERROR", ...) end
