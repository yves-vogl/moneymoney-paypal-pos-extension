-- spec/build_version_substitution_spec.lua
-- BUILD-03 verification (D-73) — tools/build.lua substitutes the literal
-- `__VERSION__` token inside src/webbanking_header.lua's `WebBanking{...}`
-- block with a Lua-numeric version derived from $GITHUB_REF_NAME (CI),
-- `git describe --tags --exact-match` (local), or `dev-<short-sha>` fallback.
--
-- Test matrix (per 06-RESEARCH §3 + 06-PATTERNS item 22):
--   v1.0.0       -> 1.00
--   v1.2.3       -> 1.20  (patch digit dropped per MoneyMoney <major>.<two-digit-minor> convention)
--   v0.10.0      -> 0.10
--   v1.0.0-rc.1  -> 1.00  (rc + patch dropped — `^v(%d+)%.(%d+)` capture only)
--   unset env    -> 0.00 (no exact-match tag) OR a numeric local tag — both tolerated
--   --verify     -> reproducible across two consecutive invocations under same env
--
-- The spec drives `tools/build.lua` via `os.execute` and reads the resulting
-- `dist/paypal-pos.lua` (binary mode). No MoneyMoney mocks are required since
-- the spec exercises only the build pipeline.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- P6-R-08: drive tools/build.lua against a per-spec tmpfile via the
-- BUILD_OUT_PATH env var so spec invocations do not clobber the canonical
-- dist/paypal-pos.lua a developer or CI is inspecting. Each spec generates
-- its own path under os.tmpname(); cleanup happens in an after_each hook.

-- Track every tmp path the suite created so the after_each block can remove
-- both the main file and the build's TMP_PATH (.tmp) sidecar.
local _tmp_paths = {}

