import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codesapiens/core/cache/cache_box.dart';

CacheBox<int> _intBox({Duration ttl = const Duration(minutes: 5)}) {
  return CacheBox<int>(
    prefsKey: 'test_int_box',
    ttl: ttl,
    decode: (json) => json as int,
    encode: (value) => value,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CacheBox', () {
    test('valueOrNull is null before anything is set', () {
      final box = _intBox();
      expect(box.valueOrNull, isNull);
      expect(box.isValid, isFalse);
    });

    test('set stores the value and makes it valid', () async {
      final box = _intBox();
      await box.set(42);
      expect(box.valueOrNull, 42);
      expect(box.isValid, isTrue);
    });

    test('valueOrNull returns null once expired, staleValueOrNull does not',
        () async {
      final box = _intBox(ttl: const Duration(milliseconds: 1));
      await box.set(7);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(box.valueOrNull, isNull);
      expect(box.staleValueOrNull, 7);
    });

    test('persists across instances via SharedPreferences (hydrate)',
        () async {
      final box1 = _intBox();
      await box1.set(99);

      final box2 = _intBox();
      expect(box2.valueOrNull, isNull); // not hydrated yet
      await box2.hydrate();
      expect(box2.valueOrNull, 99);
    });

    test('invalidate clears in-memory and persisted value', () async {
      final box = _intBox();
      await box.set(5);
      await box.invalidate();
      expect(box.valueOrNull, isNull);
      expect(box.staleValueOrNull, isNull);

      final rehydrated = _intBox();
      await rehydrated.hydrate();
      expect(rehydrated.valueOrNull, isNull);
    });

    test('getOrFetch returns cached value without calling fetcher again',
        () async {
      final box = _intBox();
      await box.set(1);
      var calls = 0;
      final result = await box.getOrFetch(() async {
        calls++;
        return 2;
      });
      expect(result, 1);
      expect(calls, 0);
    });

    test('getOrFetch fetches when cache empty and caches the result',
        () async {
      final box = _intBox();
      var calls = 0;
      final result = await box.getOrFetch(() async {
        calls++;
        return 10;
      });
      expect(result, 10);
      expect(calls, 1);
      expect(box.valueOrNull, 10);
    });

    test('getOrFetch forceRefresh bypasses a valid cache', () async {
      final box = _intBox();
      await box.set(1);
      final result = await box.getOrFetch(() async => 2, forceRefresh: true);
      expect(result, 2);
      expect(box.valueOrNull, 2);
    });

    test('concurrent getOrFetch calls are single-flighted', () async {
      final box = _intBox();
      var calls = 0;
      Future<int> fetcher() async {
        calls++;
        await Future.delayed(const Duration(milliseconds: 20));
        return 123;
      }

      final results = await Future.wait([
        box.getOrFetch(fetcher),
        box.getOrFetch(fetcher),
        box.getOrFetch(fetcher),
      ]);

      expect(calls, 1);
      expect(results, [123, 123, 123]);
    });

    test('a failed fetch clears the in-flight future so retries can happen',
        () async {
      final box = _intBox();
      var calls = 0;
      Future<int> failingFetcher() async {
        calls++;
        throw Exception('boom');
      }

      await expectLater(box.getOrFetch(failingFetcher), throwsException);
      expect(calls, 1);

      final result = await box.getOrFetch(() async => 55);
      expect(result, 55);
      expect(calls, 1); // second getOrFetch used the new fetcher, not retried
    });

    test('notifies listeners on set and invalidate', () async {
      final box = _intBox();
      var notifications = 0;
      box.addListener(() => notifications++);

      await box.set(1);
      expect(notifications, 1);

      await box.invalidate();
      expect(notifications, 2);
    });
  });
}
