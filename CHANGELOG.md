## 1.2.0

- **Fixed: ordered comparisons never match incomparable types** — `<`, `>`, `<=`, `>=` used to degrade to `0 <op> 0` when the two operands were not comparable, so `$.items[?(@.name <= 5)]` wrongly selected string-valued `name` nodes (`0 <= 0` is `true`). Mixed-type operands now yield `false`, matching JS (`'abc' <= 5` is `false` via NaN comparison) and RFC 9535 typed comparison. This also covers booleans (JSON defines no ordering for them, so `true >= false` is now `false`) and `NaN` from filter arithmetic (`0/0 > 5`), which previously compared as greater than everything. `==`/`===`/`!=`/`!==` semantics are unchanged.
- **RFC 9535 filter selectors** — bare filter expressions `[?@.price > 10]` now work without wrapping parentheses (`[?(...)]` still supported). Standard filter syntax no longer needs workarounds when migrating from `json_path`.
- **`match()` and `search()` function extensions** — `match(value, pattern)` returns true iff the *entire* string matches the regex; `search(value, pattern)` matches substrings. Non-string values and invalid patterns yield `false` (never throw), per RFC 9535 §2.4.6–2.4.7.
- **`key()` function** — `key(@)` / `key()` returns the member key (or array index) of the current node in filters; equivalent to the JSONPath-Plus `@property` magic variable and the `json_path` package's `key()`.
- **`String.match(pattern)` method** in filter expressions — returns the first matching substring or `null`.
- **`BuiltInFunction` exported** — sandbox entries named `match`/`search`/`key` shadow the built-ins, enabling user-defined filter functions.
- Analyzer-clean (`dart analyze` reports zero issues); 121 tests green.

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
