-- spec/auth_spec.lua
-- Test scaffold for M_auth (Phase 2, Wave 0).
-- Contains one sanity test confirming the artifact loads and M_auth is present,
-- plus pending() stubs for every AUTH-02/04/06 test command in
-- .planning/phases/02-authenticated-network-layer/02-VALIDATION.md (❌ W0 rows).
-- Wave 2 fills in the pending assertions once src/auth.lua is implemented.
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so that each
-- test starts with a clean module-local state (including _conn, token cache).
-- This matches the before_each pattern from spec/log_redaction_spec.lua L41-48.

local Mocks    = require("spec.helpers.mm_mocks")
local Fixtures = require("spec.helpers.fixtures")

-- Build a fresh artifact once before the suite.
do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("auth_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

-- ---------------------------------------------------------------------------
describe("M_auth", function()

  before_each(function()
    Mocks.setup()
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- -------------------------------------------------------------------------
  -- Sanity tests (non-pending) — confirm artifact loads and M_auth is present
  -- -------------------------------------------------------------------------

  it("M_auth module table is exposed", function()
    assert.is_table(M_auth)
  end)

  it("Fixtures.load reads auth/token_ok", function()
    local raw = Fixtures.load("auth/token_ok")
    assert.is_string(raw)
  end)

  -- -------------------------------------------------------------------------
  -- AUTH-02: exchange_assertion posts the correct OAuth grant body
  -- -------------------------------------------------------------------------

  pending("exchange_assertion posts grant_type", function()
    -- Wave 2: assert conn:request body contains
    -- grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer
  end)

  pending("exchange_assertion posts client_id and assertion", function()
    -- Wave 2: assert body contains client_id=<extracted> and assertion=<api_key>
  end)

  pending("exchange_assertion includes Accept: application/json header", function()
    -- Wave 2: assert headers table passed to conn:request includes Accept
    -- (Pitfall 1 from RESEARCH: Zettle requires explicit Accept header)
  end)

  -- -------------------------------------------------------------------------
  -- D-21 leg 2: fetch_profile sends Bearer header
  -- -------------------------------------------------------------------------

  pending("fetch_profile posts Bearer header", function()
    -- Wave 2: assert GET /users/self includes Authorization: Bearer <token>
  end)

  -- -------------------------------------------------------------------------
  -- AUTH-04: cached_token expiry and freshness
  -- -------------------------------------------------------------------------

  pending("cached_token expiry", function()
    -- Wave 2: when os.time() >= expires_at - 60, cached_token returns nil
  end)

  pending("cached_token returns access_token when fresh", function()
    -- Wave 2: when expires_at - 60 > os.time(), cached_token returns the token
  end)

  -- -------------------------------------------------------------------------
  -- AUTH-06: cache survives reload
  -- -------------------------------------------------------------------------

  pending("cache survives reload via flat fallback", function()
    -- Wave 2: write flat-key fallback, teardown+reload, assert cached_token
    -- still returns the token (D-23c flat fallback path)
  end)

  -- -------------------------------------------------------------------------
  -- D-22: _decode_jwt_payload edge cases
  -- -------------------------------------------------------------------------

  pending("_decode_jwt_payload returns nil for malformed input", function()
    -- Wave 2: pass a non-JWT string (no dots), assert nil returned
  end)

  pending("_decode_jwt_payload returns nil for non-JSON payload", function()
    -- Wave 2: pass a JWT whose middle segment decodes to non-JSON, assert nil
    -- (Pitfall 2 from RESEARCH: payload must be valid JSON)
  end)

  pending("_extract_client_id reads aud claim", function()
    -- Wave 2: JWT payload with aud=<uuid>, assert client_id == <uuid>
  end)

  pending("_extract_client_id falls back to client_id claim", function()
    -- Wave 2: JWT payload with no aud but client_id=<uuid>, assert fallback used
  end)

  pending("_extract_client_id returns nil when neither aud nor client_id", function()
    -- Wave 2: JWT payload with neither claim, assert nil returned
  end)

  -- -------------------------------------------------------------------------
  -- D-23c: persist_session cache shape
  -- -------------------------------------------------------------------------

  pending("persist_session writes both nested and flat cache entries", function()
    -- Wave 2: call persist_session, inspect LocalStorage.zettle[orgUuid] and
    -- LocalStorage["zettle:"..orgUuid] for the D-23c dual-path write
  end)

  -- -------------------------------------------------------------------------
  -- ACCT-04: multi-merchant cache isolation
  -- -------------------------------------------------------------------------

  pending("two orgs coexist in cache", function()
    -- Wave 2: write two orgUuid entries to LocalStorage.zettle, assert both
    -- readable and independent (ACCT-04 / Pitfall 6)
  end)

end)
