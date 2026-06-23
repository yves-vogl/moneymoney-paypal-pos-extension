# ADR-0007: No TLS-certificate pinning; rely on Connection() defaults

## Status

ACCEPTED

## Date

2026-06-22

## Deciders

Yves Vogl

## Context

TLS-certificate pinning (or HPKP, or a similar trust-on-first-use scheme)
is a defense-in-depth mechanism that protects clients against rogue
intermediate CAs and active MITM attacks. A pinned client verifies the
server presents not just a TLS chain that validates against the system
trust store, but specifically a certificate whose public-key fingerprint
matches a baked-in expected value.

Phase 1 Q8 (`docs/adr/0003-sandbox-probe-results.md`) verified MoneyMoney's
`Connection()` global performs TLS-server-certificate validation by default
against the macOS system root store. The probe also confirmed the sandbox
exposes **no API** for:

- Supplying a custom CA bundle.
- Configuring an SPKI pin set per host.
- Inspecting the server certificate post-handshake.
- Disabling the default verification (a useful sandbox property — failure
  modes do not silently degrade to plaintext).

The shipped artifact talks to three hosts only (Zettle's documented
production API endpoints):

- `oauth.zettle.com`
- `purchase.izettle.com`
- `finance.izettle.com`

Zettle is a PayPal subsidiary on a managed PKI rotation cadence. The
practical security question is: does adding pinning materially raise the
bar against the realistic threat model for a personal-finance extension
reading a single merchant's transaction history?

References:

- Phase-1 ADR-0003 Q8 — `Connection()` TLS-default-verify finding.
- CLAUDE.md → "What NOT to Use" — Lua C modules / native deps forbidden.
- Phase-4 CI egress allowlist gate (`.github/workflows/ci.yml` lines 83–120).

## Decision

The extension does not implement TLS-certificate pinning. It relies
exclusively on the TLS-server-certificate validation that `Connection()`
performs by default against the macOS system trust store.

### Rationale

1. **The sandbox forbids the implementation.** Even if we wanted to pin,
   the `Connection()` API does not expose a `set_pinned_cert_fingerprint`
   hook, a custom CA bundle path, or a post-handshake-callback. Shipping a
   pinned client would require a native Lua module — forbidden by the
   single-file-distribution constraint in CLAUDE.md.

2. **Pinning trades availability for confidentiality.** A static pin set
   breaks the extension the moment Zettle rotates a certificate or
   intermediate. The breakage is silent from the extension's perspective
   (TLS handshake fails) and the user-visible symptom — "sync stops working
   on a random morning" — is among the worst recovery experiences for a
   read-only bookkeeping aid where the user expects unattended operation.
   Zettle's PKI rotation cadence is not publicly committed; observation
   suggests semi-annual at unpredictable times.

3. **The compensating controls do the heavy lifting.** The realistic threat
   model for this extension is "an attacker exfiltrates merchant
   transaction data" — not "an attacker forges responses to alter
   transaction display". The independent controls that address the
   exfiltration risk:

   - **Egress allowlist (CI gate).** Phase-1 S-05 SEC enforced; Phase-4
     S-05 fix hardened to catch scheme-less hostnames. The CI gate
     fails any artifact that names a host outside the three allowlisted
     production endpoints. A compromised maintainer pushing a malicious
     PR cannot ship an artifact that talks to `evil.example.com`
     without the gate firing.
   - **SEC-01 redactor.** `M_log` strips `Bearer` and JWT shape before
     anything reaches MoneyMoney's stdout. Even if the runtime
     somehow logged a request, the API key and bearer are masked.
   - **Reproducible build.** `lua tools/build.lua --verify` asserts the
     released artifact is byte-identical to the source tree. A user
     can verify locally that the published `paypal-pos.lua` is what
     `main` would produce at the signed tag.
   - **GPG-signed releases.** `release.yml` refuses to publish from a
     tag not signed by the maintainer's key
     (`FDE07046A6178E89ADB57FD3DE300C53D8E18642`). A user can
     `git verify-tag vX.Y.Z` independently. This trust chain is
     fully out-of-band from TLS.

   Pinning would harden against a fifth attack vector (rogue CA at a
   network choke-point between the user and Zettle), which is materially
   smaller than the four above for a macOS desktop reading a single
   merchant's data on a typical home / café network.

## Consequences

**Positive:**

- Zero maintenance burden on Zettle PKI rotations. A future certificate
  swap by Zettle does not require an extension release.
- No risk of a "the extension stopped working overnight" incident driven
  by upstream rotation.
- No additional native code or CA-bundle ship — preserves the single-file
  distribution invariant.

**Negative:**

- If a CA in the macOS system trust store is compromised AND an attacker
  can position themselves between the user's Mac and `*.izettle.com`
  (i.e. a network MITM), the attacker can intercept merchant transaction
  data. This is **accepted risk** given:
  - The extension is read-only (no write-back vector).
  - The threat model assumes a typical home / café network, not a
    state-actor TLS-interception environment.
  - macOS users with elevated threat models can pin at the OS layer
    (Little Snitch + Apple's MDM trust profile management) without
    extension involvement.

**Mitigations summary (the trust chain that does NOT depend on TLS pinning):**

- Egress allowlist CI gate (network destination integrity).
- SEC-01 redactor (credential exposure in logs).
- Reproducible build (source-to-artifact integrity).
- GPG-signed releases (publisher identity).
- HSTS on `*.izettle.com` (downgrade protection at the TLS layer).

## References

- Phase-1 ADR-0003 Q8 — `Connection()` TLS defaults probe.
- `.github/workflows/ci.yml` lines 83–120 — egress allowlist gate.
- `src/log.lua` — SEC-01 redactor.
- `.github/workflows/release.yml` — GPG-signed-tag verification.
- CLAUDE.md → "What NOT to Use" — native dep forbidden.
- Phase 6 / 06-RESEARCH.md §Threat Mitigation enumeration.
