import 'package:test/test.dart';
import 'package:json_path_plus/json_path_plus.dart';

/// Reentrancy / evaluation-isolation tests.
///
/// Every test here calls `JSONPath.evaluate` from inside a match `callback`,
/// while an outer `evaluate` walk is still in progress. The inner call must be
/// fully isolated from the outer one: it may not change how the outer run
/// behaves for the remainder of its walk (result type, sandbox, eval mode,
/// error policy, `@other()` callback).
///
/// The `json` fixtures are shaped so the outer's first filter matches (which
/// fires the callback) and a *later* sibling of the same walk still has work to
/// do — that later step is where a leaked inner state becomes observable.
void main() {
  group('N. Reentrancy isolation', () {
    // ── resultType ───────────────────────────────────────────────────────
    test('inner resultType does not leak into the outer run', () {
      final data = {
        'a': {'x': 1},
        'b': {'x': 2},
      };
      var reentered = false;

      // The outer run asks for 'value'. The re-entrant run asks for 'path'.
      // Every match of the outer run must still come back as its value.
      final result = JSONPath.evaluate(JsonPathOptions(
        path: r'$..x',
        json: data,
        resultType: 'value',
        callback: (v, type, match) {
          if (reentered) return;
          reentered = true;
          JSONPath.evaluate(JsonPathOptions(
            path: r'$..x',
            json: {
              'inner': {'x': 100},
            },
            resultType: 'path',
          ));
        },
      ));

      expect(result, equals([1, 2]));
    });

    // ── sandbox ──────────────────────────────────────────────────────────
    test('inner sandbox does not leak into the outer run', () {
      final data = {
        'seed': {'n': 7},
        'other': {'n': 9},
      };
      var reentered = false;

      // The outer filter reads @limit from its own sandbox. The re-entrant
      // run installs a sandbox of its own, so a leaked map would take @limit
      // away from the outer run and its next filter would blow up (or, with
      // ignoreEvalErrors, silently stop matching).
      final result = JSONPath.evaluate(JsonPathOptions(
        path: r'$..[?(@.n > @limit)]',
        json: data,
        sandbox: const {'limit': 5},
        callback: (v, type, match) {
          if (reentered) return;
          reentered = true;
          JSONPath.evaluate(JsonPathOptions(
            path: r'$..n',
            json: const {'n': 100},
            sandbox: const {'limit': 1000},
          ));
        },
      ));

      expect(
        result,
        equals([
          {'n': 7},
          {'n': 9},
        ]),
      );
    });

    // ── eval mode ────────────────────────────────────────────────────────
    test('inner eval: false does not disable eval for the outer run', () {
      final data = {
        'seed': {'n': 7},
        'other': {'n': 9},
      };
      var reentered = false;

      // The outer run is allowed to evaluate filters. The re-entrant run has
      // eval disabled; that must not make the outer run's next filter throw
      // 'Eval [?(expr)] prevented.'
      final result = JSONPath.evaluate(JsonPathOptions(
        path: r'$..[?(@.n > 5)]',
        json: data,
        callback: (v, type, match) {
          if (reentered) return;
          reentered = true;
          JSONPath.evaluate(JsonPathOptions(
            path: r'$..n',
            json: const {'n': 100},
            eval: false,
          ));
        },
      ));

      expect(
        result,
        equals([
          {'n': 7},
          {'n': 9},
        ]),
      );
    });

    // ── ignoreEvalErrors ─────────────────────────────────────────────────
    test('inner ignoreEvalErrors: false does not re-enable throwing', () {
      // The first filter matches `first` (so the second filter runs, matches
      // 9 and fires the callback), then the first filter throws on `second`
      // because @missing is undefined. The outer run tolerates that and drops
      // `second`; a leaked strict flag would make it rethrow instead.
      final data = {
        'a': {
          'first': {
            'x': 1,
            'b': [9, 1]
          },
          'second': {'z': 1}
        }
      };
      var reentered = false;

      final result = JSONPath.evaluate(JsonPathOptions(
        path: r'$.a[?(@.x > 0 || @missing)].b[?(@ > 5)]',
        json: data,
        ignoreEvalErrors: true,
        callback: (v, type, match) {
          if (reentered) return;
          reentered = true;
          JSONPath.evaluate(JsonPathOptions(
            path: r'$..n',
            json: const {'n': 100},
            ignoreEvalErrors: false,
          ));
        },
      ));

      expect(result, equals([9]));
    });

    // ── otherTypeCallback ────────────────────────────────────────────────
    test('inner otherTypeCallback does not leak into the outer run', () {
      final data = {
        'seed': {'n': 7},
        'other': {'n': 9},
      };
      var reentered = false;

      // The outer @other() predicate accepts maps. The re-entrant run's
      // predicate accepts nothing, so a leaked callback would make the outer
      // run drop every node it has not yet tested.
      final result = JSONPath.evaluate(JsonPathOptions(
        path: r'$..*[@other()]',
        json: data,
        otherTypeCallback: (v, path, parent, parentProperty) => v is Map,
        callback: (v, type, match) {
          if (reentered) return;
          reentered = true;
          JSONPath.evaluate(JsonPathOptions(
            path: r'$..n',
            json: const {'n': 100},
            otherTypeCallback: (v, path, parent, parentProperty) => false,
          ));
        },
      ));

      expect(
        result,
        equals([
          {'n': 7},
          {'n': 9},
        ]),
      );
    });
  });
}
