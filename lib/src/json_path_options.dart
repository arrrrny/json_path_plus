import 'json_path_match.dart';

/// Options for evaluating a JSONPath expression.
class JsonPathOptions {
  /// The JSONPath expression string.
  final String path;

  /// The JSON object to evaluate.
  final Object json;

  /// Result type: 'value' (default), 'path', 'pointer', 'parent',
  /// 'parentProperty', or 'all'.
  final String resultType;

  /// Whether to flatten nested result arrays. Default false.
  final bool flatten;

  /// Whether to wrap single results in an array. Default true.
  final bool wrap;

  /// Variables available to code in filter expressions.
  /// 'path', 'parent', 'property', 'root', and 'v' are pre-set.
  final Map<String, Object?>? sandbox;

  /// Eval mode: 'safe' (default, uses a safe expression evaluator),
  /// 'native' (same as 'safe' in Dart),
  /// or `false` to disable eval entirely.
  final Object? eval;

  /// If true, errors in filter expression evaluation are silently ignored.
  final bool ignoreEvalErrors;

  /// Parent object (for root-level queries). Default null.
  final Object? parent;

  /// Parent property name (for root-level queries). Default null.
  final String? parentProperty;

  /// Optional callback invoked for every match.
  final void Function(Object? value, String type, JsonPathMatch full)?
      callback;

  /// Callback for the `@other()` type operator. Throws by default.
  final Object? Function(Object? value, List<String> path, Object? parent,
      String? parentProp)? otherTypeCallback;

  const JsonPathOptions({
    required this.path,
    required this.json,
    this.resultType = 'value',
    this.flatten = false,
    this.wrap = true,
    this.sandbox,
    this.eval = 'safe',
    this.ignoreEvalErrors = false,
    this.parent,
    this.parentProperty,
    this.callback,
    this.otherTypeCallback,
  });
}
