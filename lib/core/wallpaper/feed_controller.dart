import 'dart:async';

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
/// Items are deduplicated by wallpaper ID and exposed as a [List] for the
/// UI in the order the server sent them. The set is in-memory only and not
/// persisted.
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
/// Collection explore).
///
/// Owns:
/// - reactive [state] consumed by the shared grid widget,
/// - request guarding (never two pages in flight),
/// - duplicate suppression across appended pages,
/// - random-sort seed propagation between pages,
/// - retry semantics that never discard loaded content,
/// - restarting when the content policy (purity, blocked tags, API key)
///   changes, so a live feed can never keep serving items under the policy
///   that was in force when it loaded.
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

  /// Bumped by [reload]; responses from superseded generations are
  /// discarded so a slow older request can never corrupt fresh state.
  int _generation = 0;

  /// Set by [dispose]; guards signal writes from in-flight requests.
  bool _disposed = false;

  /// Last [WallpaperRepository.policyRevision] this feed has loaded under.
  int _policyRevision = 0;

  /// Watches policy changes for the lifetime of this controller.
  late final EffectCleanup _policyWatch;

  FeedController(this._repository) {
    _policyRevision = _repository.policyRevision.value;
    _policyWatch = effect(() {
      final revision = _repository.policyRevision.value;
      untracked(() {
        if (revision == _policyRevision || _disposed) return;
        _policyRevision = revision;
        onPolicyChanged();
      });
    });
  }

  /// Describes the next request from current controller inputs.
  SearchRequestSpec buildSpec();

  /// Reacts to a content-policy change.
  ///
  /// The default restarts the feed, which is what a visible feed needs: the
  /// old page was fetched under the old policy. Controllers whose surface can
  /// sit empty (Search) override this to drop results without spending a
  /// request on a query the user is not running.
  void onPolicyChanged() {
    unawaited(reload());
  }

  /// Releases reactive resources; safe to call more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _policyWatch();
    state.dispose();
  }

  /// Starts (or restarts) the feed from page 1.
  Future<void> reload() async {
    if (_disposed) return;
    final generation = _beginGeneration();
    state.set(const FeedState.initialLoading());
    await _loadPage(append: false, generation: generation);
  }

  /// Drops every loaded page and any response still in flight, without
  /// fetching anything.
  ///
  /// Used when the inputs no longer describe a request at all — a pristine
  /// search, for instance: keeping the old pages would leave tiles no current
  /// input justifies, and a response that lands later could repopulate them.
  ///
  /// The state is marked exhausted so a scroll notification can never turn the
  /// emptiness into an implicit page-1 fetch; [reload] starts a real feed
  /// again. Bumping the generation is what makes this different from merely
  /// clearing [state]: a superseded response can no longer publish items, an
  /// error, or a loading flag.
  void reset() {
    if (_disposed) return;
    _beginGeneration();
    state.set(const FeedState(hasMore: false));
  }

  /// Invalidates in-flight work (first load or pagination), rewinds pagination
  /// and returns the new generation. Only requests started afterwards may
  /// publish state.
  int _beginGeneration() {
    _generation++;
    _inFlight = false;
    _seed = null;
    _pagesRequested = 0;
    return _generation;
  }

  /// Loads the next page when available; no-op while busy or exhausted.
  Future<void> loadMore() async {
    if (_disposed) return;
    final current = state.value;
    if (_inFlight || !current.hasMore || current.loadingFirst) return;
    await _loadPage(append: true, generation: _generation);
  }

  Future<void> _loadPage({
    required bool append,
    required int generation,
  }) async {
    if (_inFlight || _disposed) return;
    _inFlight = true;
    // True when this is still the newest operation at completion time.
    bool isCurrent() => !_disposed && generation == _generation;

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
      if (!isCurrent()) return; // superseded by reload/dispose — drop result
      _seed = outcome.page.meta.seed ?? _seed;
      _pagesRequested = outcome.page.currentPage;

      // Dedupe by wallpaper ID, never by domain equality: equality also
      // compares mutable metadata (resolution, path, size), so a re-sent
      // wallpaper with updated metadata would slip through as a second tile
      // with a duplicate grid key and Hero tag. Insertion order is kept so
      // existing tiles never reshuffle.
      final seen = <String>{for (final item in state.value.items) item.id};
      final merged = <Wallpaper>[
        if (append) ...state.value.items,
      ];
      for (final item in outcome.page.items) {
        if (seen.add(item.id)) merged.add(item);
      }

      state.set(
        FeedState(
          // LinkedHashSet keeps the order above; IDs are already unique.
          items: merged.toSet(),
          hasMore:
              outcome.page.hasNextPage &&
              outcome.page.currentPage < outcome.page.lastPage,
        ),
      );
    } on WallhavenUserException catch (error) {
      _fail(error.message, append: append, isCurrent: isCurrent);
    } catch (_) {
      // Untyped failures are bugs (a decode or platform surprise), but the
      // user must still get an actionable retry instead of a skeleton that
      // never resolves: this catch owns leaving [loadingFirst]/[loadingMore].
      _fail(_unexpectedMessage, append: append, isCurrent: isCurrent);
    } finally {
      // Only the live generation owns the guard. A superseded request that
      // finishes late must not free it, or a second page could start while
      // the current request is still running.
      if (generation == _generation) _inFlight = false;
    }
  }

  /// Retries a failed load-more without touching loaded pages.
  Future<void> retryPagination() async {
    if (_disposed) return;
    if (_inFlight || !state.value.hasMore) return;
    await _loadPage(append: true, generation: _generation);
  }

  static const _unexpectedMessage =
      'Something went wrong loading wallpapers. Please try again.';

  /// Publishes a failure without discarding content that is already usable.
  void _fail(
    String message, {
    required bool append,
    required bool Function() isCurrent,
  }) {
    if (!isCurrent()) return; // superseded — do not surface stale errors
    if (append) {
      // Keep everything already on screen; surface a retry footer.
      state.set(
        state.peek().copyWith(
          loadingMore: false,
          paginationError: message,
        ),
      );
    } else {
      state.set(FeedState(error: message));
    }
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
