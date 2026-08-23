import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'collection_entry.dart';

/// Local collections store backed by Hive box `collections`.
///
/// Each entry is JSON-encoded [CollectionEntry] keyed by id.
/// Mirrors `FavoritesRepository` pattern.
final class CollectionsRepository {
  static const _boxName = 'collections';

  Box<String>? _box;

  Future<void> open() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  Future<List<CollectionEntry>> getAll() async {
    final box = _box;
    if (box == null) return const [];
    final raws = box.values.toList(growable: false);
    if (raws.isEmpty) return const [];
    return compute(_decodeCollections, raws);
  }

  bool contains(String id) => _box?.containsKey(id) ?? false;

  Future<bool> add(CollectionEntry entry) async {
    final box = _box;
    if (box == null || box.containsKey(entry.id)) return false;
    await box.put(entry.id, await compute(_encodeCollection, entry));
    return true;
  }

  Future<bool> update(CollectionEntry entry) async {
    final box = _box;
    if (box == null) return false;
    await box.put(entry.id, await compute(_encodeCollection, entry));
    return true;
  }

  Future<bool> remove(String id) async {
    final box = _box;
    if (box == null || !box.containsKey(id)) return false;
    await box.delete(id);
    return true;
  }

  Future<void> removeMany(Set<String> ids) async {
    final box = _box;
    if (box == null) return;
    for (final id in ids) {
      if (box.containsKey(id)) await box.delete(id);
    }
  }
}

List<CollectionEntry> _decodeCollections(List<String> raws) =>
    [for (final raw in raws) ?CollectionEntry.decode(raw)];

String _encodeCollection(CollectionEntry entry) => entry.encode();
