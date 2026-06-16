-- tools/build.lua
-- Amalgamator for paypal-pos.lua
-- Reads tools/manifest.txt, concatenates src/<module>.lua files into
-- dist/paypal-pos.lua with do...end wrapping for non-header/non-entry modules.
--
-- Usage:
--   lua tools/build.lua           -- build only
--   lua tools/build.lua --verify  -- build + second build + sha256 compare
--   lua tools/build.lua --help    -- print usage

-- SHA-256 is implemented at the bottom of this file (clearly marked block).
-- We forward-declare it here so the CLI section can reference it.
local sha256

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local MANIFEST_PATH = "tools/manifest.txt"
local OUTPUT_PATH   = "dist/paypal-pos.lua"
local TMP_PATH      = "dist/paypal-pos.lua.tmp"
local HEADER_MOD    = "webbanking_header"
local ENTRY_MOD     = "entry"
local BANNER        = "-- paypal-pos amalgamated artifact — do not edit by hand\n"
local SENTINEL      = "-- paypal-pos build: complete\n"

-- ---------------------------------------------------------------------------
-- Sandbox-banned patterns (H8) — matched against non-comment source lines
-- ---------------------------------------------------------------------------

local BANNED_CALLS = {
  "require%(",
  "dofile%(",
  "loadfile%(",
  "io%.open%(",
  "os%.execute%(",
  "io%.popen%(",
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Read a file in binary mode; returns content string or nil + short error message.
-- The short error strips the path prefix that io.open includes in the error string.
local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then
    -- io.open error strings are "path: reason"; strip the path prefix so callers
    -- can format "BUILD ERROR: path: reason" without duplicating the path.
    local escaped = path:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
    local reason = err and err:gsub("^" .. escaped .. ": ", "") or "unknown error"
    return nil, reason
  end
  local content = f:read("*a")
  f:close()
  return content
end

-- Normalise line endings: \r\n -> \n, then standalone \r -> \n.
-- Then strip trailing whitespace from each line.
local function normalise(content)
  -- Step 1: CRLF -> LF
  content = content:gsub("\r\n", "\n")
  -- Step 2: bare CR -> LF
  content = content:gsub("\r", "\n")
  -- Step 3: strip trailing whitespace (spaces and tabs) per line
  -- Match lines ending with whitespace followed by \n
  content = content:gsub("([ \t]+)\n", "\n")
  -- Handle trailing whitespace at end of string (no trailing newline)
  content = content:gsub("([ \t]+)$", "")
  return content
end

-- Ensure content ends with exactly one newline.
local function ensure_trailing_newline(content)
  if content == "" or content:sub(-1) ~= "\n" then
    return content .. "\n"
  end
  return content
end

-- Parse manifest; return ordered list of module base-names.
-- Skips blank lines and lines whose first non-whitespace char is '#'.
local function parse_manifest(path)
  local content, err = read_file(path)
  if not content then
    io.stderr:write("BUILD ERROR: cannot read manifest: " .. tostring(err) .. "\n")
    os.exit(1)
  end
  local modules = {}
  for line in content:gmatch("[^\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      modules[#modules + 1] = trimmed
    end
  end
  return modules
end

-- Check a source file for sandbox-banned calls (H8) and DEBUG=true (SEC-04).
-- Aborts via os.exit(1) on first violation.
-- Line comments (first non-whitespace is "--") are skipped.
local function check_source(basename, content)
  local lineno = 0
  for line in (content .. "\n"):gmatch("[^\n]*\n") do
    lineno = lineno + 1
    local stripped = line:match("^%s*(.-)%s*$")
    -- Skip lines that are line comments
    if stripped:sub(1, 2) ~= "--" then
      -- Sandbox-call gate (H8)
      for _, pattern in ipairs(BANNED_CALLS) do
        if stripped:find(pattern) then
          -- Produce a display form of the matched token
          local display = pattern:gsub("%%%(", "("):gsub("%%%.",".")
          io.stderr:write(string.format(
            "BUILD ERROR: sandbox-banned call in src/%s.lua:%d: %s\n",
            basename, lineno, display
          ))
          os.exit(1)
        end
      end
      -- DEBUG gate (SEC-04)
      if stripped:find("DEBUG%s*=%s*true") then
        io.stderr:write(string.format(
          "BUILD ERROR: DEBUG = true found in src/%s.lua:%d\n",
          basename, lineno
        ))
        os.exit(1)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Build: assemble the output string in memory and return it.
-- ---------------------------------------------------------------------------

local function build(modules)
  local parts = {}
  local entry_content = nil

  parts[#parts + 1] = BANNER

  for _, mod in ipairs(modules) do
    local path = "src/" .. mod .. ".lua"
    local content, err = read_file(path)
    if not content then
      io.stderr:write("BUILD ERROR: " .. path .. ": " .. tostring(err) .. "\n")
      os.exit(1)
    end
    content = normalise(content)
    check_source(mod, content)

    if mod == HEADER_MOD then
      -- Emit verbatim at top; ensure trailing newline
      parts[#parts + 1] = ensure_trailing_newline(content)
    elseif mod == ENTRY_MOD then
      -- Collect for verbatim emission at the end
      entry_content = content
    else
      -- Wrapped in do...end with separator banner
      parts[#parts + 1] = "-- === MODULE: " .. mod .. " ===\n"
      parts[#parts + 1] = "do\n"
      parts[#parts + 1] = ensure_trailing_newline(content)
      parts[#parts + 1] = "end\n"
    end
  end

  -- Append entry.lua verbatim (MoneyMoney callbacks must be top-level)
  if entry_content then
    parts[#parts + 1] = ensure_trailing_newline(entry_content)
  end

  parts[#parts + 1] = SENTINEL

  return table.concat(parts)
end

-- ---------------------------------------------------------------------------
-- Write the assembled output to a file path (binary mode for LF preservation).
-- ---------------------------------------------------------------------------

local function write_output(path, content)
  -- Create dist/ if it does not exist (os.execute is permitted in tools/).
  os.execute("mkdir -p dist")
  local f, err = io.open(path, "wb")
  if not f then
    io.stderr:write("BUILD ERROR: cannot write " .. path .. ": " .. tostring(err) .. "\n")
    os.exit(1)
  end
  f:write(content)
  f:close()
end

-- ---------------------------------------------------------------------------
-- Usage message
-- ---------------------------------------------------------------------------

local function print_help()
  io.stdout:write(table.concat({
    "Usage: lua tools/build.lua [--verify | --help]",
    "",
    "  (no args)   Amalgamate src/ modules into dist/paypal-pos.lua",
    "  --verify    Build twice and compare sha256 checksums for reproducibility",
    "  --help      Show this message",
    "",
    "Reads module order from tools/manifest.txt.",
    "Output: dist/paypal-pos.lua",
    "",
  }, "\n"))
end

-- ---------------------------------------------------------------------------
-- SHA-256 (pure Lua, public domain — see https://github.com/Egor-Skriptunoff/pure_lua_SHA)
-- This is a minimal standalone implementation of SHA-256 (FIPS 180-4).
-- Only the sha256(s) -> hex-string interface is implemented.
-- No streaming, no HMAC, no global state — fully re-entrant.
-- ---------------------------------------------------------------------------

do
  -- SHA-256 round constants (first 32 bits of the fractional parts of the
  -- cube roots of the first 64 primes).
  local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }

  -- Initial hash values (first 32 bits of the fractional parts of the
  -- square roots of the first 8 primes).
  local H0 = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  }

  -- Arithmetic helpers that keep values in the 32-bit unsigned range.
  -- Lua 5.4 integers are 64-bit, so we mask after operations that may overflow.
  local MASK32 = 0xffffffff

  local function band(a, b)   return a & b end
  local function bxor(a, b)   return a ~ b end
  local function bnot(a)      return (~a) & MASK32 end
  local function add32(a, b)  return (a + b) & MASK32 end

  -- Right-rotate a 32-bit value by n positions.
  local function rrot(x, n)
    return ((x >> n) | (x << (32 - n))) & MASK32
  end

  -- Right-shift (logical) a 32-bit value by n positions.
  local function rsh(x, n)
    return (x >> n) & MASK32
  end

  -- Convert a 32-bit integer to 4 bytes (big-endian), appended to t.
  local function put_uint32(t, v)
    t[#t + 1] = string.char(
      (v >> 24) & 0xff,
      (v >> 16) & 0xff,
      (v >>  8) & 0xff,
       v        & 0xff
    )
  end

  -- Process one 512-bit (64-byte) block.
  -- h is the mutable state array of 8 x 32-bit words.
  local function process_block(h, block, offset)
    -- Prepare the message schedule W[1..64]
    local W = {}
    for i = 1, 16 do
      local j = offset + (i - 1) * 4
      W[i] = (block:byte(j + 1) << 24)
            | (block:byte(j + 2) << 16)
            | (block:byte(j + 3) <<  8)
            |  block:byte(j + 4)
    end
    for i = 17, 64 do
      local s0 = bxor(rrot(W[i-15], 7), bxor(rrot(W[i-15], 18), rsh(W[i-15], 3)))
      local s1 = bxor(rrot(W[i-2], 17), bxor(rrot(W[i-2], 19),  rsh(W[i-2], 10)))
      W[i] = add32(add32(add32(W[i-16], s0), W[i-7]), s1)
    end

    -- Working variables
    local a, b, c, d, e, f, g, hh =
      h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]

    -- Compression
    for i = 1, 64 do
      local S1   = bxor(rrot(e, 6), bxor(rrot(e, 11), rrot(e, 25)))
      local ch   = bxor(band(e, f), band(bnot(e), g))
      local temp1 = add32(add32(add32(add32(hh, S1), ch), K[i]), W[i])
      local S0   = bxor(rrot(a, 2), bxor(rrot(a, 13), rrot(a, 22)))
      local maj  = bxor(band(a, b), bxor(band(a, c), band(b, c)))
      local temp2 = add32(S0, maj)

      hh = g; g = f; f = e
      e  = add32(d, temp1)
      d  = c; c = b; b = a
      a  = add32(temp1, temp2)
    end

    -- Update hash state
    h[1] = add32(h[1], a)
    h[2] = add32(h[2], b)
    h[3] = add32(h[3], c)
    h[4] = add32(h[4], d)
    h[5] = add32(h[5], e)
    h[6] = add32(h[6], f)
    h[7] = add32(h[7], g)
    h[8] = add32(h[8], hh)
  end

  -- sha256(s) -> lowercase 64-character hex string
  sha256 = function(s)
    assert(type(s) == "string", "sha256: string expected")

    -- Pre-processing: pad message to a multiple of 512 bits (64 bytes).
    local msg_len   = #s
    local bit_len   = msg_len * 8

    -- Append 0x80 byte, then zero bytes, then 64-bit big-endian bit length.
    -- Total padded length must be a multiple of 64.
    -- Number of zero bytes: we need (msg_len + 1 + 8) to be a multiple of 64.
    local pad_len = 64 - ((msg_len + 1 + 8) % 64)
    if pad_len == 64 then pad_len = 0 end

    local chunks = { s, "\x80", string.rep("\0", pad_len) }
    -- Append 64-bit big-endian representation of bit_len.
    -- Lua integers are 64-bit, so this always fits.
    chunks[#chunks + 1] = string.char(
      (bit_len >> 56) & 0xff,
      (bit_len >> 48) & 0xff,
      (bit_len >> 40) & 0xff,
      (bit_len >> 32) & 0xff,
      (bit_len >> 24) & 0xff,
      (bit_len >> 16) & 0xff,
      (bit_len >>  8) & 0xff,
       bit_len        & 0xff
    )

    local padded = table.concat(chunks)
    assert(#padded % 64 == 0, "sha256: internal padding error")

    -- Initialise hash state
    local h = {}
    for i = 1, 8 do h[i] = H0[i] end

    -- Process each 64-byte block
    for offset = 0, #padded - 64, 64 do
      process_block(h, padded, offset)
    end

    -- Produce final digest as lowercase hex
    local result = {}
    for i = 1, 8 do
      put_uint32(result, h[i])
    end
    local digest = table.concat(result)
    return digest:gsub(".", function(c)
      return string.format("%02x", c:byte())
    end)
  end
end

-- ---------------------------------------------------------------------------
-- CLI dispatch (placed after all function definitions)
-- ---------------------------------------------------------------------------

local function main()
  local arg1 = arg and arg[1]

  if arg1 == "--help" then
    print_help()
    os.exit(0)
  end

  local modules = parse_manifest(MANIFEST_PATH)

  if arg1 == "--verify" then
    -- First build: emit to OUTPUT_PATH, hash in memory
    local output1 = build(modules)
    write_output(OUTPUT_PATH, output1)
    local hash1 = sha256(output1)

    -- Second build: emit to TMP_PATH, hash in memory
    local output2 = build(modules)
    write_output(TMP_PATH, output2)
    local hash2 = sha256(output2)

    if hash1 == hash2 then
      io.stdout:write("OK: reproducible (sha256: " .. hash1 .. ")\n")
      os.remove(TMP_PATH)
      os.exit(0)
    else
      io.stderr:write("FAIL: build is not reproducible\n")
      io.stderr:write("sha256 first:  " .. hash1 .. "\n")
      io.stderr:write("sha256 second: " .. hash2 .. "\n")
      os.exit(1)
    end

  elseif arg1 == nil then
    local output = build(modules)
    write_output(OUTPUT_PATH, output)
    io.stdout:write("Built dist/paypal-pos.lua\n")
    os.exit(0)

  else
    io.stderr:write("BUILD ERROR: unknown flag: " .. tostring(arg1) .. "\n")
    print_help()
    os.exit(1)
  end
end

main()
