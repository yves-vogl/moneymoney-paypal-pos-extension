-- spec/http_spec.lua
-- Tests for M_http (Phase 2, Wave 2).
-- Covers: post_form (body encoding, Accept header, return shape, redaction,
--         empty-body handling), _infer_status (body-shape inference per Risk R-1),
--         get_json (Bearer non-leakage), and shutdown (idempotent cleanup).
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

-- Helper: run fn with DEBUG = true, restore DEBUG = false afterward.
-- Ensures debug-log tests do not bleed into adjacent tests.
local function with_debug(fn)
  _G.DEBUG = true
  local ok, err = pcall(fn)
  _G.DEBUG = false
  assert(ok, err)
end

-- ---------------------------------------------------------------------------
describe("M_http", function()

  before_each(function()
    Mocks.setup()
    -- Plan 05-03: stub MM.sleep as no-op so retry-bearing tests do not block.
    -- The retry loop in _request_with_retry calls MM.sleep on 5xx/429/empty
    -- bodies; tests that exercise those paths queue additional responses.
    _G.MM = _G.MM or {}
    _G.MM.sleep = function(_) end
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

  it("post_form constructs sorted form body with url-encoded values", function()
    -- The OAuth form body has three keys: assertion, client_id, grant_type.
    -- Sorted alphabetically: assertion < client_id < grant_type.
    -- MM.urlencode encodes colons (:) as %3A and slashes (/) as %2F.
    Mocks.push_response({ content = '{"access_token":"AT","token_type":"bearer","expires_in":7200}' })
    M_http.post_form("https://oauth.zettle.com/token", {
      grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
      client_id  = "cid-x",
      assertion  = "hdr.payload.sig",
    }, {})
    local body = Mocks._last_request.body
    -- Body must start with assertion= (alphabetically first)
    assert.truthy(body:match("^assertion="))
    -- All three keys present
    assert.truthy(body:find("assertion=", 1, true))
    assert.truthy(body:find("client_id=", 1, true))
    assert.truthy(body:find("grant_type=", 1, true))
    -- Sorted: assertion before client_id before grant_type
    local pos_a = body:find("assertion=", 1, true)
    local pos_c = body:find("client_id=", 1, true)
    local pos_g = body:find("grant_type=", 1, true)
    assert.truthy(pos_a < pos_c)
    assert.truthy(pos_c < pos_g)
    -- grant_type value is percent-encoded (colons -> %3A)
    assert.truthy(body:find("urn%3A", 1, true))
    -- assertion value is in the body
    assert.truthy(body:find("hdr.payload.sig", 1, true))
  end)

  it("post_form always sends Accept: application/json header", function()
    Mocks.push_response({ content = '{"access_token":"AT","token_type":"bearer","expires_in":7200}' })
    M_http.post_form("https://oauth.zettle.com/token", { grant_type = "x" }, {})
    assert.equals("application/json", Mocks._last_request.headers["Accept"])
  end)

  it("post_form returns 5-tuple destructured correctly", function()
    -- post_form returns (decoded_table, inferred_status, raw_body)
    local raw_json = '{"access_token":"AT","token_type":"bearer","expires_in":7200}'
    Mocks.push_response({ content = raw_json })
    local decoded, status, raw = M_http.post_form("https://oauth.zettle.com/token", { grant_type = "x" }, {})
    assert.is_table(decoded)
    assert.equals("AT", decoded.access_token)
    assert.equals(200, status)
    assert.equals(raw_json, raw)
  end)

  -- -------------------------------------------------------------------------
  -- SEC-01 / AUTH-05: redaction before debug log
  -- -------------------------------------------------------------------------

  it("post_form passes raw body through M_log.redact before debug log", function()
    -- The assertion value is a JWT-shaped string (three base64url segments, each
    -- at least 4 chars) that M_log.redact should strip from debug output.
    local jwt_value = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJjbGllbnQtaWQifQ.AAABBBCCC"
    Mocks.push_response({ content = '{"access_token":"tok"}' })
    with_debug(function()
      M_http.post_form("https://oauth.zettle.com/token", {
        grant_type = "bearer",
        assertion  = jwt_value,
      }, {})
    end)
    -- At least one captured print must contain "<redacted>"
    local found_redacted = false
    for _, line in ipairs(Mocks._captured_prints) do
      if line:find("<redacted>", 1, true) then
        found_redacted = true
      end
    end
    assert.truthy(found_redacted, "expected <redacted> in at least one DEBUG log line")
    -- No captured print must contain the raw JWT value
    for _, line in ipairs(Mocks._captured_prints) do
      assert.falsy(line:find(jwt_value, 1, true),
        "raw JWT value must not appear in any log line")
    end
  end)

  -- -------------------------------------------------------------------------
  -- D-24: network failure / empty body handling
  -- -------------------------------------------------------------------------

  it("post_form returns nil status for empty body (Plan 05-03: retry-exhausted = nil status)", function()
    -- Plan 05-03 retry semantics: empty body triggers 3 retry attempts (D-62
    -- backoff). After all 3 attempts return empty, the function preserves
    -- Phase-2 ERR-05 path: returns (nil, nil, "") which M_errors.from_http_status
    -- (nil, ...) maps to error.network.
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })
    local decoded, status, raw = M_http.post_form("https://oauth.zettle.com/token", { grant_type = "x" }, {})
    assert.is_nil(decoded)
    assert.is_nil(status)
    assert.equals("", raw)
    assert.equals(3, #Mocks._captured_requests, "expected 3 retry attempts on empty body")
  end)

  -- -------------------------------------------------------------------------
  -- Risk R-1: _infer_status body-shape inference
  -- -------------------------------------------------------------------------

  it("_infer_status maps invalid_grant body to 400", function()
    assert.equals(400, M_http._infer_status({ error = "invalid_grant" }))
    assert.equals(400, M_http._infer_status({ error = "invalid_request" }))
    assert.equals(401, M_http._infer_status({ error = "invalid_client" }))
    assert.equals(401, M_http._infer_status({ error = "unauthorized_client" }))
    -- Unknown error -> conservative 400
    assert.equals(400, M_http._infer_status({ error = "some_new_error" }))
  end)

  it("_infer_status maps success body to 200", function()
    assert.equals(200, M_http._infer_status({ access_token = "x" }))
    assert.equals(200, M_http._infer_status({ uuid = "u", organizationUuid = "o" }))
  end)

  -- -------------------------------------------------------------------------
  -- H-01 / M-02: rate_limit error body must infer status 429 (not 400)
  -- -------------------------------------------------------------------------

  it("_infer_status maps rate_limit body to 429 (H-01)", function()
    -- Zettle returns {"error":"rate_limit",...} with HTTP 200 (Risk R-1).
    -- _infer_status must recognise "rate_limit" and return 429 so that
    -- from_http_status(429, ...) surfaces the German error.rate_limit string
    -- instead of LoginFailed. Without the fix this returns 400 (conservative
    -- fallback), making D-24 case 4 permanently dead code.
    assert.equals(429, M_http._infer_status({ error = "rate_limit" }))
  end)

  it("post_form rate_limited fixture returns 429 (M-02; Plan 05-03 single-retry consumes 2)", function()
    -- Load the recorded token_rate_limited fixture and push it as the
    -- Connection response. post_form must infer status=429 so that the caller
    -- (InitializeSession2 in entry.lua) can surface the German rate-limit
    -- message rather than LoginFailed.
    -- Plan 05-03 single-retry-on-429 (D-63) consumes the queued response THEN
    -- retries once. To preserve the assertion that 429 surfaces, queue the
    -- 429 body TWICE so the retry also returns 429 → caller sees status==429.
    local Fixtures = require("spec.helpers.fixtures")
    local raw = Fixtures.load("auth/token_rate_limited")
    Mocks.push_response({ content = raw, mime = "application/json" })  -- attempt 1
    Mocks.push_response({ content = raw, mime = "application/json" })  -- attempt 2 (single retry)
    local decoded, status, _ = M_http.post_form("https://oauth.zettle.com/token", { grant_type = "x" }, {})
    assert.is_table(decoded)
    assert.equals("rate_limit", decoded.error)
    assert.equals(429, status, "expected 429 returned after single-retry exhaustion")
    assert.equals(2, #Mocks._captured_requests, "expected 2 attempts (1 initial + 1 single retry)")
  end)

  -- -------------------------------------------------------------------------
  -- Plan 05-03: post_form retry symmetry with get_json (ADR-0005 Invariants 2+3)
  -- -------------------------------------------------------------------------

  it("post_form: 5xx-equivalent empty body exhausts after 3 attempts (Phase-2 ERR-05 path preserved)", function()
    -- Empty body × 3 → nil status (Phase-2 ERR-05 inheritance), 3 captured requests
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })
    local _, status, _ = M_http.post_form("https://oauth.zettle.com/token", { grant_type = "x" }, {})
    assert.is_nil(status, "expected nil status on empty-body 3-attempt exhaustion (ERR-05 path)")
    assert.equals(3, #Mocks._captured_requests, "expected 3 retry attempts on empty body")
  end)

  it("post_form: succeeds on 2nd attempt after one empty-body retry", function()
    Mocks.push_response({ content = "" })  -- attempt 1
    Mocks.push_response({ content = '{"access_token":"AT","token_type":"bearer","expires_in":7200}' })  -- attempt 2
    local parsed, status, _ = M_http.post_form("https://oauth.zettle.com/token", { grant_type = "x" }, {})
    assert.is_table(parsed)
    assert.equals(200, status)
    assert.equals("AT", parsed.access_token)
    assert.equals(2, #Mocks._captured_requests, "expected 2 attempts (1 empty retry + 1 success)")
  end)

  -- -------------------------------------------------------------------------
  -- Defense-in-depth: Bearer header never logged
  -- -------------------------------------------------------------------------

  it("get_json never logs the Bearer header value", function()
    Mocks.push_response({ content = '{"uuid":"u","organizationUuid":"org"}' })
    with_debug(function()
      M_http.get_json("https://oauth.zettle.com/users/self", {
        Authorization = "Bearer SECRET_TOKEN_XYZ",
      })
    end)
    -- No captured line may contain the secret token value
    for _, line in ipairs(Mocks._captured_prints) do
      assert.falsy(line:find("SECRET_TOKEN_XYZ", 1, true),
        "token value must not appear in any log line")
    end
    -- No captured line may contain the literal word "Bearer" either
    -- (structural defense: the GET log is method+URL only)
    for _, line in ipairs(Mocks._captured_prints) do
      assert.falsy(line:find("Bearer", 1, true),
        "Bearer keyword must not appear in any log line")
    end
  end)

  -- -------------------------------------------------------------------------
  -- D-25: shutdown / cleanup
  -- -------------------------------------------------------------------------

  it("shutdown nils the module-local Connection", function()
    -- Instrument Connection() to count calls.
    local call_count = 0
    local real_connection_factory = _G.Connection
    _G.Connection = function()
      call_count = call_count + 1
      return real_connection_factory()
    end

    -- First call: creates _conn (count becomes 1)
    Mocks.push_response({ content = '{"access_token":"AT"}' })
    M_http.post_form("https://oauth.zettle.com/token", { grant_type = "x" }, {})
    assert.equals(1, call_count)

    -- Shutdown releases _conn
    M_http.shutdown()

    -- Second call: creates a fresh _conn (count becomes 2)
    Mocks.push_response({ content = '{"access_token":"AT2"}' })
    M_http.post_form("https://oauth.zettle.com/token", { grant_type = "x" }, {})
    assert.equals(2, call_count)
  end)

  it("shutdown is idempotent", function()
    -- Calling shutdown twice must not error.
    M_http.shutdown()
    M_http.shutdown()
    assert.truthy(true)  -- reached without error
  end)

end)
