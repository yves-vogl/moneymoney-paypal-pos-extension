-- tools/probe.lua
-- Phase 1 sandbox probe extension for MoneyMoney.
-- Standalone — NOT amalgamated, NOT referenced by tools/manifest.txt.
-- bankCode "PayPal POS Probe" so it cannot collide with the real extension.
--
-- Q1: enumerate _G keys (which globals MoneyMoney's sandbox exposes)
-- Q4: integer round-trip via JSON():set + :json + JSON():dictionary
-- Q5: LocalStorage counter increments across MoneyMoney restarts
-- Q7: services-label rendering — maintainer observes "PayPal POS Probe"
--     appears in the add-account UI
-- Q8: TLS verification default — Connection:get against expired.badssl.com
-- Q9: MM.sleep availability + behaviour (Phase 5 / D-67; OPTIONAL per ADR-0005)
--
-- Q2, Q3, Q6 are NOT runnable from this probe (require live PayPal POS
-- credentials or developer.zettle.com lookup). The maintainer fills those
-- cells in ADR-0003 manually.

-- luacheck: read_globals WebBanking Connection JSON MM ProtocolWebBanking AccountTypeGiro
-- luacheck: globals LocalStorage

WebBanking{
  version     = 0.00,
  country     = "de",
  url         = "https://oauth.zettle.com",
  services    = {"PayPal POS Probe"},
  description = "Phase 1 sandbox probe — entfernt nach ADR-0003-Eintrag",
}

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "PayPal POS Probe"
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
  return nil
end

function ListAccounts(knownAccounts)
  return {
    {
      accountNumber = "paypal-pos-probe-001",
      name          = "PayPal POS Probe",
      currency      = "EUR",
      portfolio     = false,
      type          = AccountTypeGiro,
    },
  }
end

function RefreshAccount(account, since)
  print("=== PAYPAL POS PROBE START ===")
  print("date: " .. tostring(os.date and os.date("!%Y-%m-%dT%H:%M:%SZ") or "no os.date"))

  -- Q1: enumerate _G keys (sandbox surface)
  print("--- Q1: _G keys (sandbox surface) ---")
  local keys = {}
  for k, v in pairs(_G) do
    keys[#keys + 1] = k .. " (" .. type(v) .. ")"
  end
  table.sort(keys)
  for _, k in ipairs(keys) do print("  Q1: " .. k) end
  -- Explicit probes for the high-risk globals
  for _, name in ipairs({ "require", "dofile", "loadfile", "io", "os", "debug", "package", "_G" }) do
    print(string.format("  Q1: %s = %s", name, type(_G[name])))
  end

  -- Q4: JSON integer round-trip on amount = 995
  print("--- Q4: JSON integer round-trip (amount=995) ---")
  local encoded = JSON():set({amount = 995}):json()
  print("  Q4: encoded = " .. encoded)
  local decoded = JSON(encoded):dictionary()
  print(string.format("  Q4: decoded.amount = %s (type=%s)", tostring(decoded.amount), type(decoded.amount)))
  if decoded.amount == 995 then
    print("  Q4: RESULT = PASS (integer preserved)")
  else
    print(string.format("  Q4: RESULT = FAIL (decoded=%s, expected 995)", tostring(decoded.amount)))
  end

  -- Q5: LocalStorage cross-restart persistence
  print("--- Q5: LocalStorage counter ---")
  local prev = LocalStorage.probe_counter or 0
  LocalStorage.probe_counter = prev + 1
  print(string.format("  Q5: previous_counter = %s", tostring(prev)))
  print(string.format("  Q5: current_counter  = %s", tostring(LocalStorage.probe_counter)))
  print("  Q5: ACTION = note this number, restart MoneyMoney, Aktualisieren again, observe whether it increments")

  -- Q7: services-label is observed by the maintainer in "Konto hinzufügen".
  --     Logged as a marker so the ADR row has a corresponding line.
  print("--- Q7: services-label rendering ---")
  print("  Q7: ACTION = confirm the bank list in \"Konto hinzufügen\" shows \"PayPal POS Probe\" exactly")

  -- Q8: TLS verification default — Connection:get against expired.badssl.com
  --     NOTE: this is the only non-allowlist host this file deliberately
  --     contacts, and only because Q8 cannot be answered without it.
  --     The probe file is uninstalled after ADR-0003 is filled in (D-11).
  print("--- Q8: TLS verification default ---")
  local conn = Connection()
  local ok, err = pcall(function()
    local _content = conn:get("https://expired.badssl.com/")
    return _content
  end)
  if ok then
    print("  Q8: RESULT = TLS NOT VERIFIED — Connection accepted expired certificate (BLOCKING ISSUE)")
  else
    print("  Q8: RESULT = TLS VERIFIED — Connection rejected expired certificate (good)")
    print("  Q8: error = " .. tostring(err))
  end
  conn:close()

  -- Q9: MM.sleep availability + behaviour (Phase 5 / D-67; OPTIONAL per ADR-0005)
  print("--- Q9: MM.sleep availability ---")
  if type(MM) ~= "table" then
    print("  Q9: RESULT = FAIL (MM is not a table; sandbox surface differs from expectation)")
  elseif type(MM.sleep) ~= "function" then
    print("  Q9: RESULT = ABSENT (MM.sleep is not a function — would force busy-wait fallback per ADR-0005)")
  else
    local t0 = os.time()
    local ok, err = pcall(function() MM.sleep(1) end)
    local elapsed = os.time() - t0
    if not ok then
      print("  Q9: RESULT = FAIL (MM.sleep(1) errored: " .. tostring(err) .. ")")
    elseif elapsed < 1 then
      print(string.format("  Q9: RESULT = PRESENT-BUT-NOOP (elapsed=%ds, expected >=1s)", elapsed))
    else
      print(string.format("  Q9: RESULT = PASS (MM.sleep blocks; elapsed=%ds)", elapsed))
    end
  end
  print("  Q9: ACTION = record outcome in docs/adr/0003-sandbox-probe-results.md row Q9")

  print("=== PAYPAL POS PROBE END ===")

  -- Return an empty transaction list so MoneyMoney does not display
  -- anything spurious in the account view.
  return { balance = 0, transactions = {} }
end

function EndSession()
  return nil
end
