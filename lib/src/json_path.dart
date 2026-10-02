import 'evaluation_context.dart';
import 'json_path_options.dart';
import 'json_path_match.dart';
import 'sandboxed_script.dart';
import 'dart:collection';
import 'dart:math';

class JSONPath {
  final JsonPathOptions? _opts;

  /// Upper bound on the number of compiled-path entries [_pathCache] retains.
  static const int cacheCapacity = 512;

  /// Compiled-path cache used by [toPathArray].
  ///
  /// Bounded by [cacheCapacity] and evicted least-recently-used first, so
  /// callers that build paths dynamically (interpolated keys, per-item
  /// selectors) cannot grow it without bound over the life of the process.
  /// Private so that external code cannot inject, mutate or silently drop
  /// individual entries; the read-only [cacheSize] / [isCached] helpers and
  /// the whole-cache [clearCache] are the supported public surface.
  static final LinkedHashMap<String, List<String>> _pathCache =
      LinkedHashMap<String, List<String>>();

  JSONPath({JsonPathOptions? opts}) : _opts = opts;

  /// Throwing default backing the `@other()` operator when the options omit
  /// [JsonPathOptions.otherTypeCallback]. Stateless, so a single tear-off is
  /// shared by every run instead of being re-allocated per evaluation.
  static Object? _defaultOtherTypeCallback(
      Object? val, List<String> path, Object? parent, String? prop) {
    throw ArgumentError(
      'You must supply an otherTypeCallback callback option with the @other() operator.',
    );
  }

  static dynamic evaluate(
    Object? pathOrOpts, [
    Object? json,
    void Function(Object?, String, JsonPathMatch)? callback,
    Object? Function(Object?, List<String>, Object?, String?)?
        otherTypeCallback,
  ]) {
    JsonPathOptions opts;
    if (pathOrOpts is JsonPathOptions) {
      opts = pathOrOpts;
    } else if (pathOrOpts is String) {
      opts = JsonPathOptions(
        path: pathOrOpts,
        json: json ?? {},
        callback: callback,
        otherTypeCallback: otherTypeCallback,
      );
    } else {
      throw ArgumentError('First argument must be String or JsonPathOptions');
    }
    return _run(opts);
  }

  static List<Object?> query(String path, Object json, {bool wrap = true}) {
    final result =
        evaluate(JsonPathOptions(path: path, json: json, wrap: wrap));
    if (result is List) return result.cast<Object?>();
    return [result];
  }

  dynamic evaluateOpts([JsonPathOptions? arg]) => _run(arg ?? _opts!);

  static dynamic _run(JsonPathOptions opts) {
    // All per-run state lives in this context, created fresh for every
    // evaluation, so a re-entrant run cannot disturb an in-flight one.
    final ctx = EvaluationContext(
      resultType: opts.resultType,
      evalMode: opts.eval,
      sandbox: Map<String, Object?>.from(opts.sandbox ?? {}),
      otherTypeCallback: opts.otherTypeCallback ?? _defaultOtherTypeCallback,
      ignoreEvalErrors: opts.ignoreEvalErrors,
    );
    // @root (JSONPath-Plus semantics) refers to the original document root.
    ctx.sandbox[r'_$_root'] = opts.json;

    Object? expr = opts.path;
    final json = opts.json;

    if (expr is List) {
      expr = toPathString(expr.map((e) => e.toString()).toList());
    }
    if (expr is String && expr.isEmpty) return null;

    final exprList = toPathArray(expr as String);
    if (exprList.isNotEmpty && exprList[0] == r'$' && exprList.length > 1) {
      exprList.removeAt(0);
    }

    final raw = _trace(ctx, exprList, json, [r'$'], opts.parent,
        opts.parentProperty, opts.callback, false, false);
    final result = raw.where((e) => !e.isParentSelector).toList();

    if (result.isEmpty) return opts.wrap ? <Object?>[] : null;
    if (!opts.wrap && result.length == 1 && !result[0].hasArrExpr) {
      return _output(ctx, result[0]);
    }
    return result.fold<List<Object?>>(<Object?>[], (acc, ea) {
      final v = _output(ctx, ea);
      if (opts.flatten && v is List) {
        acc.addAll(v);
      } else {
        acc.add(v);
      }
      return acc;
    });
  }

