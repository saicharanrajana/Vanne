import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../core/collections/collection_entry.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/collection_explore_controller.dart';
import '../application/collections_controller.dart';

/// Wallhaven search screen scoped to one [CollectionEntry].
///
/// Stateful so its [CollectionExploreController] is created exactly once
/// per navigation — resolving it in `build` would spawn a fresh controller
/// (and a fresh page-1 request) on every rebuild.
final class CollectionExploreScreen extends StatefulWidget {
  final String collectionId;
  final ValueChanged<Wallpaper> onOpenWallpaper;

  const CollectionExploreScreen({
    super.key,
    required this.collectionId,
    required this.onOpenWallpaper,
  });

  @override
  State<CollectionExploreScreen> createState() =>
      _CollectionExploreScreenState();
}

final class _CollectionExploreScreenState
    extends State<CollectionExploreScreen> {
  /// Null when the collection was deleted before this screen opened.
  CollectionExploreController? _controller;
  CollectionEntry? _entry;

  @override
  void initState() {
    super.initState();
    final entry = locator<CollectionsController>().entries.value
        .where((e) => e.id == widget.collectionId)
        .firstOrNull;
    if (entry != null) {
      _entry = entry;
      _controller = locator<CollectionExploreController>(param1: entry);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final entry = _entry;
    if (controller == null || entry == null) {
      return Scaffold(
        appBar: const M3EAppBar.top(
          titleText: 'Not found',
          automaticallyImplyLeading: true,
        ),
        body: const EmptyState(
          iconData: PhosphorIconsFill.magnifyingGlass,
          title: 'Collection not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    final favorites = locator<FavoritesController>();

    return Scaffold(
      appBar: M3EAppBar.top(
        titleText: entry.displayName,
        automaticallyImplyLeading: true,
      ),
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
            heroScope: 'collection-${entry.id}-',
            onRetry: controller.reload,
            onRetryPagination: controller.retryPagination,
            onLoadMore: controller.loadMore,
            favoriteIds: favorites.favoriteIds,
            onToggleFavorite: favorites.toggle,
            emptyState: EmptyState(
              title: 'Nothing here yet',
              message: 'No wallpapers matched ${entry.name}.',
            ),
            onOpen: widget.onOpenWallpaper,
          );
        },
      ),
    );
  }
}
