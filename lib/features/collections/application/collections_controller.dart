import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/collections/collection_entry.dart';
import '../../../core/collections/collection_identity.dart';
import '../../../core/collections/collection_order.dart';
import '../../../core/collections/collections_repository.dart';
import '../../../core/collections/seed_collections.dart';
import '../../../core/domain/feed_filter.dart';

/// Owns local collections state — CRUD, user ordering and curated protection.
///
/// Optimistically updates signals first, then persists. A failed write rolls
/// back only what that call changed, never a whole-map snapshot that could
/// discard an unrelated success, and `create` reports every failure as a
/// message instead of throwing at the bookmark toggle.
///
/// Two signals drive the public state: [_entries] holds the rows and [_order]
/// their display order. [entries] joins them, so a reorder never has to rebuild
/// the map and a row update never has to touch the order. Every publish goes
/// through [_publish] → [CollectionOrder.resolve], which keeps the pair
/// consistent even if a caller hands over a partial order.
final class CollectionsController {
  CollectionsController(this._repo);

  final CollectionsRepository _repo;

  final _entries = signal<Map<String, CollectionEntry>>(
    <String, CollectionEntry>{},
  );

  final _order = signal<List<String>>(const <String>[]);

  /// Bumped by every order change so a failing older write cannot roll back a
  /// newer order.
  int _orderRevision = 0;

  /// Last order confirmed by storage. Optimistic edits must never become the
  /// rollback target for a later failed edit.
  List<String> _confirmedOrder = const <String>[];

  /// Collections in the user's order. Always contains every stored row.
  late final entries = computed(() {
    final map = _entries.value;
    final ordered = <CollectionEntry>[];
    for (final id in _order.value) {
      final entry = map[id];
      if (entry != null) ordered.add(entry);
    }
    return List<CollectionEntry>.unmodifiable(ordered);
  });

  late final ids = computed(() => _entries.value.keys.toSet());

  /// The collection with [id], or `null` when it is gone.
  CollectionEntry? entryById(String id) => _entries.value[id];

  /// Whether [id] is one of the curated collections shipped with the app.
  ///
  /// Curated collections are permanent: they are restored on launch if missing
  /// and [remove] refuses them. They are ordinary entries otherwise, including
  /// for ordering.
  bool isCuratedDefault(String id) => isCuratedCollection(id);

  /// Whether [id] could be removed right now — a user collection that exists.
  bool canRemove(String id) =>
      !isCuratedDefault(id) && _entries.value.containsKey(id);

  /// The saved collection for [definition], if any.
  ///
  /// Matched on the saved search itself, never on the display name: two
  /// different searches can share a title, and removing the wrong row would be
  /// silent data loss. An entry whose recorded origin agrees with what the
  /// definition implies wins over a legacy row that predates origins; both are
  /// equal saves of the same search, so either is safe to toggle.
  CollectionEntry? findByDefinition(CollectionSearchDefinition definition) {
    CollectionEntry? legacy;
    for (final entry in entries.value) {
      if (!definition.matches(entry)) continue;
      if (entry.origin == definition.impliedOrigin) return entry;
      legacy ??= entry;
    }
    return legacy;
  }

  Future<void> restore() async {
    final list = await _repo.getAll();
    final map = <String, CollectionEntry>{
      for (final entry in list) entry.id: _classifyCuratedSeed(entry),
    };
    final stored = await _repo.getStoredOrder();
    final order = CollectionOrder.resolve(stored: stored, entries: list);
    _confirmedOrder = List<String>.unmodifiable(order);
    _publish(map, order);

    // Establish or repair the stored order once, so the next launch does not
    // have to re-derive it. Best effort: a read-only or failing store must
    // still show the collections the user has.
    if (!_sameOrder(stored, order)) {
      try {
        await _repo.saveOrder(order);
      } catch (_) {}
    }
  }

