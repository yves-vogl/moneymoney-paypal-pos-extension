# MoneyMoney PayPal POS Extension

> Eine Community-Extension für [MoneyMoney](https://moneymoney.app), die PayPal POS (ehemals Zettle) als unterstützten Kontotyp ergänzt — Kartenumsätze, Rückerstattungen (Refunds), Gebühren und Auszahlungen direkt in MoneyMoney.

[![CI](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml)
[![Coverage](https://raw.githubusercontent.com/yves-vogl/moneymoney-paypal-pos-extension/coverage-badge/coverage.svg)](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/yves-vogl/moneymoney-paypal-pos-extension/badge)](https://securityscorecards.dev/viewer/?uri=github.com/yves-vogl/moneymoney-paypal-pos-extension)
[![Dokumentation](https://img.shields.io/badge/Dokumentation-online-blue?logo=mkdocs)](https://yves-vogl.github.io/moneymoney-paypal-pos-extension/)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/yves-vogl?logo=githubsponsors&logoColor=white&label=Sponsors&color=ea4aaa)](https://github.com/sponsors/yves-vogl)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Lua 5.4](https://img.shields.io/badge/Lua-5.4-blue.svg?logo=lua&logoColor=white)](https://www.lua.org/)
[![MoneyMoney](https://img.shields.io/badge/MoneyMoney-Extension-3b8dbd.svg)](https://moneymoney.app/extensions/)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://www.conventionalcommits.org)
[![GPG-signed commits](https://img.shields.io/badge/GPG-signed%20commits-success.svg)](#verifikation-signierter-releases)

📖 **Vollständige Anwender-Dokumentation:** <https://yves-vogl.github.io/moneymoney-paypal-pos-extension/>

---

## Status

**Aktuell:** Release Candidates der `v1.0.0`-Serie unter [Releases](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases). Der erste stabile Release `v1.0.0` folgt nach Live-Validierung gegen die produktive Zettle-API.

> _Hier erscheint nach `v1.0.0` ein Screenshot der Extension in MoneyMoney._

---

## Installation

Zur Verwendung der Extension gehst Du bitte folgendermaßen vor:

1. Wähle die `paypal-pos.lua`-Datei aus dem aktuellen [Release](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases) durch einen Klick auf **↓ Download** aus.

2. Rufe in MoneyMoney die Menüfunktion **Hilfe → Datenbank im Finder zeigen** auf.

   ![Menüpunkt im Hilfe-Menü von MoneyMoney](docs/img/help-menu-extensions-folder.png)

3. Lege die heruntergeladene `.lua`-Datei in das Verzeichnis **Extensions**.

4. Öffne in MoneyMoney **Einstellungen → Erweiterungen** und aktiviere den Schalter **„Inoffizielle Extensions erlauben"**.

   ![Schalter „Inoffizielle Extensions erlauben" in den MoneyMoney-Einstellungen](docs/img/inoffizielle-extensions-erlauben.png)

5. Wähle **Konto hinzufügen → PayPal POS** und füge Deinen API-Key ein.

> **Hinweis Sandbox vs Direkt-Download:** Beide MoneyMoney-Varianten (App Store und Direkt-Download) öffnen über **Hilfe → Datenbank im Finder zeigen** automatisch den richtigen Ordner. Eine manuelle Pfad-Eingabe ist nicht nötig.

---

## API-Key erzeugen

Die Extension authentifiziert sich gegen PayPal POS / Zettle per JWT-Bearer-Assertion. Du brauchst einen API-Key mit den Scopes `READ:PURCHASE` **und** `READ:FINANCE`:

1. Öffne <https://my.zettle.com/apps/api-keys> in Deinem Zettle-Geschäfts-Account.
2. Erzeuge einen neuen API-Key mit aktivierten Scopes `READ:PURCHASE` und `READ:FINANCE`.
3. Kopiere den JWT-Key (Zettle zeigt ihn nur einmal an).
4. Füge ihn in MoneyMoney bei **Konto hinzufügen → PayPal POS** in das Feld **API-Key** ein.

---

## Was die Extension liefert

- **Karten-Umsätze als einzelne Buchungen** mit Wertstellungsdatum, Kartentyp (Visa/Mastercard/Maestro/…) und Zahlungsart (kontaktlos/Chip/online) im Verwendungszweck.
- **Rückerstattungen** als separate Buchungen mit Verweis auf die Belegnummer des Original-Verkaufs.
- **Trinkgelder** und **USt-Aufschlüsselung pro Satz** im Verwendungszweck — sichtbar wenn das Unternehmen mit gemischten Sätzen arbeitet (z. B. 19 % vor Ort, 7 % zum Mitnehmen).
- **Gebühren** pro Karten-Zahlung über das Finance-API.
- **Auszahlungen (Payouts)** als separate Buchungen.
- **Beglichene und offene Salden** in einem Konto: `balance` zeigt den ausgezahlten Stand, `pendingBalance` das, was Zettle noch nicht angewiesen hat.
- **Inkrementelle Aktualisierung** — bei jedem MoneyMoney-Refresh werden nur neue Umsätze geholt.
- **Komplett deutschsprachige Oberfläche** — alle Felder, Verwendungszwecke und Fehlertexte sind auf Deutsch.

---

## Was die Extension nicht macht

Die Extension beschränkt sich auf die Darstellung der PayPal-POS-Daten in MoneyMoney. Sie nimmt explizit **keine** Bewertungen vor, die der Steuerberatung obliegen:

- Sie nimmt keine steuerrechtliche Bewertung von Umsätzen oder Trinkgeldern vor.
- Sie bestätigt keine GoBD-Konformität.
- Sie erstellt keine USt-Voranmeldung.
- Sie ersetzt den Steuerberater nicht.

Die exportierten Daten sind als Grundlage für die Buchhaltung gedacht — die Einordnung selbst bleibt in der Verantwortung der jeweiligen Fachperson.

### GoBD-Hinweis

Diese Extension liest Rohdaten aus der PayPal-POS-API und stellt sie in MoneyMoney dar. Sie erhebt **keinen** Anspruch auf GoBD-Konformität, DATEV-Export oder steuerrechtliche Bewertung. Die Klassifizierung der Umsätze (Erlöse, Aufwendungen, Vorsteuer, etc.) obliegt der Buchhaltung bzw. der Steuerberatung. Die Extension ersetzt keine Buchhaltungssoftware.

Wer regulatorische Anforderungen an Aufzeichnungspflichten erfüllen muss, sollte die ausgelesenen Daten gemeinsam mit einer Fachperson (Steuerberatung oder Buchhaltungsfachkraft) prüfen und in eine geeignete Buchhaltungs-Lösung übernehmen.

---

## Bekannte Grenzen

Folgende Verhaltensweisen sind bewusst akzeptiert. Sie sind in [ADR-0004](docs/adr/0004-finance-api-scope-and-fee-fallback.md) dokumentiert und werden mit einer späteren Version ggf. überarbeitet.

- **Verzögerte Buchung von Auszahlungen.** Bei Händlern mit wöchentlichem oder monatlichem Auszahlungsrhythmus werden Verkäufe ein bis zwei Aktualisierungsläufe lang als „nicht gebucht" angezeigt, bis die zugehörige Auszahlung im Finance-API sichtbar ist. Der Verkauf erscheint ab dem ersten Aktualisierungslauf — nur das Wertstellungsdatum und der Status `booked` ändern sich später.
- **Tagesaggregat von Gebühren — Sonderfall „nachgereichte Verknüpfung".** Falls Zettle die Zuordnung einer Einzelgebühr zur Original-Kartenzahlung erst zwischen zwei Aktualisierungsläufen nachreicht, kann es vorkommen, dass die Extension den Tag im ersten Aktualisierungslauf als „PayPal POS Transaktionsgebühren — Detail-Verknüpfung nicht verfügbar" aggregiert bucht und im zweiten Aktualisierungslauf dann zusätzlich die Einzelgebühr als eigene Buchung anlegt. Die Aggregat-Buchung des ersten Aktualisierungslaufs bleibt in MoneyMoney bestehen — Gebühr und Aggregat decken denselben Tag doppelt ab. Sobald das auftritt, einfach die Aggregat-Buchung manuell in MoneyMoney löschen; die Einzel-Buchungen sind dann die richtige, bleibende Sicht.
- **90-Tage-Klammer für den Erstabgleich.** Ältere Umsätze werden nicht sichtbar gemacht. Zettle stellt drei Jahre Historie zur Verfügung — über mehrere Refresh-Zyklen wandert die Klammer rückwärts (Multi-Cycle-First-Sync).
- **Nur EUR.** Umsätze in anderen Währungen als EUR werden übergangen.
- **Mehrere Händler-Konten parallel.** Das Verbinden mehrerer PayPal-POS-Accounts in einem MoneyMoney-Profil ist nicht offiziell freigegeben.
- **Token-Revocation.** Nach einer Token-Revocation muss der API-Key in MoneyMoney neu eingefügt werden — siehe ADR-0005.

---

## Warum diese Extension

Einzelunternehmer und kleine Händler in Deutschland nutzen **PayPal POS** für Kartenzahlungen am Tresen. MoneyMoney unterstützt von Haus aus keine PayPal-POS-Konten — Kartenumsätze tauchen erst sichtbar auf, wenn PayPal die Auszahlung auf das Geschäftskonto bucht. Damit sind Einzel-Umsätze, Trinkgelder, Rückerstattungen, USt-Aufteilung und Gebühren in MoneyMoney nicht abbildbar — Buchhaltung passiert daneben in Excel.

Diese Extension schließt die Lücke: API-Key einmal eintragen, ab dann erscheinen alle Kartenumsätze, Rückerstattungen, Gebühren und Auszahlungen automatisch in MoneyMoney — mit USt- und Trinkgeld-Transparenz, geeignet als Beleg-Grundlage für die Buchhaltung.

---

## Voraussetzungen

- **MoneyMoney** in aktueller oder vorletzter Stable-Version
- Ein **PayPal POS / Zettle** Geschäftskonto in Deutschland
- Ein vom Händler erstellter **API-Key** (JWT) — siehe [API-Key erzeugen](#api-key-erzeugen)
- macOS — MoneyMoney läuft ausschließlich auf macOS

---

## Verifikation signierter Releases

Alle Tags und Release-Assets dieses Repos werden mit dem GPG-Schlüssel des Maintainers signiert:

```
Fingerprint: FDE07046 A617 8E89 ADB5 7FD3 DE30 0C53 D8E1 8642
Maintainer:  Yves Vogl <yves.vogl@mac.com>
```

So prüfst Du ein Release:

```bash
# Public Key vom Keyserver importieren
gpg --keyserver keys.openpgp.org --recv-keys FDE07046A6178E89ADB57FD3DE300C53D8E18642

# SHA256 prüfen (paypal-pos.lua.sha256 enthält die Soll-Summe)
shasum -a 256 -c paypal-pos.lua.sha256

# Signiertes Tag prüfen (nach `git clone` des Repositories)
git verify-tag v1.0.0
```

Eine erfolgreiche `git verify-tag`-Prüfung meldet `Good signature from "Yves Vogl <yves.vogl@mac.com>"` und bestätigt, dass der Tag — und damit der gebaute Release-Artifact — seit der Signatur nicht verändert wurde. Die Release-Pipeline (`.github/workflows/release.yml`) wiederholt diese Prüfung serverseitig, bevor sie ein Artifact veröffentlicht: ein unsigniertes oder fremd-signiertes Tag bricht den Workflow ab.

> Hinweis: MoneyMoney selbst kennt eine separate Signaturprüfung für Extensions (deaktivierbar über den „Inoffizielle Extensions erlauben"-Schalter). Solange diese Extension nicht in den offiziellen MoneyMoney-Catalog aufgenommen ist, läuft sie als „Inoffizielle Extension". GPG-Signatur am Tag, reproduzierbarer Build und SHA256-Sidecar bilden die unabhängige Vertrauenskette dieser Veröffentlichung.

---

## Datenschutz & Sicherheit

- **Keine Telemetrie.** Die Extension sendet ausschließlich Anfragen an offizielle PayPal-/Zettle-API-Hosts (`oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`).
- **Keine Drittparteien.** Kein Analytics, kein externes Logging.
- **API-Keys** werden ausschließlich über MoneyMoneys eingebaute Anmelde-Daten-Verwaltung gespeichert — nie geloggt, nie in Fehlertexten ausgegeben.
- **Read-Only.** Die Extension liest nur — sie führt keinerlei schreibende Operationen auf dem PayPal-POS-Konto durch.

Weitere Details in [SECURITY.md](SECURITY.md) und den ADRs unter [docs/adr/](docs/adr/).

---

## Anwender-Dokumentation

Die vollständige Dokumentation — Architektur, ADRs, Changelog, Mitwirken — ist als Material-Design-Site auf GitHub Pages veröffentlicht:

📖 <https://yves-vogl.github.io/moneymoney-paypal-pos-extension/>

---

## Unterstützen

Wenn Du diese Extension nützlich findest und die Weiterentwicklung unterstützen möchtest: [GitHub Sponsors → @yves-vogl](https://github.com/sponsors/yves-vogl). Sponsoring ist freiwillig und ändert nichts am Funktionsumfang oder am Open-Source-Status — die Extension bleibt MIT-lizenziert und kostenlos.

---

## Beitragen

Beiträge sind willkommen — egal ob Bug-Report, Test-Fixture aus einem ungewöhnlichen Sale-Setup oder Pull Request.

- **Fehler oder Vorschlag** → [Issues](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues)
- **Fragen, Ideen, Erfahrungsaustausch** → [Discussions](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/discussions)
- **Code-Beiträge** → siehe [CONTRIBUTING.md](CONTRIBUTING.md) für den Entwicklungs-Loop, Test-Konventionen und den Release-Prozess. Pull Requests gehen gegen `main`; signierte Commits sind Pflicht.

Alle Commits und Tags in diesem Repo sind GPG-signiert. Branch Protection erzwingt linear history und signed commits.

---

## Lizenz

[MIT](LICENSE) — frei nutzbar, modifizierbar und weitergebbar. Keine Garantie, keine Haftung.

---

## Disclaimer

Dies ist ein **inoffizielles Community-Projekt**. Weder **MoneyMoney GmbH** noch **PayPal / Zettle** sind Herausgeber, Sponsor oder verantwortlich für diese Extension. Alle genannten Markennamen sind Eigentum ihrer jeweiligen Inhaber.
