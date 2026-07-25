/// A matched JSONPath result. Mirrors the internal return object of JSONPath-Plus.
class JsonPathMatch {
  /// The path to the matched value, e.g. ['$', 'store', 'book', 0, 'title'].
  List<String> path;

  /// The matched value.
  Object? value;

  /// Parent object/array containing the matched value.
  Object? parent;

  /// Key or index of the matched value in its parent, or null for root.
  String? parentProperty;

  /// Whether an array expression (wildcard, slice, etc.) was involved.
  bool hasArrExpr;

  /// Internal: whether this result is a parent selector placeholder.
  bool isParentSelector;

  /// Internal: expression to continue tracing after parent selector.
  List<String>? parentSelectorExpr;

  /// JSON Pointer representation (only populated when resultType is 'all').
  String? pointer;

  /// Path string representation (only populated when resultType is 'all').
  String? pathString;

  JsonPathMatch({
    required this.path,
    this.value,
    this.parent,
    this.parentProperty,
    this.hasArrExpr = false,
    this.isParentSelector = false,
    this.parentSelectorExpr,
    this.pointer,
    this.pathString,
  });
}
