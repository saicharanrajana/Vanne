import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/collections/collection_entry.dart';
import '../../../core/domain/feed_filter.dart';
import '../../../core/wallpaper/feed_controller.dart';
import '../../../shared/utils/wallhaven_color_utils.dart';

/// Owns one collection’s exploration feed. Created per navigation.
final class CollectionExploreController extends FeedController {
  final CollectionEntry entry;

  /// Called once with the first wallpaper of a successful load so the
  /// collection can snapshot a missing cover. Errors and empty results leave
  /// the cover open for a later retry or filter change.
  final void Function(String coverUrl)? onCoverAvailable;

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
    final items = state.peek().items;
    if (items.isEmpty) return;
    final thumbnails = items.first.thumbnails;
    final coverUrl =
        thumbnails.large ?? thumbnails.original ?? thumbnails.small;
    if (coverUrl == null || coverUrl.isEmpty) return;
    _coverCaptured = true;
    onCoverAvailable?.call(coverUrl);
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
