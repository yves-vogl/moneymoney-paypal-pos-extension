-- spec/auth_spec.lua
-- Test scaffold for M_auth (Phase 2, Wave 0 / Wave 1).
-- Contains one sanity test confirming the artifact loads and M_auth is present,
-- plus unit tests for AUTH-02 / AUTH-05 / D-22 pure-logic helpers
-- (_decode_jwt_payload, _extract_client_id) and pending() stubs for
-- orchestration functions (exchange_assertion, fetch_profile, persist_session,
-- cached_token) that land in Plan 02-05 (Wave 3).
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
    -- Wave 3: assert conn:request body contains
    -- grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer
  end)

  pending("exchange_assertion posts client_id and assertion", function()
    -- Wave 3: assert body contains client_id=<extracted> and assertion=<api_key>
  end)

  pending("exchange_assertion includes Accept: application/json header", function()
    -- Wave 3: assert headers table passed to conn:request includes Accept
    -- (Pitfall 1 from RESEARCH: Zettle requires explicit Accept header)
  end)

  -- -------------------------------------------------------------------------
  -- D-21 leg 2: fetch_profile sends Bearer header
  -- -------------------------------------------------------------------------

  pending("fetch_profile posts Bearer header", function()
    -- Wave 3: assert GET /users/self includes Authorization: Bearer <token>
  end)

  -- -------------------------------------------------------------------------
  -- AUTH-04: cached_token expiry and freshness
  -- -------------------------------------------------------------------------

  pending("cached_token expiry", function()
    -- Wave 3: when os.time() >= expires_at - 60, cached_token returns nil
  end)

  pending("cached_token returns access_token when fresh", function()
    -- Wave 3: when expires_at - 60 > os.time(), cached_token returns the token
  end)

  -- -------------------------------------------------------------------------
  -- AUTH-06: cache survives reload
  -- -------------------------------------------------------------------------

  pending("cache survives reload via flat fallback", function()
    -- Wave 3: write flat-key fallback, teardown+reload, assert cached_token
    -- still returns the token (D-23c flat fallback path)
  end)

  -- -------------------------------------------------------------------------
  -- D-22: _decode_jwt_payload edge cases (AUTH-02 / SEC-03)
  -- Precomputed base64url middle segments (RFC 7515 Appendix C, no padding):
  --   {"aud":"client-x"}        => eyJhdWQiOiJjbGllbnQteCJ9
  --   {"aud":["client-x"]}      => eyJhdWQiOlsiY2xpZW50LXgiXX0
  --   {"client_id":"cid-x"}     => eyJjbGllbnRfaWQiOiJjaWQteCJ9
  --   {"sub":"x"}               => eyJzdWIiOiJ4In0
  -- -------------------------------------------------------------------------

  it("_decode_jwt_payload returns nil for nil input", function()
    assert.is_nil(M_auth._decode_jwt_payload(nil))
  end)

  it("_decode_jwt_payload returns nil for malformed input", function()
    -- empty string, single segment, two segments, non-base64url middle
    assert.is_nil(M_auth._decode_jwt_payload(""))
    assert.is_nil(M_auth._decode_jwt_payload("abc"))
    assert.is_nil(M_auth._decode_jwt_payload("abc.def"))
    assert.is_nil(M_auth._decode_jwt_payload("abc.@@@.def"))
  end)

  it("_decode_jwt_payload returns nil for non-JSON payload", function()
    -- middle segment "YWJj" decodes to "abc" — not JSON; pcall catches the error
    assert.is_nil(M_auth._decode_jwt_payload("abc.YWJj.def"))
  end)

  it("_decode_jwt_payload returns table for valid JWT with aud claim", function()
    -- middle: eyJhdWQiOiJjbGllbnQteCJ9 = {"aud":"client-x"}
    local result = M_auth._decode_jwt_payload("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig")
    assert.is_table(result)
    assert.equals("client-x", result.aud)
  end)

  it("_decode_jwt_payload returns table for valid JWT with aud-as-array", function()
    -- middle: eyJhdWQiOlsiY2xpZW50LXgiXX0 = {"aud":["client-x"]}
    local result = M_auth._decode_jwt_payload("hdr.eyJhdWQiOlsiY2xpZW50LXgiXX0.sig")
    assert.is_table(result)
    assert.is_table(result.aud)
    assert.equals("client-x", result.aud[1])
  end)

  -- -------------------------------------------------------------------------
  -- D-22: _extract_client_id claim priority (AUTH-05)
  -- -------------------------------------------------------------------------

  it("_extract_client_id reads aud claim", function()
    -- {"aud":"client-x"} => eyJhdWQiOiJjbGllbnQteCJ9
    local cid = M_auth._extract_client_id("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig")
    assert.equals("client-x", cid)
  end)

  it("_extract_client_id handles aud-as-array shape", function()
    -- {"aud":["client-x"]} => eyJhdWQiOlsiY2xpZW50LXgiXX0
    local cid = M_auth._extract_client_id("hdr.eyJhdWQiOlsiY2xpZW50LXgiXX0.sig")
    assert.equals("client-x", cid)
  end)

  it("_extract_client_id falls back to client_id claim", function()
    -- {"client_id":"cid-x"} => eyJjbGllbnRfaWQiOiJjaWQteCJ9
    local cid = M_auth._extract_client_id("hdr.eyJjbGllbnRfaWQiOiJjaWQteCJ9.sig")
    assert.equals("cid-x", cid)
  end)

  it("_extract_client_id returns nil when neither aud nor client_id", function()
    -- {"sub":"x"} => eyJzdWIiOiJ4In0
    local cid = M_auth._extract_client_id("hdr.eyJzdWIiOiJ4In0.sig")
    assert.is_nil(cid)
  end)

  it("_extract_client_id handles nil input without raising", function()
    assert.is_nil(M_auth._extract_client_id(nil))
  end)

  -- -------------------------------------------------------------------------
  -- D-23c: persist_session cache shape
  -- -------------------------------------------------------------------------

  pending("persist_session writes both nested and flat cache entries", function()
    -- Wave 3: call persist_session, inspect LocalStorage.zettle[orgUuid] and
    -- LocalStorage["zettle:"..orgUuid] for the D-23c dual-path write
  end)

  -- -------------------------------------------------------------------------
  -- ACCT-04: multi-merchant cache isolation
  -- -------------------------------------------------------------------------

  pending("two orgs coexist in cache", function()
    -- Wave 3: write two orgUuid entries to LocalStorage.zettle, assert both
    -- readable and independent (ACCT-04 / Pitfall 6)
  end)

end)