  static dynamic _output(EvaluationContext ctx, JsonPathMatch ea) {
    switch (ctx.resultType) {
      case 'all':
        ea.pointer = toPointer(ea.path);
        ea.pathString = toPathString(ea.path);
        return ea;
      case 'value':
        return ea.value;
      case 'parent':
        return ea.parent;
      case 'parentProperty':
        return ea.parentProperty;
      case 'path':
        return toPathString(ea.path);
      case 'pointer':
        return toPointer(ea.path);
      default:
        throw ArgumentError('Unknown result type: ${ctx.resultType}');
    }
  }

  static void _cb(EvaluationContext ctx, JsonPathMatch obj,
      void Function(Object?, String, JsonPathMatch)? cb, String type) {
    if (cb != null) cb(_output(ctx, obj), type, obj);
  }

  static List<JsonPathMatch> _trace(
    EvaluationContext ctx,
    List<String> expr,
    Object? val,
    List<String> path,
    Object? parent,
    String? parentPropName,
    void Function(Object?, String, JsonPathMatch)? callback,
    bool hasArrExpr,
    bool literalPriority,
  ) {
    if (expr.isEmpty) {
      final r = JsonPathMatch(
        path: List.from(path),
        value: val,
        parent: parent,
        parentProperty: parentPropName,
        hasArrExpr: hasArrExpr,
      );
      _cb(ctx, r, callback, 'value');
      return [r];
    }

    final loc = expr[0];
    final x = expr.sublist(1);
    final ret = <JsonPathMatch>[];

    void add(List<JsonPathMatch> es) => ret.addAll(es);

    if (loc == '*') {
      _walk(
          val,
          (m) => add(_trace(ctx, x, _get(val, m), _p(path, m), val, m, callback,
              true, true)));
    } else if (loc == '..') {
      add(_trace(ctx, x, val, path, parent, parentPropName, callback,
          hasArrExpr, false));
      _walk(val, (m) {
        final c = _get(val, m);
        if (_isObj(c)) {
          add(_trace(ctx, List.from(expr), c, _p(path, m), val, m, callback,
              true, false));
        }
      });
    } else if (loc == '^') {
      ctx.hasParentSelector = true;
      return [
        JsonPathMatch(
            path: path.sublist(0, path.length - 1),
            value: null,
            parent: null,
            parentProperty: null,
            hasArrExpr: hasArrExpr,
            isParentSelector: true,
            parentSelectorExpr: x)
      ];
    } else if (loc == '~') {
      final r = JsonPathMatch(
          path: _p(path, loc),
          value: parentPropName,
          parent: parent,
          parentProperty: null,
          hasArrExpr: hasArrExpr);
      _cb(ctx, r, callback, 'property');
      return [r];
    } else if (loc == r'$') {
      add(_trace(ctx, x, val, path, null, null, callback, hasArrExpr, false));
    } else if (RegExp(r'^(-?\d*):(-?\d*):?(-?\d*)$').hasMatch(loc)) {
      final s =
          _doSlice(ctx, loc, x, val, path, parent, parentPropName, callback);
      if (s != null) add(s);
    } else if (loc.startsWith('?(') && loc.endsWith(')')) {
      if (identical(ctx.evalMode, false)) {
        throw StateError('Eval [?(expr)] prevented.');
      }
      final code = loc.substring(2, loc.length - 1); // strip ?( and )
      _walk(val, (m) {
        if (_filter(ctx, code, _get(val, m), m, path, parent, parentPropName,
            ignoreErrors: ctx.ignoreEvalErrors)) {
          add(_trace(ctx, x, _get(val, m), _p(path, m), val, m, callback, true,
              false));
        }
      });
    } else if (loc.startsWith('(') && loc.endsWith(')')) {
      if (identical(ctx.evalMode, false)) {
        throw StateError('Eval [(expr)] prevented.');
      }
      final key = _dynamic(ctx, loc.substring(1, loc.length - 1), val,
          path.isNotEmpty ? path.last : '', parent, parentPropName);
      add(_trace(ctx, [key.toString(), ...x], val, path, parent, parentPropName,
          callback, hasArrExpr, false));
    } else if (loc.startsWith('@') && loc.endsWith('()')) {
      if (_typeCheck(ctx, loc.substring(1, loc.length - 2), val)) {
        final r = JsonPathMatch(
            path: List.from(path),
            value: val,
            parent: parent,
            parentProperty: parentPropName,
            hasArrExpr: hasArrExpr);
        _cb(ctx, r, callback, 'value');
        return [r];
      }
    } else if (loc.startsWith('`') && loc.length > 1) {
      final prop = loc.substring(1);
      if (_has(val, prop)) {
        add(_trace(ctx, x, _get(val, prop), _p(path, prop), val, prop, callback,
            hasArrExpr, true));
      }
    } else if (loc.contains(',')) {
      for (final part in loc.split(',')) {
        add(_trace(ctx, [part, ...x], val, path, parent, parentPropName,
            callback, true, false));
      }
    } else if (loc.startsWith('`') && loc.endsWith('`') && loc.length > 1) {
      final prop = loc.substring(1, loc.length - 1);
      if (_has(val, prop)) {
        add(_trace(ctx, x, _get(val, prop), _p(path, prop), val, prop, callback,
            hasArrExpr, true));
      }
    } else if (_has(val, loc)) {
      add(_trace(ctx, x, _get(val, loc), _p(path, loc), val, loc, callback,
          hasArrExpr, true));
    }

    if (ctx.hasParentSelector) {
      for (var t = 0; t < ret.length; t++) {
        if (ret[t].isParentSelector) {
          final tmp = _trace(ctx, ret[t].parentSelectorExpr ?? [], val,
              ret[t].path, parent, parentPropName, callback, hasArrExpr, false);
          if (tmp.length > 1) {
            ret[t] = tmp[0];
            for (var tt = 1; tt < tmp.length; tt++) {
              t++;
              ret.insert(t, tmp[tt]);
            }
          } else if (tmp.isNotEmpty) {
            ret[t] = tmp[0];
          } else {
            ret.removeAt(t);
            t--;
          }
        }
      }
    }
    return ret;
  }

