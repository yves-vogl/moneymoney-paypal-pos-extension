-- spec/update_spec.lua
-- Phase 7 / D-83 — M_update unit tests.
--
-- Covers:
--   * pure semver helpers (_parse_tag, _is_newer)
--   * opt-out parser (_is_disabled)
--   * cache freshness logic
--   * check() with cached entries (no network)
--   * check() with stale cache + fetch_override
--   * check() suppression for DEV builds + invalid current_tag
--   * check() does NOT consume a Connection mock when opt-out is set

local Mocks = require("spec.helpers.mm_mocks")

local function load_dist()
  -- Build first to pick up any src/ changes
  local rc = os.execute("lua tools/build.lua >/dev/null 2>&1")
  assert(rc, "tools/build.lua failed")
  dofile("dist/paypal-pos.lua")
end

describe("M_update — semver helpers", function()
  before_each(function()
    Mocks.setup()
    load_dist()
  end)
  after_each(function()
    Mocks.teardown()
  end)

  it("_parse_tag accepts strict v<int>.<int>.<int>", function()
    assert.are.same({1, 0, 0}, M_update._parse_tag("v1.0.0"))
    assert.are.same({2, 13, 7}, M_update._parse_tag("v2.13.7"))
  end)

  it("_parse_tag rejects pre-release suffixes (rc/beta/alpha/dev)", function()
    assert.is_nil(M_update._parse_tag("v1.0.0-rc.1"))
    assert.is_nil(M_update._parse_tag("v1.0.0-beta.2"))
    assert.is_nil(M_update._parse_tag("v1.0.0-dev"))
    assert.is_nil(M_update._parse_tag("v1.0.0+build.5"))
  end)

  it("_parse_tag rejects garbage", function()
    assert.is_nil(M_update._parse_tag(nil))
    assert.is_nil(M_update._parse_tag(""))
    assert.is_nil(M_update._parse_tag("1.0.0"))      -- missing v prefix
    assert.is_nil(M_update._parse_tag("v1.0"))       -- missing patch
    assert.is_nil(M_update._parse_tag("vDEV"))
    assert.is_nil(M_update._parse_tag(42))
  end)

  it("_is_newer compares major then minor then patch", function()
    assert.is_true(M_update._is_newer("v1.0.0", "v2.0.0"))
    assert.is_true(M_update._is_newer("v1.0.0", "v1.1.0"))
    assert.is_true(M_update._is_newer("v1.0.0", "v1.0.1"))
    assert.is_false(M_update._is_newer("v1.0.0", "v1.0.0"))
    assert.is_false(M_update._is_newer("v1.0.1", "v1.0.0"))
    assert.is_false(M_update._is_newer("v2.0.0", "v1.99.99"))
  end)

  it("_is_newer returns false for invalid inputs", function()
    assert.is_false(M_update._is_newer("DEV", "v1.0.0"))
    assert.is_false(M_update._is_newer("v1.0.0", "v1.0.0-rc.1"))
    assert.is_false(M_update._is_newer(nil, nil))
  end)
end)

describe("M_update — opt-out parser", function()
  before_each(function() Mocks.setup(); load_dist() end)
  after_each(function() Mocks.teardown() end)

  it("treats empty / nil / non-string as ACTIVE", function()
    assert.is_false(M_update._is_disabled(nil))
    assert.is_false(M_update._is_disabled(""))
    assert.is_false(M_update._is_disabled(42))
    assert.is_false(M_update._is_disabled({}))
  end)

  it("treats aus/off/false/0/no/nein (any case + whitespace) as DISABLED", function()
    for _, v in ipairs({"aus", "AUS", " off ", "false", "FALSE", "0", "no", "nein"}) do
      assert.is_true(M_update._is_disabled(v),
        "expected '" .. tostring(v) .. "' to disable update-check")
    end
  end)

  it("treats other strings as ACTIVE", function()
    assert.is_false(M_update._is_disabled("aktiv"))
    assert.is_false(M_update._is_disabled("ja"))
    assert.is_false(M_update._is_disabled("true"))
    assert.is_false(M_update._is_disabled("1"))
  end)
end)

