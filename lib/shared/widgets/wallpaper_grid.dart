import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../app/theme/app_shapes.dart';
import 'bottom_padding.dart';
import 'wallpaper_tile.dart';

/// Reusable staggered wallpaper grid shared by Discover, Search, Category
/// exploration and Favorites.
///
/// Knows nothing about where wallpapers come from: callers supply domain
/// objects plus lifecycle flags, and the grid renders the matching state —
///
/// * [isLoadingFirst] → tonal skeleton tiles,
/// * [error] non-null → full-area error with retry,
/// * [items] empty otherwise → [emptyState],
/// * [isLoadingMore]/[paginationError]/[hasMore] → footer states.
///
/// Infinite pagination fires [onLoadMore] when the user scrolls within
/// [loadMoreThreshold] pixels of the end.
final class WallpaperGrid extends StatelessWidget {
  final List<Wallpaper> items;

  final bool isLoadingFirst;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final String? paginationError;

  final VoidCallback? onRetry;
  final VoidCallback? onRetryPagination;
  final VoidCallback? onLoadMore;
  final ValueChanged<Wallpaper> onOpen;

  /// Reactive favorite IDs shared by every tile.
  final ReadonlySignal<Set<String>>? favoriteIds;
  final void Function(Wallpaper wallpaper)? onToggleFavorite;

  /// Shown when the feed legitimately has no content.
  final Widget? emptyState;

  final ScrollController? scrollController;
  final EdgeInsets padding;
  final double loadMoreThreshold;

  /// Namespace for tile Hero tags so two lists showing the same wallpaper
  /// never collide. Must match the detail screen's [heroScope].
  final String heroScope;

  const WallpaperGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.isLoadingFirst = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.paginationError,
    this.onRetry,
    this.onRetryPagination,
    this.onLoadMore,
    this.favoriteIds,
    this.onToggleFavorite,
    this.emptyState,
    this.scrollController,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.loadMoreThreshold = 600,
    this.heroScope = '',
  });

  /// Fires [onLoadMore] when the notification reports the viewport is
  /// within [loadMoreThreshold] of the end. Exposed so custom scroll-view
  /// hosts (e.g. Discover's collapsing header) share the trigger logic.
  void maybeTriggerLoadMore(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.metrics.extentAfter < loadMoreThreshold) {
      onLoadMore?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        maybeTriggerLoadMore(notification);
        return false;
      },
      child: CustomScrollView(
        controller: scrollController,
        slivers: buildSlivers(context),
      ),
    );
  }

  /// The feed as sliver pieces: state views fill the viewport; loaded
  /// content is one masonry sliver plus the pagination footer. Hosts may
  /// embed these in their own [CustomScrollView].
  List<Widget> buildSlivers(BuildContext context) {
    if (isLoadingFirst) return [_SkeletonSliver(padding: padding)];
    if (error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: FeedErrorView(message: error!, onRetry: onRetry),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child:
              emptyState ??
              const EmptyState(
                title: 'No wallpapers found',
                message: 'Try another search or remove a filter.',
              ),
        ),
      ];
    }

    final exhausted = !hasMore && !isLoadingMore && paginationError == null;
    // Tiles render the ORIGINAL image uncropped; decode it at cell
    // resolution so a full-res photo costs cell-sized RAM.
    final columns = _columnsFor(context).toDouble();
    final cellLogicalWidth =
        (MediaQuery.sizeOf(context).width -
            padding.horizontal -
            (columns - 1) * 10) /
        columns;
    final cacheWidth =
        (cellLogicalWidth * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(240, 1440);
    return [
      SliverPadding(
        padding: padding,
        sliver: SliverMasonryGrid.count(
          crossAxisCount: _columnsFor(context),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childCount: items.length,
          itemBuilder: (context, index) {
            final wallpaper = items[index];
            return WallpaperTile(
              key: ValueKey('wallpaper-tile-${wallpaper.id}'),
              wallpaper: wallpaper,
              favoriteIds: favoriteIds,
              memCacheWidth: cacheWidth,
              heroScope: heroScope,
              onOpen: () => onOpen(wallpaper),
              onToggleFavorite: onToggleFavorite == null
                  ? null
                  : () => onToggleFavorite!(wallpaper),
            );
          },
        ),
      ),
      SliverToBoxAdapter(
        child: _GridFooter(
          isLoadingMore: isLoadingMore,
          paginationError: paginationError,
          exhausted: exhausted,
          onRetryPagination: onRetryPagination,
        ),
      ),
      // Breathing room for the system gesture/nav bar — does not shrink
      // the viewport, content scrolls underneath.
      const SliverToBoxAdapter(child: BottomPadding()),
    ];
  }

  int _columnsFor(BuildContext context) {
    // Two columns on typical phones; grows with available width.
    final width = MediaQuery.sizeOf(context).width;
    return (width / 190).floor().clamp(2, 5);
  }
}

final class _GridFooter extends StatelessWidget {
  final bool isLoadingMore;
  final String? paginationError;
  final bool exhausted;
  final VoidCallback? onRetryPagination;

  const _GridFooter({
    required this.isLoadingMore,
    required this.paginationError,
    required this.exhausted,
    required this.onRetryPagination,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (paginationError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(
              'Unable to load more',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            M3EButton(
              style: M3EButtonStyle.tonal,
              onPressed: onRetryPagination,
              size: M3EButtonSize.sm,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (exhausted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            "You've reached the end",
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox.square(
          dimension: 36,
          child: M3ELoadingIndicator(
            size: 60,
            semanticLabel: 'Loading more wallpapers',
          ),
        ),
      ),
    );
  }
}

/// First-load skeleton: tonal masonry placeholders in mixed heights so
/// the layout matches incoming content instead of a generic spinner.
final class _SkeletonSliver extends StatelessWidget {
  final EdgeInsets padding;

  const _SkeletonSliver({required this.padding});

  static const _ratios = [9 / 16.0, 9 / 18.0, 9 / 14.0, 9 / 17.0, 9 / 15.0];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SliverPadding(
      padding: padding,
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childCount: 12,
        itemBuilder: (context, index) => AspectRatio(
          aspectRatio: _ratios[index % _ratios.length],
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-area error state for first-load failures.
final class FeedErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const FeedErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            M3EShapeContainer.cookie9Sided(
              width: 72,
              height: 72,
              color: theme.colorScheme.errorContainer,
              child: Icon(
                PhosphorIconsFill.wifiSlash,
                size: 30,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text('Something went wrong', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            M3EButton(
              style: M3EButtonStyle.filled,
              onPressed: onRetry,
              size: M3EButtonSize.md,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Intentional empty state used by feeds and favorites.
final class EmptyState extends StatelessWidget {
  final IconData? iconData;
  final String title;
  final String message;

  const EmptyState({
    super.key,
    this.iconData,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            M3EShapeContainer.clover4Leaf(
              width: 72,
              height: 72,
              color: theme.colorScheme.surfaceContainerHigh,
              child: Icon(
                iconData ?? PhosphorIconsFill.image,
                size: 30,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
