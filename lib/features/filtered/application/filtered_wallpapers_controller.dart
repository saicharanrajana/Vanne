import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/domain/feed_filter.dart';
import '../../../core/wallpaper/feed_controller.dart';
import '../../../core/wallpaper/wallpaper_repository.dart';
import '../../../shared/utils/wallhaven_color_utils.dart';

/// Ephemeral wallpapers feed for a tapped tag or color from wallpaper details.
///
/// Not persisted — offers a collection toggle to save the query as a
/// [CollectionEntry]. Supports sort & filter like Discover.
final class FilteredWallpapersController extends FeedController {
  final String title;
  final String query;
  final List<String> colorHexes;

  /// Session-only filter.
  // TODO(settings-persist-filter): Make filter persistence configurable via
  // Settings. Currently session-only (signal local, not persisted). If a
  // global toggle is added it should apply to all locations (Discover,
  // Search, Collections/Filtered).
  final filter = signal(const FeedFilter());

  FilteredWallpapersController({
    required this.title,
    required this.query,
    this.colorHexes = const [],
    FeedFilter initialFilter = const FeedFilter(),
    required WallpaperRepository repository,
  }) : super(repository) {
    filter.value = initialFilter;
    reload();
  }

  Future<void> applyFilter(FeedFilter newFilter) async {
    if (newFilter == filter.value) return;
    filter.value = newFilter;
    // TODO(settings-persist-filter): branch on settings toggle to persist
    // globally if enabled.
    await reload();
  }

  @override
  SearchRequestSpec buildSpec() => SearchRequestSpec(
        query: query,
        colors: {
          for (final hex in colorHexes)
            if (wallhavenColorForHex(hex) case final WallhavenColor c) c,
        },
        filter: filter.value,
      );

  @override
  void dispose() {
    filter.dispose();
    super.dispose();
  }
}
