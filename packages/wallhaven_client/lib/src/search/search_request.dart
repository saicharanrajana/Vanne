import '../enums/wallhaven_enums.dart';
import 'search_query.dart';

/// Strongly typed Wallhaven search request.
///
/// Maps 1:1 onto the documented `/search` query parameters. Default values
/// match the API's defaults (latest SFW, all categories, `date_added` desc).
/// Purity is always serialized because SFW-only and all-purity searches must
/// remain distinct in transport caches and in-flight request deduplication.
final class WallhavenSearchRequest {
  /// Raw query string for power users who want full control of `q` syntax.
  ///
  /// Mutually exclusive with [structuredQuery] — passing both throws
  /// [ArgumentError] at construction.
  final String? query;

  /// Structured equivalent of [query], built with [WallhavenQuery].
  final WallhavenQuery? structuredQuery;

  /// Categories bitfield (defaults to all three enabled).
  final Set<WallhavenCategory> categories;

  /// Purity bitfield. Defaults to SFW only; including
  /// [WallhavenPurity.nsfw] requires an API key server-side.
  final Set<WallhavenPurity> purity;

  final WallhavenSorting sorting;

  final WallhavenOrder order;

  /// Time window; only meaningful when [sorting] is
  /// [WallhavenSorting.toplist].
  final WallhavenTopRange? topRange;

  /// Minimum resolution in `WIDTHxHEIGHT` form, e.g. `1920x1080`
  /// (`atleast` parameter).
  final String? minResolution;

  /// Exact resolutions to include, e.g. `['1920x1080', '2560x1440']`.
  final List<String> resolutions;

  /// Aspect ratios in `WxH` form, e.g. `['16x9']`.
  final List<String> ratios;

  /// Dominant-color filters.
  final Set<WallhavenColor> colors;

  /// Tags to exclude via `-tag` tokens merged into the `q` parameter.
  /// Normalized lower-case tag names; each must match `^[a-z0-9_-]+$`.
  final Set<String> excludedTags;

  /// 1-based page number.
  final int page;

  /// Seed for [WallhavenSorting.random]. Must match `[a-zA-Z0-9]{6}`.
  ///
  /// Pass the seed returned in a previous page's metadata between requests
  /// so consecutive random pages do not repeat results.
  final String? seed;

  static final _resolutionPattern = RegExp(r'^\d+x\d+$');
  static final _ratioPattern = RegExp(r'^(\d+x\d+|portrait|landscape)$');
  static final _seedPattern = RegExp(r'^[a-zA-Z0-9]{6}$');
  static final _tagPattern = RegExp(r'^[a-z0-9_-]+$');

