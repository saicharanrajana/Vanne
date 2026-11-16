import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/collections/collection_entry.dart';
import '../../../core/domain/feed_filter.dart';
import '../../../core/wallpaper/feed_controller.dart';
import '../../../shared/utils/color_display.dart';
import '../../../shared/utils/wallhaven_color_utils.dart';

/// Owns one collection’s exploration feed. Created per navigation.
final class CollectionExploreController extends FeedController {
  final CollectionEntry entry;

  /// Called once with the cover a successful load can supply.
  ///
  /// [coverUrl] is the first wallpaper's thumbnail when the collection has no
  /// cover yet, or the stored cover when the visit happens to see it again —
  /// which is how a legacy cover gains the palette saved before palettes
  /// existed. [coverColors] describes exactly that wallpaper. Errors and empty
  /// results leave the metadata open for a later retry.
  final void Function(String coverUrl, List<String> coverColors)?
  onCoverAvailable;

  bool _coverCaptured = false;
  bool _disposed = false;

  /// Session-only filter seeded from the persisted entry. Not written back.
  // TODO(settings-persist-filter): Make filter persistence configurable via
  // Settings. Currently session-only (signal local, not persisted). If a
  // global toggle is added it should apply to all locations (Discover,
  // Search, Collections/Filtered).
  late final filter = signal(entry.filter);

  CollectionExploreController(
    this.entry,
    super.repository, {
    this.onCoverAvailable,
  }) {
    reload();
  }

  @override
  Future<void> reload() async {
    await super.reload();
    if (_disposed || _coverCaptured) return;
    final pending = entry.coverUrl == null || entry.coverColors.isEmpty;
    if (!pending) return;
    final items = state.peek().items;
    if (items.isEmpty) return;

    // A missing cover takes the first result; an existing cover is only
    // revisited so its missing palette can be attached to the same image.
    final wanted = entry.coverUrl;
    Wallpaper? match;
    for (final wallpaper in items) {
      if (wanted == null) {
        match = wallpaper;
        break;
      }
      final thumbs = wallpaper.thumbnails;
      if (wanted == thumbs.large ||
          wanted == thumbs.original ||
          wanted == thumbs.small) {
        match = wallpaper;
        break;
      }
    }
    if (match == null) return;

    final thumbs = match.thumbnails;
    // A matched legacy cover keeps its exact URL/size. Only a new cover uses
    // the preferred thumbnail size from the first result.
    final coverUrl = wanted ?? thumbs.large ?? thumbs.original ?? thumbs.small;
    if (coverUrl == null || coverUrl.isEmpty) return;
    _coverCaptured = true;
    onCoverAvailable?.call(
      coverUrl,
      ColorDisplay.normalizedPalette(match.colors),
    );
  }

  Future<void> applyFilter(FeedFilter newFilter) async {
    if (newFilter == filter.value) return;
    filter.value = newFilter;
    // TODO(settings-persist-filter): branch on settings toggle to persist
    // to CollectionEntry/repo if enabled.
    await reload();
  }

  @override
  SearchRequestSpec buildSpec() => SearchRequestSpec(
    query: entry.query,
    categories: entry.kinds,
    filter: filter.value,
    colors: {
      for (final hex in entry.colors)
        if (wallhavenColorForHex(hex) case final WallhavenColor c) c,
    },
  );

  @override
  void dispose() {
    _disposed = true;
    filter.dispose();
    super.dispose();
  }
}