describe("M_update — cache freshness", function()
  before_each(function() Mocks.setup(); load_dist() end)
  after_each(function() Mocks.teardown() end)

  it("entry within TTL is fresh", function()
    assert.is_true(M_update._cache_is_fresh({checked_at = 1000}, 1000 + 100))
    assert.is_true(M_update._cache_is_fresh({checked_at = 1000}, 1000 + 86399))
  end)

  it("entry at/over TTL is stale", function()
    assert.is_false(M_update._cache_is_fresh({checked_at = 1000}, 1000 + 86400))
    assert.is_false(M_update._cache_is_fresh({checked_at = 1000}, 1000 + 100000))
  end)

  it("missing/invalid entry is stale", function()
    assert.is_false(M_update._cache_is_fresh(nil, 1000))
    assert.is_false(M_update._cache_is_fresh({}, 1000))
    assert.is_false(M_update._cache_is_fresh({checked_at = "garbage"}, 1000))
  end)
end)

describe("M_update.check — suppression cases", function()
  before_each(function() Mocks.setup(); load_dist() end)
  after_each(function() Mocks.teardown() end)

  it("returns nil for DEV builds", function()
    assert.is_nil(M_update.check({current_tag = "DEV", now_unix = 1000}))
  end)

  it("returns nil for nil/invalid current_tag", function()
    assert.is_nil(M_update.check({current_tag = nil, now_unix = 1000}))
    assert.is_nil(M_update.check({current_tag = "garbage", now_unix = 1000}))
    assert.is_nil(M_update.check({current_tag = "v1.0", now_unix = 1000}))
  end)

  it("returns nil when user opted out (any disable token)", function()
    -- Force fresh fetch path by clearing the cache.
    _G.LocalStorage.update_check = nil
    -- Stub fetch_override so any leak past the opt-out guard would
    -- surface as a non-nil return; we expect nil.
    local fetch = function() return "v9.9.9", "https://example/" end
    for _, v in ipairs({"aus", "off", "FALSE", "0"}) do
      assert.is_nil(M_update.check({
        current_tag = "v1.0.0", opt_out = v, now_unix = 1000,
        fetch_override = fetch,
      }))
    end
  end)
end)

describe("M_update.check — cache hits", function()
  before_each(function() Mocks.setup(); load_dist() end)
  after_each(function() Mocks.teardown() end)

  it("returns nil on fresh cache with same-or-older latest", function()
    _G.LocalStorage.update_check = {
      checked_at = 1000, latest_tag = "v1.0.0", html_url = "x",
    }
    assert.is_nil(M_update.check({
      current_tag = "v1.0.0", now_unix = 1100,
    }))
  end)

  it("returns notice on fresh cache with newer latest", function()
    _G.LocalStorage.update_check = {
      checked_at = 1000, latest_tag = "v1.0.1",
      html_url = "https://example.test/v1.0.1",
    }
    local msg = M_update.check({
      current_tag = "v1.0.0", now_unix = 1100,
    })
    assert.is_string(msg)
    assert.is_truthy(msg:find("v1.0.1"))
    assert.is_truthy(msg:find("v1.0.0"))
  end)

  it("does not call fetch on fresh cache", function()
    _G.LocalStorage.update_check = {
      checked_at = 1000, latest_tag = "v1.0.0", html_url = "x",
    }
    local called = false
    M_update.check({
      current_tag = "v1.0.0", now_unix = 1100,
      fetch_override = function() called = true; return "v9.9.9", "y" end,
    })
    assert.is_false(called, "fetch_override must not fire on fresh cache")
  end)
end)

describe("M_update.check — stale cache + fetch", function()
  before_each(function() Mocks.setup(); load_dist() end)
  after_each(function() Mocks.teardown() end)

  it("uses fetch_override and updates cache when stale", function()
    _G.LocalStorage.update_check = {
      checked_at = 1, latest_tag = "v1.0.0", html_url = "x",
    }
    local msg = M_update.check({
      current_tag = "v1.0.0",
      now_unix    = 1 + 100000,  -- past TTL
      fetch_override = function() return "v1.0.5", "https://r/v1.0.5" end,
    })
    assert.is_string(msg)
    assert.is_truthy(msg:find("v1.0.5"))
    assert.equals("v1.0.5", _G.LocalStorage.update_check.latest_tag)
    assert.equals(1 + 100000, _G.LocalStorage.update_check.checked_at)
  end)

  it("soft-caches network failure (nil returned, no infinite retries)", function()
    _G.LocalStorage.update_check = nil
    local msg = M_update.check({
      current_tag    = "v1.0.0",
      now_unix       = 1000,
      fetch_override = function() return nil end,
    })
    assert.is_nil(msg)
    assert.equals(1000, _G.LocalStorage.update_check.checked_at,
      "failure must still update checked_at so we do not hammer the API")
    assert.is_nil(_G.LocalStorage.update_check.latest_tag)
  end)
end)
