## 2.0.0

This release folds in the previously-planned 1.2.0 work: **1.2.0 was never published to pub.dev, so its changes ship here under 2.0.0.**

### Breaking

- **`JSONPath.cache` removed** — the public mutable `Map<String, dynamic>` is gone. The compiled-path cache is now private (`_pathCache`), LRU-bounded at `JSONPath.cacheCapacity` (512). Inspect and clear it via `JSONPath.cacheSize`, `JSONPath.isCached()` and `JSONPath.clearCache()`. The old escape hatch for poking arbitrary entries into the memo is no longer available.

### Features

- **RFC 9535 filter selectors** — bare filter expressions `[?@.price > 10]` now work without wrapping parentheses (`[?(...)]` still supported). Standard filter syntax no longer needs workarounds when migrating from `json_path`.
- **`match()` and `search()` function extensions** — `match(value, pattern)` returns true iff the *entire* string matches the regex; `search(value, pattern)` matches substrings. Non-string values and invalid patterns yield `false` (never throw), per RFC 9535 §2.4.6–2.4.7.
- **`key()` function** — `key(@)` / `key()` returns the member key (or array index) of the current node in filters; equivalent to the JSONPath-Plus `@property` magic variable and the `json_path` package's `key()`.
- **Regex literals in filter expressions** — JS-style `/pattern/flags` literals are recognised and disambiguated from division by context, so `@.name.match(/^a/)` works as written instead of having to be rewritten as `@.name.match("^a")`. `match()`, `search()` and `String.match()` accept regex objects as well as string patterns; the RFC 9535 string form keeps its full-match semantics.
- **`String.match(pattern)` method** in filter expressions — returns the first matching substring or `null`.
- **`BuiltInFunction` exported** — sandbox entries named `match`/`search`/`key` shadow the built-ins, enabling user-defined filter functions.
- **Bounded path cache** — compiled paths are memoised in a private LRU instead of an unbounded public map, so long-running processes no longer grow without limit.

### Fixes

- **Ordered comparisons never matched incomparable types** — `<`, `>`, `<=`, `>=` used to degrade to `0 <op> 0` when the two operands were not comparable, so `$.items[?(@.name <= 5)]` wrongly selected string-valued `name` nodes (`0 <= 0` is `true`). Mixed-type operands now yield `false`, matching JS (`'abc' <= 5` is `false` via NaN comparison) and RFC 9535 typed comparison. This also covers booleans (JSON defines no ordering for them, so `true >= false` is now `false`) and `NaN` from filter arithmetic (`0/0 > 5`), which previously compared as greater than everything. `==`/`===`/`!=`/`!==` semantics are unchanged.
- **`@root` now actually works in filters** — `_filter` rewrites `@root` to `_$_root` but nothing ever bound that name in the sandbox, so every filter using the advertised `@root` variable threw `Bad state: _$_root is not defined` (or silently matched nothing under `ignoreEvalErrors: true`). It is now bound before evaluation.
- **Parenthesised filters containing `)]` inside a string literal** — `toPathArray` extracted filters with a non-greedy `\[(\??\(.*?\))\]` regex that stopped at the first `)` followed by `]`, even inside a string. `$[?(@.a == "x)]y")]` matched nothing. Extraction is now a balanced, quote-aware scan.
- **Literal property names shaped like `#N` were clobbered by filter placeholders** — any path that both contained a filter or dynamic sub-expression *and* referenced a literal `#<digits>` property resolved the property to the sub-expression (`$['#0']` alone worked only because the placeholder table was empty). Substitution is now marker-safe, and `%` is escaped so a literal `#%N%` property name cannot be clobbered either.
- **`toPathString` produced malformed path strings for keys containing quotes** — segments were wrapped in `'...'` with no escaping, so `toPathString([r'$', "a'b"])` emitted `$['a'b']`. Escaping is now applied on the way out and mirrored on the way in through `toPathArray`, so path strings round-trip for any consumer (logs, cross-process handoff, other parsers), not just in-process.

### Hardening

