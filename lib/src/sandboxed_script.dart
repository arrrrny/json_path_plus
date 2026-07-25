/// A safe expression evaluator ported from Safe-Script.js.
///
/// Parses and evaluates a restricted subset of JS expressions without
/// using `dart:mirrors`, `eval()`, or `Function.apply()`.
///
/// Supports:
/// - Property access: `obj.key`, `obj[key]`
/// - Method calls: `.indexOf(arg)`, `.includes(arg)`, `.startsWith(prefix)`,
///   `.endsWith(suffix)`, `.length`, `.toString()`
/// - Comparisons: `===`, `==`, `!==`, `!=`, `<`, `>`, `<=`, `>=`
/// - Boolean operators: `&&`, `||`, `!`
/// - Arithmetic: `+`, `-`, `*`, `/`, `%`
/// - String literals (single and double quotes)
/// - Number literals (int and float)
/// - `true`, `false`, `null` literals
/// - Ternary: `cond ? a : b`
/// - Parentheses for grouping
/// - `typeof`, unary `-`, `+`

// ── AST Nodes ──

sealed class Expr {}

class LiteralExpr extends Expr {
  final Object? value;
  LiteralExpr(this.value);
}

class IdentifierExpr extends Expr {
  final String name;
  IdentifierExpr(this.name);
}

class BinaryExpr extends Expr {
  final Expr left;
  final String op;
  final Expr right;
  BinaryExpr(this.left, this.op, this.right);
}

class UnaryExpr extends Expr {
  final String op;
  final Expr operand;
  UnaryExpr(this.op, this.operand);
}

/// Member access via dot-notation: `obj.property`
class MemberExpr extends Expr {
  final Expr object;
  final String property;
  MemberExpr(this.object, this.property);
}

/// Index access via brackets: `obj[expr]`
class IndexExpr extends Expr {
  final Expr object;
  final Expr index;
  IndexExpr(this.object, this.index);
}

class CallExpr extends Expr {
  final Expr callee;
  final List<Expr> arguments;
  CallExpr(this.callee, this.arguments);
}

class ConditionalExpr extends Expr {
  final Expr test;
  final Expr consequent;
  final Expr alternate;
  ConditionalExpr(this.test, this.consequent, this.alternate);
}

class TypeofExpr extends Expr {
  final Expr operand;
  TypeofExpr(this.operand);
}

// ── Tokenizer ──

class Token {
  final String type; // 'num', 'str', 'id', 'op', 'punc', 'bool', 'null', 'eof'
  final String value;
  Token(this.type, this.value);
}

class Tokenizer {
  final String input;
  int pos = 0;

  Tokenizer(this.input);

  List<Token> tokenize() {
    final tokens = <Token>[];
    while (pos < input.length) {
      _skipWhitespace();
      if (pos >= input.length) break;

      final ch = input[pos];

      if (_isDigit(ch) || (ch == '.' && pos + 1 < input.length && _isDigit(input[pos + 1]))) {
        tokens.add(_readNumber());
      } else if (ch == "'" || ch == '"') {
        tokens.add(_readString());
      } else if (_isIdentStart(ch)) {
        tokens.add(_readIdentifierOrKeyword());
      } else if (ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == ',' || ch == '.' || ch == ';') {
        tokens.add(Token('punc', ch));
        pos++;
      } else if (_isOperatorStart(ch)) {
        tokens.add(_readOperator());
      } else {
        // Skip unknown chars
        pos++;
      }
    }
    tokens.add(Token('eof', ''));
    return tokens;
  }

  void _skipWhitespace() {
    while (pos < input.length && _isWhitespace(input[pos])) {
      pos++;
    }
  }

  Token _readNumber() {
    final start = pos;
    while (pos < input.length && (_isDigit(input[pos]) || input[pos] == '.')) {
      pos++;
    }
    return Token('num', input.substring(start, pos));
  }

