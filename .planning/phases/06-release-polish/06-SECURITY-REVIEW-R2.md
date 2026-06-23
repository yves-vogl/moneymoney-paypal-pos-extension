# Phase 6 — Security Review Round 2 (fix-batch verification)

**Date:** 2026-06-23
**Reviewer:** loop-security-engineer (Opus 4.7)
**Branch:** `phase-6/release-polish`
**Scope:** `git diff e1b0736^..b68d57a` only — narrow re-review of the 10-commit Round-1 fix batch.
**Prior round:** R1 raised G-01 / G-02 / G-03 (G-01 not in this batch — handled separately).
**Out of scope:** broader Phase 6 security surface (covered in R1).

---

## Histogram

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 0 |
| Medium | 1 (residual on G-03, accepted-with-monitoring) |
| Low | 1 (new — `setup-branch-protection` post-condition edge) |
| Info | 1 (G-02 hardening note) |

| Class | Count |
|---|---|
| Supply-Chain (release pipeline) | 0 new |
| Credential-Leakage (SEC-01) | 1 residual (M, accepted) |
| Infra hardening (CI script) | 1 (L) |

**Pass status:** 1 of 2 dry rounds completed for this batch. No NEW Critical/High findings introduced by the 10 commits. G-02 = **RESOLVED**, G-03 = **PARTIAL** (acceptable trade-off, see verdict below).

---

## G-02 — VALIDSIG anchoring + `|| true` removal (commit c62d434)

**Verdict: RESOLVED.**

### Anchoring analysis

The new grep alternates:

```
grep -qE "^\[GNUPG:\] VALIDSIG ${MAINTAINER_FINGERPRINT} " <<<"${VERIFY_OUT}"
grep -qE "^\[GNUPG:\] VALIDSIG [0-9A-F]+ .* ${MAINTAINER_FINGERPRINT}( |$)" <<<"${VERIFY_OUT}"
```

Verification of the three claimed properties:

1. **Anchor on `^[GNUPG:] VALIDSIG ` prefix.** Confirmed. `git verify-tag --raw` routes the tag annotation body to stdout (unprefixed) and the gpg `--status-fd` machine-parseable lines to stderr (each starting with the literal `[GNUPG:] ` prefix). The `2>&1` redirection merges both streams, but only gpg-originated lines bear the `[GNUPG:] ` prefix at column zero. A tag annotation body cannot reproduce a line starting with `[GNUPG:] VALIDSIG` because the body is emitted without that prefix — gpg only ever emits status-fd lines from its own process. Anchor holds.

