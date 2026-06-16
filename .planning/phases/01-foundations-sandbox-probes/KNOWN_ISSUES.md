# Phase 1 — Known Issues

Tracked deviations from the original PLAN.md gates that are deferred to a later phase rather than blocking Phase 1 closeout.

---

## KI-01: T07 — luacov produces empty stats with the dofile-of-amalgamated-artifact spec layout — **RESOLVED**

**Resolution date:** 2026-06-16
**Resolved by:** `.luacov` pattern fix (commit on the same Phase-1 branch).

**Root cause (correct):** luacov strips the `.lua` extension from the filename BEFORE applying include/exclude patterns. The original `.luacov` config used `"src/.+%.lua$"` and `"dist/paypal%-pos%.lua$"` which therefore could never match — `dist/paypal-pos.lua` becomes `dist/paypal-pos` at match time, never ending in `.lua`. luacov silently ignored every file, producing a zero-byte `luacov.stats.out`. The earlier hypothesis (busted/Lua 5.4 incompatibility) was wrong — luacov works correctly on this Lua 5.4 build once the patterns are right.

**Fix applied:**
- `.luacov` include patterns rewritten to `{ "^src/", "^dist/paypal%-pos$" }` (no `.lua$` suffix; anchored prefix-style).
- `.luacov` exclude pattern rewritten to `"^src/webbanking_header$"` (same reason).
- `.luacov` threshold restored to `85`.
- `.luacov` header comment expanded to warn future contributors not to re-add `.lua$`.

**Verified outcome:** `busted --coverage spec/ && luacov` produces a 583-byte stats file and a luacov.report.out reporting **99.19% coverage** on `dist/paypal-pos.lua` (122 hit / 1 missed lines). The remaining missed line is the WebBanking{} registration call which is only executed when MoneyMoney loads the artifact, not during dofile.

**Follow-up integrated:** The CI workflow now (a) enforces the threshold via `luacov.report.out`-parse step, and (b) uploads the LCOV report to Codecov for trend tracking. The Phase-6 "refactor specs to load src/ modules individually" plan is no longer required — measuring on the amalgamated artifact gives a single accurate number that mirrors what MoneyMoney sees at load time.

---

## (Section reserved for additional Phase-1 known issues as they surface.)
