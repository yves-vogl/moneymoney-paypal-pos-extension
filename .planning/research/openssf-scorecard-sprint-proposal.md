# OpenSSF Scorecard Sprint — Proposal

**Drafted:** 2026-06-17 (autonom durch Claude auf Bitte von Yves)
**Status:** Vorschlag (nicht implementiert)
**Source:** https://api.securityscorecards.dev/projects/github.com/yves-vogl/moneymoney-paypal-pos-extension
**Score snapshot:** 5.2 / 10 (Scorecard v5.0.0, gemessen 2026-06-16 auf `c644f16`)

---

## TL;DR

Heutiger Aggregatscore **5.2 / 10** lässt sich realistisch auf **8.5 – 9.2 / 10** anheben — ohne Fuzzing zu erzwingen. Sechs Checks lassen sich mit kleinen PRs (≤ 1 h Arbeit pro Check) lösen, zwei sind strukturelle Entscheidungen, einer (`Maintained`) heilt sich nach 90 Tagen Repo-Alter automatisch. Zwei Items (`Fuzzing`, `Code-Review`) sind für ein Solo-Lua-Projekt nicht ohne Kompromisse erreichbar — Empfehlung: bewusst akzeptieren, im README begründen.

Empfehlung: **eigenständige „Phase 6.5: Supply-chain & Scorecard hardening"** zwischen Phase 6 (Release & Polish) und v1.0.0-Release. Drei Items, die ohnehin in Phase 6 gehören (Signed-Releases, Pinned-Dependencies, Token-Permissions), bleiben dort und werden dem neuen Sprint nicht doppelt zugeordnet.

---

## Score-Aufschlüsselung (Stand 2026-06-16)

| Check                    | Score | Status              | Aktion                                                                                      |
|--------------------------|-------|---------------------|---------------------------------------------------------------------------------------------|
| Binary-Artifacts         | 10    | ✅ pass             | —                                                                                           |
| Branch-Protection        | -1    | ⚠️ unreadable        | **PAT mit `Administration:read` + `SCORECARD_READ_TOKEN`-Secret**                            |
| CI-Tests                 | 10    | ✅ pass             | —                                                                                           |
| CII-Best-Practices       | 0     | ❌ fixable           | **OpenSSF Best Practices Badge (silver) beantragen**                                         |
| Code-Review              | 0     | ⚠️ structural        | Bot-Reviewer ODER Branch-Protection mit Self-Approval-Workaround ODER bewusst akzeptieren    |
| Contributors             | 6     | 🟢 partial           | Zweiter Hauptmaintainer/Org würde auf 10 heben — strukturell, nicht erzwingbar               |
| Dangerous-Workflow       | 10    | ✅ pass             | —                                                                                           |
| Dependency-Update-Tool   | 10    | ✅ pass             | —                                                                                           |
| Fuzzing                  | 0     | ❌ unattraktiv       | Empfehlung: **bewusst akzeptieren** (Lua-Wrapper, kein Parser/Codec ⇒ Fuzzing wenig sinnvoll) |
| License                  | 10    | ✅ pass             | —                                                                                           |
| Maintained               | 0     | ⏰ heilt sich         | Repo-Alter < 90 Tage; ab ca. 2026-09-01 automatisch ≥ 8                                       |
| Packaging                | -1    | ❎ N/A               | Lua-Script, kein Package-Registry-Distributionsweg                                            |
| Pinned-Dependencies      | 0     | ❌ fixable           | **Alle GitHub-Actions auf Commit-SHA pinnen (StepSecurity-PR)**                              |
| SAST                     | 0     | ❌ fixable           | **Semgrep-Workflow + Community-Lua-Ruleset** (CodeQL hat keinen Lua-Support)                |
| Security-Policy          | 10    | ✅ pass             | —                                                                                           |
| Signed-Releases          | -1    | ⏳ Phase 6           | GPG-signed Tag + Sigstore/cosign auf Release-Artefakt (gehört in Phase 6)                   |
| Token-Permissions        | 0     | ❌ fixable           | **`ci.yml` Top-Level auf `read-all`; Badge-Push in eigenen Job mit `contents:write`**       |
| Vulnerabilities          | 10    | ✅ pass             | —                                                                                           |

