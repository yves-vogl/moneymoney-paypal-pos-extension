-- spec/helpers/mm_mocks.lua
-- Mock surface for MoneyMoney built-in globals so busted specs can run
-- outside MoneyMoney's sandboxed Lua 5.4 runtime.
--
-- Usage:
--   local Mocks = require("spec.helpers.mm_mocks")
--   before_each(function() Mocks.setup() end)
--   after_each(function() Mocks.teardown() end)
--   Mocks.push_response({ content = '{"ok":true}' })

-- luacheck: globals Connection JSON HTML PDF MM LocalStorage WebBanking
-- luacheck: globals ProtocolWebBanking ProtocolFinTS LoginFailed
-- luacheck: globals AccountTypeGiro AccountTypeSavings AccountTypeFixedTermDeposit
-- luacheck: globals AccountTypeLoan AccountTypeCreditCard AccountTypePortfolio
-- luacheck: globals AccountTypeOther
-- luacheck: globals _WebBanking_received
-- Wave-2 request-introspection field: Mocks._last_request captures the most
-- recent {method, url, body, contentType, headers} passed to conn:request.
-- Risk R-1 contract: FOR SPEC ASSERTIONS ONLY — production code MUST NOT read it.

local dkjson = require("dkjson")

local Mocks = {}

-- -------------------------------------------------------------------------
-- Pure-Lua RFC 4648 standard-base64 decoder (used by MM.base64decode mock).
-- Accepts the standard alphabet [A-Za-z0-9+/] with optional '=' padding.
-- Returns the decoded byte string; returns "" for empty or nil input.
-- NOTE: MM.base64 (encode) stays as an identity stub — Phase 2 production
-- code never encodes; SEC-03 specs use hardcoded base64 strings directly.
-- -------------------------------------------------------------------------
local _b64_decode_map = {}
do
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, #alphabet do
    _b64_decode_map[alphabet:sub(i, i)] = i - 1
  end
end

