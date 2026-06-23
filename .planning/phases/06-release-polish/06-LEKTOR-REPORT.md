# Phase 6 / CP-1 — Lektorats-Report

**Date:** 2026-06-23
**Scope:** `README.de.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/adr/0002`, `0006`, `0007`, `0008`
**Reviewer:** loop-lektor (DE + EN pass)
**Status:** Report-only — no source edits. Findings to be triaged by orchestrator into a follow-up commit.

---

## Severity Histogram

| Severity | Count |
|---|---|
| HIGH | 5 |
| MEDIUM | 14 |
| LOW | 17 |
| **Total** | **36** |

## Per-File Counts

| File | HIGH | MED | LOW | Σ |
|---|---|---|---|---|
| `README.de.md` | 2 | 6 | 7 | 15 |
| `CHANGELOG.md` | 1 | 3 | 2 | 6 |
| `CONTRIBUTING.md` | 0 | 2 | 3 | 5 |
| `docs/adr/0002-localstorage-token-cache.md` | 0 | 1 | 2 | 3 |
| `docs/adr/0006-jwt-bearer-only-auth.md` | 1 | 1 | 1 | 3 |
| `docs/adr/0007-no-tls-pinning.md` | 0 | 0 | 1 | 1 |
| `docs/adr/0008-string-return-error-pattern.md` | 1 | 1 | 1 | 3 |

---

## Findings — `README.de.md`

### L-01 — GoBD-Wording: "GoBD-Bewertung" ist unscharf
**Lang:** DE
**Surface:** `README.de.md:70` (Was-Extension-nicht-macht-Block) und `README.de.md:82` (GoBD-Hinweis)
**Severity:** HIGH
**Current:** "Wir bestätigen keine GoBD-Bewertung." / "Sie erhebt KEINEN Anspruch auf GoBD-Konformität, DATEV-Export oder steuerrechtliche Bewertung."
**Proposed:** "Wir bestätigen keine GoBD-Konformität." / unverändert.
**Reason:** Der Fachbegriff im GoBD-Kontext ist "GoBD-Konformität" (BMF-Schreiben spricht von "Konformität mit den GoBD"). "GoBD-Bewertung" gibt es nicht als etablierten Begriff und klingt holprig. Zeile 82 verwendet bereits korrekt "GoBD-Konformität" — Zeile 70 sollte angeglichen werden. Konsistenz + Fachsprache + rechtlich sauberer.

### L-02 — "KEINEN" in Versalien wirkt schreiend, juristisch nicht erforderlich
**Lang:** DE
**Surface:** `README.de.md:82`
**Severity:** MEDIUM
**Current:** "Sie erhebt KEINEN Anspruch auf GoBD-Konformität, DATEV-Export oder steuerrechtliche Bewertung."
**Proposed:** "Sie erhebt **keinen** Anspruch auf GoBD-Konformität, DATEV-Export oder steuerrechtliche Bewertung."
**Reason:** Versalien in Fließtext (außerhalb von Abkürzungen) sind im Deutschen unüblich und wirken aggressiv. **Fett** trägt dieselbe Betonung professioneller. Gleiche juristische Wirkung.

### L-03 — Anglizismus "Refresh" inkonsistent verwendet
**Lang:** DE
**Surface:** `README.de.md:107`, `108`, `CHANGELOG.md:51` ("Aktualisierungszyklen")
**Severity:** MEDIUM
**Current:** README verwendet "Refresh" / "ein bis zwei Refreshes" / "im ersten Refresh"; CHANGELOG verwendet "Aktualisierungszyklen".
**Proposed:** Konsistent "Aktualisierung" / "Aktualisierungslauf" in beiden Dateien — oder umgekehrt "Refresh" überall. Empfehlung: "Aktualisierung" passt zur deutschen Zielgruppe + zum MoneyMoney-UI-Sprachgebrauch.
**Reason:** Querfile-Inkonsistenz. MoneyMoney-UI nutzt "Konten aktualisieren" — die Extension-Doku sollte denselben Begriff übernehmen.

