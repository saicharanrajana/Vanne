import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/collections/collection_entry.dart';
import '../../../core/collections/collection_identity.dart';
import '../../../core/wallpaper/wallpaper_repository.dart';
import '../../../shared/utils/color_display.dart';
import '../../../shared/utils/display_title.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/collection_membership_button.dart';
import '../../../shared/widgets/feed_filter_sheet.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/filtered_wallpapers_controller.dart';
import '../../collections/application/collections_controller.dart';

/// Ephemeral wallpapers list opened from a tapped tag or color.
///
/// Looks like collection explore (paginated grid, sort & filter) but offers a
/// collection toggle in the app bar: an outlined `+ Add` saves this search as
/// a collection and becomes a filled `✓ Added`, which removes that same
/// collection again. The browsing page stays exactly where it is either way.
/// Curated default collections are permanent, so their pages show no toggle at
/// all rather than a button that cannot be honoured.
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

  /// Exact id created by this page instance. A session-only filter change must
  /// not make the just-saved collection disappear from the toggle state.
  String? _sessionSavedCollectionId;

  String get _heroScope {
    if (widget.colorHexes.isNotEmpty) {
      return 'color-${widget.colorHexes.first}-';
    }
    return 'tag-${widget.query}-';
  }

  String get _displayTitle => formatDisplayTitle(widget.title);

  /// The collection this page's search is already saved as.
  ///
  /// Other saved collections require an exact effective search definition.
  /// The one exception is the exact id this page successfully created: its
  /// filter is session-only and may change after saving, but the user still
  /// expects this page's Added toggle to remove that same row.
  CollectionEntry? _savedCollection(CollectionsController collections) {
    final sessionId = _sessionSavedCollectionId;
    if (sessionId != null) {
      final sessionEntry = collections.entryById(sessionId);
      if (sessionEntry != null) return sessionEntry;
      _sessionSavedCollectionId = null;
    }

    return collections.findByDefinition(
      CollectionSearchDefinition(
        query: widget.query,
        colors: widget.colorHexes,
        filter: _controller.filter.value,
      ),
    );
  }

  /// The collection cover is the first wallpaper already fetched for this
  /// query. Saving before the first page arrives (or for an empty query)
  /// leaves the cover empty and falls back to a theme card.
  Wallpaper? get _coverWallpaper {
    final items = _controller.state.value.items;
    return items.isEmpty ? null : items.first;
  }

  String? get _coverUrl {
    final thumbnails = _coverWallpaper?.thumbnails;
    return thumbnails?.large ?? thumbnails?.original ?? thumbnails?.small;
  }

  /// Avoid a duplicate display name without treating that collision as proof
  /// that a different search is already saved. Search identity is independent
  /// of the generated presentation name.
  String _uniqueCollectionName(CollectionsController collections) {
    final used = {
      for (final entry in collections.entries.value)
        entry.name.trim().toLowerCase(),
    };
    if (!used.contains(_displayTitle.toLowerCase())) return _displayTitle;
    for (var suffix = 2; ; suffix++) {
      final candidate = '$_displayTitle ($suffix)';
      if (!used.contains(candidate.toLowerCase())) return candidate;
    }
  }

  /// The cover's palette, taken from the listing entry that supplied the
  /// cover, so nothing extra is fetched and the two always describe the same
  /// wallpaper.
  List<String> get _coverColors =>
      ColorDisplay.normalizedPalette(_coverWallpaper?.colors ?? const []);

  /// Adds this search to Collections, or removes the collection it already has.
  /// Persistence goes through the repository behind [CollectionsController],
  /// which rolls back on failure, so the button only keeps a state that
  /// actually stuck and the snackbar only reports one.
  Future<void> _toggleCollection() async {
    if (_collectionBusy) return;
    final collections = locator<CollectionsController>();
    final saved = _savedCollection(collections);
    setState(() => _collectionBusy = true);
    try {
      if (saved != null) {
        final removed = await collections.remove(saved.id);
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
      final name = _uniqueCollectionName(collections);
      final error = await collections.create(
        name: name,
        query: widget.query,
        colors: widget.colorHexes,
        filter: _controller.filter.value,
        coverUrl: _coverUrl,
        coverColors: _coverColors,
        // The origin is recorded here, where we still know which grid the
        // user bookmarked. Backfills of old rows cannot recover this.
        origin: widget.colorHexes.isNotEmpty
            ? CollectionOrigin.color
            : CollectionOrigin.tag,
      );
      if (!mounted) return;
      if (error != null) {
        AppSnack.show(context, error, type: AppSnackType.error);
      } else {
        _sessionSavedCollectionId = collections
            .findByDefinition(
              CollectionSearchDefinition(
                query: widget.query,
                colors: widget.colorHexes,
                filter: _controller.filter.value,
              ),
            )
            ?.id;
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
                      // Match the visible 32 dp back-button surface's inset.
                      padding: const EdgeInsetsDirectional.only(
                        end: AppSpacing.lg,
                      ),
                      child: SignalBuilder(
                        builder: (context) {
                          final saved = _savedCollection(colorsController);
                          // A curated collection is permanent: it has no
                          // removal control at all, not a disabled one. Its
                          // tag page simply shows no toggle.
                          if (saved != null &&
                              colorsController.isCuratedDefault(saved.id)) {
                            return const SizedBox.shrink();
                          }
                          return CollectionMembershipButton(
                            added: saved != null,
                            pending: _collectionBusy,
                            subject: _displayTitle,
                            onPressed: _collectionBusy
                                ? null
                                : _toggleCollection,
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
