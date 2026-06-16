-- spec/build_spec.lua
-- Tests for the tools/build.lua amalgamator.
-- Coverage: BUILD-01, BUILD-02, SEC-04, H8
--
-- Negative-gate design (tests 3-5):
--   For each gate, we:
--     1. Write a temporary source file under src/ that trips the gate.
--     2. Append its module name to a copy of tools/manifest.txt (by temporarily
--        replacing the real manifest).
--     3. Run lua tools/build.lua; capture stdout+stderr+exit code.
--     4. Restore the original manifest before any assertion can fail.
--   The restore happens in after_each — even if the it() body errors — so the
--   working tree is always left clean.

-- luacheck: globals _manifest_backup _debug_probe _require_probe _execute_probe

local _manifest_path     = "tools/manifest.txt"
local _dist_path         = "dist/paypal-pos.lua"
local _tmp_path          = "dist/paypal-pos.lua.tmp"

-- Read the original manifest once at suite load time so after_each can restore it.
local _manifest_original
do
  local f = assert(io.open(_manifest_path, "r"), "cannot read " .. _manifest_path)
  _manifest_original = f:read("*a")
  f:close()
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- write_file(path, content): create or overwrite a file.
local function write_file(path, content)
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end

-- run_build(extra_args): run lua tools/build.lua, optionally with extra_args.
-- Returns: output (stdout+stderr combined), exit_ok (bool), exit_code (int).
local function run_build(extra_args)
  local cmd = "lua tools/build.lua" .. (extra_args or "") .. " 2>&1; echo __EXIT__:$?"
  local handle = io.popen(cmd, "r")
  local raw = handle:read("*a")
  handle:close()
  local output    = raw:gsub("\n?__EXIT__:%d+\n?$", "")
  local exit_code = tonumber(raw:match("__EXIT__:(%d+)"))
  return output, exit_code == 0, exit_code
end

-- restore_manifest(): write back the saved original manifest content.
local function restore_manifest()
  write_file(_manifest_path, _manifest_original)
end

-- inject_probe(name, content): write src/<name>.lua with content and append
-- <name> to tools/manifest.txt.
local function inject_probe(name, content)
  write_file("src/" .. name .. ".lua", content)
  write_file(_manifest_path, _manifest_original .. name .. "\n")
end

-- remove_probe(name): remove src/<name>.lua (ignore errors if already gone).
local function remove_probe(name)
  os.remove("src/" .. name .. ".lua")
end

-- ---------------------------------------------------------------------------
-- Suite
-- ---------------------------------------------------------------------------

describe("tools/build.lua", function()

  before_each(function()
    -- Remove any stale output so tests start from a clean slate.
    os.remove(_dist_path)
    os.remove(_tmp_path)
  end)

  after_each(function()
    -- Always restore the original manifest; remove any probe source files.
    restore_manifest()
    remove_probe("_debug_probe")
    remove_probe("_require_probe")
    remove_probe("_execute_probe")
    os.remove(_tmp_path)
  end)

  -- [BUILD-01] ---------------------------------------------------------------
  it("produces dist/paypal-pos.lua", function()
    local _, ok = run_build("")
    assert.is_true(ok, "build should exit 0")
    local f = io.open(_dist_path, "rb")
    assert.is_not_nil(f, "dist/paypal-pos.lua should exist after build")
    if f then f:close() end
  end)

  -- [BUILD-02] ---------------------------------------------------------------
  it("--verify confirms byte-identical second build", function()
    local output, ok = run_build(" --verify")
    assert.is_true(ok, "--verify should exit 0 (output: " .. tostring(output) .. ")")
    assert.is_truthy(output:find("OK: reproducible"),
      "--verify stdout should contain 'OK: reproducible' (got: " .. tostring(output) .. ")")
  end)

  -- [SEC-04] negative gate ---------------------------------------------------
  it("aborts when DEBUG = true exists outside a comment", function()
    inject_probe("_debug_probe", "DEBUG = true\n")

    local output, ok = run_build("")
    assert.is_false(ok, "build should fail when DEBUG = true is in a source file")
    assert.is_truthy(output:find("DEBUG = true"),
      "stderr should mention 'DEBUG = true' (got: " .. tostring(output) .. ")")
  end)

  -- [H8] banned call: require ------------------------------------------------
  it("aborts when a source calls require()", function()
    inject_probe("_require_probe", 'local x = require("dkjson")\n')

    local output, ok = run_build("")
    assert.is_false(ok, "build should fail when a source calls require()")
    assert.is_truthy(output:find("require%(") or output:find("require("),
      "stderr should mention require( (got: " .. tostring(output) .. ")")
  end)

  -- [H8] banned call: os.execute ---------------------------------------------
  it("aborts when a source calls os.execute()", function()
    inject_probe("_execute_probe", 'os.execute("ls")\n')

    local output, ok = run_build("")
    assert.is_false(ok, "build should fail when a source calls os.execute()")
    assert.is_truthy(output:find("os%.execute%(") or output:find("os.execute("),
      "stderr should mention os.execute( (got: " .. tostring(output) .. ")")
  end)

  -- [SEC-04] positive case ---------------------------------------------------
  it("artifact contains DEBUG = false", function()
    local _, ok = run_build("")
    assert.is_true(ok, "build should succeed")

    local f = assert(io.open(_dist_path, "r"), "dist/paypal-pos.lua should exist")
    local content = f:read("*a")
    f:close()

    assert.is_truthy(content:find("DEBUG = false"),
      "dist/paypal-pos.lua should contain 'DEBUG = false'")
  end)

end)
