import 'json_path_options.dart';
import 'json_path_match.dart';
import 'sandboxed_script.dart';
import 'dart:math';

class JSONPath {
  JsonPathOptions? _opts;
  static final Map<String, dynamic> cache = {};

  // Mutable static state set before each evaluate call
  static String _resultType = 'value';
  static Object? _evalMode = 'safe';
  static Map<String, Object?> _sandbox = {};
  static Object? Function(Object?, List<String>, Object?, String?)?
      _otherTypeCallback;
  static bool _hasParentSelector = false;
  static bool _ignoreEvalErrors = false;

  JSONPath({JsonPathOptions? opts}) : _opts = opts;

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
    final result = evaluate(JsonPathOptions(path: path, json: json, wrap: wrap));
    if (result is List) return result.cast<Object?>();
    return [result];
  }

  dynamic evaluateOpts([JsonPathOptions? arg]) => _run(arg ?? _opts!);

  static dynamic _run(JsonPathOptions opts) {
    _resultType = opts.resultType;
    _evalMode = opts.eval;
    _sandbox = Map<String, Object?>.from(opts.sandbox ?? {});
    _otherTypeCallback = opts.otherTypeCallback ??
        (val, path, parent, prop) {
          throw ArgumentError(
            'You must supply an otherTypeCallback callback option with the @other() operator.',
          );
        };
    _hasParentSelector = false;
    _ignoreEvalErrors = opts.ignoreEvalErrors;

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
    _hasParentSelector = false;

    final raw = _trace(exprList, json, [r'$'], opts.parent,
        opts.parentProperty, opts.callback, false, false);
    final result = raw.where((e) => !e.isParentSelector).toList();

    if (result.isEmpty) return opts.wrap ? <Object?>[] : null;
    if (!opts.wrap && result.length == 1 && !result[0].hasArrExpr) {
      return _output(result[0]);
    }
    return result.fold<List<Object?>>(<Object?>[], (acc, ea) {
      final v = _output(ea);
      if (opts.flatten && v is List) {
        acc.addAll(v);
      } else {
        acc.add(v);
      }
      return acc;
    });
  }

  static dynamic _output(JsonPathMatch ea) {
    switch (_resultType) {
      case 'all':
        ea.pointer = toPointer(ea.path);
        ea.pathString = toPathString(ea.path);
        return ea;
      case 'value': return ea.value;
      case 'parent': return ea.parent;
      case 'parentProperty': return ea.parentProperty;
      case 'path': return toPathString(ea.path);
      case 'pointer': return toPointer(ea.path);
      default: throw ArgumentError('Unknown result type: $_resultType');
    }
  }

  static void _cb(JsonPathMatch obj, void Function(Object?, String, JsonPathMatch)? cb, String type) {
    if (cb != null) cb(_output(obj), type, obj);
  }

  static List<JsonPathMatch> _trace(
    List<String> expr, Object? val, List<String> path,
    Object? parent, String? parentPropName,
    void Function(Object?, String, JsonPathMatch)? callback,
    bool hasArrExpr, bool literalPriority,
  ) {
    if (expr.isEmpty) {
      final r = JsonPathMatch(
        path: List.from(path), value: val, parent: parent,
        parentProperty: parentPropName, hasArrExpr: hasArrExpr,
      );
      _cb(r, callback, 'value');
      return [r];
    }

    final loc = expr[0];
    final x = expr.sublist(1);
    final ret = <JsonPathMatch>[];

    void add(List<JsonPathMatch> es) => ret.addAll(es);

    if (loc == '*') {
      _walk(val, (m) => add(_trace(x, _get(val, m), _p(path, m), val, m, callback, true, true)));
    } else if (loc == '..') {
      add(_trace(x, val, path, parent, parentPropName, callback, hasArrExpr, false));
      _walk(val, (m) {
        final c = _get(val, m);
        if (_isObj(c)) add(_trace(List.from(expr), c, _p(path, m), val, m, callback, true, false));
      });
    } else if (loc == '^') {
      _hasParentSelector = true;
      return [JsonPathMatch(path: path.sublist(0, path.length - 1), value: null,
        parent: null, parentProperty: null, hasArrExpr: hasArrExpr,
        isParentSelector: true, parentSelectorExpr: x)];
    } else if (loc == '~') {
      final r = JsonPathMatch(path: _p(path, loc), value: parentPropName,
        parent: parent, parentProperty: null, hasArrExpr: hasArrExpr);
      _cb(r, callback, 'property');
      return [r];
    } else if (loc == r'$') {
      add(_trace(x, val, path, null, null, callback, hasArrExpr, false));
    } else if (RegExp(r'^(-?\d*):(-?\d*):?(\d*)$').hasMatch(loc)) {
      final s = _doSlice(loc, x, val, path, parent, parentPropName, callback);
      if (s != null) add(s);
    } else if (loc.startsWith('?(') && loc.endsWith(')')) {
      if (identical(_evalMode, false)) throw StateError('Eval [?(expr)] prevented.');
      final code = loc.substring(2, loc.length - 1); // strip ?( and )
      _walk(val, (m) {
        if (_filter(code, _get(val, m), m, path, parent, parentPropName, ignoreErrors: _ignoreEvalErrors)) {
          add(_trace(x, _get(val, m), _p(path, m), val, m, callback, true, false));
        }
      });
    } else if (loc.startsWith('(') && loc.endsWith(')')) {
      if (identical(_evalMode, false)) throw StateError('Eval [(expr)] prevented.');
      final key = _dynamic(loc.substring(1, loc.length - 1), val,
        path.isNotEmpty ? path.last : '', parent, parentPropName);
      add(_trace([key.toString(), ...x], val, path, parent, parentPropName, callback, hasArrExpr, false));
    } else if (loc.startsWith('@') && loc.endsWith('()')) {
      if (_typeCheck(loc.substring(1, loc.length - 2), val)) {
        final r = JsonPathMatch(path: List.from(path), value: val,
          parent: parent, parentProperty: parentPropName, hasArrExpr: hasArrExpr);
        _cb(r, callback, 'value');
        return [r];
      }
    } else if (loc.startsWith('`') && loc.length > 1) {
      final prop = loc.substring(1);
      if (_has(val, prop)) add(_trace(x, _get(val, prop), _p(path, prop), val, prop, callback, hasArrExpr, true));
    } else if (loc.contains(',')) {
      for (final part in loc.split(',')) {
        add(_trace([part, ...x], val, path, parent, parentPropName, callback, true, false));
      }
    } else if (_has(val, loc)) {
      add(_trace(x, _get(val, loc), _p(path, loc), val, loc, callback, hasArrExpr, true));
    }

    if (_hasParentSelector) {
      for (var t = 0; t < ret.length; t++) {
        if (ret[t].isParentSelector) {
          final tmp = _trace(ret[t].parentSelectorExpr ?? [], val, ret[t].path,
            parent, parentPropName, callback, hasArrExpr, false);
          if (tmp.length > 1) {
            ret[t] = tmp[0];
            for (var tt = 1; tt < tmp.length; tt++) { t++; ret.insert(t, tmp[tt]); }
          } else if (tmp.isNotEmpty) { ret[t] = tmp[0]; }
          else { ret.removeAt(t); t--; }
        }
      }
    }
    return ret;
  }

  static bool _typeCheck(String type, Object? val) {
    switch (type) {
      case 'scalar': return val == null || val is bool || val is num || val is String;
      case 'boolean': return val is bool;
      case 'string': return val is String;
      case 'undefined': return val == null;
      case 'function': return false;
      case 'integer': return val is int || (val is double && val == val.truncateToDouble() && val.isFinite);
      case 'number': return val is num && val.isFinite;
      case 'nonFinite': return val is double && !val.isFinite;
      case 'object': return val != null && val is Map && val is! List;
      case 'array': return val is List;
      case 'null': return val == null;
      case 'other':
        final r = _otherTypeCallback!(val, [], null, null);
        return r is bool ? r : false;
      default: throw ArgumentError('Unknown value type $type');
    }
  }

  static void _walk(Object? val, void Function(String) f) {
    if (val is List) {
      for (var i = 0; i < val.length; i++) f(i.toString());
    } else if (val is Map) {
      for (final k in val.keys) f(k.toString());
    }
  }

  static bool _has(Object? v, Object k) {
    if (v is Map) return v.containsKey(k);
    if (v is List && k is String) { final i = int.tryParse(k); return i != null && i >= 0 && i < v.length; }
    return false;
  }

  static Object? _get(Object? v, Object k) {
    if (v is Map) return v[k];
    if (v is List && k is String) { final i = int.tryParse(k); return (i != null) ? v[i] : null; }
    return null;
  }

  static List<String> _p(List<String> a, String s) => [...a, s];
  static bool _isObj(Object? v) => v != null && (v is Map || v is List);

  static List<JsonPathMatch>? _doSlice(
    String loc, List<String> expr, Object? val, List<String> path,
    Object? parent, String? ppn, callback,
  ) {
    if (val is! List) return null;
    final len = val.length;
    final parts = loc.split(':');
    final step = (parts.length > 2 && parts[2].isNotEmpty) ? int.parse(parts[2]) : 1;
    var start = (parts[0].isNotEmpty) ? int.parse(parts[0]) : 0;
    final end = (parts.length > 1 && parts[1].isNotEmpty) ? int.parse(parts[1]) : len;
    start = start < 0 ? max(0, start + len) : min(len, start);
    final eEnd = end < 0 ? max(0, end + len) : min(len, end);
    final ret = <JsonPathMatch>[];
    for (var i = start; i < eEnd; i += step) {
      ret.addAll(_trace([i.toString(), ...expr], val, path, parent, ppn, callback, true, false));
    }
    return ret;
  }

  static bool _filter(String code, Object? v, String vn, List<String> path, Object? parent, String? ppn, {bool ignoreErrors = false}) {
    _sandbox[r'_$_parentProperty'] = ppn;
    _sandbox[r'_$_parent'] = parent;
    _sandbox[r'_$_property'] = vn;
    _sandbox[r'_$_v'] = v;
    if (code.contains('@path')) _sandbox[r'_$_path'] = toPathString([...path, vn]);

    var script = code
      .replaceAll('@parentProperty', r'_$_parentProperty')
      .replaceAll('@parent', r'_$_parent')
      .replaceAll('@property', r'_$_property')
      .replaceAll('@root', r'_$_root');
    // Replace @ followed by ., space, ), or [ with _$_v prefix
      script = script.replaceAllMapped(
        RegExp(r'@(\.)'),
        (m) => r'_$_v' + m[1]!,
      );
      script = script.replaceAllMapped(
        RegExp(r'@(\s)'),
        (m) => r'_$_v' + m[1]!,
      );
      script = script.replaceAllMapped(
        RegExp(r'@(\))'),
        (m) => r'_$_v' + m[1]!,
      );
      script = script.replaceAllMapped(
        RegExp(r'@(\[)'),
        (m) => r'_$_v' + m[1]!,
      );
    if (code.contains('@path')) script = script.replaceAll('@path', r'_$_path');

    try {
      final r = SafeEval.evaluate(script, _sandbox);
      return r is bool ? r : (r != null && r != false);
    } catch (e) {
      if (ignoreErrors) return false;
      rethrow;
    }
  }

  static Object? _dynamic(String code, Object? val, Object lastPath, Object? parent, String? ppn) {
    _sandbox[r'_$_parentProperty'] = ppn;
    _sandbox[r'_$_parent'] = parent;
    _sandbox[r'_$_property'] = lastPath.toString();
    _sandbox[r'_$_v'] = val;

    var script = code
      .replaceAll('@parentProperty', r'_$_parentProperty')
      .replaceAll('@parent', r'_$_parent')
      .replaceAll('@property', r'_$_property')
      .replaceAll('@root', r'_$_root');
    // Replace @. @space @) @[ with _$_v prefix
    script = script.replaceAllMapped(RegExp(r'@(\.)'), (m) => r'_$_v' + m[1]!);
    script = script.replaceAllMapped(RegExp(r'@(\s)'), (m) => r'_$_v' + m[1]!);
    script = script.replaceAllMapped(RegExp(r'@(\))'), (m) => r'_$_v' + m[1]!);
    script = script.replaceAllMapped(RegExp(r'@(\[)'), (m) => r'_$_v' + m[1]!);

    try { return SafeEval.evaluate(script, _sandbox); }
    catch (e) { rethrow; }
  }

  // ── Public static utility methods ──

  static List<String> toPathArray(String expr) {
    if (cache.containsKey(expr) && cache[expr] is List<String>) {
      return List<String>.from(cache[expr] as List);
    }
    final subx = <String>[];
    var n = expr.replaceAllMapped(
      RegExp(r'@(?:null|boolean|number|string|integer|undefined|nonFinite|scalar|array|object|function|other)\(\)'),
      (m) => ';${m[0]};',
    );
    // Replace parenthetical filter/dynamic expressions in brackets
    // Captures ?(expr) or (expr) including the leading ?
    n = n.replaceAllMapped(RegExp(r'''\[(\??\(.*?\))\]'''), (m) {
      subx.add(m[1]!);
      return '[#${subx.length - 1}]';
    });
    // Escape dots/tildes in bracket-quoted properties
    n = n.replaceAllMapped(RegExp(r"""\[['"]([^'"]*?)['"]\]"""), (m) =>
      "['${m[1]!.replaceAll('.', '%@%').replaceAll('~', '%%@@%%')}']");
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
    final exprList = parts.map((e) {
      final m = RegExp(r'#(\d+)').firstMatch(e);
      if (m != null) {
        final idx = int.parse(m[1]!);
        return idx < subx.length ? subx[idx] : e;
      }
      return e;
    }).toList();
    cache[expr] = exprList;
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
        p += '/${path[i].toString().replaceAll('~', '~0').replaceAll('/', '~1')}';
      }
    }
    return p;
  }
}
