import 'dart:async';

import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:auto_route/auto_route.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../core/collections/collection_entry.dart';
import '../../../shared/widgets/app_search_bar_spec.dart';
import '../../../shared/widgets/feed_filter_fab.dart';
import '../../../shared/widgets/feed_filter_sheet.dart';
import '../../../shared/widgets/horizontal_edge_fade.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../collections/application/collections_controller.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/search_controller.dart' as app;
import 'widgets/search_filter_carousels.dart';

const _searchHeroTag = 'search-bar-hero';

/// Vertical pieces of the collapsing header, in logical pixels. The carousel
/// rows and headings change size with the text scale, so the sliver's expanded
/// height is computed from these rather than hard-coded per screen state.
abstract final class _HeaderMetrics {
  /// Top gutter + search bar + gap under it.
  static const double barBlock = 12 + 56 + 16;

  /// Heading line height at scale 1.0 plus the gap under the heading. The
  /// headings are 18sp/500 (`SearchFilterHeading`) on the theme's 1.5 line
  /// height, so one line is 27dp.
  static const double headingLine = 27;
  static const double headingGap = 10;

  /// Gap between the two filter sections.
  static const double sectionGap = 20;

  /// Bottom gutter of the header.
  static const double bottomGutter = 12;
}

/// Dedicated search destination: search field + expressive filter carousels
/// live inside a collapsing [SliverAppBar] (like Discover) so they scroll away,
/// leaving the staggered grid full-screen. The search bar itself lives in the
/// app-bar with a back-prefix, not a separate Scaffold AppBar.
///
/// The header floats but never snaps: snapping re-expands the whole block
/// whenever a scroll ends in the revealing direction, and force-expands it for
/// `showOnScreen` when the field gains focus.
final class SearchScreen extends StatefulWidget {
  final String? initialQuery;
  final ValueChanged<Wallpaper> onOpenWallpaper;
  final bool autofocus;