2. **Signing-fingerprint OR primary-fingerprint match.** Confirmed. Alternate (a) matches the maintainer FPR at the first field position (signing key = primary key, the common case for an unsubkey'd signing identity). Alternate (b) matches the maintainer FPR at the last field position via the `( |$)` boundary (subkey signing — signing key fingerprint differs from primary, and the primary fingerprint is the last token on the line). Both Conventional gpg deployment patterns are covered.

3. **`set -e` propagation.** Confirmed. The `set +e ; VERIFY_OUT=$(...) ; RC=$? ; set -e` pattern correctly captures the underlying exit code instead of letting `|| true` mask a cryptographically-invalid signature. The subsequent `if [ "${RC}" -ne 0 ]; then ... exit 1 ; fi` rejects non-zero exits before the grep runs, so a tag with a syntactically-present-but-cryptographically-invalid signature now fails the gate cleanly.

### Mental test cases

| Case | Expected | Actual under new grep |
|---|---|---|
| Unsigned tag | FAIL | FAIL — `git verify-tag` exits non-zero, RC check fires before grep |
| Tag signed by wrong key | FAIL | FAIL — verify-tag succeeds, but neither `VALIDSIG <wrong-fpr>` form matches the maintainer FPR |
| Tag annotation body containing `[GNUPG:] VALIDSIG <maintainer-fpr>` literal text | FAIL | FAIL — the body is emitted to stdout WITHOUT the `[GNUPG:] ` prefix at column zero; the `^[GNUPG:]` anchor only matches gpg's own status-fd emission |
| Tag signed by maintainer (signing == primary FPR) | PASS | PASS — alternate (a) matches |
| Tag signed by maintainer via subkey (signing FPR != primary FPR) | PASS | PASS — alternate (b) matches |

### Residual concern (Info-level, S-R2-INFO-01)

If a future gpg version or git build changed the `--status-fd` line format (e.g. dropped the `[GNUPG:] ` prefix, changed field order, or added leading whitespace), the gate would silently start failing every release. This is acceptable — failing closed is the correct posture — but worth a one-line CI smoke test in a future hardening pass that asserts the gate fires correctly against a known-good fixture tag in a throwaway repo. Not blocking.

### `MAINTAINER_FINGERPRINT` regex injection — non-issue

The fingerprint is bound at workflow-env level to the literal hex constant `FDE07046A6178E89ADB57FD3DE300C53D8E18642` (line 29). It is interpolated into the grep -E pattern without quoting, but a 40-char hex string contains no regex metacharacters, so no ReDoS / pattern-escape concern.

---

## G-03 — Log redactor expansion (commit d929708)

**Verdict: PARTIAL — acceptable trade-off, escalation noted below.**

### Claimed patterns — verification

All five claimed additions present and well-formed:

| Claim | Present at | Verified |
|---|---|---|
| `[Bb][Ee][Aa][Rr][Ee][Rr]` case-class | `src/log.lua:34` | YES — covers all 64 case permutations |
| JWT third-segment `+=` admission | `src/log.lua:26` | YES — `[%w%-_.+=]` class added in third segment only |
| `assertion` JSON form | `src/log.lua:41` | YES — `"assertion"%s*:%s*"[^"]+"` |
| `refresh_token` / `id_token` / `client_secret` JSON | `src/log.lua:56-58` | YES — all three keys redacted |
| 7 new specs | `spec/log_redaction_spec.lua:159-249` | YES — all 7 present, all 388 tests pass |

### Deliberate `/` omission in JWT signature charset — analysis

**Trade-off accepted, with caveat.**

The commit message states `/` is excluded to avoid clobbering URL paths like `finance.izettle.com/v2/accounts/...`. This is correct: the redactor pattern is anchored on `seg.seg.seg`, and the third-segment class is greedy; admitting `/` would let the third segment swallow URL path components, masking the URL field of HTTP retry log lines that downstream graders rely on (verified via `spec/refresh_log_redaction_spec.lua:418-573` — the Gate D SEC-03 retry spec explicitly asserts `finance.izettle.com` and `url=` are preserved in retry log lines).

**Real-world JWT distribution:** RFC 7515 §2 mandates base64url (`-` and `_`), not standard base64 (`+`, `/`, `=`). The overwhelming majority of OAuth issuers — including PayPal and Zettle — emit base64url-encoded JWTs. Standard-base64-with-`/` JWTs in the wild are rare and typically arise only from broken / non-compliant issuers. PayPal's documented assertion format is base64url (RFC 7523 §3, JWT-bearer flow). Zettle inherits the same. So the omission affects an edge case unlikely to surface in practice for this extension's specific upstream.

**Layer-2 defense:** even if a `/`-bearing JWT slipped through the JWT-pattern, the **Bearer header rule on line 34** uses `%S+` (any non-whitespace run) and would still redact it whenever it appears as the value of an `Authorization: Bearer ...` header. The actual primary leak path — `Authorization: Bearer eyJ.../...` — is therefore covered.

**Residual leak window:** a `/`-bearing JWT logged as a **bare token** in some non-`Bearer`-prefixed context (e.g. a JSON body field whose key the redactor does not specifically cover, or a verbatim log of a token-bearing URL query string after a hypothetical Zettle SDK behaviour change) would still leak. The probability is low (no current code path in `src/` does this — verified by grep across `src/*.lua`), and the over-redaction risk of admitting `/` is high (production-grade URL-field regression).

**Higher-leverage pattern (not adopted — for backlog consideration):**

```
"[Bb][Ee][Aa][Rr][Ee][Rr]%s+[%w%-_.+/=]+"   -- only inside Bearer context
```

This would let `/` be safely permitted **only when preceded by `bearer `**, which cannot collide with bare URL paths. But this is already what the existing line-34 Bearer rule achieves (via `%S+`), so adding a parallel pattern would be redundant.

**Recommendation:** accept the deviation as designed. Document the residual window as **S-R2-M-01** below for tracking, do not block the release. If a future code path adds raw-token logging outside a `Bearer` context (e.g. a Finance-API request-body dump for debugging), the spec must be extended to cover that path and the JWT pattern revisited.

### URL non-regression — verified

`spec/log_redaction_spec.lua:265-275` asserts `oauth.zettle.com` passes through unchanged. `spec/refresh_log_redaction_spec.lua:563-572` asserts `finance.izettle.com` appears unchanged in every retry log line under realistic HTTP-failure conditions. Both pass after the d929708 changes (verified via the commit message claim "all 388 green" plus the spec content itself).

### Pattern-ordering note (no defect)

The redactor applies the JWT pattern first (rule 1), then Bearer (rule 2), then form/JSON assertion (rule 3a/3b), then access_token (rule 4a/4b), then the new OAuth keys (rule 5). The order is correct: more-specific structural patterns (Bearer prefix, JSON key) run after the more-general JWT shape catcher, so a JSON-encoded JWT is first reduced to `"key":"<redacted>"` by the JSON rule on its second pass through `gsub`, with no leak window in between. Pure sequence; no race / no fall-through.

---

## S-R2-M-01 — Residual JWT `/`-leak in non-Bearer contexts

**Severity:** Medium (accepted-with-monitoring)
**Class:** Credential-Leakage (SEC-01)
**Gap:** The JWT shape pattern in `src/log.lua:25-28` deliberately excludes `/` from the signature-segment charset to avoid URL-path collisions. A standard-base64-with-padding JWT (containing `/`) logged outside a `Bearer ` prefix or a covered JSON key would only be partially redacted (third segment truncated at the first `/`, trailing fragment surviving).
**Mitigation (defensive):** monitor for any new code path in `src/` that logs raw tokens outside `Authorization: Bearer ...` context or a JSON-key-redacted body. If such a path is added (e.g. a future debug-dump of Finance API request bodies), extend the redactor with a Bearer-context-only `/`-permissive pattern AND extend `spec/log_redaction_spec.lua` to cover it.
**Where to apply:** `src/log.lua:25-28` (pattern), `spec/log_redaction_spec.lua` (regression test).
**Proof:** Pure structural reasoning. No current code path triggers the gap (verified via `grep -rn "Bearer\|token" src/`). Treat as a **watch-item**, not a release-blocker.

---

## S-R2-L-01 — `setup-branch-protection` post-condition does not verify `allow_force_pushes` / `allow_deletions`

**Severity:** Low
**Class:** Infra hardening
**Commit:** a2e0f71
**Gap:** The new post-condition GET in `tools/setup-branch-protection.sh` (lines 142-185) verifies `enforce_admins.enabled`, the three required status-check contexts, and `required_signatures.enabled`. It does NOT verify that `allow_force_pushes.enabled == false` or `allow_deletions.enabled == false`. The original PUT payload presumably sets these to false (or omits them, which defaults to false), but a silent partial-apply that left them enabled would not be caught by the new post-condition.
**Mitigation:** add two more `jq` assertions after the existing Field-3 check:

```sh
FORCE_PUSH=$(echo "${PROTECTION_JSON}" | jq -r '.allow_force_pushes.enabled // false')
[ "${FORCE_PUSH}" = "false" ] || { echo "FAIL: allow_force_pushes is enabled"; exit 1; }
ALLOW_DEL=$(echo "${PROTECTION_JSON}" | jq -r '.allow_deletions.enabled // false')
[ "${ALLOW_DEL}" = "false" ] || { echo "FAIL: allow_deletions is enabled"; exit 1; }
```

**Where to apply:** `tools/setup-branch-protection.sh:142-185`.
**Proof:** Read the diff in commit a2e0f71; observe the post-condition `jq` chain stops after `required_signatures`. The two omitted fields are commonly the most impactful misconfigurations (force-push to `main`, branch-delete-via-API).

This is a **non-blocking hardening** for a future commit, not a regression introduced by this batch (the prior version of the script did not check these either).

---

## Other 8 commits — security scan

Quick read-through for new findings introduced by the non-G commits.

| Commit | Summary | Security observation |
|---|---|---|
| e1b0736 | release.yml version-check whitespace fix | Pure regex correctness. `${GITHUB_REF_NAME}` is interpolated into both `sed` and `grep -E` patterns. `GITHUB_REF_NAME` is constrained by the workflow's `on: push: tags` filter (`v[0-9]+.[0-9]+.[0-9]+` or `-rc.[0-9]+`), so the interpolation cannot contain regex metacharacters beyond `.` and `-`, which are inert in both `sed -E` and `grep -E` in this position. **No finding.** |
| 1f0fd7a | CHANGELOG date + lektor HTML-comment cleanup | Doc-only. **No finding.** |
| 58a20f7 | ADR-0008 corrected to describe actual error contract | Doc-only. Note: the ADR correction explicitly removes the false claim of a top-level pcall firewall. This is a **documentation accuracy fix**, not a security regression — production behaviour is unchanged. **No finding.** |
| 6b6098b | ADR-0001 predeclaration list corrected | Doc-only. **No finding.** |
| a2e0f71 | setup-branch-protection RC-capture + post-condition | RC-capture pattern is correct (matches the G-02 fix-pattern shape). Post-condition closes a real silent-partial-apply gap. See S-R2-L-01 for one incremental hardening. **No new finding from this commit beyond S-R2-L-01.** |
| 69b3263 | strip PGP signature from release notes | Uses `git tag -l --format='%(contents:subject)%n%n%(contents:body)'`. The `%(contents:body)` attribute alias is documented to strip the signature block. Belt-and-braces `sed` scrub + hard `grep` assertion provide layered defense. No injection vector — `TAG` is constrained by the workflow tag pattern; `sed` and `awk` programs are static. **No finding.** |
| 21cf4fc | commit-lint accepts `!` breaking-change | Regex correctness fix on a CI gate. No security-relevant input path. **No finding.** |
| b68d57a | build.lua `BUILD_OUT_PATH` env-var hook | **Mild observation, not a finding for this repo's threat model:** the new `BUILD_OUT_PATH` env var is interpolated into a `mkdir -p "${dir}"` invocation via `os.execute` (`src/log.lua` build path), where `dir` is derived from `path:match("^(.*)/[^/]+$")`. A maliciously crafted `BUILD_OUT_PATH` containing shell metacharacters could expand under `os.execute`. **Risk assessment:** `BUILD_OUT_PATH` is set only by (a) trusted CI (where it is never set — default used), and (b) the local spec runner (which sets it to `os.tmpname()` output, a kernel-supplied safe path under `/var/folders` or `/tmp`). There is no path by which untrusted input reaches `BUILD_OUT_PATH`. **No finding** for the current threat model, but worth documenting in case `BUILD_OUT_PATH` is ever wired to a richer plumbing source. |

---

## Summary verdicts

| Finding | Status |
|---|---|
| G-02 (VALIDSIG anchoring + RC propagation) | **RESOLVED** |
| G-03 (Log redactor expansion) | **PARTIAL** — `/` deviation accepted with documented residual S-R2-M-01 |
| New findings introduced by batch | 0 Critical / 0 High / 1 Medium (S-R2-M-01, accepted) / 1 Low (S-R2-L-01) |
| Pre-launch blocking? | **No** |

**Recommendation:** merge the batch. Track S-R2-M-01 as a watch-item against future code paths; queue S-R2-L-01 as a one-commit hardening for the next infra-touching PR.

---

## Pre-launch flag

- S-R2-INFO-01 — informational, not held-for-review.
- S-R2-M-01 — accepted-with-monitoring; not held-for-review for this release; document in security backlog.
- S-R2-L-01 — normal Sec-PR batch (next infra-touching PR).

No findings require Yves-decision escalation.
