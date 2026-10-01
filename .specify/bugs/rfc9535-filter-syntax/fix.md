# Fix: rfc9535-filter-syntax (Issue #1)

**Status:** applied
**Branch:** `fix/rfc9535-filter-syntax`
**TDD mode:** emulated red-green (the `speckit-bug-*` / TDD extension skills are not
installed in this environment; the red→green→refactor loop was run manually with the
same artifacts).

## Remediation applied

### 1. `lib/src/json_path.dart`

- `toPathArray`: added a second normalization pass right after the existing
  paren-form rewrite. Bare RFC 9535 filter selectors
  `\[\s*\?(?!\()((?:[^'"[\]]|'[^']*'|"[^"]*"|\[[^\]]*\])+)\]` are captured and
  re-written into the internal `?(<expr>)` placeholder form (`[#N]`), so the
  pre-existing `_trace` filter branch handles them unchanged. The alternation
  preserves quoted strings and single-level nested brackets inside the filter.
- `_filter` / `_dynamic`: bind `key` as a `BuiltInFunction` returning the current
  member key / array index (`_$_property` semantics) — `key(@)` and `key()` both work
  and match the `json_path` package's `key()`.
- Analyzer hygiene: `final _opts`, braced statements in `_walk` (pre-existing infos).

### 2. `lib/src/sandboxed_script.dart`

- New `BuiltInFunction` class (now exported from `json_path_plus.dart` as a sandbox
  extension point).
- `SafeEval.evaluate` seeds the context with the RFC 9535 function extensions:
  - `match(value, pattern)` — full-string match (`^(?:pattern)$`),
  - `search(value, pattern)` — substring match.
  Both return `false` for non-string values or invalid patterns (RFC LogicalFalse),
  and both are shadowed by user sandbox entries.
- `_evalCall` dispatches `BuiltInFunction` callees by identifier.
- `_MethodProxy` gained `String.match(pattern)` → first matching substring or `null`.
- Added `library;` directive to fix the dangling-doc-comment lint.

### 3. Tests

- New `test/rfc9535_filter_test.dart` (29 tests), written red-first:
  - Issue #1 reproduction in bare and parenthesized form,
  - bare filters with/without spaces, string equality, logical ops, nested bracket
    notation, truthiness (RFC: only `null`/`false` are falsy),
  - `match` vs `search` semantics, non-string → false, invalid regex → false,
  - `key()` in object and array contexts, `@property` parity, shadowing,
  - `String.match()` proxy.
- Full suite: **119/119 green** (90 pre-existing + 29 new). `dart analyze`: clean.

### 4. Docs / version

- `README.md`: new "RFC 9535 filter selectors and functions" section with semantics
  notes; features list updated.
- `CHANGELOG.md`: 1.2.0 entry. `pubspec.yaml`: 1.1.0 → 1.2.0.
- Library doc comments updated (`json_path_plus.dart`, `sandboxed_script.dart`).

## Verification of the reported failure

The exact issue reproduction (`$[?match(key(@), "data-main-slot:search-result-.*")]`
over the Amazon payload) now returns the 2 matching maps.

## Notes discovered during the fix (not in scope here)

- Consecutive filter selectors drill into children (JSONPath-Plus semantics) —
  `[?a][?b]` is not "and"; document or file.
- Filter truthiness is RFC 9535 (only `null`/`false` falsy) while JSONPath-Plus uses
  JS truthiness — a deliberate, now-documented divergence.
- Placeholder-token path handling (`#N`) clobbers literal property names shaped like
  `#<digits>` when sub-expressions exist (pre-existing edge case).
