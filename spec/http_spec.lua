-- spec/http_spec.lua
-- Test scaffold for M_http (Phase 2, Wave 0).
-- Contains one sanity test confirming the artifact loads and M_http is present,
-- plus pending() stubs for every M_http test command in
-- .planning/phases/02-authenticated-network-layer/02-VALIDATION.md (❌ W0 rows).
-- Wave 2 fills in the pending assertions once src/http.lua is implemented.
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so that each
-- test starts with a clean module-local _conn (D-25: single reused Connection).
-- This matches the before_each pattern from spec/log_redaction_spec.lua L41-48.

local Mocks = require("spec.helpers.mm_mocks")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("http_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("M_http", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Sanity test (non-pending) — confirm artifact loads and M_http is present
  -- -------------------------------------------------------------------------

  it("M_http module table is exposed", function()
    assert.is_table(M_http)
  end)

  -- -------------------------------------------------------------------------
  -- D-25: post_form behaviour
  -- -------------------------------------------------------------------------

  pending("post_form constructs sorted form body with url-encoded values", function()
    -- Wave 2: push response, call post_form, inspect captured conn:request
    -- postContent to assert sorted key=value pairs per D-25 contract
  end)

  pending("post_form always sends Accept: application/json header", function()
    -- Wave 2: assert conn:request headers include Accept: application/json
    -- (Pitfall 1: Zettle token endpoint requires explicit Accept header)
  end)

  pending("post_form returns 5-tuple destructured correctly", function()
    -- Wave 2: assert (decoded_table, status, raw_body) shape from post_form
    -- per D-25 return contract (Risk R-1: status is inferred, not from tuple)
  end)

  -- -------------------------------------------------------------------------
  -- SEC-01 / AUTH-05: redaction before debug log
  -- -------------------------------------------------------------------------

  pending("post_form passes raw body through M_log.redact before debug log", function()
    -- Wave 2: push response with assertion= body, call post_form, assert
    -- captured print never contains raw assertion value (SEC-01 / AUTH-05)
  end)

  -- -------------------------------------------------------------------------
  -- D-24: network failure / empty body handling
  -- -------------------------------------------------------------------------

  pending("post_form returns nil status for empty body", function()
    -- Wave 2: push response with content="", assert status is nil (not 0 or 200)
    -- so M_errors.from_http_status(nil) returns the network error string
  end)

  -- -------------------------------------------------------------------------
  -- Risk R-1: _infer_status body-shape inference
  -- -------------------------------------------------------------------------

  pending("_infer_status maps invalid_grant body to 400", function()
    -- Wave 2: push token_invalid_grant.json, call post_form, assert status==400
  end)

  pending("_infer_status maps success body to 200", function()
    -- Wave 2: push token_ok.json, call post_form, assert status==200
  end)

  -- -------------------------------------------------------------------------
  -- Defense-in-depth: Bearer header never logged
  -- -------------------------------------------------------------------------

  pending("get_json never logs the Bearer header value", function()
    -- Wave 2: push any response, call get_json with Bearer header,
    -- assert no captured print contains "Bearer " followed by a token value
  end)

  -- -------------------------------------------------------------------------
  -- D-25: shutdown / cleanup
  -- -------------------------------------------------------------------------

  pending("shutdown nils the module-local Connection", function()
    -- Wave 2: call post_form (creates _conn), then shutdown, assert next
    -- post_form creates a fresh Connection() (via mock reset)
  end)

  pending("shutdown is idempotent", function()
    -- Wave 2: call shutdown twice without error (defensive nil-guard test)
  end)

end)
