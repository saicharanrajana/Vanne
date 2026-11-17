import 'dart:async';

import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/collections/collection_entry.dart';
import '../../../core/domain/feed_filter.dart';
import '../../../core/wallpaper/feed_controller.dart';
import '../../../shared/utils/wallhaven_color_utils.dart';

/// Owns the dedicated Search experience: typed query plus colour and saved
/// collection filters, submitted explicitly (never per keystroke).
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

  /// Currently applied saved colour collection, or `null` for none.
  ///
  /// Occupies the same single-select slot as [selectedColors]: a saved colour
  /// stands for one colour filter, so picking it replaces a plain swatch and
  /// picking a swatch replaces it. The whole entry is kept so the row can
  /// match the selected card; [pruneMissingCollections] drops it as soon as
  /// its saved collection disappears.
  final selectedColorCollection = signal<CollectionEntry?>(null);

  /// Currently applied tag collection, or `null` for none.
  ///
  /// Single-select like the colour row. The whole entry is kept so the row can
  /// match the selected card; [pruneMissingCollections] drops it as soon as
  /// its saved collection disappears.
  final selectedTag = signal<CollectionEntry?>(null);

  /// Trailing-edge debounce timer; null when no request is pending.
  Timer? _debounce;

  /// Whether any input has been committed at least once. Until then the
  /// screen shows its pristine empty state instead of generic feed data.
  late final hasCommittedInput = computed(
    () =>
        _committedQuery.value.isNotEmpty ||
        selectedColors.value.isNotEmpty ||
        selectedColorCollection.value != null ||
        selectedTag.value != null,
  );

  /// Sort/filter for search results (session-only).
  // TODO(settings-persist-filter): Make filter persistence configurable via
  // Settings. Currently session-only (signal local, not persisted). If a
  // global toggle is added it should apply to all locations (Discover,
  // Search, Collections/Filtered).
  final filter = signal(const FeedFilter());

  Future<void> applyFilter(FeedFilter newFilter) async {
    if (newFilter == filter.value) return;
    filter.set(newFilter);
    // TODO(settings-persist-filter): branch on settings toggle to persist
    // globally if enabled.
    await reload();
  }

  @override
  SearchRequestSpec buildSpec() {
    // A saved tag collection contributes the tag it stands for, composed with
    // the typed query the same way genre terms used to be.
    final applied = selectedTag.value;
    final tagQuery = applied != null && applied.isTagCollection
        ? applied.query.trim()
        : '';
    final query = [
      _committedQuery.value,
      if (tagQuery.isNotEmpty) tagQuery,
    ].where((part) => part.isNotEmpty).join(' ');

    return SearchRequestSpec(
      query: query,
      colors: {
        for (final color in selectedColors.value)
          WallhavenColor.values.firstWhere((wire) => wire.hex == color.hex),
        // A saved colour collection keeps the exact RGB the user saved, which
        // is usually not one of Wallhaven's documented values. Each hex is
        // mapped to its nearest wire colour, exactly as the collection's own
        // browsing page does, so the filter stays the search that was saved.
        for (final hex
            in selectedColorCollection.value?.colors ?? const <String>[])
          if (wallhavenColorForHex(hex) case final WallhavenColor wire) wire,
      },
      filter: filter.value,
    );
  }

  /// Commits the current text and restarts pagination (debounced).
  void submit() {
    _committedQuery.set(queryText.value.trim());
    _debouncedReload();
  }

  /// Toggles a color chip; single-select: tapping a color selects it
  /// exclusively (replacing any previous, including a saved colour
  /// collection), tapping the same again clears.
  /// Filter changes re-run the search (debounced).
  void toggleColor(FeedColor color) {
    final current = selectedColors.peek();
    if (current.contains(color) && selectedColorCollection.peek() == null) {
      selectedColors.set(const {});
    } else {
      selectedColors.set({color});
      // One colour slot for the whole row: a swatch replaces a saved colour.
      selectedColorCollection.set(null);
    }
    _debouncedReload();
  }

  /// Toggles a saved colour collection; single-select like [toggleTag], and it
  /// shares [selectedColors]' slot: picking one replaces a plain swatch, and
  /// picking the selected card again clears the colour filter.
  /// Filter changes re-run the search (debounced).
  void toggleColorCollection(CollectionEntry entry) {
    final current = selectedColorCollection.peek();
    if (current?.id == entry.id) {
      selectedColorCollection.set(null);
    } else {
      selectedColorCollection.set(entry);
      selectedColors.set(const {});
    }
    _debouncedReload();
  }

  /// Toggles a tag collection; single-select: tapping a different card
  /// replaces the applied tag, tapping the selected card clears it.
  /// Filter changes re-run the search (debounced).
  void toggleTag(CollectionEntry entry) {
    final current = selectedTag.peek();
    if (current?.id == entry.id) {
      selectedTag.set(null);
    } else {
      selectedTag.set(entry);
    }
    _debouncedReload();
  }

  /// Drops an applied collection whose saved row no longer exists.
  ///
  /// Called with the ids currently saved, so a filter can never outlive its
  /// card: leaving it set would keep changing the results while the row has
  /// nothing to show or clear. Colour and tag selections are pruned alike.
  /// The refresh is immediate rather than debounced because losing a
  /// collection is a single event, not a burst of input. Results reload only
  /// while another input (typed query or colour) still makes the search
  /// non-empty; otherwise the screen returns to its pristine state without
  /// fetching the generic feed.
  void pruneMissingCollections(Iterable<String> savedIds) {
    final ids = savedIds.toSet();
    var changed = false;

    final tag = selectedTag.peek();
    if (tag != null && !ids.contains(tag.id)) {
      selectedTag.set(null);
      changed = true;
    }

    final color = selectedColorCollection.peek();
    if (color != null && !ids.contains(color.id)) {
      selectedColorCollection.set(null);
      changed = true;
    }

    if (!changed) return;
    if (_committedQuery.peek().isNotEmpty ||
        selectedColors.peek().isNotEmpty ||
        selectedColorCollection.peek() != null) {
      unawaited(reload());
    }
  }

  /// Clears every input back to a pristine search state (debounced).
  void clearAll() {
    queryText.set('');
    _committedQuery.set('');
    selectedColors.set(const {});
    selectedColorCollection.set(null);
    selectedTag.set(null);
    _debouncedReload();
  }

  /// Collapses bursts of reload triggers into one network call: each new
  /// trigger cancels the pending timer and restarts the window; only the
  /// trailing edge fetches. Returns immediately; no value is exposed —
  /// callers observe progress via the feed [state].
  void _debouncedReload([Duration delay = const Duration(milliseconds: 350)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, reload);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    queryText.dispose();
    _committedQuery.dispose();
    selectedColors.dispose();
    selectedColorCollection.dispose();
    selectedTag.dispose();
    hasCommittedInput.dispose();
    filter.dispose();
    super.dispose();
  }
}
