import 'package:wallhaven_client/wallhaven_client.dart';

/// A browsable wallpaper category shown on the Categories tab.
///
/// Categories are pure configuration: each maps to a Wallhaven search term
/// plus optional category constraints. Adding one is a single list entry —
/// no UI changes required.
final class AppCategory {
  /// Stable identifier used in routing (`/categories/:id`).
  final String id;

  /// Display title, e.g. `Nature`.
  final String title;

  /// Search query term passed to Wallhaven (fuzzy tag match).
  final String searchTerm;

  /// Restrict the search to these Wallhaven buckets; empty = all.
  final List<WallhavenCategoryKind> kinds;

  /// Representative artwork URL — a known stable Wallhaven thumbnail.
  /// Rendered once and kept alive by the image cache; revisiting the tab
  /// makes zero additional requests.
  final Uri artwork;

  const AppCategory({
    required this.id,
    required this.title,
    required this.searchTerm,
    this.kinds = const [],
    required this.artwork,
  });
}

/// Which Wallhaven content buckets a category searches.
enum WallhavenCategoryKind { general, anime, people }

/// The curated category set for the Categories tab.
final appCategories = <AppCategory>[
  AppCategory(
    id: 'anime',
    title: 'Anime',
    searchTerm: 'anime',
    kinds: [WallhavenCategoryKind.anime],
    artwork: _art('x8zvom'),
  ),
  AppCategory(
    id: 'nature',
    title: 'Nature',
    searchTerm: 'nature landscape',
    artwork: _art('rd6kw7'),
  ),
  AppCategory(
    id: 'space',
    title: 'Space',
    searchTerm: 'space galaxy nebula',
    artwork: _art('qd5r6d'),
  ),
  AppCategory(
    id: 'abstract',
    title: 'Abstract',
    searchTerm: 'abstract',
    kinds: [WallhavenCategoryKind.general],
    artwork: _art('wqy36y'),
  ),
  AppCategory(
    id: 'minimal',
    title: 'Minimal',
    searchTerm: 'minimalist',
    artwork: _art('ml3p1m'),
  ),
  AppCategory(
    id: 'architecture',
    title: 'Architecture',
    searchTerm: 'architecture building',
    artwork: _art('ox9g6o'),
  ),
  AppCategory(
    id: 'cars',
    title: 'Cars',
    searchTerm: 'car',
    artwork: _art('e77o1q'),
  ),
  AppCategory(
    id: 'games',
    title: 'Games',
    searchTerm: 'video games',
    artwork: _art('nv6d7b'),
  ),
  AppCategory(
    id: 'technology',
    title: 'Technology',
    searchTerm: 'technology',
    artwork: _art('jv3lqv'),
  ),
  AppCategory(
    id: 'animals',
    title: 'Animals',
    searchTerm: 'animal wildlife',
    artwork: _art('2ygr9w'),
  ),
  AppCategory(
    id: 'dark',
    title: 'Dark',
    searchTerm: 'dark',
    artwork: _art('pkyxge'),
  ),
  AppCategory(
    id: 'amoled',
    title: 'AMOLED',
    searchTerm: 'amoled black background',
    artwork: _art('85oz52'),
  ),
];

/// Builds a large thumbnail URL from a hand-picked wallpaper ID.
///
/// These use Wallhaven's documented thumbnail host for the fixed IDs above;
/// dynamic wallpapers always use API-provided URLs verbatim.
Uri _art(String id) => Uri.parse('https://th.wallhaven.cc/lg/$id.jpg');

extension WallhavenCategoryKindX on WallhavenCategoryKind {
  WallhavenCategory get wire => switch (this) {
    WallhavenCategoryKind.general => WallhavenCategory.general,
    WallhavenCategoryKind.anime => WallhavenCategory.anime,
    WallhavenCategoryKind.people => WallhavenCategory.people,
  };
}
