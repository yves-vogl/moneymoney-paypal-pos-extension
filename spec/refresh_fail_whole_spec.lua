-- spec/refresh_fail_whole_spec.lua
-- Phase-5 / Plan 05-02 RED scaffold; Plan 05-05 turns GREEN.
-- Gates: ERR-06 fail-whole-refresh (D-66 / ADR-0005 Invariant 6),
--        ERR-05 network failure regression (D-65 / ADR-0005 Invariant 5).
--
-- Phase-4's 16-step RefreshAccount in src/entry.lua is already structurally
-- correct per RESEARCH §5 audit; this spec is a GATING assertion that any
-- future refactor preserves the invariant. Plan 05-03 ships retry behavior
-- (so 3 empty bodies trigger 5xx retries that exhaust → server_busy);
-- Plan 05-05 turns the `pending` blocks below into `it`.

-- luacheck: globals RefreshAccount LocalStorage M_i18n JSON M_auth
-- luacheck: ignore 431
-- luacheck: ignore 631

local Mocks    = require("spec.helpers.mm_mocks") -- luacheck: ignore 211
local Fixtures = require("spec.helpers.fixtures") -- luacheck: ignore 211

do
  local ok, _, code = os.execute("lua tools/build.lua 2>/dev/null")
  if not ok or code ~= 0 then
    error("refresh_fail_whole_spec: failed to build dist/paypal-pos.lua before suite")
  end
end

local function load_artifact()
  dofile("dist/paypal-pos.lua")
end

local function seed_token(orgUuid)
  -- VERBATIM from spec/refresh_idempotency_spec.lua L55-64.
  LocalStorage["zettle:" .. orgUuid] = JSON():set({
    access_token = "AT-VALID",
    expires_at   = os.time() + 7200,
    obtained_at  = os.time(),
    client_id    = "client-x",
    uuid         = "u-1",
    publicName   = "Beispiel Caf\xc3\xa9",
  }):json()
end

describe("RefreshAccount fail-whole-refresh (ERR-06 / D-66 / ADR-0005 Invariant 6)", function()

  before_each(function()
    Mocks.setup()
    _G.MM = _G.MM or {}
    _G.MM.sleep = function(_) end
    load_artifact()
  end)

  after_each(function()
    Mocks.teardown()
  end)

  -- ---------------------------------------------------------------------
  -- GREEN sanity: seed_token + module table exposed
  -- ---------------------------------------------------------------------

  it("seed_token writes a non-JWT-shaped bearer that cached_token returns", function()
    seed_token("org-sanity")
    local bearer = M_auth.cached_token("org-sanity")
    assert.equals("AT-VALID", bearer, "seed_token must yield AT-VALID bearer")
    assert.is_false(bearer:find("eyJ", 1, true) ~= nil,
      "seed_token bearer must NOT be JWT-shaped (SEC-03 false-positive guard)")
  end)

  -- ---------------------------------------------------------------------
  -- RED scaffolds for Plan 05-05 GREEN (ERR-06 + ERR-05 invariants)
  -- ---------------------------------------------------------------------

  pending("ERR-06: mid-pipeline 500 → German error returned, no partial txns, since untouched (D-66)", function()
    -- Plan 05-05 (depends on 05-03 retry shipped):
    --   seed_token; queue 1 purchase success + 3 empty bodies (finance retries exhaust)
    --   call RefreshAccount(account, since_in); assert (a) result is the German
    --   error.server_busy string; (b) Mocks._captured_requests contains the
    --   purchase URL; (c) result is NOT a table (no partial leak); (d) second
    --   RefreshAccount(account, since_in) with full success queue emits transactions.
    error("Plan 05-03 + Plan 05-05 GREEN: requires retry loop + gating assertions")
  end)

  pending("ERR-06: since parameter byte-identically passed across failed refresh + retry (D-66)", function()
    -- Plan 05-05: capture since_in in result1 (German error string); call result2
    -- with the SAME since_in; assert the M_purchases.fetch URL captured in
    -- Mocks._captured_requests[Nth] contains the SAME startDate timestamp
    -- (no drift, no advance — D-66 invariant).
    error("Plan 05-05 GREEN: requires URL-capture spec assertion across two refreshes")
  end)

  pending("ERR-05: network failure (empty body throughout retries) → error.network from RefreshAccount (D-65 / ADR-0005 Invariant 5)", function()
    -- Plan 05-05: queue purchase fetch returning empty body × 3 (5xx retry exhausts);
    -- assert RefreshAccount returns M_i18n.t("error.server_busy") (sentinel-mapped)
    -- — NOT a Lua error, NOT a partial transaction list, NOT a nil. Document that
    -- DNS / connect-refused / socket-timeout all manifest identically via the
    -- existing _infer_status nil path (Phase 2 inheritance).
    error("Plan 05-03 + 05-05 GREEN: requires retry loop + ERR-05 regression assertion")
  end)

end)
