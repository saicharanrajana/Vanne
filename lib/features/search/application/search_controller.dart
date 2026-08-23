import 'dart:async';

import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/domain/feed_filter.dart';
import '../../../core/wallpaper/feed_controller.dart';

/// Owns the dedicated Search experience: typed query + color and genre
/// chips, submitted explicitly (never per keystroke).
///
/// Reload triggers (submit key, chip taps) pass through one trailing
/// [Timer]-based debounce so rapid inputs collapse into a single network
/// request — only the latest committed state is fetched.
final class SearchController extends FeedController {
  SearchController(super.repository);

  /// Live text-field content — mirrors typing only; never triggers I/O.
  final queryText = signal('');

  /// Query actually committed by the user (submit key or chip change).
  final _committedQuery = signal('');

  /// Selected dominant-color filters.
  final selectedColors = signal(const <FeedColor>{});

  /// Selected genre chips.
  final selectedGenres = signal(const <FeedGenre>{});

  /// Trailing-edge debounce timer; null when no request is pending.
  Timer? _debounce;

  /// Whether any input has been committed at least once. Until then the
  /// screen shows its pristine empty state instead of generic feed data.
  late final hasCommittedInput = computed(
    () =>
        _committedQuery.value.isNotEmpty ||
        selectedColors.value.isNotEmpty ||
        selectedGenres.value.isNotEmpty,
  );

  @override
  SearchRequestSpec buildSpec() {
    // Genre chips append fuzzy terms to the typed query, mirroring how
    // power users compose Wallhaven searches (`nature minimalist`).
    final genreTerms = selectedGenres.value
        .map((genre) => genre.searchTerm)
        .where((term) => term.isNotEmpty)
        .join(' ');
    final query = [
      _committedQuery.value,
      if (genreTerms.isNotEmpty) genreTerms,
    ].where((part) => part.isNotEmpty).join(' ');

    return SearchRequestSpec(
      query: query,
      colors: {
        for (final color in selectedColors.value)
          WallhavenColor.values.firstWhere((wire) => wire.hex == color.hex),
      },
      // Newest fits chip-driven browsing; a committed query naturally
      // ranks server-side.
      filter: const FeedFilter(),
    );
  }

  /// Commits the current text and restarts pagination (debounced).
  Future<void> submit() async {
    _committedQuery.set(queryText.value.trim());
    await _debouncedReload();
  }

  /// Toggles a color chip; single-select: tapping a color selects it
  /// exclusively (replacing any previous), tapping the same again clears.
  /// Filter changes re-run the search (debounced).
  Future<void> toggleColor(FeedColor color) async {
    final current = selectedColors.peek();
    if (current.contains(color)) {
      selectedColors.set(const {});
    } else {
      selectedColors.set({color});
    }
    await _debouncedReload();
  }

  /// Toggles a genre chip; single-select: same semantics as [toggleColor].
  Future<void> toggleGenre(FeedGenre genre) async {
    final current = selectedGenres.peek();
    if (current.contains(genre)) {
      selectedGenres.set(const {});
    } else {
      selectedGenres.set({genre});
    }
    await _debouncedReload();
  }


  /// Clears every input back to a pristine search state (debounced).
  Future<void> clearAll() async {
    queryText.set('');
    _committedQuery.set('');
    selectedColors.set(const {});
    selectedGenres.set(const {});
    await _debouncedReload();
  }

  /// Collapses bursts of reload triggers into one network call: each new
  /// trigger cancels the pending timer and restarts the window; only the
  /// trailing edge fetches.
  Future<void> _debouncedReload([
    Duration delay = const Duration(milliseconds: 350),
  ]) {
    final done = Completer<void>();
    _debounce?.cancel();
    _debounce = Timer(delay, () async {
      try {
        await reload();
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  void dispose() => _debounce?.cancel();
}
