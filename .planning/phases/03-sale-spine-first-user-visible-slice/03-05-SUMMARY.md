---
phase: 03-sale-spine-first-user-visible-slice
plan: 05
subsystem: api
tags: [purchases, http-fetch, url-encoding, pagination, bearer-auth, lua, zettle]

requires:
  - phase: 02-authenticated-network-layer
    provides: M_http.get_json, M_auth.cached_token, M_errors.from_http_status, MM.urlencode mock

provides:
  - M_purchases.fetch(clamped_since, bearer, cursor) — single-page GET to purchase.izettle.com/purchases/v2
  - M_purchases.fetch_all(clamped_since, bearer) — full cursor loop delegating to M_pagination.iterate
  - _url_encode_query(params) — sorted alphabetical percent-encoded query string builder
  - _iso8601_utc(posix) — POSIX to UTC ISO-8601 formatter
  - _inline_iterate(fetch_page_fn, initial_params) — fallback cursor loop for parallel-plan window
  - spec/purchases_spec.lua — 10 passing tests for URL shape, Bearer header, error routing, pagination

affects:
  - 03-04-pagination (M_pagination.iterate supersedes _inline_iterate once merged)
  - 03-06-entry (RefreshAccount will call M_purchases.fetch_all)
  - 03-07-ci-gate (egress grep now shows purchase.izettle.com in artifact)

tech-stack:
  added: []
  patterns:
    - "sorted URL-encoded query string via _url_encode_query (mirrors _form_encode in http.lua)"
    - "_iso8601_utc uses os.date(!%Y-%m-%dT%H:%M:%SZ, posix) for UTC formatting"
    - "M_pagination.iterate delegation with inline fallback for parallel-plan window"
    - "M_http.get_json 3-tuple returned verbatim from fetch (D-43 error routing)"

key-files:
  created:
    - spec/purchases_spec.lua (filled from Wave-0 scaffold — 10 passing tests)
  modified:
    - src/purchases.lua (filled from Phase-1 stub — 148 lines)

key-decisions:
  - "fetch(clamped_since, bearer, cursor) — positional args per planner authority; account not passed (entry.lua extracts orgUuid)"
  - "fetch_all uses M_pagination.iterate when available; falls back to _inline_iterate during Wave-3 parallel-plan window (Plan 03-04 not yet merged)"
  - "startDate query param: os.date(!%Y-%m-%dT%H:%M:%SZ, posix) with MM.urlencode encoding colons as %3A"
  - "No new log call sites (D-45): Authorization header never logged; M_http.get_json logs only the URL"
  - "Single egress host literal: purchase.izettle.com (one code line, not in comments)"

requirements-completed: [SALE-06]

duration: 8min
completed: 2026-06-20
---

# Phase 3 Plan 05: Purchases Fetch Summary

**Single-page GET to purchase.izettle.com/purchases/v2 via M_http.get_json with Bearer header, sorted ISO-8601 startDate, and cursor pagination — 10 passing unit specs**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-20T16:50:04Z
- **Completed:** 2026-06-20T16:58:05Z
- **Tasks:** 2
- **Files modified:** 2 (src/purchases.lua, spec/purchases_spec.lua)

## Accomplishments

- Implemented `M_purchases.fetch(clamped_since, bearer, cursor)` delegating to `M_http.get_json` with alphabetically sorted, percent-encoded query params (descending, lastPurchaseHash when non-nil, limit, startDate)
- Implemented `M_purchases.fetch_all(clamped_since, bearer)` that delegates to `M_pagination.iterate` when available, falling back to an inline cursor loop during the parallel-plan window before Plan 03-04 merges
- Turned 8 pending spec tests into 10 passing `it()` assertions covering URL host, Bearer header, startDate ISO-8601 encoding, limit, descending, lastPurchaseHash presence/absence, error routing, and two-page pagination

## Task Commits

1. **Task 1: Fill src/purchases.lua with M_purchases.fetch + fetch_all** - `5db6df3` (feat)
2. **Task 2: Fill spec/purchases_spec.lua (Wave-0 pending → passing)** - `0c1bf61` (test)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `src/purchases.lua` — 148 lines; two public functions (`fetch`, `fetch_all`) + two private helpers (`_iso8601_utc`, `_url_encode_query`) + inline fallback `_inline_iterate`
- `spec/purchases_spec.lua` — 10 passing `it()` tests; 0 pending; `Fixtures` added alongside `Mocks`

## URL Shape Verified

```
https://purchase.izettle.com/purchases/v2?descending=false&limit=200&startDate=2023-11-14T22%3A13%3A20Z
```

- Keys in alphabetical order: `descending`, `limit`, `startDate` (and `lastPurchaseHash` when cursor present)
- Colons URL-encoded as `%3A` (via `MM.urlencode`)
- `Mocks._last_request.url` introspection confirms the shape in Test 1–6

## Bearer Header Verified

```lua
Authorization = "Bearer AT-VALID"
```

