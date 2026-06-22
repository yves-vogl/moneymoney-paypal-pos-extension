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

  -- 1. JWT-shaped tokens: three base64url segments each at least 4 chars.
  --    Pattern requires base64url charset ([%w%-_]) only in the first two segments
  --    so that hostnames like "oauth.zettle.com" (which contain dots in positions
  --    that would also match a looser pattern) are not redacted.
  --    A real JWT looks like: eyJhbGc....eyJzdWI....signature
  --    The first two parts are base64url-only; the third may contain dots (padding
  --    is stripped in JWTs but we keep dots in the char class for safety).
  s = s:gsub(
    "[%w%-_][%w%-_][%w%-_][%w%-_]+%.[%w%-_][%w%-_][%w%-_][%w%-_]+%.[%w%-_.][%w%-_.][%w%-_.][%w%-_.]+",
    "<redacted>"
  )

  -- 2. Bearer header values — %S+ matches any non-whitespace run, covering
  --    standard base64 (+, /) and padding (=) chars that the old [%w%-_.]+ class
  --    missed.  Opaque tokens like "abc+def/ghi=" are now fully redacted.
  s = s:gsub("Bearer%s+%S+", "Bearer <redacted>")

  -- 3. assertion= in OAuth form-encoded bodies
  s = s:gsub("assertion=[^%s&]+", "assertion=<redacted>")

  -- 4a. access_token in JSON key:value form ("access_token":"VALUE").
  --     Applied before the form-encoded rule so both forms are caught.
  --     Handles optional whitespace around the colon per JSON spec (S-04).
  s = s:gsub('"access_token"%s*:%s*"[^"]+"', '"access_token":"<redacted>"')

  -- 4b. access_token= in form-encoded bodies or query strings
  s = s:gsub("access_token=[^%s&]+", "access_token=<redacted>")

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
