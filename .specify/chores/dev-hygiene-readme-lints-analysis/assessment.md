# Assessment: dev hygiene — README JsonPathMatch drift, lints bump, stricter analysis

- **Slug:** `dev-hygiene-readme-lints-analysis`
- **Source:** GitHub issue https://github.com/arrrrny/json_path_plus/issues/12
- **Type:** chore (dev hygiene / documentation / tooling)
- **Verdict:** `in scope`

## Why in scope

All four items in the issue are maintenance-only:

- No public API signature changes that alter behaviour.
- No changes to the JSONPath evaluation engine, filter evaluator, or sandbox.
- Fully verifiable with the existing gate: `dart format`, `dart analyze --fatal-infos`, `dart test`.

## Size: small–medium

Four independent items; three are one-to-three line edits. The bulk of the work is
item 2 (lints `^3.0.0` → `^6.1.0`) which will surface new lint infos across
`lib/` and `test/` and require fixing each site.

## Baseline (commit `3ed31f7`, Dart 3.13.4, measured 2026-10-02)

| Gate | Result |
| --- | --- |
| `dart analyze --fatal-infos` | No issues found |
| `dart test` | 230 tests, all passing |
| `dart format --set-exit-if-changed .` | Clean |
| `lints` resolved | `3.0.0` (latest `6.1.0`) |

## Item analysis

### 1. README `JsonPathMatch` block is factually wrong — CONFIRMED

`README.md:229-238` documents a class that does not exist:

| README claims | Reality (`lib/src/json_path_match.dart`) |
| --- | --- |
| `final String path` | `List<String> path` (mutable) |
| `final List<String>? paths` | does not exist |
| `final String? property` | field is named `parentProperty` |
| `final Object? value` | `Object? value` (not final) |
| `Object? pointer` | `String? pointer` |
| — (missing) | `bool hasArrExpr` |
| — (missing) | `bool isParentSelector` (internal) |
| — (missing) | `List<String>? parentSelectorExpr` (internal) |
| — (missing) | `String? pathString` |

The class has **no** `final` fields at all. `README.md:170` also documents the
`callback` signature as `void Function(Object?, String, JsonPathMatch)?` — must be
verified against the real typedef before leaving it alone.

**Decision:** rewrite the README block to mirror the real class, and add a
comment-style table of fields with their types, documenting which fields are
public API vs internal. **Do not** make the class fields `final` in this chore —
`path` is mutated by the evaluator's parent-selector tracing and
`pointer`/`pathString` are populated after construction. Making them `final`
would be a behavioural refactor with real regression risk, out of scope for a
hygiene chore.

### 2. `lints: ^3.0.0` → `^6.1.0` — CONFIRMED STALE

pub.dev reports `lints` `6.1.0` as latest; the lockfile pins `3.0.0`. CI runs
`dart analyze --fatal-infos`, so any newly-enabled lint becomes a hard CI
failure. Expected work: bump the constraint, run `dart pub get`, fix every new
info/warning. Note the SDK floor is `>=3.0.0`; `lints 6.x` is a dev-only
dependency and does not constrain the published SDK constraint.

### 3. Stricter `analysis_options.yaml` — CONFIRMED AT FLOOR

Currently `include: package:lints/recommended.yaml` with the entire rule
section commented out — the floor. The issue suggests adding stricter rules now
that CI enforces `--fatal-infos`.

**Decision:** opt into `package:lints/core.yaml`'s stricter siblings in a
measured way rather than a blanket tightening:
- switch the include to `package:lints/recommended.yaml` (unchanged) and
  explicitly enable a small, high-signal set of extra rules that suit a
  zero-dependency library: `prefer_final_locals`, `prefer_final_parameters`,
  `unawaited_futures`, `avoid_dynamic_calls`, `always_declare_return_types`,
  `require_trailing_commas`, `omit_local_variable_types`.
- Each rule must be applied or explicitly justified; any rule that fights the
  existing style gets dropped rather than worked around.
- Rules must not be added if they cannot pass cleanly — CI is `--fatal-infos`.

### 4. pub.dev `topics` / `description` — CONFIRMED THIN

Current topics: `json`, `jsonpath`, `query`, `expression`, `filter`.
pub.dev allows up to 5 topics and scores on specificity/accuracy — these are
already at the 5-topic cap. The library is a JSONPath engine with RFC 9535
filter support and a safe expression evaluator; the current list omits the
distinguishing terms.

**Decision:** replace the weakest entries rather than exceed the cap. Proposed:
`json`, `jsonpath`, `json-query`, `filter`, `expression`. The `description`
field is already accurate and well-formed for pub.dev scoring — leave it alone.

## Risk

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| New lints cascade into a large refactor | Medium | Cap the diff; if a fix is non-trivial, drop the rule and record it |
| `final`-ing `JsonPathMatch` fields breaks the evaluator | — | Explicitly out of scope (see item 1) |
| Test-only lint fixes churn test files | Medium | Allow mechanical fixes only |
| Any behaviour change | Low | No `lib/` logic changes permitted without a bug assessment |

## Acceptance criteria

1. README `JsonPathMatch` block matches `lib/src/json_path_match.dart` field-for-field.
2. `pubspec.yaml` declares `lints: ^6.1.0` (or `^6.0.0`); `dart pub get` succeeds.
3. `dart analyze --fatal-infos` reports zero issues under the new stricter config.
4. `dart format --set-exit-if-changed .` clean.
5. `dart test` — 230 tests still passing.
6. `pubspec.yaml` topics are the 5 most specific/accurate terms.
7. `CHANGELOG.md` records the change under the next version.

## Out of scope

- Any change to `lib/src/json_path.dart`, `evaluation_context.dart`,
  `sandboxed_script.dart`, or `json_path_options.dart` logic.
- Making `JsonPathMatch` fields `final` / immutable (separate bug assessment).
- SDK constraint bumps, dependency additions, or CI workflow changes.
