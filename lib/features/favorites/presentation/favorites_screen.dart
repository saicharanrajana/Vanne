import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../app/router/tab_scroll_coordinator.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../application/favorites_controller.dart';

/// Locally-persisted favorites rendered through the shared staggered grid.
///
/// Favorites are persisted via [FavoritesRepository] (Hive box `favorites`)
/// — JSON-encoded snapshots keyed by wallpaper ID, opened at `bootstrap()`
/// and surviving app restarts. Snapshots carry enough metadata that
/// favorites render even if the wallpaper is deleted remotely.
///
/// Layout is full slivers: a floating [SliverAppBar] header plus the masonry
/// grid slivers, so scrolling hides the header. The header is static; only
/// the grid slivers subscribe to the favorites signal. The feed is finite
/// (`hasMore: false`), so there is no scroll listener or load-more wiring.
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
          // The feed is finite (hasMore: false): no scroll listener or
          // load-more wiring needed.
          final grid = WallpaperGrid(
            items: controller.wallpapers.value,
            hasMore: false,
            favoriteIds: controller.favoriteIds,
            onToggleFavorite: controller.toggle,
            heroScope: 'favorites-',
            emptyState: const EmptyState(
              iconData: PhosphorIconsFill.heart,
              title: 'No favorites yet',
              message: 'Save wallpapers you love and they’ll appear here.',
            ),
            onOpen: onOpenWallpaper,
          );
          return CustomScrollView(
            controller: locator<TabScrollCoordinator>().favorites,
            slivers: [headerSliver, ...grid.buildSlivers(context)],
          );
        },
      ),
    );
  }
}
