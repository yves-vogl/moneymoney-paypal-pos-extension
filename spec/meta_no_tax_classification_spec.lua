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
-- ADR. Files MAY be absent during W1 (CONTRIBUTING.md lands in W2); the
-- it() block tolerates missing files but asserts that at least one target
-- exists so a future delete-everything regression still fails.
local DOC_TARGETS = {
  "README.md",
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

-- DISCLAIMER_MARKERS: tokens whose presence on the SAME LINE as a forbidden
-- phrase reclassifies the match as a legitimate disclaimer rather than a
-- conformance claim. The META-03 invariant exists to prevent the project
-- from *claiming* GoBD/VAT/DATEV conformance; reading the same phrase in
-- order to disclaim it ("wir bestätigen keine GoBD-Konformität") is the
-- opposite operation and MUST stay legal.
--
-- The list deliberately covers German + English negation tokens. Surrounded
-- by word boundaries so substrings ("keiner", "nicht-") do not over-match.
local DISCLAIMER_MARKERS = {
  -- German
  "keine", "keinen", "keiner", "keines", "kein",
  "nicht", "ohne",
  -- English
  "no", "not", "without",
}

-- has_disclaimer_on_line(line) -> boolean
-- Returns true if the line carries any of the DISCLAIMER_MARKERS as a
-- whole word (case-insensitive). Used to suppress false-positive matches
-- on legitimate disclaimer prose.
local function has_disclaimer_on_line(line)
  local line_lc = line:lower()
  for _, marker in ipairs(DISCLAIMER_MARKERS) do
    -- %f[%w] is the Lua frontier pattern — matches a transition into
    -- alphanumeric. Combined with the trailing %f[%W] (transition OUT
    -- of alphanumeric), this is the equivalent of \b...\b in PCRE.
    if line_lc:find("%f[%w]" .. marker .. "%f[%W]") then
      return true
    end
  end
  return false
end

-- scan_file(path) -> { {phrase, offset, line}, ... } | nil
-- Reads the entire file content and returns the list of (phrase, byte-offset)
-- hits for any of the 13 forbidden phrases. Returns an empty table on a clean
-- file. Returns nil with an error if the file cannot be opened.
--
-- P6-R-10: case-INsensitive match. The previous implementation called
-- `content:find(phrase, 1, true)` with both arguments at original case;
-- a doc author writing "GoBD-Konform" (capital K) or "Steuerfrei" (capital S)
-- would slip past the gate. Lowering both content and phrase keeps the
-- plain-text-find safety (4th arg = true, hyphen + UTF-8 'ä' immune to
-- Lua-pattern escapes) while making the comparison case-insensitive.
-- string.lower() is byte-wise on Lua 5.4 and operates on ASCII a-z only;
-- the UTF-8 'ä' (0xC3 0xA4) byte sequence in "DATEV-fähig" is unchanged
-- by lower() — both sides stay aligned bit-for-bit.
--
-- Disclaimer suppression: hits on lines that ALSO carry a DISCLAIMER_MARKERS
-- token are suppressed. The invariant prohibits CLAIMING conformance, not
-- DISCLAIMING it. Affirmative-conformance claims (e.g. a stray "Diese
-- Extension ist GoBD-Konform.") will still trip the gate because the
-- line lacks any of the negation markers.
local function scan_file(path)
  local f, err = io.open(path, "rb")
  if not f then
    error("meta_no_tax_classification_spec: cannot open '" .. tostring(path)
      .. "': " .. tostring(err))
  end
  local content = f:read("*a")
  f:close()
  -- Walk line-by-line so the disclaimer-suppression check has a stable
  -- "same line" definition. Tracks a running byte offset so reported
  -- offsets are still relative to the whole file.
  local hits = {}
  local offset = 1
  -- Build lowercased forbidden phrases once (small constant cost).
  local forbidden_lc = {}
  for i, phrase in ipairs(FORBIDDEN) do
    forbidden_lc[i] = { phrase = phrase, lc = phrase:lower() }
  end
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    local line_lc = line:lower()
    local disclaimer = has_disclaimer_on_line(line)
    for _, entry in ipairs(forbidden_lc) do
      local pos = line_lc:find(entry.lc, 1, true)
      if pos and not disclaimer then
        hits[#hits + 1] = { phrase = entry.phrase, offset = offset + pos - 1 }
      end
    end
    offset = offset + #line + 1  -- +1 for the consumed newline
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
    -- Phase-6 extension: protects README.md + CONTRIBUTING.md + CHANGELOG.md +
    -- every docs/adr/*.md against accidentally introducing one of the 13 D-55
    -- forbidden phrases as Wave-2 doc authoring lands.
    -- Files absent at scan time (W1 stage: CONTRIBUTING.md does not yet exist)
    -- are skipped silently; the assertion only fires for files that physically
    -- exist. At least one target MUST exist so a delete-everything regression
    -- still trips the gate.
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
