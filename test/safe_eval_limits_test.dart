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