  /// Creates a search request, validating formats eagerly so malformed
  /// values fail at the call site rather than as an HTTP 400 later.
  WallhavenSearchRequest({
    this.query,
    this.structuredQuery,
    this.categories = const {
      WallhavenCategory.general,
      WallhavenCategory.anime,
      WallhavenCategory.people,
    },
    this.purity = const {WallhavenPurity.sfw},
    this.sorting = WallhavenSorting.dateAdded,
    this.order = WallhavenOrder.desc,
    this.topRange,
    this.minResolution,
    this.resolutions = const [],
    this.ratios = const [],
    this.colors = const {},
    this.excludedTags = const {},
    this.page = 1,
    this.seed,
  }) {
    if (query != null && structuredQuery != null) {
      throw ArgumentError(
        'Pass either query or structuredQuery, not both.',
        'query',
      );
    }
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'must be >= 1');
    }
    if (minResolution != null && !_resolutionPattern.hasMatch(minResolution!)) {
      throw ArgumentError.value(
        minResolution,
        'minResolution',
        'must match WIDTHxHEIGHT, e.g. 1920x1080',
      );
    }
    for (final resolution in resolutions) {
      if (!_resolutionPattern.hasMatch(resolution)) {
        throw ArgumentError.value(
          resolutions,
          'resolutions',
          'each entry must match WIDTHxHEIGHT, got "$resolution"',
        );
      }
    }
    for (final ratio in ratios) {
      if (!_ratioPattern.hasMatch(ratio)) {
        throw ArgumentError.value(
          ratios,
          'ratios',
          'each entry must match WIDTHxHEIGHT or portrait|landscape, got "$ratio"',
        );
      }
    }
    if (seed != null && !_seedPattern.hasMatch(seed!)) {
      throw ArgumentError.value(seed, 'seed', 'must match [a-zA-Z0-9]{6}');
    }
    for (final tag in excludedTags) {
      if (tag.isEmpty || !_tagPattern.hasMatch(tag)) {
        throw ArgumentError.value(
          excludedTags,
          'excludedTags',
          'each tag must match ^[a-z0-9_-]+\$, got "$tag"',
        );
      }
    }
  }

  /// Convenience copy helper returning a request targeting [newPage],
  /// preserving every other parameter (including an explicit random seed).
  WallhavenSearchRequest withPage(int newPage) => _copy(page: newPage);

  /// Convenience copy helper returning the same request with [newSeed]
  /// (pass `null` to drop an existing seed).
  WallhavenSearchRequest withSeed(String? newSeed) =>
      _copy(seed: newSeed, replaceSeed: true);

  /// Single copy implementation so a newly added field can never be
  /// silently dropped by one of the copy helpers. [replaceSeed] selects
  /// between keeping the current seed and using [seed].
  WallhavenSearchRequest _copy({
    int? page,
    String? seed,
    bool replaceSeed = false,
  }) => WallhavenSearchRequest(
    query: query,
    structuredQuery: structuredQuery,
    categories: categories,
    purity: purity,
    sorting: sorting,
    order: order,
    topRange: topRange,
    minResolution: minResolution,
    resolutions: resolutions,
    ratios: ratios,
    colors: colors,
    excludedTags: excludedTags,
    page: page ?? this.page,
    seed: replaceSeed ? seed : this.seed,
  );

  /// Wire-format query parameters. Null/empty/default-noop entries are
  /// omitted except purity, which is always explicit; list values are
  /// comma-joined per the API contract.
  Map<String, String> toQueryParameters() {
    // Note: keys here are pre-encoding literals. dio/Uri percent-encode them
    // exactly once when building the request URL.
    final params = <String, String>{};
    final rawQ = structuredQuery?.build() ?? query;
    final tagsQ = excludedTags.map((t) => '-$t').join(' ');
    final combined = [
      if (rawQ != null && rawQ.isNotEmpty) rawQ,
      if (tagsQ.isNotEmpty) tagsQ,
    ].join(' ');
    if (combined.isNotEmpty) params['q'] = combined;
    if (categories.length != WallhavenCategory.values.length) {
      params['categories'] = encodeCategories(categories);
    }
    // Keep purity explicit even for SFW and all-purity requests. Although
    // the API treats omitted/all as equivalent, the client cache and request
    // deduper key on the wire query and must distinguish these policies.
    params['purity'] = encodePurities(purity);
    if (sorting != WallhavenSorting.dateAdded) {
      params['sorting'] = sorting.wireName;
    }
    if (order != WallhavenOrder.desc) {
      params['order'] = order.wireName;
    }
    if (topRange != null) params['topRange'] = topRange!.wireName;
    if (minResolution != null) params['atleast'] = minResolution!;
    if (resolutions.isNotEmpty) params['resolutions'] = resolutions.join(',');
    if (ratios.isNotEmpty) params['ratios'] = ratios.join(',');
    if (colors.isNotEmpty) {
      params['colors'] = colors.map((c) => c.hex).join(',');
    }
    if (page > 1) params['page'] = '$page';
    if (seed != null) params['seed'] = seed!;
    return params;
  }

  @override
  String toString() => 'WallhavenSearchRequest(${toQueryParameters()})';
}
