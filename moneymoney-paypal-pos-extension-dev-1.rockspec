-- moneymoney-paypal-pos-extension-dev-1.rockspec
--
-- Machine-readable manifest for the project's *development* toolchain.
--
-- Why this file exists
-- --------------------
-- The shipped artifact (dist/paypal-pos.lua) has ZERO external dependencies:
-- it is a single amalgamated Lua file that runs inside MoneyMoney's sandbox
-- and links against nothing. This rockspec therefore does NOT describe the
-- distributable — `build.type = "none"` and nothing is installed from it.
--
-- It exists solely to give the dev/test toolchain (busted, luacheck, luacov,
-- dkjson) a computer-processable declaration in the conventional LuaRocks
-- format, instead of the four unpinned `luarocks install <name>` lines that
-- ci.yml used to carry. Those lines resolved to whatever was newest at job
-- start, which meant the toolchain was unpinned and unauditable.
--
-- CI consumes this file directly:
--     luarocks install --only-deps moneymoney-paypal-pos-extension-dev-1.rockspec
--
-- Bumping a pin
-- -------------
-- LuaRocks is not supported by Dependabot, so these pins do not move on their
-- own. `.github/workflows/lua-toolchain-audit.yml` runs weekly, compares each
-- pin below against the newest version published on luarocks.org, and files a
-- tracking issue when they drift. Bump deliberately, in a PR, with a green CI
-- run — never by relaxing a constraint back to "latest".
--
-- Note: there is no vulnerability feed to subscribe to for this ecosystem.
-- OSV.dev has no LuaRocks ecosystem (verified 2026-08-27: an OSV query with
-- `"ecosystem":"LuaRocks"` returns `{"code":3,"message":"invalid ecosystem"}`),
-- and GitHub's Advisory Database likewise carries no LuaRocks advisories. The
-- audit workflow is therefore a *freshness* check, not a CVE check; that limit
-- is stated plainly rather than papered over.

rockspec_format = "3.0"
package = "moneymoney-paypal-pos-extension"
version = "dev-1"

source = {
  url = "git+https://github.com/yves-vogl/moneymoney-paypal-pos-extension.git",
}

description = {
  summary  = "Development toolchain pins for the MoneyMoney PayPal POS extension",
  detailed = [[
    Dev-only dependency manifest. The distributed artifact is a single
    amalgamated Lua file with no runtime dependencies; this rockspec pins the
    tools used to lint, test and measure it in CI.
  ]],
  homepage = "https://github.com/yves-vogl/moneymoney-paypal-pos-extension",
  license  = "MIT",
}

-- The extension source targets Lua 5.4 semantics (MoneyMoney's sandbox).
-- The constraint below is deliberately a floor, not a range: the toolchain
-- itself runs fine on newer interpreters, and pinning an upper bound here
-- would break contributors on Lua 5.5 for no benefit. CI pins the *runtime*
-- to 5.4 explicitly via leafo/gh-actions-lua.
dependencies = {
  "lua >= 5.4",
  "busted == 2.3.0-1",
  "luacheck == 1.2.0-1",
  "luacov == 0.17.0-1",
  "dkjson == 2.11-1",
}

build = {
  type = "none",
}