  Token _readString() {
    final quote = input[pos];
    pos++; // skip opening quote
    final buffer = StringBuffer();
    while (pos < input.length && input[pos] != quote) {
      if (input[pos] == '\\' && pos + 1 < input.length) {
        pos++;
        final escaped = input[pos];
        switch (escaped) {
          case 'n':
            buffer.write('\n');
          case 't':
            buffer.write('\t');
          case 'r':
            buffer.write('\r');
          case '\\':
            buffer.write('\\');
          case "'":
            buffer.write("'");
          case '"':
            buffer.write('"');
          default:
            buffer.write(escaped);
        }
      } else {
        buffer.write(input[pos]);
      }
      pos++;
    }
    pos++; // skip closing quote
    return Token('str', buffer.toString());
  }

  Token _readIdentifierOrKeyword() {
    final start = pos;
    while (pos < input.length && _isIdentPart(input[pos])) {
      pos++;
    }
    final word = input.substring(start, pos);
    if (word == 'true' || word == 'false') {
      return Token('bool', word);
    }
    if (word == 'null') {
      return Token('null', word);
    }
    if (word == 'typeof') {
      return Token('op', 'typeof');
    }
    if (word == 'undefined') {
      return Token('null', 'null');
    }
    if (word == 'void') {
      return Token('op', 'void');
    }
    return Token('id', word);
  }

  Token _readOperator() {
    final start = pos;
    // Try to match longest operator first
    final remaining = input.substring(pos);
    final ops = [
      '===', '!==', '&&', '||', '<=', '>=', '==', '!=',
      '<<', '>>', '>>>', '++', '--', '+', '-', '*', '/', '%',
      '&', '|', '^', '~', '<', '>', '!', '?', ':',
    ];
    for (final op in ops) {
      if (remaining.startsWith(op)) {
        pos += op.length;
        return Token('op', op);
      }
    }
    // fallback
    pos++;
    return Token('op', input.substring(start, pos));
  }

  bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
  bool _isWhitespace(String ch) => ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
  bool _isIdentStart(String ch) =>
      (ch.codeUnitAt(0) >= 65 && ch.codeUnitAt(0) <= 90) || // A-Z
      (ch.codeUnitAt(0) >= 97 && ch.codeUnitAt(0) <= 122) || // a-z
      ch == '_' || ch == '\$';
  bool _isIdentPart(String ch) =>
      _isIdentStart(ch) || _isDigit(ch);
  bool _isOperatorStart(String ch) =>
      '+-*/%&|^~<>!=?:'.contains(ch);
}

// ── Parser ──

class Parser {
  final List<Token> tokens;
  int pos = 0;

  Parser(this.tokens);

  Expr parse() {
    final expr = _parseTernary();
    return expr;
  }

  Expr _parseTernary() {
    var expr = _parseOr();
    if (_matchOp('?')) {
      final consequent = _parseTernary();
      _expectOp(':');
      final alternate = _parseTernary();
      return ConditionalExpr(expr, consequent, alternate);
    }
    return expr;
  }

  Expr _parseOr() {
    var left = _parseAnd();
    while (_matchOp('||')) {
      final right = _parseAnd();
      left = BinaryExpr(left, '||', right);
    }
    return left;
  }

  Expr _parseAnd() {
    var left = _parseEquality();
    while (_matchOp('&&')) {
      final right = _parseEquality();
      left = BinaryExpr(left, '&&', right);
    }
    return left;
  }

