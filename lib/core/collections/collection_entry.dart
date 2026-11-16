import 'dart:convert';

import 'package:wallhaven_client/wallhaven_client.dart';

import '../domain/feed_filter.dart';
import '../../shared/utils/color_display.dart';
import '../../shared/utils/display_title.dart';

/// Where a saved collection came from.
///
/// Bookmarking a tag grid and bookmarking a colour grid both produce a
/// collection whose shape alone cannot be told apart reliably: an old manual
/// collection could also be a query with no colours. The origin is therefore
/// recorded at creation time instead of inferred.
///
/// [unknown] is the backward-compatible default for rows written before this
/// field existed. Those entries are preserved like any other collection but
/// never treated as tags, because their query may be an arbitrary Wallhaven
/// search expression (`like:abc123`) rather than a tag.
enum CollectionOrigin {
  /// Saved from a tag grid: [CollectionEntry.query] is the tag term.
  tag,

  /// Saved from a colour grid: [CollectionEntry.colors] holds the hex codes.
  color,

  /// Legacy row with no recorded origin. Never offered as a tag filter.
  unknown;

  /// Decodes [raw], falling back to [unknown] for absent or unknown values.
  static CollectionOrigin fromName(Object? raw) {
    for (final origin in values) {
      if (origin.name == raw) return origin;
    }
    return unknown;
  }
}

/// Locally-persisted collection — a named shortcut to a Wallhaven search.
///
/// Mirrors `FavoriteWallpaper` persistence: JSON string in Hive, `compute`
/// for batch decode. `kinds` are Wallhaven category buckets (empty = all).
final class CollectionEntry {
  final String id;
  final String name;
  final String query;
  final List<WallhavenCategory> kinds;
  final FeedFilter filter;
  final List<String> colors;

  /// Snapshot of the first wallpaper thumbnail when the user bookmarked the
  /// query. Stable afterwards; never refreshed by sorting or reopening.
  final String? coverUrl;

  /// Bundled cover for curated seeds. User-created collections use
  /// [coverUrl] instead.
  final String? coverAsset;

  /// Palette of the wallpaper that supplied [coverUrl], most common colour
  /// first, as normalized `#RRGGBB` values.
  ///
  /// Presentation only: it tints the cover's selection stroke and must never
  /// be confused with [colors], which is part of the saved search. Empty for
  /// rows saved before the field existed and for covers that could not be
  /// sampled.
  final List<String> coverColors;

  /// Where this collection was saved from. Legacy rows decode as
  /// [CollectionOrigin.unknown].
  final CollectionOrigin origin;

  final DateTime createdAt;

  const CollectionEntry({
    required this.id,
    required this.name,
    required this.query,
    this.kinds = const [],
    this.filter = const FeedFilter(),
    this.colors = const [],
    this.coverUrl,
    this.coverAsset,
    this.coverColors = const [],
    this.origin = CollectionOrigin.unknown,
    required this.createdAt,
  });

  /// Whether this collection may contribute its [query] as a tag filter.
  ///
  /// Only positively classified tag collections qualify. A colour collection
  /// has no tag term, and a legacy [CollectionOrigin.unknown] row may hold an
  /// arbitrary search expression, so neither is offered as a tag.
  bool get isTagCollection =>
      origin == CollectionOrigin.tag && query.trim().isNotEmpty;

  /// Returns a copy with cover metadata or origin replaced. A null argument
  /// keeps the current value; cover updates never clear an existing cover.
  CollectionEntry copyWith({
    String? coverUrl,
    String? coverAsset,
    List<String>? coverColors,
    CollectionOrigin? origin,
  }) => CollectionEntry(
    id: id,
    name: name,
    query: query,
    kinds: kinds,
    filter: filter,
    colors: colors,
    coverUrl: coverUrl ?? this.coverUrl,
    coverAsset: coverAsset ?? this.coverAsset,
    coverColors: coverColors ?? this.coverColors,
    origin: origin ?? this.origin,
    createdAt: createdAt,
  );

