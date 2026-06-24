# Screenshots queue

Placeholder images pending real capture (CP-5 in the Phase-6 plan —
`.planning/phases/06-release-polish/06-CONTEXT.md`).

| Filename                              | Captures                                                                 | Status      |
| ------------------------------------- | ------------------------------------------------------------------------ | ----------- |
| `inoffizielle-extensions-erlauben.png` | Schalter "Inoffizielle Extensions erlauben" in MoneyMoney → Einstellungen → Erweiterungen | placeholder |
| `help-menu-extensions-folder.png`     | Menüpunkt "Hilfe → Erweiterungen im Finder zeigen" in MoneyMoney         | placeholder |

To replace a placeholder:

1. Capture the screenshot in current-stable MoneyMoney (target version 2.4.x
   per ADR-0003 sandbox-probe results — older releases use slightly different
   menu labels).
2. Save the PNG at the same path (overwriting the 1×1 placeholder).
3. Commit with the conventional message `docs(img): capture <filename>`.
4. Remove the `<!-- screenshot: pending — CP-5 -->` marker next to the image
   reference in `README.md`.

The placeholder PNGs are valid 1×1 transparent images (~68 bytes) so the
markdown image references in `README.md` render without broken-image
icons before CP-5 is closed.
