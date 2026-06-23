# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-06-23

**First stable release.**

### Hinzugefügt

- Reproduzierbare Release-Pipeline (`.github/workflows/release.yml`): wird
  durch einen GPG-signierten Tag ausgelöst, prüft die Signatur gegen den
  Maintainer-Fingerabdruck, baut das Artefakt deterministisch und hängt
  `paypal-pos.lua` und `paypal-pos.lua.sha256` an das GitHub-Release an.
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
- Test-Wächter gegen verbotene Steuer-Klassifizierungs-Phrasen
  (`spec/meta_no_tax_classification_spec.lua`, intern META-03) erweitert
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

## [0.2.0] — Unreleased (Phase-4-Entwicklung, in v1.0.0 zusammengeführt)

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

### Grundlagen (Phase 1–3 scaffolding, vorher unter [Unreleased] geführt)

- Projekt-Scaffolding unter `.planning/` (PROJECT, REQUIREMENTS, ROADMAP, STATE, Research).
- MIT-Lizenz, `.gitignore`, deutschsprachiges README, Dokumentation zur GPG-Verifikation.
- GPG-signierte Commits und Tags per Branch Protection erzwungen
  (`required_signatures`, `required_linear_history`).
- Quellbaum-Grundlagen aus Phase 1: deterministischer Amalgamator
  (`tools/build.lua` + `tools/manifest.txt`) mit reiner Lua-SHA-256-Implementierung
  und Byte-identischem `--verify`-Check; `src/`-Modulstruktur mit
  `webbanking_header.lua`, `log.lua` (SEC-01-Redactor), `i18n.lua`
  (DE/EN-Tabellen) und `entry.lua` als Walking-Skeleton.
- Test-Harness: `spec/helpers/mm_mocks.lua` mockt die komplette
  MoneyMoney-Embedded-Interpreter-Oberfläche; 40 busted-Tests (Build,
  Mocks, Redaktion, i18n, Entry); 99,19 % luacov-Line-Coverage auf dem
  amalgamierten Artefakt.
- Sandbox-Probe-Extension `tools/probe.lua` (Q1/Q4/Q5/Q7/Q8) und
  ADR-0003-Template; ADR-0001 (Amalgamator-Design) akzeptiert.
- GitHub-Actions-CI-Workflow (`.github/workflows/ci.yml`): luacheck,
  busted, 85-%-Coverage-Threshold-Gate, selbst gehostete
  Coverage-Badge-Generierung mit Push auf den `coverage-badge`-Branch
  (nur bei `main`-Pushes), Reproducible-Build-Check, `DEBUG = false`-Gate,
  Egress-Allowlist-Gate, No-AI-attribution-Gate. Pinning auf `ubuntu-24.04`,
  Lua 5.4 via `leafo/gh-actions-lua@v13`.
- README-Badges: CI-Status, selbst gehostete Coverage, OpenSSF Scorecard,
  GitHub Sponsors, MIT, Pre-Release-Status, Lua 5.4, MoneyMoney-Extension,
  Conventional Commits 1.0.0, GPG-signierte Commits. Das Coverage-Badge
  wird aus dem repo-eigenen `coverage-badge`-Branch via
  `raw.githubusercontent.com` ausgeliefert — kein Drittanbieter-Renderer,
  kein externer Coverage-Host.
- OpenSSF-Scorecard-Workflow (`.github/workflows/scorecard.yml`):
  wöchentlich, bei `main`-Push und bei Änderungen an
  Branch-Protection-Regeln. Analysiert das Repo gegen die 18
  Supply-Chain-Security-Checks und veröffentlicht den Score an
  `api.securityscorecards.dev` (Public-Good-Infrastruktur der Linux
  Foundation). SARIF-Ergebnisse werden zusätzlich an GitHub-Code-Scanning
  übergeben, damit Reviewer sie im Repo sehen.
- `SECURITY.md`-Disclosure-Policy (deutsch primär, englisch als Fallback):
  Supported-Versions-Tabelle, GitHub Private Vulnerability Reporting als
  bevorzugter Kanal, GPG-verschlüsselte E-Mail als Alternative,
  Reaktionszeiten (72 h Ack / 7 d Triage), Reporter-Acknowledgement-Policy,
  explizite Out-of-Scope-Liste (MoneyMoney / PayPal / nutzerseitige
  Konfiguration). Verbessert den `Security-Policy`-Check der
  OpenSSF Scorecard.
- Dependabot-Konfiguration (`.github/dependabot.yml`) für GitHub Actions:
  wöchentliche Pull-Requests am Montag zum Bump der gepinnten
  Action-Versionen. Verbessert den `Dependency-Update-Tool`-Check der
  OpenSSF Scorecard. LuaRocks wird von Dependabot nicht unterstützt;
  Lua-Tool-Versionen schwimmen zur CI-Installzeit auf den jeweils
  aktuellen Stand.
- GitHub-Sponsors-Funding-Metadaten (`.github/FUNDING.yml`) und
  *Unterstützen*-Abschnitt im README.

[Unreleased]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases/tag/v1.0.0