- **`SafeEval` resource limits** — expressions longer than 64 KiB (`SafeEval.maxExpressionLength`) or nested deeper than 256 descent frames (`SafeEval.maxNestingDepth`) now throw a `FormatException` instead of overflowing the stack (~5k nesting previously crashed). Depth is counted in recursive-descent frames and chain links, so parenthesis nesting caps around 127 levels. `FormatException` is the recoverable "reject this query" outcome; an uncaught `Error` is not. Filter-expression `Error`s are converted to `FormatException` and, under `ignoreEvalErrors: true`, swallowed as before.
- **Per-evaluation context instead of shared static state** — six static mutable fields (`_resultType`, `_evalMode`, `_sandbox`, `_otherTypeCallback`, `_hasParentSelector`, `_ignoreEvalErrors`) meant a re-entrant `JSONPath.evaluate` — for example one started from inside a `match` callback — overwrote the in-flight walk's state. State is now created per run and threaded explicitly. Not exported, so the public API is unchanged.

### Maintenance

- README's `JsonPathMatch` block documented a class that did not exist (a `paths` field, a `property` field, and `final` markers that the class does not use). It now mirrors the implementation field-for-field, with internal-only fields called out and the "`pointer`/`pathString` are populated only when `resultType` is `'all'`" behaviour documented.
- `lints` dev-dependency bumped `^3.0.0` → `^6.1.0` (and `test` → `^1.32.0`). No new diagnostics — the codebase was already clean across five minor lint versions.
- `analysis_options.yaml` moved off the bare `package:lints/recommended.yaml` floor: `always_declare_return_types`, `unawaited_futures`, `prefer_final_locals`, `omit_local_variable_types` and `avoid_dynamic_calls` are now enabled and enforced by CI's `dart analyze --fatal-infos`. `prefer_final_parameters` and `require_trailing_commas` were measured and rejected (210 and 206 diagnostics respectively).
- CI workflow added: `dart format --set-exit-if-changed`, `dart analyze --fatal-infos`, `dart test`.
- pub.dev `topics` tightened to `json`, `jsonpath`, `json-query`, `filter`, `expression`.

Analyzer-clean (`dart analyze --fatal-infos` reports zero issues); 230 tests green.

## 1.1.0

- **Separated `IndexExpr` from `MemberExpr`** — cleaner AST for computed property access (`obj[key]` vs `obj.key`), enabling bracket filter expressions and dynamic properties to work correctly alongside dot-notation member access.
- **Fixed reverse slice** — `$[::-1]` now correctly returns elements in reverse order with proper start/end defaults for negative step.
- **Fixed backtick-escaped properties** — `` $.book.`0` `` now correctly resolves literal property names.
- **Fixed `!@` negation** — standalone `@` replacement now uses a proper lookahead regex so `!@` correctly yields `!_$_v` for truthiness inversion.
- **Fixed `typeof null`** — returns `"null"` (JSONPath-correct) instead of JS-style `"undefined"`.
- **Zero failures** — all 90 tests pass.

## 1.0.0

- Initial release.
- Full-featured JSONPath query engine ported from [JSONPath-Plus](https://github.com/JSONPath-Plus/JSONPath).
- Basic path syntax: dot notation, bracket notation, wildcards, recursive descent (`..`).
- Filter expressions with `@property`, `@parent`, `@root`, `@path` and comparison operators.
- Type operators: `@string()`, `@number()`, `@boolean()`, `@integer()`, `@null()`, `@array()`, `@object()`, `@scalar()`, `@other()`.
- `~` property-name operator: returns the key name instead of value.
- `^` parent selector: returns the parent of the matched node.
- Array slices: Python-style `[start:end:step]`.
- Dynamic properties: `[(1+2)]` evaluates to index 3.
- Comma-separated keys: `[0,1]` selects multiple indices.
- Backtick-escaped properties: `` `0` `` for literal property lookup.
- Multiple result types: `value`, `path`, `pointer`, `parent`, `parentProperty`, `all`.
- Safe expression evaluator with no `dart:mirrors`, no `eval()`, no external dependencies.
- Sound null safety (Dart 3.x).
