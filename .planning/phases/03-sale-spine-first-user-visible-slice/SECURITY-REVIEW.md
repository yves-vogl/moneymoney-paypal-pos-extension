# Phase 3 Security Review — Sale Spine (First User-Visible Slice)

**Branch:** `phase-3/sale-spine-first-user-visible-slice` — commit `98c194b`
**Review Date:** 2026-06-20
**Reviewer:** loop-security-engineer (adversarial pass, 3 rounds)
**Test Suite:** 192 tests — 0 failures, 0 errors at review time

---

## Severity Histogram

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 2 |
| Medium   | 2 |
| Low      | 2 |

## Class Histogram

| Class | Count |
|-------|-------|
| Input Validation | 2 |
| Data Integrity   | 2 |
| Information Disclosure | 1 |
| Logic / DoS      | 1 |

---

## Per-Threat Verdict Table

| Threat | Verdict | Evidence |
|--------|---------|----------|
| T-3-1: Bearer leak via M_purchases.fetch HTTP path | MITIGATED | `src/http.lua:125` logs only URL, never headers; `src/purchases.lua:73` keeps Bearer inside header table only |
| T-3-2: API key leak via mapping outputs | MITIGATED | Mapping operates on purchase JSON fields only; api_key never flows into the mapping pipeline |
| T-3-3: Multi-merchant data crossover | MITIGATED | `src/auth.lua:101-103` keys by `orgUuid`; `src/entry.lua:143` resolves orgUuid from `account.accountNumber` per call |
| T-3-4: Non-EUR log leak (D-37) | PARTIAL | Log line contains full attacker-controlled currency string (unbounded length); see S-01 |
| T-3-5: bookingDate manipulation — out-of-range month/year | OPEN | Month values outside [1..12] cause unhandled Lua error in `_parse_iso8601_utc`; see S-02 |
| T-3-6: transactionCode collision | PARTIAL | Nil `purchaseUUID1` produces collision `zettle:sale:`; see S-03 |
| T-3-7: `since` clamp bypass | PARTIAL | Clamp guards negative and zero `since` correctly; future `since` and `math.huge` pass through — see S-04 |
| T-3-8: Egress host scope | MITIGATED | `src/purchases.lua:70` hardcodes `https://purchase.izettle.com/purchases/v2`; `spec/purchases_spec.lua:57-59` asserts URL |
| T-3-9: Refund UUID in format-string positions | MITIGATED | `refundsPurchaseUUID1` is wrapped in `tostring()` before passing to `string.format` `%s`; no format-string injection possible in Lua |
| T-3-10: MAX_PAGES guard visibility | MITIGATED | `src/pagination.lua:47` emits `M_log.warn` before returning error; `spec/pagination_spec.lua:151-163` asserts warn and nil-result |
| T-2-1: API key never in LocalStorage | MITIGATED | `src/auth.lua:138-153` stores only `access_token`; `spec/refresh_log_redaction_spec.lua` Gate A walks LocalStorage post-refresh |
| T-2-2: Bearer never in error strings | MITIGATED | `src/errors.lua:15` body parameter unused; all returned strings are i18n templates |
| T-2-3: `pcall` NOT wrapping `conn:request` | MITIGATED | `src/http.lua:88-89` explicit comment; no pcall around connection calls |

---

## Findings

### S-01 — D-37 INFO log accepts unbounded attacker-controlled currency string

**Severity:** Medium
**Class:** Information Disclosure / Input Validation
**Gap:** The non-EUR skip log lines in `M_mapping.purchase_to_transaction` and `M_mapping.refund_to_transaction` concatenate the raw `currency` field value from the Zettle API response into the log line without any length cap. If Zettle (or a spoofed response) returns a `currency` field of 1000+ characters, the log line grows correspondingly. While `M_log._redact` passes through this value unchanged (it contains no JWT, Bearer, assertion= or access_token= patterns to redact), the unbounded length and unvalidated content reaching a log sink is a defence-in-depth gap.

**Mitigation:** Cap the currency string to a safe display length before concatenation. A `tostring(p.currency):sub(1, 8)` cap is sufficient — ISO 4217 currency codes are 3 characters; 8 provides generous margin for any edge case. No functional change is needed for the D-37 skip decision (that comparison happens separately on the full value).

**Where to apply:** `src/mapping.lua:234-235` and `src/mapping.lua:262-263`

**Proof:** Call `M_mapping.purchase_to_transaction({currency=string.rep("X",1000), amount=100, ...})`. The captured print line length exceeds 1089 characters, confirmed experimentally.

