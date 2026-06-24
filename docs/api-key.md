# API-Key erzeugen

Die Extension authentifiziert sich gegen PayPal POS / Zettle per JWT-Bearer-Assertion. Dafür brauchst Du einen API-Key mit zwei Berechtigungen:

- `READ:PURCHASE` — Karten-Umsätze und Refunds lesen
- `READ:FINANCE` — Gebühren, Auszahlungen und Salden lesen

## Schritt für Schritt

1. Öffne <https://my.zettle.com/apps/api-keys> in Deinem Zettle-Geschäfts-Account.

2. Erzeuge einen neuen API-Key. Aktiviere dabei **beide** Scopes:
   - `READ:PURCHASE`
   - `READ:FINANCE`

3. Kopiere den angezeigten JWT-Key. **Zettle zeigt ihn nur einmal an** — wenn Du das Fenster schließt, ohne ihn zu kopieren, musst Du einen neuen erzeugen.

4. Wechsle zurück zu MoneyMoney, wähle **Konto hinzufügen → PayPal POS** und füge den Key in das Feld **API-Key** ein.

   > Das zweite Feld **„Update-Check"** kannst Du leer lassen — dann prüft die Extension einmal pro Tag, ob ein neueres Release verfügbar ist. Wenn Du das nicht möchtest, trage `aus` ein.

## Sicherheit

- Der Key wird ausschließlich in MoneyMoneys eingebauter Anmelde-Daten-Verwaltung gespeichert.
- Er erscheint nie in Logs oder Fehlertexten.
- Die Extension liest nur — sie führt keinerlei schreibende Operationen auf Deinem PayPal-POS-Konto durch.

## Key zurückziehen

Falls Du den Key nicht mehr verwenden willst, kannst Du ihn jederzeit auf <https://my.zettle.com/apps/api-keys> deaktivieren. Danach das MoneyMoney-Konto entfernen und ggf. mit einem neuen Key neu hinzufügen.
