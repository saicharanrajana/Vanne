import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/collections/collection_entry.dart';
import '../../../core/collections/collections_repository.dart';
import '../../../core/collections/seed_collections.dart';
import '../../../core/domain/feed_filter.dart';

/// Owns local collections state — CRUD + multi-selection for deletion.
///
/// Optimistically updates signals first, then persists. A failed write rolls
/// back only what that call changed, never a whole-map snapshot that could
/// discard an unrelated success, and `create` reports every failure as a
/// message instead of throwing at the bookmark toggle.
final class CollectionsController {
  CollectionsController(this._repo);

  final CollectionsRepository _repo;

  final _entries = signal<Map<String, CollectionEntry>>(
    <String, CollectionEntry>{},
  );

  late final entries = computed(() {
    final vals = _entries.value.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List<CollectionEntry>.unmodifiable(vals);
  });

  late final ids = computed(() => _entries.value.keys.toSet());

  final selectedIds = signal<Set<String>>(const <String>{});

  late final hasSelection = computed(() => selectedIds.value.isNotEmpty);

  late final isEmpty = computed(() => _entries.value.isEmpty);

  Future<void> restore() async {
    final list = await _repo.getAll();
    final map = <String, CollectionEntry>{for (final e in list) e.id: e};
    _entries.value = map;
  }

  Future<String?> create({
    required String name,
    required String query,
    List<WallhavenCategory> kinds = const [],
    FeedFilter filter = const FeedFilter(),
    List<String> colors = const [],
    String? coverUrl,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return 'Name required';
    final lower = trimmedName.toLowerCase();
    for (final e in _entries.value.values) {
      if (e.name.toLowerCase() == lower) return 'Name already exists';
    }
    final now = DateTime.now();
    final id = 'c_${now.microsecondsSinceEpoch}_${trimmedName.hashCode.abs()}';
    final entry = CollectionEntry(
      id: id,
      name: trimmedName,
      query: query.trim(),
      kinds: List.unmodifiable(kinds),
      filter: filter,
      colors: List.unmodifiable(colors),
      coverUrl: coverUrl,
      createdAt: now,
    );
    _entries.value = {..._entries.peek(), id: entry};
    var stored = false;
    try {
      stored = await _repo.add(entry);
    } catch (_) {
      // Storage refused the write (full disk, provider error). The caller
      // gets the same message as a rejected write instead of an exception
      // escaping into the dialog, which would leave it stuck on "saving".
    }
    if (stored) return null;
    _dropEntry(id);
    return 'Failed to save';
  }

  /// Fills a missing cover with the first wallpaper seen for this collection.
  ///
  /// Never replaces an existing cover, and curated seeds keep their bundled
  /// asset. The update is optimistic and rolled back only when persistence
  /// fails, so the grid still opens even if storage is unavailable.
  Future<void> ensureCover(String id, String coverUrl) async {
    if (coverUrl.isEmpty) return;
    final current = _entries.peek();
    final entry = current[id];
    if (entry == null ||
        entry.coverUrl != null ||
        entry.coverAsset != null ||
        seedCoverAssets.containsKey(id)) {
      return;
    }

    final updated = entry.copyWith(coverUrl: coverUrl);
    _entries.value = {...current, id: updated};
    var stored = false;
    try {
      stored = await _repo.update(updated);
    } catch (_) {
      // Storage refused the write; the cover is presentation-only, so the
      // fallback card is preferable to surfacing an error on a grid visit.
    }
    if (stored) {
      // The collection may have been deleted while the write was in flight.
      // Remove the resurrected row so a restart cannot bring it back.
      if (!_entries.peek().containsKey(id)) {
        try {
          await _repo.removeMany({id});
        } catch (_) {}
      }
      return;
    }

    final live = _entries.peek();
    final liveEntry = live[id];
    if (liveEntry == null || liveEntry.coverUrl != coverUrl) return;
    _entries.value = {...live, id: _withoutCover(liveEntry)};
  }

  /// Deletes [idsToRemove] optimistically; rolls back and returns `false`
  /// when persistence fails so callers can surface an error instead of a
  /// false success.
  ///
  /// Rollback restores only the entries this call removed; collections
  /// created or deleted meanwhile are left exactly as the user left them.
  Future<bool> removeMany(Set<String> idsToRemove) async {
    if (idsToRemove.isEmpty) return true;
    final current = _entries.peek();
    final removed = <String, CollectionEntry>{};
    for (final id in idsToRemove) {
      final entry = current[id];
      if (entry != null) removed[id] = entry;
    }
    final next = Map<String, CollectionEntry>.from(current)
      ..removeWhere((id, _) => idsToRemove.contains(id));
    _entries.value = next;
    // prune selection that no longer exists
    selectedIds.value = selectedIds.value.where(next.containsKey).toSet();
    try {
      await _repo.removeMany(idsToRemove);
      return true;
    } catch (_) {
      final restored = Map<String, CollectionEntry>.from(_entries.peek());
      for (final entry in removed.entries) {
        restored.putIfAbsent(entry.key, () => entry.value);
      }
      _entries.value = restored;
      return false;
    }
  }

  static CollectionEntry _withoutCover(CollectionEntry entry) =>
      CollectionEntry(
        id: entry.id,
        name: entry.name,
        query: entry.query,
        kinds: entry.kinds,
        filter: entry.filter,
        colors: entry.colors,
        coverAsset: entry.coverAsset,
        createdAt: entry.createdAt,
      );

  /// Removes one optimistic entry, leaving every other entry untouched.
  void _dropEntry(String id) {
    if (!_entries.peek().containsKey(id)) return;
    _entries.value = Map<String, CollectionEntry>.from(_entries.peek())
      ..remove(id);
  }

  void toggleSelection(String id) {
    final cur = selectedIds.value;
    if (cur.contains(id)) {
      selectedIds.value = cur.where((e) => e != id).toSet();
    } else {
      selectedIds.value = {...cur, id};
    }
  }

  void clearSelection() {
    selectedIds.value = const <String>{};
  }
}
