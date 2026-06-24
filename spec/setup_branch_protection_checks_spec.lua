-- spec/setup_branch_protection_checks_spec.lua
-- P6-R-14 — assert that every CHECKS entry in tools/setup-branch-protection.sh
-- matches a `name:` declaration in some workflow file under .github/workflows/.
--
-- Why this spec exists
-- --------------------
-- tools/setup-branch-protection.sh registers required status-check contexts
-- with GitHub by NAME. The strings MUST match the `name:` field of the
-- corresponding workflow job byte-identically — if a job is renamed in
-- .github/workflows/*.yml without an in-lockstep update to the CHECKS array
-- (lines 50-56 of the script), branch protection will refuse to merge any
-- PR until the missing context arrives (which it never will). Failure mode:
-- silent — `gh api … /protection` does not validate that the contexts
-- actually correspond to jobs.
--
-- This spec walks both sides:
--   1. Extract CHECKS=("…" "…" …) from tools/setup-branch-protection.sh
--   2. Grep `^[[:space:]]*name: …` from every .github/workflows/*.yml
--   3. For each CHECKS entry, assert the string appears somewhere in the
--      union of workflow `name:` declarations. (Set-membership, not
--      set-equality — workflows may declare jobs we do NOT enforce as
--      required status checks.)
--
-- Implementation note: parses with shell + Lua patterns rather than a
-- YAML parser so the spec stays portable (no yaml-lua rock dependency).

-- ---------------------------------------------------------------------------
-- Extract CHECKS array entries from the shell script.
-- Format being parsed (lines 50-56 of tools/setup-branch-protection.sh):
--   declare -a CHECKS=(
--     "Lint + tests + reproducible build"
--     "gitleaks secret scan"
--     ...
--   )
local function parse_checks_array(path)
  local f = assert(io.open(path, "rb"),
    "P6-R-14: cannot open " .. path)
  local content = f:read("*a")
  f:close()
  local out = {}
  -- Locate the array body, then pull every double-quoted string up to the
  -- closing paren. The trailing-paren guard prevents over-running into
  -- later code (e.g. an unrelated heredoc with stray quoted strings).
  local body = content:match("declare%s+%-a%s+CHECKS=%((.-)%)")
  assert(body, "P6-R-14: could not find `declare -a CHECKS=(...)` in " .. path)
  for entry in body:gmatch('"([^"]+)"') do
    out[#out + 1] = entry
  end
  return out
end

-- Extract every `name: …` declaration from a single workflow file.
-- Tolerates both quoted and unquoted YAML strings; ignores comments.
-- The Conventional-Commits gate (commit-lint.yml) declares BOTH
-- workflow-level `name:` and job-level `name:`; we want both because
-- GitHub uses the job-level name as the status-context string.
local function extract_workflow_names(path)
  local f = assert(io.open(path, "rb"),
    "P6-R-14: cannot open " .. path)
  local content = f:read("*a")
  f:close()
  local names = {}
  for line in content:gmatch("[^\n]+") do
    -- Strip a trailing comment so `name: foo # bar` parses cleanly.
    local nocomment = line:gsub("%s+#.*$", "")
    local n = nocomment:match("^%s*name:%s*(.+)%s*$")
    if n then
      -- Strip surrounding quotes if present.
      n = n:gsub('^"(.-)"$', "%1"):gsub("^'(.-)'$", "%1")
      -- Trim.
      n = n:gsub("^%s+", ""):gsub("%s+$", "")
      names[#names + 1] = n
    end
  end
  return names
end

-- Union all `name:` declarations across every workflow file.
local function collect_all_workflow_names()
  local handle = assert(io.popen("ls .github/workflows/*.yml 2>/dev/null"),
    "P6-R-14: ls .github/workflows failed")
  local all = {}
  local set = {}
  for path in handle:lines() do
    for _, n in ipairs(extract_workflow_names(path)) do
      if not set[n] then
        set[n] = path
        all[#all + 1] = n
      end
    end
  end
  handle:close()
  return all, set
end

-- ---------------------------------------------------------------------------
describe("P6-R-14: setup-branch-protection CHECKS array matches workflow job names", function()

  it("every CHECKS entry corresponds to a declared workflow `name:`", function()
    local checks = parse_checks_array("tools/setup-branch-protection.sh")
    assert.is_true(#checks >= 1,
      "expected at least one CHECKS entry; parsing may have failed")

    local _, workflow_name_set = collect_all_workflow_names()
    assert.is_true(next(workflow_name_set) ~= nil,
      "expected at least one workflow `name:` declaration; parsing may have failed")

    for _, ctx in ipairs(checks) do
      assert.is_truthy(workflow_name_set[ctx],
        "P6-R-14: CHECKS entry '" .. ctx .. "' does NOT match any workflow `name:` declaration. " ..
        "Either rename a job in .github/workflows/*.yml to match, or remove the entry from " ..
        "tools/setup-branch-protection.sh's CHECKS array.")
    end
  end)

  it("at least 5 CHECKS entries are registered (post-Phase-6.1 baseline)", function()
    -- Defensive floor: Phase 6.1 expanded CHECKS to 5 entries. A future
    -- accidental truncation (e.g. an editor mishap or partial rebase) that
    -- shrinks the array would silently weaken branch protection. The floor
    -- catches it.
    local checks = parse_checks_array("tools/setup-branch-protection.sh")
    assert.is_true(#checks >= 5,
      "P6-R-14: CHECKS array has " .. tostring(#checks) ..
      " entries; expected >= 5 since Phase 6.1 (CI test, gitleaks, commit-lint, Scorecard, Semgrep).")
  end)

end)
