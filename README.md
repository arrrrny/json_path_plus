# json_path_plus

A Dart port of [JSONPath-Plus](https://github.com/JSONPath-Plus/JSONPath) — a full-featured JSONPath query engine with filter expressions, type operators, array slices, and safe expression evaluation.

[![pub package](https://img.shields.io/pub/v/json_path_plus.svg)](https://pub.dev/packages/json_path_plus)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart SDK](https://img.shields.io/badge/sdk-3.0%2B-blue)](https://dart.dev/get-dart)
[![Powered by ZikZak AI](https://img.shields.io/badge/Powered%20by-ZikZak%20AI-8A2BE2?style=flat-square&logo=heart)](https://zuzu.dev)

---

## Features

- **Basic path syntax**: dot notation, bracket notation, wildcards, recursive descent (`..`)
- **Filter expressions**: `[?(@.price > 10)]` with `@property`, `@parent`, `@root`, `@path`
- **RFC 9535 filters**: bare filter selectors `[?@.price > 10]` (no parentheses) plus the standard `match()`, `search()`, and `key()` function extensions
- **Type operators**: `@string()`, `@number()`, `@boolean()`, `@integer()`, `@null()`, `@array()`, `@object()`, `@scalar()`, `@other()`
- **`~` property-name operator**: returns the key name instead of value
- **`^` parent selector**: returns the parent of the matched node
- **Array slices**: Python-style `[start:end:step]`
- **Dynamic properties**: `[(1+2)]` evaluates to index 3
- **Comma-separated keys**: `[0,1]` selects multiple indices
- **Backtick-escaped properties**: `` `0` `` for literal property lookup
- **Multiple result types**: `value`, `path`, `pointer`, `parent`, `parentProperty`, `all`
- **Safe expression evaluator**: No `dart:mirrors`, no `eval()`, no external dependencies

## Getting started

### Install

Add to your `pubspec.yaml`:

```yaml
dependencies:
  json_path_plus: ^1.0.0
```

Then run:

```sh
dart pub get
```

### Requirements

- Dart SDK 3.0+ (sound null safety)
- Zero external runtime dependencies
- Flutter-compatible (no `dart:mirrors`)

## Usage

### Basic queries

```dart
import 'package:json_path_plus/json_path_plus.dart';

final data = {
  'store': {
    'book': [
      {'title': 'Sayings of the Century', 'price': 8.95},
      {'title': 'Moby Dick', 'price': 12.99},
      {'title': 'The Lord of the Rings', 'price': 22.99},
    ],
  },
};

// Simple query — returns all titles
final titles = JSONPath.query(r'$.store.book[*].title', data);
print(titles); // ['Sayings of the Century', 'Moby Dick', 'The Lord of the Rings']

// Filter: books over $10
final expensive = JSONPath.query(r'$.store.book[?(@.price > 10)].title', data);
print(expensive); // ['Moby Dick', 'The Lord of the Rings']

// With full options — get paths instead of values
final result = JSONPath.evaluate(JsonPathOptions(
  path: r'$..book[?(@.price > 10)]',
  json: data,
  resultType: 'path',
));
print(result); // ["$['store']['book'][1]", "$['store']['book'][2]"]
```

### RFC 9535 filter selectors and functions

Standard (RFC 9535) filter syntax works without wrapping parentheses, and the
standard function extensions are available inside filters:

```dart
final data = {
  'data-client-side-metrics-info': {'html': 'foo'},
  'data-main-slot:search-result-2': {'asin': 'B00KHB2ZIW'},
  'data-main-slot:search-result-3': {'asin': 'B0DCZS98ZT'},
};

// Bare filter selector — [? <expr>] with no wrapping parentheses
final cheap = JSONPath.query(r'$[?@.price > 10]', products);

// match(value, pattern) — the ENTIRE string must match the regex
final slots = JSONPath.query(
  r'$[?match(key(@), "data-main-slot:search-result-.*")]',
  data,
);
print(slots.length); // 2

// search(value, pattern) — the string must CONTAIN a match
final hits = JSONPath.query(r'$[?search(key(@), "search-result")]', data);

// key() — the member key (or array index) of the current node;
// equivalent to the JSONPath-Plus magic variable @property
final byKey = JSONPath.query(r'$[?key(@) === "b"]', {'a': 1, 'b': 2});
print(byKey); // [2]
```

RFC 9535 semantics notes:

- `match()` requires the **full** string to match (prefix patterns need `.*`); `search()` matches substrings.
- Both functions return `false` (never throw) when the first argument is not a string or the pattern is an invalid regex.
- In filter test expressions only `null` and `false` are falsy — `0` and `''` are truthy (per RFC 9535, unlike JS truthiness).
- Sandbox entries named `match` / `search` shadow the built-ins, which is also how you can supply custom filter functions (wrap them in `BuiltInFunction`).

### Walgreens-style `@property` filter

Match keys dynamically using `@property` in filter expressions:

```dart
final data = {
  'productInfo': {
    'filmStripUrl': [
      {'stripUrl1': '...', 'zoomImageUrl1': '//pics.example.com/image1.jpg'},
      {'stripUrl2': '...', 'zoomImageUrl2': '//pics.example.com/image2.jpg'},
    ],
  },
};

final zoomUrls = JSONPath.evaluate(JsonPathOptions(
  path: r'$.productInfo.filmStripUrl[*][?(@property.indexOf("zoomImageUrl") === 0)]',
  json: data,
));
print(zoomUrls); // ['//pics.example.com/image1.jpg', '//pics.example.com/image2.jpg']
```

### Array slice

```dart
final sliced = JSONPath.query(r'$[1:4:2]', [0, 1, 2, 3, 4, 5]);
print(sliced); // [1, 3]
```

### Type operator filter

```dart
final strings = JSONPath.query(
  r'$[?(@string())]',
  ['hello', 42, true, null, 'world'],
);
print(strings); // ['hello', 'world']
```

## API

### `JSONPath.evaluate(options)`

The main evaluation entry point. Accepts either a `JsonPathOptions` object or positional arguments.

```dart
static dynamic evaluate(
  Object? pathOrOpts, [
  Object? json,
  void Function(Object?, String, JsonPathMatch)? callback,
  Object? Function(Object?, List<String>, Object?, String?)? otherTypeCallback,
])
```

### `JSONPath.query(path, json, {wrap})`

Shorthand for value-only queries. Always returns `List<Object?>`.

```dart
static List<Object?> query(String path, Object json, {bool wrap = true})
```

### `JSONPath.toPathArray(expr)` / `toPathString(path)` / `toPointer(path)`

Convert between path representations:

```dart
JSONPath.toPathArray(r"$['store']['book'][0]['title']");
// → ['$', 'store', 'book', '0', 'title']

JSONPath.toPathString(['$', 'store', 'book', '0', 'title']);
// → "$['store']['book'][0]['title']"

JSONPath.toPointer(['$', 'store', 'book', '0', 'title']);
// → '/store/book/0/title'
```

### Path cache

`toPathArray` memoizes compiled paths internally. The cache is private and
bounded: it retains at most `JSONPath.cacheCapacity` (512) entries and evicts
the least recently used one when full, so workloads that build paths
dynamically (interpolated keys, per-item selectors) cannot grow it without
bound. Only read-only inspection is exposed:

```dart
JSONPath.cacheSize;              // → entries currently retained
JSONPath.isCached(r'$.a.b');     // → true if that path is cached
JSONPath.clearCache();           // → drop every cached path
```

### `JsonPathOptions`

| Field               | Type        | Default   | Description                                                               |
| ------------------- | ----------- | --------- | ------------------------------------------------------------------------- |
| `path`              | `String`    | required  | JSONPath expression                                                       |
| `json`              | `Object`    | required  | JSON data                                                                 |
| `resultType`        | `String`    | `'value'` | `'value'`, `'path'`, `'pointer'`, `'parent'`, `'parentProperty'`, `'all'` |
| `flatten`           | `bool`      | `false`   | Flatten nested arrays                                                     |
| `wrap`              | `bool`      | `true`    | Always return array                                                       |
| `sandbox`           | `Map?`      | `{}`      | Variables for filter expressions                                          |
| `eval`              | `Object?`   | `'safe'`  | `'safe'`, `'native'`, `false`                                             |
| `ignoreEvalErrors`  | `bool`      | `false`   | Silently ignore eval errors                                               |
| `callback`          | `Function?` | `null`    | Per-match callback                                                        |
| `otherTypeCallback` | `Function?` | throws    | For `@other()` type                                                       |

### `JsonPathMatch`

Returned by `JSONPath.evaluate` when `resultType: 'all'`, and passed to the
`callback` option.

```dart
class JsonPathMatch {
  List<String> path;               // Path components, e.g. ['$', 'store', 'book', 0]
  Object? value;                   // The matched value
  Object? parent;                  // Object/array containing the matched value
  String? parentProperty;          // Key or index within parent; null for root
  bool hasArrExpr;                 // Whether a wildcard/slice/array expr was involved
  String? pointer;                 // JSON Pointer; only populated when resultType is 'all'
  String? pathString;              // Path string; only populated when resultType is 'all'

  // Internal to the engine — not part of the public contract:
  bool isParentSelector;
  List<String>? parentSelectorExpr;
}
```

Note there is no `property` field — the member key is `parentProperty`.
`pointer` and `pathString` are populated only when `resultType` is `'all'`.

### `SafeEval`

The safe expression evaluator for filter conditions. Supports arithmetic, comparison,
logical operators, and string concatenation — without `dart:mirrors` or `eval()`.

```dart
final result = SafeEval.evaluate('1 + 2 * 3 > 5 && "hello" + " world"');
// → true
```

## Constraints

- **Zero external runtime dependencies** (only `dart:core`, `dart:math`, `dart:convert`)
- **Sound null safety** (Dart 3.x, SDK `>=3.0.0 <4.0.0`)
- **No `dart:mirrors`** (Flutter-compatible)
- **No `eval()` or `Function.apply()`** — uses a custom expression parser

## Security notes

- **Resource limits** — `SafeEval` refuses expressions longer than 64 KiB
  (`SafeEval.maxExpressionLength`) or nested deeper than 256 descent
  frames (`SafeEval.maxNestingDepth`); both throw `FormatException`
  (`expression too long` / `expression too deeply nested`) instead of
  crashing with a `StackOverflowError`. Depth is counted in recursive-descent
  frames and chain links, not uniform nesting levels — each parenthesis
  level costs two frames (parenthesized nesting caps at ~127 levels), and
  every member/index/call chain link or binary operator counts one, so
  evaluation recursion stays bounded too. If your filter or dynamic
  expressions ever embed untrusted input, treat `FormatException` as
  "reject this query" — an uncaught `Error` is not a recoverable outcome.
- **ReDoS caveat for interpolated regex patterns** — `match()`, `search()`,
  and `.match()` compile their pattern with Dart's `RegExp`. Patterns
  embedded in the path string are authored by the developer and considered
  trusted, but a pattern interpolated from external input (user data, remote
  config) can be pathological and hang evaluation — Dart's `RegExp` offers
  no match-timeout knob. If patterns ever come from untrusted sources, cap
  their length (a few hundred characters is a practical ceiling), restrict
  them to known-safe constructs, and/or run the query in an isolate you can
  kill.

## Similar packages

- [`json_path`](https://pub.dev/packages/json_path) — Another JSONPath implementation for Dart with a different feature set
- [`json_path_plus`](https://pub.dev/packages/json_path_plus) — This package, a Dart port of JSONPath-Plus with extended operators
- [`json5_plus`](https://pub.dev/packages/json5_plus) — JSON5 parser (by the same team)
- [`zikzak_json`](https://pub.dev/packages/zikzak_json) — Best-effort JSON parser with simdjson fallback (by the same team)

---

## Powered by ZikZak AI

json_path_plus is developed by **ZikZak AI** to serve as the JSONPath query engine for high-throughput data extraction workloads.

- 🌐 [zuzu.dev](https://zuzu.dev)
- 🐙 [GitHub](https://github.com/arrrrny/json_path_plus)
- 🐛 [Issue Tracker](https://github.com/arrrrny/json_path_plus/issues)

## Sponsors

[![https://zuzu.dev](./assets/zikzak-ai.png)](https://zuzu.dev) [![Sponsored by ZikZak AI](https://img.shields.io/badge/Sponsored%20by-ZikZak%20AI-8A2BE2?style=flat-square&logo=heart)](https://zuzu.dev)

Thanks to ZikZak AI for sponsoring this project!

ZikZak AI is an AI-Powered Price Comparison app that you scan barcodes, and discover amazing savings instantly. Your personal shopping assistant that never sleeps.

<a href="https://apps.apple.com/tr/app/zik-zak/id1563425450"><img src="https://zuzu.dev/app-store-badge.png" width="160" style="margin-right: 8px;"></a>
<a href="https://play.google.com/store/apps/details?id=dev.zuzu.zingo"><img src="https://zuzu.dev/google-play-badge.png" width="160"></a>

---

Licensed under the [MIT License](LICENSE).