local function _base64decode(s)
  if s == nil or s == "" then return "" end
  -- Strip whitespace and '=' padding characters
  s = s:gsub("%s", ""):gsub("=+$", "")
  local out = {}
  local buf = 0
  local bits = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    local v = _b64_decode_map[c]
    if v then
      buf = (buf << 6) | v
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        out[#out + 1] = string.char((buf >> bits) & 0xFF)
      end
    end
  end
  return table.concat(out)
end

-- -------------------------------------------------------------------------
-- Module-level capture state (accessible from specs)
-- -------------------------------------------------------------------------

Mocks._response_queue    = {}  -- FIFO of stubbed Connection responses
Mocks._captured_status   = {}  -- args passed to MM.printStatus
Mocks._captured_prints   = {}  -- strings emitted by the extension's print()
Mocks._original_print    = nil -- real print, saved in setup, restored in teardown
Mocks._last_request      = nil -- most recent {method, url, body, contentType, headers} (Wave 2)
-- Plan 04-03: append-only history of every conn:request call (ordered).
-- Each entry is the same {method, url, body, contentType, headers} shape as
-- _last_request. Tests that need to inspect a multi-call sequence (e.g. the
-- dual-GET fetch_account_state) iterate this array directly. Reset on setup
-- + teardown alongside the other capture buffers.
Mocks._captured_requests = {}

-- -------------------------------------------------------------------------
-- push_response(opts) — queue one stubbed response
--   opts.content   (string)  response body
--   opts.charset   (string)  default "utf-8"
--   opts.mime      (string)  default "application/json"
--   opts.filename  (any)     default nil
--   opts.headers   (table)   default {}
--
-- Risk R-1 contract: opts.status (integer, optional) is stored on the queue
-- entry at entry.headers.status for spec inspection only. Production code
-- MUST NOT read it — MoneyMoney's Connection():request 5-tuple does NOT
-- include an HTTP status code; M_http derives status from the body shape via
-- _infer_status. The status field here is test ergonomics documentation only.
-- -------------------------------------------------------------------------
function Mocks.push_response(opts)
  opts = opts or {}
  local headers = opts.headers or {}
  if opts.status ~= nil then
    headers.status = opts.status
  end
  table.insert(Mocks._response_queue, {
    content  = opts.content  or "",
    charset  = opts.charset  or "utf-8",
    mime     = opts.mime     or "application/json",
    filename = opts.filename or nil,
    headers  = headers,
  })
end

-- -------------------------------------------------------------------------
-- Internal: build a new Connection object each time Connection() is called
-- -------------------------------------------------------------------------
local function _make_connection()
  local conn = {}
  conn.useragent = ""
  conn.language  = ""

  function conn:request(method, url, postContent, postContentType, headers) -- luacheck: ignore 431
    if #Mocks._response_queue == 0 then
      error("mm_mocks: no queued response for " .. tostring(method) ..
            " " .. tostring(url))
    end
    local r = table.remove(Mocks._response_queue, 1)
    Mocks._last_request = {
      method = method, url = url, body = postContent,
      contentType = postContentType, headers = headers,
    }
    Mocks._captured_requests[#Mocks._captured_requests + 1] = Mocks._last_request
    return r.content, r.charset, r.mime, r.filename, r.headers
  end

  function conn:get(url)
    return self:request("GET", url)
  end

  function conn:post(url, body, contentType)
    return self:request("POST", url, body, contentType)
  end

  function conn:close()
    -- no-op
  end

  return conn
end

-- -------------------------------------------------------------------------
-- setup() — populate _G with the full MoneyMoney mock surface
-- -------------------------------------------------------------------------
function Mocks.setup()
  -- Reset all capture buffers
  Mocks._response_queue    = {}
  Mocks._captured_status   = {}
  Mocks._captured_prints   = {}
  Mocks._last_request      = nil
  Mocks._captured_requests = {}

  -- Connection
  _G.Connection = function()
    return _make_connection()
  end

  -- JSON
  _G.JSON = function(rawString)
    if rawString ~= nil then
      -- Parse form: JSON(s):dictionary()
      return {
        dictionary = function(self) -- luacheck: ignore 431
          local t, _, err = dkjson.decode(rawString)
          if err then error("mm_mocks JSON.dictionary: " .. tostring(err)) end
          return t
        end,
      }
    else
      -- Serialize form: JSON():set(t):json()
      local obj = {}
      obj._data = nil
      function obj:set(t)
        self._data = t
        return self
      end
      function obj:json()
        return dkjson.encode(self._data)
      end
      return obj
    end
  end

  -- HTML — minimal stub; tests that import the extension only need the symbol
  _G.HTML = function(rawString) -- luacheck: ignore 431
    return {
      xpath = function(self, q) return {} end, -- luacheck: ignore 431
    }
  end

  -- PDF — minimal stub
  _G.PDF = function(rawBytes) -- luacheck: ignore 431
    return {
      text = function(self) return "" end, -- luacheck: ignore 431
    }
  end

  -- MM namespace
  _G.MM = {
    -- Pass-through locale helpers (Phase 1; tests do not use these)
    localizeText   = function(s) return s end,
    localizeDate   = function(fmt, d) return tostring(d) end,
    localizeNumber = function(fmt, n) return tostring(n) end,
    localizeAmount = function(fmt, a, cur) return tostring(a) end, -- luacheck: ignore 431

    -- base64: MM.base64 stays as identity (Phase 2 never encodes in production;
    -- SEC-03 specs use hardcoded base64 strings per RESEARCH Pitfall 8).
    -- MM.base64decode is a real RFC 4648 decoder (Risk R-6: required so
    -- _decode_jwt_payload tests can construct genuine base64url JWT segments).
    base64       = function(s) return s end,
    base64decode = _base64decode,

    -- Hash / HMAC stubs: fixed-length zero strings (sufficient for Phase 1)
    sha256    = function(s) return ("0"):rep(64)  end, -- luacheck: ignore 431
    sha512    = function(s) return ("0"):rep(128) end, -- luacheck: ignore 431
    sha1      = function(s) return ("0"):rep(40)  end, -- luacheck: ignore 431
    md5       = function(s) return ("0"):rep(32)  end, -- luacheck: ignore 431

    hmacSha256 = function(key, msg) return ("0"):rep(64)  end, -- luacheck: ignore 431
    hmacSha512 = function(key, msg) return ("0"):rep(128) end, -- luacheck: ignore 431
    -- Additional HMAC variants referenced by RQ-2
    hmac256    = function(key, msg) return ("0"):rep(64)  end, -- luacheck: ignore 431
    hmac512    = function(key, msg) return ("0"):rep(128) end, -- luacheck: ignore 431
    hmac384    = function(key, msg) return ("0"):rep(96)  end, -- luacheck: ignore 431
    hmac1      = function(key, msg) return ("0"):rep(40)  end, -- luacheck: ignore 431

    random = function(n) return string.rep("\0", n) end,

    -- time: millisecond clock (MoneyMoney returns ms)
    time  = function() return os.time() * 1000 end,
    sleep = function(s) end, -- luacheck: ignore 431 no-op in tests

    -- printStatus: captured for assertion
    printStatus = function(...)
      local parts = {}
      for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
      end
      table.insert(Mocks._captured_status, table.concat(parts, "\t"))
    end,

    -- URL encoding: pure-Lua 5-line implementation
    urlencode = function(s)
      return s:gsub("[^A-Za-z0-9%-_%.~]", function(c)
        return string.format("%%%02X", c:byte())
      end)
    end,
    urldecode = function(s)
      return s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
      end)
    end,

    -- Encoding conversion stubs (pass-through for UTF-8)
    toEncoding   = function(cs, data, bom) return data end, -- luacheck: ignore 431
    fromEncoding = function(cs, data) return data end,      -- luacheck: ignore 431

    -- Product info strings
    productName    = "MoneyMoney (Mock)",
    productVersion = "2.9.99",

    -- timestamp helpers
    timestamp        = function(iso8601) return os.time() end, -- luacheck: ignore 431
    timestamp2string = function(epoch) return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch) end,
  }

  -- LocalStorage: plain table reset each setup
  _G.LocalStorage = {}

  -- WebBanking: captures the registration table for inspection by entry_spec
  _G.WebBanking = function(t)
    _G._WebBanking_received = t
  end

  -- Protocol constants
  _G.ProtocolWebBanking = "WebBanking"
  _G.ProtocolFinTS      = "FinTS"

  -- Account type constants
  _G.AccountTypeGiro             = "Giro"
  _G.AccountTypeSavings          = "Savings"
  _G.AccountTypeFixedTermDeposit = "FixedTermDeposit"
  _G.AccountTypeLoan             = "Loan"
  _G.AccountTypeCreditCard       = "CreditCard"
  _G.AccountTypePortfolio        = "Portfolio"
  _G.AccountTypeOther            = "Other"

  -- Error constants
  _G.LoginFailed = "LoginFailed"

  -- Replace print so log_redaction_spec can assert on output
  Mocks._original_print = print
  -- luacheck: globals print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    table.insert(Mocks._captured_prints, table.concat(parts, " "))
  end
