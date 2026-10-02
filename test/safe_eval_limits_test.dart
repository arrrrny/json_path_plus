import 'package:test/test.dart';
import 'package:json_path_plus/json_path_plus.dart';

/// SafeEval resource-limit hardening (issue #10).
///
/// Covers:
/// - Expression length cap (64 KiB) → `FormatException`, not unbounded
///   tokenizer work.
/// - Parse nesting depth cap (256) → `FormatException` instead of a
///   `StackOverflowError` (an `Error`, not an `Exception`) at ~5k nesting.
/// - `_filter` converts evaluator `Error`s per `ignoreEvalErrors` instead of
///   letting them escape as crashes.
void main() {
  // Probe builders (interpolated to keep the analyzer's
  // prefer_interpolation_to_compose_strings lint happy).
  String nestedParens(int depth) => '1${' + (1' * depth} + 1${')' * depth}';
  String hugeLiteral(int length) => "'${'a' * length}'.length";

  group('SafeEval expression length limit', () {
    test('expression longer than 64 KiB throws FormatException', () {
      // A single huge string literal: trivially shallow, purely long.
      expect(
        () => SafeEval.evaluate(hugeLiteral(70000), {}),
        throwsA(
          isA<FormatException>().having(
              (e) => e.message, 'message', contains('expression too long')),
        ),
      );
    });

    test('long-but-legal expression just under the limit still evaluates', () {
      expect(SafeEval.evaluate(hugeLiteral(60000), {}), 60000);
    });

    test('expression of exactly maxExpressionLength chars still evaluates', () {
      // hugeLiteral(n) contributes n + 9 chars of code ('...' plus .length).
      expect(
        SafeEval.evaluate(hugeLiteral(SafeEval.maxExpressionLength - 9), {}),
        SafeEval.maxExpressionLength - 9,
      );
    });
  });

  group('SafeEval nesting depth limit', () {
    test('moderate nesting still evaluates', () {
      // 100 nested parens: well under the 256 cap. The probe contains
      // 102 ones (leading 1 + 100 inside parens + trailing 1).
      expect(SafeEval.evaluate(nestedParens(100), {}), 102);
    });

    test('5000 nested parens throw FormatException, not StackOverflowError',
        () {
      // The crash probe from issue #10.
      expect(
        () => SafeEval.evaluate(nestedParens(5000), {}),
        throwsA(
          isA<FormatException>().having(
              (e) => e.message, 'message', 'expression too deeply nested'),
        ),
      );
    });

    test('deep unary chain throws FormatException', () {
      // Unary operators recurse through _parseUnary without any parens;
      // the depth cap must cover that path too.
      expect(
        () => SafeEval.evaluate('${'!' * 1000}true', {}),
        throwsA(
          isA<FormatException>().having(
              (e) => e.message, 'message', 'expression too deeply nested'),
        ),
      );
    });

    test('127 nested parens (the parse-depth boundary) still evaluate', () {
      // Depth is counted in descent frames: each paren level costs two
      // (ternary + unary), so 127 levels reach exactly 256 frames.
      expect(SafeEval.evaluate(nestedParens(127), {}), 129);
    });

    test('128 nested parens exceed the parse-depth cap', () {
      expect(
        () => SafeEval.evaluate(nestedParens(128), {}),
        throwsA(
          isA<FormatException>().having(
              (e) => e.message, 'message', 'expression too deeply nested'),
        ),
      );
    });
  });

  group('SafeEval chain depth limit (evaluation-time recursion)', () {
    test('deep member chain throws FormatException, not StackOverflowError',
        () {
      // a.b.b… × 20000 parses iteratively at descent depth ≈ 0 but recurses
      // in _evalMember; chain links must count toward the same cap.
      expect(
        () => SafeEval.evaluate('a${'.b' * 20000}', {}),
        throwsA(
          isA<FormatException>().having(
              (e) => e.message, 'message', 'expression too deeply nested'),
        ),
      );
    });

    test('deep binary chain throws FormatException, not StackOverflowError',
        () {
      // 1+1+… × 30000 builds a left-deep AST that recurses in _evalBinary.
      expect(
        () => SafeEval.evaluate('${'1+' * 30000}1', {}),
        throwsA(
          isA<FormatException>().having(
              (e) => e.message, 'message', 'expression too deeply nested'),
        ),
      );
    });

    test('deep index chain throws FormatException, not StackOverflowError', () {
      // a[0][0]… × 15000 recurses in _evalIndex at evaluation time.
      expect(
        () => SafeEval.evaluate('a${'[0]' * 15000}', {}),
        throwsA(
          isA<FormatException>().having(
              (e) => e.message, 'message', 'expression too deeply nested'),
        ),
      );
    });

    test('binary chain at the depth boundary still evaluates', () {
      // 256 absorbed '+' operators: exactly at the 256-link cap.
      expect(SafeEval.evaluate('${'1+' * 256}1', {}), 257);
    });

    test('binary chain past the depth cap throws FormatException', () {
      expect(
        () => SafeEval.evaluate('${'1+' * 257}1', {}),
        throwsA(
          isA<FormatException>().having(
              (e) => e.message, 'message', 'expression too deeply nested'),
        ),
      );
    });
  });

  group('JSONPath filter resource limits (issue #10)', () {
    final json = {
      'items': [1, 2, 3],
    };

    test('deeply nested filter expression throws FormatException', () {
      final path = '\$[?(${'(' * 5000}@ > 1${')' * 5000})]';
      expect(
        () => JSONPath.query(path, json),
        throwsA(
          isA<FormatException>().having(
              (e) => e.message, 'message', 'expression too deeply nested'),
        ),
      );
    });

    test('filter evaluator Error is converted to FormatException', () {
      // An undefined identifier raises StateError — an Error, not an
      // Exception. With ignoreEvalErrors off it must surface as a
      // FormatException (catchable by `on Exception` handlers), not as an
      // Error.
      expect(
        () => JSONPath.query(r'$[?($_undefined === 1)]', json),
        throwsA(isA<FormatException>()),
      );
    });

    test('filter Error is swallowed when ignoreEvalErrors is true', () {
      final result = JSONPath.evaluate(JsonPathOptions(
        path: r'$[?($_undefined === 1)]',
        json: json,
        ignoreEvalErrors: true,
      ));
      expect(result, isEmpty);
    });
  });
}