  static bool _typeCheck(EvaluationContext ctx, String type, Object? val) {
    switch (type) {
      case 'scalar':
        return val == null || val is bool || val is num || val is String;
      case 'boolean':
        return val is bool;
      case 'string':
        return val is String;
      case 'undefined':
        return val == null;
      case 'function':
        return false;
      case 'integer':
        return val is int ||
            (val is double && val == val.truncateToDouble() && val.isFinite);
      case 'number':
        return val is num && val.isFinite;
      case 'nonFinite':
        return val is double && !val.isFinite;
      case 'object':
        return val != null && val is Map && val is! List;
      case 'array':
        return val is List;
      case 'null':
        return val == null;
      case 'other':
        final r = ctx.otherTypeCallback!(val, [], null, null);
        return r is bool ? r : false;
      default:
        throw ArgumentError('Unknown value type $type');
    }
  }

  static void _walk(Object? val, void Function(String) f) {
    if (val is List) {
      for (var i = 0; i < val.length; i++) {
        f(i.toString());
      }
    } else if (val is Map) {
      for (final k in val.keys) {
        f(k.toString());
      }
    }
  }

  static bool _has(Object? v, Object k) {
    if (v is Map) return v.containsKey(k);
    if (v is List && k is String) {
      final i = int.tryParse(k);
      return i != null && i >= 0 && i < v.length;
    }
    return false;
  }

  static Object? _get(Object? v, Object k) {
    if (v is Map) return v[k];
    if (v is List && k is String) {
      final i = int.tryParse(k);
      return (i != null) ? v[i] : null;
    }
    return null;
  }

  static List<String> _p(List<String> a, String s) => [...a, s];
  static bool _isObj(Object? v) => v != null && (v is Map || v is List);

