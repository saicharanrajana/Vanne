import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../core/collections/collection_entry.dart';
import '../../../core/wallpaper/wallpaper_repository.dart';
import '../../../shared/utils/display_title.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/feed_filter_sheet.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/filtered_wallpapers_controller.dart';
import '../../collections/application/collections_controller.dart';

/// Ephemeral wallpapers list opened from a tapped tag or color.
///
/// Looks like collection explore (paginated grid, sort & filter) but offers a
/// collection toggle in the app bar: tapping saves this query as a collection,
/// tapping again removes that collection again.
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

  /// Guards the collection toggle against double taps: collection create and
  /// delete are async, and two overlapping calls could create duplicates or
  /// delete a row that is about to be recreated.
  bool _collectionBusy = false;

  String get _heroScope {
    if (widget.colorHexes.isNotEmpty) {
      return 'color-${widget.colorHexes.first}-';
    }
    return 'tag-${widget.query}-';
  }

  String get _displayTitle => formatDisplayTitle(widget.title);

  /// The collection this screen represents, matched on the same display title
  /// [CollectionsController.create] stores. `null` when the query is not saved.
  CollectionEntry? _savedCollection(CollectionsController collections) {
    final target = _displayTitle.toLowerCase();
    for (final entry in collections.entries.value) {
      if (entry.name.toLowerCase() == target) return entry;
    }
    return null;
  }

  /// Saves or removes this query's collection — a real toggle, not a one-way
  /// promotion. Persistence goes through the repository behind
  /// [CollectionsController], which rolls back on failure, so the snackbar
  /// only reports a state that actually stuck.
  Future<void> _toggleCollection() async {
    if (_collectionBusy) return;
    setState(() => _collectionBusy = true);
    try {
      final collections = locator<CollectionsController>();
      final saved = _savedCollection(collections);
      if (saved != null) {
        final removed = await collections.removeMany({saved.id});
        if (!mounted) return;
        if (removed) {
          AppSnack.showRoot(
            'Removed from Collections',
            type: AppSnackType.removal,
          );
        } else {
          AppSnack.show(
            context,
            'Could not remove the collection',
            type: AppSnackType.error,
          );
        }
        return;
      }
      final error = await collections.create(
        name: _displayTitle,
        query: widget.query,
        colors: widget.colorHexes,
        filter: _controller.filter.value,
      );
      if (!mounted) return;
      if (error != null) {
        AppSnack.show(context, error, type: AppSnackType.error);
      } else {
        AppSnack.showRoot('Added to Collections', type: AppSnackType.success);
      }
    } finally {
      if (mounted) {
        setState(() => _collectionBusy = false);
      } else {
        _collectionBusy = false;
      }
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
              message: 'No wallpapers matched $_displayTitle.',
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
                      // The tonal container owns both halves of its colour
                      // pair; pinning onSurfaceVariant fought
                      // onSecondaryContainer.
                      icon: const Icon(PhosphorIconsBold.arrowLeft, size: 18),
                    ),
                  ),
                  title: Text(_displayTitle),
                  actions: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: SignalBuilder(
                        builder: (context) {
                          final saved =
                              _savedCollection(colorsController) != null;
                          return M3EIconButton(
                            // A transparent app-bar action, not a primary
                            // call to action: the 1.1.3 default `filled`
                            // variant painted a primary disc that also
                            // changed shape when the action became disabled.
                            variant: M3EIconButtonVariant.standard,
                            isSelected: saved,
                            // Busy only briefly while persisting; disabling
                            // the control keeps a second tap from racing the
                            // create/delete.
                            onPressed: _collectionBusy
                                ? null
                                : _toggleCollection,
                            tooltip: saved
                                ? 'Remove from Collections'
                                : 'Save to Collections',
                            semanticLabel: saved
                                ? 'Remove from Collections'
                                : 'Save to Collections',
                            // Outline when absent, filled when saved: the
                            // glyph carries the state, not colour alone.
                            icon: const Icon(PhosphorIconsBold.bookmarkSimple),
                            selectedIcon: const Icon(
                              PhosphorIconsFill.bookmarkSimple,
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
