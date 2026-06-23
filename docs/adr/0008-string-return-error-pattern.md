# ADR-0008: All callbacks return nil/success or a localized German error string

## Status

ACCEPTED

## Date

2026-06-22

## Deciders

Yves Vogl

## Context

MoneyMoney's WebBanking API defines the following return-value contract for
the four mandatory callbacks (per `moneymoney.app/api/webbanking/` and the
existing community extensions audited in CLAUDE.md):

| Callback             | Success return                                       | Failure return                  |
| -------------------- | ---------------------------------------------------- | ------------------------------- |
| `InitializeSession2` | `nil`                                                | `LoginFailed` (sentinel) or a localized error string |
| `ListAccounts`       | `{ <account-table>, ... }`                           | localized error string         |
| `RefreshAccount`     | `{ balance = ..., transactions = {...} }`            | localized error string         |
| `EndSession`         | `nil`                                                | localized error string         |

MoneyMoney renders error strings **verbatim** in its native UI. A raw Lua
error (i.e. `error("attempt to index nil value")`) escapes to MoneyMoney as
a generic "Lua error" surface — useless for a non-technical merchant trying
to figure out whether their API key expired or their network is down.

The realistic users of this extension are German sole proprietors and small
merchants. They read MoneyMoney in German. They do not read Lua tracebacks.
The error string is the entire UX of the failure path.

This ADR retroactively documents the Phase-2 + Phase-3 + Phase-4 + Phase-5
discipline — the string-return pattern was decided pragmatically during
Phase 2 (Plan 02-03 `M_errors` design) and held consistently through all
subsequent phases. ADR-0005 §Invariants 1–6 formalized the resilience
shape on top of this pattern; this ADR documents the foundational rule
itself.

References:

- moneymoney.app/api/webbanking/ — callback return-value contract.
- Phase-2 Plan 02-03 — `M_errors` / `M_i18n` design.
- Phase-5 ADR-0005 §Invariants 1–6 — ERR-01..ERR-06 contracts built on
  this pattern.
- CLAUDE.md → "Required Entry Points" table — return-value column.
- `src/i18n.lua` — `error.*` localization table.

## Decision

Every MoneyMoney callback in `src/entry.lua` returns either:

1. **Success:** `nil` (for `InitializeSession2` / `EndSession`) or a
   structured success value per the API contract (for `ListAccounts` /
   `RefreshAccount`).
2. **Failure:** the localized German error string from
   `M_i18n.t("error.<key>")`, where `<key>` is one of the
   register-by-convention keys in `src/i18n.lua` (e.g. `invalid_grant`,
   `token_revoked`, `server_busy`, `network_unavailable`,
   `unsupported_currency`).

No Lua `error()` call may **escape** the callback boundary. Internal use of
`error` / `pcall` / `xpcall` is permitted (and required in places — see
ADR-0005 Carve-out 3 for the `MM.sleep` pcall) as long as every
`pcall`/`xpcall` ultimately translates a caught error into a string-return
at the callback's top-level return statement.

The `LoginFailed` sentinel (a MoneyMoney-defined global) is reserved for
the specific case "the credentials are wrong; prompt for re-entry" — it
triggers MoneyMoney's native credential-redialog. Any non-credential
failure that should NOT trigger the dialog is returned as a plain string.

### Implementation pin

`src/entry.lua` implements the WebBanking callbacks
(`SupportsBank`, `InitializeSession2`, `ListAccounts`, `RefreshAccount`,
`EndSession`) directly at top scope. Each callback's body is structured
as an ordered sequence of fallible steps; every failing step terminates
the callback with an early `return` of a localized error string
(`M_i18n.t("error.<key>")` or one of the MoneyMoney sentinels —
`LoginFailed`, `PasswordChanged`).

Sketch (excerpted from `src/entry.lua` `RefreshAccount`):