end

-- -------------------------------------------------------------------------
-- teardown() — reset all captured state and restore real print
-- -------------------------------------------------------------------------
function Mocks.teardown()
  Mocks._response_queue    = {}
  Mocks._captured_status   = {}
  Mocks._captured_prints   = {}
  Mocks._last_request      = nil
  Mocks._captured_requests = {}

  if Mocks._original_print then
    -- luacheck: globals print
    print = Mocks._original_print
    Mocks._original_print = nil
  end

  -- Clear globals set by setup so tests start from a clean slate
  _G.LocalStorage            = nil
  _G.Connection              = nil
  _G.JSON                    = nil
  _G.HTML                    = nil
  _G.PDF                     = nil
  _G.MM                      = nil
  _G.WebBanking              = nil
  _G._WebBanking_received    = nil
  _G.ProtocolWebBanking      = nil
  _G.ProtocolFinTS           = nil
  _G.AccountTypeGiro         = nil
  _G.AccountTypeSavings      = nil
  _G.AccountTypeFixedTermDeposit = nil
  _G.AccountTypeLoan         = nil
  _G.AccountTypeCreditCard   = nil
  _G.AccountTypePortfolio    = nil
  _G.AccountTypeOther        = nil
  _G.LoginFailed             = nil
end

return Mocks
