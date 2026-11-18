/// Minimal cache seam for API responses.
///
/// The default [InMemoryCacheStore] keeps decoded JSON bodies with a TTL.
/// A future persistent implementation can replace it without touching the
/// `WallhavenClient` abstraction — swap the store passed into the
/// [CacheInterceptor].
library;

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

  /// Drops the entry for [key], if any.
  ///
  /// Used to discard a response the caller rejected on validation: replaying
  /// a body the client cannot decode would make every retry fail until the
  /// TTL expires.
  Future<void> remove(String key);

  /// Removes all entries (used by `close()`).
  Future<void> clear();
}

/// Default cap on distinct cached responses; guards long sessions against
/// unbounded growth.
const int _defaultMaxEntries = 100;

/// Simple in-memory store; dio calls within one isolate are serialized by
/// the event loop between awaits.
///
/// Entries expire lazily (on [get]) and the store holds at most
/// [maxEntries] entries — when full, the least-recently-used entry is
/// evicted to make room.
final class InMemoryCacheStore implements CacheStore {
  InMemoryCacheStore({int maxEntries = _defaultMaxEntries})
      : maxEntries = maxEntries < 1 ? 1 : maxEntries;

  /// Maximum number of entries retained; LRU-evicted beyond this.
  final int maxEntries;

  // Insertion-ordered map used as an LRU: reads re-insert the key at the
  // end, so the first key is always the least recently used.
  final Map<String, CacheEntry> _entries = <String, CacheEntry>{};

  @override
  Future<CacheEntry?> get(String key, {required DateTime now}) async {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (entry.isExpiredAt(now)) return null;
    _entries[key] = entry; // touch → most recently used position
    return entry;
  }

  @override
  Future<void> put(String key, CacheEntry entry) async {
    _entries.remove(key);
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = entry;
  }

  @override
  Future<void> remove(String key) async {
    _entries.remove(key);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}
