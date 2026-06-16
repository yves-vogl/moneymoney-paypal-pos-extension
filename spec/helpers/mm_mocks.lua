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

local dkjson = require("dkjson")

local Mocks = {}

-- -------------------------------------------------------------------------
-- Module-level capture state (accessible from specs)
-- -------------------------------------------------------------------------

Mocks._response_queue  = {}   -- FIFO of stubbed Connection responses
Mocks._captured_status = {}   -- args passed to MM.printStatus
Mocks._captured_prints = {}   -- strings emitted by the extension's print()
Mocks._original_print  = nil  -- real print, saved in setup, restored in teardown

-- -------------------------------------------------------------------------
-- push_response(opts) — queue one stubbed response
--   opts.content   (string)  response body
--   opts.charset   (string)  default "utf-8"
--   opts.mime      (string)  default "application/json"
--   opts.filename  (any)     default nil
--   opts.headers   (table)   default {}
-- -------------------------------------------------------------------------
function Mocks.push_response(opts)
  opts = opts or {}
  table.insert(Mocks._response_queue, {
    content  = opts.content  or "",
    charset  = opts.charset  or "utf-8",
    mime     = opts.mime     or "application/json",
    filename = opts.filename or nil,
    headers  = opts.headers  or {},
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
  Mocks._response_queue  = {}
  Mocks._captured_status = {}
  Mocks._captured_prints = {}

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

    -- base64: identity stubs — no test in Phase 1 requires real encoding
    base64       = function(s) return s end,
    base64decode = function(s) return s end,

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
  Mocks._response_queue  = {}
  Mocks._captured_status = {}
  Mocks._captured_prints = {}

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
