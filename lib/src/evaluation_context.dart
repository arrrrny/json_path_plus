/// Internal, per-evaluation state for a single `JSONPath` run.
///
/// One instance is created by `JSONPath._run` and threaded through
/// `_trace` / `_typeCheck` / `_doSlice` / `_filter` / `_dynamic` / `_output` /
/// `_cb` as an explicit argument. It replaced a set of static mutable fields on
/// `JSONPath`, which a re-entrant run would otherwise overwrite for the
/// remainder of the walk that invoked it — a re-entrant `JSONPath.evaluate`
/// (for example one made from inside a match `callback`, or from a function
/// invoked by a filter expression) can no longer observe or clobber the state
/// of its caller, so every run is isolated per call.
///
/// Not exported from `package:json_path_plus/json_path_plus.dart`; the public
/// API is unchanged.
class EvaluationContext {
  /// Result type of the enclosing options: `'value'`, `'path'`, `'pointer'`,
  /// `'parent'`, `'parentProperty'` or `'all'`.
  final String resultType;

  /// Eval mode of the enclosing options: `'safe'` (default), `'native'`, or
  /// `false` to forbid expression evaluation entirely.
  final Object? evalMode;

  /// Variables available to filter and dynamic expressions. Owned by this run
  /// alone: `_filter` and `_dynamic` write the current node's bindings into
  /// it before handing it to [SafeEval.evaluate].
  final Map<String, Object?> sandbox;

  /// Callback backing the `@other()` type operator. Never null — the run
  /// substitutes a throwing default when the options omit it.
  final Object? Function(
          Object? value, List<String> path, Object? parent, String? parentProp)?
      otherTypeCallback;

  /// Whether filter errors are silently ignored in this run.
  final bool ignoreEvalErrors;

  /// Set when a `^` parent selector is traced, and read by the post-chain of
  /// every ancestor `_trace` frame in this run. `^` is a terminal early-return
  /// with no user code of its own, so the last walk item that reaches it sets
  /// this after any interleaved user code (match callbacks, sandbox filter
  /// functions) has fired, and no user code runs between that set and the
  /// post-chain reads — a re-entrant run therefore has no observable window
  /// in which to clobber the flag.
  bool hasParentSelector = false;

  EvaluationContext({
    required this.resultType,
    required this.evalMode,
    required this.sandbox,
    required this.otherTypeCallback,
    required this.ignoreEvalErrors,
  });
}
