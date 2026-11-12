import 'dart:async';

import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:auto_route/auto_route.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../app/theme/app_motion.dart';
import '../../../core/domain/feed_filter.dart';
import '../../../shared/widgets/app_search_bar_spec.dart';
import '../../../shared/widgets/feed_filter_sheet.dart';
import '../../../shared/widgets/horizontal_edge_fade.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/search_controller.dart' as app;

const _searchHeroTag = 'search-bar-hero';

/// Dedicated search destination: search field + expressive filter rows live
/// inside a collapsing [SliverAppBar] (like Discover) so they scroll away,
/// leaving the staggered grid full-screen. The search bar itself lives in
/// the app-bar with a back-prefix, not a separate Scaffold AppBar.
///
/// The header floats but never snaps: snapping re-expands the whole 280/310dp
/// block whenever a scroll ends in the revealing direction, and force-expands
/// it for `showOnScreen` when the field gains focus.
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

  late final _textEditing = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  late final _focusNode = FocusNode();
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
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
    _focusTimer?.cancel();
    _textEditing.dispose();
    _focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final headerSliver = SliverAppBar(
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
      expandedHeight: 280,
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
              const _FilterHeading('By color'),
              const SizedBox(height: 8),
              HorizontalEdgeFade(
                child: SizedBox(
                  height: 48,
                  child: SignalBuilder(
                    builder: (context) {
                      final selected = controller.selectedColors.value;
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 20,
                        ),
                        children: [
                          for (final color in FeedColor.values)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: 14,
                              ),
                              child: _ColorChip(
                                color: color,
                                selected: selected.contains(color),
                                onTap: () {
                                  M3EHaptics.selection();
                                  controller.toggleColor(color);
                                },
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const _FilterHeading('By genre'),
              const SizedBox(height: 8),
              HorizontalEdgeFade(
                child: SizedBox(
                  height: 48,
                  child: SignalBuilder(
                    builder: (context) {
                      final selected = controller.selectedGenres.value;
                      return _GenreStrip(
                        selected: selected,
                        onToggle: controller.toggleGenre,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SignalBuilder(
          builder: (context) {
            if (!controller.hasCommittedInput.value) {
              return CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  headerSliver,
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
                          message: 'Type a query or pick a color / genre to find wallpapers.',
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              emptyState: const EmptyState(
                title: 'No wallpapers found',
                message: 'Try another search or remove a filter.',
              ),
              onOpen: widget.onOpenWallpaper,
            );

            // Search header with sort/filter chip embedded so a floating
            // reveal brings bar + chip back together. Expanded height grows to
            // fit the extra chip row (280 -> 310).
            final headerSliverWithFilter = SliverAppBar(
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
              expandedHeight: 310,
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
                                final hero =
                                    direction == HeroFlightDirection.push
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
                            onLeadingPressed: () =>
                                context.router.root.maybePop(),
                            onSubmitted: (_) => controller.submit(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _FilterHeading('By color'),
                      const SizedBox(height: 8),
                      HorizontalEdgeFade(
                        child: SizedBox(
                          height: 48,
                          child: SignalBuilder(
                            builder: (context) {
                              final selected = controller.selectedColors.value;
                              return ListView(
                                scrollDirection: Axis.horizontal,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsetsDirectional.symmetric(
                                  horizontal: 20,
                                ),
                                children: [
                                  for (final color in FeedColor.values)
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        end: 14,
                                      ),
                                      child: _ColorChip(
                                        color: color,
                                        selected: selected.contains(color),
                                        onTap: () {
                                          M3EHaptics.selection();
                                          controller.toggleColor(color);
                                        },
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _FilterHeading('By genre'),
                      const SizedBox(height: 8),
                      HorizontalEdgeFade(
                        child: SizedBox(
                          height: 48,
                          child: SignalBuilder(
                            builder: (context) {
                              final selected = controller.selectedGenres.value;
                              return _GenreStrip(
                                selected: selected,
                                onToggle: controller.toggleGenre,
                              );
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SignalBuilder(
                            builder: (context) {
                              final filter = controller.filter.value;
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
                                    initial: controller.filter.value,
                                    onApply: (f) => controller.applyFilter(f),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
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
                  headerSliverWithFilter,
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

/// A compact circular color swatch with an accessible 48dp selection target.
final class _ColorChip extends StatelessWidget {
  final FeedColor color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final display = Color(color.colorValue);
    final contrastingCheck = _contrastingForeground(display);

    return Tooltip(
      message: 'Filter by color ${color.label}',
      child: Semantics(
        key: ValueKey('search-color-${color.name}'),
        button: true,
        selected: selected,
        label: 'Filter by color ${color.label}',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                width: selected ? 46 : 44,
                height: selected ? 46 : 44,
                decoration: BoxDecoration(
                  color: display,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 2.5 : 1.25,
                  ),
                ),
                child: selected
                    ? Icon(
                        PhosphorIconsBold.check,
                        key: const ValueKey('search-color-check'),
                        size: 18,
                        color: contrastingCheck,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _contrastingForeground(Color background) {
  final luminance = background.computeLuminance();
  final blackContrast = (luminance + 0.05) / 0.05;
  final whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

/// Section label above a filter strip.
final class _FilterHeading extends StatelessWidget {
  final String text;

  const _FilterHeading(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Horizontally scrolling genre chips that keep the selected chip fully
/// visible when selection changes.
final class _GenreStrip extends StatefulWidget {
  final Set<FeedGenre> selected;
  final ValueChanged<FeedGenre> onToggle;

  const _GenreStrip({required this.selected, required this.onToggle});

  @override
  State<_GenreStrip> createState() => _GenreStripState();
}

final class _GenreStripState extends State<_GenreStrip> {
  final _controller = ScrollController();
  late final List<GlobalKey> _keys;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(FeedGenre.values.length, (_) => GlobalKey());
    if (widget.selected.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void didUpdateWidget(_GenreStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected.isNotEmpty &&
        widget.selected.first != oldWidget.selected.firstOrNull) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  void _revealSelected() {
    final genre = widget.selected.firstOrNull;
    if (genre == null) return;
    final index = FeedGenre.values.indexOf(genre);
    final keyContext = index >= 0 && index < _keys.length
        ? _keys[index].currentContext
        : null;
    if (keyContext == null) return;
    Scrollable.ensureVisible(
      keyContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.arrivalCurve,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
      children: [
        for (var i = 0; i < FeedGenre.values.length; i++)
          Padding(
            key: _keys[i],
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: ChoiceChip(
              key: ValueKey('search-genre-${FeedGenre.values[i].name}'),
              label: Text(FeedGenre.values[i].label),
              selected: widget.selected.contains(FeedGenre.values[i]),
              onSelected: (_) {
                M3EHaptics.selection();
                widget.onToggle(FeedGenre.values[i]);
              },
              selectedColor: scheme.secondaryContainer,
              backgroundColor: scheme.surfaceContainerLow,
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                color: widget.selected.contains(FeedGenre.values[i])
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
              checkmarkColor: scheme.onSecondaryContainer,
              showCheckmark: true,
              side: BorderSide(
                color: widget.selected.contains(FeedGenre.values[i])
                    ? scheme.primary
                    : scheme.outlineVariant,
                width: widget.selected.contains(FeedGenre.values[i]) ? 1.5 : 1,
              ),
              shape: const StadiumBorder(),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              tooltip: 'Filter by genre ${FeedGenre.values[i].label}',
            ),
          ),
      ],
    );
  }
}
