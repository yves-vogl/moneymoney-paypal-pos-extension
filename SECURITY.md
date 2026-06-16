# Sicherheits-Policy / Security Policy

> 🇩🇪 Primärsprache: Deutsch · 🇬🇧 English follows below

---

## Unterstützte Versionen

Diese Extension befindet sich in der Pre-Release-Phase. Sicherheits-Fixes werden ausschließlich gegen den `main`-Branch entwickelt und mit der nächsten regulären Veröffentlichung freigegeben. Es existiert noch kein veröffentlichtes Release.

| Version | Unterstützt |
|---------|-------------|
| `main` (Pre-Release) | ✅ |
| keine Release-Tags vorhanden | n/a |

## Eine Sicherheitslücke melden

Bitte **nicht** über öffentliche Issues melden, solange die Lücke nicht behoben und ein Patch-Release publiziert ist.

**Bevorzugter Kanal:** GitHub Private Vulnerability Reporting unter
[github.com/yves-vogl/moneymoney-paypal-pos-extension/security/advisories/new](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/security/advisories/new)

**Alternativ per signierter E-Mail:** an `yves@kadenz.live`, verschlüsselt mit dem öffentlichen GPG-Schlüssel des Maintainers:

```
Fingerprint: FDE07046 A617 8E89 ADB5 7FD3 DE30 0C53 D8E1 8642
Key-Server : keys.openpgp.org
```

## Was bitte mitsenden

- Betroffene Datei(en) und Commit-SHA, gegen den der Befund gilt
- Reproduktionsschritte (so minimal wie möglich)
- Erwartetes Verhalten vs. beobachtetes Verhalten
- Sicherheits-Impact (Vertraulichkeit / Integrität / Verfügbarkeit) und realistisches Angreifer-Modell
- Falls bekannt: Vorschlag für Mitigation oder Fix

## Reaktionszeit-Erwartung

| Schritt | Zielzeit |
|---------|----------|
| Bestätigung des Eingangs | innerhalb 72 h |
| Erste inhaltliche Einschätzung | innerhalb 7 Tagen |
| Fix-Release | abhängig von Schwere; kritische Lücken werden priorisiert |

Wer eine Lücke verantwortungsvoll meldet, wird im Release-Changelog des Fix-Releases benannt (sofern gewünscht).

## Out of Scope

Folgendes ist **kein** Sicherheitsproblem dieser Extension:

- Schwachstellen in MoneyMoney selbst → bitte direkt an `support@moneymoney.app`
- Schwachstellen in der PayPal-/Zettle-API → bitte über das PayPal Bug-Bounty-Programm
- Probleme mit lokal generierten API-Keys auf der MoneyMoney-Nutzer-Seite
- Selbst gewählte Konfigurationsfehler (z. B. ungeschützte Backups der MoneyMoney-Datenbank)

---

## English

This extension is in a pre-release state. Security fixes are developed against `main` and shipped with the next regular release.

**Reporting a vulnerability — preferred:** GitHub Private Vulnerability Reporting at
[github.com/yves-vogl/moneymoney-paypal-pos-extension/security/advisories/new](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/security/advisories/new)

**Alternative:** PGP-encrypted email to `yves@kadenz.live`. Maintainer key fingerprint:
`FDE07046 A617 8E89 ADB5 7FD3 DE30 0C53 D8E1 8642` (available on keys.openpgp.org).

Please include affected files / commit SHA, minimal reproduction, expected vs. observed behaviour, security impact (CIA triad), and — if known — a suggested fix or mitigation. Acknowledgement within 72 hours; first substantive assessment within 7 days; fix-release timeline depends on severity. Responsible disclosures are credited in the fix-release CHANGELOG with the reporter's consent.

Out of scope: MoneyMoney-itself vulnerabilities (please contact MoneyMoney support directly), PayPal/Zettle API vulnerabilities (please use the PayPal bug-bounty program), and user-side configuration mistakes.
