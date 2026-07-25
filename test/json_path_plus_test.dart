import 'dart:convert';
import 'package:test/test.dart';
import 'package:json_path_plus/json_path_plus.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════
  // Section A: Basic path syntax
  // ═══════════════════════════════════════════════════════════════════

  group('A. Basic path syntax', () {
    test(r'$.store.book[0].title — standard dot + bracket', () {
      final data = {'store': {'book': [{'title': 'A'}]}};
      final result = JSONPath.query(r'$.store.book[0].title', data);
      expect(result, equals(['A']));
    });

    test(r"$['store']['book'][0]['title'] — bracket notation", () {
      final data = {'store': {'book': [{'title': 'A'}]}};
      final result =
          JSONPath.query(r"$['store']['book'][0]['title']", data);
      expect(result, equals(['A']));
    });

    test(r'$.store.book[*].title — wildcard produces all titles', () {
      final data = {
        'store': {
          'book': [
            {'title': 'A'},
            {'title': 'B'},
            {'title': 'C'},
          ],
        },
      };
      final result = JSONPath.query(r'$.store.book[*].title', data);
      expect(result, equals(['A', 'B', 'C']));
    });

    test(r'$..title — recursive descent', () {
      final data = {'store': {'book': [{'title': 'A'}]}};
      final result = JSONPath.query(r'$..title', data);
      expect(result, equals(['A']));
    });

    test(r'$..book[0] — recursive descent + index', () {
      final data = {'store': {'book': [{'title': 'A'}]}};
      final result = JSONPath.query(r'$..book[0]', data);
      expect(result.length, equals(1));
      expect((result[0] as Map).containsKey('title'), isTrue);
      expect((result[0] as Map)['title'], equals('A'));
    });

    test(r'$..book[*] — recursive descent + wildcard', () {
      final data = {'store': {'book': [{'title': 'A'}]}};
      final result = JSONPath.query(r'$..book[*]', data);
      expect(result.length, equals(1));
      expect((result[0] as Map)['title'], equals('A'));
    });

    test(r"$['store']['book'][0] — returns the whole object", () {
      final data = {'store': {'book': [{'title': 'A'}]}};
      final result = JSONPath.query(r"$['store']['book'][0]", data);
      expect(result.length, equals(1));
      expect((result[0] as Map)['title'], equals('A'));
    });

    test(r'Root $ returns root', () {
      final data = {'a': 1};
      final result = JSONPath.query(r'$', data);
      expect(result, equals([{'a': 1}]));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section B: Filter expressions with @property
  // ═══════════════════════════════════════════════════════════════════

  group('B. Filter expressions', () {
    test('@property === key name in object context', () {
      final data = {
        'store': {'name': 'main', 'id': 1},
      };
      final result = JSONPath.query(
        r"$[?(@property === 'store')]",
        data,
      );
      expect(result.length, equals(1));
      expect((result[0] as Map)['name'], equals('main'));
    });

    test('@.property truthy check', () {
      final data = {
        'items': [
          {'name': 'a', 'zoomImageUrl1': 'url1'},
          {'name': 'b', 'other': 'url2'},
        ],
      };
      final result = JSONPath.query(
        r'$.items[?(@.zoomImageUrl1)]',
        data,
      );
      expect(result.length, equals(1));
      expect((result[0] as Map)['name'], equals('a'));
    });

    test('@property === value && @ === value', () {
      final data = {
        'items': [
          {'key': 'title', 'val': 'A'},
          {'key': 'author', 'val': 'B'},
        ],
      };
      // Filter by matching a property within each map item.
      // `@.key` accesses the "key" property of the current map item.
      final result = JSONPath.query(
        r'$.items[?(@.key === "title")].val',
        data,
      );
      expect(result, equals(['A']));
    });

    test('@property in array context is index', () {
      final data = [10, 20, 30];
      final result = JSONPath.query(
        r'$[?(@property === "1")]',
        data,
      );
      expect(result, equals([20]));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section B-extra: Walgreens @property.indexOf filter
  // ═══════════════════════════════════════════════════════════════════

  group('B-extra: Walgreens @property.indexOf filter', () {
    test('filters object keys starting with zoomImageUrl', () {
      final data = jsonDecode('''
      {
        "productInfo": {
          "filmStripUrl": [
            {
              "stripUrl1": "...",
              "largeImageUrl1": "...",
              "zoomImageUrl1": "//pics.example.com/image1_900.jpg"
            },
            {
              "stripUrl2": "...",
              "largeImageUrl2": "...",
              "zoomImageUrl2": "//pics.example.com/image2_900.jpg"
            }
          ]
        }
      }
      ''') as Map<String, dynamic>;

      final result = JSONPath.evaluate(JsonPathOptions(
        path: r'$.productInfo.filmStripUrl[*][?(@property.indexOf("zoomImageUrl") === 0)]',
        json: data,
        resultType: 'value',
      ));

      expect(result, isA<List>());
      final list = result as List;
      expect(list.length, equals(2));
      expect(list[0], equals('//pics.example.com/image1_900.jpg'));
      expect(list[1], equals('//pics.example.com/image2_900.jpg'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section C: Eval context for filters
  // ═══════════════════════════════════════════════════════════════════

  group('C. Eval context', () {
    test('@.property access in filter', () {
      final data = {
        'books': [
          {'title': 'A', 'price': 10},
          {'title': 'B', 'price': 20},
        ],
      };
      final result = JSONPath.query(
        r'$.books[?(@.price > 15)].title',
        data,
      );
      expect(result, equals(['B']));
    });

    test('@.nested.key access', () {
      final data = {
        'items': [
          {'meta': {'level': 1}, 'name': 'first'},
          {'meta': {'level': 2}, 'name': 'second'},
        ],
      };
      final result = JSONPath.query(
        r'$.items[?(@.meta.level > 1)].name',
        data,
      );
      expect(result, equals(['second']));
    });

    test('Comparisons: ===, !==, <, >, <=, >=', () {
      final data = {'items': [1, 5, 9]};
      expect(
        JSONPath.query(r'$.items[?(@ === 5)]', data),
        equals([5]),
      );
      expect(
        JSONPath.query(r'$.items[?(@ !== 3)]', data),
        equals([1, 5, 9]),
      );
      expect(
        JSONPath.query(r'$.items[?(@ > 5)]', data),
        equals([9]),
      );
      expect(
        JSONPath.query(r'$.items[?(@ < 5)]', data),
        equals([1]),
      );
    });

    test('Boolean operators: && and ||', () {
      final data = {
        'items': [
          {'a': true, 'b': true},
          {'a': true, 'b': false},
        ],
      };
      final result = JSONPath.query(
        r'$.items[?(@.a && @.b)]',
        data,
      );
      expect(result.length, equals(1));
    });

    test('String method: .indexOf()', () {
      final data = {'items': ['hello', 'world', 'hello world']};
      final result = JSONPath.query(
        r"$.items[?(@.indexOf('world') !== -1)]",
        data,
      );
      expect(result, equals(['world', 'hello world']));
    });

    test('String method: .includes()', () {
      final data = {'items': ['foo', 'foobar', 'baz']};
      final result = JSONPath.query(
        r"$.items[?(@.includes('foo'))]",
        data,
      );
      expect(result, equals(['foo', 'foobar']));
    });

    test('String method: .startsWith()', () {
      final data = {'items': ['apple', 'apricot', 'banana']};
      final result = JSONPath.query(
        r"$.items[?(@.startsWith('ap'))]",
        data,
      );
      expect(result, equals(['apple', 'apricot']));
    });

    test('String method: .endsWith()', () {
      final data = {'items': ['cat', 'bat', 'dog']};
      final result = JSONPath.query(
        r"$.items[?(@.endsWith('at'))]",
        data,
      );
      expect(result, equals(['cat', 'bat']));
    });

    test('Arithmetic in filter', () {
      final data = {'items': [1, 2, 3, 4, 5]};
      final result = JSONPath.query(
        r'$.items[?(@ * 2 > 6)]',
        data,
      );
      expect(result, equals([4, 5]));
    });

    test('Negation operator !', () {
      final data = {'items': [true, false, null, 0]};
      final result = JSONPath.query(
        r'$.items[?(!@)]',
        data,
      );
      expect(result, equals([false, null, 0]));
    });

    test('Ternary operator', () {
      final data = {'items': [1, 2, 3]};
      final result = JSONPath.query(
        r'$.items[?(@ > 1 ? true : false)]',
        data,
      );
      expect(result, equals([2, 3]));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section D: Type operators
  // ═══════════════════════════════════════════════════════════════════

  group('D. Type operators', () {
    test('@string() keeps strings', () {
      final data = {'items': ['hello', 42, true, null]};
      final result = JSONPath.query(r'$.items[*]@string()', data);
      expect(result, equals(['hello']));
    });

    test('@number() keeps numbers', () {
      final data = {'items': ['hello', 42, 19.99, true, null]};
      final result = JSONPath.query(r'$.items[*]@number()', data);
      expect(result, equals([42, 19.99]));
    });

    test('@integer() keeps integers', () {
      final data = {'items': [42, 19.99, 3.0, 'hello']};
      final result = JSONPath.query(r'$.items[*]@integer()', data);
      expect(result, containsAll([42]));
    });

    test('@boolean() keeps booleans', () {
      final data = {'items': [true, false, 'hello', 42]};
      final result = JSONPath.query(r'$.items[*]@boolean()', data);
      expect(result, equals([true, false]));
    });

    test('@null() keeps nulls', () {
      final data = {'items': [null, 'hello', 42]};
      final result = JSONPath.query(r'$.items[*]@null()', data);
      expect(result, equals([null]));
    });

    test('@array() keeps arrays', () {
      final data = {'items': [[1, 2], 'hello', {'a': 1}]};
      final result = JSONPath.query(r'$.items[*]@array()', data);
      expect(result.length, equals(1));
      expect(result[0], equals([1, 2]));
    });

    test('@object() keeps objects (maps)', () {
      final data = {'items': [[1, 2], 'hello', {'a': 1}]};
      final result = JSONPath.query(r'$.items[*]@object()', data);
      expect(result.length, equals(1));
      expect((result[0] as Map)['a'], equals(1));
    });

    test('@scalar() keeps non-object values', () {
      final data = {'items': ['hello', 42, true, [1], {'a': 1}, null]};
      final result = JSONPath.query(r'$.items[*]@scalar()', data);
      expect(result, equals(['hello', 42, true, null]));
    });

    test('@other() with callback', () {
      final data = {'items': ['a', 'b', 'c']};
      final result = JSONPath.evaluate(JsonPathOptions(
        path: r'$.items[*]@other()',
        json: data,
        otherTypeCallback: (val, path, parent, parentProp) {
          return val is String && val.length == 1;
        },
      ));
      expect(result, equals(['a', 'b', 'c']));
    });

    test('@other() throws without callback', () {
      final data = {'items': ['a']};
      expect(
        () => JSONPath.query(r'$.items[*]@other()', data),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section E: ~ property-name operator and ^ parent selector
  // ═══════════════════════════════════════════════════════════════════

  group('E. ~ property-name and ^ parent selector', () {
    test('~ returns property name', () {
      final data = {'book': [{'title': 'A'}]};
      final result = JSONPath.query(r'$.book[0].title~', data);
      expect(result, equals(['title']));
    });

    test('^ returns parent of matched node', () {
      final data = {
        'store': {
          'book': [
            {'title': 'A'},
          ],
        },
      };
      final result = JSONPath.query(r'$.store.book[0]^', data);
      expect(result.length, equals(1));
      expect(result[0], isA<List>());
      expect((result[0] as List)[0], equals({'title': 'A'}));
    });

    test('title^ returns parent object', () {
      final data = {
        'store': {
          'book': [
            {'title': 'A'},
          ],
        },
      };
      final result = JSONPath.query(r'$.store.book[0].title^', data);
      expect(result.length, equals(1));
      expect(result[0], equals({'title': 'A'}));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section F: Array slice [start:end:step]
  // ═══════════════════════════════════════════════════════════════════

  group('F. Array slice', () {
    test(r'$[0:2] returns first two', () {
      final data = ['a', 'b', 'c'];
      final result = JSONPath.query(r'$[0:2]', data);
      expect(result, equals(['a', 'b']));
    });

    test(r'$[1:3] returns middle two', () {
      final data = ['a', 'b', 'c'];
      final result = JSONPath.query(r'$[1:3]', data);
      expect(result, equals(['b', 'c']));
    });

    test(r'$[::-1] reverses', () {
      final data = ['a', 'b', 'c'];
      final result = JSONPath.query(r'$[::-1]', data);
      expect(result, equals(['c', 'b', 'a']));
    });

    test(r'$[0:5:2] steps by 2', () {
      final data = ['a', 'b', 'c', 'd', 'e'];
      final result = JSONPath.query(r'$[0:5:2]', data);
      expect(result, equals(['a', 'c', 'e']));
    });

    test(r'$[:2] returns first two (omitted start)', () {
      final data = ['a', 'b', 'c'];
      final result = JSONPath.query(r'$[:2]', data);
      expect(result, equals(['a', 'b']));
    });

    test('Negative start index', () {
      final data = ['a', 'b', 'c', 'd'];
      final result = JSONPath.query(r'$[-2:]', data);
      expect(result, equals(['c', 'd']));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section G: Dynamic property [(expr)]
  // ═══════════════════════════════════════════════════════════════════

  group('G. Dynamic property', () {
    test(r'$[(1+2)] evaluates to index 3', () {
      final data = [10, 20, 30, 40, 50];
      final result = JSONPath.query(r'$[(1+2)]', data);
      expect(result, equals([40]));
    });

    test(r'$[(0+1)] evaluates to index 1', () {
      final data = ['a', 'b', 'c'];
      final result = JSONPath.query(r'$[(0+1)]', data);
      expect(result, equals(['b']));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section H: Comma-separated keys
  // ═══════════════════════════════════════════════════════════════════

  group('H. Comma-separated keys', () {
    test(r'$[0,1] returns first two elements', () {
      final data = ['a', 'b', 'c'];
      final result = JSONPath.query(r'$[0,1]', data);
      expect(result, equals(['a', 'b']));
    });

    test(r'$.store.book[0,1].title returns two titles', () {
      final data = {
        'store': {
          'book': [
            {'title': 'A'},
            {'title': 'B'},
            {'title': 'C'},
          ],
        },
      };
      final result = JSONPath.query(r'$.store.book[0,1].title', data);
      expect(result, equals(['A', 'B']));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section I: Backtick-escaped property
  // ═══════════════════════════════════════════════════════════════════

  group('I. Backtick-escaped property', () {
    test('backtick escapes numeric key in object', () {
      final data = {
        'book': {
          '0': 'zero-val',
          '1': 'one-val',
        },
      };
      final result = JSONPath.query(r"$.book.`0`", data);
      expect(result, equals(['zero-val']));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section J: Options — resultType, wrap, flatten, callback
  // ═══════════════════════════════════════════════════════════════════

  group('J. Options', () {
    group('resultType', () {
      test('resultType: "value" (default)', () {
        final data = {'store': {'book': [{'title': 'A'}]}};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.store.book[0].title',
          json: data,
          resultType: 'value',
        ));
        expect(result, equals(['A']));
      });

      test('resultType: "path"', () {
        final data = {'store': {'book': [{'title': 'A'}]}};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.store.book[0].title',
          json: data,
          resultType: 'path',
        ));
        expect(result, equals([r"$['store']['book'][0]['title']"]));
      });

      test('resultType: "pointer"', () {
        final data = {'store': {'book': [{'title': 'A'}]}};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.store.book[0].title',
          json: data,
          resultType: 'pointer',
        ));
        expect(result, equals(['/store/book/0/title']));
      });

      test('resultType: "parent"', () {
        final data = {'store': {'book': [{'title': 'A'}]}};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.store.book[0].title',
          json: data,
          resultType: 'parent',
        ));
        expect(result.length, equals(1));
        expect((result[0] as Map)['title'], equals('A'));
      });

      test('resultType: "parentProperty"', () {
        final data = {'store': {'book': [{'title': 'A'}]}};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.store.book[0].title',
          json: data,
          resultType: 'parentProperty',
        ));
        expect(result, equals(['title']));
      });

      test('resultType: "all"', () {
        final data = {'store': {'book': [{'title': 'A'}]}};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.store.book[0].title',
          json: data,
          resultType: 'all',
        ));
        expect(result, isA<List>());
        final match = (result as List)[0] as JsonPathMatch;
        expect(match.value, equals('A'));
        expect(match.pointer, equals('/store/book/0/title'));
        expect(match.pathString, isNotNull);
      });
    });

    group('wrap', () {
      test('wrap: true — empty results return []', () {
        final data = {'a': 1};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.nonexistent',
          json: data,
          wrap: true,
        ));
        expect(result, equals([]));
      });

      test('wrap: false — empty results return null', () {
        final data = {'a': 1};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.nonexistent',
          json: data,
          wrap: false,
        ));
        expect(result, isNull);
      });

      test('wrap: false — single result returns value directly', () {
        final data = {'a': 1};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.a',
          json: data,
          wrap: false,
        ));
        expect(result, equals(1));
      });

      test('wrap: false — multiple results still return list', () {
        final data = {'items': [1, 2]};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.items[*]',
          json: data,
          wrap: false,
        ));
        expect(result, equals([1, 2]));
      });
    });

    group('flatten', () {
      test('flatten: true flattens nested arrays', () {
        final data = {'items': [[1, 2], [3, 4]]};
        final result = JSONPath.evaluate(JsonPathOptions(
          path: r'$.items[*]',
          json: data,
          flatten: true,
        ));
        expect(result, equals([1, 2, 3, 4]));
      });
    });

    group('callback', () {
      test('callback is invoked for each match', () {
        final data = {'items': ['a', 'b', 'c']};
        final captured = <String>[];
        JSONPath.evaluate(JsonPathOptions(
          path: r'$.items[*]',
          json: data,
          callback: (value, type, full) {
            captured.add(type);
          },
        ));
        expect(captured, equals(['value', 'value', 'value']));
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section K: eval parameter
  // ═══════════════════════════════════════════════════════════════════

  group('K. eval parameter', () {
    test('eval: false throws on filter expression', () {
      final data = {'items': [1, 2, 3]};
      expect(
        () => JSONPath.evaluate(JsonPathOptions(
          path: r'$.items[?(@ > 1)]',
          json: data,
          eval: false,
        )),
        throwsA(isA<StateError>()),
      );
    });

    test('eval: false throws on dynamic property', () {
      final data = [1, 2, 3];
      expect(
        () => JSONPath.evaluate(JsonPathOptions(
          path: r'$[(0+1)]',
          json: data,
          eval: false,
        )),
        throwsA(isA<StateError>()),
      );
    });

    test('ignoreEvalErrors: true returns false for bad eval', () {
      final data = {'items': [1, 2, 3]};
      final result = JSONPath.evaluate(JsonPathOptions(
        path: r'$.items[?(@.nonexistentMethod())]',
        json: data,
        ignoreEvalErrors: true,
      ));
      expect(result, equals([]));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section L: Sandboxed expression evaluator
  // ═══════════════════════════════════════════════════════════════════

  group('L. SandboxedScript / SafeEval', () {
    test('basic arithmetic', () {
      expect(SafeEval.evaluate('1 + 2', {}), equals(3));
      expect(SafeEval.evaluate('10 - 3', {}), equals(7));
      expect(SafeEval.evaluate('4 * 5', {}), equals(20));
      expect(SafeEval.evaluate('10 / 3', {}), equals(10 / 3));
      expect(SafeEval.evaluate('10 % 3', {}), equals(1));
    });

    test('comparisons', () {
      expect(SafeEval.evaluate('1 === 1', {}), equals(true));
      expect(SafeEval.evaluate('1 !== 2', {}), equals(true));
      expect(SafeEval.evaluate('1 < 2', {}), equals(true));
      expect(SafeEval.evaluate('2 > 1', {}), equals(true));
      expect(SafeEval.evaluate('1 <= 1', {}), equals(true));
      expect(SafeEval.evaluate('1 >= 2', {}), equals(false));
    });

    test('boolean logic', () {
      expect(SafeEval.evaluate('true && false', {}), equals(false));
      expect(SafeEval.evaluate('true || false', {}), equals(true));
      expect(SafeEval.evaluate('!true', {}), equals(false));
    });

    test('variable lookup', () {
      expect(
        SafeEval.evaluate('x + 1', {'x': 10}),
        equals(11),
      );
    });

    test('string concatenation', () {
      expect(
        SafeEval.evaluate('"hello" + " world"', {}),
        equals('hello world'),
      );
    });

    test('string methods', () {
      expect(
        SafeEval.evaluate("'hello'.indexOf('ll')", {}),
        equals(2),
      );
      expect(
        SafeEval.evaluate("'hello'.includes('ell')", {}),
        equals(true),
      );
      expect(
        SafeEval.evaluate("'hello'.startsWith('hel')", {}),
        equals(true),
      );
      expect(
        SafeEval.evaluate("'hello'.endsWith('llo')", {}),
        equals(true),
      );
    });

    test('typeof', () {
      expect(SafeEval.evaluate('typeof "hello"', {}), equals('string'));
      expect(SafeEval.evaluate('typeof 42', {}), equals('number'));
      expect(SafeEval.evaluate('typeof null', {}), equals('null'));
      expect(SafeEval.evaluate('typeof true', {}), equals('boolean'));
    });

    test('ternary', () {
      expect(
        SafeEval.evaluate('true ? 1 : 2', {}),
        equals(1),
      );
      expect(
        SafeEval.evaluate('false ? 1 : 2', {}),
        equals(2),
      );
    });

    test('null literals', () {
      expect(SafeEval.evaluate('null', {}), isNull);
      expect(SafeEval.evaluate('null === null', {}), equals(true));
    });

    test('nested property access', () {
      expect(
        SafeEval.evaluate('a.b.c', {'a': {'b': {'c': 42}}}),
        equals(42),
      );
    });

    test('computed property access', () {
      expect(
        SafeEval.evaluate("a['b']", {'a': {'b': 'found'}}),
        equals('found'),
      );
    });

    test('length property', () {
      expect(
        SafeEval.evaluate("'hello'.length", {}),
        equals(5),
      );
    });

    test('.toString() method', () {
      expect(
        SafeEval.evaluate('(42).toString()', {}),
        equals('42'),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Section M: Caching
  // ═══════════════════════════════════════════════════════════════════

  group('M. Caching', () {
    test('toPathArray caches results', () {
      JSONPath.cache.clear();
      final expr = r'$.store.book[0].title';
      final result1 = JSONPath.toPathArray(expr);
      final result2 = JSONPath.toPathArray(expr);
      expect(result1, equals(result2));
      expect(JSONPath.cache.containsKey(expr), isTrue);
    });

    test('cache can be cleared', () {
      JSONPath.cache.clear();
      final expr = r'$.a.b';
      JSONPath.toPathArray(expr);
      expect(JSONPath.cache.containsKey(expr), isTrue);
      JSONPath.cache.remove(expr);
      expect(JSONPath.cache.containsKey(expr), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Static methods
  // ═══════════════════════════════════════════════════════════════════

  group('Static utility methods', () {
    test('toPathArray — bracket notation', () {
      final result = JSONPath.toPathArray(r"$['a']['b'][0]");
      expect(result, equals([r'$', 'a', 'b', '0']));
    });

    test('toPathArray — dot notation', () {
      final result = JSONPath.toPathArray(r'$.a.b');
      expect(result, equals([r'$', 'a', 'b']));
    });

    test('toPathString — path array to string', () {
      final result = JSONPath.toPathString([r'$', 'a', 'b', '0']);
      expect(result, equals(r"$['a']['b'][0]"));
    });

    test('toPointer — path array to pointer', () {
      final result = JSONPath.toPointer([r'$', 'a', 'b', '0']);
      expect(result, equals('/a/b/0'));
    });

    test('toPointer escapes ~ and /', () {
      final result = JSONPath.toPointer([r'$', 'a/b', 'c~d']);
      expect(result, equals('/a~1b/c~0d'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Edge cases
  // ═══════════════════════════════════════════════════════════════════

  group('Edge cases', () {
    test('empty object returns empty for any path', () {
      final data = <String, dynamic>{};
      final result = JSONPath.query(r'$.a', data);
      expect(result, equals([]));
    });

    test('null values in data', () {
      final data = {'a': null, 'b': 'hello'};
      final result = JSONPath.query(r'$.a', data);
      expect(result, equals([null]));
    });

    test('deeply nested structures', () {
      final data = {
        'l1': {
          'l2': {
            'l3': {
              'l4': {'value': 'deep'},
            },
          },
        },
      };
      final result = JSONPath.query(r'$..value', data);
      expect(result, equals(['deep']));
    });

    test('falsy values: 0, empty string, false', () {
      final data = {'items': [0, '', false, null]};
      final result = JSONPath.query(r'$.items[*]', data);
      expect(result, equals([0, '', false, null]));
    });

    test('empty array', () {
      final data = {'items': <dynamic>[]};
      final result = JSONPath.query(r'$.items[*]', data);
      expect(result, equals([]));
    });

    test('query shorthand with wrap: false', () {
      final data = {'a': 1};
      final result = JSONPath.query(r'$.a', data, wrap: false);
      expect(result, equals([1])); // query always returns List
    });

    test('evaluate with String shorthand', () {
      final data = {'a': 1};
      final result = JSONPath.evaluate(r'$.a', data);
      expect(result, equals([1]));
    });
  });
}
