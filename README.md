# MoneyMoney PayPal POS Extension

> Eine Community-Extension für [MoneyMoney](https://moneymoney.app), die PayPal POS (ehemals Zettle) als unterstützten Kontotyp ergänzt — Kartenumsätze, Rückerstattungen (Refunds), Gebühren und Auszahlungen direkt in MoneyMoney.

[![CI](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml)
[![Coverage](https://raw.githubusercontent.com/yves-vogl/moneymoney-paypal-pos-extension/coverage-badge/coverage.svg)](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/yves-vogl/moneymoney-paypal-pos-extension/badge)](https://securityscorecards.dev/viewer/?uri=github.com/yves-vogl/moneymoney-paypal-pos-extension)
[![Dokumentation](https://img.shields.io/badge/Dokumentation-online-blue?logo=mkdocs)](https://yves-vogl.github.io/moneymoney-paypal-pos-extension/)
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

---

## Inoffizielle Extensions erlauben

MoneyMoney lädt Community-Extensions nur, wenn dieser Schalter aktiv ist. Die folgenden vier Schritte führen einmalig durch die Einrichtung — danach lädt die Extension bei jedem MoneyMoney-Start automatisch.

1. In MoneyMoney **Hilfe → Erweiterungen im Finder zeigen** öffnen.

   ![Menüpunkt im Hilfe-Menü von MoneyMoney](docs/img/help-menu-extensions-folder.png)

2. `paypal-pos.lua` (aus dem aktuellen [Release](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases)) in den geöffneten Ordner kopieren.

3. In MoneyMoney **Einstellungen → Erweiterungen** öffnen und den Schalter **„Inoffizielle Extensions erlauben"** aktivieren.

   ![Schalter „Inoffizielle Extensions erlauben" in den MoneyMoney-Einstellungen](docs/img/inoffizielle-extensions-erlauben.png)

4. **Konto hinzufügen → PayPal POS** wählen und den API-Key einfügen.

**Hinweis Sandboxed vs Non-Sandboxed Build:** Der Mac-App-Store-Build von MoneyMoney läuft in einer Sandbox; der Erweiterungs-Ordner liegt unter `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/`. Der Direkt-Download von der MoneyMoney-Website ist nicht sandboxed; der Ordner liegt unter `~/Library/Application Support/MoneyMoney/Extensions/`. Der Menüpunkt **Hilfe → Erweiterungen im Finder zeigen** öffnet in jedem Fall den korrekten Pfad — daher ist die manuelle Pfad-Eingabe nicht nötig.

---

## Was die Extension jetzt kann

Mit `v0.2.0` zeigt die Extension folgende Daten aus PayPal POS / Zettle direkt in MoneyMoney:

- Vollständige Buchhaltungssicht: Auszahlungen, Gebühren, USt-Aufschlüsselung sowie beglichene und offene Salden in einem Konto.
- Rückerstattungen verlinken zum ursprünglichen Beleg — die Belegnummer des Original-Verkaufs steht im Verwendungszweck der Rückerstattungsbuchung.
- Pro Kartenzahlung: Kartentyp und Zahlungsart (kontaktlos, Chip, online) im Verwendungszweck.
- USt-Aufschlüsselung pro Satz, wenn das Unternehmen mit gemischten Sätzen arbeitet (z. B. 19 % auf Speisen vor Ort, 7 % zum Mitnehmen).
- Abgeschlossene Verkäufe werden mit Wertstellungsdatum (dem Auszahlungstag) gebucht, sobald die Auszahlung im Finance-API sichtbar ist.

---

## Was die Extension nicht macht

Die Extension beschränkt sich auf die Darstellung der PayPal-POS-Daten in MoneyMoney. Sie nimmt explizit keine Bewertungen vor, die der Steuerberatung obliegen:

- Wir nehmen keine steuerrechtliche Bewertung von Umsätzen oder Trinkgeldern vor.
- Wir bestätigen keine GoBD-Konformität.
- Wir erstellen keine USt-Voranmeldung.
- Wir ersetzen den Steuerberater nicht.

Die exportierten Daten sind als Grundlage für die Buchhaltung gedacht — die Einordnung selbst bleibt in der Verantwortung der jeweiligen Fachperson.

---

## GoBD-Hinweis

Hinweis zur Buchhaltung: Diese Extension liest Rohdaten aus der PayPal POS API und stellt sie in MoneyMoney dar. Sie erhebt **keinen** Anspruch auf GoBD-Konformität, DATEV-Export oder steuerrechtliche Bewertung. Die Klassifizierung der Umsätze (Erlöse, Aufwendungen, Vorsteuer, etc.) obliegt der Buchhaltung bzw. der Steuerberatung. Die Extension ersetzt keine Buchhaltungssoftware.

Wer regulatorische Anforderungen an Aufzeichnungspflichten erfüllen muss, sollte die ausgelesenen Daten gemeinsam mit einer Fachperson (Steuerberatung oder Buchhaltungsfachkraft) prüfen und in eine geeignete Buchhaltungs-Lösung übernehmen.

---

## Inbetriebnahme bei bestehendem v0.1.0 API-Key

Wer bereits einen API-Key aus `v0.1.0` verwendet, braucht für `v0.2.0` einen neuen Schlüssel mit zusätzlichen Scopes. Grund: das Finance-API (Auszahlungen, Gebühren, Salden) erfordert die zusätzliche Berechtigung `READ:FINANCE`, die in `v0.1.0`-Schlüsseln nicht gesetzt war. Ohne den neuen Scope schlägt die Aktualisierung mit einem Anmelde-Fehler fehl.

So geht's:

1. **Neuen Key erzeugen** unter <https://my.zettle.com/apps/api-keys?scopes=READ:PURCHASE+READ:FINANCE>. Beide Scopes — `READ:PURCHASE` **und** `READ:FINANCE` — müssen aktiviert sein.
2. Den neuen JWT-Key kopieren (Zettle zeigt ihn nur einmal an).
3. In MoneyMoney unter **Konten → PayPal POS → entfernen** das bestehende Konto löschen.
4. **Konto hinzufügen → PayPal POS** wählen, den neuen Key einfügen — das Konto erscheint mit allen `v0.2.0`-Funktionen.

Der alte Key kann anschließend in der Zettle-Verwaltung deaktiviert werden.

---

## Bekannte Grenzen

Folgende Verhaltensweisen sind bewusst akzeptiert. Sie sind in [ADR-0004](docs/adr/0004-finance-api-scope-and-fee-fallback.md) dokumentiert und werden mit einer späteren Version ggf. überarbeitet.

- **Verzögerte Buchung von Auszahlungen.** Bei Händlern mit wöchentlichem oder monatlichem Auszahlungsrhythmus werden Verkäufe ein bis zwei Aktualisierungsläufe lang als „nicht gebucht" angezeigt, bis die zugehörige Auszahlung im Finance-API sichtbar ist. Der Verkauf erscheint ab dem ersten Aktualisierungslauf — nur das Wertstellungsdatum und der Status `booked` ändern sich später.
- **Tagesaggregat von Gebühren — Sonderfall „nachgereichte Verknüpfung".** Falls Zettle die Zuordnung einer Einzelgebühr zur Original-Kartenzahlung erst zwischen zwei Aktualisierungsläufen nachreicht, kann es vorkommen, dass die Extension den Tag im ersten Aktualisierungslauf als „PayPal POS Transaktionsgebühren — Detail-Verknüpfung nicht verfügbar" aggregiert bucht und im zweiten Aktualisierungslauf dann zusätzlich die Einzelgebühr als eigene Buchung anlegt. Die Aggregat-Buchung des ersten Aktualisierungslaufs bleibt in MoneyMoney bestehen — Gebühr und Aggregat decken denselben Tag doppelt ab. Sobald das auftritt, einfach die Aggregat-Buchung manuell in MoneyMoney löschen; die Einzel-Buchungen sind dann die richtige, bleibende Sicht.
- **Mehrere Händler-Konten parallel.** Das Verbinden mehrerer PayPal-POS-Accounts in einem MoneyMoney-Profil ist als zukünftige Erweiterung geplant, in `v0.2.0` aber noch nicht offiziell freigegeben.

---

## Warum diese Extension

Einzelunternehmer und kleine Händler in Deutschland nutzen **PayPal POS** für Kartenzahlungen am Tresen. MoneyMoney unterstützt von Haus aus keine PayPal-POS-Konten — Kartenumsätze tauchen erst sichtbar auf, wenn PayPal die Auszahlung auf das Geschäftskonto bucht. Damit sind Einzel-Umsätze, Trinkgelder, Rückerstattungen, USt-Aufteilung und Gebühren in MoneyMoney nicht abbildbar — Buchhaltung passiert daneben in Excel.

Diese Extension schließt die Lücke: API-Key einmal eintragen, ab dann erscheinen alle Kartenumsätze, Rückerstattungen, Gebühren und Auszahlungen automatisch in MoneyMoney — mit USt- und Trinkgeld-Transparenz, geeignet als Beleg-Grundlage für die Buchhaltung.

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

1. Aktuelles Release von der [Releases-Seite](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases) herunterladen: `paypal-pos.lua` und `paypal-pos.lua.sha256`.
2. SHA256-Prüfsumme verifizieren und ggf. die signierte Tag-Quelle prüfen — siehe [Verifikation signierter Releases](#verifikation-signierter-releases).
3. Mit den vier Schritten aus dem Abschnitt [Inoffizielle Extensions erlauben](#inoffizielle-extensions-erlauben) die Extension in den richtigen Ordner kopieren und den Schalter aktivieren.
4. **Konto hinzufügen → PayPal POS** wählen, den API-Key einfügen, fertig.

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

# SHA256 prüfen (paypal-pos.lua.sha256 enthält die Soll-Summe)
shasum -a 256 -c paypal-pos.lua.sha256

# Signiertes Tag prüfen (nach `git clone` des Repositories)
git verify-tag v1.0.0
```

Eine erfolgreiche `git verify-tag`-Prüfung meldet `Good signature from "Yves Vogl <yves@kadenz.live>"` und bestätigt, dass der Tag — und damit der gebaute Release-Artifact — seit der Signatur nicht verändert wurde. Die Release-Pipeline (`.github/workflows/release.yml`) wiederholt diese Prüfung serverseitig, bevor sie ein Artifact veröffentlicht: ein unsigniertes oder fremd-signiertes Tag bricht den Workflow ab.

> Hinweis: MoneyMoney selbst kennt eine separate RSA-Signatur, die nur der MoneyMoney-Hersteller vergeben kann. Diese Extension läuft daher initial als „Inoffizielle Extension". GPG-Signatur am Tag, reproduzierbarer Build und SHA256-Sidecar bilden die unabhängige Vertrauenskette dieser Veröffentlichung.

---

## Datenschutz & Sicherheit

- **Keine Telemetrie.** Die Extension sendet ausschließlich Anfragen an offizielle PayPal-/Zettle-API-Hosts (`oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`).
- **Keine Drittparteien.** Kein Analytics, kein externes Logging.
- **API-Keys** werden ausschließlich über MoneyMoneys eingebaute Anmelde-Daten-Verwaltung gespeichert — nie geloggt, nie in Fehlertexten ausgegeben.
- **Read-Only.** Die Extension liest nur — sie führt keinerlei schreibende Operationen auf dem PayPal-POS-Konto durch.

---

## Unterstützen

Wer diese Extension nützlich findet und die Weiterentwicklung unterstützen möchte: [GitHub Sponsors → @yves-vogl](https://github.com/sponsors/yves-vogl). Sponsoring ist freiwillig und ändert nichts am Funktionsumfang oder am Open-Source-Status — die Extension bleibt MIT-lizenziert und kostenlos.

---

## Beitragen

Beiträge sind willkommen — egal ob Bug-Report, Test-Fixture aus einem ungewöhnlichen Sale-Setup oder Pull Request.

- **Fehler oder Vorschlag** → [Issues](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues)
- **Fragen, Ideen, Erfahrungsaustausch** → [Discussions](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/discussions)
- **Code-Beiträge** → siehe [CONTRIBUTING.md](CONTRIBUTING.md) für den Entwicklungs-Loop, Test-Konventionen und den Release-Prozess. Pull Requests gehen gegen `main`; signierte Commits sind Pflicht.

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
