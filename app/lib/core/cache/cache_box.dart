import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cached_entry.dart';

/// Non-generic surface of [CacheBox] — lets code that manages a heterogeneous
/// collection of boxes (e.g. AppStateNotifier's field list) call [hydrate]
/// and [invalidate] on all of them without running into Dart's generic
/// invariance (a `List<CacheBox<Object?>>` can't hold a `CacheBox<String>`).
abstract class CacheBoxLike extends ChangeNotifier {
  Future<void> hydrate();
  Future<void> invalidate();
}

/// A single named, typed, TTL-aware cache slot backed by [SharedPreferences],
/// with built-in single-flight dedupe for concurrent [getOrFetch] callers.
///
/// This is the one place TTL/serialization logic should live for a given
/// piece of data — call sites should never hand-rolled their own
/// SharedPreferences + timestamp scheme.
class CacheBox<T> extends CacheBoxLike {
  CacheBox({
    required this.prefsKey,
    required this.ttl,
    required this.decode,
    required this.encode,
  });

  final String prefsKey;
  final Duration ttl;
  final T Function(Object? json) decode;
  final Object? Function(T value) encode;

  String get _timestampKey => '${prefsKey}_ts';

  CachedEntry<T>? _entry;
  Future<T>? _inFlight;

  /// The cached value, only if it's still within [ttl].
  T? get valueOrNull => (_entry?.isValid ?? false) ? _entry!.data : null;

  /// The cached value regardless of TTL — for offline-tolerant fallbacks.
  T? get staleValueOrNull => _entry?.data;

  bool get isValid => _entry?.isValid ?? false;

  bool get hasValue => _entry != null;

  DateTime? get cachedAt => _entry?.cachedAt;

  /// Loads any persisted value from SharedPreferences into memory.
  /// Safe to call multiple times; swallows decode errors (corrupt/old cache).
  @override
  Future<void> hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      final tsMs = prefs.getInt(_timestampKey);
      if (raw == null || tsMs == null) return;
      final data = decode(jsonDecode(raw));
      _entry = CachedEntry<T>(
        data: data,
        ttl: ttl,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(tsMs),
      );
      notifyListeners();
    } catch (_) {
      // Corrupt or incompatible cache entry — ignore, treat as empty.
    }
  }

  /// Cache-aside read: returns the valid cached value if present, otherwise
  /// calls [fetcher] (deduped across concurrent callers) and caches the
  /// result. Pass [forceRefresh] to bypass the cache and always re-fetch.
  Future<T> getOrFetch(
    Future<T> Function() fetcher, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh && isValid) {
      return Future.value(_entry!.data);
    }
    if (_inFlight != null) return _inFlight!;
    final future = fetcher().then((data) {
      _inFlight = null;
      set(data);
      return data;
    }).catchError((Object error) {
      _inFlight = null;
      throw error;
    });
    _inFlight = future;
    return future;
  }

  /// Writes a value directly — used for optimistic updates after a mutation,
  /// or to store a freshly-fetched value.
  Future<void> set(T data) async {
    _entry = CachedEntry<T>(data: data, ttl: ttl);
    notifyListeners();
    await _persist(data);
  }

  @override
  Future<void> invalidate() async {
    _entry = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
      await prefs.remove(_timestampKey);
    } catch (_) {}
  }

  Future<void> _persist(T data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(encode(data)));
      await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
