import 'dart:convert';

import 'package:wallhaven_client/wallhaven_client.dart';

import '../domain/feed_filter.dart';
import '../../shared/utils/display_title.dart';

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
  final DateTime createdAt;

  const CollectionEntry({
    required this.id,
    required this.name,
    required this.query,
    this.kinds = const [],
    this.filter = const FeedFilter(),
    this.colors = const [],
    required this.createdAt,
  });

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
    },
    'colors': colors,
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

    final colorsRaw = json['colors'] as List<dynamic>? ?? const [];
    final colors = [
      for (final raw in colorsRaw)
        if (raw is String && raw.isNotEmpty) raw,
    ];

    return CollectionEntry(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      query: json['query'] as String? ?? '',
      kinds: kinds,
      filter: FeedFilter(
        sorting: sorting,
        topRange: topRange,
        minResolution: minRes,
      ),
      colors: colors,
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now(),
    );
  }

  String encode() => jsonEncode(toJson());

  static CollectionEntry? decode(String raw) {
    try {
      return CollectionEntry.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    }
  }
}
