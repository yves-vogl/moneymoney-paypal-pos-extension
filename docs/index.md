# MoneyMoney PayPal POS Extension

Eine Community-Extension für [MoneyMoney](https://moneymoney.app), die
PayPal POS (ehemals Zettle) als unterstützten Kontotyp ergänzt —
Kartenumsätze, Rückerstattungen, Gebühren und Auszahlungen direkt in
MoneyMoney.

## Schnelleinstieg

1. **[Vollständiges README](readme.md)** — Installation, API-Key-Erzeugung
   (Scopes `READ:PURCHASE` + `READ:FINANCE`), GoBD-Hinweis, Inbetriebnahme,
   Verifikation signierter Releases.
2. **[Sicherheits-Policy](security.md)** — Schwachstellen verantwortungsvoll
   melden.
3. **[Mitwirken](contributing.md)** — Setup für lokale Entwicklung, Conventional
   Commits, Test- und Coverage-Vorgaben.

## Architektur

Die Architektur-Entscheidungen sind als MADR-formatierte ADRs unter
**[Architektur (ADRs)](adr/0001-amalgamator-design.md)** dokumentiert:

- Amalgamator-Design (ADR-0001)
- LocalStorage-Token-Cache (ADR-0002)
- Sandbox-Probes (ADR-0003)
- Finance-API-Scope (ADR-0004)
- Resilience-Invarianten (ADR-0005)
- JWT-Bearer-Auth (ADR-0006)
- Kein TLS-Pinning (ADR-0007)
- String-Return-Fehlermuster (ADR-0008)
- OpenSSF-Scorecard-Stance (ADR-0009)

## Status

Diese Extension befindet sich derzeit in aktiver Entwicklung. Status,
aktuelle Funktionen und der Beitragspfad finden sich im
[Repository-README](https://github.com/yves-vogl/moneymoney-paypal-pos-extension)
sowie im [Änderungsverlauf](changelog.md).
