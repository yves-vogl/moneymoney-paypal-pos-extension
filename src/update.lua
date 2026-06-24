-- src/update.lua
-- Phase 7 / D-83: optional Github-Release update check.
--
-- On the first RefreshAccount per UTC-day, perform ONE HTTPS GET against
-- `api.github.com/repos/<repo>/releases/latest`, compare the latest tag_name
-- against this build's __VERSION_TAG__ literal, and surface a German status
-- line via MM.printStatus when a newer stable release is available.
--
-- Contract:
--   * At most ONE api.github.com request per 24h, cached via LocalStorage.
--   * Pre-release tags (rc/beta/alpha/dev) are NEVER suggested as updates.
--   * Network failure is SILENT — never breaks a Refresh, never logs the
--     bearer token (uses no Bearer header here at all; it is an
--     unauthenticated REST call).
--   * Dev builds (__VERSION_TAG__ resolves to "DEV") suppress the check
--     entirely — no spurious "0.0 → 1.0.0" suggestions for local builds.
--   * User opt-out: if the optional second credential field "Update-Check"
--     contains "aus" / "off" / "false" / "0", the check is skipped.
--
-- The egress allowlist gate in ci.yml is extended to permit api.github.com.

do
  M_update.REPO            = "yves-vogl/moneymoney-paypal-pos-extension"
  M_update.CACHE_TTL       = 86400  -- 24 hours in seconds
  M_update.LOCALSTORAGE_K  = "update_check"
  M_update.API_HOST        = "api.github.com"

  -- Filled by entry.lua at module init based on the __VERSION_TAG__ literal.
  M_update.CURRENT_TAG     = nil

  -- ------------------------------------------------------------------------
  -- Pure helpers (testable without network)
  -- ------------------------------------------------------------------------

  -- Parse "v1.2.3" → {1, 2, 3}; non-matching → nil.
  -- Pre-release suffixes ("-rc.1", "-beta.2", "-dev") are REJECTED.
  function M_update._parse_tag(tag)
    if type(tag) ~= "string" then return nil end
    -- Strict: only v<int>.<int>.<int> with no trailing suffix.
    local maj, min, pat = tag:match("^v(%d+)%.(%d+)%.(%d+)$")
    if not maj then return nil end
    return {tonumber(maj), tonumber(min), tonumber(pat)}
  end

  -- Returns true iff `latest` is strictly newer than `current` semver-wise.
  function M_update._is_newer(current_tag, latest_tag)
    local c = M_update._parse_tag(current_tag)
    local l = M_update._parse_tag(latest_tag)
    if not c or not l then return false end
    if l[1] > c[1] then return true end
    if l[1] < c[1] then return false end
    if l[2] > c[2] then return true end
    if l[2] < c[2] then return false end
    return l[3] > c[3]
  end

  -- Returns true iff the user disabled the check via the optional credential.
  function M_update._is_disabled(opt_out_value)
    if type(opt_out_value) ~= "string" then return false end
    local lower = opt_out_value:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return lower == "aus" or lower == "off" or lower == "false" or lower == "0"
      or lower == "no" or lower == "nein"
  end

  -- ------------------------------------------------------------------------
  -- LocalStorage cache
  -- ------------------------------------------------------------------------

  function M_update._cache_read()
    if type(LocalStorage) ~= "table" then return nil end
    local entry = LocalStorage[M_update.LOCALSTORAGE_K]
    if type(entry) ~= "table" then return nil end
    return entry
  end

  function M_update._cache_write(entry)
    if type(LocalStorage) ~= "table" then return end
    LocalStorage[M_update.LOCALSTORAGE_K] = entry
  end

  function M_update._cache_is_fresh(entry, now_unix)
    if type(entry) ~= "table" then return false end
    local ts = tonumber(entry.checked_at)
    if not ts then return false end
    return (now_unix - ts) < M_update.CACHE_TTL
  end

  -- ------------------------------------------------------------------------
  -- Network — single GET against api.github.com/repos/.../releases/latest.
  -- Wrapped in pcall so any error (network, JSON, MM-API quirk) is silent.
  -- ------------------------------------------------------------------------

  function M_update._fetch_latest_tag()
    if type(Connection) ~= "function" then return nil end
    local conn = Connection()
    local ok_conn, content_or_err = pcall(function()
      return conn:request(
        "GET",
        "https://" .. M_update.API_HOST
          .. "/repos/" .. M_update.REPO .. "/releases/latest",
        nil,
        nil,
        {
          ["Accept"]               = "application/vnd.github+json",
          ["X-GitHub-Api-Version"] = "2022-11-28",
          ["User-Agent"]           = "moneymoney-paypal-pos-extension",
        }
      )
    end)
    if not ok_conn or type(content_or_err) ~= "string" then return nil end

    local ok_json, data = pcall(function()
      return JSON(content_or_err):dictionary()
    end)
    if not ok_json or type(data) ~= "table" then return nil end

    if data.prerelease == true or data.draft == true then return nil end
    local tag = data.tag_name
    if type(tag) ~= "string" then return nil end
    if not M_update._parse_tag(tag) then return nil end
    return tag, data.html_url
  end

  -- ------------------------------------------------------------------------
  -- Orchestration — called from RefreshAccount at the very start.
  -- Returns either nil (no notice) or a formatted German status string ready
  -- for MM.printStatus.
  -- ------------------------------------------------------------------------

  function M_update.check(opts)
    opts = opts or {}
    local current_tag = opts.current_tag or M_update.CURRENT_TAG
    if type(current_tag) ~= "string" or current_tag == "DEV" then return nil end
    if not M_update._parse_tag(current_tag) then return nil end
    if M_update._is_disabled(opts.opt_out) then return nil end

    local now = (type(opts.now_unix) == "number") and opts.now_unix or os.time()
    local entry = M_update._cache_read()

    -- Fresh cache: only emit a notice if the cache says an update is pending.
    if M_update._cache_is_fresh(entry, now) then
      if entry.latest_tag
        and M_update._is_newer(current_tag, entry.latest_tag) then
        return string.format(
          M_i18n.t("update.available"),
          entry.latest_tag, current_tag,
          entry.html_url or ""
        )
      end
      return nil
    end

    -- Stale or absent cache: fetch fresh.
    local latest_tag, html_url
    if type(opts.fetch_override) == "function" then
      latest_tag, html_url = opts.fetch_override()
    else
      latest_tag, html_url = M_update._fetch_latest_tag()
    end

    if type(latest_tag) ~= "string" then
      -- Soft cache the failure so we do not hammer the API every refresh.
      M_update._cache_write({
        checked_at  = now,
        latest_tag  = entry and entry.latest_tag or nil,
        html_url    = entry and entry.html_url   or nil,
      })
      return nil
    end

    M_update._cache_write({
      checked_at = now,
      latest_tag = latest_tag,
      html_url   = html_url,
    })

    if M_update._is_newer(current_tag, latest_tag) then
      return string.format(
        M_i18n.t("update.available"),
        latest_tag, current_tag, html_url or ""
      )
    end
    return nil
  end
end