  static List<JsonPathMatch>? _doSlice(
    EvaluationContext ctx,
    String loc,
    List<String> expr,
    Object? val,
    List<String> path,
    Object? parent,
    String? ppn,
    callback,
  ) {
    if (val is! List) return null;
    final len = val.length;
    final parts = loc.split(':');
    final step =
        (parts.length > 2 && parts[2].isNotEmpty) ? int.parse(parts[2]) : 1;
    if (step == 0) return [];
    // Defaults differ for forward vs reverse slices
    final defStart = step > 0 ? 0 : len - 1;
    final defEnd = step > 0 ? len : -1;
    var start = (parts[0].isNotEmpty) ? int.parse(parts[0]) : defStart;
    var end = (parts.length > 1 && parts[1].isNotEmpty)
        ? int.parse(parts[1])
        : defEnd;
    // Handle negative indices relative to length.
    // For reverse slices with default end (-1 sentinel), keep end at -1 so
    // the loop iterates down to index 0 (i > -1 means i=2,1,0).
    if (start < 0) start = max(0, len + start);
    if (end < 0) {
      // For forward slices, negative end means len + end.
      // For reverse slices, -1 end sentinel means "include index 0".
      end = step > 0 ? max(0, len + end) : -1;
    }
    start = min(step > 0 ? len : len - 1, start);
    if (step > 0) end = min(len, end);
    final ret = <JsonPathMatch>[];
    for (var i = start; (step > 0 ? i < end : i > end); i += step) {
      ret.addAll(_trace(ctx, [i.toString(), ...expr], val, path, parent, ppn,
          callback, true, false));
    }
    return ret;
  }

  /// Apply [rewrite] to every part of [code] that lies outside a string or
  /// regex literal.
  ///
  /// The `@` magic variables are rewritten textually, before tokenization, so
  /// without this an `@` *inside* a literal would be rewritten too — silently
  /// turning `/^a@/` into `/^a_$_v/` and making an email pattern match
  /// nothing. Literal boundaries come from the tokenizer, which already
  /// resolves the regex-vs-division ambiguity.
  static String _rewriteOutsideLiterals(
      String code, String Function(String chunk) rewrite) {
    final spans = Tokenizer.literalSpansOf(code);
    if (spans == null || spans.isEmpty) {
      // Nothing to protect: either no literals, or code that does not
      // tokenize — in which case the evaluator reports the syntax error.
      return rewrite(code);
    }
    final out = StringBuffer();
    var pos = 0;
    for (final span in spans) {
      if (span.start > pos) out.write(rewrite(code.substring(pos, span.start)));
      out.write(code.substring(span.start, span.end));
      pos = span.end;
    }
    if (pos < code.length) out.write(rewrite(code.substring(pos)));
    return out.toString();
  }

  /// Pull every bracketed filter/dynamic expression out of [expr] into [subx],
  /// replacing each with a `[#%n%]` placeholder.
  ///
  /// Handles both forms: `[(expr)]` / `[?(expr)]` (kept verbatim, leading `?`
  /// included) and the RFC 9535 `[? <expr>]` selector, which is normalized to
  /// `?(expr)` so downstream filter handling stays uniform. Bracket nesting is
  /// counted and string/regex literal spans are skipped, so a literal holding
  /// `]`, `[` or `)` — `/^[x\]]+$/`, `'a]b'` — cannot truncate the expression
  /// or terminate the bracket early.
  static String _extractBracketExpressions(String expr, List<String> subx) {
    final spans = Tokenizer.literalSpansOf(expr) ?? const [];
    final out = StringBuffer();
    var pos = 0;
    while (pos < expr.length) {
      // Jump straight to the next '[' that is not inside a literal.
      final open = _indexOfOutsideLiteral(expr, '[', pos, spans);
      if (open < 0) break;
      final close = _matchingBracket(expr, open, spans);
      if (close < 0) {
        // Unbalanced '[' — leave the rest as-is, as the old regexes did.
        break;
      }
      final inner = expr.substring(open + 1, close);
      final extracted = _filterSubExpression(inner);
      if (extracted == null) {
        // Not a filter/dynamic expression (e.g. a plain index) — copy through
        // and keep scanning after this bracket.
        out.write(expr.substring(pos, close + 1));
        pos = close + 1;
        continue;
      }
      out.write(expr.substring(pos, open));
      subx.add(extracted);
      // %#..% sentinel namespace — quoted properties get their '%' escaped
      // before substitution, so user data can never produce this shape
      // (issue #6).
      out.write('[#%${subx.length - 1}%]');
      pos = close + 1;
    }
    out.write(expr.substring(pos));
    return out.toString();
  }

