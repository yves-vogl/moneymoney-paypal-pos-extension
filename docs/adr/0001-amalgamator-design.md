# ADR-0001: Single-file amalgamation via custom tools/build.lua

## Status

ACCEPTED

## Date

2026-06-16

## Deciders

Yves Vogl

## Context

MoneyMoney loads every extension as a single top-level Lua chunk via its embedded Lua 5.4
interpreter. The `WebBanking{...}` registration table and the five mandatory callbacks
(`SupportsBank`, `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `EndSession`) must
all be declared at top scope — MoneyMoney invokes them as globals, not as module-exported
functions. The embedded interpreter has no LuaRocks installation, no `package.path` for
non-stdlib modules, and `require()` of sibling files is not available inside the sandbox.

Source-tree maintainability demands a multi-file layout under `src/` (one concern per file,
1:1 mirroring with `spec/<module>_spec.lua` test files). But the shipped artifact must be a
single `.lua` file with no `require` calls visible at load time.

Reference: MoneyMoney WebBanking API — https://moneymoney.app/api/webbanking/

## Decision

Custom ~150-line `tools/build.lua` amalgamator, driven by `tools/manifest.txt`, that
concatenates `src/*.lua` modules in declared order.

- `src/webbanking_header.lua` is emitted verbatim at the top of the artifact: it contains
  the `WebBanking{...}` registration call and predeclares all cross-module tables
  (`M_log`, `M_errors`, `M_i18n`, `M_model`, `M_http`, `M_auth`, `M_pagination`,
  `M_purchases`, `M_finance`, `M_mapping`) as top-level locals.
- `src/entry.lua` is emitted verbatim at the tail: the MoneyMoney callbacks must be
  top-level globals, not enclosed in a `do...end` block.
- All other modules are wrapped in `do...end` blocks with a `-- === MODULE: <name> ===`
  banner comment. Module cross-references go through the predeclared `M_*` globals.
- Build is deterministic: LF normalisation on input, no timestamps, no env reads, no git
  SHA in the artifact, explicit manifest (not a directory walk).
- `lua tools/build.lua --verify` builds twice and compares SHA-256 of both outputs via a
  self-contained pure-Lua SHA-256 routine embedded in `tools/build.lua`. Exit code 0 with
  stdout `OK: reproducible` on match; exit code 1 on mismatch.

## Alternatives considered

### lua-amalg (rejected)

[`siffiejoe/lua-amalg`](https://github.com/siffiejoe/lua-amalg) is the established prior-art
Lua amalgamation tool. It works by wrapping each module in a `package.preload` loader so that
a subsequent `require("module")` call activates it. This model is incompatible with
MoneyMoney's load contract: (1) the `WebBanking{...}` registration and the five callbacks
must be visible at top scope immediately, not behind a `require`; (2) `package` may not be
available in MoneyMoney's sandbox in the form a stock Lua-on-CLI installation expects.
Reference: https://github.com/siffiejoe/lua-amalg — ARCHITECTURE.md §3.

### Hand-maintained single file (rejected)

The existing Payback and Trading-212 MoneyMoney community extensions hand-maintain a single
`.lua` file with no build step (see https://github.com/jgoldhammer/moneymoney-payback/blob/master/payback.lua
and https://github.com/teal-bauer/moneymoney-ext-trading212). This is acceptable below ~1500
lines of code, but PR diff-review quality and unit-testability degrade as the file grows.
The PayPal POS v1.0 surface (auth + purchases + finance + mapping + i18n + errors + log)
sits on the boundary of that threshold. The amalgamator pays its complexity back in clean
source-tree organisation, per-module test coverage, and reproducible builds.

### Lua bytecode (luac) ship (rejected)

`luac` output is platform-dependent and Lua patch-version-pinned. MoneyMoney controls the
embedded interpreter patch level; distributing bytecode-only means any MoneyMoney update
could silently break the extension without any source change. Source form is also auditable,
which matters for an extension that handles merchant API credentials.

## Consequences

- Approximately 150 lines of build tooling added under `tools/` (pure Lua, no external
  dependencies, not shipped in the artifact).
- Deterministic build verified by `lua tools/build.lua --verify`; byte-identical output
  confirmed across consecutive runs and tested via `spec/build_spec.lua`.
- Build aborts on any source line (outside a comment) containing: `require(`, `dofile(`,
  `loadfile(`, `io.open(`, `os.execute(`, `io.popen(` (H8 sandbox-call gate) or
  `DEBUG = true` (SEC-04 gate).
- The pure-Lua SHA-256 routine is embedded in `tools/build.lua` (public domain, cited in
  the source comment). Tools are dev-only; nothing in `tools/` ships in the artifact.
- Source-tree contributors must not use `require()` in any `src/*.lua` file. Cross-module
  references go through the predeclared `M_*` globals from `src/webbanking_header.lua`.