```lua
function RefreshAccount(account, since)
  local orgUuid = account and account.accountNumber
  if type(orgUuid) ~= "string" or orgUuid == "" then
    return M_i18n.t("error.network", "missing_account")
  end

  local bearer = M_auth.cached_token(orgUuid)
  if not bearer then
    return M_i18n.t("error.network", "\xe2\x80\x94")
  end

  local purchases, fetch_err = M_purchases.fetch_all(effective_since, bearer)
  if fetch_err then return fetch_err end

  -- ...further fallible steps, each returning an error string on failure.

  return { balance = ..., transactions = ... }
end
```

The discipline that no internal module raises a Lua `error()` across
the callback boundary is enforced by **code review and the test suite**,
not by a runtime `pcall` firewall. Every internal module (`M_auth`,
`M_http`, `M_purchases`, `M_finance`, `M_mapping`, `M_pagination`,
`M_errors`) returns either a successful value or `(nil, err_string)` /
an error string up the call stack. Specs assert specific localized
error strings for every classified failure path
(see e.g. `spec/refresh_fail_whole_spec.lua`,
`spec/refresh_idempotency_spec.lua`, `spec/auth_spec.lua`), which surfaces
any regression that would either leak a raw Lua error or change a
user-facing string.

A future hardening step (tracked as an explicit TODO if the surface
grows) could add a top-level `pcall` wrapper per callback as a true
runtime safety net. As of v1.0.0 the safety net is review +
test-suite discipline; this ADR documents the actual contract rather
than an aspirational firewall.

## Consequences

**Positive:**

- A German merchant whose API key was revoked sees the localized message:

  > `"Anmeldung verloren — bitte API-Key in MoneyMoney neu eintragen."`

  (the `error.token_revoked` string from `src/i18n.lua`) instead of the raw
  Lua error `attempt to index a nil value (field 'access_token')`. The
  message tells them exactly what to do.
- The exact error string is a contract — tests assert specific strings
  (e.g. `spec/refresh_spec.lua` checks `assert.equal(M_i18n.t("error.token_revoked"), result)`). Refactors that change the string break the test, surfacing intent.
- Localization is centralized in `src/i18n.lua`. Adding a translation
  target (Phase 8+ stretch goal per ROADMAP) means adding a new keyed
  table, not auditing every callsite.
- The pattern composes with ADR-0005's ERR-01..ERR-06 invariants —
  classification (`M_errors.classify`) maps HTTP status / response shape
  to an i18n key, then the callback returns `M_i18n.t(key)`.

**Negative:**

- Stack traces are not visible to the user. If a code path raises an
  unhandled Lua `error()` it currently escapes to MoneyMoney as a
  generic "Lua error" — the in-source discipline relies on each module
  returning `(nil, err_string)` instead of raising. Specs exercise the
  classified failure paths to keep this discipline honest; a runtime
  `pcall` firewall is an explicit future-work item if the surface grows.
  Developers reproduce defects in `DEBUG = true` builds where the
  `M_log.*` channel emits more context (subject to the SEC-01 redactor).
- Tests asserting exact strings are sensitive to wording changes — a
  lektor pass that polishes error phrasing requires updating the test
  literals in lockstep. ADR-0005 §IN-04 documented this; lektor passes
  batch string and test updates together to preserve the test contract.

**Constraint for future contributors:**

- Any new error state requires:
  1. A new key in `src/i18n.lua` under `error.<key>`.
  2. A corresponding spec assertion of the exact string in the relevant
     spec file.
  3. The classifier (`M_errors.classify`) updated to emit the new key
     for the new condition.

  Phase-5 closure added `error.server_busy` (ERR-03 503/429 fallback) and
  `error.token_revoked` (ERR-04) following exactly this three-step
  recipe.

## References

- MoneyMoney WebBanking API — return-value contract per callback.
- `src/i18n.lua` — `error.*` table (canonical key list).
- `src/errors.lua` — `M_errors.classify` HTTP→key mapping.
- `src/entry.lua` — WebBanking callback dispatch with explicit early-return error strings per fallible step.
- Phase-5 ADR-0005 §Invariants 1–6 — ERR-01..ERR-06 built on this pattern.
- Phase-5 ADR-0005 Carve-out 3 — `MM.sleep` pcall internal-use precedent.
- Phase-2 Plan 02-03 — `M_errors` / `M_i18n` design provenance.
