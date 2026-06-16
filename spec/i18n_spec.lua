-- spec/i18n_spec.lua
-- Tests for M_i18n.t() — German default strings, interpolation, fallback,
-- and DE/EN key-parity (I18N-02, I18N-03).
--
-- Loading strategy: Mocks.setup() + dofile("dist/paypal-pos.lua").
-- The artifact is built once before the suite runs.

local Mocks = require("spec.helpers.mm_mocks")

-- Build a fresh artifact once for the whole suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("i18n_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

-- Load the artifact into the current environment once.
-- Called inside a setup block so Mocks are in place when WebBanking{} runs.
local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("M_i18n.t()", function()

  setup(function()
    Mocks.setup()
    load_artifact()
  end)

  teardown(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  it("returns German strings by default", function()
    assert.equals("Kartenzahlung", M_i18n.t("transaction.name.sale"))
  end)

  it("interpolates positional arguments via string.format", function()
    -- The em-dash in "PayPal POS — %s" is U+2014 (three UTF-8 bytes: 0xE2 0x80 0x94).
    assert.equals("PayPal POS \xE2\x80\x94 Test-H\xC3\xA4ndler",
                  M_i18n.t("account.name", "Test-Händler"))
  end)

  it("falls back to the key literal for missing keys", function()
    assert.equals("nonexistent.key", M_i18n.t("nonexistent.key"))
  end)

  it("STRINGS.en covers every STRINGS.de key", function()
    local de = M_i18n._strings.de
    local en = M_i18n._strings.en
    for k in pairs(de) do
      assert.is_not_nil(en[k],
        "key '" .. k .. "' is present in STRINGS.de but missing from STRINGS.en")
    end
  end)

  it("STRINGS.de covers every STRINGS.en key", function()
    local de = M_i18n._strings.de
    local en = M_i18n._strings.en
    for k in pairs(en) do
      assert.is_not_nil(de[k],
        "key '" .. k .. "' is present in STRINGS.en but missing from STRINGS.de")
    end
  end)

  it("_locale reports 'de'", function()
    assert.equals("de", M_i18n._locale)
  end)

end)
