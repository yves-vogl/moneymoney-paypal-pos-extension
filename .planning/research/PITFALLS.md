# Pitfalls Research

**Domain:** MoneyMoney community extension integrating PayPal POS (Zettle) Public API for German merchants — Lua, single-file distribution, GitHub Actions CI/CD, MIT-licensed.
**Researched:** 2026-06-16
**Confidence:** HIGH for MoneyMoney semantics and Zettle API shape (confirmed against the official Web Banking API docs and the iZettle/PayPal developer portal); MEDIUM for runtime sandbox edges of MoneyMoney's Lua VM (under-documented — verify with a probe extension in Phase 1); MEDIUM for current Zettle rate-limit numbers (documented as 429 behavior but the exact quota is not published).

The entire list below is niche-specific. Generic "use HTTPS / rotate secrets" advice is omitted unless the niche bends it in a non-obvious way.

---

## Critical Pitfalls

### Pitfall 1: Returning incomplete transaction records → MoneyMoney UI behaves unpredictably

**What goes wrong:**
A `RefreshAccount` implementation returns transactions with `amount` and `bookingDate` set but omits `booked`, `name`, `purpose`, or `valueDate`. MoneyMoney then renders rows inconsistently: pending sales appear as booked, search-by-purpose misses entries, German VAT export to bookkeeping software drops fields. Some users see ghost-positions where the running balance no longer matches reality.

**Why it happens:**
The MoneyMoney Web Banking API only enforces `amount` and `bookingDate` at the schema level — every other field is "optional" in the spec, which tempts the developer to skip them. In practice, MoneyMoney's downstream consumers (search, export, reconciliation, the iOS companion app via `mmexport`) treat missing fields as a contract violation that surfaces silently.

**How to avoid:**
Build a single `buildTransaction()` helper that always emits the full canonical record: `name`, `amount`, `currency`, `bookingDate`, `valueDate`, `purpose`, `bookingText`, `booked`, `transactionCode`. For PayPal POS sales: `name = "PayPal POS — <merchant-name>"`, `bookingText` ∈ {`"Kartenzahlung"`, `"Erstattung"`, `"Transaktionsgebühr"`, `"Auszahlung"`}, `booked = true` for completed purchases, `booked = false` for purchases the Finance API has not yet linked to a payout. Unit-test the helper against a golden record fixture so a missing field fails CI.

**Warning signs:**
- Manual smoke test: open MoneyMoney's transaction detail panel — empty fields are immediately visible.
- Export to CSV → fewer columns populated than expected.
- The iOS companion shows blank rows or "—" placeholders.

**Phase to address:** Phase 2 (Transaction modeling) — make the canonical-record helper the first commit of that phase and lock it with a schema test.

---

### Pitfall 2: Confusing `bookingDate` and `valueDate` for PayPal POS sales

**What goes wrong:**
Developer sets `bookingDate = valueDate = purchase.timestamp` for every sale. Result: pending purchases (sold today, not yet paid out) show up with a `valueDate` of today, distorting MoneyMoney's "available balance projected at date X" computations. German operators doing liquidity planning see phantom money.

**Why it happens:**
The Zettle Purchase API exposes one `timestamp` (the moment the card was swiped). The Finance API exposes the payout date separately. The naive mapping uses `timestamp` for both MoneyMoney fields because they are syntactically identical (POSIX timestamps).

**How to avoid:**
- `bookingDate` ← `purchase.timestamp` (when the sale was rung up — this is what merchants expect to search by).
- `valueDate` ← the payout date if the purchase is already linked to a payout via the Finance API; otherwise the same as `bookingDate` plus the documented settlement delay (PayPal POS settles 1–2 working days), **but** flag the transaction `booked = false` so MoneyMoney knows it is pending.
- Document this mapping in an ADR; it is the kind of rule that drifts when a new contributor touches the file.

**Warning signs:**
- Difference between `balance` and `pendingBalance` in MoneyMoney does not match the difference observable on my.zettle.com.
- Bookkeeping export shows VAT period assignment off by a day for end-of-month sales.

**Phase to address:** Phase 2 (Transaction modeling) and Phase 3 (Finance API integration / payout linking).

---

### Pitfall 3: Unstable `transactionCode` / identifier across refreshes → MoneyMoney duplicates instead of dedupes

**What goes wrong:**
Developer derives the transaction's identity from `purchase.purchaseNumber` or, worse, a hash of `(timestamp + amount)`. On the next refresh, the same sale gets a different identity (e.g. because `purchaseNumber` resets per register, or the hash collides for two espressos rung up in the same second). MoneyMoney sees a "new" transaction and re-inserts it. The user reports double-bookings.

**Why it happens:**
MoneyMoney's deduplication is opaque — the docs say "classified as new if not already in the database" without naming the key. In practice MoneyMoney uses a fingerprint over several fields, and any drift in the surfaced identity creates duplicates. Zettle exposes both `purchaseUUID` (legacy, deprecated) and `purchaseUUID1` (v1 UUID, stable); choosing the wrong one is easy.

**How to avoid:**
- Use `purchaseUUID1` as the canonical identity. Embed it in `transactionCode` (e.g. `transactionCode = "zettle:purchase:" .. purchase.purchaseUUID1`).
- For refunds: derive a deterministic child identity (`"zettle:refund:" .. refund.purchaseUUID1`).
- For fees: `"zettle:fee:" .. purchase.purchaseUUID1`.
- For payouts: `"zettle:payout:" .. payout.uuid` from the Finance API.
- Write a contract test that runs `RefreshAccount` twice over the same fixture and asserts the second run returns zero new transactions.

**Warning signs:**
- Running balance in MoneyMoney drifts further from PayPal POS dashboard with each refresh.
- A specific sale shows up twice in MoneyMoney transaction list with identical content.

**Phase to address:** Phase 2 (Transaction modeling) — the double-refresh idempotency test is the gate for "Phase 2 complete."

---

### Pitfall 4: Ignoring the `since` parameter → full history re-fetched every refresh

