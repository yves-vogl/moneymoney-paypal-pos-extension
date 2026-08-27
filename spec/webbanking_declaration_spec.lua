-- spec/webbanking_declaration_spec.lua
--
-- Regression coverage for the `WebBanking{...}` registration table that
-- src/webbanking_header.lua emits verbatim at the top of the shipped
-- artifact.
--
-- Why this spec exists
-- -------------------
-- Commit 66d9b95 ("fix(ui): declare WebBanking credentials so MM renders
-- API-Key field", #23) fixed a user-visible defect: without an explicit
-- `credentials` array, MoneyMoney's "Konto hinzufügen" dialog silently falls
-- back to its default Benutzername/Passwort fields, so the user is prompted
-- for the wrong thing and the extension can never authenticate. That fix
-- shipped WITHOUT a regression test, and it sat in the one blind spot where
-- nothing else would catch a re-break:
--
--   * .luacov excludes `^src/webbanking_header$`, so statement coverage says
--     nothing about this file;
--   * the declaration is inert data consumed by MoneyMoney itself, so no
--     other spec's code path touches it;
--   * `tools/build.lua` only gates DEBUG/egress, not the table's shape.
--
-- Deleting the `credentials` array would therefore have kept the whole suite
-- green while breaking every user's account setup. This spec closes that gap
-- by asserting the declaration in the BUILT artifact (not the source), which
-- is the thing MoneyMoney actually loads.
--
-- The second historical hazard is encoded too: the first draft of #23 put a
-- documentation URL in the credential description, which tripped the CI
-- egress-allowlist gate (it greps dist/paypal-pos.lua for scheme-prefixed
-- URLs). The "no URL in credential strings" assertion below keeps that from
-- silently returning.

-- luacheck: globals _WebBanking_received

local Mocks = require("spec.helpers.mm_mocks")

describe("WebBanking{} registration table (shipped artifact)", function()

  -- Mirrors the load_artifact() convention used by
  -- spec/phase3_surface_preservation_spec.lua: build, then dofile the
  -- amalgamation so the assertions run against what actually ships.
  local function load_artifact()
    local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
    if not ok or code ~= 0 then
      error("webbanking_declaration_spec: failed to build dist/paypal-pos.lua")
    end
    dofile("dist/paypal-pos.lua")
  end

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Core registration fields
  -- -------------------------------------------------------------------------

  it("registers exactly one service, named 'PayPal POS'", function()
    local t = _WebBanking_received
    assert.is_table(t)
    assert.is_table(t.services)
    assert.are.equal(1, #t.services)
    assert.are.equal("PayPal POS", t.services[1])
  end)

  it("declares country 'de' and a numeric version", function()
    local t = _WebBanking_received
    assert.are.equal("de", t.country)
    -- BUILD-03: tools/build.lua substitutes __VERSION__ with a numeric
    -- literal. A non-number here means the placeholder shipped unsubstituted.
    assert.are.equal("number", type(t.version))
  end)

  -- -------------------------------------------------------------------------
  -- credentials array — the actual regression guard for #23
  -- -------------------------------------------------------------------------

  it("declares a credentials array so MM does not fall back to user/password", function()
    local t = _WebBanking_received
    assert.is_table(t.credentials)
    assert.are.equal(2, #t.credentials)
  end)

  it("declares the API-Key field first and marks it secret", function()
    local field = _WebBanking_received.credentials[1]
    assert.are.equal("API-Key", field.label)
    -- secret = true is what makes MoneyMoney mask the input and route the
    -- value into its encrypted credential store rather than plain settings.
    assert.is_true(field.secret)
    assert.is_string(field.description)
  end)

  it("declares the Update-Check opt-out field second and does not mark it secret", function()
    local field = _WebBanking_received.credentials[2]
    assert.are.equal("Update-Check", field.label)
    assert.is_false(field.secret)
    assert.is_string(field.description)
  end)

  -- -------------------------------------------------------------------------
  -- Egress-gate hazard (see file header)
  -- -------------------------------------------------------------------------

  it("keeps every credential string free of scheme-prefixed URLs", function()
    for i, field in ipairs(_WebBanking_received.credentials) do
      for _, key in ipairs({ "label", "description" }) do
        local value = field[key]
        if type(value) == "string" then
          assert.is_nil(value:match("https?://"),
            ("credentials[%d].%s must not embed a URL — the CI egress-allowlist "
             .. "gate rejects scheme-prefixed hosts in dist/paypal-pos.lua"):format(i, key))
        end
      end
    end
  end)
end)
