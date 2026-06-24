# Installation

Zur Verwendung der Extension gehst Du bitte folgendermaßen vor.

## 1. Aktuelles Release herunterladen

Öffne die [Releases-Seite](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases) und lade die `paypal-pos.lua`-Datei aus dem aktuellen Release per Klick auf **↓ Download** herunter.

Optional: Mit `paypal-pos.lua.sha256` kannst Du die Integrität prüfen via `shasum -a 256 -c paypal-pos.lua.sha256`. Mit dem signierten Tag prüfst Du die Echtheit (`git verify-tag v1.0.0`); Fingerabdruck des Maintainer-Keys: `FDE07046 A617 8E89 ADB5 7FD3 DE30 0C53 D8E1 8642`.

## 2. Extensions-Ordner in MoneyMoney öffnen

Rufe in MoneyMoney die Menüfunktion **Hilfe → Datenbank im Finder zeigen** auf.

![Menüpunkt im Hilfe-Menü von MoneyMoney](img/help-menu-extensions-folder.png)

> **Hinweis Sandbox vs Direkt-Download:** Beide MoneyMoney-Varianten (App Store und Direkt-Download von der Website) öffnen über **Datenbank im Finder zeigen** automatisch den richtigen Pfad. Eine manuelle Pfad-Eingabe ist nicht nötig.

## 3. Datei in den Extensions-Ordner kopieren

Lege die heruntergeladene `paypal-pos.lua`-Datei in das Verzeichnis **Extensions**.

## 4. Inoffizielle Extensions erlauben

Öffne in MoneyMoney **Einstellungen → Erweiterungen** und aktiviere den Schalter **„Inoffizielle Extensions erlauben"**.

![Schalter „Inoffizielle Extensions erlauben" in den MoneyMoney-Einstellungen](img/inoffizielle-extensions-erlauben.png)

> Diese Extension ist (noch) nicht im offiziellen MoneyMoney-Catalog. MoneyMoney prüft daher ihre Signatur nicht, weshalb der Schalter aktiviert sein muss. Siehe [FAQ](faq.md) für die Hintergründe.

## 5. Konto hinzufügen

Wähle in MoneyMoney **Konto hinzufügen → PayPal POS** und füge Deinen API-Key in das Feld **API-Key** ein.

Du hast noch keinen API-Key? → [API-Key erzeugen](api-key.md).

## Fertig

Beim nächsten Refresh holt MoneyMoney Deine Karten-Umsätze, Refunds, Gebühren und Auszahlungen aus PayPal POS. Beim Erstabgleich werden die letzten 90 Tage geladen; ältere Umsätze folgen über mehrere Refresh-Zyklen.

Wenn etwas nicht klappt, schau in die [Häufigen Fragen](faq.md) oder eröffne ein [Issue](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues).