- Concatenation occurs only inside the `headers` table local; `M_http.get_json` logs only the URL (D-45 / T-03-W3b-01)
- Confirmed by Test 2: `Mocks._last_request.headers["Authorization"] == "Bearer AT-VALID"`

## nil-token Guard (D-41)

`fetch_all` does not call `M_auth.cached_token` — that responsibility is at the `entry.lua` RefreshAccount boundary (Plan 03-06). `fetch` accepts `bearer` as a pre-fetched string parameter, so nil-token guard is enforced upstream.

## Egress Hosts in Artifact (Post-Plan)

```
oauth.zettle.com   — Phase 2 (auth)
purchase.izettle.com — Phase 3 (this plan, first appearance)
```

No `finance.izettle.com` (Phase 4 territory). Single URL literal in src/purchases.lua.

## Reproducible Build

SHA256: `8414d65dc24bfbc1f0d6114bf73c51fa41d2eff5575517f93df42e6eda8787dd`

## Full Suite Results

```
166 successes / 2 failures / 0 errors / 7 pending : 7.63 seconds
```

- Failures: both in `spec/refresh_idempotency_spec.lua` (Wave 4 / Plan 03-06 — expected RED)
- Pending: 7 in `spec/pagination_spec.lua` (Plan 03-04, parallel — expected)
- All prior specs (auth, http, errors, entry, mapping, log_redaction) remain GREEN

## Decisions Made

- **fetch signature** — `fetch(clamped_since, bearer, cursor)` per PLAN task action; the `account` parameter is not passed to `fetch` (entry.lua extracts `orgUuid` for `cached_token`, passes the bearer string directly)
- **inline fallback** — `_inline_iterate` added inside `purchases.lua` to enable spec Test 8 to pass in the parallel-plan window (Plan 03-04 not yet merged). Superseded once `M_pagination.iterate` is defined. Documented as Rule 2 deviation.
- **one egress host literal** — comment references to `purchase.izettle.com` removed from inline docs to keep `grep -c` at exactly 1 (acceptance criterion)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added _inline_iterate fallback in src/purchases.lua**
- **Found during:** Task 2 (spec activation)
- **Issue:** `M_pagination.iterate` is nil when Plan 03-04 has not yet merged; calling `nil` errors; Test 8 (fetch_all pagination) would fail
- **Fix:** Added `_inline_iterate(fetch_page_fn, initial_params)` inside `purchases.lua`; `fetch_all` calls it when `type(M_pagination.iterate) ~= "function"`
- **Files modified:** src/purchases.lua
- **Verification:** Test 8 and Test 9 both pass with the fallback; will delegate to real `M_pagination.iterate` once 03-04 lands
- **Committed in:** `5db6df3` (Task 1 commit)

**2. [Rule 1 - Bug] Fixed `%%3A` pattern in Test 3 (url:find plain-text search)**
- **Found during:** Task 2 first run (Test 3 failure)
- **Issue:** `url:find("%%3A", 1, true)` with `plain=true` searches for the literal string `%%3A` (two percent signs), not `%3A`; the assertion returned nil even though `%3A` was correctly present in the URL
- **Fix:** Changed to `url:find("%3A", 1, true)` (plain-text search for single percent sign + 3A) and `url:find("2023-11-14T22%3A13%3A20Z", 1, true)` for full-value assertion
- **Files modified:** spec/purchases_spec.lua
- **Verification:** Test 3 passes; URL contains `startDate=2023-11-14T22%3A13%3A20Z`
- **Committed in:** `0c1bf61` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 bug)
**Impact on plan:** Both auto-fixes necessary for correctness. No scope creep.

## Issues Encountered

None beyond the two auto-fixed deviations above.

## Known Stubs

None — `M_purchases.fetch` and `M_purchases.fetch_all` are fully implemented. The `_inline_iterate` fallback is intentional and documented (not a stub — it is production-correct code that will be superseded by Plan 03-04).

## Threat Flags

None — no new threat surface beyond what is documented in the plan's threat model:
- Bearer token flows through Phase-2's `M_http.get_json` headers (never logged, T-02-04-02 confirmed)
- Single egress host literal: `purchase.izettle.com` (no Phase-4 `finance.izettle.com`)
- URL query param values are deterministic (POSIX number → ISO-8601 string → `MM.urlencode`)

## Next Phase Readiness

- `M_purchases.fetch` and `M_purchases.fetch_all` ready for Plan 03-06 (entry.lua wiring)
- Once Plan 03-04 lands: `M_pagination.iterate` will supersede `_inline_iterate`; no changes needed in purchases.lua
- Plan 03-07 (CI egress gate) will confirm `purchase.izettle.com` now appears in the artifact

## Self-Check: PASSED

- `src/purchases.lua` EXISTS
- `spec/purchases_spec.lua` EXISTS
- Commit `5db6df3` EXISTS
- Commit `0c1bf61` EXISTS
- `wc -l src/purchases.lua` = 148 (>= 60 requirement met)

---
*Phase: 03-sale-spine-first-user-visible-slice*
*Completed: 2026-06-20*