**Aggregatberechnung:** Scorecard zählt N/A-Checks (`-1`) nicht in den Durchschnitt; aktuell gehen 15 Checks ein, Summe = 78 / 150 → 5.2.

**Realistisches Ziel nach Sprint:** 8 fixable Items auf 10 heben (+ Maintained zeitversetzt) ⇒ Aggregat ≈ 8.5 – 9.0.

---

## Vorgeschlagener Sprint: Phase 6.5 — Supply-chain & Scorecard hardening

> Dieser Sprint ist als eigenständige Phase zwischen Phase 6 (Release & Polish) und dem v1.0.0-Tag gedacht. Begründung: Drei Items (Signed-Releases, Pinned-Dependencies, Token-Permissions) hängen am Release-Pfad und müssen vor dem ersten Release stehen; ohne dass Phase 6 dadurch aufgebläht wird, isoliert ein eigener Sprint die Scorecard-Arbeit als ein Block.

**Goal:** OpenSSF Scorecard-Aggregat ≥ 8.5 / 10 auf `main` HEAD. SECURITY.md, README, ADRs spiegeln die getroffenen Härtungsmaßnahmen.

**Mode:** mvp (jeder Plan ist eine Vertical-Slice „PR landet → Scorecard re-runt → Score steigt um X").

**Depends on:** Phase 6 (Release-Pipeline existiert; ohne den Release-Workflow lassen sich Signed-Releases nicht messen).

### Plan-Aufschlüsselung (vorgeschlagen)

#### Plan 6.5-01 — Pinned-Dependencies → 10/10

| Eigenschaft   | Wert                                                                                                            |
|---------------|-----------------------------------------------------------------------------------------------------------------|
| Effort        | ~30 min                                                                                                         |
| Impact        | +0.7 Aggregatpunkte                                                                                             |
| Files         | `.github/workflows/ci.yml`, `.github/workflows/scorecard.yml`, `.github/workflows/release.yml` (wenn vorhanden) |
| Aktion        | Jede `uses:`-Action auf Commit-SHA pinnen, Versions-Kommentar dahinter                                          |
| Tool          | `pin-github-action` CLI ODER manuell via StepSecurity-Generator (https://app.stepsecurity.io)                   |
| Dependabot    | `.github/dependabot.yml` erweitern: `package-ecosystem: github-actions` mit `groups` und SHA-Pinning            |
| Acceptance    | `grep -E '@(v[0-9]+\.[0-9]+\.[0-9]+\|main)$' .github/workflows/*.yml` liefert keine Treffer                      |

Beispiel der Umstellung:

```yaml
# vorher
- uses: actions/checkout@v4

# nachher
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
```

Concrete to-pin list (aus heutigem CI-State):
- `actions/checkout@v4` (verwendet in `ci.yml:21`, `scorecard.yml:33`)
- `leafo/gh-actions-lua@v13` (`ci.yml:26`)
- `leafo/gh-actions-luarocks@v6.1.0` (`ci.yml:31`)
- `ossf/scorecard-action@v2.4.0` (`scorecard.yml:38`)
- `actions/upload-artifact@v4` (`scorecard.yml:48`)
- `github/codeql-action/upload-sarif@v3` (`scorecard.yml:55`)

#### Plan 6.5-02 — Token-Permissions → 10/10

| Eigenschaft | Wert                                                                                              |
|-------------|---------------------------------------------------------------------------------------------------|
| Effort      | ~45 min                                                                                            |
| Impact      | +0.7                                                                                              |
| Files       | `.github/workflows/ci.yml`                                                                         |
| Aktion      | Top-Level auf `permissions: read-all`; Badge-Push-Step in einen separaten Job verschieben mit explizitem `permissions: { contents: write }` und `if: github.event_name == 'push' && github.ref == 'refs/heads/main'` |
| Risk        | Coverage-Badge-Branch muss noch beschreibbar bleiben — Test in Feature-Branch, dann auf main mergen |

Vorgeschlagene Job-Aufteilung:

```yaml
permissions: read-all  # neues Top-Level

jobs:
  test:
    permissions:
      contents: read   # nur lesen
    # ... bestehendes Setup ...

  badge:
    needs: test
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    permissions:
      contents: write  # nur dieser Job darf den Badge-Branch pushen
    # ... Badge-Generierung + Push ...
```

#### Plan 6.5-03 — Branch-Protection → -1 → 10/10

| Eigenschaft | Wert                                                                                                                                                 |
|-------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| Effort      | ~60 min (Token erstellen, Secret hinterlegen, Branch-Rules anpassen)                                                                                  |
| Impact      | +0.6                                                                                                                                                  |
| Files       | `.github/workflows/scorecard.yml`, Repo-Settings (off-repo)                                                                                            |
| Aktion 1    | Fine-grained PAT für *yves-vogl/moneymoney-paypal-pos-extension* mit Scope **Administration: Read-only**, gespeichert als Repo-Secret `SCORECARD_READ_TOKEN` |
| Aktion 2    | `scorecard.yml` → `with.repo_token: ${{ secrets.SCORECARD_READ_TOKEN }}`                                                                              |
| Aktion 3    | Branch-Protection auf `main` aktivieren: require PR, require status checks (CI + Scorecard), require signed commits, restrict force-pushes, restrict deletions, require linear history |
| Acceptance  | Nach nächstem Scorecard-Lauf liefert die API `Branch-Protection.score ≥ 8`                                                                            |

#### Plan 6.5-04 — SAST → 10/10

| Eigenschaft | Wert                                                                                                       |
|-------------|------------------------------------------------------------------------------------------------------------|
| Effort      | ~90 min                                                                                                     |
| Impact      | +0.7                                                                                                       |
| Files       | `.github/workflows/sast.yml` (neu), `.semgrep.yml` (neu)                                                    |
| Aktion 1    | Semgrep-Workflow auf jeden Push und PR; Ergebnisse als SARIF zu code-scanning hochladen                    |
| Aktion 2    | Ruleset: `p/security-audit` (generisch) + `p/secrets` (key/token-Patterns). Lua-spezifische Rules via Community-Repo verlinken |
| Caveat      | CodeQL unterstützt Lua nicht ⇒ Semgrep ist der einzige Scorecard-anerkannte SAST-Pfad für dieses Stack    |
| Acceptance  | Scorecard erkennt SAST-Tool auf den letzten ≥ 25 Commits                                                   |

Workflow-Skelett (zur PR-Diskussion):

```yaml
name: SAST
on: [push, pull_request]
permissions: read-all
jobs:
  semgrep:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      actions: read
      contents: read
    container: returntocorp/semgrep
    steps:
      - uses: actions/checkout@<sha> # v4.x
      - run: semgrep ci --sarif --output=semgrep.sarif
      - uses: github/codeql-action/upload-sarif@<sha>
        with:
          sarif_file: semgrep.sarif
```

#### Plan 6.5-05 — CII Best Practices Badge → 5/10 (passing) → 7/10 (silver) → 10/10 (gold)

| Eigenschaft | Wert                                                                                                                  |
|-------------|-----------------------------------------------------------------------------------------------------------------------|
| Effort      | passing: ~2 h Fragebogen; silver: weitere ~3 h; gold: nur sinnvoll wenn Projekt > 1 Maintainer                       |
| Impact      | +0.3 (passing) bis +0.7 (gold)                                                                                       |
| Aktion      | Registrierung bei https://bestpractices.coreinfrastructure.org; Self-Assessment-Fragebogen ausfüllen                  |
| Acceptance  | Badge-URL in README; Scorecard erkennt automatisch den Badge-Level                                                    |
| Empfehlung  | Bis **silver** gehen — gold verlangt zwei unabhängige Maintainer und macht für ein Solo-Projekt keinen Sinn          |

Inhaltliche Themen, die der Fragebogen abfragt (sind alle bereits abgedeckt):
- License (MIT ✓)
- Documented build (`tools/build.lua` ✓)
- Public CI (✓)
- Crypto-Best-Practices (TLS only, kein eigenes Crypto ✓)
- Vulnerability disclosure (`SECURITY.md` ✓)
- Static analysis (kommt mit Plan 6.5-04)
- Signed releases (kommt mit Phase 6)

#### Plan 6.5-06 — Signed-Releases → -1 → 10/10 *(gehört in Phase 6, hier nur als Erinnerung)*

| Eigenschaft | Wert                                                                                          |
|-------------|-----------------------------------------------------------------------------------------------|
| Effort      | ~60 min (im Rahmen Phase 6 Release-Pipeline)                                                  |
| Impact      | +0.6 (wirkt erst nach erstem Release)                                                         |
| Aktion 1    | GPG-signed Git-Tag (`git tag -s vX.Y.Z`)                                                       |
| Aktion 2    | Sigstore/cosign auf Release-Artefakt (`cosign sign-blob dist/paypal-pos.lua`)                 |
| Aktion 3    | Provenance via SLSA-GitHub-Generator (Level 3)                                                 |
| Verzicht    | Plan **bewusst in Phase 6 belassen**, nicht hier doppeln                                       |

#### Plan 6.5-07 — Documentation & rationale

| Eigenschaft | Wert                                                                                                                          |
|-------------|-------------------------------------------------------------------------------------------------------------------------------|
| Effort      | ~30 min                                                                                                                        |
| Impact      | 0 Punkte direkt, aber: macht die bewusst akzeptierten Lücken (Fuzzing, solo Code-Review) für externe Beobachter:innen lesbar |
| Files       | `SECURITY.md`, `README.md`, `docs/adr/0004-openssf-scorecard-stance.md` (neu)                                                  |
| Aktion      | ADR-0004 dokumentiert: warum kein Fuzzing (Lua-Wrapper, kein Parser/Codec, OSS-Fuzz overkill); warum Solo-Code-Review (Single-Maintainer); welche Mitigations stattdessen greifen (SAST, reproducible build, TLS-only, redact-before-log, egress-allowlist) |

---

## Bewusst akzeptierte Lücken

### Fuzzing — bleibt auf 0/10

**Begründung:** Phase-2-Code ist ein dünner Wrapper um eine vertrauenswürdige HTTPS-API. Es gibt keinen Parser, keinen Decoder, kein eigenes Wireformat. OSS-Fuzz/ClusterFuzzLite gibt erfahrungsgemäß **keine** zusätzlichen Bugs in solchen Codebases. Kosten/Nutzen: setup ~6 h, laufende Wartung, kaum Findings.

**Mitigation:** Property-based-Tests via busted-Helper für die zwei nicht-trivialen Decoder (`_b64url_decode`, `_extract_client_id`) — sind ohnehin geplant in Plan 02-03.

### Code-Review — bleibt bei 0/10 solange Solo-Maintainer

**Begründung:** Scorecard zählt approved-by-different-user-Reviews. Bei Solo-Maintainer-Projekten ist dieser Score strukturell nicht erreichbar, ohne das Repo zu kapern (z. B. Bot-Reviewer wie CodeRabbit, der approven kann — Scorecard akzeptiert das, aber es ist ein Workaround, kein echtes Code-Review).

**Optionen, falls trotzdem auf 10/10:**
1. CodeRabbit / Greptile / Diamond als „autonomer Reviewer" einsetzen (kommerziell, ca. $20–50/Monat).
2. Branch-Protection so konfigurieren, dass jeder PR durch einen Bot-Auto-Approver durchlaufen muss — fragwürdig, kein echter Sicherheitsgewinn.
3. Bewusst akzeptieren, Begründung in `SECURITY.md`.

**Empfehlung:** Option 3, bis das Projekt einen Co-Maintainer findet. Score-Impact: -2 absolut (von 10 möglich), ~-1.0 Aggregat.

### Maintained — heilt sich (Repo < 90 Tage alt)

Ab ca. 2026-09-01 wird der Score automatisch ≥ 8 sein, sofern in jeder Kalenderwoche mindestens 1 Commit + 1 Issue/PR-Aktivität nachweisbar ist. Da der Sprint-Plan ohnehin laufende Phase-2-bis-Phase-6-Arbeit beinhaltet, ist diese Voraussetzung erfüllt.

### Packaging — strukturell N/A

`Lua`-Extension hat kein etabliertes Package-Registry-Konzept im Sinne von npm/PyPI/crates.io. Distribution erfolgt via GitHub Releases — der Scorecard-Check sucht nach LuaRocks/npm/etc. Publishing-Workflows. Empfehlung: in ADR-0004 dokumentieren.

### Contributors — strukturell limitiert

Aktuell 6/10 (zwei Contributor-Organisationen erkannt: adessoSE + adesso se — Yves' Arbeitgeber, automatisch erkannt via Git-Email). 10/10 wäre erreichbar, wenn ein zweiter externer Contributor aktiv beiträgt — nicht erzwingbar. Empfehlung: bewusst akzeptieren.

---

## Sprint-Goal-Kalibration

| Szenario                 | Score-Ziel | Sprints/Effort           |
|--------------------------|------------|--------------------------|
| **Minimal** (nur fixable) | 7.5 – 8.0  | Plan 6.5-01, -02, -04 (~3 h gesamt) |
| **Empfohlen**             | 8.5 – 9.0  | + Plan 6.5-03, -05 (passing), -07 (~6 h gesamt) |
| **Aggressiv**             | 9.0 – 9.5  | + CII silver + Bot-Reviewer (kostenpflichtig) (~10 h + Subscription) |
| **Vollständig**           | 9.5 – 10   | Nur erreichbar mit Co-Maintainer + OSS-Fuzz |

**Empfehlung:** Szenario „Empfohlen" — 8.5 – 9.0 Aggregat, ohne strukturelle Verrenkungen, ohne externe Subscriptions, in ~6 h Arbeit über 3 PRs verteilt.

---

## Vorgeschlagener nächster Schritt

Yves entscheidet nach Rückkehr:

1. **Ja, neuen Sprint** — Ich lege „Phase 6.5: Supply-chain & Scorecard hardening" via `/gsd-phase --insert 6.5` an, dann `/gsd-discuss-phase 6.5` zur Decision-Locking, dann `/gsd-plan-phase 6.5`.
2. **Nein, in Phase 6 einbauen** — ich erweitere Phase 6's CONTEXT.md um die fixable Items und schiebe nur ADR-0004 + CII-Badge in eine kleine Solo-Aktion vor.
3. **Nur ein paar Quick-Wins jetzt** — ich öffne PRs für Pinned-Deps + Token-Permissions noch heute (autonomer Quick-Sprint), Rest landet bei Phase 6.

Default (wenn keine Rückmeldung kommt): Option 1, weil sie die Scorecard-Arbeit sauber isoliert und Phase 6 fokussiert lässt.

---

## Quellen

- OpenSSF Scorecard API: https://api.securityscorecards.dev/projects/github.com/yves-vogl/moneymoney-paypal-pos-extension (gemessen 2026-06-16T22:54:06Z)
- Scorecard Check Documentation: https://github.com/ossf/scorecard/blob/ea7e27e/docs/checks.md
- Best Practices Badge: https://bestpractices.coreinfrastructure.org
- StepSecurity Workflow Generator: https://app.stepsecurity.io
- Semgrep Lua Rules (Community): https://semgrep.dev/r?lang=lua
- Sigstore/cosign: https://docs.sigstore.dev/cosign/signing/overview/
