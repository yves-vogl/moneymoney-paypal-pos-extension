-- spec/finance_account_state_spec.lua
-- Plan 04-03 Task 1: covers M_finance.fetch_account_state — the dual-GET
-- balance fetcher (RESEARCH §1.4):
--   1. GET https://finance.izettle.com/v2/accounts/liquid/balance       (settled)
--   2. GET https://finance.izettle.com/v2/accounts/preliminary/balance  (in-flight)
--
-- ACCT-03 / D-37: currency-guard for non-EUR balances; D-52 ERR-06 fail-
-- whole-refresh on either-leg HTTP error. The Bearer header pass-through
-- (D-42) mirrors M_finance.fetch.

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("finance_account_state_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- luacheck: globals M_finance LoginFailed

describe("M_finance.fetch_account_state", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  it("fetch_account_state is a function exposed by the artifact (Task 1 GREEN)", function()
    assert.is_function(M_finance.fetch_account_state,
      "M_finance.fetch_account_state must be a function (Plan 04-03 Task 1)")
  end)

  it("fetch_account_state issues two sequential GETs (liquid then preliminary)", function()
    local liquid_raw, _      = Fixtures.load("finance/finance_balance_liquid")
    local preliminary_raw, _ = Fixtures.load("finance/finance_balance_preliminary")
    Mocks.push_response({ content = liquid_raw })
    Mocks.push_response({ content = preliminary_raw })

    M_finance.fetch_account_state("AT-VALID")

    assert.equals(2, #Mocks._captured_requests,
      "fetch_account_state must issue exactly 2 GETs")
    local first  = Mocks._captured_requests[1]
    local second = Mocks._captured_requests[2]
    assert.is_not_nil(first.url:find("/v2/accounts/liquid/balance", 1, true),
      "first GET must target /v2/accounts/liquid/balance, got: " .. first.url)
    assert.is_not_nil(second.url:find("/v2/accounts/preliminary/balance", 1, true),
      "second GET must target /v2/accounts/preliminary/balance, got: " .. second.url)
    -- Bearer header pass-through (D-42) on BOTH legs.
    assert.equals("Bearer AT-VALID", first.headers["Authorization"])
    assert.equals("Bearer AT-VALID", second.headers["Authorization"])
  end)

  it("fetch_account_state returns {balance = 123.45, pendingBalance = 6.78} on EUR fixtures", function()
    local liquid_raw, _      = Fixtures.load("finance/finance_balance_liquid")
    local preliminary_raw, _ = Fixtures.load("finance/finance_balance_preliminary")
    Mocks.push_response({ content = liquid_raw })
    Mocks.push_response({ content = preliminary_raw })

    local state, err = M_finance.fetch_account_state("AT-VALID")
    assert.is_nil(err, "no error expected, got: " .. tostring(err))
    assert.is_table(state)
    assert.equals(123.45, state.balance,
      "liquid balance must be totalBalance / 100 (12345 -> 123.45)")
    assert.equals(6.78, state.pendingBalance,
      "preliminary balance must be totalBalance / 100 (678 -> 6.78)")
  end)

  it("currency-guard: non-EUR liquid -> balance = nil, pendingBalance still populated (R-4)", function()
    -- Inline non-EUR liquid fixture (GBP) so the currency-guard branch fires.
    local liquid_gbp = '{"data": {"totalBalance": 9999, "currencyId": "GBP"}}'
    local preliminary_raw, _ = Fixtures.load("finance/finance_balance_preliminary")
    Mocks.push_response({ content = liquid_gbp })
    Mocks.push_response({ content = preliminary_raw })

    local state, err = M_finance.fetch_account_state("AT-VALID")
    assert.is_nil(err)
    assert.is_table(state)
    assert.is_nil(state.balance, "non-EUR liquid balance must surface as nil (D-37 / R-4)")
    assert.equals(6.78, state.pendingBalance,
      "EUR preliminary balance must still populate when liquid is skipped")
  end)

  it("fetch_account_state returns (nil, err) when liquid call errors; preliminary GET NOT issued (ERR-06)", function()
    -- A non-JSON body forces M_http.get_json to return (nil, nil, raw) which
    -- routes via M_errors.from_http_status(nil) -> German error.network string.
    Mocks.push_response({ content = "not json at all" })

    local state, err = M_finance.fetch_account_state("AT-VALID")
    assert.is_nil(state)
    assert.is_string(err)
    -- Preliminary GET must NOT have been issued (fail-whole-refresh; only one
    -- captured request from the liquid call).
    assert.equals(1, #Mocks._captured_requests,
      "preliminary GET must NOT be issued after liquid error (ERR-06), got " ..
      tostring(#Mocks._captured_requests) .. " captured requests")
    assert.is_not_nil(Mocks._captured_requests[1].url:find("/liquid/balance", 1, true),
      "the single captured request must be the liquid call, got: " ..
      Mocks._captured_requests[1].url)
  end)

  it("fetch_account_state returns (nil, err = LoginFailed) when preliminary 401s", function()
    -- Liquid OK, preliminary returns invalid_client body -> _infer_status -> 401 -> LoginFailed
    local liquid_raw, _ = Fixtures.load("finance/finance_balance_liquid")
    Mocks.push_response({ content = liquid_raw })
    Mocks.push_response({ content = '{"error":"invalid_client"}' })

    local state, err = M_finance.fetch_account_state("AT-VALID")
    assert.is_nil(state, "fetch_account_state must return nil on preliminary error")
    assert.equals(LoginFailed, err,
      "invalid_client on preliminary call must route to LoginFailed")
    -- Both calls must have been issued
    assert.equals(2, #Mocks._captured_requests)
  end)

  it("fetch_account_state asserts on nil bearer", function()
    assert.has_error(function() M_finance.fetch_account_state(nil) end)
  end)

  it("fetch_account_state asserts on empty bearer", function()
    assert.has_error(function() M_finance.fetch_account_state("") end)
  end)

end)
