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

-- ---------------------------------------------------------------------------
describe("M_i18n.t() Phase 3 account.purpose.* keys (D-34 / D-35 / I18N-01)", function()

  setup(function()
    Mocks.setup()
    load_artifact()
  end)

  teardown(function()
    Mocks.teardown()
  end)

  it("account.purpose.gross returns German Brutto line", function()
    assert.equals("Brutto: 9,95 \xe2\x82\xac", M_i18n.t("account.purpose.gross", "9,95"),
      "expected 'Brutto: 9,95 €'")
  end)

  it("account.purpose.vat returns German MwSt line", function()
    assert.equals("MwSt: 1,59 \xe2\x82\xac", M_i18n.t("account.purpose.vat", "1,59"),
      "expected 'MwSt: 1,59 €'")
  end)

  it("account.purpose.tip returns German Trinkgeld line", function()
    assert.equals("Trinkgeld: 1,00 \xe2\x82\xac", M_i18n.t("account.purpose.tip", "1,00"),
      "expected 'Trinkgeld: 1,00 €'")
  end)

  it("account.purpose.net returns German Netto line", function()
    assert.equals("Netto: 7,36 \xe2\x82\xac", M_i18n.t("account.purpose.net", "7,36"),
      "expected 'Netto: 7,36 €'")
  end)

  it("account.purpose.refund_for returns German Rückerstattung line", function()
    assert.equals("R\xc3\xbcckerstattung zu Beleg #1001", M_i18n.t("account.purpose.refund_for", "1001"),
      "expected 'Rückerstattung zu Beleg #1001'")
  end)

  it("account.purpose.receipt_number returns German Beleg line", function()
    assert.equals("Beleg #1001", M_i18n.t("account.purpose.receipt_number", "1001"),
      "expected 'Beleg #1001'")
  end)

  it("account.name.card_payment returns German Kartenzahlung", function()
    assert.equals("Kartenzahlung", M_i18n.t("account.name.card_payment"),
      "expected 'Kartenzahlung'")
  end)

end)

-- ---------------------------------------------------------------------------
describe("M_i18n.t() Plan 04-02 fee / payout / payment-method keys (D-49 / D-57 / PAYOUT-02)", function()

  setup(function()
    Mocks.setup()
    load_artifact()
  end)

  teardown(function()
    Mocks.teardown()
  end)

  -- ----- de table (normative) -----

  it("de account.name.fee = 'Gebühr'", function()
    assert.equals("Geb\xc3\xbchr", M_i18n._strings.de["account.name.fee"])
  end)

  it("de account.name.fee_aggregate = 'PayPal POS Transaktionsgebühren'", function()
    assert.equals("PayPal POS Transaktionsgeb\xc3\xbchren",
      M_i18n._strings.de["account.name.fee_aggregate"])
  end)

  it("de account.name.payout = 'Auszahlung an Bankkonto'", function()
    assert.equals("Auszahlung an Bankkonto", M_i18n._strings.de["account.name.payout"])
  end)

  it("de account.purpose.fee_label = 'Gebühr'", function()
    assert.equals("Geb\xc3\xbchr", M_i18n._strings.de["account.purpose.fee_label"])
  end)

  it("de account.purpose.fee_for_receipt interpolates receipt number", function()
    assert.equals("Geb\xc3\xbchr f\xc3\xbcr Beleg #2001",
      M_i18n.t("account.purpose.fee_for_receipt", "2001"))
  end)

  it("de account.purpose.fee_aggregate interpolates count + contains em-dash + 'Tagesaggregat'", function()
    local s = M_i18n.t("account.purpose.fee_aggregate", 3)
    assert.is_truthy(s:find("Tagesaggregat", 1, true))
    assert.is_truthy(s:find("3 Einzelgeb\xc3\xbchren", 1, true))
    -- U+2014 em-dash = \xe2\x80\x94
    assert.is_truthy(s:find("\xe2\x80\x94", 1, true), "must contain em-dash")
  end)

  it("de account.purpose.payment_method.kontaktlos = 'kontaktlos'", function()
    assert.equals("kontaktlos", M_i18n._strings.de["account.purpose.payment_method.kontaktlos"])
  end)

  it("de account.purpose.payment_method.chip = 'Chip'", function()
    assert.equals("Chip", M_i18n._strings.de["account.purpose.payment_method.chip"])
  end)

  it("de account.purpose.payment_method.swipe = 'Magnetstreifen'", function()
    assert.equals("Magnetstreifen", M_i18n._strings.de["account.purpose.payment_method.swipe"])
  end)

  it("de account.purpose.payment_method.ecommerce = 'Online'", function()
    assert.equals("Online", M_i18n._strings.de["account.purpose.payment_method.ecommerce"])
  end)

  it("de account.purpose.payment_method.manual = 'Manuell'", function()
    assert.equals("Manuell", M_i18n._strings.de["account.purpose.payment_method.manual"])
  end)

  it("de account.purpose.payment_method.unknown = 'unbekannt'", function()
    assert.equals("unbekannt", M_i18n._strings.de["account.purpose.payment_method.unknown"])
  end)

  -- ----- en table (parity / technical fallback) -----

  it("en account.name.fee = 'Fee'", function()
    assert.equals("Fee", M_i18n._strings.en["account.name.fee"])
  end)

  it("en account.name.fee_aggregate = 'PayPal POS Transaction Fees'", function()
    assert.equals("PayPal POS Transaction Fees", M_i18n._strings.en["account.name.fee_aggregate"])
  end)

  it("en account.name.payout = 'Payout to Bank Account'", function()
    assert.equals("Payout to Bank Account", M_i18n._strings.en["account.name.payout"])
  end)

  it("en account.purpose.fee_label = 'Fee'", function()
    assert.equals("Fee", M_i18n._strings.en["account.purpose.fee_label"])
  end)

  it("en account.purpose.fee_for_receipt interpolates receipt number", function()
    assert.equals("Fee for receipt #2001",
      M_i18n._strings.en["account.purpose.fee_for_receipt"]:format("2001"))
  end)

  it("en account.purpose.fee_aggregate contains 'Daily aggregate' + count", function()
    local en_template = M_i18n._strings.en["account.purpose.fee_aggregate"]
    local s = en_template:format(5)
    assert.is_truthy(s:find("Daily aggregate", 1, true))
    assert.is_truthy(s:find("5 individual fees", 1, true))
  end)

  it("en account.purpose.payment_method.kontaktlos = 'contactless'", function()
    assert.equals("contactless", M_i18n._strings.en["account.purpose.payment_method.kontaktlos"])
  end)

  it("en account.purpose.payment_method.chip = 'Chip'", function()
    assert.equals("Chip", M_i18n._strings.en["account.purpose.payment_method.chip"])
  end)

  it("en account.purpose.payment_method.swipe = 'Magstripe'", function()
    assert.equals("Magstripe", M_i18n._strings.en["account.purpose.payment_method.swipe"])
  end)

  it("en account.purpose.payment_method.ecommerce = 'Online'", function()
    assert.equals("Online", M_i18n._strings.en["account.purpose.payment_method.ecommerce"])
  end)

  it("en account.purpose.payment_method.manual = 'Manual'", function()
    assert.equals("Manual", M_i18n._strings.en["account.purpose.payment_method.manual"])
  end)

  it("en account.purpose.payment_method.unknown = 'unknown'", function()
    assert.equals("unknown", M_i18n._strings.en["account.purpose.payment_method.unknown"])
  end)

end)