  Expr _parseEquality() {
    var left = _parseComparison();
    while (true) {
      if (_matchOp('===')) {
        left = BinaryExpr(left, '===', _parseComparison());
      } else if (_matchOp('!==')) {
        left = BinaryExpr(left, '!==', _parseComparison());
      } else if (_matchOp('==')) {
        left = BinaryExpr(left, '==', _parseComparison());
      } else if (_matchOp('!=')) {
        left = BinaryExpr(left, '!=', _parseComparison());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseComparison() {
    var left = _parseAddSub();
    while (true) {
      if (_matchOp('<')) {
        left = BinaryExpr(left, '<', _parseAddSub());
      } else if (_matchOp('>')) {
        left = BinaryExpr(left, '>', _parseAddSub());
      } else if (_matchOp('<=')) {
        left = BinaryExpr(left, '<=', _parseAddSub());
      } else if (_matchOp('>=')) {
        left = BinaryExpr(left, '>=', _parseAddSub());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseAddSub() {
    var left = _parseMulDiv();
    while (true) {
      if (_matchOp('+')) {
        left = BinaryExpr(left, '+', _parseMulDiv());
      } else if (_matchOp('-')) {
        left = BinaryExpr(left, '-', _parseMulDiv());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseMulDiv() {
    var left = _parseUnary();
    while (true) {
      if (_matchOp('*')) {
        left = BinaryExpr(left, '*', _parseUnary());
      } else if (_matchOp('/')) {
        left = BinaryExpr(left, '/', _parseUnary());
      } else if (_matchOp('%')) {
        left = BinaryExpr(left, '%', _parseUnary());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseUnary() {
    if (_matchOp('!')) {
      return UnaryExpr('!', _parseUnary());
    }
    if (_matchOp('-')) {
      // Check for negative number literal — avoid wrapping
      if (_current().type == 'num') {
        final tok = _current();
        _advance();
        final val = -num.parse(tok.value);
        return LiteralExpr(val);
      }
      return UnaryExpr('-', _parseUnary());
    }
    if (_matchOp('+')) {
      return UnaryExpr('+', _parseUnary());
    }
    if (_matchOp('~')) {
      return UnaryExpr('~', _parseUnary());
    }
    if (_peekOp('typeof')) {
      _advance();
      return TypeofExpr(_parseUnary());
    }
    if (_matchOp('void')) {
      return UnaryExpr('void', _parseUnary());
    }
    return _parsePostfix();
  }

  Expr _parsePostfix() {
    var expr = _parsePrimary();
    while (true) {
      if (_matchPunc('.')) {
        // Member access: obj.key
        final prop = _expectIdentifier();
        expr = MemberExpr(expr, prop);
      } else if (_matchPunc('[')) {
        // Computed index access: obj[key]
        final index = _parseTernary();
        _expectPunc(']');
        expr = IndexExpr(expr, index);
      } else if (_matchPunc('(')) {
        // Function call
        final args = <Expr>[];
        if (!_peekPunc(')')) {
          args.add(_parseTernary());
          while (_matchPunc(',')) {
            args.add(_parseTernary());
          }
        }
        _expectPunc(')');
        expr = CallExpr(expr, args);
      } else {
        break;
      }
    }
    return expr;
  }

  Expr _parsePrimary() {
    final tok = _current();
    if (tok.type == 'num') {
      _advance();
      final val = num.parse(tok.value);
      return LiteralExpr(val);
    }
    if (tok.type == 'str') {
      _advance();
      return LiteralExpr(tok.value);
    }
    if (tok.type == 'bool') {
      _advance();
      return LiteralExpr(tok.value == 'true');
    }
    if (tok.type == 'null') {
      _advance();
      return LiteralExpr(null);
    }
    if (tok.type == 'id') {
      _advance();
      return IdentifierExpr(tok.value);
    }
    if (_matchPunc('(')) {
      final expr = _parseTernary();
      _expectPunc(')');
      return expr;
    }
    // Fallback: skip unknown token
    _advance();
    return LiteralExpr(null);
  }

  Token _current() => pos < tokens.length ? tokens[pos] : tokens.last;

  void _advance() {
    if (pos < tokens.length - 1) pos++;
  }

  bool _matchOp(String op) {
    if (_current().type == 'op' && _current().value == op) {
      _advance();
      return true;
    }
    return false;
  }

  bool _peekOp(String op) {
    return _current().type == 'op' && _current().value == op;
  }

  bool _matchPunc(String p) {
    if (_current().type == 'punc' && _current().value == p) {
      _advance();
      return true;
    }
    return false;
  }

  bool _peekPunc(String p) {
    return _current().type == 'punc' && _current().value == p;
  }

  void _expectPunc(String p) {
    if (!_matchPunc(p)) {
      throw FormatException('Expected "$p" but got "${_current().value}"');
    }
  }

  void _expectOp(String op) {
    if (!_matchOp(op)) {
      throw FormatException('Expected "$op" but got "${_current().value}"');
    }
  }

  String _expectIdentifier() {
    final tok = _current();
    if (tok.type == 'id') {
      _advance();
      return tok.value;
    }
    // Also accept keywords that could be property names
    if (tok.type == 'bool' || tok.type == 'null') {
      _advance();
      return tok.value;
    }
    throw FormatException('Expected identifier but got "${tok.value}"');
  }
}

// ── Evaluator ──

class SafeEval {
  /// Parse and evaluate a JS-style expression string with the given
  /// variable bindings.
  static Object? evaluate(String code, Map<String, Object?> context) {
    final tokenizer = Tokenizer(code);
    final tokens = tokenizer.tokenize();
    final parser = Parser(tokens);
    final ast = parser.parse();
    return _evalAst(ast, context);
  }

  static Object? _evalAst(Expr ast, Map<String, Object?> subs) {
    switch (ast) {
      case LiteralExpr():
        return ast.value;
      case IdentifierExpr():
        if (subs.containsKey(ast.name)) {
          return subs[ast.name];
        }
        throw StateError('${ast.name} is not defined');
      case BinaryExpr():
        return _evalBinary(ast, subs);
      case UnaryExpr():
        return _evalUnary(ast, subs);
      case MemberExpr():
        return _evalMember(ast, subs);
      case IndexExpr():
        return _evalIndex(ast, subs);
      case CallExpr():
        return _evalCall(ast, subs);
      case ConditionalExpr():
        if (_isTruthy(_evalAst(ast.test, subs))) {
          return _evalAst(ast.consequent, subs);
        }
        return _evalAst(ast.alternate, subs);
      case TypeofExpr():
        final val = _evalAst(ast.operand, subs);
        return _typeofVal(val);
    }
  }

  static Object? _evalBinary(BinaryExpr ast, Map<String, Object?> subs) {
    switch (ast.op) {
      case '||':
        final left = _evalAst(ast.left, subs);
        if (_isTruthy(left)) return left;
        return _evalAst(ast.right, subs);
      case '&&':
        final left = _evalAst(ast.left, subs);
        if (!_isTruthy(left)) return left;
        return _evalAst(ast.right, subs);
      case '===':
        return _deepEquals(_evalAst(ast.left, subs), _evalAst(ast.right, subs));
      case '!==':
        return !_deepEquals(_evalAst(ast.left, subs), _evalAst(ast.right, subs));
      case '==':
        return _looseEquals(_evalAst(ast.left, subs), _evalAst(ast.right, subs));
      case '!=':
        return !_looseEquals(_evalAst(ast.left, subs), _evalAst(ast.right, subs));
      case '<':
        return _compare(_evalAst(ast.left, subs), _evalAst(ast.right, subs)) < 0;
      case '>':
        return _compare(_evalAst(ast.left, subs), _evalAst(ast.right, subs)) > 0;
      case '<=':
        return _compare(_evalAst(ast.left, subs), _evalAst(ast.right, subs)) <= 0;
      case '>=':
        return _compare(_evalAst(ast.left, subs), _evalAst(ast.right, subs)) >= 0;
      case '+':
        final l = _evalAst(ast.left, subs);
        final r = _evalAst(ast.right, subs);
        if (l is num && r is num) return l + r;
        if (l is String || r is String) return '${l ?? ''}${r ?? ''}';
        return _toNum(l) + _toNum(r);
      case '-':
        return _toNum(_evalAst(ast.left, subs)) - _toNum(_evalAst(ast.right, subs));
      case '*':
        return _toNum(_evalAst(ast.left, subs)) * _toNum(_evalAst(ast.right, subs));
      case '/':
        return _toNum(_evalAst(ast.left, subs)) / _toNum(_evalAst(ast.right, subs));
      case '%':
        return _toNum(_evalAst(ast.left, subs)) % _toNum(_evalAst(ast.right, subs));
      case '|':
        return (_toNum(_evalAst(ast.left, subs)).toInt()) |
            (_toNum(_evalAst(ast.right, subs)).toInt());
      case '^':
        return (_toNum(_evalAst(ast.left, subs)).toInt()) ^
            (_toNum(_evalAst(ast.right, subs)).toInt());
      case '&':
        return (_toNum(_evalAst(ast.left, subs)).toInt()) &
            (_toNum(_evalAst(ast.right, subs)).toInt());
      case '<<':
        return (_toNum(_evalAst(ast.left, subs)).toInt()) <<
            (_toNum(_evalAst(ast.right, subs)).toInt());
      case '>>':
        return (_toNum(_evalAst(ast.left, subs)).toInt()) >>
            (_toNum(_evalAst(ast.right, subs)).toInt());
      case '>>>':
        return (_toNum(_evalAst(ast.left, subs)).toInt()) >>
            (_toNum(_evalAst(ast.right, subs)).toInt());
      default:
        throw StateError('Unknown operator: ${ast.op}');
    }
  }

  static Object? _evalUnary(UnaryExpr ast, Map<String, Object?> subs) {
    switch (ast.op) {
      case '!':
        return !_isTruthy(_evalAst(ast.operand, subs));
      case '-':
        return -_toNum(_evalAst(ast.operand, subs));
      case '+':
        return _toNum(_evalAst(ast.operand, subs));
      case '~':
        return ~(_toNum(_evalAst(ast.operand, subs)).toInt());
      case 'void':
        _evalAst(ast.operand, subs);
        return null;
      default:
        throw StateError('Unknown unary operator: ${ast.op}');
    }
  }

  /// Evaluate a dot-notation member expression: `obj.property`
  static Object? _evalMember(MemberExpr ast, Map<String, Object?> subs) {
    final obj = _evalAst(ast.object, subs);
    final prop = ast.property;

    if (obj == null) return null;

    // Handle .length on strings, lists, and maps
    if (prop == 'length') {
      if (obj is String) return obj.length;
      if (obj is List) return obj.length;
      if (obj is Map) return obj.length;
    }

    // Return a method proxy for known string methods
    if (obj is String) {
      switch (prop) {
        case 'indexOf': case 'includes': case 'startsWith':
        case 'endsWith': case 'charAt': case 'substring':
        case 'toLowerCase': case 'toUpperCase': case 'trim':
        case 'split': case 'replace':
          return _MethodProxy(obj, prop);
        case 'toString':
          return _MethodProxy(obj, 'toString');
      }
    }

    // Return a method proxy for list methods
    if (obj is List) {
      switch (prop) {
        case 'indexOf': case 'includes': case 'join':
          return _MethodProxy(obj, prop);
        case 'toString':
          return _MethodProxy(obj, 'toString');
      }
    }

    // Return a method proxy for number methods
    if (obj is num) {
      if (prop == 'toString' || prop == 'toFixed' || prop == 'toPrecision') {
        return _MethodProxy(obj, prop);
      }
    }

    if (obj is bool) {
      if (prop == 'toString') return _MethodProxy(obj, 'toString');
    }

    // Map property access
    if (obj is Map) return obj[prop];

    return null;
  }

  /// Evaluate a bracket index expression: `obj[expr]`
  static Object? _evalIndex(IndexExpr ast, Map<String, Object?> subs) {
    final obj = _evalAst(ast.object, subs);
    final index = _evalAst(ast.index, subs);

    if (obj == null) return null;

    if (obj is List && index is int) {
      if (index >= 0 && index < obj.length) return obj[index];
      if (index < 0 && -index <= obj.length) return obj[obj.length + index];
      return null;
    }

    if (obj is Map) {
      return obj[index.toString()];
    }

    return null;
  }

  static Object? _evalCall(CallExpr ast, Map<String, Object?> subs) {
    // If callee is a MemberExpr or IndexExpr, resolve the method/value first
    if (ast.callee is MemberExpr || ast.callee is IndexExpr) {
      final methodResult = _evalAst(ast.callee, subs);
      if (methodResult is _MethodProxy) {
        final args = ast.arguments.map((a) => _evalAst(a, subs)).toList();
        return methodResult.call(args);
      }
      return null;
    }

    // Fallback: try to evaluate callee directly
    final callee = _evalAst(ast.callee, subs);
    if (callee is _MethodProxy) {
      final args = ast.arguments.map((a) => _evalAst(a, subs)).toList();
      return callee.call(args);
    }

    throw StateError('Cannot call non-function value');
  }

  // ── Helpers ──

  static bool _isTruthy(Object? val) {
    if (val == null) return false;
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) return val.isNotEmpty;
    if (val is List) return val.isNotEmpty;
    if (val is Map) return val.isNotEmpty;
    return true;
  }

  static String _typeofVal(Object? val) {
    if (val == null) return 'null';
    if (val is bool) return 'boolean';
    if (val is num) return 'number';
    if (val is String) return 'string';
    if (val is List) return 'array';
    if (val is Map) return 'object';
    if (val is Function) return 'function';
    return 'undefined';
  }
}

/// Deep equality supporting cross-numeric-type comparison.
bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Loose equality (== in JS).
bool _looseEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null && b == null) return true;
  if (a == null || b == null) return a == null && b == null;
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  return a == b;
}

int _compare(Object? a, Object? b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  return 0;
}

num _toNum(Object? val) {
  if (val is num) return val;
  if (val is String) return num.tryParse(val) ?? 0;
  if (val is bool) return val ? 1 : 0;
  return 0;
}

/// Internal callable proxy for method invocations.

/// Internal callable proxy for method invocations.
class _MethodProxy {
  final Object? _target;
  final String _methodName;

  _MethodProxy(this._target, this._methodName);

  Object? call(List<Object?> args) {
    final target = _target;
    if (target is String) {
      switch (_methodName) {
        case 'indexOf':
          if (args.isNotEmpty && args[0] is String) {
            return target.indexOf(args[0] as String, args.length > 1 && args[1] is int ? args[1] as int : 0);
          }
          return -1;
        case 'includes':
          if (args.isNotEmpty && args[0] is String) return target.contains(args[0] as String);
          return false;
        case 'startsWith':
          if (args.isNotEmpty && args[0] is String) return target.startsWith(args[0] as String);
          return false;
        case 'endsWith':
          if (args.isNotEmpty && args[0] is String) return target.endsWith(args[0] as String);
          return false;
        case 'charAt':
          if (args.isNotEmpty && args[0] is int) {
            final idx = args[0] as int;
            return idx < target.length ? target[idx] : '';
          }
          return '';
        case 'substring':
          if (args.isNotEmpty && args[0] is int) {
            if (args.length > 1 && args[1] is int) {
              return target.substring(args[0] as int, args[1] as int);
            }
            return target.substring(args[0] as int);
          }
          return target;
        case 'toLowerCase':
          return target.toLowerCase();
        case 'toUpperCase':
          return target.toUpperCase();
        case 'trim':
          return target.trim();
        case 'split':
          if (args.isNotEmpty && args[0] is String) return target.split(args[0] as String);
          return [target];
        case 'replace':
          if (args.length >= 2 && args[0] is String && args[1] is String) {
            return target.replaceAll(args[0] as String, args[1] as String);
          }
          return target;
        case 'toString':
          return target;
      }
    }

    if (target is List) {
      switch (_methodName) {
        case 'indexOf':
          if (args.isNotEmpty) {
            for (int i = 0; i < target.length; i++) {
              if (_deepEquals(target[i], args[0])) return i;
            }
          }
          return -1;
        case 'includes':
          if (args.isNotEmpty) {
            for (int i = 0; i < target.length; i++) {
              if (_deepEquals(target[i], args[0])) return true;
            }
          }
          return false;
        case 'join':
          return target.map((e) => e?.toString() ?? 'null')
              .join(args.isNotEmpty && args[0] is String ? args[0] as String : ',');
        case 'toString':
          return target.toString();
      }
    }

    if (target is num && _methodName == 'toString') {
      return target.toString();
    }
    if (target is bool && _methodName == 'toString') {
      return target.toString();
    }
    if (_methodName == 'toString') {
      return target?.toString() ?? 'null';
    }

    throw StateError('Cannot call $_methodName on ${target.runtimeType}');
  }
}
