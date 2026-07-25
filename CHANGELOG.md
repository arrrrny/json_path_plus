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
