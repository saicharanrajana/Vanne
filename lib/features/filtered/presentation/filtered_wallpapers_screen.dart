import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../core/wallpaper/wallpaper_repository.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/feed_filter_sheet.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/filtered_wallpapers_controller.dart';
import '../../collections/application/collections_controller.dart';

/// Ephemeral wallpapers list opened from a tapped tag or color.
///
/// Looks like collection explore (paginated grid, sort & filter) but offers
/// "Add as collection" in the app bar to promote to a persisted collection.
final class FilteredWallpapersScreen extends StatefulWidget {
  final String title;
  final String query;
  final List<String> colorHexes;
  final ValueChanged<Wallpaper> onOpenWallpaper;
  final VoidCallback onBack;

  const FilteredWallpapersScreen({
    super.key,
    required this.title,
    required this.query,
    this.colorHexes = const [],
    required this.onOpenWallpaper,
    required this.onBack,
  });

  @override
  State<FilteredWallpapersScreen> createState() =>
      _FilteredWallpapersScreenState();
}

final class _FilteredWallpapersScreenState
    extends State<FilteredWallpapersScreen> {
  late final FilteredWallpapersController _controller =
      FilteredWallpapersController(
        title: widget.title,
        query: widget.query,
        colorHexes: widget.colorHexes,
        repository: locator<WallpaperRepository>(),
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _heroScope {
    if (widget.colorHexes.isNotEmpty) {
      return 'color-${widget.colorHexes.first}-';
    }
    return 'tag-${widget.query}-';
  }

  Future<void> _saveAsCollection() async {
    final collections = locator<CollectionsController>();
    final title = widget.title;
    // Normalize like CollectionsController does: case-insensitive check.
    final exists = collections.entries.value.any(
      (e) => e.name.toLowerCase() == title.toLowerCase(),
    );
    if (exists) {
      if (mounted) AppSnack.show(context, 'Collection already exists');
      return;
    }
    final err = await collections.create(
      name: title,
      query: widget.query,
      colors: widget.colorHexes,
      filter: _controller.filter.value,
    );
    if (!mounted) return;
    if (err != null) {
      AppSnack.show(context, err, error: true);
    } else {
      AppSnack.showRoot('Added "${widget.title}" to collections');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorsController = locator<CollectionsController>();
    final favorites = locator<FavoritesController>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SignalBuilder(
        builder: (context) {
          final state = _controller.state.value;
          final grid = WallpaperGrid(
            items: state.items.toList(growable: false),
            isLoadingFirst: state.loadingFirst,
            isLoadingMore: state.loadingMore,
            hasMore: state.hasMore,
            error: state.error,
            paginationError: state.paginationError,
            heroScope: _heroScope,
            onRetry: _controller.reload,
            onRetryPagination: _controller.retryPagination,
            onLoadMore: _controller.loadMore,
            favoriteIds: favorites.favoriteIds,
            onToggleFavorite: favorites.toggle,
            emptyState: EmptyState(
              title: 'Nothing here yet',
              message: 'No wallpapers matched ${widget.title}.',
            ),
            onOpen: widget.onOpenWallpaper,
          );

          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              grid.maybeTriggerLoadMore(n);
              return false;
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  snap: true,
                  pinned: false,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  leading: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: M3EIconButton(
                      variant: M3EIconButtonVariant.tonal,
                      size: M3EIconButtonSize.xs,
                      onPressed: widget.onBack,
                      tooltip: 'Back',
                      icon: Icon(
                        PhosphorIconsBold.arrowLeft,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  title: Text(widget.title),
                  actions: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: SignalBuilder(
                        builder: (context) {
                          final exists = colorsController.entries.value.any(
                            (e) =>
                                e.name.toLowerCase() ==
                                widget.title.toLowerCase(),
                          );
                          // Re-read alreadyExists via signal so icon updates.
                          return M3EIconButton(
                            onPressed: exists ? null : _saveAsCollection,
                            tooltip: exists
                                ? 'Already in collections'
                                : 'Add as collection',
                            icon: Icon(
                              exists
                                  ? PhosphorIconsFill.bookmarkSimple
                                  : PhosphorIconsBold.plus,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: SignalBuilder(
                          builder: (context) {
                            final filter = _controller.filter.value;
                            return M3EChip(
                              label: filter.summary,
                              type: M3EChipType.filter,
                              selected: true,
                              leading: Icon(
                                PhosphorIconsFill.slidersHorizontal,
                                size: 16,
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                              onPressed: () {
                                M3EHaptics.trigger(M3EHapticFeedback.light);
                                showFeedFilterSheet(
                                  context,
                                  initial: _controller.filter.value,
                                  onApply: (f) => _controller.applyFilter(f),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                ...grid.buildSlivers(context),
              ],
            ),
          );
        },
      ),
    );
  }
}