  /// Display name in Pascal casing per word, e.g. `dark minimal` →
  /// `Dark Minimal`. Storage keeps the raw input; only presentation cases.
  /// Hex names (`#RRGGBB`) are returned verbatim uppercased so `#ff0000`
  /// does not become `#Ff0000`.
  String get displayName => formatDisplayTitle(name);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'query': query,
    'kinds': [for (final k in kinds) k.name],
    'filter': {
      'sorting': filter.sorting.name,
      'topRange': filter.topRange?.name,
      'minResolution': filter.minResolution,
      // Categories are part of what the collection saves, so they must
      // round-trip: a row whose categories were dropped would decode as the
      // General-only default and stop matching the page it was saved from.
      'categories': [for (final c in filter.categories) c.name],
    },
    'colors': colors,
    if (coverUrl != null) 'coverUrl': coverUrl,
    if (coverAsset != null) 'coverAsset': coverAsset,
    if (coverColors.isNotEmpty) 'coverColors': coverColors,
    'origin': origin.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CollectionEntry.fromJson(Map<String, dynamic> json) {
    final kindsRaw = json['kinds'] as List<dynamic>? ?? const [];
    final kinds = <WallhavenCategory>[];
    for (final raw in kindsRaw) {
      if (raw is String) {
        try {
          kinds.add(WallhavenCategory.values.byName(raw));
        } catch (_) {}
      }
    }
    final filterRaw = json['filter'] as Map<String, dynamic>? ?? const {};
    final sortingName = filterRaw['sorting'] as String?;
    final topRangeName = filterRaw['topRange'] as String?;
    FeedSorting sorting = FeedSorting.newest;
    if (sortingName != null) {
      try {
        sorting = FeedSorting.values.byName(sortingName);
      } catch (_) {}
    }
    FeedTopRange? topRange;
    if (topRangeName != null) {
      try {
        topRange = FeedTopRange.values.byName(topRangeName);
      } catch (_) {}
    }
    final minRes = filterRaw['minResolution'] as String?;
    final categoriesRaw = filterRaw['categories'] as List<dynamic>?;
    // Absent for rows written before categories were persisted. Those rows
    // were created by builds whose default was General-only, so the default
    // [FeedFilter] is the faithful reading rather than a lossy one. An empty
    // list is kept as-is: an all-off bitfield filters everything out, it does
    // not mean "all categories".
    final defaultCategories = const {WallhavenCategory.general};
    Set<WallhavenCategory> categories = defaultCategories;
    if (categoriesRaw != null) {
      final decoded = <WallhavenCategory>{};
      for (final raw in categoriesRaw) {
        if (raw is! String) continue;
        try {
          decoded.add(WallhavenCategory.values.byName(raw));
        } catch (_) {}
      }
      categories = decoded;
    }

    final colorsRaw = json['colors'] as List<dynamic>? ?? const [];
    final colors = [
      for (final raw in colorsRaw)
        if (raw is String && raw.isNotEmpty) raw,
    ];
    final coverUrl = json['coverUrl'];
    final coverAsset = json['coverAsset'];
    final coverColorsRaw = json['coverColors'];
    final coverColors = ColorDisplay.normalizedPalette(
      coverColorsRaw is List ? coverColorsRaw.whereType<String>() : const [],
    );

    return CollectionEntry(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      query: json['query'] as String? ?? '',
      kinds: kinds,
      filter: FeedFilter(
        sorting: sorting,
        topRange: topRange,
        minResolution: minRes,
        categories: categories,
      ),
      colors: colors,
      coverUrl: coverUrl is String && coverUrl.isNotEmpty ? coverUrl : null,
      coverAsset: coverAsset is String && coverAsset.isNotEmpty
          ? coverAsset
          : null,
      coverColors: coverColors,
      origin: CollectionOrigin.fromName(json['origin']),
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now(),
    );
  }

  String encode() => jsonEncode(toJson());

  static CollectionEntry? decode(String raw) {
    try {
      return CollectionEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }
}