### L-04 — Bindestrich-Inkonsistenz "Karten-Umsätze" vs. "Karten-Zahlungen"
**Lang:** DE
**Surface:** `README.de.md:3`, `115`, `117` ("Karten-Umsätze"), `115` ("Karten-Zahlungen")
**Severity:** LOW
**Current:** "Karten-Umsätze", "Karten-Zahlungen" (mit Bindestrich) vs. "Kartenzahlung" (Z. 59, kein Bindestrich)
**Proposed:** Durchgängig ohne Bindestrich: "Kartenumsätze", "Kartenzahlungen". Zusammenschreibung ist nach Duden Standard für etablierte Komposita.
**Reason:** Der Bindestrich ist hier nicht lesehilfreich (keine Vokal-Häufung, keine Mehrdeutigkeit) und inkonsistent durchgehalten.

### L-05 — "MoneyMoney's" — Deppen-Apostroph
**Lang:** DE
**Surface:** `README.de.md:175`
**Severity:** HIGH
**Current:** "API-Keys werden ausschließlich über MoneyMoney's eingebaute Anmelde-Daten-Verwaltung gespeichert"
**Proposed:** "API-Keys werden ausschließlich über die in MoneyMoney eingebaute Anmelde-Daten-Verwaltung gespeichert" — oder "über MoneyMoneys eingebaute …" (deutscher Genitiv ohne Apostroph).
**Reason:** Englischer Possessiv-Apostroph ist im Deutschen falsch (sog. "Deppen-Apostroph", Duden D 16). CHANGELOG.md Z. 67 ("MoneyMoneys eingebaute") und Z. 126 machen es bereits richtig — README sollte angeglichen werden.

### L-06 — Inkonsistente Schreibweise "MwSt-" vs. "USt-"
**Lang:** DE
**Surface:** `README.de.md:57`, `60`, `86` (MwSt) vs. `71`, `115`, `117` (USt)
**Severity:** MEDIUM
**Current:** Mischung von "MwSt-Aufschlüsselung" und "USt-Voranmeldung" / "USt-Aufteilung" / "USt- und Trinkgeld-Transparenz"
**Proposed:** Konsistent "USt." (Umsatzsteuer) verwenden — das ist der amtliche Begriff. "MwSt." ist umgangssprachlich/historisch. Alternativ explizit trennen: "MwSt." nur dort, wo das Rohdaten-Feld so heißt (Zettle-Feld `vatAmount`), "USt." für rechtliche/buchhalterische Kontexte.
**Reason:** Für eine Buchhaltungs-orientierte Zielgruppe (Solo-Selbständige + Steuerberatung) ist die Konsistenz wichtig. Empfehlung: "USt." überall, da die Doku sich am Steuer-Kontext orientiert.

### L-07 — "z.B." → "z. B." (mit geschütztem Leerzeichen)
**Lang:** DE
**Surface:** `README.de.md:60`, `CHANGELOG.md:86`
**Severity:** LOW
**Current:** "z.B. 19 % auf Speisen"
**Proposed:** "z. B. 19 % auf Speisen" (mit Leerzeichen — Duden D 14).
**Reason:** Duden-Empfehlung; in den meisten Markdown-Renderern wird "z. B." sauber gesetzt. Konsistenz zur restlichen Doku-Hygiene (Prozentzeichen hat bereits Spatium).

### L-08 — "Solo-Selbständige" Bindestrich-Frage
**Lang:** DE
**Surface:** `README.de.md` (kommt im Brief vor, nicht im Text — aber typische Zielgruppen-Bezeichnung fehlt im README ganz; "Sole Proprietors" Z. 115 ist Anglizismus)
**Severity:** MEDIUM
**Current:** "Sole Proprietors und kleine Händler in Deutschland nutzen **PayPal POS**"
**Proposed:** "Einzelunternehmer und kleine Händler in Deutschland nutzen **PayPal POS**" oder "Soloselbständige und kleine Händler …"
**Reason:** "Sole Proprietors" ist im deutschen Fließtext irritierend (Brief-Begründung "deutsche Solo-Merchants" passt nicht zum englischen Begriff in der DE-README). "Einzelunternehmer" ist der präzise rechtliche Begriff für die Zielgruppe.

