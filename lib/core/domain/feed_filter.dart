import 'package:wallhaven_client/wallhaven_client.dart';

/// User-facing feed configuration shared by Discover, Search and collection
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

  /// Category filters. Defaults to General only per product choice.
  /// Encoding omits the param only when all three are set (`111`).
  final Set<WallhavenCategory> categories;

  const FeedFilter({
    this.sorting = FeedSorting.newest,
    this.topRange,
    this.minResolution,
    this.categories = const {WallhavenCategory.general},
  });

  /// The product default for the Discover feed — General only.
  static const discoverDefault = FeedFilter(
    categories: {WallhavenCategory.general},
  );

  bool get isDefaultCategories =>
      categories.length == WallhavenCategory.values.length;

  FeedFilter copyWith({
    FeedSorting? sorting,
    FeedTopRange? topRange,
    String? minResolution,
    Set<WallhavenCategory>? categories,
    bool clearMinResolution = false,
    bool clearTopRange = false,
  }) => FeedFilter(
    sorting: sorting ?? this.sorting,
    topRange: clearTopRange ? null : (topRange ?? this.topRange),
    minResolution: clearMinResolution
        ? null
        : (minResolution ?? this.minResolution),
    categories: categories ?? this.categories,
  );

  /// Human-readable summary shown on the filter button, e.g. `Popular ·
  /// This week · 1080p+`. Categories are deliberately omitted from the chip.
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
          other.minResolution == minResolution &&
          other.categories.length == categories.length &&
          other.categories.containsAll(categories);

  @override
  int get hashCode => Object.hash(
    sorting,
    topRange,
    minResolution,
    Object.hashAllUnordered(categories),
  );
}

/// Ordering options surfaced in the UI.
enum FeedSorting {
  newest,
  relevance,
  random,
  views,
  favorites,
  popular,
  hot;

  String get label => switch (this) {
    FeedSorting.newest => 'Newest',
    FeedSorting.relevance => 'Relevance',
    FeedSorting.random => 'Random',
    FeedSorting.views => 'Most viewed',
    FeedSorting.favorites => 'Most favorited',
    FeedSorting.popular => 'Popular',
    FeedSorting.hot => 'Hot',
  };

  WallhavenSorting get wire => switch (this) {
    FeedSorting.newest => WallhavenSorting.dateAdded,
    FeedSorting.relevance => WallhavenSorting.relevance,
    FeedSorting.random => WallhavenSorting.random,
    FeedSorting.views => WallhavenSorting.views,
    FeedSorting.favorites => WallhavenSorting.favorites,
    FeedSorting.popular => WallhavenSorting.toplist,
    FeedSorting.hot => WallhavenSorting.hot,
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
  art('Art'),
  abstract('Abstract'),
  minimal('Minimal'),
  architecture('Architecture'),
  dark('Dark');

  final String label;

  const FeedGenre(this.label);

  /// Search term appended to the query when selected.
  String get searchTerm => switch (this) {
    FeedGenre.abstract => 'abstract',
    FeedGenre.minimal => 'minimalist',
    _ => name,
  };
}
