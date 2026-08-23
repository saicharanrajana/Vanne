import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/collections/collection_entry.dart';
import '../../../core/collections/collections_repository.dart';
import '../../../core/domain/feed_filter.dart';

/// Owns local collections state — CRUD + multi-selection for deletion.
///
/// Optimistically updates signals first, then persists. On persist failure
/// rolls back. Mirrors `FavoritesController` pattern.
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
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return 'Name required';
    if (trimmedName.length > 30) return 'Name too long (max 30)';
    final lower = trimmedName.toLowerCase();
    for (final e in _entries.value.values) {
      if (e.name.toLowerCase() == lower) return 'Name already exists';
    }
    final id = 'c_${DateTime.now().microsecondsSinceEpoch}_${trimmedName.hashCode.abs()}';
    final entry = CollectionEntry(
      id: id,
      name: trimmedName,
      query: query.trim(),
      kinds: List.unmodifiable(kinds),
      filter: filter,
      createdAt: DateTime.now(),
    );
    final prev = Map<String, CollectionEntry>.from(_entries.value);
    _entries.value = {...prev, id: entry};
    final ok = await _repo.add(entry);
    if (!ok) {
      _entries.value = prev;
      return 'Failed to save';
    }
    return null;
  }

  Future<String?> update(CollectionEntry entry) async {
    if (!_entries.value.containsKey(entry.id)) return 'Not found';
    final lower = entry.name.toLowerCase();
    for (final e in _entries.value.values) {
      if (e.id != entry.id && e.name.toLowerCase() == lower) {
        return 'Name already exists';
      }
    }
    final prev = Map<String, CollectionEntry>.from(_entries.value);
    _entries.value = {...prev, entry.id: entry};
    final ok = await _repo.update(entry);
    if (!ok) {
      _entries.value = prev;
      return 'Failed to save';
    }
    return null;
  }

  Future<void> removeMany(Set<String> idsToRemove) async {
    if (idsToRemove.isEmpty) return;
    final prev = Map<String, CollectionEntry>.from(_entries.value);
    final next = Map<String, CollectionEntry>.from(prev);
    for (final id in idsToRemove) {
      next.remove(id);
    }
    _entries.value = next;
    // prune selection that no longer exists
    final remainingIds = next.keys.toSet();
    selectedIds.value =
        selectedIds.value.where(remainingIds.contains).toSet();
    try {
      await _repo.removeMany(idsToRemove);
    } catch (_) {
      _entries.value = prev;
    }
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
