import 'dart:convert';

import 'package:wallhaven_client/wallhaven_client.dart';

import '../../shared/utils/color_display.dart';
import '../../shared/utils/display_title.dart';
import '../domain/feed_filter.dart';
import '../storage/persisted_json.dart';

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

  /// Whether this collection may contribute its [colors] as a colour filter.
  ///
  /// The mirror of [isTagCollection]: only positively classified colour
  /// collections qualify, so a legacy row of unknown origin is never treated
  /// as one from the shape of its fields alone.
  bool get isColorCollection =>
      origin == CollectionOrigin.color && colors.isNotEmpty;

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
    // Local storage is untrusted: every field except the id is read with a
    // safe default, so one damaged field cannot delete a saved collection.
    final kindsRaw = readList(json['kinds']);
    final kinds = <WallhavenCategory>[];
    for (final raw in kindsRaw) {
      if (raw is String) {
        try {
          kinds.add(WallhavenCategory.values.byName(raw));
        } catch (_) {}
      }
    }
    final filterRaw = readObject(json['filter']);
    final sortingName = readString(filterRaw['sorting']);
    final topRangeName = readString(filterRaw['topRange']);
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
    final minRes = readString(filterRaw['minResolution']);
    final categoriesRaw = filterRaw['categories'] is List
        ? readList(filterRaw['categories'])
        : null;
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

    final colorsRaw = readList(json['colors']);
    final colors = [
      for (final raw in colorsRaw)
        if (raw is String && raw.isNotEmpty) raw,
    ];
    final coverUrl = readString(json['coverUrl']);
    final coverAsset = readString(json['coverAsset']);
    final coverColors = ColorDisplay.normalizedPalette(
      readList(json['coverColors']).whereType<String>(),
    );

    return CollectionEntry(
      id: readString(json['id']) ?? '',
      name: readString(json['name']) ?? '',
      query: readString(json['query']) ?? '',
      kinds: kinds,
      filter: FeedFilter(
        sorting: sorting,
        topRange: topRange,
        minResolution: minRes,
        categories: categories,
      ),
      colors: colors,
      coverUrl: coverUrl != null && coverUrl.isNotEmpty ? coverUrl : null,
      coverAsset: coverAsset != null && coverAsset.isNotEmpty
          ? coverAsset
          : null,
      coverColors: coverColors,
      origin: CollectionOrigin.fromName(json['origin']),
      // Rows written before timestamps were stored, or with a damaged one,
      // fall back to "now": collections sort by creation, and a fabricated
      // default keeps the rest of the list intact.
      createdAt:
          DateTime.tryParse(readString(json['createdAt']) ?? '') ??
          DateTime.now(),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Decodes a stored row, or `null` when [raw] cannot describe one.
  ///
  /// A row is only unreadable when it has no identity: not JSON, not an
  /// object, or no non-empty `id`. Other fields are metadata and are read with
  /// safe defaults by [CollectionEntry.fromJson]. The [TypeError] catch is an
  /// outer guard for the same reason — an escaping error would reject the
  /// whole batch, and startup awaits collection reconciliation before it shows
  /// any screen.
  static CollectionEntry? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final entry = CollectionEntry.fromJson(decoded);
      // Rows are keyed by id and every screen routes by it.
      return entry.id.isEmpty ? null : entry;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