  /// The subx form of a bracketed expression's contents, or null when the
  /// bracket holds neither a parenthesized expression nor a `[? ...]` filter
  /// selector. A parenthesized `[?(...)]`/`[(...)]` is returned verbatim; a bare
  /// `[? ...]` selector is wrapped as `?(...)`.
  static String? _filterSubExpression(String inner) {
    // Whitespace-insensitive: the paren/dynamic form may follow the bracket
    // with or without space (`[ ?(x)]` ≡ `[?(x)]`), and the bare form
    // likewise (`[ ? expr ]` ≡ `[?expr]`).
    final trimmed = inner.trimLeft();
    if (trimmed.startsWith('?(') || trimmed.startsWith('(')) {
      return trimmed;
    }
    if (!trimmed.startsWith('?')) return null;
    final body = trimmed.substring(1).trim();
    // `[?]` / `[? ]` carry no expression.
    if (body.isEmpty) return null;
    return '?($body)';
  }

  /// Index of the first [needle] at or after [from] that lies outside every
  /// literal span, or -1.
  static int _indexOfOutsideLiteral(
      String s, String needle, int from, List<({int start, int end})> spans) {
    var i = from;
    while (i < s.length) {
      final at = s.indexOf(needle, i);
      if (at < 0) return -1;
      if (!_insideLiteral(spans, at)) return at;
      i = at + 1;
    }
    return -1;
  }

  /// The index of the `]` closing the `[` at [open], or -1 when unbalanced.
  static int _matchingBracket(
      String s, int open, List<({int start, int end})> spans) {
    var depth = 0;
    var i = open;
    while (i < s.length) {
      if (_insideLiteral(spans, i)) {
        // Skip the whole literal — brackets inside it are not delimiters.
        i = spans.firstWhere((s) => s.start <= i && i < s.end).end;
        continue;
      }
      final ch = s[i];
      if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }
    return -1;
  }

  static bool _insideLiteral(List<({int start, int end})> spans, int index) =>
      spans.any((span) => span.start <= index && index < span.end);

  static bool _filter(EvaluationContext ctx, String code, Object? v, String vn,
      List<String> path, Object? parent, String? ppn,
      {bool ignoreErrors = false}) {
    final sandbox = ctx.sandbox;
    sandbox[r'_$_parentProperty'] = ppn;
    sandbox[r'_$_parent'] = parent;
    sandbox[r'_$_property'] = vn;
    sandbox[r'_$_v'] = v;
    // key(@) — RFC 9535-style member key (or array index) of the current
    // node; equivalent to the @property magic variable.
    sandbox['key'] = BuiltInFunction((_) => vn);
    if (code.contains('@path')) {
      sandbox[r'_$_path'] = toPathString([...path, vn]);
    }

    final script = _rewriteOutsideLiterals(code, (chunk) {
      var s = chunk
          .replaceAll('@parentProperty', r'_$_parentProperty')
          .replaceAll('@parent', r'_$_parent')
          .replaceAll('@property', r'_$_property')
          .replaceAll('@root', r'_$_root');
      // Replace all lone @ with _$_v (e.g. !@ → !_$_v, @ === 5 → _$_v === 5)
      s = s.replaceAllMapped(RegExp(r'@(?![a-zA-Z0-9_])'), (m) => r'_$_v');
      if (code.contains('@path')) s = s.replaceAll('@path', r'_$_path');
      return s;
    });

    try {
      final r = SafeEval.evaluate(script, sandbox);
      return r is bool ? r : (r != null && r != false);
    } on Error catch (e, st) {
      // Errors (StateError, StackOverflowError, ...) must not escape the
      // filter as crashes: swallow per ignoreEvalErrors, otherwise convert
      // to an exception callers can catch.
      if (ignoreErrors) return false;
      Error.throwWithStackTrace(
          FormatException('filter expression evaluation failed: $e'), st);
    } catch (e) {
      if (ignoreErrors) return false;
      rethrow;
    }
  }

