import 'cache_box.dart';

/// A keyed collection of [CacheBox]es, for reference data addressed by a
/// composite key (e.g. curriculum keyed by college+course+regulation).
///
/// Boxes are created lazily on first access and reused thereafter, so the
/// per-key TTL/decode/encode logic is defined once here rather than
/// hand-rolled at each call site.
class CacheBoxFamily<T> {
  CacheBoxFamily({
    required this.ttl,
    required this.prefsKeyFor,
    required this.decode,
    required this.encode,
  });

  final Duration ttl;
  final String Function(String key) prefsKeyFor;
  final T Function(Object? json) decode;
  final Object? Function(T value) encode;

  final Map<String, CacheBox<T>> _boxes = {};

  CacheBox<T> operator [](String key) => _boxes.putIfAbsent(
        key,
        () => CacheBox<T>(
          prefsKey: prefsKeyFor(key),
          ttl: ttl,
          decode: decode,
          encode: encode,
        ),
      );

  /// Invalidates every already-instantiated box whose key matches [test].
  /// Note this only reaches boxes created this session via `[]` — callers
  /// that need to guarantee persisted-but-not-yet-instantiated entries are
  /// also purged (e.g. from a previous app session) must additionally scan
  /// SharedPreferences directly by key prefix.
  void invalidateMatching(bool Function(String key) test) {
    for (final entry in _boxes.entries) {
      if (test(entry.key)) entry.value.invalidate();
    }
  }
}
