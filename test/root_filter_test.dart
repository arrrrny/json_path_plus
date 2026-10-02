import 'package:test/test.dart';
import 'package:json_path_plus/json_path_plus.dart';

/// Tests for the `@root` magic variable in filter expressions (issue #3).
///
/// `@root` refers to the original document root (JSONPath-Plus semantics).
/// It used to be rewritten to `_$_root` but never bound in the sandbox,
/// so any filter using it threw `Bad state: _$_root is not defined`.
void main() {
  group('Issue #3 reproduction', () {
    test(r'$.items[?(@.v === @root.top)] — @root in filter', () {
      final result = JSONPath.query(
        r'$.items[?(@.v === @root.top)]',
        {
          'top': 5,
          'items': [
            {'v': 5},
            {'v': 1},
          ],
        },
      );
      expect(result, hasLength(1));
      expect(result[0], {'v': 5});
    });

    test(r'@root does not throw without ignoreEvalErrors', () {
      expect(
        () => JSONPath.query(
          r'$.items[?(@.v === @root.top)]',
          {
            'top': 5,
            'items': [
              {'v': 5},
            ],
          },
        ),
        returnsNormally,
      );
    });

    test(r'@root with ignoreEvalErrors: true matches instead of failing all',
        () {
      final result = JSONPath.evaluate(
        JsonPathOptions(
          path: r'$.items[?(@.v === @root.top)]',
          json: {
            'top': 5,
            'items': [
              {'v': 5},
              {'v': 1},
            ],
          },
          ignoreEvalErrors: true,
        ),
      ) as List<Object?>;
      expect(result, hasLength(1));
      expect(result[0], {'v': 5});
    });
  });

  group('@root semantics', () {
    final doc = {
      'threshold': 10,
      'items': [
        {'name': 'a', 'price': 5},
        {'name': 'b', 'price': 12},
        {'name': 'c', 'price': 22},
      ],
    };

    test(r'$..item[?(@.price > @root.threshold)] — comparison against root',
        () {
      final result =
          JSONPath.query(r'$.items[?(@.price > @root.threshold)]', doc);
      expect(result, hasLength(2));
      expect((result[0] as Map)['name'], 'b');
      expect((result[1] as Map)['name'], 'c');
    });

    test(r'@root usable in nested paths — @root.items.length-like access', () {
      final result = JSONPath.query(
        r'$.items[?(@.price === @root.items.length)]',
        doc,
      );
      // items.length is 3; no price equals 3 — but the expression must
      // evaluate instead of throwing.
      expect(result, isEmpty);
    });
  });
}
