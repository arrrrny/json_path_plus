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

class MemberExpr extends Expr {
  final Expr object;
  final Expr property;
  final bool computed; // true for obj[key], false for obj.key
  MemberExpr(this.object, this.property, {this.computed = false});
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
    var left = _parseBitwiseOr();
    while (true) {
      if (_matchOp('<')) {
        left = BinaryExpr(left, '<', _parseBitwiseOr());
      } else if (_matchOp('>')) {
        left = BinaryExpr(left, '>', _parseBitwiseOr());
      } else if (_matchOp('<=')) {
        left = BinaryExpr(left, '<=', _parseBitwiseOr());
      } else if (_matchOp('>=')) {
        left = BinaryExpr(left, '>=', _parseBitwiseOr());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseBitwiseOr() {
    var left = _parseBitwiseXor();
    while (_matchOp('|')) {
      left = BinaryExpr(left, '|', _parseBitwiseXor());
    }
    return left;
  }

  Expr _parseBitwiseXor() {
    var left = _parseBitwiseAnd();
    while (_matchOp('^')) {
      left = BinaryExpr(left, '^', _parseBitwiseAnd());
    }
    return left;
  }

  Expr _parseBitwiseAnd() {
    var left = _parseShift();
    while (_matchOp('&')) {
      left = BinaryExpr(left, '&', _parseShift());
    }
    return left;
  }

  Expr _parseShift() {
    var left = _parseAddition();
    while (true) {
      if (_matchOp('<<')) {
        left = BinaryExpr(left, '<<', _parseAddition());
      } else if (_matchOp('>>')) {
        left = BinaryExpr(left, '>>', _parseAddition());
      } else if (_matchOp('>>>')) {
        left = BinaryExpr(left, '>>>', _parseAddition());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseAddition() {
    var left = _parseMultiplication();
    while (true) {
      if (_matchOp('+')) {
        left = BinaryExpr(left, '+', _parseMultiplication());
      } else if (_matchOp('-')) {
        left = BinaryExpr(left, '-', _parseMultiplication());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseMultiplication() {
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
        expr = MemberExpr(expr, IdentifierExpr(prop), computed: false);
      } else if (_matchPunc('[')) {
        // Computed access: obj[key]
        final prop = _parseTernary();
        _expectPunc(']');
        expr = MemberExpr(expr, prop, computed: true);
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
        // Dart doesn't have unsigned right shift; approximate
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

  static Object? _evalMember(MemberExpr ast, Map<String, Object?> subs) {
    final obj = _evalAst(ast.object, subs);
    String prop;
    if (ast.computed) {
      final propVal = _evalAst(ast.property, subs);
      prop = propVal?.toString() ?? '';
    } else if (ast.property is IdentifierExpr) {
      prop = (ast.property as IdentifierExpr).name;
    } else {
      prop = _evalAst(ast.property, subs)?.toString() ?? '';
    }

    if (obj == null) {
      return null;
    }

    // Handle .length on strings and lists
    if (prop == 'length') {
      if (obj is String) return obj.length;
      if (obj is List) return obj.length;
      if (obj is Map) return obj.length;
    }

    // Handle .toString()
    if (prop == 'toString') {
      // Return a callable marker — we handle it in CallExpr
      return _MethodProxy(obj, 'toString');
    }

    // Handle map/list property access
    if (obj is Map) {
      return obj[prop];
    }
    if (obj is List) {
      final idx = int.tryParse(prop);
      if (idx != null && idx >= 0 && idx < obj.length) {
        return obj[idx];
      }
      return null;
    }
    if (obj is String) {
      // String method proxies
      switch (prop) {
        case 'indexOf':
          return _MethodProxy(obj, 'indexOf');
        case 'includes':
          return _MethodProxy(obj, 'includes');
        case 'startsWith':
          return _MethodProxy(obj, 'startsWith');
        case 'endsWith':
          return _MethodProxy(obj, 'endsWith');
        case 'charAt':
          return _MethodProxy(obj, 'charAt');
        case 'substring':
          return _MethodProxy(obj, 'substring');
        case 'toLowerCase':
          return _MethodProxy(obj, 'toLowerCase');
        case 'toUpperCase':
          return _MethodProxy(obj, 'toUpperCase');
        case 'trim':
          return _MethodProxy(obj, 'trim');
        case 'split':
          return _MethodProxy(obj, 'split');
        case 'replace':
          return _MethodProxy(obj, 'replace');
      }
      return null;
    }

    return null;
  }

  static Object? _evalCall(CallExpr ast, Map<String, Object?> subs) {
    // Special handling for method proxies
    if (ast.callee is MemberExpr) {
      final memberExpr = ast.callee as MemberExpr;
      // Evaluate the member to see if it's a MethodProxy
      final methodResult = _evalMember(memberExpr, subs);
      if (methodResult is _MethodProxy) {
        final args = ast.arguments.map((a) => _evalAst(a, subs)).toList();
        return methodResult.call(args);
      }
    }

    final callee = _evalAst(ast.callee, subs);
    if (callee is _MethodProxy) {
      final args = ast.arguments.map((a) => _evalAst(a, subs)).toList();
      return callee.call(args);
    }

    // If callee is a function-like thing (shouldn't happen in sandbox)
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

  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is num && b is num) {
      // Handle int/double cross-comparison
      return a == b;
    }
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
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }

  // Loose equality (== in JS)
  static bool _looseEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a == null && b == null) return true;
    // In JS, null == undefined is true
    if (a == null || b == null) return a == null && b == null;
    if (a is num && b is num) return a == b;
    if (a is String && b is String) return a == b;
    if (a is bool && b is bool) return a == b;
    return a == b;
  }

  static int _compare(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    return 0;
  }

  static num _toNum(Object? val) {
    if (val is num) return val;
    if (val is String) return num.tryParse(val) ?? 0;
    if (val is bool) return val ? 1 : 0;
    return 0;
  }

  static String _typeofVal(Object? val) {
    if (val == null) return 'undefined';
    if (val is bool) return 'boolean';
    if (val is num) {
      if (val is int) return 'number';
      return 'number';
    }
    if (val is String) return 'string';
    if (val is List) return 'object';
    if (val is Map) return 'object';
    if (val is Function) return 'function';
    return 'object';
  }
}

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
            return target.indexOf(args[0] as String);
          }
          return -1;
        case 'includes':
          if (args.isNotEmpty && args[0] is String) {
            return target.contains(args[0] as String);
          }
          return false;
        case 'startsWith':
          if (args.isNotEmpty && args[0] is String) {
            return target.startsWith(args[0] as String);
          }
          return false;
        case 'endsWith':
          if (args.isNotEmpty && args[0] is String) {
            return target.endsWith(args[0] as String);
          }
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
          if (args.isNotEmpty && args[0] is String) {
            return target.split(args[0] as String);
          }
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
    if (_methodName == 'toString') {
      return target?.toString() ?? 'null';
    }
    if (target is List && _methodName == 'length') {
      return target.length;
    }
    throw StateError('Cannot call $_methodName on ${target.runtimeType}');
  }
}
