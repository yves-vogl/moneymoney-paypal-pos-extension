-- spec/http_retry_spec.lua
-- Phase-5 / Plan 05-02 RED scaffold; Plan 05-03 turns GREEN.
-- Gates: D-62 (5xx retry-with-backoff {1,2,4}), D-63 (429 Retry-After
-- integer-only with 60s cap + 30s default), ADR-0005 Invariants 2 + 3.
--
-- Every retry-behavior it() block uses `pending()` so the suite passes
-- on this plan's commit; Plan 05-03 flips them to `it()` once src/http.lua
-- ships the retry loop. The sanity test (200-no-sleep) ships GREEN.

-- luacheck: globals M_http M_log MM
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

  before_each(function()
    Mocks.setup()
    -- IMPORTANT: stub MM.sleep to no-op so tests do not wait for real seconds.
    -- Production code uses MM.sleep(seconds) per ADR-0005; the mock is already
    -- a no-op at spec/helpers/mm_mocks.lua:233, but we re-stub defensively in case
    -- a future Mocks.setup variant changes the default.
    _G.MM = _G.MM or {}
    _G.MM.sleep = function(_) end
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
  end)

  -- ---------------------------------------------------------------------
  -- RED scaffolds for Plan 05-03 GREEN (D-62 + D-63 behaviors)
  -- ---------------------------------------------------------------------

  pending("5xx retry: 3 attempts then surface 599 sentinel (D-62 / ADR-0005 Invariant 2)", function()
    -- Plan 05-03: push 3 empty bodies → M_http retry loop fires 1s + 2s sleeps
    -- → returns (nil, 599, "") after 3rd empty body. Captured requests count == 3.
    -- Captured prints include exactly 2 "HTTP retry:" INFO lines (after attempt 1 and 2).
    error("Plan 05-03 GREEN: requires src/http.lua retry loop")
  end)

  pending("5xx retry: succeeds on 2nd attempt → status 200 returned, ONE retry log", function()
    -- Plan 05-03: push empty body + JSON success body. M_http sleeps 1s, retries, returns 200.
    -- Captured requests count == 2; captured prints include exactly 1 "HTTP retry:" line.
    error("Plan 05-03 GREEN: requires src/http.lua retry loop")
  end)

  pending("429 retry: Retry-After integer honored, single retry, capped at 60s (D-63)", function()
    -- Plan 05-03: push 429-shaped body with headers={Retry-After="5"}; push 200 second.
    -- Assert MM.sleep called with 5; final status 200 returned.
    error("Plan 05-03 GREEN: requires _parse_retry_after + retry loop")
  end)

  pending("429 retry: no Retry-After → default 30s sleep (D-63)", function()
    -- Plan 05-03: push 429 body with no headers; push 200 second.
    -- Assert MM.sleep called with 30; final status 200.
    error("Plan 05-03 GREEN: requires _parse_retry_after default 30s")
  end)

  pending("429 retry: Retry-After=9999 capped at 60s (D-63 cap)", function()
    -- Plan 05-03: push 429 with Retry-After=9999; push 200 second.
    -- Assert MM.sleep called with 60; final status 200.
    error("Plan 05-03 GREEN: requires _parse_retry_after cap")
  end)

  pending("429 retry: Retry-After=-5 rejected → default 30s (D-63 negative guard)", function()
    -- Plan 05-03: push 429 with Retry-After=-5; push 200 second.
    -- Assert MM.sleep called with 30 (negative rejected); final status 200.
    error("Plan 05-03 GREEN: requires _parse_retry_after negative guard")
  end)

  pending("429 retry: Retry-After=\"abc\" rejected → default 30s (D-63 non-numeric guard)", function()
    -- Plan 05-03: tonumber("abc") returns nil → 30s default.
    error("Plan 05-03 GREEN: requires _parse_retry_after tonumber guard")
  end)

  pending("429 retry exhausted on 2nd attempt → final 429 surfaces error.rate_limit (D-63)", function()
    -- Plan 05-03: push 429 + push 429 second; assert single retry only (no infinite backoff).
    -- Captured requests == 2; M_errors.from_http_status(429, raw) == M_i18n.t("error.rate_limit").
    error("Plan 05-03 GREEN: requires single-retry-per-refresh on 429")
  end)

end)
