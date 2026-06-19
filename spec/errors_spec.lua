-- spec/errors_spec.lua
-- Tests for M_errors.from_http_status (D-24 six-case HTTP-status mapping).
-- Greened by Wave 1 (plan 02-02). Each test name corresponds directly to a
-- D-24 case from .planning/phases/02-authenticated-network-layer/02-CONTEXT.md.
-- The SEC-03 structural-invariant test gates that body is never echoed.

local Mocks = require("spec.helpers.mm_mocks")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("errors_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("M_errors.from_http_status", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Sanity test (non-pending) — confirm artifact loads and M_errors is present
  -- -------------------------------------------------------------------------

  it("M_errors module table is exposed", function()
    assert.is_table(M_errors)
  end)

  -- -------------------------------------------------------------------------
  -- D-24: nil status (network/timeout/no response)
  -- -------------------------------------------------------------------------

  it("nil status returns network string with dash placeholder", function()
    local result = M_errors.from_http_status(nil, "")
    assert.equals(M_i18n.t("error.network", "—"), result)
  end)

  -- -------------------------------------------------------------------------
  -- D-24: 2xx range → nil (signals "no error")
  -- -------------------------------------------------------------------------

  it("200 returns nil", function()
    local result = M_errors.from_http_status(200, '{"access_token":"AT"}')
    assert.is_nil(result)
  end)

  it("299 returns nil", function()
    local result = M_errors.from_http_status(299, "")
    assert.is_nil(result)
  end)

  -- -------------------------------------------------------------------------
  -- D-24: 400/401/403 → LoginFailed (AUTH-03 synchronous fail surface)
  -- -------------------------------------------------------------------------

  it("400 returns LoginFailed", function()
    local result = M_errors.from_http_status(400, '{"error":"invalid_grant"}')
    assert.equals(LoginFailed, result)
  end)

  it("401 returns LoginFailed", function()
    local result = M_errors.from_http_status(401, "")
    assert.equals(LoginFailed, result)
  end)

  it("403 returns LoginFailed", function()
    local result = M_errors.from_http_status(403, "")
    assert.equals(LoginFailed, result)
  end)

  -- -------------------------------------------------------------------------
  -- D-24: 429 → rate_limit string
  -- -------------------------------------------------------------------------

  it("429 returns rate_limit string", function()
    local result = M_errors.from_http_status(429, "")
    assert.equals(M_i18n.t("error.rate_limit"), result)
  end)

  -- -------------------------------------------------------------------------
  -- D-24: 5xx → network string with status code
  -- -------------------------------------------------------------------------

  it("500 returns network string with status", function()
    local result = M_errors.from_http_status(500, "")
    assert.equals(M_i18n.t("error.network", "500"), result)
  end)

  it("599 returns network string with status", function()
    local result = M_errors.from_http_status(599, "")
    assert.equals(M_i18n.t("error.network", "599"), result)
  end)

  -- -------------------------------------------------------------------------
  -- D-24: catch-all (anything else) → network string with status
  -- -------------------------------------------------------------------------

  it("999 returns network string with status", function()
    local result = M_errors.from_http_status(999, "")
    assert.equals(M_i18n.t("error.network", "999"), result)
  end)

  -- -------------------------------------------------------------------------
  -- SEC-03: structural invariant — body is never echoed into the result
  -- -------------------------------------------------------------------------

  it("body parameter is never echoed into the result", function()
    local secret_body = '{"error":"invalid_grant","error_description":"SECRET_BODY_MARKER_XYZ"}'
    local result = M_errors.from_http_status(400, secret_body)
    -- result must be LoginFailed or a string; body content must never appear
    if type(result) == "string" then
      assert.is_falsy(result:find("SECRET_BODY_MARKER_XYZ", 1, true))
    end
    -- Non-string results (LoginFailed literal) trivially satisfy the invariant
  end)

end)
