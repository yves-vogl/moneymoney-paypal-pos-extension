-- spec/auth_spec.lua
-- Test scaffold for M_auth (Phase 2, Wave 0 / Wave 1 / Wave 3).
-- Contains one sanity test confirming the artifact loads and M_auth is present,
-- plus unit tests for AUTH-02 / AUTH-05 / D-22 pure-logic helpers
-- (_decode_jwt_payload, _extract_client_id) and greened orchestration tests
-- (exchange_assertion, fetch_profile, persist_session, cached_token)
-- that land in Plan 02-05 (Wave 3).
--
-- Setup: before_each re-loads the artifact after Mocks.setup() so that each
-- test starts with a clean module-local state (including _conn, token cache).
-- This matches the before_each pattern from spec/log_redaction_spec.lua L41-48.

-- luacheck: ignore 631

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

  it("exchange_assertion posts grant_type", function()
    local raw = Fixtures.load("auth/token_ok")
    Mocks.push_response({ content = raw })
    -- api_key: a synthetic JWT with aud="client-x" payload (base64url middle segment)
    M_auth.exchange_assertion("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig", "client-x")
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made")
    assert.equals("https://oauth.zettle.com/token", Mocks._last_request.url)
    -- ':' is encoded as %3A; '-' is NOT percent-encoded per MM.urlencode alphabet [A-Za-z0-9%-_%.~]
    -- Using Lua pattern mode (plain=false): %% is literal %, %- is literal -, %. is literal dot
    local body = Mocks._last_request.body or ""
    assert.is_not_nil(body:find("grant_type=urn%%3Aietf%%3Aparams%%3Aoauth%%3Agrant%-type%%3Ajwt%-bearer"),
      "body must contain percent-encoded grant_type")
  end)

  it("exchange_assertion posts client_id and assertion", function()
    local raw = Fixtures.load("auth/token_ok")
    Mocks.push_response({ content = raw })
    M_auth.exchange_assertion("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig", "client-x")
    local body = Mocks._last_request.body or ""
    -- '-' is in the safe alphabet so client-x stays as client-x (no encoding)
    assert.is_not_nil(body:find("client_id=client%-x"),
      "body must contain client_id=client-x")
    -- '.' is in the safe alphabet; base64url segments keep their dots
    -- Note: in Lua pattern mode, %% = literal %, %. = literal dot, %- = literal hyphen
    assert.is_not_nil(body:find("assertion=hdr%.eyJhdWQiOiJjbGllbnQteCJ9%.sig"),
      "body must contain assertion=<api_key>")
  end)

  it("exchange_assertion includes Accept: application/json header", function()
    local raw = Fixtures.load("auth/token_ok")
    Mocks.push_response({ content = raw })
    M_auth.exchange_assertion("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig", "client-x")
    assert.is_not_nil(Mocks._last_request, "expected a request to have been made")
    local hdrs = Mocks._last_request.headers or {}
    assert.equals("application/json", hdrs["Accept"])
  end)

  it("exchange_assertion content type is x-www-form-urlencoded", function()
    local raw = Fixtures.load("auth/token_ok")
    Mocks.push_response({ content = raw })
    M_auth.exchange_assertion("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig", "client-x")
    assert.equals("application/x-www-form-urlencoded", Mocks._last_request.contentType)
  end)

  -- -------------------------------------------------------------------------
  -- ERR-01 / D-61 / ADR-0005 Invariant 1: token-mint invalid_grant → LoginFailed
  -- Regression test using existing Phase-2 fixture; no source change required.
  -- The Phase-2 _infer_status branch maps {"error":"invalid_grant"} → 400,
  -- which M_errors.from_http_status then routes to LoginFailed (D-24 case 3).
  -- This test asserts the full round-trip so any future refactor to either
  -- M_http._infer_status OR M_errors.from_http_status surfaces here.
  -- -------------------------------------------------------------------------

  it("ERR-01 / D-61: exchange_assertion 400 invalid_grant maps to LoginFailed via M_errors", function()
    local raw = Fixtures.load("auth/token_invalid_grant")
    Mocks.push_response({ content = raw })
    local _, status, raw_body = M_auth.exchange_assertion("hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig", "client-x")
    assert.equals(400, status, "expected _infer_status to map invalid_grant body to 400")
    assert.equals(LoginFailed, M_errors.from_http_status(status, raw_body),
      "ERR-01: invalid_grant must surface LoginFailed constant per D-61")
  end)

  -- -------------------------------------------------------------------------
  -- D-21 leg 2: fetch_profile sends Bearer header
  -- -------------------------------------------------------------------------

  it("fetch_profile posts Bearer header", function()
    local raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = raw })
    local profile = M_auth.fetch_profile("AT-12345")
    assert.equals("https://oauth.zettle.com/users/self", Mocks._last_request.url)
    local hdrs = Mocks._last_request.headers or {}
    assert.equals("Bearer AT-12345", hdrs["Authorization"])
    assert.is_string(profile.organizationUuid)
    assert.is_true(#profile.organizationUuid > 0)
  end)

  it("fetch_profile never echoes the access token in any captured print", function()
    local raw = Fixtures.load("auth/users_self_ok")
    Mocks.push_response({ content = raw })
    M_auth.fetch_profile("AT-SECRET-XYZ")
    for _, line in ipairs(Mocks._captured_prints) do
      assert.is_nil(line:find("AT-SECRET-XYZ", 1, true),
        "captured print must not contain the access token literal")
    end
  end)

  -- -------------------------------------------------------------------------
  -- AUTH-04: cached_token expiry and freshness
  -- -------------------------------------------------------------------------

  it("cached_token expiry", function()
    local now = os.time()
    -- Expired: expires_at is 100s in the past
    LocalStorage.zettle = { ["org-1"] = { access_token = "AT-old", expires_at = now - 100 } }
    assert.is_nil(M_auth.cached_token("org-1"), "should return nil for expired entry")

    -- Within 60s guard: expires_at is 30s in the future (now + 30 < now + 60 guard)
    LocalStorage.zettle["org-1"] = { access_token = "AT-near", expires_at = now + 30 }
    assert.is_nil(M_auth.cached_token("org-1"), "should return nil when within 60s guard")
  end)

  it("cached_token returns access_token when fresh", function()
    local now = os.time()
    -- Fresh: expires_at is 3600s in the future (well beyond 60s guard)
    LocalStorage.zettle = { ["org-1"] = { access_token = "AT-fresh", expires_at = now + 3600 } }
    assert.equals("AT-fresh", M_auth.cached_token("org-1"))
  end)

  -- -------------------------------------------------------------------------
  -- AUTH-06: cache survives reload via flat fallback
  -- -------------------------------------------------------------------------

  it("cache survives reload via flat fallback", function()
    -- Write session to both nested and flat paths via persist_session
    M_auth.persist_session(
      { access_token = "AT-flat", expires_in = 7200 },
      { uuid = "user-1", organizationUuid = "org-flat", publicName = "Flat Café" },
      "client-flat"
    )
    -- Simulate Q5: nested table lost (e.g. across MoneyMoney restart)
    LocalStorage.zettle = nil
    -- Flat-string fallback must still return the token
    assert.equals("AT-flat", M_auth.cached_token("org-flat"),
      "cached_token must fall through to flat-string path when nested is nil")
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

  it("persist_session writes both nested and flat cache entries", function()
    M_auth.persist_session(
      { access_token = "AT-1", expires_in = 7200 },
      { uuid = "user-1", organizationUuid = "org-1", publicName = "Beispiel Café" },
      "client-x"
    )
    -- Nested path
    assert.is_table(LocalStorage.zettle, "LocalStorage.zettle must be a table")
    assert.is_table(LocalStorage.zettle["org-1"], "nested entry must exist")
    assert.equals("AT-1", LocalStorage.zettle["org-1"].access_token)
    -- Flat path
    assert.equals("string", type(LocalStorage["zettle:org-1"]),
      "flat cache entry must be a JSON string")
    -- Round-trip verify
    local decoded = JSON(LocalStorage["zettle:org-1"]):dictionary()
    assert.equals("AT-1", decoded.access_token)
    assert.equals("Beispiel Café", decoded.publicName)
  end)

  -- -------------------------------------------------------------------------
  -- B-02 defensive guard in persist_session (S-01 belt-and-suspenders)
  -- -------------------------------------------------------------------------

  it("persist_session with nil organizationUuid returns nil and does not crash (B-02)", function()
    -- profile table with no organizationUuid field simulates a malformed
    -- /users/self 200 response. Without the defensive guard in persist_session,
    -- _cache_write(nil, entry) throws "table index is nil".
    local result = M_auth.persist_session(
      { access_token = "AT-2", expires_in = 7200 },
      { uuid = "user-2" },  -- organizationUuid intentionally absent
      "client-y"
    )
    -- Must return nil cleanly (no crash, no partial write)
    assert.is_nil(result)
    assert.is_nil(LocalStorage.zettle)
  end)

  it("persist_session with empty-string organizationUuid returns nil and does not crash (B-02)", function()
    -- Empty string is structurally invalid as a cache key; guard must reject it.
    local result = M_auth.persist_session(
      { access_token = "AT-3", expires_in = 7200 },
      { uuid = "user-3", organizationUuid = "" },
      "client-z"
    )
    assert.is_nil(result)
    assert.is_nil(LocalStorage.zettle)
  end)

  -- -------------------------------------------------------------------------
  -- ACCT-04: multi-merchant cache isolation
  -- -------------------------------------------------------------------------

  it("two orgs coexist in cache", function()
    M_auth.persist_session(
      { access_token = "AT-org1", expires_in = 7200 },
      { uuid = "user-1", organizationUuid = "org-1", publicName = "Merchant A" },
      "client-a"
    )
    M_auth.persist_session(
      { access_token = "AT-org2", expires_in = 7200 },
      { uuid = "user-2", organizationUuid = "org-2", publicName = "Merchant B" },
      "client-b"
    )
    -- Both nested entries must survive
    assert.equals("AT-org1", M_auth.cached_token("org-1"),
      "org-1 token must still be accessible after org-2 was written")
    assert.equals("AT-org2", M_auth.cached_token("org-2"),
      "org-2 token must be accessible")
    -- Both keys must exist in nested table
    assert.is_not_nil(LocalStorage.zettle["org-1"])
    assert.is_not_nil(LocalStorage.zettle["org-2"])
  end)

  -- -------------------------------------------------------------------------
  -- SEC-03 / AUTH-05: API key never written to LocalStorage
  -- -------------------------------------------------------------------------

  -- -------------------------------------------------------------------------
  -- Plan 05-04 / ERR-01: explicit regression gate using the round-trip path
  -- through InitializeSession2 (the actual MoneyMoney entry boundary).
  -- The Phase-2 test above (line 110) verifies the M_errors.from_http_status
  -- mapping in isolation; this test exercises the full round-trip so any
  -- future refactor to either InitializeSession2's error routing OR
  -- exchange_assertion's transport surfaces here as a Phase-2 regression.
  -- Regression-only: if this fails, do NOT silently rewrite Phase-2 behavior
  -- in Plan 05-04 — root-cause + fix in a separate `fix(02):` commit.
  -- -------------------------------------------------------------------------
  describe("ERR-01 (Phase-5 regression) LoginFailed on invalid_grant", function()
    it("InitializeSession2 returns the LoginFailed constant on invalid_grant (ERR-01)", function()
      local raw = Fixtures.load("auth/token_invalid_grant")
      Mocks.push_response({ content = raw })
      -- Mint-time invalid_grant: _infer_status maps {"error":"invalid_grant"} → 400,
      -- M_errors.from_http_status routes 400 → LoginFailed, InitializeSession2
      -- returns it verbatim (no i18n wrapping — MoneyMoney handles the special UI).
      local api_key = "hdr.eyJhdWQiOiJjbGllbnQteCJ9.sig"
      local result = InitializeSession2(ProtocolWebBanking, "PayPal POS", nil, api_key, true)
      assert.equals(LoginFailed, result,
        "ERR-01: InitializeSession2 must return the LoginFailed constant verbatim "
        .. "(NOT a German string) so MoneyMoney shows its credential re-prompt UI.")
    end)
  end)

  -- -------------------------------------------------------------------------
  -- Plan 05-04 / ERR-04: post-mint 401 → error.token_revoked German string.
  -- Justified exception to D-43 documented in src/purchases.lua and src/finance.lua.
  -- _infer_status maps {"error":"invalid_client"} → 401 (per src/http.lua:128-129).
  -- The 401-direct-check intercepts at the iterator boundary (Plan-deviation per
  -- Rule 1; see SUMMARY) and returns the German string from M_i18n.
  -- -------------------------------------------------------------------------
  describe("ERR-04 token-revoked on post-mint 401", function()
    it("RefreshAccount returns error.token_revoked German string when purchase fetch 401s after successful mint (ERR-04)", function()
      -- Seed a fresh cached token so RefreshAccount skips re-auth (D-41).
      LocalStorage["zettle:org-err04"] = JSON():set({
        access_token = "AT-WAS-VALID",
        expires_at   = os.time() + 7200,
        obtained_at  = os.time(),
        client_id    = "client-x",
        uuid         = "u-1",
        publicName   = "Beispiel Caf\195\169",
      }):json()

      -- Queue an invalid_client body for the FIRST resource call (purchases page 1).
      -- _infer_status maps {"error":"invalid_client"} → 401.
      Mocks.push_response({ content = '{"error":"invalid_client"}' })

      local account = { accountNumber = "org-err04", currency = "EUR", balance = 0 }
      local result = RefreshAccount(account, 0)

      -- ERR-04 contract: returns a STRING (not a table), containing the German
      -- token_revoked text. The exact i18n value lives in Plan 05-02; we assert
      -- on the unambiguous prefix "Anmeldung verloren" so future locale changes
      -- to the tail (e.g. punctuation) don't break the test.
      assert.is_string(result,
        "RefreshAccount must return a STRING on ERR-04, got: " .. type(result))
      assert.is_not_nil(result:find("Anmeldung verloren", 1, true),
        "ERR-04: result must contain the German token_revoked prefix "
        .. "'Anmeldung verloren', got: " .. tostring(result))
      -- Exact i18n value match (locked at Plan 05-02 i18n).
      assert.equals(M_i18n.t("error.token_revoked"), result,
        "ERR-04: result must equal the M_i18n.t('error.token_revoked') value verbatim "
        .. "(no rewrapping by error.network or other layers).")
    end)
  end)

  it("persist_session never writes the api_key anywhere in LocalStorage", function()
    -- Simulate the full session-init sequence:
    -- decode api_key -> extract client_id -> exchange -> fetch -> persist
    --
    -- Segments are chosen to be unique and longer than trivial 3-char strings
    -- (e.g. "sig", "hdr") that can collide with fixture UUIDs or token values.
    -- Aligned with the gating-spec pattern (log_redaction_spec.lua:279-286):
    -- iterate over each dot-separated segment individually rather than checking
    -- a fixed prefix so the guard holds for any future synthetic key shape.
    --
    -- APIKEYHEADER and APIKEYSIG99 are uppercase tokens that do not appear in
    -- any fixture file or in the base64url alphabet, so no collision is possible.
    local api_key = "APIKEYHEADER.eyJhdWQiOiJjbGllbnQteCJ9.APIKEYSIG99"
    local client_id = M_auth._extract_client_id(api_key)  -- "client-x"
    assert.equals("client-x", client_id)

    -- exchange_assertion needs a queued response
    Mocks.push_response({ content = Fixtures.load("auth/token_ok") })
    local token_table = M_auth.exchange_assertion(api_key, client_id)

    -- fetch_profile needs a queued response
    Mocks.push_response({ content = Fixtures.load("auth/users_self_ok") })
    local profile = M_auth.fetch_profile(token_table.access_token)

    M_auth.persist_session(token_table, profile, client_id)

    -- Recursive LocalStorage walker: visits every string value in the table.
    -- Per-segment check aligned with log_redaction_spec.lua:279-286.
    local function walk(t, prefix)
      for k, v in pairs(t) do
        local path = prefix .. "." .. tostring(k)
        if type(v) == "string" then
          for seg in api_key:gmatch("[^.]+") do
            assert.is_nil(v:find(seg, 1, true),
              "LocalStorage" .. path .. " must not contain JWT segment '" .. seg .. "'")
          end
        elseif type(v) == "table" then
          walk(v, path)
        end
      end
    end
    walk(LocalStorage, "")
  end)

end)
