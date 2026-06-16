-- spec/mm_mocks_spec.lua
-- Smoke-tests for spec/helpers/mm_mocks.lua.
-- Coverage: TEST-01 — verifies every documented MoneyMoney global is reachable
-- after Mocks.setup() and that the core mock behaviours (Connection FIFO,
-- JSON parse/serialise, LocalStorage, LoginFailed, WebBanking capture) work.

local Mocks = require("spec.helpers.mm_mocks")

describe("mm_mocks", function()

  before_each(function()
    Mocks.setup()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Global presence
  -- -------------------------------------------------------------------------

  it("declares all MoneyMoney globals after setup", function()
    local expected = {
      "Connection", "JSON", "HTML", "PDF", "MM", "LocalStorage",
      "WebBanking",
      "ProtocolWebBanking", "ProtocolFinTS",
      "AccountTypeGiro", "AccountTypeSavings", "AccountTypeFixedTermDeposit",
      "AccountTypeLoan", "AccountTypeCreditCard", "AccountTypePortfolio",
      "AccountTypeOther",
      "LoginFailed",
    }
    for _, name in ipairs(expected) do
      assert.is_not_nil(_G[name], name .. " should be non-nil after Mocks.setup()")
    end
  end)

  -- -------------------------------------------------------------------------
  -- MM.* method callability
  -- -------------------------------------------------------------------------

  it("provides callable MM.* methods", function()
    local methods = {
      "localizeText", "printStatus", "time",
      "sha256", "sha512", "sha1", "md5",
      "hmacSha256", "hmacSha512",
      "base64", "base64decode",
      "urlencode", "urldecode",
      "timestamp", "timestamp2string",
    }
    for _, name in ipairs(methods) do
      assert.equals("function", type(_G.MM[name]),
        "MM." .. name .. " should be a function")
    end

    -- Call each with representative arguments to confirm no runtime error.
    assert.equals("hello",  _G.MM.localizeText("hello"))
    _G.MM.printStatus("status text")
    local t = _G.MM.time()
    assert.is_truthy(type(t) == "number" and t > 0, "MM.time() should return a positive number")
    assert.equals(64,  #_G.MM.sha256("x"))
    assert.equals(128, #_G.MM.sha512("x"))
    assert.equals(40,  #_G.MM.sha1("x"))
    assert.equals(32,  #_G.MM.md5("x"))
    assert.equals(64,  #_G.MM.hmacSha256("k", "m"))
    assert.equals(128, #_G.MM.hmacSha512("k", "m"))
    assert.is_string(_G.MM.base64("abc"))
    assert.is_string(_G.MM.base64decode("abc"))
    assert.equals("hello%20world", _G.MM.urlencode("hello world"))
    assert.equals("hello world",   _G.MM.urldecode("hello%20world"))
    assert.is_number(_G.MM.timestamp("2024-01-01T00:00:00Z"))
    assert.is_string(_G.MM.timestamp2string(0))
  end)

  -- -------------------------------------------------------------------------
  -- Connection FIFO
  -- -------------------------------------------------------------------------

  it("Connection FIFO queues and returns responses in order", function()
    Mocks.push_response({ content = '{"hi":1}' })
    local c = _G.Connection()
    local body = c:get("https://example.com")
    assert.equals('{"hi":1}', body)
  end)

  it("Connection FIFO returns responses in first-in-first-out order", function()
    Mocks.push_response({ content = "first" })
    Mocks.push_response({ content = "second" })
    local c = _G.Connection()
    local a = c:get("https://example.com/a")
    local b = c:get("https://example.com/b")
    assert.equals("first",  a)
    assert.equals("second", b)
  end)

  it("Connection errors when queue is empty", function()
    local c = _G.Connection()
    local ok, err = pcall(function() c:get("https://example.com") end)
    assert.is_false(ok, "should raise an error when the queue is empty")
    assert.is_truthy(tostring(err):find("no queued response"),
      "error message should mention 'no queued response' (got: " .. tostring(err) .. ")")
  end)

  -- -------------------------------------------------------------------------
  -- JSON mock
  -- -------------------------------------------------------------------------

  it("JSON parses a JSON string via :dictionary()", function()
    local s = '{"a":1,"b":[1,2,3]}'
    local t = _G.JSON(s):dictionary()
    assert.equals(1, t.a)
    assert.equals(1, t.b[1])
    assert.equals(3, t.b[3])
  end)

  it("JSON serialises a table via :set():json()", function()
    local j = _G.JSON():set({ a = 1 }):json()
    assert.is_string(j)
    assert.is_truthy(j:find('"a"'),
      'serialised JSON should contain "a" (got: ' .. tostring(j) .. ')')
  end)

  -- -------------------------------------------------------------------------
  -- LocalStorage
  -- -------------------------------------------------------------------------

  it("LocalStorage is a writable table", function()
    _G.LocalStorage.foo = "bar"
    assert.equals("bar", _G.LocalStorage.foo)
  end)

  -- -------------------------------------------------------------------------
  -- Constants
  -- -------------------------------------------------------------------------

  it("LoginFailed is the documented string constant", function()
    assert.equals("LoginFailed", _G.LoginFailed)
  end)

  -- -------------------------------------------------------------------------
  -- WebBanking capture
  -- -------------------------------------------------------------------------

  it("WebBanking captures the registration table", function()
    _G.WebBanking({ services = { "PayPal POS" } })
    assert.is_not_nil(_G._WebBanking_received,
      "_WebBanking_received should be set after calling WebBanking()")
    assert.equals("PayPal POS", _G._WebBanking_received.services[1])
  end)

end)
