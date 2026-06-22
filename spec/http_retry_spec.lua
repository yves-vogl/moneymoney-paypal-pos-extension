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

  it("5xx-equivalent empty-body storm: 3 attempts then (nil,nil,raw) → error.network (D-62 / ERR-05)", function()
    -- WR-02 (05-06): renamed from the misleading "5xx retry: 3 attempts then
    -- surface 599 sentinel" title. Empty body × 3 is the Phase-2 ERR-05 path
    -- (DNS / connect / timeout / 5xx-without-body) and returns (nil, nil, "")
    -- — NOT the 599 sentinel. The genuine 599 sentinel emission via 5xx body
    -- shapes (server_error / service_unavailable / server_busy) is now gated
    -- by the new "5xx body: server_error × 3 → 599 sentinel" test below.
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

  -- -------------------------------------------------------------------------
  -- 05-06 fix-batch (S-02 / WR-01 / S-05): 599 sentinel emission contract
  -- -------------------------------------------------------------------------
  -- REVIEW WR-01 / SECURITY S-02 found the 5xx retry branch unreachable
  -- because _infer_status never returned a status in [500, 598]. This block
  -- gates the now-live 5xx-body classification: server_error / internal_error
  -- → 500; service_unavailable / temporarily_unavailable → 503; server_busy
  -- → 599 directly. After _MAX_ATTEMPTS the loop emits the 599 sentinel which
  -- M_errors.from_http_status maps to error.server_busy. S-05 (sentinel
  -- collision) is mitigated by routing both inferred 599 and exhausted-5xx
  -- 599 to the same error.server_busy string — no semantic ambiguity.
  it("5xx body: server_error × 3 → 599 sentinel surfaces error.server_busy (S-02 / WR-01)", function()
    local body = '{"error":"server_error","error_description":"upstream failure"}'
    Mocks.push_response({ content = body, mime = "application/json" })
    Mocks.push_response({ content = body, mime = "application/json" })
    Mocks.push_response({ content = body, mime = "application/json" })
    local parsed, status, raw = M_http.get_json("https://finance.izettle.com/test", {})
    assert.is_table(parsed)
    assert.equals(599, status,
      "expected 599 sentinel after 3-attempt 5xx body-shape exhaust")
    assert.equals(3, #Mocks._captured_requests,
      "expected 3 HTTP attempts (1 original + 2 retries)")
    assert.equals(2, #_captured_sleeps,
      "expected 2 sleeps (between attempts 1->2 and 2->3)")
    assert.equals(1, _captured_sleeps[1])
    assert.equals(2, _captured_sleeps[2])
    assert.equals(M_i18n.t("error.server_busy"), M_errors.from_http_status(status, raw),
      "M_errors must route 599 sentinel to error.server_busy")
  end)

  it("5xx body: service_unavailable inferred as 503 → retried then 599 surfaces (S-02)", function()
    local body = '{"error":"service_unavailable"}'
    Mocks.push_response({ content = body, mime = "application/json" })
    Mocks.push_response({ content = body, mime = "application/json" })
    Mocks.push_response({ content = body, mime = "application/json" })
    local _, status, raw = M_http.get_json("https://finance.izettle.com/test", {})
    assert.equals(599, status,
      "expected 599 sentinel after 3-attempt service_unavailable storm")
    assert.equals(M_i18n.t("error.server_busy"), M_errors.from_http_status(status, raw))
  end)

  it("5xx body: server_error → recovers on 2nd attempt → status 200 (S-02)", function()
    Mocks.push_response({ content = '{"error":"server_error"}', mime = "application/json" })
    Mocks.push_response({ content = '{"ok":true}', mime = "application/json" })
    local parsed, status, _ = M_http.get_json("https://finance.izettle.com/test", {})
    assert.is_table(parsed)
    assert.equals(200, status, "expected recovery to surface 200")
    assert.equals(1, #_captured_sleeps, "expected one sleep between attempt 1 and 2")
    assert.equals(1, _captured_sleeps[1], "expected backoff[1] = 1s")
  end)

  -- -------------------------------------------------------------------------
  -- 05-06 fix-batch (S-01 / WR-03): wall-clock budget abort
  -- -------------------------------------------------------------------------
  -- REVIEW WR-03 / SECURITY S-01 noticed that the shared attempt counter does
  -- not bound total wait time. Adversarial sequence [429 Retry-After=60,
  -- empty, empty] sleeps ~62s on a single endpoint; across 4 endpoints
  -- worst-case ~248s, exceeding MoneyMoney's per-call timeout (~30-60s per
  -- ADR-0003). The fix introduces _WALL_CLOCK_CAP (60s): before each
  -- _sleep_with_log call we check `(elapsed + sleep_seconds) > cap` and abort,
  -- returning whatever the most-recent attempt's tuple was so the caller sees
  -- a deterministic outcome (not silently retried).
  it("wall-clock budget: [429 Retry-After=60, empty, empty] aborts after first sleep (S-01/WR-03)", function()
    -- Stub os.time so the elapsed-budget check is deterministic.
    -- Sequence: attempt=1 takes 0s elapsed -> sleep(60); after sleep elapsed=60s;
    -- attempt=2 empty body; trying to sleep(_BACKOFF_SECONDS[2]=2) would push
    -- elapsed to 62 > _WALL_CLOCK_CAP=60 -> abort and return (nil, nil, "").
    local _saved_os_time = os.time
    local _t = 0
    -- Each MM.sleep call advances the simulated clock by the requested seconds.
    _G.MM.sleep = function(s)
      _captured_sleeps[#_captured_sleeps + 1] = s
      _t = _t + s
    end
    os.time = function() return _t end -- luacheck: ignore

    local rate_limit_body = '{"error":"rate_limit"}'
    Mocks.push_response({
      content = rate_limit_body, mime = "application/json",
      headers = { ["Retry-After"] = "60" },
    })
    Mocks.push_response({ content = "" })  -- attempt 2: empty body (5xx-equivalent)
    Mocks.push_response({ content = "" })  -- attempt 3: would-be, but cap aborts before this

    local parsed, status, raw = M_http.get_json("https://finance.izettle.com/test", {})

    os.time = _saved_os_time -- luacheck: ignore

    -- After the wall-clock abort, we should return whatever the last attempt
    -- produced (attempt 2's empty body → (nil, nil, "")).
    assert.is_nil(parsed, "expected nil parsed after wall-clock abort on empty body")
    assert.is_nil(status, "expected nil status after wall-clock abort (ERR-05 path)")
    assert.equals("", raw, "expected empty raw body after wall-clock abort")

    -- At most TWO MM.sleep calls (one for the 429 + zero or one for the
    -- empty-body retry that the cap aborts). With Retry-After=60 already at
    -- cap, the second sleep MUST NOT fire -> exactly 1 sleep.
    assert.equals(1, #_captured_sleeps,
      "expected exactly 1 MM.sleep call (60s for 429); the wall-clock cap "
      .. "must abort before the second sleep")
    local total = 0
    for _, s in ipairs(_captured_sleeps) do total = total + s end
    assert.is_true(total <= 60,
      "expected total sleep <= 60s wall-clock cap, got " .. tostring(total))

    -- Only 2 attempts issued (the 3rd request must not happen — the cap aborts
    -- after attempt 2's empty body, before sleeping for attempt 3).
    assert.equals(2, #Mocks._captured_requests,
      "expected exactly 2 HTTP attempts (cap aborts before attempt 3)")
  end)

  it("wall-clock budget: 5xx body × 3 still completes within cap (budget non-interference)", function()
    -- Sanity check: a normal 5xx storm where each sleep is small (1s + 2s = 3s
    -- elapsed) must NOT trip the cap — the loop should still emit 599 after
    -- the documented 3 attempts.
    local _saved_os_time = os.time
    local _t = 0
    _G.MM.sleep = function(s)
      _captured_sleeps[#_captured_sleeps + 1] = s
      _t = _t + s
    end
    os.time = function() return _t end -- luacheck: ignore

    local body = '{"error":"server_error"}'
    Mocks.push_response({ content = body, mime = "application/json" })
    Mocks.push_response({ content = body, mime = "application/json" })
    Mocks.push_response({ content = body, mime = "application/json" })

    local _, status, _ = M_http.get_json("https://finance.izettle.com/test", {})

    os.time = _saved_os_time -- luacheck: ignore

    assert.equals(599, status, "expected 599 sentinel; cap should not trigger on small sleeps")
    assert.equals(2, #_captured_sleeps, "expected 2 sleeps (1s + 2s) under cap")
  end)

end)
