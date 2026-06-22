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

`src/entry.lua`'s callback wrappers each carry a top-level `pcall` of the
form:

```lua
function RefreshAccount(account, since)
  local ok, result_or_err = pcall(M_refresh.run, account, since)
  if not ok then
    -- result_or_err is an internal Lua error message; log + redact then
    -- return the user-facing localized fallback.
    M_log.error("internal", { module = "RefreshAccount", err = result_or_err })
    return M_i18n.t("error.internal_unexpected")
  end
  return result_or_err
end
```

That `pcall` is the firewall. Every internal module (`M_auth`, `M_http`,
`M_purchases`, `M_payouts`, `M_balance`, `M_mapping`) is expected to
return success or a string up the call stack without `error()`-ing; the
top-level pcall is the safety net for the case where a programmer mistake
slipped through review.

## Consequences

**Positive:**

- A German merchant whose API key was revoked sees `"PayPal POS / Zettle: Der API-Key wurde widerrufen oder ist abgelaufen. Bitte unter my.zettle.com/apps/api-keys neu erzeugen."` instead of `attempt to index a nil value (field 'access_token')`. The message tells them where to go and what to do.
- The exact error string is a contract — tests assert specific strings
  (e.g. `spec/refresh_spec.lua` checks `assert.equal(M_i18n.t("error.token_revoked"), result)`). Refactors that change the string break the test, surfacing intent.
- Localization is centralized in `src/i18n.lua`. Adding a translation
  target (Phase 8+ stretch goal per ROADMAP) means adding a new keyed
  table, not auditing every callsite.
- The pattern composes with ADR-0005's ERR-01..ERR-06 invariants —
  classification (`M_errors.classify`) maps HTTP status / response shape
  to an i18n key, then the callback returns `M_i18n.t(key)`.

**Negative:**

- Stack traces are not visible to the user. A real bug is logged via
  `M_log.error` (with the SEC-01 redactor stripping any credential
  fragments from the message) but the user sees only the generic
  `error.internal_unexpected` fallback. This is the right trade for end
  users; developers reproduce in `DEBUG = true` builds where stack
  traces flow through.
- Tests asserting exact strings are sensitive to wording changes — a
  lektor pass that polishes error phrasing requires updating the test
  literals in lockstep. ADR-0005 §IN-04 documented this; the
  Phase-6 CP-1 lektor pass will batch the string + test updates
  together.

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
- `src/entry.lua` — top-level `pcall` firewall per callback.
- Phase-5 ADR-0005 §Invariants 1–6 — ERR-01..ERR-06 built on this pattern.
- Phase-5 ADR-0005 Carve-out 3 — `MM.sleep` pcall internal-use precedent.
- Phase-2 Plan 02-03 — `M_errors` / `M_i18n` design provenance.
