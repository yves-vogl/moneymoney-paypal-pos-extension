-- spec/meta_no_tax_classification_spec.lua
-- META-03 invariant gate (CONTEXT D-55, locked permanent).
--
-- The extension MUST NEVER claim tax / VAT / GoBD / DATEV conformance anywhere
-- in the shipped Lua source or the built artifact. This spec walks every
-- src/*.lua file AND dist/paypal-pos.lua and asserts that none of the 13
-- forbidden phrases from D-55 appear (case-sensitive, plain-text find).
--
-- D-55 (LOCKED): the 13-phrase list is the once-locked-permanent invariant.
-- Any future change requires reopening the CONTEXT D-55 conversation, not a
-- silent override in a downstream plan.
--
-- RESEARCH §7.2: plain-text find (4th arg = true) avoids Lua-pattern escape
-- complications with the hyphen `-` and accent characters in DATEV-fähig.

-- Build the artifact once before the suite runs so the dist/ scan reflects
-- the current src/ tree (mirrors the preamble pattern from spec/refresh_*_spec.lua).
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("meta_no_tax_classification_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

-- DOC_TARGETS: documentation files the Phase-6 META-03 walker covers.
-- Static list covers the canonical entries; dynamic enumeration adds every
-- ADR. Files MAY be absent during W1 (README.de.md / CONTRIBUTING.md land
-- in W2); the it() block tolerates missing files but asserts that at least
-- one target exists so a future delete-everything regression still fails.
local DOC_TARGETS = {
  "README.md",
  "README.de.md",
  "CONTRIBUTING.md",
  "CHANGELOG.md",
}
do
  local handle = io.popen("ls docs/adr/*.md 2>/dev/null")
  if handle then
    for path in handle:lines() do
      DOC_TARGETS[#DOC_TARGETS + 1] = path
    end
    handle:close()
  end
end

-- 13 forbidden phrases verbatim per CONTEXT D-55 (Yves-locked).
-- DATEV-fähig / DATEV fähig contain the UTF-8 byte sequence \xC3\xA4 for 'ä'.
local FORBIDDEN = {
  "USt-frei",
  "USt frei",
  "steuerfrei",
  "steuerlich",
  "GoBD-konform",
  "GoBD konform",
  "DATEV-f\xc3\xa4hig",
  "DATEV f\xc3\xa4hig",
  "VAT-exempt",
  "VAT exempt",
  "tax-free",
  "tax exempt",
  "non-taxable",
}

-- scan_file(path) -> { {phrase, offset}, ... } | nil
-- Reads the entire file content and returns the list of (phrase, byte-offset)
-- hits for any of the 13 forbidden phrases. Returns an empty table on a clean
-- file. Returns nil with an error if the file cannot be opened.
local function scan_file(path)
  local f, err = io.open(path, "rb")
  if not f then
    error("meta_no_tax_classification_spec: cannot open '" .. tostring(path)
      .. "': " .. tostring(err))
  end
  local content = f:read("*a")
  f:close()
  local hits = {}
  for _, phrase in ipairs(FORBIDDEN) do
    local pos = content:find(phrase, 1, true)
    if pos then
      hits[#hits + 1] = { phrase = phrase, offset = pos }
    end
  end
  return hits
end

local function format_hits(path, hits)
  local parts = {}
  for _, h in ipairs(hits) do
    parts[#parts + 1] = string.format("  %s at byte %d", h.phrase, h.offset)
  end
  return "META-03 violation in " .. path .. ":\n" .. table.concat(parts, "\n")
end

-- ---------------------------------------------------------------------------
describe("META-03: forbidden tax-classification phrases (D-55)", function()

  it("none of src/*.lua contains a forbidden phrase", function()
    local handle = io.popen("ls src/*.lua")
    assert.is_not_nil(handle, "io.popen('ls src/*.lua') must succeed")
    local scanned = 0
    for path in handle:lines() do
      scanned = scanned + 1
      local hits = scan_file(path)
      assert.equals(0, #hits, format_hits(path, hits))
    end
    handle:close()
    assert.is_true(scanned >= 1,
      "expected at least one src/*.lua file to scan; got " .. tostring(scanned))
  end)

  it("dist/paypal-pos.lua contains no forbidden phrase (built artifact gate)", function()
    -- Ensure the artifact exists (preamble already built it but tolerate
    -- repeated invocations — tools/build.lua is deterministic).
    local ok = os.execute("lua tools/build.lua >/dev/null 2>&1")
    assert.is_truthy(ok, "lua tools/build.lua must succeed before scanning dist/")
    local hits = scan_file("dist/paypal-pos.lua")
    assert.equals(0, #hits, format_hits("dist/paypal-pos.lua", hits))
  end)

  it("none of the documentation files contains a forbidden phrase (DOC-04 / Phase 6 extension)", function()
    -- Phase-6 extension: protects README.md + README.de.md + CONTRIBUTING.md +
    -- CHANGELOG.md + every docs/adr/*.md against accidentally introducing one
    -- of the 13 D-55 forbidden phrases as Wave-2 doc authoring lands.
    -- Files absent at scan time (W1 stage: README.de.md / CONTRIBUTING.md do
    -- not yet exist) are skipped silently; the assertion only fires for
    -- files that physically exist. At least one target MUST exist so a
    -- delete-everything regression still trips the gate.
    local scanned = 0
    for _, path in ipairs(DOC_TARGETS) do
      local f = io.open(path, "rb")
      if f then
        f:close()
        scanned = scanned + 1
        local hits = scan_file(path)
        assert.equals(0, #hits, format_hits(path, hits))
      end
    end
    assert.is_true(scanned >= 1,
      "expected at least one documentation target to exist; got " .. tostring(scanned))
  end)

end)
