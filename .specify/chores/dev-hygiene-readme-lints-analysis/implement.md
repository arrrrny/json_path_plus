# Implementation: dev hygiene — README JsonPathMatch drift, lints bump, stricter analysis

- **Slug:** `dev-hygiene-readme-lints-analysis`
- **Issue:** https://github.com/arrrrny/json_path_plus/issues/12
- **Branch:** `chore/dev-hygiene-readme-lints-analysis` (from `master` @ `3ed31f7`)
- **Status:** `applied`
- **Date:** 2026-10-02
- **Toolchain:** Dart 3.13.4

## Item 1 — README `JsonPathMatch` drift — APPLIED

`README.md:227` documented a class that does not exist. Rewritten to mirror
`lib/src/json_path_match.dart` field-for-field.

Corrections made:

| Old (wrong) | New (verified) |
| --- | --- |
| `final String path` | `List<String> path` (path components, mutable) |
| `final List<String>? paths` | removed — field does not exist |
| `final String? property` | `String? parentProperty` |
| `final Object? value` | `Object? value` (not final) |
| `Object? pointer` | `String? pointer` |
| — | added `bool hasArrExpr` |
| — | added `String? pathString` |
| — | added internal `isParentSelector`, `parentSelectorExpr` |

Every claim in the new block was verified against the implementation:

- `pointer` / `pathString` are assigned **only** in the `case 'all'` branch of
  `JSONPath._output` (`lib/src/json_path.dart:114-118`) — confirmed.
- `isParentSelector` results are filtered out before user-visible output
  (`lib/src/json_path.dart:97`) — hence "internal".
- `hasArrExpr` is public behaviour (drives the `wrap: false` single-result
  optimisation, `lib/src/json_path.dart:100`), so it is **not** listed as internal.

Also added an explicit note that there is no `property` field, since that was
the single most misleading entry in the old block.

### Fields made `final`? — NO (deliberately out of scope)

The issue suggested considering `final`. Rejected: `path` is rebuilt during
parent-selector tracing (`lib/src/json_path.dart:180`) and `pointer` /
`pathString` are assigned *after* construction by `_output`. Making them
`final` is a behavioural refactor of the evaluator, not hygiene. Per the
assessment this stays out of scope.

### `callback` signature verified — no change needed

`README.md:170` documents `void Function(Object?, String, JsonPathMatch)?`.
This matches `JSONPath._cb` (`lib/src/json_path.dart:135-138`) exactly. Left
as-is.

## Item 2 — `lints: ^3.0.0` → `^6.1.0` — APPLIED

`pubspec.yaml` now declares `lints: ^6.1.0` (was `^3.0.0`). `pubspec.lock`
updated via `dart pub get`.

**The issue predicted "a handful of new infos" — that did not materialise.**
Bumping `lints` 3.0.0 → 6.1.0 across 5 minor versions surfaced **zero** new
diagnostics. The codebase was already clean under the newer lint set. The only
infos that appeared during this chore came from the *newly enabled* rules in
item 3, not from the package bump.

Also bumped `test: ^1.25.0` → `^1.32.0` — the latest resolvable version per
`dart pub outdated`, and the same hygiene rationale. Dev-only; no effect on
consumers or the SDK constraint.

## Item 3 — Stricter `analysis_options.yaml` — APPLIED

`analysis_options.yaml` had the entire `linter:` section commented out — the
bare `package:lints/recommended.yaml` floor. Since CI runs
`dart analyze --fatal-infos`, every added rule is a hard gate, so each candidate
was measured individually before adoption:

| Candidate rule | New diagnostics | Decision |
| --- | --- | --- |
| `always_declare_return_types` | 0 | **Adopted** |
| `unawaited_futures` | 0 | **Adopted** |
| `prefer_final_locals` | 1 | **Adopted** + fixed |
| `omit_local_variable_types` | 2 | **Adopted** + fixed |
| `avoid_dynamic_calls` | 4 | **Adopted** + fixed |
| `prefer_final_parameters` | 210 | Rejected — drops |
| `require_trailing_commas` | 206 | Rejected — drops; also fights the Dart 3.7+ formatter, which now owns trailing-comma placement |

Rejection rationale is recorded inline in `analysis_options.yaml` so the next
person does not re-run the experiment.

### Fixes required by the new rules (7 total, all mechanical)

`lib/src/sandboxed_script.dart`:

- `:382` `var expr = _parseOr()` → `final expr = _parseOr()` (never reassigned).
- `:1193`, `:1200` `for (int i = 0; ...)` → `for (var i = 0; ...)` — matches the
  existing convention at `:1062` in the same file.

Test files — three sites accessed a member on the `dynamic` returned by
`JSONPath.evaluate` (declared `static dynamic evaluate`). Fixed with an explicit
`as List<Object?>` cast at the declaration, which is the real return shape:

- `test/json_path_plus_test.dart:710`
- `test/rfc9535_filter_test.dart:243`
- `test/root_filter_test.dart:55`

## Item 4 — pub.dev `topics` — APPLIED

`query` replaced with `json-query`. pub.dev allows max 5 topics and the list
was already at the cap, so the weakest term was swapped rather than appended.
Final set: `json`, `jsonpath`, `json-query`, `filter`, `expression`.

The `description` field was reviewed and left unchanged — it is already
well-formed, accurate, and within pub.dev's 180-char limit.

## Verification

All gates run on the chore branch, matching `.github/workflows/ci.yml`:

```
dart format --output=none --set-exit-if-changed .   →  Formatted 13 files (0 changed)
dart analyze --fatal-infos                          →  No issues found!
dart test                                            →  All tests passed!  (230 tests)
```

| Gate | Baseline (`3ed31f7`) | After | Change |
| --- | --- | --- | --- |
| `dart analyze --fatal-infos` | No issues | No issues | — |
| `dart test` | 230 passing | 230 passing | — |
| `dart format --set-exit-if-changed` | Clean | Clean | — |
| `lints` | 3.0.0 | 6.1.0 | bumped |

**No behavioural change.** The 7 source edits are type-annotation and
`final` changes only; no expression, no control flow, no API surface touched.

## Deviations from Assessment

1. **Item 2's premise was wrong.** The issue said a lints bump "will likely
   surface a handful of new infos, fix them in the same change." It surfaced
   none. All 7 new infos came from the item-3 rule additions instead. Recorded
   so nobody re-chases the original prediction.

2. **`test: ^1.25.0` → `^1.32.0` added beyond assessment scope.** Same hygiene
   rationale as `lints`; flagged here for review rather than buried.

3. **CHANGELOG entry deferred.** Acceptance criterion 7 asked for a changelog
   entry. `pubspec.yaml` is already at `2.0.0` and **unpublished** (pub.dev
   latest is `1.1.0`), and `CHANGELOG.md` already carries a `## 2.0.0` section
   from the breaking cache change. Adding a separate entry here would fragment
   the same unreleased version. These changes will be folded into the existing
   `## 2.0.0` entry during the publish step instead.

## Files changed

```
 README.md                     | 23 ++++++-----
 analysis_options.yaml         | 37 ++++++++-------
 lib/src/sandboxed_script.dart |  6 ++--
 pubspec.lock                  | 16 ++++++-------
 pubspec.yaml                  |  8 ++---
 test/json_path_plus_test.dart |  2 +-
 test/rfc9535_filter_test.dart |  2 +-
 test/root_filter_test.dart    |  2 +-
```

Plus this chore's `.specify/chores/dev-hygiene-readme-lints-analysis/`
artifacts, tracked by precedent with `.specify/bugs/`.
