-- spec/log_redaction_spec.lua
-- Tests for the log redaction patterns in M_log (from src/log.lua).
-- Coverage: SEC-01 (redaction of JWT, Bearer, assertion=, access_token=),
--           SEC-04 positive path ([paypal-pos][INFO] prefix present).
--           SEC-03 gating spec (D-29): API key never leaks through any channel.
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
  -- S-03: Bearer pattern must cover tokens with = and + characters (S-03).
  -- The old [%w%-_.]+ pattern truncates at these chars, leaking a fragment.
  -- The fix widens to %S+ (any non-whitespace run after "Bearer ").
  -- -----------------------------------------------------------------------

  it("S-03: redacts a Bearer token containing + (standard base64 alphabet)", function()
    -- Old [%w%-_.]+ pattern stops at +, leaking the suffix "def/ghi=" in output.
    M_log.info("Authorization: Bearer abc+def/ghi=")

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:find("Bearer <redacted>"),
      "Bearer value with + should be fully replaced (got: " .. tostring(line) .. ")")
    assert.is_falsy(line:find("def/ghi"),
      "fragment after + must not appear in output (got: " .. tostring(line) .. ")")
  end)

  it("S-03: redacts a Bearer token containing = (base64 padding char)", function()
    -- Old pattern stops before =, leaving the trailing fragment in output.
    M_log.info("Authorization: Bearer tok+ending=x")

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:find("Bearer <redacted>"),
      "Bearer value with = should be fully replaced (got: " .. tostring(line) .. ")")
    assert.is_falsy(line:find("ending=x"),
      "trailing fragment after + must not appear in output (got: " .. tostring(line) .. ")")
  end)

  -- -----------------------------------------------------------------------
  -- S-04: access_token in JSON key:value form must also be redacted.
  -- The old rule only covers form-encoded (access_token=VALUE); a JSON body
  -- like {"access_token":"short_tok",...} passes through all four rules.
  -- -----------------------------------------------------------------------

  it("S-04: redacts access_token in JSON key-value form (short non-JWT value)", function()
    -- short_tok is not JWT-shaped so rule 1 (JWT three-segment pattern) misses it.
    M_log.info('{"access_token":"short_tok","expires_in":7200}')

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_truthy(line:find('"access_token":"<redacted>"'),
      'JSON access_token value should be replaced (got: ' .. tostring(line) .. ')')
    assert.is_falsy(line:find("short_tok"),
      "raw JSON access_token value must not appear in output (got: " .. tostring(line) .. ")")
  end)

  it("S-04: redacts access_token JSON form with optional whitespace around colon", function()
    -- Pattern must handle "access_token" : "value" (spaces around :).
    M_log.info('{"access_token" : "mytoken"}')

    local line = last_print()
    assert.is_not_nil(line, "M_log.info should have produced output")
    assert.is_falsy(line:find("mytoken"),
      "raw token must not appear in output when spaces around colon (got: " .. tostring(line) .. ")")
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

-- =========================================================================
-- SEC-03 — API key never leaks (D-29)
-- =========================================================================
-- Threads a REAL auth failure / success through the full integration path:
--   InitializeSession2 -> M_auth._extract_client_id / exchange_assertion
--   -> M_http.post_form -> M_errors.from_http_status
-- and asserts three negative invariants:
--   1. The MoneyMoney return string contains no JWT-shape, no "Bearer", and no
--      base64url segment of the input API key.
--   2. The captured print stream (M_log path) is likewise clean.
--   3. No LocalStorage value (walked recursively) contains the API key or any
--      of its three JWT segments.
--
-- Per Plan 02-07 / RESEARCH section "SEC-03 Gating Test" L1014-L1129.
-- Pitfall 8 avoidance: MM.base64 is an identity stub in mm_mocks.lua, so
-- we hard-code precomputed base64url constants rather than calling MM.base64.
-- "eyJhdWQiOiJjbGllbnQteCJ9" is the standard-base64url encoding of
-- '{"aud":"client-x"}' (no padding; verified offline).

describe("SEC-03 -- API key never leaks (D-29)", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -----------------------------------------------------------------------
  -- Test 1: malformed JWT (payload is valid base64url but not JSON).
  -- _extract_client_id returns nil -> no network call -> returns invalid_grant.
  -- -----------------------------------------------------------------------

  it("rejects a malformed JWT without echoing it anywhere", function()
    -- Middle segment "bm90anNvbg" decodes to "notjson" -- JSON parse fails.
    local fake_jwt = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.bm90anNvbg.signature"

    -- NO queued response: _extract_client_id fails before any network call (D-22).
    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = fake_jwt } }, false)

    assert.equals(M_i18n.t("error.invalid_grant"), result)

    -- The returned string must not contain the input or any JWT segment.
    assert.is_falsy(result:find("eyJ", 1, true),
      "result contains eyJ-shape: " .. tostring(result))
    assert.is_falsy(result:find("Bearer", 1, true),
      "result mentions Bearer: " .. tostring(result))
    for seg in fake_jwt:gmatch("[^.]+") do
      assert.is_falsy(result:find(seg, 1, true),
        "result contains JWT segment '" .. seg .. "': " .. tostring(result))
    end

    -- The captured print stream (M_log.redact path) must also be clean.
    for _, line in ipairs(Mocks._captured_prints) do
      assert.is_falsy(line:find(fake_jwt, 1, true),
        "print contains raw JWT: " .. line)
      for seg in fake_jwt:gmatch("[^.]+") do
        assert.is_falsy(line:find(seg, 1, true),
          "print contains JWT segment '" .. seg .. "': " .. line)
      end
    end
  end)

  -- -----------------------------------------------------------------------
  -- Test 2: valid JWT (client_id extracted) but /token returns invalid_grant.
  -- Reaches the network; assert error is LoginFailed with no API-key echo.
  -- -----------------------------------------------------------------------

  it("rejects an invalid_grant from /token without echoing the assertion", function()
    -- Precomputed base64url of '{"aud":"client-x"}' -- hardcoded per Pitfall 8
    -- (MM.base64 is an identity stub; we must not call it for encoding).
    local mid      = "eyJhdWQiOiJjbGllbnQteCJ9"
    local fake_jwt = "header." .. mid .. ".sig"

    Mocks.push_response({
      content = '{"error":"invalid_grant","error_description":"bad assertion"}',
    })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = fake_jwt } }, false)

    assert.equals(LoginFailed, result)

    -- Negative checks on the returned string.
    assert.is_falsy(result:find(fake_jwt, 1, true),
      "result contains fake_jwt: " .. tostring(result))
    for seg in fake_jwt:gmatch("[^.]+") do
      assert.is_falsy(result:find(seg, 1, true),
        "result contains JWT segment '" .. seg .. "': " .. tostring(result))
    end

    -- Negative checks on the captured print stream.
    for _, line in ipairs(Mocks._captured_prints) do
      assert.is_falsy(line:find(fake_jwt, 1, true),
        "print contains fake_jwt: " .. line)
      -- mid is the sensitive payload segment -- assert individually.
      assert.is_falsy(line:find(mid, 1, true),
        "print contains mid segment: " .. line)
    end
  end)

  -- -----------------------------------------------------------------------
  -- Test 3: successful auth round-trip -- LocalStorage must not hold the key.
  -- AUTH-05 + SEC-03 at the integration layer.
  -- -----------------------------------------------------------------------

  it("never writes the API key to LocalStorage even after a successful auth", function()
    local mid      = "eyJhdWQiOiJjbGllbnQteCJ9"
    local fake_jwt = "header." .. mid .. ".sig"

    -- Use a non-JWT-shaped access_token (AT-12345) so its characters cannot
    -- collide with fake_jwt segments in the LocalStorage walk below.
    Mocks.push_response({
      content = '{"access_token":"AT-12345","expires_in":7200,"token_type":"Bearer"}',
    })
    Mocks.push_response({
      content = '{"uuid":"user-1","organizationUuid":"org-1","publicName":"Test"}',
    })

    local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", 2,
                                      { { value = fake_jwt } }, false)

    assert.is_nil(result)

    -- Recursive LocalStorage walker: visits every string value in the table.
    local function walk(t, visit)
      for _, v in pairs(t) do
        if type(v) == "table" then
          walk(v, visit)
        elseif type(v) == "string" then
          visit(v)
        end
      end
    end

    walk(LocalStorage, function(s)
      assert.is_falsy(s:find(fake_jwt, 1, true),
        "LocalStorage value contains full API key: " .. s)
      for seg in fake_jwt:gmatch("[^.]+") do
        assert.is_falsy(s:find(seg, 1, true),
          "LocalStorage value contains JWT segment '" .. seg .. "': " .. s)
      end
    end)
  end)

end)
