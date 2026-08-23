import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../core/collections/collection_entry.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/collection_explore_controller.dart';
import '../application/collections_controller.dart';

/// Wallhaven search screen scoped to one [CollectionEntry].
final class CollectionExploreScreen extends StatelessWidget {
  final String collectionId;
  final ValueChanged<Wallpaper> onOpenWallpaper;

  const CollectionExploreScreen({
    super.key,
    required this.collectionId,
    required this.onOpenWallpaper,
  });

  @override
  Widget build(BuildContext context) {
    final collCtrl = locator<CollectionsController>();
    CollectionEntry? entry;
    try {
      entry = collCtrl.entries.value.firstWhere((e) => e.id == collectionId);
    } catch (_) {
      entry = null;
    }

    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: const EmptyState(
          iconData: Icons.search_off,
          title: 'Collection not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    final controller = locator<CollectionExploreController>(param1: entry);
    final favorites = locator<FavoritesController>();

    return Scaffold(
      appBar: AppBar(title: Text(entry.displayName)),
      body: SignalBuilder(
        builder: (context) {
          final state = controller.state.value;
          return WallpaperGrid(
            items: state.items.toList(growable: false),
            isLoadingFirst: state.loadingFirst,
            isLoadingMore: state.loadingMore,
            hasMore: state.hasMore,
            error: state.error,
            paginationError: state.paginationError,
            heroScope: 'collection-${entry!.id}-',
            onRetry: controller.reload,
            onRetryPagination: controller.retryPagination,
            onLoadMore: controller.loadMore,
            favoriteIds: favorites.favoriteIds,
            onToggleFavorite: favorites.toggle,
            emptyState: EmptyState(
              title: 'Nothing here yet',
              message: 'No wallpapers matched ${entry.name}.',
            ),
            onOpen: onOpenWallpaper,
          );
        },
      ),
    );
  }
}