---

### S-02 — `_parse_iso8601_utc` crashes on out-of-range month (Lua error, not nil return)

**Severity:** High
**Class:** Input Validation / DoS
**Gap:** `_parse_iso8601_utc` (mapping.lua) uses a pattern `(%d%d)` to extract the month component. The pattern accepts any two-digit string including `"00"` and `"13"`. Both `tonumber("00") = 0` and `tonumber("13") = 13` pass the truthiness guard on line 76 (`if not (Y and M and D ...)`). When the code reaches `days = days + _MONTH_DAYS[M]` at line 84, `_MONTH_DAYS[0]` and `_MONTH_DAYS[13]` are both `nil` in Lua, causing `attempt to perform arithmetic on a nil value` — a hard Lua error, not a nil return.

This error is NOT caught by a `pcall` anywhere in the `RefreshAccount` call stack. If Zettle (or a future API change returning malformed data) delivers any purchase with `timestamp` containing month `00` or `>12`, the entire `RefreshAccount` call aborts ungracefully via a Lua error propagating to MoneyMoney. MoneyMoney's behaviour when a WebBanking callback raises an uncaught error is undefined and implementation-specific.

The day component (`D`) has the same theoretical issue if `D = 0`, but `days + (D - 1) = days + (-1)` is arithmetic on a valid integer, so `D = 0` does not crash — it silently produces a one-day-off `bookingDate` with no error.

Leap seconds (`S = 60`) are accepted silently and produce a one-second-ahead `bookingDate`, which is benign.

**Mitigation:** Add explicit range guards inside `_parse_iso8601_utc` after `tonumber` conversion and before the `_MONTH_DAYS` lookup:

```lua
if M < 1 or M > 12 then return nil end
if D < 1 or D > 31 then return nil end
```

This converts the crash to the intended graceful nil return, which the callers already handle via the `utc and ... or os.time()` fallback at lines 240 and 267.

**Where to apply:** `src/mapping.lua` — inside `_parse_iso8601_utc`, between line 76 (the nil guard) and line 79 (the day arithmetic), approximately after `tonumber` conversions complete.

**Proof:** Call `M_mapping.purchase_to_transaction({currency="EUR", timestamp="2026-13-01T00:00:00.000+0000", ...})` — confirmed to raise `attempt to perform arithmetic on a nil value` at `dist/paypal-pos.lua:835`.

---

### S-03 — `transactionCode` collision when `purchaseUUID1` is nil or empty

**Severity:** High
**Class:** Data Integrity
**Gap:** `M_mapping.purchase_to_transaction` and `M_mapping.refund_to_transaction` build `transactionCode` via:

```lua
"zettle:sale:" .. tostring(p.purchaseUUID1 or "")
```

When `p.purchaseUUID1` is `nil`, `tostring(nil or "") = ""`, yielding the code `"zettle:sale:"`. If two separate purchases in the same API response both have `nil` or `""` as their `purchaseUUID1`, they produce identical `transactionCode` values. MoneyMoney uses `transactionCode` for idempotent de-duplication; a collision means one of the two purchases is silently dropped on the second refresh.

The Zettle API should always supply `purchaseUUID1`, but a schema change, a partial response, or a corrupt page can produce a nil. Phase 3 has no guard that discards purchases with missing or empty UUIDs before mapping.

**Mitigation:** Add an early guard inside both mapping functions that returns `nil` (skip) when `purchaseUUID1` is nil or empty, with an `M_log.warn` line. This is analogous to the existing D-37 currency guard:

```lua
if type(p.purchaseUUID1) ~= "string" or #p.purchaseUUID1 == 0 then
  M_log.warn("M_mapping.purchase_to_transaction: skipping purchase with missing purchaseUUID1")
  return nil
end
```

**Where to apply:** `src/mapping.lua:231-237` (purchase path) and `src/mapping.lua:259-265` (refund path)

**Proof:** Call `M_mapping.purchase_to_transaction({currency="EUR", purchaseUUID1=nil, ...})` twice; both return `transactionCode = "zettle:sale:"`.

---

### S-04 — `since = math.huge` bypasses the 90-day clamp and crashes `_iso8601_utc`

**Severity:** Medium
**Class:** Input Validation / Logic
**Gap:** `RefreshAccount` clamps the `since` parameter with:

```lua
local effective_since = math.max(since or 0, os.time() - NINETY_DAYS)
```

