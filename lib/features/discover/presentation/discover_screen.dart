import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/discover_controller.dart';
import 'widgets/discover_filter_sheet.dart';

const _searchHeroTag = 'search-bar-hero';

/// The primary screen: large heading, prominent (tappable) search bar,
/// feed-filter trigger and the infinite staggered wallpaper feed — all as
/// proper slivers. Header lives inside SliverAppBar so floating/snap and
/// Material LookupBoundary are handled by the framework.
final class DiscoverScreen extends StatefulWidget {
  final VoidCallback onOpenSearch;
  final ValueChanged<Wallpaper> onOpenWallpaper;

  const DiscoverScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenWallpaper,
  });

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

final class _DiscoverScreenState extends State<DiscoverScreen> {
  late final DiscoverController controller = locator<DiscoverController>();
  late final FavoritesController favorites = locator<FavoritesController>();

  @override
  Widget build(BuildContext context) {
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
      expandedHeight: 200,
      flexibleSpace: FlexibleSpaceBar(
        background: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Discover', style: theme.textTheme.displaySmall),
                const SizedBox(height: 12),
                Hero(
                  tag: _searchHeroTag,
                  flightShuttleBuilder:
                      (
                        flightContext,
                        animation,
                        direction,
                        fromHeroContext,
                        toHeroContext,
                      ) {
                        final hero = direction == HeroFlightDirection.push
                            ? toHeroContext.widget as Hero
                            : fromHeroContext.widget as Hero;
                        return Material(
                          color: Colors.transparent,
                          child: hero.child,
                        );
                      },
                  placeholderBuilder: (context, size, child) =>
                      SizedBox.fromSize(size: size, child: child),
                  child: SearchBar(
                    hintText: 'Search wallpapers',
                    padding: const WidgetStatePropertyAll(
                      EdgeInsetsDirectional.symmetric(horizontal: 16),
                    ),
                    readOnly: true,
                    onTap: widget.onOpenSearch,
                    leading: Icon(
                      Icons.search,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _FilterRow(controller: controller),
              ],
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: SignalBuilder(
        builder: (context) {
          final state = controller.state.value;
          final grid = WallpaperGrid(
            items: state.items.toList(growable: false),
            isLoadingFirst: state.loadingFirst,
            isLoadingMore: state.loadingMore,
            hasMore: state.hasMore,
            error: state.error,
            paginationError: state.paginationError,
            onRetry: controller.reload,
            onRetryPagination: controller.retryPagination,
            onLoadMore: controller.loadMore,
            favoriteIds: favorites.favoriteIds,
            onToggleFavorite: favorites.toggle,
            heroScope: 'discover-',
            onOpen: widget.onOpenWallpaper,
          );
          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              grid.maybeTriggerLoadMore(notification);
              return false;
            },
            child: CustomScrollView(
              slivers: [headerSliver, ...grid.buildSlivers(context)],
            ),
          );
        },
      ),
    );
  }
}

/// Compact row showing the active filter summary; tapping opens the
/// smooth-sheets driven filter sheet.
final class _FilterRow extends StatelessWidget {
  final DiscoverController controller;

  const _FilterRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SignalBuilder(
          builder: (context) {
            final filter = controller.filter.value;
            return FilterChip(
              label: Text(
                filter.summary,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
              avatar: Icon(
                Icons.tune,
                size: 16,
                color: scheme.onSecondaryContainer,
              ),
              backgroundColor: scheme.secondaryContainer,
              selectedColor: scheme.secondaryContainer,
              checkmarkColor: scheme.onSecondaryContainer,
              side: BorderSide(color: scheme.outlineVariant),
              selected: false,
              onSelected: (_) =>
                  showDiscoverFilterSheet(context, controller: controller),
            );
          },
        ),
      ),
    );
  }
}
