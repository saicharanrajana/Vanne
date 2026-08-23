import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../domain/feed_filter.dart';
import 'wallpaper_repository.dart';

/// Immutable UI state for an infinitely-paginated wallpaper feed.
///
/// Errors are localized: [error] replaces content only on first load,
/// while [paginationError] preserves already-loaded pages and offers a
/// retry affordance at the end of the grid.
///
/// Items are stored as a [Set] via signals for deduplication (equatable
/// on author/size/dimension/url) and exposed as a [List] for the UI.
/// The set is in-memory only and not persisted.
final class FeedState {
  final Set<Wallpaper> items;

  /// True while page 1 is loading (skeleton state).
  final bool loadingFirst;

  /// True while a subsequent page is loading (footer indicator).
  final bool loadingMore;

  /// First-load failure message; `null` when content is usable.
  final String? error;

  /// Load-more failure message; existing items remain visible.
  final String? paginationError;

  /// Whether another page may exist.
  final bool hasMore;

  const FeedState({
    this.items = const {},
    this.loadingFirst = false,
    this.loadingMore = false,
    this.error,
    this.paginationError,
    this.hasMore = true,
  });

  const FeedState.initialLoading()
    : this(items: const {}, loadingFirst: true);

  /// Ordered list for widgets that need a List (preserves insertion order).
  List<Wallpaper> get itemsList => items.toList(growable: false);

  FeedState copyWith({bool? loadingMore, String? paginationError}) => FeedState(
    items: items,
    loadingFirst: loadingFirst,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error,
    paginationError: paginationError ?? this.paginationError,
    hasMore: hasMore,
  );
}

/// Base controller for every remote wallpaper feed (Discover, Search,
/// Category exploration).
///
/// Owns:
/// - reactive [state] consumed by the shared grid widget,
/// - request guarding (never two pages in flight),
/// - duplicate suppression across appended pages,
/// - random-sort seed propagation between pages,
/// - retry semantics that never discard loaded content.
///
/// Subclasses describe *which* search to run via [buildSpec]; input
/// changes call [reload] which restarts pagination cleanly.
abstract class FeedController {
  final WallpaperRepository _repository;

  /// Current reactive state.
  final state = signal(const FeedState());

  /// Server seed carried across pages of a random-sorted feed.
  String? _seed;

  /// Last requested page number; reset on [reload].
  int _pagesRequested = 0;

  /// Guards concurrent page loads.
  bool _inFlight = false;

  FeedController(this._repository);

  /// Describes the next request from current controller inputs.
  SearchRequestSpec buildSpec();

  /// Starts (or restarts) the feed from page 1.
  Future<void> reload() async {
    _inFlight = false;
    _seed = null;
    _pagesRequested = 0;
    state.set(const FeedState.initialLoading());
    await _loadPage(append: false);
  }

  /// Loads the next page when available; no-op while busy or exhausted.
  Future<void> loadMore() async {
    final current = state.value;
    if (_inFlight || !current.hasMore || current.loadingFirst) return;
    await _loadPage(append: true);
  }

  Future<void> _loadPage({required bool append}) async {
    if (_inFlight) return;
    _inFlight = true;

    if (append) {
      state.set(state.peek().copyWith(loadingMore: true));
    }

    try {
      final spec = buildSpec();
      final outcome = await _repository.search(
        query: spec.query,
        colors: spec.colors,
        categories: spec.categories,
        filter: spec.filter,
        page: append ? _pagesRequested + 1 : 1,
        seed: append ? _seed : null,
      );
      _seed = outcome.page.meta.seed ?? _seed;
      _pagesRequested = outcome.page.currentPage;

      // Dedup via Wallpaper equatable (author/size/dimension/url) stored
      // in a Set signal. Covers cross-page repeats and intra-page dupes
      // in one pass; Set preserves insertion order for the grid.
      final seen = Set<Wallpaper>.from(state.value.items);
      final fresh = <Wallpaper>{
        for (final item in outcome.page.items)
          if (seen.add(item)) item,
      };
      final merged = append ? {...state.value.items, ...fresh} : fresh;

      state.set(
        FeedState(
          items: merged,
          hasMore:
              outcome.page.hasNextPage &&
              outcome.page.currentPage < outcome.page.lastPage,
        ),
      );
    } on WallhavenUserException catch (error) {
      if (append) {
        // Keep everything already on screen; surface a retry footer.
        state.set(
          state.peek().copyWith(
            loadingMore: false,
            paginationError: error.message,
          ),
        );
      } else {
        state.set(FeedState(error: error.message));
      }
    } finally {
      _inFlight = false;
    }
  }

  /// Retries a failed load-more without touching loaded pages.
  Future<void> retryPagination() async {
    if (_inFlight || !state.value.hasMore) return;
    await _loadPage(append: true);
  }
}

/// Everything [WallpaperRepository.search] needs, resolved at call time so
/// preference changes (purity, portrait-only) always apply to new requests.
final class SearchRequestSpec {
  final String query;
  final Set<WallhavenColor> colors;
  final List<WallhavenCategory> categories;
  final FeedFilter filter;

  const SearchRequestSpec({
    this.query = '',
    this.colors = const {},
    this.categories = const [],
    this.filter = const FeedFilter(),
  });
}
