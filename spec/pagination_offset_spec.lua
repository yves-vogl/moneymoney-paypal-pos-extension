-- spec/pagination_offset_spec.lua
-- Covers: M_pagination.offset_iterate sibling iterator (Phase 4 Plan 04-02, D-48,
-- RESEARCH §1.6 termination semantics). Does NOT touch the Phase-3 cursor iterator.
--
-- RED in Task 1: M_pagination.offset_iterate does not yet exist; tests fail
-- on is_function check. Task 2 (GREEN) lands the impl.

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("pagination_offset_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- luacheck: globals M_pagination

describe("M_pagination.offset_iterate", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  it("terminates after one fetch when first page is shorter than limit", function()
    assert.is_function(M_pagination.offset_iterate,
      "M_pagination.offset_iterate must be a function (Task 2 GREEN)")
    local _, page = Fixtures.load("finance/finance_multi_page_2")  -- 2 records, < limit
    local call_index = 0
    local function fetch_fn(_params) -- luacheck: ignore 431
      call_index = call_index + 1
      return page, 200, "{}"
    end
    local all, err = M_pagination.offset_iterate(fetch_fn, { offset = 0, limit = 1000 })
    assert.is_nil(err, "no error expected")
    assert.equals(2, #all, "should accumulate the 2 records")
    assert.equals(1, call_index, "should fetch exactly once (short page terminates)")
  end)

  it("terminates after second fetch when first page has exactly `limit` records and second is shorter", function()
    assert.is_function(M_pagination.offset_iterate)
    local _, page1 = Fixtures.load("finance/finance_multi_page_1")  -- 5 records
    local _, page2 = Fixtures.load("finance/finance_multi_page_2")  -- 2 records (< limit)
    local pages = { page1, page2 }
    local call_index = 0
    local seen_offsets = {}
    local function fetch_fn(params)
      call_index = call_index + 1
      seen_offsets[#seen_offsets + 1] = params.offset
      return pages[call_index], 200, "{}"
    end
    -- Inject limit=5 so finance_multi_page_1 (5 records) == limit, triggering offset++
    local all, err = M_pagination.offset_iterate(fetch_fn, { offset = 0, limit = 5 })
    assert.is_nil(err)
    assert.equals(7, #all, "should accumulate 5 + 2 = 7 records")
    assert.equals(2, call_index, "should fetch exactly twice")
    assert.equals(0, seen_offsets[1], "first call must have offset=0")
    assert.equals(5, seen_offsets[2], "second call must have offset=5 (offset += limit)")
  end)

  it("returns (nil, err) when fetch_page_fn surfaces an HTTP error mid-pagination", function()
    assert.is_function(M_pagination.offset_iterate)
    local function fetch_fn(_params) -- luacheck: ignore 431
      return nil, 500, "{\"error\":\"upstream\"}"
    end
    local all, err = M_pagination.offset_iterate(fetch_fn, { offset = 0, limit = 1000 })
    assert.is_nil(all, "no records on error")
    assert.is_string(err, "error string must be returned")
    assert.is_truthy(err:find("500", 1, true),
      "error must mention status 500, got: " .. tostring(err))
  end)

  it("fires MAX_PAGES guard after 50 full-limit pages", function()
    assert.is_function(M_pagination.offset_iterate)
    -- Build a synthetic page of exactly `limit` records so the iterator never sees
    -- a short page and the MAX_PAGES guard is the only termination path.
    local LIMIT = 5
    local function build_full_page()
      local records = {}
      for i = 1, LIMIT do
        records[i] = {
          timestamp = "2026-06-01T10:00:00.000+0000",
          amount = 100,
          originatorTransactionType = "PAYMENT",
          originatingTransactionUuid = "uuid-" .. tostring(i),
        }
      end
      return { data = records }
    end
    local call_index = 0
    local function fetch_fn(_params) -- luacheck: ignore 431
      call_index = call_index + 1
      return build_full_page(), 200, "{}"
    end
    local all, err = M_pagination.offset_iterate(fetch_fn, { offset = 0, limit = LIMIT })
    assert.is_nil(all, "must return nil records when guard fires")
    assert.is_string(err, "must return error string")
    assert.is_truthy(err:find("Netzwerk", 1, true) or err:find("max", 1, true),
      "error must mention max-pages, got: " .. tostring(err))
    -- The guard triggers AFTER MAX_PAGES iterations; we expect exactly 50 fetches.
    assert.equals(50, call_index,
      "expected exactly 50 fetch calls before guard fires, got: " .. tostring(call_index))
  end)

  it("does NOT mutate the caller's initial_params table", function()
    assert.is_function(M_pagination.offset_iterate)
    local _, page = Fixtures.load("finance/finance_multi_page_2")
    local function fetch_fn(_params) -- luacheck: ignore 431
      return page, 200, "{}"
    end
    local caller_params = { offset = 0, limit = 1000, custom_marker = "untouched" }
    local snapshot = {}
    for k, v in pairs(caller_params) do snapshot[k] = v end
    M_pagination.offset_iterate(fetch_fn, caller_params)
    for k, v in pairs(snapshot) do
      assert.equals(v, caller_params[k],
        "caller_params['" .. k .. "'] mutated from " .. tostring(v) ..
        " to " .. tostring(caller_params[k]))
    end
    -- And no extra keys leaked into the caller's table either
    local caller_keys = 0
    for _ in pairs(caller_params) do caller_keys = caller_keys + 1 end
    local snap_keys = 0
    for _ in pairs(snapshot) do snap_keys = snap_keys + 1 end
    assert.equals(snap_keys, caller_keys,
      "caller_params key count changed (snapshot=" .. snap_keys ..
      ", after=" .. caller_keys .. ")")
  end)

end)
