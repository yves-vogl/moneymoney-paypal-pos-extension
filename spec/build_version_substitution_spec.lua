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

-- Read dist/paypal-pos.lua and return its content. Raises on missing file.
local function read_dist()
  local f, err = io.open("dist/paypal-pos.lua", "rb")
  if not f then
    error("build_version_substitution_spec: cannot read dist/paypal-pos.lua: "
      .. tostring(err))
  end
  local content = f:read("*a")
  f:close()
  return content
end

-- Run `tools/build.lua` with an optional env prefix. Returns the truthy/falsy
-- result of `os.execute` so callers can `assert.is_truthy(...)` it.
local function run_build(env_prefix)
  local cmd = (env_prefix or "") .. " lua tools/build.lua >/dev/null 2>&1"
  return os.execute(cmd)
end

-- ---------------------------------------------------------------------------
-- describe block
-- ---------------------------------------------------------------------------

describe("BUILD-03: __VERSION__ substitution (D-73)", function()

  it("v1.0.0 substitutes to 1.00", function()
    local ok = run_build("GITHUB_REF_NAME=v1.0.0")
    assert.is_truthy(ok)
    local content = read_dist()
    assert.is_truthy(content:find("version%s*=%s*1%.00,"),
      "expected `version = 1.00,` in dist/paypal-pos.lua under GITHUB_REF_NAME=v1.0.0")
    assert.is_nil(content:find("__VERSION__"),
      "__VERSION__ token must be fully substituted")
  end)

  it("v1.2.3 substitutes to 1.20 (patch dropped)", function()
    local ok = run_build("GITHUB_REF_NAME=v1.2.3")
    assert.is_truthy(ok)
    local content = read_dist()
    assert.is_truthy(content:find("version%s*=%s*1%.20,"),
      "expected `version = 1.20,` in dist/paypal-pos.lua under GITHUB_REF_NAME=v1.2.3")
    assert.is_nil(content:find("__VERSION__"))
  end)

  it("v0.10.0 substitutes to 0.10", function()
    local ok = run_build("GITHUB_REF_NAME=v0.10.0")
    assert.is_truthy(ok)
    local content = read_dist()
    assert.is_truthy(content:find("version%s*=%s*0%.10,"),
      "expected `version = 0.10,` in dist/paypal-pos.lua under GITHUB_REF_NAME=v0.10.0")
    assert.is_nil(content:find("__VERSION__"))
  end)

  it("v1.0.0-rc.1 substitutes to 1.00 (rc + patch dropped)", function()
    local ok = run_build("GITHUB_REF_NAME=v1.0.0-rc.1")
    assert.is_truthy(ok)
    local content = read_dist()
    assert.is_truthy(content:find("version%s*=%s*1%.00,"),
      "expected `version = 1.00,` for v1.0.0-rc.1 (rc dropped per ^v(%d+)%.(%d+))")
    assert.is_nil(content:find("__VERSION__"))
  end)

  it("dev fallback (unset GITHUB_REF_NAME) substitutes to 0.00 or local-tag-derived numeric", function()
    -- `env -u VAR` works on both BSD (macOS) and GNU (Linux) `env`.
    local ok = run_build("env -u GITHUB_REF_NAME")
    assert.is_truthy(ok)
    local content = read_dist()
    assert.is_nil(content:find("__VERSION__"),
      "__VERSION__ token must be fully substituted even in dev fallback")
    -- Tolerate either dev fallback (`0.00`) OR a numeric local exact-match tag.
    -- The regex matches `version = <int>.<int>,` with any number of digits.
    assert.is_truthy(content:find("version%s*=%s*%d+%.%d+,"),
      "expected `version = N.NN,` (dev fallback 0.00 or local tag) in dist/paypal-pos.lua")
  end)

  it("DEV BUILD banner appears for dev fallback and is absent for tagged builds", function()
    -- Tagged build: line 2 should NOT contain 'DEV BUILD'.
    assert.is_truthy(run_build("GITHUB_REF_NAME=v1.0.0"))
    local tagged = read_dist()
    local lines_tagged = {}
    for line in tagged:gmatch("[^\n]*") do
      lines_tagged[#lines_tagged + 1] = line
      if #lines_tagged >= 4 then break end
    end
    assert.is_nil(lines_tagged[2] and lines_tagged[2]:find("DEV BUILD"),
      "DEV BUILD banner must NOT appear for tagged builds (got line 2: "
        .. tostring(lines_tagged[2]) .. ")")

    -- Dev fallback: line 2 should contain 'DEV BUILD' when version resolves to 0.00.
    -- We force the dev-fallback shape by unsetting GITHUB_REF_NAME AND providing
    -- a sentinel that prevents git from resolving an exact-match tag. The cleanest
    -- way is to set GITHUB_REF_NAME to an empty/non-matching string that the regex
    -- in version_to_number_string rejects, which forces `0.00`. We use
    -- GITHUB_REF_NAME="dev-test" — does not match `^v%d` so resolve_version_string
    -- falls through; version_to_number_string returns `0.00`.
    assert.is_truthy(run_build("GITHUB_REF_NAME=dev-test"))
    local dev = read_dist()
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
    local cmd = "GITHUB_REF_NAME=v1.0.0 lua tools/build.lua --verify >/dev/null 2>&1"
    local ok1 = os.execute(cmd)
    local ok2 = os.execute(cmd)
    assert.is_truthy(ok1, "first --verify run must succeed for GITHUB_REF_NAME=v1.0.0")
    assert.is_truthy(ok2, "second --verify run must succeed for GITHUB_REF_NAME=v1.0.0")
  end)

end)
