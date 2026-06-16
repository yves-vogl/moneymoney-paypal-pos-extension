# Outreach Plan — v0.1.0 Launch

> **Status:** Planning only. **Do not post anything from this document before `v0.1.0` is released.** Outreach to external communities requires a working, installable artifact.

## Scope

This document drafts the announcement copy and target communities for the first public release. It is a checklist for the maintainer, not a script to be executed automatically.

## Pre-Launch Checklist

Before posting anywhere, all of these must be true:

- [ ] `v0.1.0` tag exists on `main`, GPG-signed.
- [ ] GitHub Release page has `Extension.lua` + `Extension.lua.sha256` + `Extension.lua.asc` attached.
- [ ] README's "Installation" section is verified end-to-end on a fresh MoneyMoney install by at least one tester other than the maintainer.
- [ ] At least one real merchant has run a full refresh against a live PayPal POS account and confirmed sales, refunds, fees, and a payout appear correctly.
- [ ] GitHub Discussions is enabled on the repo with at least one welcome topic pinned.
- [ ] CHANGELOG `[v0.1.0]` section is filled with the actual changes (not the `[Unreleased]` placeholder).

If any of the above is missing, the release is not ready for outreach.

## Target Communities

### 1. MoneyMoney Forum — Primary

- **URL:** https://moneymoney-app.com/forum/ (verify before posting — host has historically also been reachable as `forum.moneymoney.app`)
- **Why:** This is the canonical home for community extensions. Most MoneyMoney power users read it. The maintainer of MoneyMoney occasionally engages here too.
- **Subforum:** Extensions / Erweiterungen (Deutsch).
- **Thread title (DE):**
  > Neue Extension: PayPal POS (Zettle) — Karten-Umsätze, Refunds, Gebühren & Auszahlungen direkt in MoneyMoney
- **Posting body (DE, draft):**

  > Hallo zusammen,
  >
  > für alle, die PayPal POS (vormals Zettle) für Karten-Zahlungen nutzen und sich über die Datenlücke in MoneyMoney geärgert haben: ich habe eine Community-Extension veröffentlicht, die Sales, Refunds, Trinkgelder, Gebühren und Auszahlungen direkt synchronisiert.
  >
  > **Repo:** https://github.com/yves-vogl/moneymoney-paypal-pos-extension
  > **Release:** v0.1.0 (GPG-signiert, SHA256 verifizierbar)
  > **Lizenz:** MIT, kostenlos, keine Telemetrie
  >
  > Setup ist einmaliges Einfügen eines PayPal-POS-API-Keys. Anschließend taucht das Konto in MoneyMoney wie jedes andere auf — mit USt-Aufteilung und Trinkgeld im Verwendungszweck, sodass es als Beleg-Grundlage taugt.
  >
  > Feedback, Bug-Reports und Test-Fixtures aus ungewöhnlichen Sale-Setups (Mixed-VAT, Refunds-of-Refunds, Cash-Register-Receipts) sind sehr willkommen — gerne als Issue oder in den Discussions.

- **Posting cadence:** Single thread, monitor for 7 days, respond actively, then update only on minor/major releases.

### 2. r/Finanzen — Secondary (German)

- **URL:** https://www.reddit.com/r/Finanzen/
- **Why:** Larger reach than the MM forum, but more general — needs framing for the average self-employed reader, not the MM power user.
- **Caveat:** r/Finanzen subreddit rules forbid promotional posts. Frame as a "shared a free tool I built for my own bookkeeping" — link in a comment to a relevant thread (e.g. someone asking how to track Zettle/SumUp card revenue) rather than starting a new thread cold. Honest, helpful, low-key.
- **Decision:** Skip cold posting. Only respond to existing threads where the topic genuinely fits.

### 3. r/de — Skip

- Too broad, off-topic for the subreddit's focus.

### 4. Hacker News — Skip for v0.1.0

- **Why skip:** "Show HN" thrives on novel technical claims and English-speaking audience. A German-market accounting extension for a single macOS app is too niche to land well, and a flop on HN burns the only first-impression slot the project gets there. Revisit at `v1.0.0` if the project gains broader applicability (e.g. multi-merchant support, English UI, more PSPs).

### 5. Accounting / Bookkeeping Communities — Tertiary

- **finanzbuchhalter.de / SteuerberaterCommunities:** Skip — these audiences don't typically pick their own software. Indirect via tax-advisor recommendations is a v1.x play.
- **DATEV-related forums:** Skip for v0.1.0 — Extension does not produce DATEV-export, scope mismatch.
- **macOS Indie / Setapp-style newsletters:** Skip unless they reach out.

### 6. Personal Channels (Maintainer)

- **GitHub profile:** Pin the repo, add to profile README "Currently building" section.
- **LinkedIn / Mastodon:** Optional — only if the maintainer normally posts there. A single, factual launch post is appropriate; avoid follow-up spam.

## Tone Guidelines

- **Factual, not promotional.** Lead with the problem solved, not adjectives.
- **No "Generated with AI" markers, no Claude attribution.** Standard repo rule.
- **German for German-speaking communities, English nowhere except `developer.zettle.com` references.**
- **Be honest about pre-`v1.0` status.** Pre-1.0 means "expect rough edges, please file issues" — set expectations correctly.

## What This Plan Does NOT Cover

- Paid advertising — out of scope.
- Press releases — out of scope.
- Influencer / YouTuber outreach — out of scope.
- Forum-account creation — the maintainer must use their own established accounts; sock puppets and brand-new accounts are spam signals.

## Post-Launch Review

After 30 days from `v0.1.0` post on the MoneyMoney forum:

- Issues opened — count, types (bugs vs feature requests).
- Stars and forks delta.
- Outbound: did a tax advisor or accounting community pick the project up organically?

If signal is strong, plan a follow-up post for `v0.2.0`. If signal is weak, root-cause: discoverability, value-prop framing, or actual product gaps — then decide whether to broaden scope or stay deep on the existing audience.