`math.max(math.huge, any_number) = math.huge`. This is benign only if `_iso8601_utc(math.huge)` handles infinity gracefully. It does not: `os.date("!%Y-%m-%dT%H:%M:%SZ", math.huge)` raises `bad argument #2 to 'date' (number has no integer representation)` — a hard Lua error. This crashes `M_purchases.fetch` before the HTTP request is made.

The practical trigger is narrow: MoneyMoney would need to pass `math.huge` as the `since` argument, which it should not do in practice. However, the `since` parameter is not validated before use, and the crash path is real and confirmed.

Similarly, a future timestamp `since > os.time()` is not clamped by the `max()` logic: `math.max(now+1000, now-90days) = now+1000`. This causes `startDate` to be set to a future time, resulting in zero transactions returned (not a security issue but a data-completeness gap under adversarial conditions).

**Mitigation:** Add a guard after the `math.max` call that clamps `effective_since` to a finite reasonable range:

```lua
if type(effective_since) ~= "number" or effective_since ~= effective_since  -- NaN check
    or effective_since == math.huge or effective_since == -math.huge then
  effective_since = os.time() - NINETY_DAYS
end
```

A simpler guard: `effective_since = math.min(effective_since, os.time())` caps future timestamps at the current time, preventing both the future-startDate data gap and the math.huge crash path.

**Where to apply:** `src/entry.lua:151` — immediately after the `math.max` call

**Proof:** `os.date("!%Y-%m-%dT%H:%M:%SZ", math.huge)` raises `bad argument #2 to 'date'`. Confirmed in Lua 5.4.

---

### S-05 — DST table ends at 2040; purchases timestamped 2041+ get wrong Berlin offset

**Severity:** Low
**Class:** Data Integrity
**Gap:** `_to_berlin_local_time` in `mapping.lua` applies a linear scan over `DST_TABLE` which contains entries only for years 2020-2040. For any UTC timestamp after 2040-10-28T01:00:00Z (the last summer-end boundary), no DST entry matches, and the function falls through to the winter-default offset of `+3600` (CET). In summer months of 2041 and beyond, this silently applies the wrong UTC+1 offset instead of the correct UTC+2, causing `bookingDate` values to be off by one hour — which may shift the booking across local midnight and produce an incorrect booking date in MoneyMoney.

This is a future-dated gap (14+ years from now) and carries no immediate security consequence. It is a data-integrity risk for long-lived deployments.

**Mitigation:** Extend `DST_TABLE` to 2050 or further. Alternatively, document the gap as a known limitation in `src/mapping.lua` and add a CI test that asserts `_to_berlin_local_time` gives the wrong offset for a 2041 summer timestamp (to make the gap machine-detectable when the table is eventually updated).

**Where to apply:** `src/mapping.lua:47` — add entries for 2041-2050

**Proof:** `M_mapping.purchase_to_transaction({timestamp="2050-06-15T12:00:00.000+0000", ...})` returns `bookingDate = 2538910800` (UTC+1), not `2538914400` (UTC+2 correct). Confirmed experimentally.

---

### S-06 — `MAX_PAGES` error message surfaces internal placeholder text to users

**Severity:** Low
**Class:** Information Disclosure
**Gap:** When the pagination guard fires, it returns `M_i18n.t("error.network", "max_pages")`, which renders as the German string `"Netzwerkfehler: max_pages"`. The literal string `"max_pages"` is an internal code identifier, not German prose. While this is not a security issue (it leaks no credentials or data), it exposes implementation internals to MoneyMoney users and violates the project's German-primary UX principle. A user seeing this message has no actionable information.

**Mitigation:** Add a dedicated i18n key for the MAX_PAGES condition, e.g.:

```lua
["error.too_many_pages"] = "Zu viele Seiten — Bitte Zeitraum einschränken."
```

and use it in `pagination.lua:48` instead of `M_i18n.t("error.network", "max_pages")`.

**Where to apply:** `src/i18n.lua` — new key; `src/pagination.lua:48` — update call

**Proof:** Trigger the MAX_PAGES guard (see `spec/pagination_spec.lua:151-163`); assert that the error string `err` contains `"max_pages"` — which it does per current spec assertion at line 161.

---

## SEC-03 Compliance Verdict

**COMPLIANT.** The three SEC-03 gates are satisfied:

