# Accessibility audit of the documentation site — 2026-08-27

**Scope:** the published MkDocs Material site
(<https://yves-vogl.github.io/moneymoney-paypal-pos-extension/>), audited
against WCAG 2.1 AA on a local `mkdocs build --strict` of the same commit.
The extension software itself renders no UI — MoneyMoney owns the entire
interface surface (dialogs, tables, colours, fonts, screen-reader
exposure); the extension only supplies text strings. See the
"Extension software" section at the end for that half of the criterion.

**Issue:** #86 (`accessibility_best_practices`, OpenSSF Silver SHOULD).

## Methodology

Two independent engines over all four published pages
(`/`, `/installation/`, `/api-key/`, `/faq/`), no paid tooling:

| Tool | Version | Standard | Colour schemes |
|---|---|---|---|
| axe-core (via puppeteer-core, Chrome headless) | 4.13.0 | WCAG 2.0/2.1 A+AA + axe best-practice rules | light **and** dark (`prefers-color-scheme` emulation) |
| pa11y (HTML_CodeSniffer) | 9.1.1 | WCAG2AA | light |

Site built with the pinned docs toolchain (`requirements/docs.txt`,
MkDocs 1.6.1) in `--strict` mode. Manual checks: heading-level order in
the authored Markdown, alt text of all images under `docs/img/`.

Reproduction:

```sh
pip install -r requirements/docs.txt && mkdocs build --strict -d /tmp/site
python3 -m http.server 8321 -d /tmp/site &
npx pa11y --standard WCAG2AA http://127.0.0.1:8321/           # per page
# axe: inject axe-core 4.13.0 via puppeteer-core, run per page with
# page.emulateMediaFeatures prefers-color-scheme light/dark
```

## Findings and dispositions

### Fixed in this audit (commit introducing this file)

| Finding | WCAG | Where | Fix |
|---|---|---|---|
| `color-contrast`: footer copyright line rendered with `--md-footer-fg-color--lighter`, below 4.5:1 on the indigo footer in both schemes | 1.4.3 | `.md-copyright` (theme default) | `docs/stylesheets/extra.css` raises it to the full-contrast footer foreground colour |
| `link-in-text-block`: body links distinguished from surrounding text by colour only | 1.4.1 | `.md-typeset a` (theme default) | `docs/stylesheets/extra.css` underlines links in typeset content (buttons and heading permalinks keep their non-colour distinction) |
| `aria-dialog-name`: the search overlay is `role="dialog"` without an accessible name | 4.1.2 | `.md-search` (theme default) | `docs/js/a11y.js` sets `aria-label="Suche"`; the search UI is JavaScript-only, so a JavaScript-applied name covers every state in which the dialog is operable |

### Assessed, not a defect

| Finding | Engine | Disposition |
|---|---|---|
| H32.2 "form does not contain a submit button" on the palette-toggle form and the search form | pa11y/HTML_CodeSniffer | Both are JavaScript-driven theme controls, not submitting forms. WCAG 3.2.2 requires that changing a setting must not cause an unannounced *change of context*; the palette radio toggles the colour scheme (change of presentation, not context) and the search input filters results as-you-type without moving focus or context. HTML_CodeSniffer's heuristic cannot see this; no submit button is applicable to either control. |
| `color-contrast` *incomplete* (not violation) on two FAQ list items | axe-core | axe declines to evaluate elements whose direct text is only non-text characters — here the "→" glyph between a bold label and a link. Manually verified: the glyph inherits the default body text colour, which passes 4.5:1 in both schemes (same computed colour as the body text axe passes on every page). |

### Verified clean

- **Re-run after fixes: 0 violations, all four pages, light and dark**
  (axe-core 4.13.0, WCAG A/AA + best-practice ruleset).
- **Heading order:** every page has exactly one `h1` followed by ordered
  `h2` sections; no skipped levels in the authored Markdown.
- **Images:** both screenshots under `docs/img/` carry meaningful German
  alt text describing the UI element shown.
- **Theme baseline (now verified, not assumed):** keyboard navigation,
  skip-to-content link, semantic landmarks and search keyboard shortcuts
  are Material defaults and passed both engines above.

## Extension software

The extension has no UI of its own. It runs inside MoneyMoney's Lua
sandbox and returns data (account and transaction tables, status and
error strings) that MoneyMoney renders in its native macOS interface;
accessibility of that rendering (VoiceOver exposure, contrast, keyboard
operation) is owned by MoneyMoney. The project-authored user-facing
surface is limited to text: credential field labels, transaction
name/purpose lines and error messages (`src/i18n.lua`). These follow the
conventions that keep text accessible: plain language, no information
conveyed by colour, symbols or layout, and no ASCII art — screen readers
receive the same information as sighted users.

## Badge questionnaire answer (`accessibility_best_practices` — Met)

> The documentation site was audited against WCAG 2.1 AA on 2026-08-27
> with axe-core 4.13.0 (light and dark schemes) and pa11y/HTML_CodeSniffer
> 9.1.1: three theme-level findings (footer contrast, colour-only links,
> unnamed search dialog) were fixed; the re-run reports zero violations
> on all pages in both colour schemes. Heading order and image alt text
> were verified manually. The extension software renders no UI of its
> own — MoneyMoney owns the interface; the project-authored surface is
> plain-text strings that convey no information by colour or layout.
> Audit record: `.planning/research/accessibility-audit-2026-08-27.md`.
