// Hardening for issue #8 — `JSONPath.cache` grew without bound and was a
// public, mutable `Map`. The compiled-path cache is now private and bounded
// by a least-recently-used eviction policy, with read-only introspection
// helpers on the public surface.
import 'package:json_path_plus/json_path_plus.dart';
import 'package:test/test.dart';

void main() {
  setUp(JSONPath.clearCache);

  group('Path cache capacity', () {
    test('never exceeds the cap as distinct paths accumulate', () {
      expect(JSONPath.cacheCapacity, greaterThan(0));
      expect(
        JSONPath.cacheCapacity,
        inInclusiveRange(256, 1024),
        reason: 'the hardening issue asked for a cap in the 256-1024 range',
      );

      final overflow = JSONPath.cacheCapacity + 200;
      for (var i = 0; i < overflow; i++) {
        JSONPath.toPathArray('\$.item_$i.selector');
      }

      expect(JSONPath.cacheSize, JSONPath.cacheCapacity);
    });

    test('does not grow when the same path is requested repeatedly', () {
      for (var i = 0; i < 50; i++) {
        JSONPath.toPathArray(r'$.store.book[*].title');
      }
      expect(JSONPath.cacheSize, 1);
    });

    test('holds exactly the cap once saturated', () {
      for (var i = 0; i < JSONPath.cacheCapacity * 2; i++) {
        JSONPath.toPathArray('\$.k$i');
      }
      expect(JSONPath.cacheSize, JSONPath.cacheCapacity);
    });
  });

  group('Path cache eviction policy', () {
    String path(int i) => '\$.evict_$i.a';

    test('evicts the least recently used entry', () {
      final cap = JSONPath.cacheCapacity;
      for (var i = 0; i < cap; i++) {
        JSONPath.toPathArray(path(i));
      }
      expect(JSONPath.cacheSize, cap);
      expect(JSONPath.isCached(path(0)), isTrue);

      // Re-reading path(0) makes it the most recent, so path(1) becomes the
      // least recently used and must be the one dropped next.
      JSONPath.toPathArray(path(0));

      JSONPath.toPathArray(path(cap));
      expect(JSONPath.cacheSize, cap);
      expect(JSONPath.isCached(path(0)), isTrue,
          reason: 'recently read entry must survive eviction');
      expect(JSONPath.isCached(path(1)), isFalse,
          reason: 'least recently used entry must be evicted');
      expect(JSONPath.isCached(path(cap)), isTrue);
    });

    test('eviction does not corrupt retained entries', () {
      final cap = JSONPath.cacheCapacity;
      final first = JSONPath.toPathArray(path(0));
      for (var i = 0; i < cap * 2; i++) {
        JSONPath.toPathArray(path(i));
      }
      // The evicted entry is recompiled from scratch, so the result is
      // identical to the one captured before eviction.
      expect(JSONPath.toPathArray(path(0)), equals(first));
    });
  });

  group('Read-only cache helpers', () {
    test('isCached and cacheSize report the retained entries', () {
      expect(JSONPath.cacheSize, 0);
      expect(JSONPath.isCached(r'$.a.b'), isFalse);

      JSONPath.toPathArray(r'$.a.b');
      expect(JSONPath.isCached(r'$.a.b'), isTrue);
      expect(JSONPath.cacheSize, 1);
    });

    test('clearCache drops every retained entry', () {
      for (var i = 0; i < 10; i++) {
        JSONPath.toPathArray('\$.c$i');
      }
      expect(JSONPath.cacheSize, 10);

      JSONPath.clearCache();
      expect(JSONPath.cacheSize, 0);
      expect(JSONPath.isCached(r'$.c0'), isFalse);
    });

    test('toPathArray hands back a defensive copy of the cached array', () {
      final first = JSONPath.toPathArray(r'$.a.b');
      first.add('injected');

      expect(JSONPath.toPathArray(r'$.a.b'), equals([r'$', 'a', 'b']));
      expect(JSONPath.cacheSize, 1);
    });

    test('evaluate mutating its compiled path does not poison the cache', () {
      JSONPath.query(r'$.store.book[*].title', {
        'store': {
          'book': [
            {'title': 'Sayings of the Century'}
          ]
        }
      });
      expect(JSONPath.isCached(r'$.store.book[*].title'), isTrue);
      expect(
        JSONPath.toPathArray(r'$.store.book[*].title'),
        equals([r'$', 'store', 'book', '*', 'title']),
      );
    });
  });
}
