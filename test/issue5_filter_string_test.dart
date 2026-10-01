import 'package:test/test.dart';
import 'package:json_path_plus/json_path_plus.dart';

/// Filter scanner tests (issue #5).
///
/// Covers:
/// - Paren-form filters `[?(expr)]` whose expression contains `)]` inside a
///   string literal — the old non-greedy regex `\[(\??\(.*?\))\]` truncated
///   the capture at the first `)` followed by `]`, even inside quotes.
/// - Bare RFC 9535 filters `[?<expr>]` with multi-level nested brackets —
///   the old `\[[^\]]*\]` alternation only handled one nesting level.
void main() {
  group('Issue #5 reproduction', () {
    final data = {
      'p': {'a': 'x)]y', 'b': 1},
      'q': {'a': 'no', 'b': 2},
    };

    test(r'$[?(@.a == "x)]y")].b — paren form, `)]` inside a string', () {
      final result = JSONPath.query(
        r"""$[?(@.a == "x)]y")].b""",
        data,
      );
      expect(result, [1]);
    });

    test(r"$[?(@.a == 'x)]y')].b — paren form, `)]` inside single quotes", () {
      final result = JSONPath.query(
        r"$[?(@.a == 'x)]y')].b",
        data,
      );
      expect(result, [1]);
    });

    test(r'$[?@.a == "x)]y"].b — bare form, `)]` inside a string', () {
      final result = JSONPath.query(
        r"""$[?@.a == "x)]y"].b""",
        data,
      );
      expect(result, [1]);
    });
  });

  group('Issue #5 related: nested brackets in bare filters', () {
    final nested = {
      'items': [
        {
          'a': ['x'],
          'n': 1
        },
        {
          'a': ['y'],
          'n': 2
        },
      ],
    };

    test(r'$.items[?@["a"][0] === "y"].n — chained bracket subscript', () {
      final result = JSONPath.query(r'$.items[?@["a"][0] === "y"].n', nested);
      expect(result, [2]);
    });

    test(
        r"""$.items[?@['a'][0] === 'x'].n — chained single-quoted subscripts""",
        () {
      final result =
          JSONPath.query(r"""$.items[?@['a'][0] === 'x'].n""", nested);
      expect(result, [1]);
    });

    test(r"$[?@['a]b']] — bracket nested in bare filter, `]` inside quotes",
        () {
      // Multi-level nesting: the subscript key contains a `]` inside a string
      // literal, inside the bare filter's own brackets. The old one-level
      // `\[[^\]]*\]` alternation truncated at the `]` inside the quoted key.
      final d = {
        'items': [
          {'a]b': 1, 'n': 10},
          {'plain': 2, 'n': 20},
        ],
      };
      final result = JSONPath.query(r"$.items[?@['a]b']].n", d);
      expect(result, [10]);
    });
  });

  group('Issue #5 regressions — plain filters still tokenize', () {
    test('paren form equality still works', () {
      final d = {
        'a': {'v': 1},
        'b': {'v': 2},
      };
      final result = JSONPath.query(r'$[?(@.v === 2)]', d);
      expect(result.length, 1);
      expect(result[0], {'v': 2});
    });

    test('bare form comparison still works', () {
      final d = {
        'a': {'v': 1},
        'b': {'v': 2},
      };
      final result = JSONPath.query(r'$[?@.v > 1]', d);
      expect(result.length, 1);
      expect(result[0], {'v': 2});
    });

    test('dynamic property [(expr)] still works', () {
      final list = ['a', 'b', 'c'];
      final result = JSONPath.query(r'$[(1+1)]', list);
      expect(result, ['c']);
    });

    test('bare filter with match() and quoted pattern still works', () {
      final d = {
        'x1': {'v': 1},
        'other': {'v': 2},
        'x22': {'v': 3},
      };
      final result = JSONPath.query(r'$[?match(key(@), "x[0-9]+")]', d);
      expect(result.length, 2);
    });
  });
}
