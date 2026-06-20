-- spec/dst_table_spec.lua
-- RED pending scaffold for D-36 / SALE-04: EU-DST boundary correctness of
-- _to_berlin_local_time (implementation lands in src/mapping.lua, Wave 2,
-- Plan 03-03). Wave 0 stubs the pending test names so Wave 2 only fills bodies.
--
-- Two locked acceptance timestamps from 03-RESEARCH.md §2b:
--   summer: 2026-06-19T23:55:00Z  -> CEST (+02:00) -> Berlin local 2026-06-20T01:55
--   winter: 2026-01-31T23:55:00Z  -> CET  (+01:00) -> Berlin local 2026-02-01T00:55
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so each test
-- starts with a clean global environment (pattern from spec/http_spec.lua L37-44).

-- luacheck: ignore 431

local Mocks = require("spec.helpers.mm_mocks")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("dst_table_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("DST table (D-36 / SALE-04)", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Sanity test (non-pending) — confirms dofile worked and M_mapping is present
  -- -------------------------------------------------------------------------

  it("M_mapping module table is exposed", function()
    assert.is_table(M_mapping)
  end)

  -- -------------------------------------------------------------------------
  -- Pending tests — Wave 2 (Plan 03-03) fills these bodies
  -- -------------------------------------------------------------------------

  pending("_to_berlin_local_time CEST summer offset 2026-06-19T23:55Z -> local 2026-06-20T01:55", function()
    -- Wave 2 expectation:
    -- POSIX(2026-06-19T23:55:00Z) = 1781913300
    -- Berlin local POSIX (+7200)  = 1781920500
    -- DST_TABLE[7] = {1774746000, 1792890000}  -- 2026 entry (summer_start_utc, summer_end_utc)
  end)

  pending("_to_berlin_local_time CET winter offset 2026-01-31T23:55Z -> local 2026-02-01T00:55", function()
    -- Wave 2 expectation:
    -- POSIX(2026-01-31T23:55:00Z) = 1769903700
    -- Berlin local POSIX (+3600)  = 1769907300
    -- DST_TABLE[7] = {1774746000, 1792890000}  -- 2026 entry (summer_start_utc, summer_end_utc)
  end)

  pending("_to_berlin_local_time DST table covers years 2020..2040 boundaries", function()
  end)

  pending("_to_berlin_local_time exact start-boundary timestamp picks summer offset", function()
  end)

  pending("_to_berlin_local_time exact end-boundary timestamp picks winter offset", function()
  end)

end)
