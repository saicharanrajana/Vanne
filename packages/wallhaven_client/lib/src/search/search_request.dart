import '../enums/wallhaven_enums.dart';
import 'search_query.dart';

/// Strongly typed Wallhaven search request.
///
/// Maps 1:1 onto the documented `/search` query parameters. Defaults match
/// the API's own defaults (latest SFW, all categories, `date_added` desc)
/// and are omitted from the generated parameter map when unchanged.
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
      throw ArgumentError.value(
        seed,
        'seed',
        'must match [a-zA-Z0-9]{6}',
      );
    }
  }

  /// Convenience copy helper returning a request targeting [newPage],
  /// preserving every other parameter (including an explicit random seed).
  WallhavenSearchRequest withPage(int newPage) => WallhavenSearchRequest(
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
        page: newPage,
        seed: seed,
      );

  /// Convenience copy helper returning the same request with [newSeed]
  /// (pass `null` to drop an existing seed).
  WallhavenSearchRequest withSeed(String? newSeed) => WallhavenSearchRequest(
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
        page: page,
        seed: newSeed,
      );

  /// Wire-format query parameters. Null/empty/default-noop entries are
  /// omitted; list values are comma-joined per the API contract.
  Map<String, String> toQueryParameters() {
    // Note: keys here are pre-encoding literals. dio/Uri percent-encode them
    // exactly once when building the request URL.
    final params = <String, String>{};
    final q = structuredQuery?.build() ?? query;
    if (q != null && q.isNotEmpty) params['q'] = q;
    if (categories.length != WallhavenCategory.values.length) {
      params['categories'] = encodeCategories(categories);
    }
    // Purity is omitted when equal to the documented API default (SFW
    // only) or when every purity is enabled (equivalent server-side).
    final isDefaultPurity = purity.length == 1 &&
        purity.contains(WallhavenPurity.sfw);
    if (!isDefaultPurity && purity.length != WallhavenPurity.values.length) {
      params['purity'] = encodePurities(purity);
    }
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
