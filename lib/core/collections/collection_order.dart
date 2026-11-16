import 'collection_entry.dart';

/// Reconciles the persisted collection order against the rows that exist.
///
/// The order is stored separately from collection content so existing rows keep
/// their JSON shape. Separate stores mean the two can drift: a crash between a
/// row write and an order write leaves an id pointing at nothing, or a row with
/// no position. [resolve] is the single repair step for both directions, and it
/// is safe to run on every launch because it is idempotent:
///
/// * stored ids that no longer exist are dropped,
/// * duplicate ids keep their first position,
/// * rows missing from the stored order are appended in creation order,
/// * two rows created in the same microsecond fall back to id order, so the
///   result never depends on map iteration.
///
/// A `null` [stored] means no order has ever been written (a fresh install, or
/// an install upgraded from the version that sorted by creation date). Every
/// row is then placed in creation order, which is exactly what those installs
/// showed before the upgrade, with restored curated collections appended after
/// them in their own deterministic creation order.
abstract final class CollectionOrder {
  /// Returns the display order for [entries] as a list of collection ids.
  ///
  /// The result always contains every id in [entries] exactly once, so callers
  /// can treat it as authoritative.
  static List<String> resolve({
    required List<String>? stored,
    required Iterable<CollectionEntry> entries,
  }) {
    final byId = <String, CollectionEntry>{
      for (final entry in entries) entry.id: entry,
    };
    final ordered = <String>[];
    final placed = <String>{};
    for (final id in stored ?? const <String>[]) {
      if (!byId.containsKey(id)) continue;
      if (!placed.add(id)) continue;
      ordered.add(id);
    }
    final unplaced = [
      for (final entry in byId.values)
        if (!placed.contains(entry.id)) entry,
    ]..sort(_byCreation);
    ordered.addAll(unplaced.map((entry) => entry.id));
    return ordered;
  }

  static int _byCreation(CollectionEntry a, CollectionEntry b) {
    final byDate = a.createdAt.compareTo(b.createdAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }
}
