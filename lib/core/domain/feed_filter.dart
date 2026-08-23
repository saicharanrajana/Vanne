import 'package:wallhaven_client/wallhaven_client.dart';

/// User-facing feed configuration shared by Discover, Search and Category
/// exploration. Pure value object — no request types leak into UI.
///
/// Portrait-only and purity are intentionally NOT part of this object:
/// they are global preferences applied by [WallpaperRepository] on every
/// request, so a filter change in one screen can never silently weaken
/// another screen's content policy.
final class FeedFilter {
  /// Result ordering.
  final FeedSorting sorting;

  /// Time window when [sorting] is popular; ignored otherwise.
  final FeedTopRange? topRange;

  /// Minimum resolution in `WIDTHxHEIGHT` form, or `null` for no floor.
  final String? minResolution;

  const FeedFilter({
    this.sorting = FeedSorting.newest,
    this.topRange,
    this.minResolution,
  });

  /// The product default for the Discover feed.
  static const discoverDefault = FeedFilter();

  FeedFilter copyWith({
    FeedSorting? sorting,
    FeedTopRange? topRange,
    String? minResolution,
    bool clearMinResolution = false,
  }) => FeedFilter(
    sorting: sorting ?? this.sorting,
    topRange: topRange ?? this.topRange,
    minResolution: clearMinResolution
        ? null
        : (minResolution ?? this.minResolution),
  );

  /// Human-readable summary shown on the filter button, e.g. `Popular ·
  /// This week · 1080p+`. Empty string when everything is default.
  String get summary {
    final parts = <String>[
      sorting.label,
      if (sorting == FeedSorting.popular && topRange != null) topRange!.label,
      if (minResolution != null) '$minResolution+',
    ];
    return parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedFilter &&
          other.sorting == sorting &&
          other.topRange == topRange &&
          other.minResolution == minResolution;

  @override
  int get hashCode => Object.hash(sorting, topRange, minResolution);
}

/// Ordering options surfaced in the UI.
enum FeedSorting {
  newest,
  popular,
  random,
  views;

  String get label => switch (this) {
    FeedSorting.newest => 'Newest',
    FeedSorting.popular => 'Popular',
    FeedSorting.random => 'Random',
    FeedSorting.views => 'Most viewed',
  };

  WallhavenSorting get wire => switch (this) {
    FeedSorting.newest => WallhavenSorting.dateAdded,
    FeedSorting.popular => WallhavenSorting.toplist,
    FeedSorting.random => WallhavenSorting.random,
    FeedSorting.views => WallhavenSorting.views,
  };
}

/// Time windows offered for popular sorting.
enum FeedTopRange {
  day,
  week,
  month,
  year;

  String get label => switch (this) {
    FeedTopRange.day => 'Today',
    FeedTopRange.week => 'This week',
    FeedTopRange.month => 'This month',
    FeedTopRange.year => 'This year',
  };

  WallhavenTopRange get wire => switch (this) {
    FeedTopRange.day => WallhavenTopRange.day1,
    FeedTopRange.week => WallhavenTopRange.week1,
    FeedTopRange.month => WallhavenTopRange.month1,
    FeedTopRange.year => WallhavenTopRange.year1,
  };
}

/// Dominant-color filter options (Wallhaven's documented search colors).
enum FeedColor {
  black('000000'),
  white('ffffff'),
  red('cc0000'),
  orange('ff9900'),
  yellow('ffff00'),
  green('77cc33'),
  cyan('66cccc'),
  blue('0066cc'),
  purple('993399'),
  pink('ea4c88');

  const FeedColor(this.hex);

  /// 6-digit hex without `#`, exactly as the API expects.
  final String hex;

  String get label => name[0].toUpperCase() + name.substring(1);

  /// Display color derived from the wire hex.
  int get colorValue => 0xFF000000 | int.parse(hex, radix: 16);
}

/// Genre chips offered on the Search screen. Each maps to a fuzzy tag
/// term; tapping combines with the typed query.
enum FeedGenre {
  anime('Anime'),
  nature('Nature'),
  space('Space'),
  abstract('Abstract'),
  minimal('Minimal'),
  architecture('Architecture'),
  cars('Cars'),
  games('Games'),
  technology('Technology'),
  dark('Dark'),
  amoled('AMOLED');

  final String label;

  const FeedGenre(this.label);

  /// Search term appended to the query when selected.
  String get searchTerm => switch (this) {
    FeedGenre.abstract => 'abstract',
    FeedGenre.minimal => 'minimalist',
    _ => name,
  };
}
