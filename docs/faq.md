# Häufige Fragen

Die ausführliche FAQ mit allen bekannten Grenzen, Datenschutz-Erläuterungen und Inoffizielle-vs-offizielle-Extension-Hintergrund pflege ich als pinned Discussion-Thread im Repo:

📌 [**FAQ — Häufige Fragen, bekannte Grenzen, Sicherheit**](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/discussions/25)

So bleibt der Inhalt diskutierbar, durchsuchbar und Du kannst direkt antworten oder eigene Fragen stellen.

## Wenn Du eine Frage hast

- **Allgemeine Frage / Erfahrungs-Austausch** → [Q&A-Discussions](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/discussions/categories/q-a)
- **Bug-Report** → [Issues](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/issues)
- **Sicherheitsschwachstelle (privat)** → [Private Vulnerability Reporting](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/security/advisories/new) (siehe auch [SECURITY.md](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/blob/main/SECURITY.md) im Repo)

## Kurzform der wichtigsten Punkte

- **Keine Telemetrie**, keine Drittparteien. Nur die offiziellen Zettle-API-Hosts.
- **API-Keys** liegen ausschließlich in MoneyMoneys Anmelde-Daten-Verwaltung.
- **Read-Only** — keine schreibenden Operationen.
- **Keine GoBD-Konformität** zugesichert. Die Extension liefert Rohdaten; die buchhalterische Bewertung obliegt der Steuerberatung.
- **Inoffizielle Extension** — der Schalter „Inoffizielle Extensions erlauben" muss in MoneyMoney aktiviert sein. Tags + Releases sind GPG-signiert (Maintainer-Fingerabdruck `FDE07046 A617 8E89 ADB5 7FD3 DE30 0C53 D8E1 8642`).

Die volle Erklärung steht im verlinkten Discussion-Thread oben.