**What goes wrong:**
`RefreshAccount` always pulls the last three years (Zettle's default lookback). Each refresh takes 60+ seconds, hits the rate limit, and on cellular networks the MoneyMoney user sees a spinner that never resolves. Worse: if dedup also has a bug, every refresh duplicates the entire history.

**Why it happens:**
The `since` parameter is a POSIX timestamp passed *by MoneyMoney* into `RefreshAccount`. Developers either don't read the parameter, or read it but fail to translate it into the Zettle `startDate` query parameter (which expects ISO 8601 UTC, not a POSIX integer).

**How to avoid:**
- Always honor `since`. Convert: `startDate = os.date("!%Y-%m-%dT%H:%M:%S.000Z", since)` (the `!` produces UTC, which Zettle requires).
- Add a small backstep (e.g. 24h) to `since` to catch out-of-order settlement events for purchases that crossed the day boundary in different timezones.
- Cap the per-refresh window so a first-time setup doesn't pull three years synchronously — fetch incrementally over several refresh cycles or paginate within the call.

**Warning signs:**
- MoneyMoney refresh > 20 s on every cycle (target: <5 s for incremental, <30 s for first run).
- Zettle returns 429 in CI integration tests.

**Phase to address:** Phase 3 (Incremental refresh / pagination).

---

### Pitfall 5: Throwing the wrong error type — MoneyMoney shows a useless dialog or auto-disables the account

**What goes wrong:**
On a transient network error or a 401 from Zettle (expired token), the extension raises a generic string error. MoneyMoney either (a) shows a stack-trace-looking dialog that scares the user, or (b) — when the developer accidentally raises the `LoginFailed` constant on a transient failure — locks the account and forces the user to re-paste their API key on every minor blip.

**Why it happens:**
The MoneyMoney API exposes exactly one specialized error constant (`LoginFailed`) and treats all other errors as generic strings. Developers default to `error("Zettle API returned " .. status)` because it's the obvious thing.

**How to avoid:**
Branch error handling on Zettle response:
- HTTP 401 with `error = "invalid_grant"` (per Zettle assertion-grant docs) on the token endpoint → raise `LoginFailed` (the API key really was revoked or rotated by the merchant).
- HTTP 401 on any other endpoint after a valid token exchange → raise a generic German string ("Die Sitzung ist abgelaufen — wird beim nächsten Abruf erneuert.") and *don't* throw `LoginFailed`; just let the next refresh re-mint the token.
- HTTP 429 → raise a German string ("PayPal POS limitiert gerade Anfragen — bitte später erneut versuchen.") with no `LoginFailed`.
- HTTP 5xx / network → raise a German string with the HTTP status, no `LoginFailed`.

**Warning signs:**
- User reports MoneyMoney keeps asking for the API key on every refresh.
- User reports a German-but-cryptic error like `attempt to index a nil value (field ...)` — that's an uncaught Lua exception, not an API error.

**Phase to address:** Phase 4 (Error handling and resilience).

---

### Pitfall 6: Using the wrong OAuth grant type — Zettle does not support `password` or `client_credentials`

**What goes wrong:**
Developer reads "OAuth2" in the Zettle docs and reaches for `grant_type=client_credentials` or `grant_type=password`. Zettle rejects both with `unsupported_grant_type`. The extension never authenticates. Worse: developer reads "the API key authenticates the app" and tries to use the API key as a Bearer token directly — Zettle returns 401.

**Why it happens:**
The Zettle assertion-grant flow is non-standard for OAuth2 client-credentials use cases: the API key is the JWT *assertion*, not a bearer token, and the grant type is the JWT-bearer grant (`urn:ietf:params:oauth:grant-type:jwt-bearer`). Most OAuth tutorials don't cover this path.

**How to avoid:**
Hard-code the token exchange exactly as the Zettle docs specify:
- POST `https://oauth.zettle.com/token`
- `Content-Type: application/x-www-form-urlencoded`
- Body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&client_id=<merchant-client-id>&assertion=<api-key>`
- Response: `{ "access_token": "...", "expires_in": 7200 }` — note no `refresh_token`.
Use the resulting `access_token` as `Authorization: Bearer <access_token>` for all subsequent API calls. Cache the token in memory for the session, refresh on 401 or near `expires_in`.

**Warning signs:**
- 400 `unsupported_grant_type` in the dev log.
- 401 on every API call despite "having an API key."

**Phase to address:** Phase 1 (Authentication spike).

---

### Pitfall 7: Conflating Sandbox and Production endpoints / credentials

**What goes wrong:**
Developer points local dev at sandbox, ships, and CI passes. A user installs the extension and pastes a production API key — but the extension still calls sandbox URLs. User sees zero transactions and assumes the extension is broken.

**Why it happens:**
PayPal POS / Zettle uses environment-specific base URLs (`oauth.zettle.com` vs sandbox variants) and the API key alone does not tell the client which environment it belongs to. The naive approach hard-codes one URL and never asks.

**How to avoid:**
- Hard-code **production** URLs in the shipped `.lua` file. Period.
- For CI/local dev, use the build pipeline to inject sandbox URLs (e.g. a `# sandbox-block` annotation in the source that gets stripped/replaced during the release build step).
- Do **not** expose an "environment toggle" in the MoneyMoney credentials UI — that puts the responsibility on the user, who can't possibly know.

**Warning signs:**
- A "test mode" checkbox sneaks into the credentials dialog during development.
- CI fixtures contain sandbox URLs that match shipped code.

**Phase to address:** Phase 5 (Reproducible build).

---

### Pitfall 8: Pagination cursor mishandling → silent transaction loss

**What goes wrong:**
Developer fetches `/purchases/v2?limit=100&startDate=...` and stops at the first page. Or follows `lastPurchaseHash` but forgets that with `descending=true` the cursor semantics invert. A busy merchant (200+ sales/day) silently misses transactions. The user only finds out at tax time.

**Why it happens:**
Zettle's pagination uses both a `linkUrls` array with `rel="next"` headers and a `lastPurchaseHash` cursor parameter — duplicate signaling invites picking one and missing the edge case. With `descending=true`, the "next" page means "older purchases," which is the opposite of what most pagination loops expect.

**How to avoid:**
- Iterate with `descending=false` (chronological, oldest first) starting from `since`. This makes the loop semantics natural: "next" means "newer."
- Loop until the response contains fewer items than `limit` AND no `rel="next"` link is present. Both conditions, not either.
- Add a hard upper bound (e.g. 50 pages per refresh) and surface a warning if reached — that's an indicator something is wrong with cursor handling.
- Property-test the paginator with a fixture that has exactly `limit` items on the last page (the classic off-by-one).

**Warning signs:**
- MoneyMoney balance < PayPal POS dashboard balance for a single specific day.
- Last-N-transactions list in MoneyMoney is missing the most recent (or oldest) sale of a busy day.

**Phase to address:** Phase 3 (Pagination + incremental refresh).

---

### Pitfall 9: Timezone errors — Zettle returns UTC ISO 8601, MoneyMoney expects POSIX timestamps

**What goes wrong:**
Developer parses `"2026-06-16T17:05:06.123+0000"` with a naive parser that ignores the timezone marker and treats the date as local. Sales at 23:30 CET get booked on the wrong day. End-of-month sales land in the wrong VAT period. German monthly USt-Voranmeldung is wrong.

**Why it happens:**
Zettle's `timestamp` is always UTC with explicit offset. MoneyMoney's `bookingDate` is a POSIX timestamp (seconds since epoch, timezone-neutral). The conversion is straightforward only if you remember it's a conversion at all.

**How to avoid:**
- Centralize all timestamp parsing in one function: `parseZettleTimestamp(iso) → posix_seconds`. Lua does not ship a strict ISO 8601 parser; write a small one (regex over `YYYY-MM-DDTHH:MM:SS(.fff)?(Z|±HHMM)`) and unit-test it against fixtures including UTC offset, fractional seconds, and DST boundary cases (last Sunday of March/October).
- For display in `purpose` (where the user reads it), reformat to German local time (`Europe/Berlin`). The `bookingDate` and `valueDate` fields themselves stay POSIX UTC — MoneyMoney displays them in the user's local zone.
- Add a fixture for a sale at 23:55 UTC and assert the German display says "01:55 Uhr" the next day in summer (CEST) and "00:55 Uhr" in winter (CET).

**Warning signs:**
- Daily totals in MoneyMoney don't match daily totals in PayPal POS dashboard for the user's local day.
- A sale rung up at 23:50 local time shows up on the previous day in MoneyMoney.

**Phase to address:** Phase 2 (Transaction modeling) — bake the parser test into the schema test from Pitfall 1.

---

### Pitfall 10: Per-purchase fee not exposed — netting silently mixes revenue and expense

**What goes wrong:**
Developer can't find a per-purchase fee field in the Purchase API, so they net the fee into the sale amount (`sale_amount - fee`). The German operator loses the ability to book the fee as a separate Betriebsausgabe. VAT base for the sale is now understated. The Steuerberater either re-keys the data manually or charges extra for the cleanup.

**Why it happens:**
The Zettle Purchase API does not expose the processing fee per purchase — only `serviceCharge` (which is an operator-defined surcharge like delivery, not the Zettle fee). The processing fee shows up only at the Finance API / payout level, often aggregated.

**How to avoid:**
- Always book the gross sale amount as the sale transaction (including VAT, tip, service charge).
- Pull the Finance API's transaction list for the payout and emit one fee transaction per fee event the Finance API reports. If the API only aggregates fees at the payout level, emit one daily-aggregate fee transaction with `purpose = "PayPal POS Transaktionsgebühren <date>"` and a clear comment in the README that per-sale fee attribution is not possible upstream.
- Make this an ADR — it's a recurring question and the answer is environmental, not preference.

**Warning signs:**
- Sale amounts in MoneyMoney don't match the gross amount printed on the customer receipt.
- The README is silent on where fees come from.

**Phase to address:** Phase 3 (Finance API integration / fee modeling) plus an ADR.

---

### Pitfall 11: VAT and tip not separated in `purpose` → unusable for bookkeeping

**What goes wrong:**
The full `purpose` is `"PayPal POS sale 12.34 EUR"` — no VAT breakdown, no tip line. The merchant has to open my.zettle.com for every transaction to figure out the VAT split and tip share. The entire point of the extension (bookkeeping-ready data in MoneyMoney) is lost.

**Why it happens:**
The Purchase API exposes `vatAmount` and the payment object's `gratuityAmount`, but they live on different sub-objects and require unwrapping. Developer flattens to a one-liner to keep the code simple.

**How to avoid:**
Standard multi-line German `purpose`:
```
Kartenzahlung — Beleg #<purchaseNumber>
Brutto: 12,34 EUR
  davon 19% MwSt: 1,97 EUR
  davon 7% MwSt: 0,00 EUR
Trinkgeld: 1,00 EUR
PayPal POS UUID: <purchaseUUID1>
```
Multi-line via `"\n"` is explicitly supported by MoneyMoney's `purpose`. Always include the UUID — that's the user's lifeline when reconciling against Zettle's dashboard.

**Warning signs:**
- `purpose` field is one line.
- VAT rates are hard-coded (19% only) — Germany has 7% and 0% rates too; food, ebooks etc. are 7%.
- Tips not visible when the Zettle dashboard shows `gratuityAmount > 0`.

**Phase to address:** Phase 2 (Transaction modeling) — establish the `purpose` template early; lock with golden-file test.

---

### Pitfall 12: Tip taxation ambiguity surfaced as a decision the extension cannot make

**What goes wrong:**
The extension auto-classifies all tips as "Trinkgeld an Mitarbeiter" (tax-free per §3 Nr. 51 EStG). The merchant is a sole proprietor with no employees — the tip is taxable revenue for them. Tax return now under-reports income; on audit this is unpleasant.

**Why it happens:**
The Zettle API has no concept of "employee tip vs operator tip." The extension cannot decide on the merchant's behalf. Developer guesses based on common case (cafés have employees) and gets it wrong for solo operators.

**How to avoid:**
The extension states tip facts but does not classify them:
- `purpose` line: `"Trinkgeld: 1,00 EUR (Steuerliche Behandlung abhängig von Betriebsmodell — siehe README)"`.
- README has a one-paragraph explainer linking to the relevant tax-law text, saying *the operator must decide and book accordingly in their bookkeeping tool* (DATEV, Lexware, etc.).
- No "is your tip taxable?" toggle in the credentials UI — that's not what credentials are for, and it'd be wrong on next year's tax law anyway.

**Warning signs:**
- A "tip handling mode" setting appears in design discussions — push back.
- README treats §3 Nr. 51 EStG as the default rather than the special case.

**Phase to address:** Phase 2 (Transaction modeling) and Phase 7 (Documentation/README).

---

### Pitfall 13: API key leaked in error messages / debug log / Lua tracebacks

**What goes wrong:**
On a network failure the code does `error("Failed to authenticate with " .. token_request_body)` — the body contains `assertion=<the API key>`. The error string lands in MoneyMoney's debug log on the user's disk, possibly in a crash report sent to MoneyMoney support, possibly pasted to a GitHub issue.

**Why it happens:**
Lua's loose concatenation makes it natural to dump request context into errors. The API key is a JWT (long opaque string), so a developer skimming logs doesn't spot it as a secret.

**How to avoid:**
- Single accessor for the API key (`getApiKey()`), and a single accessor for the access token. Never inline the key into a format string.
- `tostring(err)` filter that redacts JWT-shaped tokens: a regex like `eyJ[A-Za-z0-9_-]+%.[A-Za-z0-9_-]+%.[A-Za-z0-9_-]+` → `[REDACTED-TOKEN]`. Run *every* string passed to `error()` through this filter.
- Test that exercises auth failure and asserts the API key substring is absent from the raised error message.
- Never write to `print()` (which lands in MoneyMoney's debug log) in production code paths — keep `print` only inside `if DEBUG then ... end` blocks and ensure `DEBUG = false` in the shipped build.

**Warning signs:**
- A user's GitHub issue includes a token-looking string.
- Grep the shipped `.lua` for `print` — any non-guarded print is a vuln.

**Phase to address:** Phase 1 (Authentication) — the redact filter is part of the same commit that introduces the API key handling.

---

### Pitfall 14: API key persisted outside MoneyMoney's credentials store

**What goes wrong:**
For "performance," developer caches the API key (or the access token) in a Lua `local` at module scope or in a file in `os.tmpname()`. After a crash, the on-disk artifact remains. A user with FileVault off has their key on disk in plaintext.

**Why it happens:**
MoneyMoney passes credentials into `InitializeSession2` once per session; re-reading per-API-call feels wasteful. The developer optimizes by caching.

**How to avoid:**
- API key is only ever held in the function-local arguments of `InitializeSession2` and the access token derived from it. Never copied to a module-level local outside the session, never written to disk, never written to `os.tmpname()`.
- Access token cached in a session-scoped local (a closure or a table cleared in `EndSession`). On extension reload, re-mint from the API key.
- Audit step in the build pipeline: `grep -E "io\\.open|os\\.tmpname|os\\.execute" the_extension.lua` — fail the build if matched (or annotated as allowed).

**Warning signs:**
- Any reference to `io.open` for writing in the extension code.
- Any module-level table named `cache` or `credentials`.

**Phase to address:** Phase 1 (Authentication) and Phase 5 (build pipeline audit step).

---

### Pitfall 15: Network calls to unexpected hosts

**What goes wrong:**
A dev dependency added at some point includes a telemetry beacon, or a contributor adds a fancy "version check" that hits GitHub. The shipped extension now phones home — directly contradicting the no-telemetry promise in the README.

**Why it happens:**
Single-file Lua with no `require()` makes accidental dependencies unlikely, but copy-pasted snippets from Stack Overflow that include analytics URLs do sneak in. Likewise, an enthusiastic contributor adds a "useful" feature like checking for updates.

**How to avoid:**
- Source-level allowlist of hostnames: `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com` (verify exact production hosts in Phase 1 spike). A `Connection()` wrapper checks the URL against this list and refuses any other.
- Lint rule (luacheck custom check or a CI grep) that catches any string literal containing `://` outside the constant block where allowed hosts are defined.
- README claim: "The extension only contacts the following hosts: …" — make the list explicit and verifiable.

**Warning signs:**
- A new URL string appears in a PR diff outside the constants module.
- A contributor proposes a "check for updates" feature.

**Phase to address:** Phase 1 (Networking abstraction) and Phase 5 (CI audit).

---

### Pitfall 16: Users not enabling "Inoffizielle Extensions erlauben" → silent failure

**What goes wrong:**
User drops the `.lua` into the Extensions directory. MoneyMoney silently ignores it. User opens a GitHub issue: "doesn't work, doesn't even appear in the bank selection list." Hours of back-and-forth before the setting is discovered.

**Why it happens:**
MoneyMoney's third-party extension setting is off by default and the failure mode is silent (no toast, no log entry the user can find).

**How to avoid:**
- README, top of file, **before** the install instructions: a screenshot of the "Inoffizielle Extensions erlauben" checkbox with a red arrow and a one-line bilingual explanation. German first.
- Issue template includes a checkbox: "Ich habe in MoneyMoney unter Einstellungen → Extensions die Option 'Inoffizielle Extensions erlauben' aktiviert."
- Consider a `/diagnose` documentation section: "If the extension does not appear, check this setting first."

**Warning signs:**
- First few GitHub issues all ask the same "doesn't show up" question.
- README install section is buried below the feature list.

**Phase to address:** Phase 7 (Documentation/release).

---

### Pitfall 17: Lua sandbox surprises — `require`, `os.execute`, `io.popen` not available

**What goes wrong:**
Developer splits code across files for maintainability using `require("zettle.api")`. Works locally with the standalone Lua interpreter. Fails in MoneyMoney with `attempt to call a nil value (global 'require')` or, worse, succeeds in dev and silently loads stale code in production.

**Why it happens:**
MoneyMoney runs scripts in a sandboxed VM. The docs guarantee "first five chapters of Programming in Lua" plus the documented MoneyMoney globals. `require`, `os.execute`, `io.popen`, `package.loadlib`, `dofile`, `loadfile`, and `debug.*` are not guaranteed and historically behave inconsistently. Even if they are available in some MoneyMoney build, relying on them is not portable across MoneyMoney versions.

**How to avoid:**
- Hard rule: the shipped `.lua` is a single file with **no** `require` / `dofile` / `loadfile`.
- For development modularity: keep source split, but the build step concatenates into one file in a deterministic order (lexical sort of `src/*.lua`, with a banner comment per included section). A test verifies the concatenated artifact runs `RefreshAccount` end-to-end in the mock harness.
- Probe extension (10 lines) in Phase 1: enumerate which globals are present in the MoneyMoney runtime and pin the result in an ADR.

**Warning signs:**
- Any `require` line in `src/`.
- The extension works in `busted` but throws on first call in MoneyMoney.

**Phase to address:** Phase 1 (sandbox probe) and Phase 5 (build pipeline).

---

### Pitfall 18: UTF-8 / German umlaut handling in `purpose` and `name`

**What goes wrong:**
Merchant's business name is `Café Müller`. Zettle returns it as UTF-8. The extension uses `string.upper()` or `string.len()` and corrupts the umlauts (Lua's string library is byte-oriented, not UTF-8-aware). MoneyMoney displays `Caf? M?ller` or splits the row on a multi-byte boundary.

**Why it happens:**
Lua 5.1/5.2 string functions operate on bytes. Lua 5.3+ has `utf8.*` but not all `string.*` operations are UTF-8 safe (`upper`, `lower`, `len`, `sub`).

**How to avoid:**
- Never call `string.upper`, `string.lower`, `string.len`, `string.sub` on strings that may contain non-ASCII. If a length check is needed for `purpose` (MoneyMoney truncates at some length), measure bytes and stay under a conservative limit.
- Verify with a fixture: `Café Müller — Bockwurst & Kompott`, `Ø-Test`, emoji (a customer with `🌮` in their nickname is plausible).
- Confirm Zettle responses are UTF-8 (they are, per JSON RFC). MoneyMoney's `JSON()` parser preserves UTF-8 if input is UTF-8.

**Warning signs:**
- `?` characters appear in MoneyMoney transaction display.
- Fixture-based tests pass but real-data refresh shows mangled strings.

**Phase to address:** Phase 2 (Transaction modeling) — include umlaut fixtures from day one.

---

### Pitfall 19: Currency amounts — minor units vs. decimals

**What goes wrong:**
Zettle returns `amount: 995` (995 cents = €9.95). Developer assumes decimal euros and books a €995 sale. Or the opposite: Zettle returns `995` but the developer divides by 100 once *and* MoneyMoney expects the value in major-unit decimals — works for euros, breaks for currencies with non-2 decimal places (JPY has 0, BHD has 3 — out of scope per v1 but the bug is latent).

**Why it happens:**
Zettle exposes amounts in "minor units" (the smallest currency subdivision). MoneyMoney expects `amount` as a major-unit decimal number. The conversion is a divide by `10^minor_units(currency)`.

**How to avoid:**
- Single helper `minorToMajor(amount, currency) → number` that maps via ISO 4217 minor-unit table.
- For v1 scope (EUR primary): divide by 100. Add a guard that throws on any currency where the table is undefined rather than silently dividing wrong.
- Unit-test with EUR, USD (also 2), JPY (0), BHD (3) so the helper is right when scope expands.
- **Do not** use string concatenation to format amounts (`"9" .. "." .. "95"`). Use Lua's `string.format("%.2f", value)` and replace `.` with `,` for German display.

**Warning signs:**
- A sale displays as 995,00 EUR in MoneyMoney instead of 9,95 EUR.
- Tests pass because both sides of the test use the same wrong conversion.

**Phase to address:** Phase 2 (Transaction modeling).

---

### Pitfall 20: CI secrets — sandbox keys committed accidentally

**What goes wrong:**
Developer commits a real sandbox API key to enable a local test. CI runs fine. The key is in git history forever. Even after rotation, the *fact* that the maintainer once committed a secret undermines trust in a security-sensitive extension.

**Why it happens:**
Sandbox keys feel "less serious" than production keys, and the path to CI integration tests is `commit, push, see what breaks`.

**How to avoid:**
- CI sandbox key lives **only** in GitHub Actions encrypted secrets (`ZETTLE_SANDBOX_API_KEY`, `ZETTLE_SANDBOX_CLIENT_ID`). Never in repo, never in `.env`.
- Default test mode: **fixture-replay**. Recorded JSON responses from real sandbox calls. Run on every PR.
- "Live sandbox" job is opt-in: only triggered on `workflow_dispatch` or on push to `main`, reads secrets from Actions context, does not run on forks (`if: github.event.pull_request.head.repo.full_name == github.repository`).
- Pre-commit hook (`gitleaks` or `detect-secrets`) blocks any JWT-shaped string in staged files. Document the hook install in `CONTRIBUTING.md`.

**Warning signs:**
- A `.env` file in the repo (even gitignored — too easy to mis-commit).
- A test that depends on a key being present in the environment without a sandbox/fixture toggle.

**Phase to address:** Phase 5 (CI/CD) and Phase 1 (Authentication, which is the first time a key is involved).

---

### Pitfall 21: GitHub Actions runners cannot GPG-sign tags out of the box

**What goes wrong:**
Tag-signing requirement (per maintainer's standard) clashes with a release workflow that wants to create a tag automatically when a `vX.Y.Z` PR merges. The runner has no GPG key. Either the tag is unsigned (violating policy) or the release process must be manual (defeating the point of CI/CD).

**Why it happens:**
GPG signing requires a private key. Putting the maintainer's personal signing key in CI secrets is wrong (the key is *personal*, not project-scoped, and revoking it elsewhere would be painful).

**How to avoid:**
- **Local tagging stays manual.** The maintainer runs `git tag -s vX.Y.Z && git push --tags` on their workstation. The signing key never leaves the maintainer's machine.
- CI reacts to the *pushed signed tag*: a workflow triggered by `on.push.tags: ['v*']` builds the release artifact, computes SHA256, and creates the GitHub Release with the `.lua` and the checksum attached. The runner never signs anything.
- Document this in `RELEASE.md` so a future contributor doesn't try to "automate the tag step too" and accidentally introduce an unsigned-tag workflow.

**Warning signs:**
- Any PR proposes `actions/create-tag` or `release-please` configured to auto-tag.
- An unsigned tag appears on the repo.

**Phase to address:** Phase 5 (CI/CD) — document the tag-signing split in `RELEASE.md` as a hard rule.

---

### Pitfall 22: Reproducible-build divergence between local and CI

**What goes wrong:**
Local build of `the_extension.lua` differs by a single byte from the CI build (file ordering, trailing newline, Lua version banner). Users computing SHA256 to verify the release see a mismatch and (correctly) refuse to trust the artifact.

**Why it happens:**
File concatenation in shell scripts is sensitive to locale-dependent sort, glob order, and trailing newlines. Different Lua minifier versions produce different output. A CI matrix that builds on multiple OSes can produce multiple "reproducible" hashes.

**How to avoid:**
- **One build environment is canonical.** Pin: ubuntu-24.04 (or the LTS available in Actions), Lua 5.4.x (exact patch version), explicit `LC_ALL=C` for any sort, no minification (single-file readability has value for a free open-source security-relevant artifact).
- Concatenation script uses explicit ordered file list, not glob. `cat src/01-constants.lua src/02-utils.lua ...` with leading numeric prefixes that pin order.
- CI step: build twice in the same job, diff the outputs, fail if they differ.
- Release notes include the build environment fingerprint (`Built on ubuntu-24.04, Lua 5.4.7, LC_ALL=C, sha256: …`).

**Warning signs:**
- "Works on my machine" SHA256 mismatch.
- A glob (`cat src/*.lua`) anywhere in the build script.

**Phase to address:** Phase 5 (CI/CD).

---

### Pitfall 23: Coverage regressions silently merged

**What goes wrong:**
A PR adds a new feature without tests; coverage drops from 92% to 78%. CI is green (because no test *failed*). PR merges. Months later a bug is traced to that untested code path.

**Why it happens:**
`busted` runs return success when tests pass; coverage is a separate concern often not gated.

**How to avoid:**
- `luacov` configured with a minimum threshold (e.g. 85%). CI step explicitly fails if coverage falls below.
- PR template includes a checkbox: "Coverage non-decreasing (compared to `main`)."
- Optional: comment-bot that posts coverage delta on each PR.

**Warning signs:**
- Coverage number drifts down between releases.
- A "fix coverage" PR appears later — should have been caught at the original PR.

**Phase to address:** Phase 5 (CI/CD).

---

### Pitfall 24: Extension version drifts from Git tag

**What goes wrong:**
The `WebBanking{version = 1.02, ...}` line in the Lua file says `1.02` but the Git tag is `v1.0.3`. Users opening MoneyMoney's extension list see `1.02` and can't easily tell whether they have the latest. Issue reporters quote the in-file version, which doesn't match any GitHub release.

**Why it happens:**
The version is in two places. Manual updates desync.

**How to avoid:**
- Source of truth: Git tag. Build pipeline reads the tag (`git describe --tags --exact-match`) and substitutes a `__VERSION__` placeholder in the source. The committed Lua has `version = __VERSION__` (or a default like `0.0.0-dev`); the released artifact has the real number.
- Tag format pinned to SemVer via the Conventional Commits release pipeline (e.g. `release-please` or manual SemVer + changelog).
- Tests assert that the built artifact's `version` field matches the tag.

**Warning signs:**
- Maintainer manually edits `version = ...` in the `.lua` source before tagging.
- A GitHub issue references a version not in the releases page.

**Phase to address:** Phase 5 (CI/CD) and Phase 7 (release process documentation).

---

### Pitfall 25: GoBD / GDPdU misunderstanding — the extension is not the bookkeeping system

**What goes wrong:**
A user (or, worse, their Steuerberater) treats MoneyMoney's view of PayPal POS sales as the authoritative bookkeeping record. The extension doesn't expose the GoBD-relevant audit trail (immutable receipt PDFs, retention period guarantees, export formats). On a tax audit, the operator can't produce the required records.

**Why it happens:**
The extension *looks* like a complete record because it shows every sale, refund, fee, payout. Operators conflate "I can see it" with "I have it for audit."

**How to avoid:**
- README has a section titled "GoBD-Hinweis": the extension is a *visualization* of the PayPal POS data on the merchant's side. The authoritative records remain with PayPal POS / Zettle (which provides GoBD-conformant export from my.zettle.com). The extension does not change the merchant's GoBD obligations and is not a replacement for archived PayPal POS reports.
- Do not advertise "GoBD-conform" anywhere. We can't claim it — we don't manage retention.
- Cite §147 AO and GoBD principles by reference, not by paraphrase (don't pretend to give tax advice).

**Warning signs:**
- The word "GoBD" appears in feature copy as a benefit.
- A user asks "can I delete my PayPal POS account now and just use MoneyMoney?" — that's a flag the disclaimer is missing.

**Phase to address:** Phase 7 (Documentation/README) and Phase 8 (Support process).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip per-purchase fee → net into sale | One transaction per sale, simpler model | Wrong VAT base, German bookkeeping misery, painful migration when corrected | **Never.** Always emit fees as separate transactions, even if only daily-aggregate. |
| Fetch full 3-year history each refresh, ignore `since` | Easier first-version pagination | Hits rate limit, slow UX, MoneyMoney spinner of doom | Only as a v0.1 spike to validate the API works — must be replaced by Phase 3. |
| Hard-code 19% VAT label everywhere | Common case works for restaurant/retail | Wrong for 7% goods (food, books), wrong if law changes | **Never.** Always read `vatPercentage` from the Zettle payload. |
| Single-file split source, no build step (write the .lua by hand) | No CI complexity | Maintainability suffers fast (>1000 lines), merge conflicts on every PR | Only acceptable for the first 200 lines of code; introduce the build step before file exceeds ~500 lines. |
| Skip the API-key redaction filter in dev | Faster iteration | A debug print can ship; the moment a contributor adds telemetry-ish logging, the key leaks | **Never.** The filter is one function; introduce it in Phase 1. |
| Inline Lua tests in the same file as the extension | Fewer files | Tests ship to users, file grows huge, accidentally executes test code in MoneyMoney | **Never.** Tests live in `spec/`. |
| No probe of MoneyMoney sandbox — assume Lua features are available | Skip Phase 1 detour | Late-stage discovery that `require` doesn't work → architectural rewrite | **Never.** The probe is 30 minutes. |
| Use `math.floor((minor)/100)` for euro conversion (integer truncation) | Quick | Cents disappear, balances drift | **Never.** Use floating-point division and `string.format("%.2f", …)` for display only. |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Zettle OAuth2 token endpoint | Sending `grant_type=client_credentials` or using the API key as a bearer token | POST `https://oauth.zettle.com/token` with `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`, `client_id=…`, `assertion=<api_key>`. Cache the resulting `access_token` for ~7200 s. |
| Zettle Purchase API pagination | Using only `lastPurchaseHash` *or* only `linkUrls` rel="next", not both as termination conditions | Iterate ascending (`descending=false`) from `since`; stop when `linkUrls` has no `rel="next"` AND returned count < `limit`. |
| Zettle timestamp parsing | Treating ISO 8601 as local time | Parse explicitly as UTC, store as POSIX seconds in MoneyMoney `bookingDate`/`valueDate`. |
| Zettle Finance API for payouts | Linking by purchase number (mutable across registers) | Link by payment `uuid` from the purchase payload to Finance API transactions. |
| MoneyMoney `RefreshAccount(since)` | Ignoring `since`, always fetching full history | Convert `since` (POSIX) to ISO 8601 UTC and pass as Zettle `startDate` with a 24h safety backstep. |
| MoneyMoney error handling | Raising `LoginFailed` on transient 401 (post-token-mint) | Only raise `LoginFailed` on token-mint failure with `error=invalid_grant`. Transient post-mint 401 → re-mint silently. |
| MoneyMoney `transactionCode` | Using `purchaseNumber` (per-register sequential, not globally unique) | Use `purchaseUUID1`. |
| MoneyMoney credentials UI | Adding a "sandbox vs production" toggle | Never. Production URLs are hard-coded; CI uses build-time substitution. |
| MoneyMoney `purpose` field | Single-line summary, no VAT breakdown | Multi-line `\n`-separated German block with brutto, MwSt per rate, tip, UUID. |
| GitHub Actions release workflow | Auto-tagging from CI (no GPG key on runner) | Maintainer signs tag locally; CI builds artifact on tag push. |
| Zettle sandbox vs production hostname | Same code path with conditional URL | Production URLs in source; sandbox URLs injected at build time only for CI fixtures. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| No `since` honoring → full re-pull | MoneyMoney refresh > 30 s every cycle | Pass `since` through to Zettle `startDate` | Any merchant with > ~3 months of sales |
| Sequential page fetch with no upper bound | Refresh hangs on busy days | Cap pages per refresh; surface warning if hit | Merchants with > 1000 sales/day (food trucks, market stalls) |
| Synchronous fee-per-purchase via Finance API per row | N+1 API calls; rate-limit (429) | Batch-fetch Finance API once per refresh, build a map keyed by payment UUID, attach in-memory | Merchants with > 100 sales between refreshes |
| Re-parsing JSON responses repeatedly | Wasted CPU, MoneyMoney UI lag | Parse once, transform once, pass plain Lua tables forward | Always — fix early, cheap to do |
| Logging full response bodies | Disk pressure, slow log writes | Log only structured short summaries (`"fetched 23 purchases, last hash <abc>"`), never raw JSON | Always — also a security concern (see Pitfall 13) |
| Token re-mint on every API call | Doubles request volume, rate-limit risk | Cache access token until 5 minutes before `expires_in` | Merchants with frequent (auto) refresh in MoneyMoney |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| API key concatenated into error string | Key persisted in MoneyMoney debug log; pasted into GitHub issues | Redaction filter applied to every error message; never inline `api_key` in format strings |
| Access token persisted to `os.tmpname()` or `io.open` write | Plaintext token on disk after process exit | Token lives only in a session-local closure; cleared in `EndSession` |
| `print()` in production paths | Token / API key / merchant PII in MoneyMoney debug log | All `print` guarded by `if DEBUG then` block; `DEBUG = false` in shipped build, asserted by build pipeline grep |
| Network call to non-Zettle host | Telemetry / data exfiltration violation of no-telemetry promise | Hostname allowlist in a `Connection()` wrapper; CI lint catches any `://` string outside the allowlisted constants |
| Sandbox key committed to repo | Key in git history forever, trust damage | `gitleaks` / `detect-secrets` pre-commit hook; key only in GitHub Actions encrypted secrets; live-sandbox CI job disabled for forks |
| TLS verification disabled "to debug" | MITM possible on user's network | `Connection()` default verifies TLS; no developer flag to disable. If a debug toggle exists, it must require source modification (not config). |
| TLS certificate pinning attempted via undocumented MoneyMoney internals | Breakage on every CA rotation; angry users; possibly inoperable | Do not attempt cert pinning. MoneyMoney's `Connection()` already does TLS verification against system trust store; that's the right layer. Document the decision in an ADR. |
| Logging Zettle merchant ID / payout bank account | Personal/business data in logs | Treat merchant data with the same redaction discipline as the API key |
| MoneyMoney version coupling | Future MoneyMoney update breaks the extension silently | Pin `WebBanking{version = X.YY}` to the Lua API version expected; on mismatch detection (if MoneyMoney provides one), surface a German error explaining the version requirement |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Account label `"PayPal POS"` is the same for every instance | User with multiple PayPal POS accounts can't tell them apart in MoneyMoney's sidebar | Default label includes merchant name from the Zettle profile API: `"PayPal POS — <merchant-name>"`. Allow override via `InitializeSession2` credential field. |
| English error messages on a German-primary product | Confused users, support burden | All user-facing strings German. English only in technical/contributor docs. |
| Refund shown with no link to original sale | Operator can't reconcile "what was refunded" | `purpose` of refund includes `"Erstattung zu Beleg #<original-purchaseNumber>"` and the original `purchaseUUID1`. |
| First-refresh shows nothing because `since` was set far back and pagination caps out early | User thinks the extension is broken | First refresh: warn (German) that an initial sync of N months can take multiple refresh cycles; show progress where MoneyMoney's API allows. |
| Credentials dialog asks for both `client_id` and `api_key` without explanation | User pastes wrong values into wrong fields | Each field labeled in German with one-line context and a link (in README, not in dialog) to a screenshot of where to find each in my.zettle.com. |
| No way to test connection from inside MoneyMoney | User has to wait for first scheduled refresh to find out the key was wrong | On `InitializeSession2`, perform a lightweight ping (e.g. fetch merchant profile) so bad keys fail fast with a clear German error message. |
| Payout shown as a generic outflow | Operator can't tell payout from a fee or a real expense | `bookingText = "Auszahlung"` and `purpose = "Auszahlung an Bankkonto <last-4-digits-if-exposed>"`. |

## "Looks Done But Isn't" Checklist

- [ ] **Account setup:** Often missing per-instance differentiation — verify two PayPal POS accounts can coexist in one MoneyMoney install with distinguishable labels.
- [ ] **Initial sync:** Often missing the multi-cycle UX — verify a 12-month first sync completes (eventually) and doesn't lock up MoneyMoney.
- [ ] **Refunds:** Often missing the partial-refund case — verify a sale of €10 with a €3 partial refund produces a -€3 refund row linked to the original.
- [ ] **VAT in `purpose`:** Often missing the multi-rate case — verify a single purchase with both 19% and 7% items shows both rates.
- [ ] **Tip:** Often missing when tip = 0 — verify the line is absent (not "Trinkgeld: 0,00 EUR") to avoid noise.
- [ ] **Fees:** Often missing on the first day of operation (no payout yet) — verify the extension shows pending sales without yet emitting fee rows, and emits fee rows retroactively when the payout appears.
- [ ] **Pending vs booked:** Often missing the `booked=false` flag for unsettled sales — verify a sale rung up today shows as pending until the payout day.
- [ ] **Currency formatting:** Often missing for non-EUR — verify USD and GBP at least render correctly (out-of-scope localization but should not error).
- [ ] **Dedup:** Often missing the double-refresh idempotency test — verify running `RefreshAccount` twice produces zero duplicates.
- [ ] **Error messages:** Often missing German translation — grep for any `error("…")` containing English text in the final .lua.
- [ ] **Debug log:** Often containing tokens — grep the MoneyMoney debug log after a full refresh for any JWT-shaped string (`eyJ…`).
- [ ] **README:** Often missing the "Inoffizielle Extensions erlauben" screenshot — verify it's the first install step.
- [ ] **Release artifact:** Often differs from a freshly-cloned local build — verify CI artifact SHA256 matches a clean checkout build on the maintainer's machine.
- [ ] **Tag signing:** Often missing — verify `git tag -v vX.Y.Z` succeeds against the maintainer's public key for every release.
- [ ] **Version in file:** Often desynced from tag — verify `WebBanking{version = …}` in the released `.lua` matches the tag.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Unstable `transactionCode` causing duplicates in users' MoneyMoney | HIGH | (1) Ship fix making identity stable. (2) Document a one-time cleanup procedure in the release notes — user must manually delete duplicates (MoneyMoney has no scriptable cleanup). (3) Send a German announcement on the GitHub release. There is no way to retroactively merge duplicates; this is why the double-refresh test is non-negotiable up front. |
| Fees netted into sales in early version → corrected later | HIGH | Affected sales' gross amounts are wrong in users' DBs. Recovery requires the user to re-fetch the affected range. Provide a "Reset and re-sync" procedure: user deletes the PayPal POS account in MoneyMoney and re-adds it, accepting the full 3-year resync penalty. |
| API key leaked in a user's GitHub issue | MEDIUM | User must rotate the key at my.zettle.com immediately (revokes the old). Maintainer redacts the issue. Investigate which version of the extension emitted the key, ship a fix. |
| Sandbox key committed to repo | MEDIUM | Rotate the sandbox key at my.zettle.com. Force-push history rewrite is **not** worth it — the key is rotated, history rewrite damages contributor trust and breaks all forks. Add the pre-commit hook (Pitfall 20) so it doesn't recur. |
| Reproducible-build hash mismatch reported by user | LOW | Confirm with maintainer's local build. If genuine drift: investigate (locale, Lua version, file order). Most cases: user is using a different Lua version to verify — clarify in README that SHA256 verification requires matching the documented build environment. |
| Wrong VAT rate hard-coded | MEDIUM | Ship fix reading `vatPercentage` from Zettle. Users' historical data is wrong but VAT period reports can be recomputed from PayPal POS directly. Communicate to known users via release notes. |
| MoneyMoney version update breaks the extension | MEDIUM | Yves runs preview MoneyMoney builds when published; on first sign of incompatibility, open issue + pin a known-good MoneyMoney version range in README. Most breakages are field additions, not removals. |
| User can't enable "Inoffizielle Extensions" because of corporate policy MDM | LOW | Out of scope for fix. README mentions this as a known limitation; suggest the stretch goal of getting the extension into the official MoneyMoney bundle. |

## Pitfall-to-Phase Mapping

The phases below are the consumer of this research. The roadmap should at least cover these themes (final phase naming is the roadmap's concern).

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 — Incomplete transaction records | Phase 2 (Transaction modeling) | Schema test: every field present in golden fixture |
| 2 — `bookingDate` vs `valueDate` confusion | Phase 2 + Phase 3 | ADR documenting the mapping; unit test for pending vs settled |
| 3 — Unstable transaction identity | Phase 2 | Double-refresh idempotency test |
| 4 — Ignoring `since` | Phase 3 (Incremental refresh) | Test asserts `startDate` ≈ `since` on every fetch |
| 5 — Wrong error type | Phase 4 (Error handling) | Tests cover 401-on-token, 401-post-token, 429, 5xx, network — only the first raises `LoginFailed` |
| 6 — Wrong OAuth grant type | Phase 1 (Authentication spike) | Integration test against sandbox token endpoint |
| 7 — Sandbox/production confusion | Phase 5 (Reproducible build) | Grep test: shipped `.lua` contains no `sandbox` substring |
| 8 — Pagination mishandling | Phase 3 | Off-by-one fixture; large-result fixture |
| 9 — Timezone errors | Phase 2 | DST boundary fixtures; end-of-day local time fixture |
| 10 — Fees netted | Phase 3 (Finance API) + ADR | Test asserts a fee row exists for every payout |
| 11 — VAT/tip missing from `purpose` | Phase 2 | Golden-file test for multi-rate + tip purpose block |
| 12 — Tip taxation classification | Phase 2 + Phase 7 (README) | README explicitly states the operator decides |
| 13 — API key in error strings | Phase 1 | Test that exercises auth failure and greps for JWT pattern in the error |
| 14 — API key persisted to disk | Phase 1 + Phase 5 (CI grep) | Build pipeline grep for `io.open`, `os.tmpname` |
| 15 — Unexpected hosts | Phase 1 + Phase 5 | CI grep for `://` outside the allowlist constants |
| 16 — User hasn't enabled unofficial extensions | Phase 7 (Documentation) | README structural review |
| 17 — Lua sandbox surprises | Phase 1 (sandbox probe) + Phase 5 (build) | Probe extension in MoneyMoney; ADR pinning available globals |
| 18 — UTF-8 / umlaut handling | Phase 2 | Umlaut + emoji fixtures |
| 19 — Currency minor units | Phase 2 | Multi-currency unit tests including JPY (0 decimals) |
| 20 — CI secrets leak | Phase 5 | Pre-commit hook (`gitleaks`) wired in CONTRIBUTING.md; CI live-sandbox job gated to repo, not forks |
| 21 — Unsigned tags from CI | Phase 5 | Maintainer-signs-locally process documented in `RELEASE.md`; tag verification step in CI |
| 22 — Non-reproducible build | Phase 5 | CI builds twice and diffs |
| 23 — Coverage regression | Phase 5 | `luacov` threshold gate |
| 24 — Version desync | Phase 5 + Phase 7 | Build substitutes `__VERSION__` from tag; test asserts match |
| 25 — GoBD misunderstanding | Phase 7 (Documentation) | README has "GoBD-Hinweis" section |

## Sources

- [MoneyMoney Web Banking API (offical reference)](https://moneymoney.app/api/webbanking/) — transaction fields, `since` parameter, `LoginFailed` constant, sandbox guarantees.
- [Zettle Developer Portal — Purchase API reference](https://developer.zettle.com/docs/api/purchase/api-reference-md) — purchase / refund / VAT / tip / pagination shape.
- [Zettle Developer Portal — OAuth assertion grant](https://developer.zettle.com/docs/api/oauth/user-guides/set-up-app-authorisation/set-up-authorisation-assertion-grant) — token-exchange flow, `invalid_grant` semantics, 7200 s lifetime.
- [Zettle Developer Portal — APIs overview (rate limits, 429 behavior)](https://developer.zettle.com/docs/api) — rate-limit signaling.
- [iZettle API documentation (GitHub, historical)](https://github.com/iZettle/api-documentation) — older but more verbose purchase.adoc, useful for refund modeling and identifier stability.
- [Community MoneyMoney extensions for reference patterns](https://github.com/topics/moneymoney-extension) — bitpanda, ledger-export, truelayer extensions; observation of `transactionCode` / `purpose` patterns across the ecosystem.
- Maintainer's prior experience with MoneyMoney + GPG-signed release pipelines (`feedback_commit_signing`, `tech_standards`).
- German tax-law references (§3 Nr. 51 EStG for employee tips, §147 AO + GoBD for retention) — referenced not paraphrased.

Confidence summary:
- MoneyMoney semantics (Pitfalls 1–5, 16–18, 24): HIGH — confirmed against the official docs.
- Zettle API shape (Pitfalls 6–11, 19): HIGH — confirmed against the developer portal and iZettle GitHub repo.
- Lua sandbox specifics (Pitfall 17): MEDIUM — MoneyMoney docs do not enumerate prohibited globals. Phase 1 must include a small probe extension to pin the answer.
- Rate-limit exact numbers (performance traps): MEDIUM — Zettle documents 429 behavior but not the specific quotas. The defensive caps in the performance traps section assume modest limits.
- German tax law nuances (Pitfalls 12, 25): MEDIUM — the extension's correct posture (surface the facts, do not classify) is HIGH-confidence; the specific tax-law references are a directional aid, not professional tax advice.

---
*Pitfalls research for: MoneyMoney PayPal POS / Zettle extension — German merchant focus, single-file Lua, GitHub Actions CI, MIT, GPG-signed releases.*
*Researched: 2026-06-16*
