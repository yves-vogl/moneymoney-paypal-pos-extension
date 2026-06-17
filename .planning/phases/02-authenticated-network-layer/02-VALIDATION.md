---
phase: 2
slug: authenticated-network-layer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-17
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from `02-RESEARCH.md §"Validation Architecture"`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | busted 2.3.0 |
| **Config file** | `.busted` (Phase-1 installed) |
| **Quick run command** | `busted spec/auth_spec.lua spec/http_spec.lua spec/errors_spec.lua` |
| **Full suite command** | `busted --coverage spec/` |
| **Estimated runtime** | quick: ~5 s · full: ~15 s |

---

## Sampling Rate

- **After every task commit:** Run `busted spec/auth_spec.lua spec/http_spec.lua spec/errors_spec.lua` + `luacheck src/ spec/`
- **After every plan wave:** Run `busted --coverage spec/`
- **Before `/gsd-verify-work`:** Full suite must be green AND coverage ≥ 85 % on `src/` (excluding `webbanking_header.lua`)
- **Max feedback latency:** 5 seconds (quick) · 15 seconds (full)
- **Phase gate:** Full suite green + coverage threshold met + maintainer-only manual install in real MoneyMoney with a real PayPal POS API key (out-of-band — not gated by CI)

---

## Per-Task Verification Map

> Filled by the planner per plan/wave. Below seeds the required REQ-ID → test mapping from RESEARCH.md; the planner extends with concrete task IDs.

| Req ID | Behavior | Test Type | Automated Command | File Exists | Status |
|--------|----------|-----------|-------------------|-------------|--------|
| AUTH-01 | InitializeSession2 first call (credentials==nil) returns the German credential challenge object | unit | `busted spec/entry_spec.lua -t "credential.api_key.label"` | ✅ (Phase-1 entry_spec covers this) | ⬜ pending |
| AUTH-02 | `M_auth.exchange_assertion` posts the exact OAuth body to `oauth.zettle.com/token` | unit | `busted spec/auth_spec.lua -t "exchange_assertion posts grant_type"` | ❌ W0 | ⬜ pending |
| AUTH-03 | InitializeSession2 with `[token_invalid_grant]` returns `LoginFailed` synchronously | unit (integration) | `busted spec/entry_spec.lua -t "invalid_grant returns LoginFailed"` | ❌ W0 | ⬜ pending |
| AUTH-04 | `M_auth.cached_token` returns nil when `now >= expires_at - 60`; returns access_token when fresh; no refresh token used | unit | `busted spec/auth_spec.lua -t "cached_token expiry"` | ❌ W0 | ⬜ pending |
| AUTH-05 | After successful auth, no LocalStorage value or captured print contains the input API key or any of its three JWT segments | unit (SEC-03 gating) | `busted spec/log_redaction_spec.lua -t "never writes the API key"` | ❌ W0 | ⬜ pending |
| AUTH-06 | Token cache populated after auth survives a `Mocks.teardown()` + re-`dofile` cycle when written to flat-key fallback path | unit | `busted spec/auth_spec.lua -t "cache survives reload via flat fallback"` | ❌ W0 | ⬜ pending |
| SEC-03 | Authentication-failure return string contains no JWT, no `Bearer`, no base64-url segment of input | unit (SEC-03 gating) | `busted spec/log_redaction_spec.lua -t "rejects an invalid_grant"` | ❌ W0 | ⬜ pending |
| ACCT-01 | ListAccounts returns one account of type `AccountTypeGiro` with currency `"EUR"` | unit | `busted spec/entry_spec.lua -t "ListAccounts returns AccountTypeGiro"` | ✅ (Phase-1 covers shape; Phase 2 extends to read from cache) | ⬜ pending |
| ACCT-02 | Account label = `"PayPal POS — " .. publicName`; fallback to `organizationUuid:sub(1,8)` when publicName empty | unit | `busted spec/entry_spec.lua -t "ListAccounts label uses publicName"` | ❌ W0 | ⬜ pending |
| ACCT-04 | Two `LocalStorage.zettle[orgUuid]` entries coexist; ListAccounts returns both | unit | `busted spec/entry_spec.lua -t "two merchants coexist"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `spec/auth_spec.lua` — stubs for AUTH-02, AUTH-04, AUTH-06
- [ ] `spec/http_spec.lua` — stubs for `M_http.post_form` / `M_http.get_json` (form encoding, Accept header, status inference)
- [ ] `spec/errors_spec.lua` — stubs for D-24 six cases
- [ ] `spec/log_redaction_spec.lua` extended with SEC-03 three gating tests (AUTH-05, SEC-03)
- [ ] `spec/entry_spec.lua` extended with auth-integration cases (AUTH-03, ACCT-02, ACCT-04)
- [ ] `spec/fixtures/auth/token_ok.json`
- [ ] `spec/fixtures/auth/token_invalid_grant.json`
- [ ] `spec/fixtures/auth/users_self_ok.json`
- [ ] `spec/fixtures/auth/users_self_unauthorized.json`
- [ ] `spec/fixtures/auth/token_rate_limited.json`
- [ ] `spec/fixtures/auth/network_timeout.json`
- [ ] `spec/helpers/mm_mocks.lua` — `Mocks.push_response` extended with `status` field; `MM.base64` / `MM.base64decode` replaced with real pure-Lua implementations (Risk R-6)
- [ ] `spec/helpers/fixtures.lua` — nested-path support (`Fixtures.load("auth/token_ok")`)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| End-to-end add-account against real `oauth.zettle.com` with a real PayPal POS API key | AUTH-01, AUTH-02, ACCT-01, ACCT-02 | Production endpoint; requires a live PayPal POS merchant account; mocking would defeat the validation | Install `dist/paypal-pos.lua` in MoneyMoney; in "Konto hinzufügen", paste real API key into the German API-Key field; account `"PayPal POS — <merchant-name>"` of type Giro appears in the sidebar within ~2 s. |
| Wrong-key fast-fail surfaces synchronously in add-account dialog | AUTH-03 | UX dialog behavior is part of MoneyMoney; not testable against the mock | Same install path; paste a corrupted API key; verify MoneyMoney shows the German `LoginFailed`-equivalent error in the add-account dialog (NOT silently later on refresh). |
| Token cache survives MoneyMoney restart | AUTH-04, AUTH-06 | `LocalStorage` cross-restart persistence is a MoneyMoney-runtime property; unit tests can only simulate | Add account successfully; quit MoneyMoney via cmd-Q; relaunch; observe `RefreshAccount` does NOT re-prompt for credentials and reuses the cached token (visible in maintainer's Protokoll panel if DEBUG enabled). |
| ADR-0003 Q2 redirect-behavior observation | R-3 (informational only) | Live network observation against `oauth.zettle.com` required | First live token exchange — capture `Connection():request` return values; record whether a redirect was followed automatically. Append observation to ADR-0003. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5 s (quick) / 15 s (full)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