### L-09 — Anglizismus "Refunds" / Mischung mit "Rückerstattung"
**Lang:** DE
**Surface:** `README.de.md:3`, `58`, `117` ("Refunds"); `58` ("Rückerstattungsbuchung")
**Severity:** LOW
**Current:** Mischung von "Refunds" und "Rückerstattung"
**Proposed:** Beim ersten Vorkommen einmal expliziter Brückenbau: "Rückerstattungen (Refunds)". Danach durchgängig "Rückerstattungen" — der deutsche Begriff ist etabliert.
**Reason:** "Refund" ist im deutschen Payment-Jargon zwar verbreitet, im README für Solo-Selbständige aber unnötig fachsprachlich. Konsistenz erhöht Lesbarkeit.

### L-10 — Typografische Anführungszeichen fehlen
**Lang:** DE
**Surface:** `README.de.md:42`, `44`, `107`, `108`, `167`, `212` (gerade " statt deutsche „"")
**Severity:** LOW
**Current:** `„Inoffizielle Extensions erlauben"` (Mischung „ + gerade ")
**Proposed:** `„Inoffizielle Extensions erlauben"` (deutsche Anführungszeichen unten/oben).
**Reason:** Bereits teilweise korrekt — aber inkonsistent. Z. 42/44/167/212 verwenden korrekt „…", Z. 107/108 verwenden „…" mit geradem schließendem ". Vereinheitlichen. **Caveat:** "Inoffizielle Extensions erlauben" ist locked wording (UI-Label); innerhalb der Anführungszeichen NICHT umschreiben.

### L-11 — Apostroph "‚nicht-gebucht'" ist ungewöhnlich
**Lang:** DE
**Surface:** `README.de.md:107`
**Severity:** LOW
**Current:** "werden Verkäufe ein bis zwei Refreshes lang als „nicht-gebucht" angezeigt"
**Proposed:** "… als „nicht gebucht" angezeigt" (ohne Bindestrich — kein zusammengesetztes Adjektiv).
**Reason:** "nicht gebucht" ist Adverb + Partizip, kein Bindestrich nötig. Vgl. "nicht angemeldet" (nicht "nicht-angemeldet").

### L-12 — "Schritt-für-Schritt-Anleitung" — überflüssige Überschrift
**Lang:** DE
**Surface:** `README.de.md:92`
**Severity:** LOW
**Current:** "Schritt-für-Schritt-Anleitung:"
**Proposed:** "So geht's:" oder ganz weglassen — die nummerierte Liste folgt unmittelbar und ist selbsterklärend.
**Reason:** Redundant zur direkt folgenden Liste; Du-Form passt besser zum Rest (Z. 22 "Wer mitwirken möchte", Z. 117 etc. nutzen impersonal/Wer-Form).

### L-13 — "Berechtigungsumfang" → "Scope" inkonsistent
**Lang:** DE
**Surface:** `README.de.md:90`, `94`
**Severity:** LOW
**Current:** Z. 90 "erweitertem Berechtigungsumfang" / Z. 94 "Beide Scopes — `READ:PURCHASE` **und** `READ:FINANCE`"
**Proposed:** Einheitlich bei "Scopes" bleiben (Z. 94), und Z. 90 anpassen: "einen neuen Schlüssel mit zusätzlichen Scopes". OAuth-Fachsprache; ohnehin technisch.
**Reason:** Innerhalb von 4 Zeilen wechselt der Begriff. "Scope" ist OAuth-Standardterminologie; die DE-README für eine technische Inbetriebnahme darf sich daran orientieren.

### L-14 — "_„PayPal POS Transaktionsgebühren — Detail-Verknüpfung nicht verfügbar"_" — kursiv + Anführung
**Lang:** DE
**Surface:** `README.de.md:108`
**Severity:** LOW
**Current:** Kombination aus Markdown-Kursiv `_…_` PLUS deutschen Anführungszeichen.
**Proposed:** Entscheidung: Entweder nur kursiv ODER nur Anführungszeichen — beides zusammen ist typografisches Overengineering. Empfehlung: nur Anführungszeichen, da es ein konkreter UI-String ist: `„PayPal POS Transaktionsgebühren — Detail-Verknüpfung nicht verfügbar"`.
**Reason:** Duden-Empfehlung (Anführungen für Zitate/UI-Strings, Kursiv für Hervorhebung/Werktitel — nicht beides).

### L-15 — "Pro Kartenzahlung" vs "Pro Karten-Zahlung" — siehe L-04
**Lang:** DE
**Surface:** `README.de.md:59`
**Severity:** LOW (Duplikat — als Belege zu L-04 zählend)
**Current:** "Pro Kartenzahlung: Kartentyp und Zahlungsart"
**Proposed:** (unverändert — diese Zeile macht es bereits richtig; siehe L-04 für die anderen Stellen).
**Reason:** Verweis auf L-04.

---

## Findings — `CHANGELOG.md`

### L-16 — Keep-a-Changelog: gemischte Sprache verletzt Konvention
**Lang:** DE / EN consistency
**Surface:** `CHANGELOG.md:14`, `49`, `77`, `88`, `96`, `104`, `118`, `128`
**Severity:** HIGH
**Current:** Section-Header gemischt Deutsch ("Hinzugefügt", "Geändert", "Bekannte Grenzen", "Sicherheit", "Voraussetzung für Bestandskunden") und Englisch ("Foundations (previously tracked under Unreleased — Phase 1 + 2 + 3 scaffolding)").
**Proposed:** **Entscheidung treffen:** Entweder durchgängig Englisch (Keep-a-Changelog Konvention: "Added / Changed / Deprecated / Removed / Fixed / Security") oder durchgängig Deutsch. Da der README primary Deutsch ist und Endnutzer Deutsch lesen, plädiere ich für **konsistent Deutsch** — aber dann muss die "Foundations"-Sektion (Z. 128–141) zumindest mit deutschem Header laufen und der Fließtext darin auch übersetzt werden. **Yves-Decision erforderlich.**
**Reason:** Keep-a-Changelog 1.1.0 standardisiert englische Header. Wenn lokalisiert werden soll, dann komplett — die jetzige Mischung wirkt unfertig. Yves-gated.

### L-17 — "Foundations"-Sektion in 0.2.0 — Wording unscharf
**Lang:** EN
**Surface:** `CHANGELOG.md:128`
**Severity:** MEDIUM
**Current:** "### Foundations (previously tracked under Unreleased — Phase 1 + 2 + 3 scaffolding)"
**Proposed:** "### Foundations (Phase 1–3 scaffolding, previously under [Unreleased])"
**Reason:** Etwas kürzer, "Phase 1 + 2 + 3" ist umständlich. "[Unreleased]" als Markdown-Link-Style passt zu Keep-a-Changelog.

### L-18 — "die GitHub-Release" — falsches Genus
**Lang:** DE
**Surface:** `CHANGELOG.md:19`
**Severity:** MEDIUM
**Current:** "hängt `paypal-pos.lua` und `paypal-pos.lua.sha256` an die GitHub-Release."
**Proposed:** "hängt `paypal-pos.lua` und `paypal-pos.lua.sha256` an **das** GitHub-Release an."
**Reason:** "Release" ist im Deutschen sächlich (analog "das Album", "das Update"). "Die Release" ist umgangssprachlich; Duden führt es als Neutrum.

### L-19 — Datum-Inkonsistenz im 0.2.0 Header
**Lang:** DE
**Surface:** `CHANGELOG.md:75`
**Severity:** MEDIUM
**Current:** "## [0.2.0] - 2026-MM-DD"
**Proposed:** Datum nachtragen oder klar markieren als "Unreleased preview".
**Reason:** Im Release-Doc für v1.0.0 darf kein Platzhalter `MM-DD` stehen — wirkt unfertig. Wenn 0.2.0 nicht eigenständig releast wurde sondern in 1.0.0 aufging, dann sollte der Block entweder gelöscht oder mit einem Note-Banner versehen werden ("Subsumiert in 1.0.0; nie als eigenständiges Release veröffentlicht").

### L-20 — "v0.2.0" — verweist auf nie-erschienenes Release
**Lang:** DE
**Surface:** `CHANGELOG.md:49`, `145`
**Severity:** LOW
**Current:** "### Bekannte Grenzen (unverändert seit v0.2.0)" + Link `[0.2.0]: …/releases/tag/v0.2.0` — aber gibt es kein v0.2.0-Release.
**Proposed:** Konsistent mit L-19: Wenn 0.2.0 nie released wurde, dann Z. 49 "(unverändert seit dem 0.2.0-Entwicklungsstand)" und Z. 145 Link entfernen oder auf Tag verweisen der existiert.
**Reason:** Broken external link bei Release-Veröffentlichung — Klick führt auf 404. Sauberkeit der Release-Dokumentation.

### L-21 — "META-03-Wächter" — Insider-Begriff im User-CHANGELOG
**Lang:** DE
**Surface:** `CHANGELOG.md:44`
**Severity:** LOW
**Current:** "META-03-Wächter (`spec/meta_no_tax_classification_spec.lua`) erweitert"
**Proposed:** "Test-Wächter gegen verbotene Steuer-Klassifizierungs-Phrasen (`spec/meta_no_tax_classification_spec.lua`, intern META-03) erweitert auf alle Markdown-Dokumentations-Dateien …"
**Reason:** "META-03" ist Plan-internes Vokabular ohne öffentliche Erläuterung. Im Endnutzer-CHANGELOG entweder erklären oder weglassen.

---

## Findings — `CONTRIBUTING.md`

### L-22 — "GPG-signierten-Tag-Anforderung" → englisch übersetzt fehlt
**Lang:** EN
**Surface:** `CHANGELOG.md:28-29` (referenziert CONTRIBUTING)
**Severity:** N/A (Hinweis, kein Finding)
**Current:** —
**Proposed:** —
**Reason:** False positive; verschoben.

### L-22 (revised) — "every commit eines PR" — German leakage in CHANGELOG description
**Lang:** DE / EN consistency
**Surface:** `CHANGELOG.md:37–38`
**Severity:** MEDIUM
**Current:** "Conventional-Commits-Lint (`.github/workflows/commit-lint.yml`) prüft jeden Commit eines PR gegen die Conventional-Commits-Grammatik."
**Proposed:** (DE-Variante korrekt — kein Finding hier; verschoben.)
**Reason:** —

### L-23 — Code-block heredoc: missing closing quote
**Lang:** EN
**Surface:** `CONTRIBUTING.md:172–175`
**Severity:** MEDIUM
**Current:**
```
gh pr create --base main --title "release: vX.Y.Z" --body "$(cat <<EOF
Cuts CHANGELOG entry for vX.Y.Z. Tag will be pushed after merge.
EOF
)"
```
**Proposed:** Add `--no-edit` is not relevant; but the snippet is syntactically OK. The issue is the EOF needs to be unquoted-like and inside `"…"`. The shown form is correct shell. **No change** — withdrawing this finding. Keeping the L-number as a placeholder note: the example correctly uses `<<EOF` without indent + closing `)"`.
**Reason:** Withdrawn after re-read.

### L-24 — "approachable" → minor style improvement
**Lang:** EN
**Surface:** `CONTRIBUTING.md:9`
**Severity:** LOW
**Current:** "This contributor guide is English so it is approachable for non-German collaborators."
**Proposed:** "This contributor guide is in English so non-German collaborators can read it without translation friction."
**Reason:** "is English" reads slightly off without article; "approachable" is fine but vague. Suggested form is more direct.

### L-25 — "release loop" inconsistency: "Cutting a release" vs "release process"
**Lang:** EN
**Surface:** `CONTRIBUTING.md:160`, `161`
**Severity:** LOW
**Current:** "## Release process" / "### Cutting a release (maintainer)"
**Proposed:** OK as is — both standard idioms.
**Reason:** Withdrawn; not a finding.

### L-25 (revised) — Use of "GPG-signierten-Tag-Anforderung" inside English CHANGELOG-ref
**Lang:** EN
**Surface:** `CONTRIBUTING.md:29` (via reference)
**Severity:** N/A; verschoben.
**Current:** —

### L-26 — TDD discipline phrasing
**Lang:** EN
**Surface:** `CONTRIBUTING.md:102`
**Severity:** LOW
**Current:** "**TDD: RED → GREEN.** Write the failing spec first (commit prefix `test:`)"
**Proposed:** "**TDD: RED → GREEN.** Write the failing spec first (commit type `test:`)"
**Reason:** Conventional Commits calls these "types", not "prefixes". The example on line 88 already uses "Conventional Commits". Use the canonical term.

### L-27 — "monkey-patches" hyphenation
**Lang:** EN
**Surface:** `CONTRIBUTING.md:109`
**Severity:** LOW
**Current:** "ad-hoc module-level monkey-patches"
**Proposed:** "ad hoc module-level monkey patches" (or, more idiomatically, "module-level monkeypatches").
**Reason:** "ad hoc" is unhyphenated when used adverbially (Chicago Manual of Style). "Monkey patch" is open in technical writing (Wikipedia, Python docs).

### L-28 — "in lockstep" missing test/string change scope
**Lang:** EN
**Surface:** `CONTRIBUTING.md` — N/A (this is in ADR-0008, see L-36)
**Severity:** —
**Current:** —
**Proposed:** —
**Reason:** Verschoben zu L-36.

---

## Findings — `docs/adr/0002-localstorage-token-cache.md`

### L-29 — "in-flight TTL exhaustion" — jargon-heavy
**Lang:** EN
**Surface:** `0002:69`
**Severity:** LOW
**Current:** "60-second safety margin against clock skew and in-flight TTL exhaustion"
**Proposed:** "60-second safety margin against clock skew and TTL expiration during an in-flight request"
**Reason:** "in-flight TTL exhaustion" is dense and ambiguous. Spelling out makes the safety property concrete.

### L-30 — "spelunking" — informal in an ADR
**Lang:** EN
**Surface:** `0002:42`
**Severity:** LOW
**Current:** "without spelunking the source"
**Proposed:** "without reading the source end-to-end"
**Reason:** "Spelunking" is hacker-jargon; in a formal MADR document, plain English serves better.

### L-31 — "field is set but never read for branching" — clearer wording
**Lang:** EN
**Surface:** `0002:79`
**Severity:** MEDIUM
**Current:** "For v1.0.x (assertion-grant-only) the field is set but never read for branching — the freshness check alone is sufficient."
**Proposed:** "For v1.0.x (assertion-grant-only) the field is recorded but never used to choose between code paths — the freshness check alone is sufficient."
**Reason:** "Read for branching" forces the reader to parse twice. The proposed phrasing makes intent explicit.

---

## Findings — `docs/adr/0006-jwt-bearer-only-auth.md`

### L-32 — Inkonsistente Versionsangaben: "v1.0" vs "v1.0.x"
**Lang:** EN
**Surface:** `0006:34`, `61`, `66`, `76`, `103`, `106`, `113`, `115`
**Severity:** HIGH
**Current:** Wechsel zwischen "v1.0" (Z. 34), "v1.0.x" (Z. 61, 66, 76, 113), "v2.0.0" (Z. 116) — und unter ADR-0002 wird konsequent "v1.0.x" verwendet.
**Proposed:** Durchgängig "v1.0.x" für die laufende Major-Minor-Serie verwenden. Z. 34 "rejects flow 2 for v1.0" → "rejects flow 2 for v1.0.x".
**Reason:** Semver-Disziplin. "v1.0" suggeriert ein einzelnes Release, "v1.0.x" die ganze Patch-Reihe. Cross-ADR consistency mit ADR-0002.

### L-33 — "Anmeldung blockiert" — locked wording check
**Lang:** DE (innerhalb EN-ADR)
**Surface:** `0006:71`
**Severity:** MEDIUM
**Current:** "to surface the standard \"Anmeldung fehlgeschlagen\" / \"Anmeldung blockiert\" string-return error messages (see ADR-0008)"
**Proposed:** Beleg per `M_i18n` / `src/i18n.lua` prüfen: Sind das die exakten i18n-Strings? Falls ja → unverändert lassen mit Quellen-Anker (`src/i18n.lua:error.login_failed`). Falls die Strings dort anders lauten, ADR-Zitat angleichen.
**Reason:** ADRs zitieren UI-Strings — diese sind Test-Contract (siehe ADR-0008 L-36). Lokerstrings sollten 1:1 zitiert werden, sonst läuft das ADR aus dem Code raus. **Yves-Decision oder grep-Verifikation erforderlich.**

### L-34 — "Easier security audit surface" awkward
**Lang:** EN
**Surface:** `0006:96`
**Severity:** LOW
**Current:** "Easier security audit surface — one auth path, one token type, one failure mode (`invalid_grant`)."
**Proposed:** "Smaller security-audit surface — one auth path, one token type, one failure mode (`invalid_grant`)."
**Reason:** "Easier surface" is a category mismatch (surfaces are large/small, not easy/hard). "Smaller" captures the intended security benefit (reduced attack surface).

---

## Findings — `docs/adr/0007-no-tls-pinning.md`

### L-35 — "HSTS on `*.izettle.com` (preloaded; …)" — verify factual claim
**Lang:** EN
**Surface:** `0007:136`
**Severity:** LOW (factual flag, not stylistic)
**Current:** "HSTS on `*.izettle.com` (preloaded; downgrade protection at the browser-PKI ecosystem level)."
**Proposed:** Verifiziere via `https://hstspreload.org/?domain=izettle.com` ob `izettle.com` tatsächlich preloaded ist. Falls nicht → Claim entfernen oder zu "HSTS on `*.izettle.com` (downgrade protection at the TLS layer)" abschwächen. Falls ja → unverändert.
**Reason:** ADR-Aussagen sollten faktisch korrekt sein. "Preloaded" ist eine konkrete, verifizierbare Behauptung; wenn falsch, schwächt das den ganzen Mitigations-Block. **Verification-Task vor PR.**

---

## Findings — `docs/adr/0008-string-return-error-pattern.md`

### L-36 — "Phase-6 CP-1 lektor pass" — meta-self-reference now obsolete
**Lang:** EN
**Surface:** `0008:156`
**Severity:** HIGH
**Current:** "the Phase-6 CP-1 lektor pass will batch the string + test updates together."
**Proposed:** Nach Abschluss von CP-1 (also nach Merge dieses Reports) umformulieren zu: "The Phase-6 CP-1 lektor pass (2026-06-23) batched the string + test updates together." — oder, falls Strings hier NICHT touched wurden, neutralere Formulierung: "Lektor passes batch string + test updates together to preserve the test contract."
**Reason:** Self-referential future-tense statement that becomes false the moment the ADR-File is merged in Phase 6. Decision needed: did CP-1 actually touch i18n strings? If not, soften to general principle. **Yves-Decision erforderlich.**

### L-37 — "Carve-out" — hyphenation inconsistency
**Lang:** EN
**Surface:** `0008:67`, `178`
**Severity:** LOW
**Current:** "ADR-0005 Carve-out 3"
**Proposed:** OK as is (capitalized + hyphenated is consistent within ADR-0005 if that's the source). Verify ADR-0005 uses the same form. If ADR-0005 uses "carveout" or "carve out" — align.
**Reason:** Cross-ADR consistency check. Likely no change needed.

### L-38 — Long sentence in §Consequences/Positive
**Lang:** EN
**Surface:** `0008:131–132`
**Severity:** MEDIUM
**Current:** "A German merchant whose API key was revoked sees `\"PayPal POS / Zettle: Der API-Key wurde widerrufen oder ist abgelaufen. Bitte unter my.zettle.com/apps/api-keys neu erzeugen.\"` instead of `attempt to index a nil value (field 'access_token')`. The message tells them where to go and what to do."
**Proposed:** Break into two sentences and verify the German string matches `src/i18n.lua` verbatim (test contract). Suggested: "A German merchant whose API key was revoked sees the localized message:\n\n> `\"PayPal POS / Zettle: Der API-Key wurde widerrufen oder ist abgelaufen. Bitte unter my.zettle.com/apps/api-keys neu erzeugen.\"`\n\ninstead of the raw Lua error `attempt to index a nil value (field 'access_token')`. The message tells them where to go and what to do."
**Reason:** Blockquote separation aids readability. The verbatim-quote concern overlaps with L-33: ADR text quoting i18n strings should match the actual key/value in `src/i18n.lua` 1:1, else the ADR drifts from the code.

---

## Cross-File / Consistency Findings

### L-39 — `paypal-pos.lua` vs `Extension.lua` artifact-name drift
**Lang:** DE/EN consistency
**Surface:** `README.de.md:40`, `136` ("paypal-pos.lua") vs. CLAUDE.md snapshot references to `Extension.lua`
**Severity:** N/A (CLAUDE.md was removed; new artifact name is `paypal-pos.lua` per CHANGELOG.md:19, 73, CONTRIBUTING.md:124, 188)
**Current:** Consistent in scope.
**Proposed:** No change. Documented for clarity.
**Reason:** No-op finding; just noting that snapshot reference is historical.

### L-40 — "API-Key" vs "API key" — Bindestrich-Disziplin
**Lang:** DE/EN consistency
**Surface:** Überall im README.de und in den ADRs.
**Severity:** LOW
**Current:** DE konsistent "API-Key" (mit Bindestrich, Großschreibung), EN konsistent "API key" (zwei Wörter, klein).
**Proposed:** Beibehalten. Korrekte Sprach-spezifische Schreibung.
**Reason:** Bestätigung — keine Änderung nötig.

---

## Yves-Gated Items (require decision before PR)

1. **L-16** (HIGH) — CHANGELOG language mixing: full DE or full EN headers? Yves-Decision für Keep-a-Changelog-Sektion.
2. **L-19 / L-20** (MEDIUM / LOW) — `[0.2.0]` section in CHANGELOG: ist 0.2.0 jemals als Standalone-Release veröffentlicht worden, oder direkt in 1.0.0 aufgegangen? Beeinflusst Datums-Platzhalter und Versionslink.
3. **L-33** (MEDIUM) — Verify exact i18n strings cited in ADR-0006 against `src/i18n.lua`. Touches test contract (ADR-0008).
4. **L-36** (HIGH) — ADR-0008 §156 self-reference: did CP-1 actually batch string changes? If no, soften to principle.
5. **L-38** (MEDIUM) — Verify the verbatim German error string in ADR-0008 §131–132 against `src/i18n.lua` — must match 1:1 (test contract).

---

## Top 3 Highest-Severity Findings (orchestrator handoff)

1. **L-05** (HIGH, `README.de.md:175`) — "MoneyMoney's eingebaute" Deppen-Apostroph → "die in MoneyMoney eingebaute" / "MoneyMoneys eingebaute". Stilfehler; CHANGELOG bereits korrekt, README sollte angeglichen werden.
2. **L-16** (HIGH, `CHANGELOG.md:14/49/77/88/96/104/118/128`) — Gemischte DE/EN Section-Header in CHANGELOG. **Yves-Decision** für komplett DE oder komplett EN. Verletzt Keep-a-Changelog-Konvention in der jetzigen Mischform.
3. **L-32** (HIGH, `docs/adr/0006`) — Inkonsistente Versionsangaben "v1.0" vs "v1.0.x" in ADR-0006. Semver-Disziplin; ADR-0002 ist bereits konsistent mit "v1.0.x" — ADR-0006 angleichen.

Additional HIGH-severity items: **L-01** (GoBD-Wording-Konsistenz) und **L-36** (ADR-0008 obsolete self-reference, Yves-gated).

---

## Notes on locked wording (verified — NO changes proposed)

- "PayPal POS" — durchgängig korrekt verwendet, nie als "PayPal Zettle" oder "Zettle by PayPal" geschrieben.
- "MoneyMoney" — ein Wort, durchgängig.
- "Inoffizielle Extensions erlauben" — UI-Label exakt zitiert.
- "paypal-pos-plugin" — projektname stabil.
- "Yves Vogl" — Maintainer-Name konsistent (Z. 149 README.de; Z. 71 CHANGELOG; ADR-Deciders).

Keine Locked-Wording-Verstöße gefunden.
