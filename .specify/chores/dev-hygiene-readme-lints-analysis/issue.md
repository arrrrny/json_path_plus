# Issue #12: chore: dev hygiene — README JsonPathMatch drift, lints bump, stricter analysis

- **State:** OPEN
- **URL:** https://github.com/arrrrny/json_path_plus/issues/12
- **Raw:** `issue.json` in this directory

### Problem

Small hardening items found during the 1.2.0 pass:

1. **README `JsonPathMatch` docs don't match the class** — README shows `final String path` / `final String? property`, but the actual class (`lib/src/json_path_match.dart`) has `List<String> path` (mutable), `parentProperty`, `hasArrExpr`, `pointer`, `pathString`, and no `property` field. Update the README block (and consider whether the fields should be `final`).
2. **`lints: ^3.0.0` is outdated** — current is ^6.x; bumping will likely surface a handful of new infos, fix them in the same change.
3. **`analysis_options.yaml`** — consider enabling a stricter set (e.g. adding `prefer_final_locals`, `unawaited_futures`-class rules, or adopting a stricter shared preset) now that CI runs `dart analyze --fatal-infos`.
4. **pubspec** — double-check `topics` (add `regexp` / `rfc9535`-adjacent discoverability keywords if useful) and the description for pub.dev scoring.

### Baseline (measured 2026-10-02, commit `3ed31f7`, Dart 3.13.4)

- `dart analyze --fatal-infos` — **no issues found**
- `dart test` — **230 tests, all passing**
- `dart format --set-exit-if-changed .` — clean
- `lints` resolved: `3.0.0`; latest on pub.dev: `6.1.0`