  /// Recognises curated seeds persisted before [CollectionOrigin] existed.
  ///
  /// Only [curatedSeedIds] qualify, and their queries are tags by
  /// definition, so this cannot promote an arbitrary legacy saved search. The
  /// promotion is in-memory: stored rows stay untouched until something else
  /// rewrites them.
  static CollectionEntry _classifyCuratedSeed(CollectionEntry entry) {
    if (entry.origin != CollectionOrigin.unknown) return entry;
    if (!curatedSeedIds.contains(entry.id)) return entry;
    return entry.copyWith(origin: CollectionOrigin.tag);
  }

  Future<String?> create({
    required String name,
    required String query,
    List<WallhavenCategory> kinds = const [],
    FeedFilter filter = const FeedFilter(),
    List<String> colors = const [],
    String? coverUrl,
    List<String> coverColors = const [],
    CollectionOrigin origin = CollectionOrigin.unknown,
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
      coverColors: List.unmodifiable(coverColors),
      origin: origin,
      createdAt: now,
    );
    final previousOrder = _order.peek();
    // New collections belong at the end: the user's own prioritisation of the
    // existing grid is never disturbed by adding one more.
    _publish({..._entries.peek(), id: entry}, [...previousOrder, id]);
    var stored = false;
    try {
      stored = await _repo.add(entry);
    } catch (_) {
      // Storage refused the write (full disk, provider error). The caller
      // gets the same message as a rejected write instead of an exception
      // escaping into the dialog, which would leave it stuck on "saving".
    }
    if (stored) return null;
    // Drop only this row, from the order as it stands now: a reorder that
    // landed while the write was in flight must survive the rollback.
    _publish(Map<String, CollectionEntry>.from(_entries.peek())..remove(id), [
      for (final existing in _order.peek())
        if (existing != id) existing,
    ]);
    return 'Failed to save';
  }

  /// Fills missing cover metadata for [id] from a grid visit.
  ///
  /// The cover itself is only taken when the collection has none, so a
  /// snapshot never changes underneath the user. A collection that already has
  /// a cover (including a legacy row saved before palettes existed) still gains
  /// its missing palette when the visit sees that same cover. Curated seeds keep
  /// their bundled asset and sampled palette.
  ///
  /// Optimistic, rolled back only on persistence failure, so the grid still
  /// opens when storage is unavailable. If the collection is deleted while the
  /// write is in flight the repository refuses the write, so the row cannot be
  /// resurrected by a late cover.
  Future<void> ensureCover(
    String id, {
    required String coverUrl,
    List<String> coverColors = const [],
  }) async {
    if (coverUrl.isEmpty) return;
    final current = _entries.peek();
    final entry = current[id];
    if (entry == null || seedCoverAssets.containsKey(id)) return;

    final takesCover = entry.coverUrl == null && entry.coverAsset == null;
    final takesPalette =
        entry.coverColors.isEmpty &&
        coverColors.isNotEmpty &&
        (takesCover || entry.coverUrl == coverUrl);
    if (!takesCover && !takesPalette) return;

    final updated = entry.copyWith(
      coverUrl: takesCover ? coverUrl : null,
      coverColors: takesPalette ? List.unmodifiable(coverColors) : null,
    );
    _entries.value = {...current, id: updated};
    var stored = false;
    try {
      stored = await _repo.update(updated);
    } catch (_) {
      // Storage refused the write; cover metadata is presentation-only, so the
      // fallback card is preferable to surfacing an error on a grid visit.
    }
    if (stored) return;

    // Roll back only the cover metadata, and only if this call's write is still
    // the newest one: a later cover for the same collection must win.
    final live = Map<String, CollectionEntry>.from(_entries.peek());
    final currentEntry = live[id];
    if (currentEntry == null || currentEntry.coverUrl != updated.coverUrl) {
      return;
    }
    live[id] = entry;
    _entries.value = live;
  }

