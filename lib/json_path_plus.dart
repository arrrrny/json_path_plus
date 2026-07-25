/// A Dart port of JSONPath-Plus — full-featured JSONPath query engine.
///
/// JSONPath-Plus is an MIT-licensed implementation of the JSONPath query
/// language with extensions: type operators (`@string()`, `@number()`, etc.),
/// filter expressions with `@property`, `@parent`, `@root`, `@path` variables,
/// the `~` property-name operator, the `^` parent-selector operator,
/// Python-style array slices, and dynamic property evaluation via `[(expr)]`.
///
/// ```dart
/// import 'package:json_path_plus/json_path_plus.dart';
///
/// final data = {
///   'store': {
///     'book': [
///       {'title': 'A', 'price': 10},
///       {'title': 'B', 'price': 20},
///     ],
///   },
/// };
///
/// // Simple query
/// final titles = JSONPath.query(r'$.store.book[*].title', data);
/// print(titles); // ['A', 'B']
///
/// // Filter expression
/// final filtered = JSONPath.query(
///   r'$.store.book[?(@.price > 15)].title',
///   data,
/// );
/// print(filtered); // ['B']
///
/// // Using options
/// final result = JSONPath.evaluate(JsonPathOptions(
///   path: r'$..title',
///   json: data,
///   resultType: 'path',
/// ));
/// print(result); // [$['store']['book'][0]['title'], $['store']['book'][1]['title']]
/// ```
library;

export 'src/json_path.dart';
export 'src/json_path_match.dart';
export 'src/json_path_options.dart';
export 'src/sandboxed_script.dart' show SafeEval;