  const SearchScreen({
    super.key,
    this.initialQuery,
    required this.onOpenWallpaper,
    this.autofocus = true,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

final class _SearchScreenState extends State<SearchScreen> {
  late final app.SearchController controller = locator<app.SearchController>();
  late final FavoritesController favorites = locator<FavoritesController>();
  late final CollectionsController _collections =
      locator<CollectionsController>();

  late final _textEditing = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  late final _focusNode = FocusNode();
  Timer? _focusTimer;
  late final EffectCleanup _pruneTagEffect;

  @override
  void initState() {
    super.initState();
    // A deleted collection must not keep filtering through an invisible card:
    // the By tag row only shows saved tag collections, so the applied tag is
    // dropped as soon as its source row is gone.
    _pruneTagEffect = effect(() {
      final savedIds = [
        for (final entry in _collections.entries.value) entry.id,
      ];
      untracked(() => controller.pruneSelectedTag(savedIds));
    });
    _textEditing.addListener(() {
      controller.queryText.set(_textEditing.text);
    });
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      controller.queryText.set(widget.initialQuery!);
    }
    if (!widget.autofocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusTimer = Timer(const Duration(milliseconds: 320), () {
        if (mounted && _focusNode.canRequestFocus) {
          try {
            _focusNode.requestFocus();
          } catch (_) {}
        }
      });
    });
  }

  @override
  void dispose() {
    _pruneTagEffect();
    _focusTimer?.cancel();
    _textEditing.dispose();
    _focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  /// Collections the tag row can offer.
  ///
  /// Only positively classified tag collections belong here. A colour
  /// collection has no tag term, and a legacy collection with no recorded
  /// origin may hold an arbitrary saved search expression, so neither can
  /// contribute a tag filter. The row hides entirely when nothing qualifies.
  List<CollectionEntry> _tagEntries() => [
    for (final entry in _collections.entries.value)
      if (entry.isTagCollection) entry,
  ];

  double _headerExtent(BuildContext context, {required bool showTagRow}) {
    // Line heights round in the text layout, so each heading keeps a couple of
    // logical pixels of headroom instead of assuming the scaled 24dp line
    // lands exactly on a whole pixel.
    final heading =
        MediaQuery.textScalerOf(context)
            .scale(_HeaderMetrics.headingLine)
            .ceilToDouble() +
        2;
    var extent =
        _HeaderMetrics.barBlock +
        heading +
        _HeaderMetrics.headingGap +
        SearchFilterCarouselSpec.height +
        _HeaderMetrics.bottomGutter;
    if (showTagRow) {
      extent +=
          _HeaderMetrics.sectionGap +
          heading +
          _HeaderMetrics.headingGap +
          SearchFilterCarouselSpec.height;
    }
    return extent;
  }

  Widget _buildHeader(
    BuildContext context, {
    required List<CollectionEntry> tagEntries,
    required CollectionEntry? selectedTag,
  }) {
    final theme = Theme.of(context);
    final showTagRow = tagEntries.isNotEmpty;
    return SliverAppBar(
      floating: true,
      snap: false,
      pinned: false,
      automaticallyImplyLeading: false,
      backgroundColor: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 0,
      collapsedHeight: 0,
      expandedHeight: _headerExtent(context, showTagRow: showTagRow),
      flexibleSpace: FlexibleSpaceBar(
        background: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Hero(
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
                  child: AppSearchBarSpec.buildBar(
                    controller: _textEditing,
                    focusNode: _focusNode,
                    hintText: 'Search wallpapers',
                    glyph: PhosphorIconsBold.arrowLeft,
                    tooltip: 'Back',
                    onLeadingPressed: () => context.router.root.maybePop(),
                    onSubmitted: (_) => controller.submit(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SearchFilterHeading('By color'),
              const SizedBox(height: _HeaderMetrics.headingGap),
              HorizontalEdgeFade(
                child: SearchColorCarousel(
                  selected: controller.selectedColors.value,
                  onToggle: controller.toggleColor,
                ),
              ),
              // The whole tag section disappears when no saved collection
              // stands for a tag — there is nothing to filter by.
              if (showTagRow) ...[
                const SizedBox(height: _HeaderMetrics.sectionGap),
                const SearchFilterHeading('By tag'),
                const SizedBox(height: _HeaderMetrics.headingGap),
                HorizontalEdgeFade(
                  child: SearchTagCollectionCarousel(
                    entries: tagEntries,
                    selectedId: selectedTag?.id,
                    onToggle: controller.toggleTag,
                  ),
                ),
              ],
              const SizedBox(height: _HeaderMetrics.bottomGutter),
            ],
          ),
        ),
      ),
    );
  }

  void _openFilters() {
    M3EHaptics.trigger(M3EHapticFeedback.light);
    showFeedFilterSheet(
      context,
      initial: controller.filter.value,
      onApply: (f) => controller.applyFilter(f),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: SignalBuilder(
        builder: (context) => controller.hasCommittedInput.value
            ? FeedFilterFab(
                triggerKey: const ValueKey('feed-filter-trigger-search'),
                onPressed: _openFilters,
              )
            : const SizedBox.shrink(),
      ),
      body: SafeArea(
        bottom: false,
        child: SignalBuilder(
          builder: (context) {
            final selectedTag = controller.selectedTag.value;
            final tagEntries = _tagEntries();

            if (!controller.hasCommittedInput.value) {
              return CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  _buildHeader(
                    context,
                    tagEntries: tagEntries,
                    selectedTag: selectedTag,
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 32),
                        child: EmptyState(
                          iconData: PhosphorIconsFill.magnifyingGlass,
                          title: 'Search wallpapers',
                          message:
                              'Type a query, pick a color, or start from a '
                              'saved tag collection.',
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

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
              heroScope: 'search-',
              // Room for the floating filter trigger at the end of the list.
              padding: const EdgeInsets.fromLTRB(
                16,
                4,
                16,
                24 + FeedFilterFab.scrollClearance,
              ),
              emptyState: const EmptyState(
                title: 'No wallpapers found',
                message: 'Try another search or remove a filter.',
              ),
              onOpen: widget.onOpenWallpaper,
            );

            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                grid.maybeTriggerLoadMore(notification);
                return false;
              },
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  _buildHeader(
                    context,
                    tagEntries: tagEntries,
                    selectedTag: selectedTag,
                  ),
                  ...grid.buildSlivers(context),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
