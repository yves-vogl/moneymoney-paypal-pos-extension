-- spec/errors_spec.lua
-- Test scaffold for M_errors.from_http_status (Phase 2, Wave 0).
-- Contains one sanity test confirming the artifact loads and M_errors is present,
-- plus pending() stubs for the D-24 six-case HTTP-status mapping documented in
-- .planning/phases/02-authenticated-network-layer/02-CONTEXT.md D-24 and the
-- per-task verification map in 02-VALIDATION.md (❌ W0 rows).
-- Wave 1 (plan 02-02) fills in the pending assertions once src/errors.lua
-- implements M_errors.from_http_status(status, body).
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so M_errors
-- and M_i18n are fresh in each test.

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

  pending("nil status returns network string with dash placeholder", function()
    -- Wave 1: assert M_errors.from_http_status(nil) == M_i18n.t("error.network", "—")
  end)

  -- -------------------------------------------------------------------------
  -- D-24: 2xx range → nil (signals "no error")
  -- -------------------------------------------------------------------------

  pending("200 returns nil", function()
    -- Wave 1: assert M_errors.from_http_status(200) == nil
  end)

  pending("299 returns nil", function()
    -- Wave 1: assert M_errors.from_http_status(299) == nil (boundary check)
  end)

  -- -------------------------------------------------------------------------
  -- D-24: 400/401/403 → LoginFailed (AUTH-03 synchronous fail surface)
  -- -------------------------------------------------------------------------

  pending("400 returns LoginFailed", function()
    -- Wave 1: assert M_errors.from_http_status(400) == LoginFailed
    -- (D-24 / AUTH-03: invalid_grant body path → LoginFailed)
  end)

  pending("401 returns LoginFailed", function()
    -- Wave 1: assert M_errors.from_http_status(401) == LoginFailed
  end)

  pending("403 returns LoginFailed", function()
    -- Wave 1: assert M_errors.from_http_status(403) == LoginFailed
  end)

  -- -------------------------------------------------------------------------
  -- D-24: 429 → rate_limit string
  -- -------------------------------------------------------------------------

  pending("429 returns rate_limit string", function()
    -- Wave 1: assert M_errors.from_http_status(429) == M_i18n.t("error.rate_limit")
  end)

  -- -------------------------------------------------------------------------
  -- D-24: 5xx → network string with status code
  -- -------------------------------------------------------------------------

  pending("500 returns network string with status", function()
    -- Wave 1: assert M_errors.from_http_status(500) == M_i18n.t("error.network","500")
  end)

  pending("599 returns network string with status", function()
    -- Wave 1: assert M_errors.from_http_status(599) == M_i18n.t("error.network","599")
    -- (D-24 boundary: highest 5xx)
  end)

  -- -------------------------------------------------------------------------
  -- D-24: catch-all (anything else) → network string with status
  -- -------------------------------------------------------------------------

  pending("999 returns network string with status", function()
    -- Wave 1: assert M_errors.from_http_status(999) == M_i18n.t("error.network","999")
    -- (D-24 catch-all for unrecognised status codes)
  end)

end)
