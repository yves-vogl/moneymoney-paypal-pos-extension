-- spec/helpers/fixtures.lua
-- Fixture loader for recorded API responses stored under spec/fixtures/*.json.
-- Later phases add real fixture files; this helper exists so specs can call
-- Fixtures.load("name") without revisiting the helpers directory.
--
-- Usage:
--   local Fixtures = require("spec.helpers.fixtures")
--   local raw, decoded = Fixtures.load("purchase_list")
--   -- raw    : string — raw JSON bytes from the file
--   -- decoded: table  — dkjson-decoded Lua table

local dkjson = require("dkjson")

local Fixtures = {}

-- Fixtures.load(name) -> raw_string, decoded_table
-- Opens spec/fixtures/<name>.json relative to the project root.
-- Errors with a clear message when the file is missing.
function Fixtures.load(name)
  local path = "spec/fixtures/" .. name .. ".json"
  local f, err = io.open(path, "r")
  if not f then
    error("fixtures.load: cannot open '" .. path .. "': " .. tostring(err))
  end
  local raw = f:read("*a")
  f:close()

  local decoded, _, decode_err = dkjson.decode(raw)
  if decode_err then
    error("fixtures.load: JSON decode error in '" .. path .. "': " .. tostring(decode_err))
  end

  return raw, decoded
end

return Fixtures
