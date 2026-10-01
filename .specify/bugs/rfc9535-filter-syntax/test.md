# Test Report: rfc9535-filter-syntax (Issue #1)

**Result:** verified
**Suite:** `dart test` — **119/119 passed** · `dart analyze` — **no issues**
**Branch:** `fix/rfc9535-filter-syntax` @ 6d0676e

## Reproduction re-check (Step 2)

| Query (Amazon payload from issue #1)                       | Before            | After            |
| ---------------------------------------------------------- | ----------------- | ---------------- |
| `$[?match(key(@), "data-main-slot:search-result-.*")]`     | `[]`              | **2 matches** ✅ |
| `$[?(match(key(@), "data-main-slot:search-result-.*"))]`   | throws (`Bad state: match is not defined`) | **2 matches** ✅ |
| `$[?search(key(@), "search-result")]`                      | `[]`              | **2 matches** ✅ |

## Regression coverage

- **Pre-existing suite**: `test/json_path_plus_test.dart` — 90/90 green, zero
  regressions. Notably still green: paren-form filters, `@property` filters,
  `@`-scalar filters, `&&` filters, backtick properties, reverse slices,
  `!@` negation, `typeof null` — all the behaviors touched indirectly.
- **New suite**: `test/rfc9535_filter_test.dart` — 29 tests covering:
  - bare selectors: no-paren, spaced, string equality, logical operators,
    truthiness (only `null`/`false` falsy per RFC 9535), single-level nested
    bracket notation, bare+paren in one path;
  - `match()`/`search()`: full-vs-substring distinction, non-string → false,
    invalid regex → false (no throw), pattern spanning whole string;
  - `key()`: object keys, array indices (string form), `@property` parity,
    combined with `match()`;
  - `String.match()` method proxy (prefix and substring);
  - sandbox shadowing of built-ins (extension point).

## Behavioral notes recorded (verified intentional)

1. `match()` is a full match — `match(key(@), "^data-")` matches nothing by
   design (RFC 9535 §2.4.6); prefix patterns must use `data-.*`. Documented in
   README and pinned by a test.
2. Filter test expressions use RFC 9535 truthiness (`0`/`''` are truthy) —
   differs from JS truthiness of JSONPath-Plus; documented and pinned by a test.
3. Consecutive filter selectors drill into children (JSONPath-Plus semantics);
   combine conditions with `&&` instead of chaining `[?a][?b]`.