  static Object? _dynamic(EvaluationContext ctx, String code, Object? val,
      Object lastPath, Object? parent, String? ppn) {
    final sandbox = ctx.sandbox;
    sandbox[r'_$_parentProperty'] = ppn;
    sandbox[r'_$_parent'] = parent;
    sandbox[r'_$_property'] = lastPath.toString();
    sandbox[r'_$_v'] = val;
    sandbox['key'] = BuiltInFunction((_) => lastPath.toString());

    // Replace @. @space @) @[ with _$_v prefix — skipping string and regex
    // literal spans, so a pattern keeps its own `@`.
    final script = _rewriteOutsideLiterals(code, (chunk) {
      var s = chunk
          .replaceAll('@parentProperty', r'_$_parentProperty')
          .replaceAll('@parent', r'_$_parent')
          .replaceAll('@property', r'_$_property')
          .replaceAll('@root', r'_$_root');
      s = s.replaceAllMapped(RegExp(r'@(\.)'), (m) => r'_$_v' + m[1]!);
      s = s.replaceAllMapped(RegExp(r'@(\s)'), (m) => r'_$_v' + m[1]!);
      s = s.replaceAllMapped(RegExp(r'@(\))'), (m) => r'_$_v' + m[1]!);
      s = s.replaceAllMapped(RegExp(r'@(\[)'), (m) => r'_$_v' + m[1]!);
      return s;
    });

    try {
      return SafeEval.evaluate(script, sandbox);
    } catch (e) {
      rethrow;
    }
  }

  // ── Public static utility methods ──

  /// Number of compiled-path entries currently retained by the cache.
  static int get cacheSize => _pathCache.length;

  /// Whether [expr] currently has a compiled-path entry retained.
  static bool isCached(String expr) => _pathCache.containsKey(expr);

  /// Drops every cached path, releasing the retained memory.
  ///
  /// Deliberately a whole-cache operation: single entries are an internal
  /// detail, so callers cannot evict or inject paths piecemeal.
  static void clearCache() => _pathCache.clear();

  /// Returns the cached path array for [expr] and promotes it to
  /// most-recently-used, or `null` when nothing is cached for it.
  ///
  /// The returned list is the live internal entry — callers must not mutate
  /// it; copy it (e.g. `List<String>.from(...)`) before handing it out.
  static List<String>? _cacheLookup(String expr) {
    final cached = _pathCache.remove(expr);
    if (cached == null) return null;
    _pathCache[expr] = cached;
    return cached;
  }

  /// Caches [pathArray] for [expr], evicting the least recently used entry
  /// when the cache is already at [cacheCapacity].
  static void _cacheStore(String expr, List<String> pathArray) {
    _pathCache[expr] = pathArray;
    if (_pathCache.length > cacheCapacity) {
      _pathCache.remove(_pathCache.keys.first);
    }
  }

