# Sicherheits-Policy / Security Policy

> 🇩🇪 Primärsprache: Deutsch · 🇬🇧 English follows below

---

## Unterstützte Versionen

Diese Extension befindet sich in der Pre-Release-Phase. Sicherheits-Fixes werden ausschließlich gegen den `main`-Branch entwickelt und mit der nächsten regulären Veröffentlichung freigegeben. Es existiert noch kein veröffentlichtes Release.

| Version | Unterstützt |
|---------|-------------|
| `main` (Pre-Release) | ✅ |
| keine Release-Tags vorhanden | n/a |

## Ausgehende Verbindungen / Egress

Die Extension stellt Verbindungen ausschließlich zu folgenden Hosts her:

- `oauth.zettle.com` — OAuth-Token-Exchange
- `purchase.izettle.com` — Karten-Umsätze
- `finance.izettle.com` — Gebühren, Auszahlungen, Salden
- `api.github.com` — **optional**: Update-Check (max. 1× pro 24h, prüft den `releases/latest`-Endpoint des Public-Repos). Kann pro Konto über das zweite Credential-Feld „Update-Check" mit Wert `aus` / `off` / `false` / `0` deaktiviert werden.

Es werden keine Identifikatoren übertragen, kein API-Key, keine Konto- oder Transaktionsdaten — der Update-Check liest ausschließlich öffentliche Repo-Metadaten (`tag_name` des neuesten Releases) ohne Authentifizierung.

Ein CI-Gate (`.github/workflows/ci.yml` Egress-Allowlist) erzwingt diese vier Hosts auf jedem Release-Build.

## Eine Sicherheitslücke melden

Bitte **nicht** über öffentliche Issues melden, solange die Lücke nicht behoben und ein Patch-Release publiziert ist.

**Bevorzugter Kanal:** GitHub Private Vulnerability Reporting unter
[github.com/yves-vogl/moneymoney-paypal-pos-extension/security/advisories/new](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/security/advisories/new)

**Alternativ per signierter E-Mail:** an `yves.vogl@mac.com`, verschlüsselt mit dem öffentlichen GPG-Schlüssel des Maintainers:

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

## Lieferketten-Kontrollen

Diese Extension folgt einer formalen Supply-chain-Härtungspolitik, die mit
Phase 6.1 etabliert wurde. Die aktiven Kontrollen sind:

| Kontrolle | Umsetzung | Referenz |
|-----------|-----------|----------|
| GitHub-Actions auf Commit-SHA gepinnt | Jede `uses:`-Referenz in `.github/workflows/*.yml` trägt eine 40-Zeichen-SHA + `# vX.Y.Z`-Kommentar; Dependabot bumpt SHA + Kommentar im Lockstep. | SEC-06 |
| Workflow-Token least-privilege | Alle Workflows haben Top-Level `permissions: read-all`; Schreibrechte sind Job-lokal und minimal. | SEC-07 |
| Semgrep SAST blockierend | `p/security-audit` + `p/secrets` laufen auf jedem Push und PR; ERROR-Findings brechen den Workflow; SARIF wird ins Code-Scanning hochgeladen. | SEC-08 |
| Branch protection auf `main` | PR-Pflicht, signierte Commits, lineare History, force-push + delete blockiert, kein Admin-Bypass; required status checks: 5 (Lint+tests+reproducible build, gitleaks secret scan, Commit-message lint, Scorecard analysis, Semgrep SAST). | SEC-05 |
| Scorecard nightly + Branch-Protection-Introspection | `ossf/scorecard-action` läuft wöchentlich; `SCORECARD_READ_TOKEN` (Fine-grained PAT, `Administration:read` only, Rotation ≤ 1 Jahr) ermöglicht die Branch-Protection-Lesung. | SEC-05 |
| Gitleaks secret scan | Läuft auf jedem PR; `.gitleaks.toml` + `.gitleaksignore` definieren die Detection + per-Fingerprint-Allowlist auditierter Falschmeldungen. | CI-05 |
| Signed releases | GPG-signierter Git-Tag (`v[0-9]+.[0-9]+.[0-9]+`) löst die Release-Pipeline aus; `verify-signed-tag`-Job prüft die Signatur gegen den Maintainer-Fingerprint `FDE07046A6178E89ADB57FD3DE300C53D8E18642`. | BUILD-04 |
| Reproducible build | `lua tools/build.lua --verify` baut deterministisch byte-identisch; CI failt bei Diff. | BUILD-02 |
| Redact-before-log | Jede `print()`-Ausgabe läuft durch `M_log.*`-Redaktor, der JWT- und Bearer-Substrings entfernt (D-79-Gate). | SEC-01 |
| Egress-Allowlist | Im gebauten Artefakt sind nur Hosts `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com` referenzierbar; CI-Grep blockiert sonstige Hostnamen. | SEC-04 |