- **Gate A (LocalStorage walk):** `spec/refresh_log_redaction_spec.lua` walks `LocalStorage` after each RefreshAccount run and asserts no value matches `eyJ[A-Za-z0-9_-]+`. Confirmed passing across five test cases.
- **Gate B (print stream):** The spec asserts no captured print line contains `"Bearer eyJ"`. `src/http.lua:125` logs only the URL for GET requests; `src/mapping.lua` log lines contain only currency codes and UUID prefixes, both of which pass through `M_log._redact` with no structural JWT pattern.
- **Gate C (transactionCode prefix):** Every `transactionCode` emitted by `RefreshAccount` starts with `zettle:sale:` or `zettle:refund:`. Confirmed by `spec/refresh_log_redaction_spec.lua` Gate C tests and `spec/refresh_idempotency_spec.lua`.

Note: S-01 (unbounded currency string in INFO log) is a defence-in-depth gap that does not violate SEC-03 because the currency value is not a credential type covered by the redaction patterns. However, S-01 should be addressed to prevent future unexpected log bloat.

---

## Phase-2 Carryover Verdict

| Carryover | Verdict | Notes |
|-----------|---------|-------|
| T-2-1: API key never in LocalStorage | MITIGATED | Extended by Phase-3 Gate A spec |
| T-2-2: Bearer never in error strings | MITIGATED | `src/errors.lua` body parameter intentionally unused |
| T-2-3: No pcall around `conn:request` | MITIGATED | `src/http.lua:88-89` explicit; Phase 3 adds no new `conn:request` call sites |

---

<orchestrator_handoff>
{
  "verdict": "FINDINGS",
  "pass_summary": "Pass 3 — dry (no new findings in pass 3 versus pass 2). 3 adversarial rounds total.",
  "critical_findings_count": 0,
  "high_findings_count": 2,
  "medium_findings_count": 2,
  "low_findings_count": 2,
  "sec03_compliant": true,
  "findings": {
    "S-01": {
      "severity": "Medium",
      "class": "Input Validation / Information Disclosure",
      "summary": "D-37 INFO log concatenates full unbounded attacker-controlled currency string",
      "file": "src/mapping.lua:234-235, 262-263",
      "pr_type": "Sec-PR batch",
      "fix": "Cap currency string with :sub(1,8) before log concatenation"
    },
    "S-02": {
      "severity": "High",
      "class": "Input Validation / DoS",
      "summary": "_parse_iso8601_utc crashes (Lua error) on month outside [1..12] — no nil return, no pcall catch in RefreshAccount",
      "file": "src/mapping.lua:68-91",
      "pr_type": "Held-for-review PR",
      "fix": "Add M < 1 or M > 12 guard returning nil before _MONTH_DAYS[M] lookup"
    },
    "S-03": {
      "severity": "High",
      "class": "Data Integrity",
      "summary": "nil purchaseUUID1 produces transactionCode collision 'zettle:sale:' across multiple purchases",
      "file": "src/mapping.lua:248, 278",
      "pr_type": "Held-for-review PR",
      "fix": "Guard on nil/empty purchaseUUID1 at mapping entry, return nil + M_log.warn"
    },
    "S-04": {
      "severity": "Medium",
      "class": "Input Validation / Logic",
      "summary": "since=math.huge passes through 90-day clamp and crashes os.date() in _iso8601_utc; future since values not upper-bounded",
      "file": "src/entry.lua:151",
      "pr_type": "Held-for-review PR",
      "fix": "Cap effective_since to math.min(effective_since, os.time()) after math.max"
    },
    "S-05": {
      "severity": "Low",
      "class": "Data Integrity",
      "summary": "DST table ends at 2040; summer timestamps from 2041 onward get wrong UTC+1 instead of UTC+2",
      "file": "src/mapping.lua:47",
      "pr_type": "Normal Sec-PR batch (not time-critical)",
      "fix": "Extend DST_TABLE entries to 2050"
    },
    "S-06": {
      "severity": "Low",
      "class": "Information Disclosure",
      "summary": "MAX_PAGES error shows 'Netzwerkfehler: max_pages' — internal placeholder text visible to users",
      "file": "src/pagination.lua:48, src/i18n.lua",
      "pr_type": "Normal Sec-PR batch",
      "fix": "Add dedicated i18n key error.too_many_pages with German prose"
    }
  },
  "held_for_review": ["S-02", "S-03", "S-04"],
  "normal_batch": ["S-01", "S-05", "S-06"],
  "launch_block": false,
  "recommendation": "Phase 3 is CONDITIONALLY CLEARED for merge. S-02 and S-03 must be addressed before Phase 4 which will increase API surface area. S-04 should be fixed before any production deployment. S-01, S-05, S-06 can go through the normal Sec-PR batch. No critical findings. SEC-03 is compliant."
}
</orchestrator_handoff>