  static List<String> toPathArray(String expr) {
    final cached = _cacheLookup(expr);
    if (cached != null) {
      return List<String>.from(cached);
    }
    final subx = <String>[];
    var n = expr.replaceAllMapped(
      RegExp(
          r'@(?:null|boolean|number|string|integer|undefined|nonFinite|scalar|array|object|function|other)\(\)'),
      (m) => ';${m[0]};',
    );
    // Normalize backtick-escaped properties: .`ident` → ['ident']
    // so they survive the subsequent regex-based tokenization.
    n = n.replaceAllMapped(RegExp(r"""\.`([^`]*)`"""), (m) => "['${m[1]}']");
    // Pull bracketed filter/dynamic expressions out into subx, replacing each
    // with a [#%n%] placeholder. Scanned rather than regex-matched: a regex
    // literal may contain `]`, `)` or `[` (`/^[x\]]+$/`), which truncated the
    // old alternation mid-expression, and quoted strings may contain brackets
    // too (`)]` inside a string literal, issue #5). Literal spans come from
    // the tokenizer, bracket nesting from a depth counter. Placeholders use
    // the %#..% sentinel namespace so they cannot collide with literal quoted
    // property names such as '#0' (issue #6).
    n = _extractBracketExpressions(n, subx);
    // Escape dots/tildes in bracket-quoted properties. Percent signs are
    // escaped first so the placeholder sentinels below cannot be confused
    // with user data: a literal '#%0%' property name must survive the
    // substitution pass untouched (issue #6). Escaping '%' first also keeps
    // the '.'/'~' sentinels from being double-escaped.
    n = n.replaceAllMapped(
        RegExp(r"""\[['"]([^'"]*?)['"]\]"""),
        (m) =>
            "['${m[1]!.replaceAll('%', '%@pct@%').replaceAll('.', '%@%').replaceAll('~', '%%@@%%')}']");
    n = n.replaceAll('~', ';~;');
    n = n.replaceAll(RegExp(r"""['"]?\.['"]?(?![^[]*\])|\[['"]?"""), ';');
    n = n.replaceAll('%@%', '.');
    n = n.replaceAll('%%@@%%', '~');
    n = n.replaceAllMapped(RegExp(r'(?:;)?(\^+)(?:;)?'), (m) {
      final ups = m[1]!;
      return ';${ups.split('').join(';')};';
    });
    n = n.replaceAll(RegExp(r';;;|;;'), ';..;');
    // Remove trailing semicolons and quotes (matching JS: /;$|'?\]|'$/u)
    n = n.replaceAll(RegExp(r''';$|'?]|'$'''), '');

    final parts = n.split(';');
    // Substitute placeholders by splicing them into the token, so a
    // placeholder followed by a tokenization remainder keeps the remainder
    // instead of being replaced wholesale (issue #6).
    //
    // The '%' escape is undone on the token's own segments only, never on the
    // spliced-in filter text: a filter whose expression literally contains
    // '%@pct@%' must survive verbatim. Every token is restored, including
    // placeholder-free ones — '$['#%0%']' alone carries no placeholder, so an
    // early return there would leak the escape sentinel.
    final placeholder = RegExp(r'#%(\d+)%');
    String restorePct(String segment) => segment.replaceAll('%@pct@%', '%');
    final exprList = parts.map((e) {
      if (subx.isEmpty || !e.contains('#%')) return restorePct(e);
      final spliced = StringBuffer();
      var cursor = 0;
      for (final m in placeholder.allMatches(e)) {
        spliced.write(restorePct(e.substring(cursor, m.start)));
        final idx = int.parse(m[1]!);
        spliced.write(idx < subx.length ? subx[idx] : m[0]!);
        cursor = m.end;
      }
      spliced.write(restorePct(e.substring(cursor)));
      return spliced.toString();
    }).toList();
    _cacheStore(expr, exprList);
    return List<String>.from(exprList);
  }

  static String toPathString(List<String> pathArr) {
    if (pathArr.isEmpty) return r'$';
    var p = r'$';
    for (var i = 1; i < pathArr.length; i++) {
      if (!RegExp(r'^(~|\^|@.*?\(\))$').hasMatch(pathArr[i])) {
        p += RegExp(r'^[0-9*]+$').hasMatch(pathArr[i])
            ? '[${pathArr[i]}]'
            : "['${pathArr[i]}']";
      }
    }
    return p;
  }

  static String toPointer(List<String> path) {
    var p = '';
    for (var i = 1; i < path.length; i++) {
      if (!RegExp(r'^(~|\^|@.*?\(\))$').hasMatch(path[i])) {
        p +=
            '/${path[i].toString().replaceAll('~', '~0').replaceAll('/', '~1')}';
      }
    }
    return p;
  }
}