  /// Deletes one user collection, optimistically.
  ///
  /// Returns `false` when the collection is curated, unknown, or the write
  /// failed — in which case the row is restored, so callers can surface an
  /// error instead of a false success. Rollback restores only this row, so a
  /// collection created or reordered meanwhile is left exactly as the user left
  /// it.
  Future<bool> remove(String id) async {
    final current = _entries.peek();
    final entry = current[id];
    if (entry == null || isCuratedDefault(id)) return false;
    final previousOrder = _order.peek();
    _publish(
      Map<String, CollectionEntry>.from(current)..remove(id),
      previousOrder,
    );
    try {
      await _repo.remove(id);
      _confirmedOrder = List<String>.unmodifiable(_order.peek());
      return true;
    } catch (_) {
      final live = Map<String, CollectionEntry>.from(_entries.peek());
      live.putIfAbsent(id, () => entry);
      final order = [..._order.peek()];
      if (!order.contains(id)) {
        final previousIndex = previousOrder.indexOf(id);
        order.insert(
          previousIndex < 0
              ? order.length
              : previousIndex.clamp(0, order.length),
          id,
        );
      }
      _publish(live, order);
      // A reorder issued while this removal was pending may have persisted an
      // order without [id]. Queue a repaired full order after it so restart
      // observes the same rollback position as the live grid.
      final repairedOrder = List<String>.unmodifiable(_order.peek());
      try {
        if (await _repo.saveOrder(repairedOrder)) {
          _confirmedOrder = repairedOrder;
        }
      } catch (_) {}
      return false;
    }
  }

  /// Persists [ids] as the new display order.
  ///
  /// The list is the full order the user just arranged, which keeps drag
  /// semantics (where a card lands after the one it passed) in the widget that
  /// owns the pointer, instead of splitting them across index conventions.
  /// Ids that no longer exist are ignored and rows missing from [ids] keep
  /// their place at the end, so a reorder that races a delete cannot lose a
  /// collection.
  ///
  /// Returns `true` when the order is stored (or already matched). On failure
  /// the previous order is restored unless a newer reorder has replaced it.
  Future<bool> reorder(List<String> ids) async {
    final current = _order.peek();
    final next = CollectionOrder.resolve(
      stored: ids,
      entries: _entries.peek().values,
    );
    if (_sameOrder(current, next)) return true;
    return _applyOrder(next);
  }

  /// Moves the collection [id] so it ends up at [index] (clamped).
  ///
  /// Returns `false` when [id] is unknown or the order could not be persisted;
  /// the previous order is then restored unless a newer move already replaced
  /// it.
  Future<bool> moveTo(String id, int index) async {
    final current = _order.peek();
    final from = current.indexOf(id);
    if (from < 0) return false;
    final target = index.clamp(0, current.length - 1);
    if (from == target) return true;
    final next = [...current]
      ..removeAt(from)
      ..insert(target, id);
    return _applyOrder(next);
  }

  /// Moves the collection [id] to the first position.
  Future<bool> moveToStart(String id) => moveTo(id, 0);

  /// Moves the collection [id] to the last position.
  Future<bool> moveToEnd(String id) => moveTo(id, _order.peek().length - 1);

  /// Shows [next], persists it, and rolls back to [previous] on failure.
  ///
  /// The revision guard matters because reorders overlap: without it a failing
  /// older write would snap the grid back to an order the user has already
  /// moved past.
  Future<bool> _applyOrder(List<String> next) async {
    final revision = ++_orderRevision;
    _publish(_entries.peek(), next);
    var stored = false;
    try {
      stored = await _repo.saveOrder(next);
    } catch (_) {}
    if (stored) {
      _confirmedOrder = List<String>.unmodifiable(
        CollectionOrder.resolve(stored: next, entries: _entries.peek().values),
      );
      return true;
    }
    if (_orderRevision != revision) return false;
    _publish(_entries.peek(), _confirmedOrder);
    return false;
  }

  /// Publishes a consistent (entries, order) pair.
  ///
  /// [CollectionOrder.resolve] drops ids with no row and appends rows with no
  /// id, so a caller only has to describe the intent — the invariant that the
  /// order names exactly the stored collections holds afterwards.
  void _publish(Map<String, CollectionEntry> map, List<String> order) {
    final resolved = CollectionOrder.resolve(
      stored: order,
      entries: map.values,
    );
    _entries.value = Map<String, CollectionEntry>.unmodifiable(map);
    _order.value = List<String>.unmodifiable(resolved);
  }

  static bool _sameOrder(List<String>? a, List<String> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
