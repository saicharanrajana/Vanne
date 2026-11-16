import 'package:wallhaven_client/wallhaven_client.dart';

import '../../shared/utils/color_display.dart';
import '../domain/feed_filter.dart';
import 'collection_entry.dart';

/// The saved search a collection stands for.
///
/// `CollectionsController.create` derives a collection's *name* from the tag or
/// colour page it was bookmarked from, so names are presentation, not identity:
/// two different searches can share a title, and a user-visible rename must not
/// change which search a row saves. Deciding whether a browsed page is already
/// saved therefore compares this definition instead of the display name — a
/// name collision can never authorise deleting someone else's collection.
///
/// Normalisation is deliberately conservative. Only differences that cannot
/// change the search are folded away:
///
/// * surrounding and repeated whitespace in [query],
/// * `#rgb` / `#RRGGBB` / case differences in [colors],
/// * colours becoming an unordered set (they are a filter, not an ordering),
/// * [FeedFilter.topRange] while the sort is not `popular` (Wallhaven ignores
///   it there), and `minResolution` padding.
///
/// Query case and boolean operators are kept verbatim: `like:abc123` and
/// `LIKE:abc123` are not assumed to mean the same thing.
///
/// Categories are compared as the request actually uses them: a non-empty
/// legacy [CollectionEntry.kinds] overrides [FeedFilter.categories], otherwise
/// the filter categories are effective.
final class CollectionSearchDefinition {
  final String query;
  final FeedFilter filter;
  final Set<String> colors;

  CollectionSearchDefinition._({
    required this.query,
    required this.filter,
    required this.colors,
  });

  factory CollectionSearchDefinition({
    required String query,
    FeedFilter filter = const FeedFilter(),
    Iterable<String> colors = const [],
    Iterable<WallhavenCategory>? categories,
  }) {
    final suppliedCategories = categories?.toSet();
    final effectiveCategories =
        suppliedCategories == null || suppliedCategories.isEmpty
        ? filter.categories
        : suppliedCategories;
    return CollectionSearchDefinition._(
      query: _normalizeQuery(query),
      filter: _normalizeFilter(
        filter,
        effectiveCategories: effectiveCategories,
      ),
      colors: Set.unmodifiable(_normalizeColors(colors)),
    );
  }

  /// The definition [entry] was saved with, using the same category precedence
  /// as [WallpaperRepository.search].
  factory CollectionSearchDefinition.of(CollectionEntry entry) =>
      CollectionSearchDefinition(
        query: entry.query,
        filter: entry.filter,
        categories: entry.kinds,
        colors: entry.colors,
      );

  /// The origin a fresh save of this definition would record.
  ///
  /// Colours only ever come from a colour grid, and a query without colours
  /// from a tag grid; this is a property of the definition, not of the row.
  CollectionOrigin get impliedOrigin =>
      colors.isEmpty ? CollectionOrigin.tag : CollectionOrigin.color;

  /// Whether [entry] saves exactly this definition.
  bool matches(CollectionEntry entry) =>
      CollectionSearchDefinition.of(entry) == this;

  static final _whitespace = RegExp(r'\s+');

  static String _normalizeQuery(String raw) =>
      raw.trim().replaceAll(_whitespace, ' ');

  static FeedFilter _normalizeFilter(
    FeedFilter filter, {
    required Set<WallhavenCategory> effectiveCategories,
  }) {
    final resolution = filter.minResolution?.trim();
    return FeedFilter(
      sorting: filter.sorting,
      // Only popular sorting consults the range; keeping a stale value on any
      // other sort would make an otherwise identical search look different.
      topRange: filter.sorting == FeedSorting.popular ? filter.topRange : null,
      minResolution: (resolution == null || resolution.isEmpty)
          ? null
          : resolution,
      categories: Set.unmodifiable(effectiveCategories),
    );
  }

  static Set<String> _normalizeColors(Iterable<String> raw) {
    final normalized = <String>{};
    for (final value in raw) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      // Unparseable values are kept verbatim so two identical junk entries
      // still compare equal instead of silently disappearing.
      normalized.add(ColorDisplay.normalizedHex(trimmed) ?? trimmed);
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectionSearchDefinition &&
          other.query == query &&
          other.filter == filter &&
          other.colors.length == colors.length &&
          other.colors.containsAll(colors);

  @override
  int get hashCode =>
      Object.hash(query, filter, Object.hashAllUnordered(colors));

  @override
  String toString() =>
      'CollectionSearchDefinition(query: $query, '
      'filter: ${filter.summary}, colors: $colors)';
}
