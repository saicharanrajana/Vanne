import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/domain/app_category.dart';

import '../../../app/dependencies.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/category_explore_controller.dart';

/// Wallhaven search screen scoped to one [AppCategory] — reuses the same
/// grid/pagination architecture as Discover.
final class CategoryExploreScreen extends StatelessWidget {
  final AppCategory category;
  final ValueChanged<Wallpaper> onOpenWallpaper;

  const CategoryExploreScreen({
    super.key,
    required this.category,
    required this.onOpenWallpaper,
  });

  @override
  Widget build(BuildContext context) {
    final controller = locator<CategoryExploreController>(param1: category);
    final favorites = locator<FavoritesController>();
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
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
            heroScope: 'category-${category.id}-',
            onRetry: controller.reload,
            onRetryPagination: controller.retryPagination,
            onLoadMore: controller.loadMore,
            favoriteIds: favorites.favoriteIds,
            onToggleFavorite: favorites.toggle,
            emptyState: EmptyState(
              title: 'Nothing here yet',
              message: 'No wallpapers matched ${category.title}.',
            ),
            onOpen: onOpenWallpaper,
          );
        },
      ),
    );
  }
}
