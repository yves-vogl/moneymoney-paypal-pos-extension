# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

<!-- lektor-review: pending — v0.2.0 sections drafted as engineering placeholder per Plan 04-06 Task 3; a final lektor pass is queued as a Yves checkpoint after merge. -->

## [1.0.0] - 2026-MM-DD

<!-- lektor-review: pending — CP-1; CHANGELOG.md v1.0.0 wording is engineering-grade; Yves or loop-lektor finalises before tag publication. -->

**First stable release.**

### Hinzugefügt

- Reproduzierbare Release-Pipeline (`.github/workflows/release.yml`): wird
  durch einen GPG-signierten Tag ausgelöst, prüft die Signatur gegen den
  Maintainer-Fingerabdruck, baut das Artefakt deterministisch, hängt
  `paypal-pos.lua` und `paypal-pos.lua.sha256` an die GitHub-Release.
- `__VERSION__`-Substitution in `tools/build.lua` aus dem Git-Tag; die
  `WebBanking{version}`-Angabe im Artefakt entspricht der veröffentlichten
  Version.
- Zweisprachige Dokumentation: `README.de.md` (deutsch-primär, mit
  Screenshot-illustrierter Installationsanleitung, GoBD-Hinweis und
  Datenschutz/Sicherheits-Erläuterungen); `README.md` als englischer
  Pointer für internationale Besucher.
- `CONTRIBUTING.md` (englisch) dokumentiert den Entwicklungs-Loop,
  Test-Konventionen, Amalgamator-Architektur, Release-Prozess und die
  GPG-signierten-Tag-Anforderung.
- Vier neue MADR-Architekturentscheidungen (ADR-0002 LocalStorage-Token-
  Cache, ADR-0006 JWT-Bearer-Only-Authentifizierung, ADR-0007 keine
  TLS-Pinning, ADR-0008 String-Return-Fehlermuster) — sie ergänzen die
  bestehenden ADR-0001/0003/0004/0005 zur lückenlosen Dokumentation aller
  in Phase 2–5 getroffenen Entscheidungen.
- Secret-Scanning per gitleaks (`gitleaks/gitleaks-action@v2`) auf jedem
  Push und Pull-Request.
- Conventional-Commits-Lint (`.github/workflows/commit-lint.yml`) prüft
  jeden Commit eines PR gegen die Conventional-Commits-Grammatik.
- Branch-Protection auf `main`: Pull-Request-Pflicht, GPG-signierte
  Commits erforderlich, alle CI-Checks grün, lineare History.
- Repository-Metadaten: deutsche Beschreibung und sieben Themen
  (`moneymoney`, `moneymoney-extension`, `paypal-pos`, `zettle`, `lua`,
  `germany`, `accounting`).
- META-03-Wächter (`spec/meta_no_tax_classification_spec.lua`) erweitert
  auf alle Markdown-Dokumentations-Dateien: README.md, README.de.md,
  CONTRIBUTING.md, CHANGELOG.md und alle ADRs werden bei jedem CI-Lauf
  auf die 13 verbotenen Phrasen geprüft.

### Bekannte Grenzen (unverändert seit v0.2.0)

- Verzögerte Buchung von Auszahlungen (1–2 Aktualisierungszyklen bei
  wöchentlichem oder monatlichem Auszahlungsrhythmus) — siehe ADR-0004.
- Tagesaggregat von Gebühren bei nachträglich nachgereichter Verknüpfung
  durch Zettle — siehe README.de.md.
- 90-Tage-Klammer für den Erstabgleich; ältere Umsätze werden nicht
  sichtbar gemacht.
- Umsätze in anderen Währungen als EUR werden übergangen.
- Nach einer Token-Revocation muss der API-Key in MoneyMoney neu
  eingefügt werden (ERR-04 — dokumentiert in ADR-0005).

### Sicherheit

- Keine Telemetrie, keine Dritt-Anbieter: das Artefakt kontaktiert
  ausschließlich `oauth.zettle.com`, `purchase.izettle.com` und
  `finance.izettle.com`; ein CI-Gate erzwingt diese Egress-Allowlist auf
  jedem Release.
- API-Keys werden ausschließlich über MoneyMoneys eingebaute
  Anmelde-Daten-Verwaltung gespeichert — nie in LocalStorage, nie in
  Logs, nie in Fehlermeldungen.
- Alle Tags sind GPG-signiert (Maintainer-Fingerabdruck
  `FDE07046A6178E89ADB57FD3DE300C53D8E18642`); jeder Release-Lauf prüft
  die Signatur, baut das Artefakt reproduzierbar nach und veröffentlicht
  eine SHA256-Prüfsumme als Asset.

## [0.2.0] - 2026-MM-DD

### Hinzugefügt

- Vollständige Buchhaltungssicht: Auszahlungen, Gebühren, MwSt-Aufschlüsselung,
  beglichene und offene Salden in einem Konto.
- Refunds verlinken zum ursprünglichen Beleg: die Belegnummer des Original-
  Verkaufs erscheint im Verwendungszweck der Rückerstattungsbuchung.
- Pro Kartenzahlung: Kartentyp und Zahlungsart (kontaktlos, Chip, online) im
  Verwendungszweck.
- MwSt-Aufschlüsselung pro Satz, wenn das Unternehmen mit gemischten Sätzen
  arbeitet (z.B. 19 % auf Speisen vor Ort, 7 % zum Mitnehmen).

### Geändert

- `balance` zeigt jetzt den beglichenen Saldo: bereits ausgezahlte plus
  auszahlungsbereite Umsätze.
