import 'dart:async';

import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../core/domain/feed_filter.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../../favorites/application/favorites_controller.dart';
import '../application/search_controller.dart' as app;

const _searchHeroTag = 'search-bar-hero';

/// Dedicated search destination: search field + expressive filter rows live
/// inside a collapsing [SliverAppBar] (like Discover) so they scroll away,
/// leaving the staggered grid full-screen. The `SearchBar` itself lives in
/// the app-bar with a back-prefix, not a separate Scaffold AppBar.
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
      snap: true,
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Hero(
                  tag: _searchHeroTag,
                  flightShuttleBuilder: (flightContext, animation, direction,
                      fromHeroContext, toHeroContext) {
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
                    controller: _textEditing,
                    focusNode: _focusNode,
                    hintText: 'Search wallpapers',
                    padding: const WidgetStatePropertyAll(
                      EdgeInsetsDirectional.symmetric(horizontal: 16),
                    ),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      color: theme.colorScheme.onSurfaceVariant,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => controller.submit(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 76,
                  child: SignalBuilder(
                    builder: (context) {
                      final selected = controller.selectedColors.value;
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final color in FeedColor.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: _ColorChip(
                                color: color,
                                selected: selected.contains(color),
                                onTap: () => controller.toggleColor(color),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 64,
                  child: SignalBuilder(
                    builder: (context) {
                      final selected = controller.selectedGenres.value;
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final genre in FeedGenre.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _GenreChip(
                                genre: genre,
                                selected: selected.contains(genre),
                                onTap: () => controller.toggleGenre(genre),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
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
                          iconData: Icons.search,
                          title: 'Search wallpapers',
                          message:
                              'Type a query or pick a color / genre to find wallpapers.',
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
                slivers: [
                  headerSliver,
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

/// 8-leaf clover swatch — expressive Material shape for color filters.
///
/// Uses [M3EContainer.l8LeafClover] so each color reads as a tangible
/// expressive chip. 72×64 gives a generous wide hit target while the lobed
/// shape adds delight. Selection is a primary ring + soft shadow + check.
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

    // Wire hex is a validated 6-digit value from the enum itself.
    final display = Color(color.colorValue);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter by color ${color.name}',
      child: GestureDetector(
        onTap: onTap,
        child: M3EContainer.l8LeafClover(
          width: 72,
          height: 64,
          color: display,
          border: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.8),
            width: selected ? 3 : 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.28),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
          child: selected
              ? Center(
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check, size: 18, color: Colors.black87),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Clamshell (clampShell) genre chip — expressive Material shape.
///
/// Replaces the stock [FilterChip] with a bigger, more tactile target:
/// 48dp min height via padding, 28dp horizontal breathing room, and the
/// `clampShell` expressive silhouette. Selected state uses
/// `secondaryContainer` + primary outline.
final class _GenreChip extends StatelessWidget {
  final FeedGenre genre;
  final bool selected;
  final VoidCallback onTap;

  const _GenreChip({
    required this.genre,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter by genre ${genre.label}',
      child: GestureDetector(
        onTap: onTap,
        child: M3EContainer.clampShell(
          color: selected ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
          border: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.18),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          child: Text(
            genre.label,
            style: textTheme.labelLarge?.copyWith(
              color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}
