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
