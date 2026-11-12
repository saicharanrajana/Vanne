import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'collection_entry.dart';

/// Local collections store backed by Hive box `collections`.
///
/// Each entry is JSON-encoded [CollectionEntry] keyed by id.
/// Not `final` so tests can provide fakes via `implements`.
class CollectionsRepository {
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

  /// Adds [entry]; returns `false` when it could not be stored.
  ///
  /// One entry is a ~300-byte string, so it is encoded inline: an isolate
  /// round-trip would cost more than it saves.
  Future<bool> add(CollectionEntry entry) async {
    final box = _box;
    if (box == null || box.containsKey(entry.id)) return false;
    await box.put(entry.id, entry.encode());
    return true;
  }

  /// Inserts [entries] in one Hive batch; used for first-run seeding.
  ///
  /// Encoding happens in a single isolate round-trip rather than one per
  /// entry, which keeps first launch off the slow path.
  Future<void> addAll(List<CollectionEntry> entries) async {
    final box = _box;
    if (box == null || entries.isEmpty) return;
    final encoded = await compute(_encodeCollections, entries);
    await box.putAll({
      for (var i = 0; i < entries.length; i++) entries[i].id: encoded[i],
    });
  }

  Future<void> removeMany(Set<String> ids) async {
    final box = _box;
    if (box == null) return;
    await box.deleteAll(ids);
  }
}

List<CollectionEntry> _decodeCollections(List<String> raws) =>
    [for (final raw in raws) ?CollectionEntry.decode(raw)];

List<String> _encodeCollections(List<CollectionEntry> entries) =>
    [for (final entry in entries) entry.encode()];
