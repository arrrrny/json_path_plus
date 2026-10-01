# Issue #1: Support RFC 9535 filter syntax: [?...] without parens, key(@), and match()

- **State:** OPEN
- **Author:** arrrrrny (Ahmet TOK)
- **URL:** https://github.com/arrrrny/json_path_plus/issues/1

### Problem

Scraper configurations migrating to or using `json_path_plus` that contain RFC 9535 standard filter expressions fail to match. For example:

```jsonpath
$[?match(key(@), "data-main-slot:search-result-.*")]
```

On a payload like:
```json
{
  "data-client-side-metrics-info": { ... },
  "data-main-slot:search-result-2": { "asin": "B00KHB2ZIW", "html": "..." },
  "data-main-slot:search-result-3": { "asin": "B0DCZS98ZT", "html": "..." }
}
```

This returns `[]` (0 matches) in `json_path_plus`, whereas RFC 9535 implementations (`json_path`) return the 2 matching maps.

### Root Causes

1. **Filter Expression Tokenization**: in `lib/src/json_path.dart` (`toPathArray`), the bracket regex `\[(\??\(.*?\))\]` requires parentheses immediately after `?` (`[?(...)]`). RFC 9535 defines filter selectors as `[? <logical-expr> ]` without requiring outer parentheses. As a result, `[?match(...)]` is not recognized as a filter and is instead treated as a literal property lookup.

2. **Undefined `key(@)` function**: even when wrapped in parentheses `$[?(match(key(@), "..."))]`, the sandbox evaluator throws `Bad state: match is not defined` / `key is not defined`. In the reference `json_path` implementation, `key(@)` retrieves the member key of the current object being filtered. In JSONPath-Plus, this is accessed via the magic identifier `@property`.

3. **Undefined `match()` function / regex matching in `sandboxed_script.dart`**: there is no global `match(target, regexPattern)` function, no `.match()` method on `String` in `_MethodProxy`, and the tokenizer does not support `/regex/` literals.

### Minimal Reproduction

```dart
import 'package:json_path_plus/json_path_plus.dart';

void main() {
  final map = {
    'data-client-side-metrics-info': {'html': 'foo'},
    'data-main-slot:search-result-2': {'asin': 'B00KHB2ZIW'},
    'data-main-slot:search-result-3': {'asin': 'B0DCZS98ZT'},
  };

  final selector = r'$[?match(key(@), "data-main-slot:search-result-.*")]';
  final result = JSONPath.query(selector, map, wrap: true);
  print(result); // Expected: 2 items, Actual: []
}
```

### Suggested Fixes

1. Update the bracket regex in `json_path.dart` to recognize `[? ... ]` even without wrapping parentheses, normalizing it into a filter expression.
2. In `sandboxed_script.dart`: provide `key(@)` / `key()` as an alias for `@property`; provide built-in `match(str, pattern)` and `search(str, pattern)` functions per RFC 9535; optionally add `.match(pattern)` to `String`'s `_MethodProxy`.
