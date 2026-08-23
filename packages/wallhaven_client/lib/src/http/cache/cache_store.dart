/// Minimal cache seam for API responses.
///
/// The default [InMemoryCacheStore] keeps decoded JSON bodies with a TTL.
/// A future persistent implementation can replace it without touching the
/// `WallhavenClient` abstraction — swap the store passed into the
/// [CacheInterceptor].
library;

import 'dart:collection';

/// A cached response payload with its expiry instant.
final class CacheEntry {
  final int statusCode;

  /// Decoded JSON body (map or list).
  final Object? json;

  final DateTime expiresAt;

  const CacheEntry({
    required this.statusCode,
    required this.json,
    required this.expiresAt,
  });

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}

/// Storage contract for cached responses.
abstract interface class CacheStore {
  /// Returns the entry for [key] if present and not expired at [now].
  Future<CacheEntry?> get(String key, {required DateTime now});

  /// Stores [entry] under [key], replacing any previous value.
  Future<void> put(String key, CacheEntry entry);

  /// Removes all entries (used by `close()`).
  Future<void> clear();
}

/// Thread-unsafe-by-design simple in-memory store; dio calls within one
/// isolate are serialized by the event loop between awaits.
final class InMemoryCacheStore implements CacheStore {
  // LinkedHashMap preserves insertion order; we evict expired entries lazily.
  final Map<String, CacheEntry> _entries = HashMap<String, CacheEntry>();

  @override
  Future<CacheEntry?> get(String key, {required DateTime now}) async {
    final entry = _entries[key];
    if (entry == null) return null;
    if (entry.isExpiredAt(now)) {
      _entries.remove(key);
      return null;
    }
    return entry;
  }

  @override
  Future<void> put(String key, CacheEntry entry) async {
    _entries[key] = entry;
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}