local function fresh_tmp_path()
  local p = os.tmpname()
  -- os.tmpname() on some platforms returns a path under /var/folders/...;
  -- the returned name is unique. Track it for cleanup.
  _tmp_paths[#_tmp_paths + 1] = p
  return p
end

-- Read an arbitrary path's content. Raises on missing file.
local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then
    error("build_version_substitution_spec: cannot read " .. tostring(path)
      .. ": " .. tostring(err))
  end
  local content = f:read("*a")
  f:close()
  return content
end

-- Run `tools/build.lua` with an env prefix and the tmp BUILD_OUT_PATH.
-- The env prefix is shell-prepended exactly as before (callers pass things
-- like "GITHUB_REF_NAME=v1.0.0" or "env -u GITHUB_REF_NAME").
-- Returns (ok, out_path) so callers can read the artifact at out_path.
local function run_build(env_prefix)
  local out_path = fresh_tmp_path()
  local cmd = (env_prefix or "")
    .. " BUILD_OUT_PATH=" .. out_path
    .. " lua tools/build.lua >/dev/null 2>&1"
  local ok = os.execute(cmd)
  return ok, out_path
end

-- ---------------------------------------------------------------------------
-- describe block
-- ---------------------------------------------------------------------------

describe("BUILD-03: __VERSION__ substitution (D-73)", function()

  -- Per P6-R-08: spec invocations of tools/build.lua write to per-test
  -- tmpfiles (via $BUILD_OUT_PATH), not to dist/paypal-pos.lua. This
  -- after_each removes every tmp file the suite created plus its .tmp
  -- sidecar so we never leak files under /var/folders or /tmp.
  after_each(function()
    for _, p in ipairs(_tmp_paths) do
      os.remove(p)
      os.remove(p .. ".tmp")
    end
    _tmp_paths = {}
  end)

  it("v1.0.0 substitutes to 1.00", function()
    local ok, out_path = run_build("GITHUB_REF_NAME=v1.0.0")
    assert.is_truthy(ok)
    local content = read_file(out_path)
    assert.is_truthy(content:find("version%s*=%s*1%.00,"),
      "expected `version = 1.00,` in artifact under GITHUB_REF_NAME=v1.0.0")
    assert.is_nil(content:find("__VERSION__"),
      "__VERSION__ token must be fully substituted")
  end)

  it("v1.2.3 substitutes to 1.20 (patch dropped)", function()
    local ok, out_path = run_build("GITHUB_REF_NAME=v1.2.3")
    assert.is_truthy(ok)
    local content = read_file(out_path)
    assert.is_truthy(content:find("version%s*=%s*1%.20,"),
      "expected `version = 1.20,` in artifact under GITHUB_REF_NAME=v1.2.3")
    assert.is_nil(content:find("__VERSION__"))
  end)

  it("v0.10.0 substitutes to 0.10", function()
    local ok, out_path = run_build("GITHUB_REF_NAME=v0.10.0")
    assert.is_truthy(ok)
    local content = read_file(out_path)
    assert.is_truthy(content:find("version%s*=%s*0%.10,"),
      "expected `version = 0.10,` in artifact under GITHUB_REF_NAME=v0.10.0")
    assert.is_nil(content:find("__VERSION__"))
  end)

  it("v1.0.0-rc.1 substitutes to 1.00 (rc + patch dropped)", function()
    local ok, out_path = run_build("GITHUB_REF_NAME=v1.0.0-rc.1")
    assert.is_truthy(ok)
    local content = read_file(out_path)
    assert.is_truthy(content:find("version%s*=%s*1%.00,"),
      "expected `version = 1.00,` for v1.0.0-rc.1 (rc dropped per ^v(%d+)%.(%d+))")
    assert.is_nil(content:find("__VERSION__"))
  end)

  it("dev fallback (unset GITHUB_REF_NAME) substitutes to 0.00 or local-tag-derived numeric", function()
    -- `env -u VAR` works on both BSD (macOS) and GNU (Linux) `env`.
    local ok, out_path = run_build("env -u GITHUB_REF_NAME")
    assert.is_truthy(ok)
    local content = read_file(out_path)
    assert.is_nil(content:find("__VERSION__"),
      "__VERSION__ token must be fully substituted even in dev fallback")
    -- Tolerate either dev fallback (`0.00`) OR a numeric local exact-match tag.
    -- The regex matches `version = <int>.<int>,` with any number of digits.
    assert.is_truthy(content:find("version%s*=%s*%d+%.%d+,"),
      "expected `version = N.NN,` (dev fallback 0.00 or local tag) in artifact")
  end)

  it("DEV BUILD banner appears for dev fallback and is absent for tagged builds", function()
    -- Tagged build: line 2 should NOT contain 'DEV BUILD'.
    local ok_tagged, tagged_path = run_build("GITHUB_REF_NAME=v1.0.0")
    assert.is_truthy(ok_tagged)
    local tagged = read_file(tagged_path)
    local lines_tagged = {}
    for line in tagged:gmatch("[^\n]*") do
      lines_tagged[#lines_tagged + 1] = line
      if #lines_tagged >= 4 then break end
    end
    assert.is_nil(lines_tagged[2] and lines_tagged[2]:find("DEV BUILD"),
      "DEV BUILD banner must NOT appear for tagged builds (got line 2: "
        .. tostring(lines_tagged[2]) .. ")")

    -- Dev fallback: line 2 should contain 'DEV BUILD' when version resolves to 0.00.
    -- Setting GITHUB_REF_NAME="dev-test" defeats tier 1 (no `^v%d` match), but on
    -- CI at a tagged commit `git describe --tags --exact-match` still resolves to
    -- the live tag and overrides via tier 2. Setting GIT_DIR=/nonexistent forces
    -- BOTH git invocations (tier 2 + tier 3) to fail; resolve_version_string then
    -- returns "dev-unknown" → version_to_number_string returns "0.00" → DEV BUILD
    -- banner is emitted. This makes the test stable on CI release builds too.
    local ok_dev, dev_path = run_build("GIT_DIR=/nonexistent GITHUB_REF_NAME=dev-test")
    assert.is_truthy(ok_dev)
    local dev = read_file(dev_path)
    local lines_dev = {}
    for line in dev:gmatch("[^\n]*") do
      lines_dev[#lines_dev + 1] = line
      if #lines_dev >= 4 then break end
    end
    assert.is_truthy(lines_dev[2] and lines_dev[2]:find("DEV BUILD"),
      "DEV BUILD banner must appear on line 2 for dev fallback (got line 2: "
        .. tostring(lines_dev[2]) .. ")")
  end)

  it("--verify is reproducible per-tag (two consecutive invocations exit 0)", function()
    -- --verify reads OUTPUT_PATH/TMP_PATH from build.lua's module state.
    -- Route both through BUILD_OUT_PATH so the verify pair also lands
    -- on tmpfiles instead of dist/.
    local out_path = fresh_tmp_path()
    local cmd = "GITHUB_REF_NAME=v1.0.0 BUILD_OUT_PATH=" .. out_path
      .. " lua tools/build.lua --verify >/dev/null 2>&1"
    local ok1 = os.execute(cmd)
    local ok2 = os.execute(cmd)
    assert.is_truthy(ok1, "first --verify run must succeed for GITHUB_REF_NAME=v1.0.0")
    assert.is_truthy(ok2, "second --verify run must succeed for GITHUB_REF_NAME=v1.0.0")
  end)

end)
