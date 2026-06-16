# MoneyMoney PayPal POS Extension

> Eine Community-Extension für [MoneyMoney](https://moneymoney.app), die PayPal POS (ehemals Zettle) als unterstützten Kontotyp ergänzt — Karten-Umsätze, Refunds, Gebühren und Auszahlungen direkt in MoneyMoney.

[![CI](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/yves-vogl/moneymoney-paypal-pos-extension/branch/main/graph/badge.svg)](https://codecov.io/gh/yves-vogl/moneymoney-paypal-pos-extension)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/yves-vogl?logo=githubsponsors&logoColor=white&label=Sponsors&color=ea4aaa)](https://github.com/sponsors/yves-vogl)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Status: Pre-Release](https://img.shields.io/badge/Status-Pre--Release-orange.svg)](#status)
[![Lua 5.4](https://img.shields.io/badge/Lua-5.4-blue.svg?logo=lua&logoColor=white)](https://www.lua.org/)
[![MoneyMoney](https://img.shields.io/badge/MoneyMoney-Extension-3b8dbd.svg)](https://moneymoney.app/extensions/)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://www.conventionalcommits.org)
[![GPG-signed commits](https://img.shields.io/badge/GPG-signed%20commits-success.svg)](#verifikation-signierter-releases)

---

## Status

**Diese Extension befindet sich in aktiver Entwicklung.** Es existiert noch kein installierbares Release. Das erste signierte Release (`v0.1.0`) wird veröffentlicht, sobald der grundlegende Umsatz-Sync (Phase 3 der [Roadmap](.planning/ROADMAP.md)) stabil läuft.

Wer den Fortschritt verfolgen oder mitwirken möchte: ⭐ das Repository markieren und im Abschnitt [Beitragen](#beitragen) starten.

> _Hier erscheint nach `v0.1.0` ein Screenshot der Extension in MoneyMoney._
> <!-- TODO: screenshot/demo GIF after v0.1.0 -->

---

## Warum diese Extension

Sole Proprietors und kleine Händler in Deutschland nutzen **PayPal POS** für Karten-Zahlungen am Tresen. MoneyMoney unterstützt von Haus aus keine PayPal-POS-Konten — Karten-Umsätze tauchen erst sichtbar auf, wenn PayPal die Auszahlung auf das Geschäftskonto bucht. Damit sind Einzel-Umsätze, Trinkgelder, Refunds, USt-Aufteilung und Gebühren in MoneyMoney nicht abbildbar — Buchhaltung passiert daneben in Excel.

Diese Extension schließt die Lücke: API-Key einmal eintragen, ab dann erscheinen alle Karten-Umsätze, Refunds, Gebühren und Auszahlungen automatisch in MoneyMoney — mit USt- und Trinkgeld-Transparenz, geeignet als Beleg-Grundlage für die Buchhaltung.

---

## Funktionen (geplant für v0.1.0)

- ✅ Anmeldung per PayPal POS API-Key (JWT-Bearer Grant)
- ✅ Karten-Umsätze (Sales) als einzelne Transaktionen
- ✅ Refunds als getrennte Buchungen mit Verweis auf den Original-Umsatz
- ✅ Trinkgelder und USt-Beträge im Verwendungszweck transparent
- ✅ Gebühren pro Umsatz (Finance API)
- ✅ Auszahlungen (Payouts) als separater Buchungstyp
- ✅ Inkrementeller Sync — schnelle Refreshes
- ✅ Komplett deutschsprachige Oberfläche

Out of Scope für v0.1.0: Mehrere Händler-Konten parallel, Live-Item-Level-Reporting im POS-Sinne, Schreibzugriff auf PayPal POS.

---

## Voraussetzungen

- **MoneyMoney** in aktueller oder vorletzter Stable-Version
- Ein **PayPal POS / Zettle** Geschäftskonto in Deutschland
- Ein vom Händler erstellter **API-Key** (JWT) — Anleitung folgt mit `v0.1.0`
- macOS — MoneyMoney läuft ausschließlich auf macOS

---

## Installation

> Installation und Verifikation werden ab `v0.1.0` vollständig dokumentiert. Solange kein Release existiert, bitte keine Installation aus dem `main`-Branch versuchen — die Extension ist noch nicht funktionsfähig.

Geplanter Installations-Pfad (gilt ab `v0.1.0`):

1. Aktuelles Release von der [Releases-Seite](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases) herunterladen: `Extension.lua` und `Extension.lua.sha256` und die `.asc`-Signatur-Datei.
2. SHA256-Prüfsumme und GPG-Signatur verifizieren — siehe [Verifikation signierter Releases](#verifikation-signierter-releases).
3. In MoneyMoney **Hilfe → Erweiterungen im Finder zeigen** öffnen und `Extension.lua` in den Erweiterungs-Ordner kopieren.
4. In MoneyMoney **Einstellungen → Erweiterungen** den Schalter **„Inoffizielle Extensions erlauben"** aktivieren.
5. **Konto hinzufügen → PayPal POS** wählen, den API-Key einfügen, fertig.

---

## Verifikation signierter Releases

Alle Tags und Release-Assets dieses Repos werden mit dem GPG-Schlüssel des Maintainers signiert:

```
Fingerprint: FDE07046 A617 8E89 ADB5 7FD3 DE30 0C53 D8E1 8642
Maintainer:  Yves Vogl <yves@kadenz.live>
```

So prüft man ein Release:

```bash
# Public Key vom Keyserver importieren
gpg --keyserver keys.openpgp.org --recv-keys FDE07046A6178E89ADB57FD3DE300C53D8E18642

# Heruntergeladene Signatur prüfen
gpg --verify Extension.lua.asc Extension.lua

# SHA256 prüfen
shasum -a 256 -c Extension.lua.sha256
```

Eine erfolgreiche Verifikation gibt `Good signature from "Yves Vogl <yves@kadenz.live>"` aus und bestätigt, dass die Datei seit dem signierten Release nicht verändert wurde.

> Hinweis: MoneyMoney selbst kennt eine separate RSA-Signatur, die nur der MoneyMoney-Hersteller vergeben kann. Diese Extension läuft daher initial als „Inoffizielle Extension". GPG-Signatur und SHA256-Checksumme bilden die unabhängige Vertrauenskette dieser Veröffentlichung.

---

## Datenschutz & Sicherheit

- **Keine Telemetrie.** Die Extension sendet ausschließlich Anfragen an offizielle PayPal-/Zettle-API-Hosts (`oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`).
- **Keine Drittparteien.** Kein Analytics, kein externes Logging.
- **API-Keys** werden ausschließlich über MoneyMoney's eingebaute Anmelde-Daten-Verwaltung gespeichert — nie geloggt, nie in Fehlertexten ausgegeben.
- **Read-Only.** Die Extension liest nur — sie führt keinerlei schreibende Operationen auf dem PayPal-POS-Konto durch.

---

## Unterstützen

Wer diese Extension nützlich findet und die Weiterentwicklung unterstützen möchte: [GitHub Sponsors → @yves-vogl](https://github.com/sponsors/yves-vogl). Sponsoring ist freiwillig und ändert nichts am Funktionsumfang oder am Open-Source-Status — die Extension bleibt MIT-lizenziert und kostenlos.

---

## Beitragen

Beiträge sind willkommen — egal ob Bug-Report, Test-Fixture aus einem ungewöhnlichen Sale-Setup oder Pull Request.

- **Fehler oder Vorschlag** → [Issues](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues)
- **Fragen, Ideen, Erfahrungsaustausch** → [Discussions](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/discussions)
- **Code-Beiträge** → Pull Requests gegen `main`; bitte signierte Commits (siehe [CONTRIBUTING.md](CONTRIBUTING.md), folgt mit Phase 6 der Roadmap).

Alle Commits und Tags in diesem Repo sind GPG-signiert. Branch Protection erzwingt linear history und signed commits.

---

## Roadmap

Die vollständige Roadmap mit allen sechs Phasen liegt unter [`.planning/ROADMAP.md`](.planning/ROADMAP.md). Aktuelle Phase und Status: [`.planning/STATE.md`](.planning/STATE.md).

---

## Lizenz

[MIT](LICENSE) — frei nutzbar, modifizierbar und weitergebbar. Keine Garantie, keine Haftung.

---

## Disclaimer

Dies ist ein **inoffizielles Community-Projekt**. Weder **MoneyMoney GmbH** noch **PayPal / Zettle** sind Herausgeber, Sponsor oder verantwortlich für diese Extension. Alle genannten Markennamen sind Eigentum ihrer jeweiligen Inhaber.
