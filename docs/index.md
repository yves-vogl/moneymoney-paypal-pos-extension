# MoneyMoney PayPal POS Extension

Diese Extension ergänzt **MoneyMoney** um **PayPal POS** (ehemals Zettle) als unterstützten Kontotyp. Du siehst Deine Karten-Umsätze, Refunds, Gebühren und Auszahlungen direkt in MoneyMoney — mit USt- und Trinkgeld-Transparenz, geeignet als Beleg-Grundlage für die Buchhaltung.

## In drei Schritten

1. **[Installation](installation.md)** — Download, „Inoffizielle Extensions erlauben", Datei in den Extensions-Ordner.
2. **[API-Key erzeugen](api-key.md)** — neuer Zettle-API-Key mit Scopes `READ:PURCHASE` + `READ:FINANCE`.
3. **[Häufige Fragen](faq.md)** — Bekannte Grenzen, Datenschutz, Inoffizielle vs. offizielle Extension.

## Was Du am Ende siehst

- Karten-Umsätze als einzelne Buchungen mit Kartentyp und Zahlungsart
- Refunds als separate Buchungen mit Verweis auf den Original-Beleg
- Trinkgelder und USt-Aufschlüsselung im Verwendungszweck
- Gebühren pro Karten-Zahlung
- Auszahlungen (Payouts) als eigene Buchungen
- Beglichener und offener Saldo getrennt

## Voraussetzungen

- **MoneyMoney** in aktueller oder vorletzter Stable-Version
- Ein **PayPal POS / Zettle** Geschäftskonto in Deutschland
- macOS

## Aktueller Stand

Die Extension ist in der **Release-Candidate-Phase** für `v1.0.0`. Aktuelle Releases:
<https://github.com/yves-vogl/moneymoney-paypal-pos-extension/releases>
