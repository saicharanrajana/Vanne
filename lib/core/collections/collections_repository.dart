import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'collection_entry.dart';
import 'collection_order.dart';

/// Local collections store backed by Hive.
///
/// The box `collections` holds one JSON-encoded [CollectionEntry] per id.
/// A second box, `collection_order`, holds the user's display order as a list
/// of ids under a single key. Keeping the order outside the rows means the row
/// format stays readable by older builds, and either side can be repaired from
/// the other: [CollectionOrder.resolve] is what
/// [CollectionsRepository.getStoredOrder] callers use to stitch the two back
/// together after a crash between writes.
///
/// Every mutation is serialised through [_mutate]. Hive writes are async, so
/// without a queue two overlapping operations can land out of order — an
/// in-flight cover update could re-create a row the user just deleted, and a
/// stale reorder could overwrite a newer one. The queue runs them in call
/// order; [update] additionally refuses to write a row that no longer exists.
///
/// Not `final` so tests can provide fakes via `implements`.
class CollectionsRepository {
  static const _boxName = 'collections';
  static const _orderBoxName = 'collection_order';
  static const _orderKey = 'ids';

  Box<String>? _box;
  Box<dynamic>? _orderBox;

  /// Tail of the serialised mutation queue. Never completes with an error, so
  /// one failed write cannot poison every later one.
  Future<void> _queue = Future<void>.value();

  Future<void> open() async {
    _box ??= await Hive.openBox<String>(_boxName);
    _orderBox ??= await Hive.openBox<dynamic>(_orderBoxName);
  }

  Future<List<CollectionEntry>> getAll() async {
    final box = _box;
    if (box == null) return const [];
    final raws = box.values.toList(growable: false);
    if (raws.isEmpty) return const [];
    return compute(_decodeCollections, raws);
  }

  /// The persisted display order, or `null` when none has been written yet.
  ///
  /// `null` is not the same as an empty list: it means the install predates
  /// stored ordering (or has never been reconciled), so callers should fall
  /// back to creation order via [CollectionOrder.resolve].
  Future<List<String>?> getStoredOrder() async {
    final box = _orderBox;
    if (box == null) return null;
    final raw = box.get(_orderKey);
    if (raw is! List) return null;
    return raw.whereType<String>().toList(growable: false);
  }

  /// Persists [ids] as the display order; returns `false` when it could not be
  /// stored.
  ///
  /// The list is stored as given. Readers reconcile it against the rows they
  /// actually have, so a stale id here is harmless and cannot resurrect a
  /// deleted collection.
  Future<bool> saveOrder(List<String> ids) async {
    if (_orderBox == null) return false;
    return _mutate(() async {
      try {
        await _orderBox!.put(_orderKey, List<String>.from(ids));
        return true;
      } catch (_) {
        return false;
      }
    });
  }

  /// Adds [entry]; returns `false` when it could not be stored.
  ///
  /// One entry is a ~300-byte string, so it is encoded inline: an isolate
  /// round-trip would cost more than it saves. An existing id is never
  /// overwritten, which is what makes a repeated add idempotent.
  Future<bool> add(CollectionEntry entry) async {
    if (_box == null) return false;
    return _mutate(() async {
      final box = _box!;
      if (box.containsKey(entry.id)) return false;
      await box.put(entry.id, entry.encode());
      // The row is what the user asked for; a failed position write must not
      // turn a saved collection into a reported failure. The next reconcile
      // appends rows the order does not mention.
      await _bestEffortOrder(() => _appendToOrder([entry.id]));
      return true;
    });
  }

  /// Inserts [entries] in one Hive batch; used for first-run seeding and for
  /// restoring curated collections that are missing.
  ///
  /// Encoding happens in a single isolate round-trip rather than one per
  /// entry, which keeps first launch off the slow path.
  Future<void> addAll(List<CollectionEntry> entries) async {
    if (_box == null || entries.isEmpty) return;
    final encoded = await compute(_encodeCollections, entries);
    await _mutate(() async {
      final box = _box!;
      final fresh = <String>[];
      final writes = <String, String>{};
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (box.containsKey(entry.id)) continue;
        writes[entry.id] = encoded[i];
        fresh.add(entry.id);
      }
      if (writes.isEmpty) return;
      await box.putAll(writes);
      await _bestEffortOrder(() => _appendToOrder(fresh));
    });
  }

  /// Deletes one collection and drops it from the order.
  ///
  /// Throws when storage refuses the delete: the caller cannot report a
  /// partial success, so failure has to be visible. Only the row write can
  /// fail the call — once the row is gone, a failed position write is repaired
  /// by the next reconcile rather than reported as a collection that still
  /// exists.
  Future<void> remove(String id) async {
    if (_box == null) return;
    await _mutate(() async {
      await _box!.delete(id);
      await _bestEffortOrder(
        () => _mutateOrder(
          (ids) => [
            for (final existing in ids)
              if (existing != id) existing,
          ],
        ),
      );
    });
  }

  /// Rewrites an existing entry (used to fill a missing cover once).
  ///
  /// Returns `false` when the row is gone: a cover write that started before
  /// the user deleted the collection must not bring it back, so this never
  /// inserts. One entry is small enough to encode inline, matching [add].
  Future<bool> update(CollectionEntry entry) async {
    if (_box == null) return false;
    return _mutate(() async {
      final box = _box!;
      if (!box.containsKey(entry.id)) return false;
      await box.put(entry.id, entry.encode());
      return true;
    });
  }

  /// Runs [action] after every previously queued mutation has finished.
  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Runs an order change without letting it fail the row write it follows.
  Future<void> _bestEffortOrder(Future<void> Function() change) async {
    try {
      await change();
    } catch (_) {}
  }

  /// Appends [ids] that the stored order does not already contain.
  ///
  /// A missing order stays missing: writing an order made only of the new ids
  /// would hide every existing collection on the next launch. The next
  /// reconcile (or [saveOrder]) establishes one from the rows themselves.
  Future<void> _appendToOrder(List<String> ids) async {
    if (ids.isEmpty) return;
    await _mutateOrder((order) => [...order, ...ids]);
  }

  /// Read-modify-write of the stored order. No-op while none exists.
  Future<void> _mutateOrder(
    List<String> Function(List<String> order) change,
  ) async {
    final box = _orderBox;
    if (box == null) return;
    final raw = box.get(_orderKey);
    if (raw is! List) return;
    final current = raw.whereType<String>().toList();
    final next = change(current);
    if (listEquals(next, current)) return;
    await box.put(_orderKey, next);
  }
}

List<CollectionEntry> _decodeCollections(List<String> raws) => [
  for (final raw in raws) ?CollectionEntry.decode(raw),
];

List<String> _encodeCollections(List<CollectionEntry> entries) => [
  for (final entry in entries) entry.encode(),
];
