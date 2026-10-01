import 'package:test/test.dart';
import 'package:json_path_plus/json_path_plus.dart';

/// RFC 9535 filter selector tests (issue #1).
///
/// Covers:
/// - Bare filter selectors `[?<expr>]` without wrapping parentheses.
/// - The standard `match()` (full match) and `search()` (substring match)
///   function extensions with strict RFC semantics.
/// - The `key()` function (member key / array index of the current node),
///   matching the `json_path` package's `key(@)` for migration parity.
void main() {
  // Payload from issue #1 (Amazon scraper config).
  final amazonPayload = {
    'data-client-side-metrics-info': {'html': 'foo'},
    'data-main-slot:search-result-2': {'asin': 'B00KHB2ZIW'},
    'data-main-slot:search-result-3': {'asin': 'B0DCZS98ZT'},
  };

  group('Issue #1 reproduction', () {
    test(r'$[?match(key(@), "data-main-slot:search-result-.*")] — bare form',
        () {
      final result = JSONPath.query(
        r'$[?match(key(@), "data-main-slot:search-result-.*")]',
        amazonPayload,
      );
      expect(result.length, 2);
      expect((result[0] as Map)['asin'], 'B00KHB2ZIW');
      expect((result[1] as Map)['asin'], 'B0DCZS98ZT');
    });

    test(r'$[?(match(key(@), "..."))] — parenthesized form', () {
      final result = JSONPath.query(
        r'$[?(match(key(@), "data-main-slot:search-result-.*"))]',
        amazonPayload,
      );
      expect(result.length, 2);
    });

    test(r'$[?search(key(@), "search-result")] — search() substring', () {
      final result = JSONPath.query(
        r'$[?search(key(@), "search-result")]',
        amazonPayload,
      );
      expect(result.length, 2);
    });

    test(r'$[?match(key(@), "data-.*")] — full match with wildcard suffix', () {
      final result = JSONPath.query(
        r'$[?match(key(@), "data-.*")]',
        amazonPayload,
      );
      expect(result.length, 3);
    });

    test(r'$[?match(key(@), "^data-")] — prefix-only pattern matches nothing',
        () {
      // match() is a FULL match: "^data-" can only match the exact string
      // "data-" — prefix patterns must use .* (RFC 9535 anchoring).
      final result = JSONPath.query(
        r'$[?match(key(@), "^data-")]',
        amazonPayload,
      );
      expect(result, isEmpty);
    });

    test(r'$[?match(key(@), "search-result")] — full match rejects substrings',
        () {
      // "data-main-slot:search-result-2" does not fully match "search-result".
      final result = JSONPath.query(
        r'$[?match(key(@), "search-result")]',
        amazonPayload,
      );
      expect(result, isEmpty);
    });
  });

  group('RFC 9535 bare filter selectors', () {
    final items = {
      'items': [
        {'name': 'apple', 'price': 10},
        {'name': 'banana', 'price': 25},
        {'name': 'cherry', 'price': 3},
      ],
    };

    test(r'$.items[?@.price > 10] — no parens, no spaces', () {
      final result = JSONPath.query(r'$.items[?@.price > 10].name', items);
      expect(result, ['banana']);
    });

    test(r'$.items[? @.price > 10 ] — spaces around the expression', () {
      final result = JSONPath.query(r'$.items[? @.price > 10 ].name', items);
      expect(result, ['banana']);
    });

    test(r'$.items[?@.name === "banana"] — string equality', () {
      final result =
          JSONPath.query(r'$.items[?@.name === "banana"].price', items);
      expect(result, [25]);
    });

    test(r'$[?@.asin] — truthiness: only null and false are falsy', () {
      final data = {
        'a': {'asin': 'X1'},
        'b': {'other': 1},
        'c': {'asin': null},
      };
      // RFC 9535 test expressions: only null and false yield LogicalFalse.
      // (Unlike JS truthiness, '' and 0 are truthy — so an empty asin WOULD
      // match; use null to model "missing".) 'b' has no asin at all → null.
      final result = JSONPath.query(r'$[?@.asin].asin', data);
      expect(result, ['X1']);
    });

    test(r'$[?@.b] — bare filter on map members', () {
      final data = {
        'a': {'flag': true},
        'b': {'flag': false},
      };
      final result = JSONPath.query(r'$[?@.flag]', data);
      expect(result.length, 1);
      expect(result[0], {'flag': true});
    });

    test(r'$.items[?(@.price > 10)] — paren form still works (regression)', () {
      final result = JSONPath.query(r'$.items[?(@.price > 10)].name', items);
      expect(result, ['banana']);
    });

    test(
        r'bare filter with logical operators: $.items[?@.price > 5 && @.price < 20]',
        () {
      final result =
          JSONPath.query(r'$.items[?@.price > 5 && @.price < 20].name', items);
      expect(result, ['apple']);
    });

    test('bare filter with single-quoted string and nested bracket notation',
        () {
      final data = {
        'items': [
          {
            'tags': ['x'],
            'n': 1
          },
          {
            'tags': ['y'],
            'n': 2
          },
        ],
      };
      final result = JSONPath.query(r"""$.items[?@.tags[0] === 'y'].n""", data);
      expect(result, [2]);
    });

    test('bare filter and paren filter coexist in one path', () {
      // Consecutive selectors drill down: the bare filter keeps members with
      // ok=true, then .inner (an array) is filtered by the paren form.
      final data = {
        'a': {
          'ok': true,
          'inner': [
            {'v': 1},
            {'v': 2}
          ]
        },
        'b': {
          'ok': false,
          'inner': [
            {'v': 3}
          ]
        },
      };
      final result = JSONPath.query(r'$[?@.ok].inner[?(@.v === 2)]', data);
      expect(result, [
        {'v': 2}
      ]);
    });
  });

  group('match() / search() RFC semantics', () {
    final data = {
      'items': [
        {'name': 'abc', 'price': 1},
        {'name': 'bbc', 'price': 2},
      ],
    };

    test('match() is a full match: match(@.name, "b") matches nothing', () {
      // Neither "abc" nor "bbc" is exactly "b" — full match required.
      final result =
          JSONPath.query(r'$.items[?match(@.name, "b")].price', data);
      expect(result, isEmpty);
    });

    test('match(@.name, "a.c") — pattern spans the entire string', () {
      final result =
          JSONPath.query(r'$.items[?match(@.name, "a.c")].price', data);
      expect(result, [1]);
    });

    test('search(@.name, "bb") — substring match', () {
      // "abc" does not contain "bb"; "bbc" does.
      final result =
          JSONPath.query(r'$.items[?search(@.name, "bb")].price', data);
      expect(result, [2]);
    });

    test('match() returns false for non-string first argument', () {
      final d = {
        'a': 10,
        'b': 'ten',
      };
      final result = JSONPath.query(r'$[?match(@, "^10$")]', d);
      expect(result.length, 0); // 10 is a number → LogicalFalse per RFC 9535
    });

    test('match() returns false (no throw) for an invalid regex', () {
      final d = {'a': 'abc'};
      final result = JSONPath.query(r'$[?match(@.a, "[")]', d);
      expect(result, isEmpty);
    });

    test('search() returns false (no throw) for an invalid regex', () {
      final d = {'a': 'abc'};
      final result = JSONPath.query(r'$[?search(@.a, "(*")]', d);
      expect(result, isEmpty);
    });

    test('user sandbox can shadow the built-ins', () {
      final d = {'a': 'abc'};
      // A sandbox entry named like a built-in takes precedence: the shadowed
      // match() returns true even though the RFC built-in would reject the
      // pattern — proving the override wins. This is the extension point for
      // user-defined filter functions.
      final opts = JsonPathOptions(
        path: r'$[?match(@, "zzz")]',
        json: d,
        sandbox: {
          'match': BuiltInFunction((args) => args.isNotEmpty),
        },
      );
      final result = JSONPath.evaluate(opts);
      expect(result.length, 1);
    });
  });

  group('key() function', () {
    test('key(@) in object context returns the member key', () {
      final d = {
        'x': 1,
        'y': 2,
      };
      final result = JSONPath.query(r'$[?key(@) === "y"]', d);
      expect(result, [2]);
    });

    test('key() with no argument also works', () {
      final d = {'x': 1, 'y': 2};
      final result = JSONPath.query(r'$[?key() === "x"]', d);
      expect(result, [1]);
    });

    test('key(@) in array context returns the index as a string', () {
      final d = {
        'items': ['a', 'b', 'c']
      };
      final result = JSONPath.query(r'$.items[?key(@) === "1"]', d);
      expect(result, ['b']);
    });

    test('key(@) matches @property behavior', () {
      final d = {'x': 1, 'y': 2};
      final byKey = JSONPath.query(r'$[?key(@) === "y"]', d);
      final byProp = JSONPath.query(r'$[?@property === "y"]', d);
      expect(byKey, byProp);
    });

    test('key(@) inside match() on nested maps', () {
      final d = {
        'data': {
          'slot-1': {'v': 1},
          'other': {'v': 2},
          'slot-22': {'v': 3},
        },
      };
      final result = JSONPath.query(
        r'$.data[?match(key(@), "slot-[0-9]+")].v',
        d,
      );
      expect(result, [1, 3]);
    });
  });

  group('String.match() method proxy', () {
    test(r'$.items[?@.name.match("^a")] — truthy on first match', () {
      final d = {
        'items': [
          {'name': 'apple'},
          {'name': 'banana'},
        ],
      };
      final result = JSONPath.query(r'$.items[?@.name.match("^a")].name', d);
      expect(result, ['apple']);
    });

    test(r'$.items[?@.name.match("an")] — substring match works', () {
      final d = {
        'items': [
          {'name': 'apple'},
          {'name': 'banana'},
        ],
      };
      final result = JSONPath.query(r'$.items[?@.name.match("an")].name', d);
      expect(result, ['banana']);
    });
  });

  group('Regex literals /re/flags in filter expressions (issue #7)', () {
    final items = {
      'items': [
        {'name': 'apple'},
        {'name': 'banana'},
      ],
    };

    test(r'$.items[?@.name.match(/^a/)].name — issue #7 repro', () {
      final result =
          JSONPath.query(r'$.items[?@.name.match(/^a/)].name', items);
      expect(result, ['apple']);
    });

    test(r'$.items[?(@.name.match(/^a/))].name — parenthesized form', () {
      final result =
          JSONPath.query(r'$.items[?(@.name.match(/^a/))].name', items);
      expect(result, ['apple']);
    });

    test(
        r'$.items[?@.name.match(/^b/)].name — non-matching literal filters out',
        () {
      final result =
          JSONPath.query(r'$.items[?@.name.match(/^b/)].name', items);
      expect(result, ['banana']);
    });

    test(
        r'$.items[?@.name.match(/an/)].name — unanchored literal finds substring',
        () {
      final result =
          JSONPath.query(r'$.items[?@.name.match(/an/)].name', items);
      expect(result, ['banana']);
    });

    test(r'$.items[?@.name.match(/^A/i)].name — flags: case-insensitive', () {
      final result =
          JSONPath.query(r'$.items[?@.name.match(/^A/i)].name', items);
      expect(result, ['apple']);
    });

    test(r'escaped slash in a regex literal: @.name.match(/^a\/b/)', () {
      final d = {
        'items': [
          {'name': 'a/b'},
          {'name': 'ab'},
        ],
      };
      final result = JSONPath.query(r'$.items[?@.name.match(/^a\/b/)].name', d);
      expect(result, ['a/b']);
    });

    test('match() accepts a regex object: /^a/ keeps its JS prefix meaning',
        () {
      // The regex literal is self-contained — no RFC anchoring is applied.
      // The string form match(@.name, "^a") matches nothing (full match),
      // but the regex form behaves like JSONPath-Plus.
      final result =
          JSONPath.query(r'$.items[?match(@.name, /^a/)].name', items);
      expect(result, ['apple']);
    });

    test('search() accepts a regex object: /^ban/ anchors inside the literal',
        () {
      final result =
          JSONPath.query(r'$.items[?search(@.name, /^ban/)].name', items);
      expect(result, ['banana']);
    });

    test('match() still rejects non-string values with a regex object', () {
      final d = {'a': 10, 'b': 'ten'};
      final result = JSONPath.query(r'$[?match(@, /^10$/)]', d);
      expect(result, isEmpty); // 10 is a number → LogicalFalse per RFC 9535
    });

    test('division is not confused with a regex literal', () {
      // `/` following an operand stays the division operator.
      expect(SafeEval.evaluate('8 / 2 / 2', {}), equals(2.0));
      expect(SafeEval.evaluate('(4 + 4) / 2', {}), equals(4.0));
    });
  });

  group('Regex literal contract (review findings on #16)', () {
    test('an invalid literal throws one FormatException naming the literal',
        () {
      // A lexically valid literal with an invalid *pattern* is not a JSONPath
      // syntax error, so it must not crash the whole query from inside the
      // filter the way an uncaught FormatException would.
      expect(
        () => JSONPath.query(r'$.items[?@.name.match(/(/)].name', {
          'items': [
            {'name': 'apple'}
          ]
        }),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            allOf(contains('/(/'), contains('Unterminated group')))),
      );
    });

    test('an invalid literal is reported even when not inside a filter call',
        () {
      expect(
        () => JSONPath.query(r'$.items[?/(/)].name', {
          'items': [
            {'name': 'apple'}
          ]
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('/(/'))),
      );
    });

    test('typeof a regex literal is "object", matching JS', () {
      expect(SafeEval.evaluate('typeof /a/', {}), equals('object'));
    });

    test('unknown regex flags are rejected instead of silently dropped', () {
      // `/a/qq` used to behave exactly like `/a/`, hiding a config typo.
      expect(
        () => SafeEval.evaluate('/a/qq', {}),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('Unknown regex flag "q"'))),
      );
    });

    test('the no-op flags g, y and d are still accepted', () {
      expect(SafeEval.evaluate('typeof /a/g', {}), equals('object'));
      expect(SafeEval.evaluate('typeof /a/y', {}), equals('object'));
      expect(SafeEval.evaluate('typeof /a/d', {}), equals('object'));
    });

    test('a regex literal is compiled at parse time, not while evaluating', () {
      // Compilation happens once, when the literal is parsed: a literal in the
      // never-taken branch of a ternary is still compiled, so it still fails.
      // If the pattern were compiled lazily during evaluation this would
      // return 2 — which is exactly the bug (a compile per evaluation, in a
      // filter hot loop over N candidates).
      expect(
        () => SafeEval.evaluate('/(/ ? 1 : 2', {}),
        throwsA(isA<FormatException>()),
      );
      expect(SafeEval.evaluate('/^a/ ? 1 : 2', {}), equals(1));
    });

    group(r'@ inside a literal is not rewritten to _$_v', () {
      final data = {
        'items': [
          {'name': 'a@'},
          {'name': 'a@b'},
          {'name': 'plain'},
        ]
      };

      test(r'/^a@$/ matches "a@" — the literal keeps its own @', () {
        // Fully anchored so the assertion is about the `@` surviving the
        // rewrite, not about regex-literal substring semantics.
        final result =
            JSONPath.query(r'$.items[?@.name.match(/^a@$/)].name', data);
        expect(result, ['a@']);
      });

      test(r'an email-style pattern /2 matches "a@b"', () {
        final result = JSONPath.query(
            r'$.items[?@.name.match(/^[^@]+@[^@]*$/)].name', data);
        expect(result, ['a@', 'a@b']);
      });

      test(r'a negated class /[^@]+/ still excludes @', () {
        final result =
            JSONPath.query(r'$.items[?@.name.match(/^[^@]+$/)].name', data);
        expect(result, ['plain']);
      });

      test(r'a @ inside a string pattern is preserved too', () {
        // Pre-existing bug, same root cause: the lone-@ rewrite ran over the
        // raw text and hit string literals as well.
        final result =
            JSONPath.query(r'$.items[?match(@.name, "^a@")].name', data);
        expect(result, ['a@']);
      });

      test('the @ magic variables outside literals still work', () {
        expect(
            JSONPath.query(r'$.items[?(@.name !== "zzz")].name', data).length,
            3);
        expect(JSONPath.query(r'$.items[?@.name === "a@"].name', data), ['a@']);
      });
    });

    group('filter extraction is regex-literal aware', () {
      final data = {
        'items': [
          {'name': 'x]'},
          {'name': 'plain'},
        ]
      };

      test(r'a char class holding ] survives extraction — [? ... ] form', () {
        final result =
            JSONPath.query(r'$.items[?@.name.match(/^[x\]]+$/)].name', data);
        expect(result, ['x]']);
      });

      test(r'a char class holding ] survives extraction — [?(...)] form', () {
        final result =
            JSONPath.query(r'$.items[?(@.name.match(/^[x\]]+$/))].name', data);
        expect(result, ['x]']);
      });

      test(r'an escaped ] also survives extraction', () {
        final d = {
          'items': [
            {'name': 'a]b'},
            {'name': 'plain'},
          ]
        };
        final result =
            JSONPath.query(r'$.items[?@.name.match(/^a\]b$/)].name', d);
        expect(result, ['a]b']);
      });

      test(r'a ] inside a string pattern does not truncate extraction', () {
        final d = {
          'items': [
            {'name': 'x]y'},
            {'name': 'zz'},
          ]
        };
        final result =
            JSONPath.query(r'$.items[?match(@.name, "x]y")].name', d);
        expect(result, ['x]y']);
      });

      test('a filter whose literal holds ) does not truncate extraction', () {
        final d = {
          'items': [
            {'name': 'a)b'},
            {'name': 'plain'},
          ]
        };
        final result =
            JSONPath.query(r'$.items[?(@.name.match(/^a\)[b]$/))].name', d);
        expect(result, ['a)b']);
      });

      test('division inside a filter is still division', () {
        final d = {
          'items': [
            {'n': 4, 'name': 'four'},
            {'n': 1, 'name': 'one'},
          ]
        };
        expect(JSONPath.query(r'$.items[?(@.n / 2 > 1)].name', d), ['four']);
      });

      test('plain index and bracket-property paths are untouched', () {
        expect(JSONPath.toPathArray(r'$.a[0].b'), [r'$', 'a', '0', 'b']);
        expect(JSONPath.toPathArray(r"$.a['b.c'].d"), [r'$', 'a', 'b.c', 'd']);
        expect(JSONPath.toPathArray(r'$.a[0:2].b'), [r'$', 'a', '0:2', 'b']);
      });
    });
  });
}
