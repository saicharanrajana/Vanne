import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../core/domain/favorite_wallpaper.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../application/favorites_controller.dart';

/// Locally-persisted favorites rendered through the shared staggered grid.
///
/// Favorites are persisted via [FavoritesRepository] (Hive box `favorites`)
/// — JSON-encoded snapshots keyed by wallpaper ID, opened at `bootstrap()`
/// and surviving app restarts. Snapshots carry enough metadata that
/// favorites render even if the wallpaper is deleted remotely.
///
/// Layout is full slivers like Discover: a floating [SliverAppBar] header
/// plus the masonry grid slivers, so scrolling hides the header.
final class FavoritesScreen extends StatelessWidget {
  final ValueChanged<Wallpaper> onOpenWallpaper;

  const FavoritesScreen({super.key, required this.onOpenWallpaper});

  @override
  Widget build(BuildContext context) {
    final controller = locator<FavoritesController>();
    final theme = Theme.of(context);

    final headerSliver = SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      automaticallyImplyLeading: false,
      backgroundColor: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 0,
      collapsedHeight: 0,
      expandedHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        background: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text('Favorites', style: theme.textTheme.displaySmall),
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: SignalBuilder(
        builder: (context) {
          final items = controller.items.map(_asWallpaper).toList();
          final grid = WallpaperGrid(
            items: items,
            hasMore: false,
            favoriteIds: controller.favoriteIds,
            onToggleFavorite: controller.toggle,
            heroScope: 'favorites-',
            emptyState: const EmptyState(
              iconData: Icons.favorite,
              title: 'No favorites yet',
              message: 'Save wallpapers you love and they’ll appear here.',
            ),
            onOpen: onOpenWallpaper,
          );
          // Use NotificationListener for consistency, though hasMore false
          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              grid.maybeTriggerLoadMore(notification);
              return false;
            },
            child: CustomScrollView(
              slivers: [
                headerSliver,
                ...grid.buildSlivers(context),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Adapts the persisted snapshot back into the domain model the grid
  /// consumes. Listing-only fields (views, colors) are not displayed by
  /// tiles and default harmlessly.
  static Wallpaper _asWallpaper(FavoriteWallpaper favorite) => Wallpaper(
    id: favorite.id,
    url: favorite.pageUrl,
    source: '',
    purity: Purity.sfw,
    category: Category.general,
    width: favorite.width,
    height: favorite.height,
    resolution: favorite.resolution,
    ratio: favorite.ratio,
    fileSizeBytes: favorite.fileSizeBytes,
    fileType: favorite.fileType,
    createdAt: favorite.createdAt,
    colors: const [],
    views: 0,
    favorites: 0,
    path: favorite.imageUrl,
    thumbnails: Thumbnails(small: favorite.thumbnailUrl),
  );
}