- `pendingBalance` zeigt offene Umsätze, die noch nicht abgerechnet sind.
- Abgeschlossene Verkäufe werden mit Wertstellungsdatum (dem Auszahlungstag)
  gebucht, sobald die Auszahlung im Finance-API sichtbar ist.

### Voraussetzung für Bestandskunden

- Der API-Key muss zusätzlich zur Berechtigung `READ:PURCHASE` auch
  `READ:FINANCE` enthalten. Neuen Key erzeugen unter
  https://my.zettle.com/apps/api-keys mit beiden Scopes; anschließend in
  MoneyMoney das bestehende PayPal-POS-Konto entfernen und mit dem neuen
  Schlüssel neu hinzufügen.

### Bekannte Grenzen

- Auszahlungen werden Verkäufen zeitlich zugeordnet (frühester PAYOUT mit
  Zeitstempel ≥ PAYMENT.Zeitstempel). Bei wöchentlicher oder monatlicher
  Auszahlung kann ein Verkauf 1-2 Aktualisierungszyklen brauchen, bis er
  als beglichen markiert wird.
- Die Aufschlüsselung von Gebühren (pro Verkauf vs. Tagesaggregat) richtet
  sich nach den Daten, die Zettle liefert. Bei lückenhafter Verknüpfung
  wird ein Tagesaggregat gebucht; sollte Zettle die Verknüpfung später
  nachreichen, kann am betroffenen Tag zusätzlich eine Aggregat-Zeile
  bestehen bleiben — diese gegebenenfalls manuell in MoneyMoney löschen.
- Erstabgleich umfasst maximal 90 Tage; ältere Umsätze sind nicht sichtbar.
- Umsätze in anderen Währungen als EUR werden übergangen.

### Sicherheit

- Die Extension nimmt keine steuerrechtliche Bewertung von Umsätzen oder
  Trinkgeldern vor und beansprucht keine GoBD-Bewertung. Diese Einordnung
  bleibt der Steuerberatung des Anwenders überlassen.
- Keine Telemetrie, keine Drittparteien: ausschließlich `oauth.zettle.com`,
  `purchase.izettle.com` und `finance.izettle.com` werden kontaktiert.
- Bearer-Token werden niemals geloggt; API-Key bleibt ausschließlich in
  MoneyMoneys eingebauter Anmelde-Daten-Verwaltung.

### Foundations (previously tracked under Unreleased — Phase 1 + 2 + 3 scaffolding)

- Project scaffolding under `.planning/` (PROJECT, REQUIREMENTS, ROADMAP, STATE, research).
- MIT license, `.gitignore`, German-language README, GPG-verification documentation.
- GPG-signed commits and tags enforced via branch protection (`required_signatures`, `required_linear_history`).
- Phase 1 source-tree foundations: deterministic amalgamator (`tools/build.lua` + `tools/manifest.txt`) with pure-Lua SHA-256 and `--verify` byte-identical check; `src/` module layout with `webbanking_header.lua`, `log.lua` (SEC-01 redactor), `i18n.lua` (DE/EN tables), and `entry.lua` walking skeleton.
- Test harness: `spec/helpers/mm_mocks.lua` mocking the full MoneyMoney embedded-interpreter surface; 40 busted tests (build, mocks, redaction, i18n, entry); 99.19 % luacov line coverage on the amalgamated artifact.
- Sandbox probe extension `tools/probe.lua` (Q1/Q4/Q5/Q7/Q8) and ADR-0003 template; ADR-0001 (amalgamator design) accepted.
- GitHub Actions CI workflow (`.github/workflows/ci.yml`): luacheck, busted, 85 % coverage threshold gate, self-hosted coverage badge generation + push to `coverage-badge` branch (only on `main` pushes), reproducible-build check, `DEBUG = false` gate, egress allowlist gate, no-AI-attribution gate. Pinned to `ubuntu-24.04`, Lua 5.4 via `leafo/gh-actions-lua@v13`.
- README badges: CI status, self-hosted Coverage, OpenSSF Scorecard, GitHub Sponsors, MIT, Pre-Release status, Lua 5.4, MoneyMoney-Extension, Conventional Commits 1.0.0, GPG-signed commits. The coverage badge is served from the repo's own `coverage-badge` branch via `raw.githubusercontent.com` — no third-party renderer or coverage host.
- OpenSSF Scorecard workflow (`.github/workflows/scorecard.yml`): weekly + on `main` push + on branch-protection-rule changes. Analyses the repo against the 18 supply-chain-security checks and publishes the score to `api.securityscorecards.dev` (Linux Foundation public-good infrastructure). SARIF results are also uploaded to GitHub code-scanning for in-repo review.
- `SECURITY.md` disclosure policy (German primary, English fallback): supported-versions table, GitHub Private Vulnerability Reporting as preferred channel, GPG-encrypted email as alternative, response-time expectations (72 h ack / 7 d triage), reporter acknowledgement policy, explicit out-of-scope list (MoneyMoney / PayPal / user-side config). Improves OpenSSF Scorecard's `Security-Policy` check.
- Dependabot config (`.github/dependabot.yml`) for GitHub Actions: weekly Monday PRs to bump pinned action versions. Improves OpenSSF Scorecard's `Dependency-Update-Tool` check. LuaRocks is not Dependabot-supported; Lua tool versions float to latest at CI install time.
- GitHub Sponsors funding metadata (`.github/FUNDING.yml`) and README *Unterstützen* section.

[Unreleased]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases/tag/v1.0.0
[0.2.0]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases/tag/v0.2.0