Diese Posture ist gegenüber der OpenSSF Scorecard messbar; siehe
[ADR-0009](docs/adr/0009-openssf-scorecard-stance.md) für den bewussten
Trade-off-Diskurs (akzeptierte Lücken, alternative Optionen, upstream-timed
Verbesserungen) und das CII Best Practices Badge (Passing-Tier) im README.

### `SCORECARD_READ_TOKEN`-Rotation

Der Fine-grained PAT wird mit 1-Jahres-Ablauf erstellt. Vor Ablauf:

1. Neuer PAT mit identischem Scope erzeugen (`Administration:read` only).
2. `gh secret set SCORECARD_READ_TOKEN --repo yves-vogl/moneymoney-paypal-pos-extension`.
3. Alten PAT in den GitHub-Settings revoken.
4. `gh workflow run "OpenSSF Scorecard"` zur Verifikation triggern.

---

## English

This extension is in a pre-release state. Security fixes are developed against `main` and shipped with the next regular release.

**Reporting a vulnerability — preferred:** GitHub Private Vulnerability Reporting at
[github.com/yves-vogl/moneymoney-paypal-pos-extension/security/advisories/new](https://github.com/yves-vogl/moneymoney-paypal-pos-extension/security/advisories/new)

**Alternative:** PGP-encrypted email to `yves.vogl@mac.com`. Maintainer key fingerprint:
`FDE07046 A617 8E89 ADB5 7FD3 DE30 0C53 D8E1 8642` (available on keys.openpgp.org).

Please include affected files / commit SHA, minimal reproduction, expected vs. observed behaviour, security impact (CIA triad), and — if known — a suggested fix or mitigation. Acknowledgement within 72 hours; first substantive assessment within 7 days; fix-release timeline depends on severity. Responsible disclosures are credited in the fix-release CHANGELOG with the reporter's consent.

Out of scope: MoneyMoney-itself vulnerabilities (please contact MoneyMoney support directly), PayPal/Zettle API vulnerabilities (please use the PayPal bug-bounty program), and user-side configuration mistakes.

## Supply-chain controls

This extension follows a formal supply-chain hardening policy established
in Phase 6.1. Active controls:

| Control | Implementation | Reference |
|---------|----------------|-----------|
| Pinned GitHub Actions | Every `uses:` reference in `.github/workflows/*.yml` carries a 40-char SHA + `# vX.Y.Z` comment; Dependabot bumps SHA + comment in lockstep. | SEC-06 |
| Least-privilege workflow tokens | All workflows declare top-level `permissions: read-all`; write scopes are job-local and minimal. | SEC-07 |
| Blocking Semgrep SAST | `p/security-audit` + `p/secrets` run on every push and PR; ERROR findings fail the workflow; SARIF uploaded to code-scanning. | SEC-08 |
| Branch protection on `main` | PR required, signed commits, linear history, force-push + delete blocked, no admin bypass; 5 required status checks. | SEC-05 |
| Scorecard nightly + Branch-Protection introspection | `ossf/scorecard-action` runs weekly; `SCORECARD_READ_TOKEN` (fine-grained PAT, `Administration:read` only, rotation ≤ 1 year) enables Branch-Protection reads. | SEC-05 |
| Gitleaks secret scan | Runs on every PR; `.gitleaks.toml` + `.gitleaksignore` define detection + per-fingerprint allowlist of audited false positives. | CI-05 |
| Signed releases | GPG-signed git tag (`v[0-9]+.[0-9]+.[0-9]+`) triggers the release pipeline; `verify-signed-tag` asserts the maintainer fingerprint `FDE07046A6178E89ADB57FD3DE300C53D8E18642`. | BUILD-04 |
| Reproducible build | `lua tools/build.lua --verify` builds byte-identically; CI fails on diff. | BUILD-02 |
| Redact-before-log | Every `print()` output flows through the `M_log.*` redactor stripping JWT and Bearer substrings (D-79 gate). | SEC-01 |
| Egress allowlist | The built artifact may reference only the hosts `oauth.zettle.com`, `purchase.izettle.com`, `finance.izettle.com`; a CI grep blocks any other hostname. | SEC-04 |

The posture is measurable against the OpenSSF Scorecard; see
[ADR-0009](docs/adr/0009-openssf-scorecard-stance.md) for the deliberate
trade-off discussion (accepted gaps, alternative options, upstream-timed
improvements) and the CII Best Practices Passing-tier badge in the README.

### `SCORECARD_READ_TOKEN` rotation

The fine-grained PAT is created with a 1-year expiry. Before expiry:

1. Generate new PAT with identical scope (`Administration:read` only).
2. `gh secret set SCORECARD_READ_TOKEN --repo yves-vogl/moneymoney-paypal-pos-extension`.
3. Revoke the old PAT in GitHub settings.
4. Trigger `gh workflow run "OpenSSF Scorecard"` to verify.
