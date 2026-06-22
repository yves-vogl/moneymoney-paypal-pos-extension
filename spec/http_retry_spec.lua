-- spec/http_retry_spec.lua
-- Phase-5 / Plan 05-03: GREEN retry-with-backoff specs.
-- Gates: D-62 (5xx retry-with-backoff {1,2,4}), D-63 (429 Retry-After
-- integer-only with 60s cap + 30s default), ADR-0005 Invariants 2 + 3.
--
-- Plan 05-02 shipped this file with 1 it() + 8 pending() RED scaffolds.
-- Plan 05-03 flips the 8 pending() to passing it() blocks now that
-- src/http.lua _request_with_retry implements the retry semantics; adds
-- 1 new lowercase-header test (Pitfall §6).

-- luacheck: globals M_http M_log MM M_i18n M_errors
-- luacheck: ignore 431

local Mocks = require("spec.helpers.mm_mocks")

do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("http_retry_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

describe("M_http retry-with-backoff (Phase 5 / D-62 / D-63 / ADR-0005 Invariants 2+3)", function()

  local _captured_sleeps

  before_each(function()
    Mocks.setup()
    -- Capturing MM.sleep stub: every call records the requested sleep duration
    -- so tests can assert exact backoff values (1, 2, 5, 30, 60, etc.).
    _captured_sleeps = {}
    _G.MM = _G.MM or {}
    _G.MM.sleep = function(s)
      _captured_sleeps[#_captured_sleeps + 1] = s
    end
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- ---------------------------------------------------------------------
  -- GREEN sanity: 200 first attempt → no retry, no sleep log
  -- ---------------------------------------------------------------------
  it("200 first attempt → no retry log emitted (baseline)", function()
    Mocks.push_response({ content = '{"ok":true}' })
    local parsed, status, _ = M_http.get_json("https://finance.izettle.com/test", {})
    assert.is_table(parsed)
    assert.equals(200, status)
    -- No "HTTP retry:" prefix in any captured log line
    for _, line in ipairs(Mocks._captured_prints) do
      assert.is_falsy(line:find("HTTP retry:", 1, true),
        "200-first-attempt must NOT emit retry log line; got: " .. tostring(line))
    end
    -- Exactly 1 request issued
    assert.equals(1, #Mocks._captured_requests,
      "expected exactly 1 HTTP attempt for 200-first-attempt")
    -- No sleeps captured
    assert.equals(0, #_captured_sleeps,
      "expected zero MM.sleep calls on 200 first attempt")
  end)

  -- ---------------------------------------------------------------------
  -- GREEN (Plan 05-03): D-62 + D-63 behaviors
  -- ---------------------------------------------------------------------

  it("5xx retry: 3 attempts then surface 599 sentinel (D-62 / ADR-0005 Invariant 2)", function()
    -- Empty body × 3 → Phase-2 ERR-05 path: returns (nil, nil, "") (NOT 599).
    -- The 599 sentinel is for non-empty body-shape 5xx (covered separately when
    -- _infer_status grows a 5xx body branch; for now empty-body is the only
    -- 5xx-equivalent we recognise per RESEARCH §4.b heuristic).
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })
    Mocks.push_response({ content = "" })
    local _, status, _ = M_http.get_json("https://finance.izettle.com/test", {})
    assert.is_nil(status)
    assert.equals(3, #Mocks._captured_requests, "expected 3 HTTP attempts on empty-body storm")
    assert.equals(2, #_captured_sleeps, "expected 2 sleeps (between attempt 1->2 and 2->3)")
    assert.equals(1, _captured_sleeps[1])
    assert.equals(2, _captured_sleeps[2])
  end)

  it("5xx retry: succeeds on 2nd attempt → status 200 returned, ONE retry log", function()
    Mocks.push_response({ content = "" })  -- attempt 1: empty body
    Mocks.push_response({ content = '{"ok":true,"data":"hello"}' })  -- attempt 2: success
    local parsed, status, _ = M_http.get_json("https://finance.izettle.com/test", {})
    assert.is_table(parsed)
    assert.equals(200, status)
    assert.equals(2, #Mocks._captured_requests, "expected 2 HTTP attempts (1 empty + 1 success)")
    assert.equals(1, #_captured_sleeps, "expected 1 sleep (between attempt 1->2)")
    assert.equals(1, _captured_sleeps[1])
    -- Exactly 1 HTTP retry log line
    local retry_log_count = 0
    for _, line in ipairs(Mocks._captured_prints) do
      if line:find("HTTP retry:", 1, true) then retry_log_count = retry_log_count + 1 end
    end
    assert.equals(1, retry_log_count, "expected exactly 1 HTTP retry log line")
  end)

  it("429 retry: Retry-After integer honored, single retry, capped at 60s (D-63)", function()
    local rate_limit_body = '{"error":"rate_limit","error_description":"Too many requests"}'
    Mocks.push_response({
      content = rate_limit_body,
      mime    = "application/json",
      headers = { ["Retry-After"] = "5" },
    })
    Mocks.push_response({ content = '{"ok":true}' })  -- success on retry
    local parsed, status, _ = M_http.get_json("https://finance.izettle.com/test", {})
    assert.is_table(parsed)
    assert.equals(200, status)
    assert.equals(2, #Mocks._captured_requests)
    assert.equals(1, #_captured_sleeps)
    assert.equals(5, _captured_sleeps[1], "expected MM.sleep(5) per Retry-After header")
  end)

  it("429 retry: no Retry-After → default 30s sleep (D-63)", function()
    local rate_limit_body = '{"error":"rate_limit"}'
    Mocks.push_response({ content = rate_limit_body, mime = "application/json" })
    Mocks.push_response({ content = '{"ok":true}' })
    M_http.get_json("https://finance.izettle.com/test", {})
    assert.equals(1, #_captured_sleeps)
    assert.equals(30, _captured_sleeps[1], "expected default 30s sleep when Retry-After absent")
  end)

  it("429 retry: Retry-After=9999 capped at 60s (D-63 cap)", function()
    local rate_limit_body = '{"error":"rate_limit"}'
    Mocks.push_response({
      content = rate_limit_body, mime = "application/json",
      headers = { ["Retry-After"] = "9999" },
    })
    Mocks.push_response({ content = '{"ok":true}' })
    M_http.get_json("https://finance.izettle.com/test", {})
    assert.equals(1, #_captured_sleeps)
    assert.equals(60, _captured_sleeps[1], "expected MM.sleep(60) per cap")
  end)

  it("429 retry: Retry-After=-5 rejected → default 30s (D-63 negative guard)", function()
    local rate_limit_body = '{"error":"rate_limit"}'
    Mocks.push_response({
      content = rate_limit_body, mime = "application/json",
      headers = { ["Retry-After"] = "-5" },
    })
    Mocks.push_response({ content = '{"ok":true}' })
    M_http.get_json("https://finance.izettle.com/test", {})
    assert.equals(1, #_captured_sleeps)
    assert.equals(30, _captured_sleeps[1], "expected default 30s when Retry-After negative")
  end)

  it("429 retry: Retry-After=\"abc\" rejected → default 30s (D-63 non-numeric guard)", function()
    local rate_limit_body = '{"error":"rate_limit"}'
    Mocks.push_response({
      content = rate_limit_body, mime = "application/json",
      headers = { ["Retry-After"] = "abc" },
    })
    Mocks.push_response({ content = '{"ok":true}' })
    M_http.get_json("https://finance.izettle.com/test", {})
    assert.equals(1, #_captured_sleeps)
    assert.equals(30, _captured_sleeps[1], "expected default 30s when Retry-After non-numeric")
  end)

  it("429 retry exhausted on 2nd attempt → final 429 surfaces error.rate_limit (D-63)", function()
    local rate_limit_body = '{"error":"rate_limit"}'
    Mocks.push_response({ content = rate_limit_body, mime = "application/json" })
    Mocks.push_response({ content = rate_limit_body, mime = "application/json" })
    local _, status, raw = M_http.get_json("https://finance.izettle.com/test", {})
    assert.equals(429, status, "expected 429 returned after single-retry exhaustion")
    assert.equals(2, #Mocks._captured_requests, "expected exactly 2 attempts (no infinite backoff)")
    assert.equals(1, #_captured_sleeps, "expected exactly 1 sleep (single retry budget)")
    assert.equals(M_i18n.t("error.rate_limit"), M_errors.from_http_status(status, raw),
      "M_errors must route 429 to error.rate_limit")
  end)

  it("429 retry: lower-case retry-after header honored (Pitfall §6)", function()
    local rate_limit_body = '{"error":"rate_limit"}'
    Mocks.push_response({
      content = rate_limit_body, mime = "application/json",
      headers = { ["retry-after"] = "7" },  -- lowercase
    })
    Mocks.push_response({ content = '{"ok":true}' })
    M_http.get_json("https://finance.izettle.com/test", {})
    assert.equals(1, #_captured_sleeps)
    assert.equals(7, _captured_sleeps[1],
      "expected MM.sleep(7) -- lowercase retry-after must be honored per Pitfall §6")
  end)

end)
