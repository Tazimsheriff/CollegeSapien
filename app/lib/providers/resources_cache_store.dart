import '../core/cache/cache_box.dart';
import '../models/api_models.dart';

/// Cache for the QP/Notes resource hubs — replaces the old zero-TTL
/// [CacheService] map entries with a real TTL, persisted across restarts,
/// while preserving the existing stale-while-revalidate UX (paint cached
/// instantly, refresh in the background).
class ResourcesCacheStore {
  ResourcesCacheStore._();

  static final ResourcesCacheStore instance = ResourcesCacheStore._();

  static const ttl = Duration(minutes: 30);

  final qpBox = _hubResourceBox('cache_resources_qp');
  final notesBox = _hubResourceBox('cache_resources_notes');

  static CacheBox<List<HubResource>> _hubResourceBox(String prefsKey) {
    return CacheBox<List<HubResource>>(
      prefsKey: prefsKey,
      ttl: ttl,
      decode: (json) => (json as List<dynamic>)
          .map((item) => HubResource.fromJson(item as Map<String, dynamic>))
          .toList(),
      encode: (value) => value.map((item) => item.toJson()).toList(),
    );
  }
}
