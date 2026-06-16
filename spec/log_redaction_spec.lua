-- spec/log_redaction_spec.lua
-- Tests for the log redaction patterns in M_log (from src/log.lua).
-- Coverage: SEC-01 (redaction of JWT, Bearer, assertion=, access_token=),
--           SEC-04 positive path ([paypal-pos][INFO] prefix present).
--
-- Strategy: Mocks.setup() installs the WebBanking mock and replaces print()
-- with a capture buffer.  dofile("dist/paypal-pos.lua") loads the amalgamated
-- artifact, which populates M_log (a top-level global declared in
-- src/webbanking_header.lua and filled by the do...end block for src/log.lua).
-- After each call to M_log.info/warn/error, the captured print line is checked.
--
-- The artifact is (re-)built once before the suite runs to ensure it is fresh.

local Mocks = require("spec.helpers.mm_mocks")

-- Build a fresh artifact once for the whole suite.
-- We use os.execute here (permitted in tools/); the spec itself is in spec/.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("log_redaction_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

-- Helper: load the amalgamated artifact into the current environment.
-- Called in each before_each after Mocks.setup() so the log module sees the
-- mocked print() rather than the real one.
local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- Helper: return the most recently captured print line (last entry in the table).
local function last_print()
  local p = Mocks._captured_prints
  return p[#p]
end

-- -------------------------------------------------------------------------
describe("M_log redaction", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -----------------------------------------------------------------------
  -- Positive redaction cases
  -- -----------------------------------------------------------------------

  it("redacts a JWT three-part token", function()
    -- A realistic-looking JWT: header.payload.signature, each >=4 base64url chars.
    local fake_jwt = "abcd1234.efgh5678.ijkl9012zzzz"
    M_log.info("token=" .. fake_jwt)

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:find("<redacted>"),
      "JWT should be replaced with <redacted> (got: " .. tostring(line) .. ")")
    assert.is_falsy(line:find("abcd1234%.efgh5678"),
      "original JWT payload should not appear in output (got: " .. tostring(line) .. ")")
  end)

  it("redacts a Bearer token in an Authorization header", function()
    M_log.info("Authorization: Bearer abc123def456")

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:find("Bearer <redacted>"),
      "Bearer value should be replaced (got: " .. tostring(line) .. ")")
    assert.is_falsy(line:find("abc123def456"),
      "raw Bearer value should not appear in output (got: " .. tostring(line) .. ")")
  end)

  it("redacts an assertion= form-encoded field", function()
    M_log.info("grant_type=jwt-bearer&assertion=eyJSECRET&client_id=foo")

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:find("assertion=<redacted>"),
      "assertion value should be replaced (got: " .. tostring(line) .. ")")
    assert.is_falsy(line:find("eyJSECRET"),
      "raw assertion value should not appear in output (got: " .. tostring(line) .. ")")
  end)

  it("redacts an access_token= form-encoded field", function()
    M_log.info("access_token=mysecret&token_type=Bearer")

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:find("access_token=<redacted>"),
      "access_token value should be replaced (got: " .. tostring(line) .. ")")
    assert.is_falsy(line:find("mysecret"),
      "raw access_token value should not appear in output (got: " .. tostring(line) .. ")")
  end)

  -- -----------------------------------------------------------------------
  -- Negative cases — innocuous strings must pass through unchanged
  -- -----------------------------------------------------------------------

  it("does NOT redact innocuous strings", function()
    M_log.info("Refreshing account abc-123")

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:find("Refreshing account abc%-123"),
      "innocuous message should be unchanged (got: " .. tostring(line) .. ")")
  end)

  it("does NOT redact hostnames like oauth.zettle.com", function()
    -- The JWT pattern's 4-char-minimum guard must not match short hostname segments
    -- separated by dots (oauth has 5 chars but the second segment 'zettle' does not
    -- look like a base64url-only segment when followed by a TLD).
    M_log.info("Connecting to oauth.zettle.com")

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:find("oauth%.zettle%.com"),
      "hostname oauth.zettle.com should be present unchanged (got: " .. tostring(line) .. ")")
  end)

  -- -----------------------------------------------------------------------
  -- Format check
  -- -----------------------------------------------------------------------

  it("formats output with [paypal-pos][INFO] prefix", function()
    M_log.info("hello")

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:sub(1, 18) == "[paypal-pos][INFO]",
      "output should start with [paypal-pos][INFO] (got: " .. tostring(line) .. ")")
  end)

end)
