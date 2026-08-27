# ADR-0010: Internationalization Posture

## Status

ACCEPTED

## Date

2026-08-27

## Deciders

Yves Vogl

## Context

Issue #87 (OpenSSF Silver SHOULD criterion `internationalization`) asks
for a decided posture: *"The software produced by the project SHOULD be
internationalized to enable easy localization for the target audience's
culture, region, or language."* Per the criterion's own details
(bestpractices.dev, accessed 2026-08-27), internationalization is "the
design and development of a product […] that enables easy localization" —
it is an architecture property, distinct from shipping multiple locales
or runtime switching.

Current state of the code:

- `src/i18n.lua` is a locale-keyed string table `{ de = {…}, en = {…} }`
  with a single access point `M_i18n.t(key, ...)` and the fallback chain
  *active locale → en → key literal*. Every user-facing string (account
  names, transaction name/purpose templates, credential labels, error
  messages) goes through it (I18N-01/02).
- English parity is not aspirational: `spec/i18n_spec.lua` enforces
  bidirectional key parity between the `de` and `en` tables, so a string
  cannot be added in one language only.
- The active locale is hard-coded: `local LOCALE = "de"` (I18N-03: no
  locale switch in v1).

What the host application offers (MoneyMoney WebBanking API,
<https://moneymoney.app/api/webbanking/>, accessed 2026-08-27):

- There is **no API that exposes MoneyMoney's UI language** to an
  extension (no `MM.language` or equivalent).
- `MM.localizeText` is an `NSLocalizedString` wrapper that only
  translates strings shipped *inside MoneyMoney itself* — it cannot
  translate extension-authored strings.
- `connection.language` is the default value of the outbound HTTP
  `Accept-Language` header (initialised from the OS language). It is an
  HTTP concern, not a documented UI-language signal.
- `MM.localizeDate` / `MM.localizeNumber` / `MM.localizeAmount` localize
  typed values; booked amounts, dates and balances are passed to
  MoneyMoney as typed data and rendered locale-correctly by the host.

The audience fact from #87 stands: MoneyMoney is a German-market product
and the PayPal POS onboarding in this extension's docs is written against
the German dialog labels.

## Decision

1. **Keep the internationalized architecture as the contract.** All
   user-facing strings live in the locale-keyed table behind
   `M_i18n.t()`; the DE/EN parity test remains mandatory. Localizing to
   a new language is a data change (add a table), activating one is a
   one-line change (`LOCALE`). This satisfies the criterion as written.
2. **German stays the single active locale, hard-coded.** No runtime
   locale switching ships, because the host exposes no UI-language
   signal to switch on (see Context) — any switch would be a guess.
3. **Docs split stays as-is:** user documentation German
   (`mkdocs.yml: language: de`), contributor surface (CONTRIBUTING.md,
   ADRs, code comments, commits) English.

## Alternatives Considered

- **Infer the locale from `connection.language`'s OS-language default.**
  Rejected. The attribute is documented as an outbound header value, not
  a UI-language API; the OS language need not match MoneyMoney's UI
  language; and — decisive — flipping the active locale for existing
  users would rewrite the `name`/`purpose` text of transactions on the
  next refresh, undermining the stable-output expectation that the
  refresh idempotency invariant protects.
- **A user-visible locale setting (extra credential field).** Rejected
  for now: a settings surface with exactly one plausible non-default
  value and no demonstrated demand is complexity without a user. The
  architecture keeps this option a small change if demand appears.
- **`MM.localizeText` for extension strings.** Inapplicable — it only
  resolves MoneyMoney's own string catalog.

## Consequences

- OpenSSF `internationalization` is answered **Met**: the software is
  internationalized (locale-keyed tables, single access point, enforced
  EN parity, host-side locale-aware rendering of typed values); the
  precise limitation — no runtime locale selection — is a host-API
  constraint documented here, not a design gap.
- The stale claim in earlier planning material that `src/i18n.lua`
  "ships a single German string table" is superseded by this ADR.
- If MoneyMoney ever exposes its UI language to extensions, revisiting
  point 2 is a deliberate, small change: initialise `LOCALE` from that
  API. Until then, `LOCALE` changes require a maintainer decision.
