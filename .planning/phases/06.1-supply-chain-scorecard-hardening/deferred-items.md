# Deferred items — Phase 06.1

Items discovered during execution that are out-of-scope for the discovering plan.

## From Plan 06.1-03 (discovered 2026-06-23)

- **Node 20 → 24 deprecation warning** on `actions/checkout@11bd7190…` (v4.2.2) and `github/codeql-action/upload-sarif@8272c299…` (v3.36.2). Runners force them onto Node 24 today; explicit bump is a separate plan (likely Plan 06.1-05 Dependabot uplift).
- **CodeQL Action v3 → v4 deprecation** (December 2026 cliff) on `github/codeql-action/upload-sarif@8272c299…`. Same SHA is reused in `scorecard.yml` (Plan 06.1-01). Both call-sites need synchronized bumping; track for Plan 06.1-05 or a dedicated follow-on.

