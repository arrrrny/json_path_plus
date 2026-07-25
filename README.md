# json_path_plus

A Dart port of [JSONPath-Plus](https://github.com/JSONPath-Plus/JSONPath) — a full-featured JSONPath query engine.

## Features

- **Basic path syntax**: dot notation, bracket notation, wildcards, recursive descent (`..`)
- **Filter expressions**: `[?(@.price > 10)]` with `@property`, `@parent`, `@root`, `@path`
- **Type operators**: `@string()`, `@number()`, `@boolean()`, `@integer()`, `@null()`, `@array()`, `@object()`, `@scalar()`, `@other()`
- **`~` property-name operator**: returns the key name instead of value
- **`^` parent selector**: returns the parent of the matched node
- **Array slices**: Python-style `[start:end:step]`
- **Dynamic properties**: `[(1+2)]` evaluates to index 3
- **Comma-separated keys**: `[0,1]` selects multiple indices
- **Backtick-escaped properties**: `` `0` `` for literal property lookup
- **Safe expression evaluator**: No `dart:mirrors`, no `eval()`, no external dependencies

## Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  json_path_plus:
    path: path/to/json_path_plus
```

## Usage

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

// Simple query
final titles = JSONPath.query(r'$.store.book[*].title', data);
print(titles); // ['Sayings of the Century', 'Moby Dick', 'The Lord of the Rings']

// Filter: books over $10
final expensive = JSONPath.query(r'$.store.book[?(@.price > 10)].title', data);
print(expensive); // ['Moby Dick', 'The Lord of the Rings']

// Using full options
final result = JSONPath.evaluate(JsonPathOptions(
  path: r'$..book[?(@.price > 10)]',
  json: data,
  resultType: 'path',
));
print(result); // ['$['store']['book'][1]', '$['store']['book'][2]']
```

### Walgreens-style @property filter

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

## API

### `JSONPath.evaluate(options)`

Evaluate a JSONPath expression with full options.

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

Convert between path representations.

### `JsonPathOptions`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `path` | `String` | required | JSONPath expression |
| `json` | `Object` | required | JSON data |
| `resultType` | `String` | `'value'` | `'value'`, `'path'`, `'pointer'`, `'parent'`, `'parentProperty'`, `'all'` |
| `flatten` | `bool` | `false` | Flatten nested arrays |
| `wrap` | `bool` | `true` | Always return array |
| `sandbox` | `Map?` | `{}` | Variables for filter expressions |
| `eval` | `Object?` | `'safe'` | `'safe'`, `'native'`, `false` |
| `ignoreEvalErrors` | `bool` | `false` | Silently ignore eval errors |
| `callback` | `Function?` | `null` | Per-match callback |
| `otherTypeCallback` | `Function?` | throws | For `@other()` type |

## Constraints

- Zero external dependencies (only `dart:core`, `dart:math`, `dart:convert`)
- Sound null safety (Dart 3.x)
- No `dart:mirrors` (Flutter-compatible)
- No `eval()` or `Function.apply()` — uses a custom expression parser

## License

MIT (ported from JSONPath-Plus which is also MIT-licensed)
