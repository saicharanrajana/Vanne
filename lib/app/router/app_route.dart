import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../dependencies.dart';
import '../../features/collections/application/collections_controller.dart';
import '../../features/collections/presentation/collection_explore_screen.dart';
import '../../features/collections/presentation/collections_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/filtered/presentation/filtered_wallpapers_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/api_key_screen.dart';
import '../../features/settings/presentation/blocked_tags_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import '../../features/wallpaper_detail/presentation/wallpaper_detail_screen.dart';
import '../../features/wallpaper_detail/presentation/widgets/set_wallpaper_sheet.dart';
import '../../core/domain/feed_filter.dart';
import '../../shared/widgets/feed_filter_sheet.dart';
import '../../shared/widgets/spring_sheet.dart';
import 'tab_scroll_coordinator.dart';

part 'app_route.gr.dart';

/// The single application router.
///
/// Full-screen destinations and application-owned overlays are all entries in
/// this root stack. The tab router is nested under [MainShellPage] only to
/// preserve each destination's widget and scroll state.
@AutoRouterConfig(replaceInRouteName: 'Page|Screen,Route')
final class AppRouter extends RootStackRouter {
  @override
  RouteType get defaultRouteType =>
      const RouteType.material(enablePredictiveBackGesture: true);

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: MainShellRoute.page,
      path: '/',
      initial: true,
      children: [
        AutoRoute(page: DiscoverTabRoute.page, path: '', initial: true),
        AutoRoute(page: CollectionsTabRoute.page, path: 'collections'),
        AutoRoute(page: FavoritesTabRoute.page, path: 'favorites'),
        AutoRoute(page: SettingsTabRoute.page, path: 'settings'),
      ],
    ),
    // The search bar is a shared Hero with Discover, so use the same
    // non-predictive transition as wallpaper detail for reverse edge pops.
    CustomRoute(
      page: SearchRoute.page,
      path: '/search',
      transitionsBuilder: heroCompatibleTransitionBuilder,
    ),
    AutoRoute(
      page: CollectionExploreRoute.page,
      path: '/collections/:collectionId',
    ),
    // Flutter's predictive-back page transition does not participate in the
    // Hero flight. Use the normal Material transition here so both the
    // toolbar button and an edge-back commit share the reverse Hero animation.
    CustomRoute(
      page: WallpaperDetailRoute.page,
      path: '/wallpaper/:wallpaperId',
      transitionsBuilder: heroCompatibleTransitionBuilder,
    ),
    AutoRoute(page: FilteredWallpapersRoute.page, path: '/filtered'),
    AutoRoute(page: ApiKeySettingsRoute.page, path: '/settings/api-key'),
    AutoRoute(page: BlockedTagsRoute.page, path: '/settings/blocked-tags'),
    CustomRoute(
      page: DeleteCollectionsDialogRoute.page,
      path: '/_modal/delete-collections',
      opaque: false,
      barrierDismissible: true,
      customRouteBuilder: m3eDialogRouteBuilder,
    ),
    CustomRoute(
      page: RemoveApiKeyDialogRoute.page,
      path: '/_modal/remove-api-key',
      opaque: false,
      barrierDismissible: true,
      customRouteBuilder: m3eDialogRouteBuilder,
    ),
    CustomRoute(
      page: SetWallpaperDialogRoute.page,
      path: '/_modal/set-wallpaper',
      opaque: false,
      barrierDismissible: true,
      customRouteBuilder: m3eDialogRouteBuilder,
    ),
    CustomRoute(
      page: FeedFilterSheetRoute.page,
      path: '/_modal/feed-filter',
      opaque: false,
      barrierDismissible: true,
      customRouteBuilder: springSheetRouteBuilder,
    ),
  ];
}

Widget heroCompatibleTransitionBuilder(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final route = ModalRoute.of(context);
  if (route is! PageRoute<dynamic>) return child;

  return const FadeForwardsPageTransitionsBuilder().buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    child,
  );
}

/// Modal routes carry live widget state and must never be restored from an
/// external URI without their typed runtime arguments.
Future<Uri> appDeepLinkTransformer(Uri uri) async {
  if (uri.pathSegments.firstOrNull == '_modal') return Uri(path: '/');
  return uri;
}

/// Builds M3E dialogs as page-backed routes on the root navigator.
Route<T> m3eDialogRouteBuilder<T>(
  BuildContext context,
  Widget child,
  AutoRoutePage<T> page,
) {
  final theme = M3EThemeScope.resolveOf(context) ?? M3ETheme.of(context);
  final dialogTheme = theme.dialogTheme;

  return DialogRoute<T>(
    context: context,
    settings: page,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: dialogTheme.scrimColor(theme.colorScheme),
    builder: (context) => M3EScrimSystemUi.wrap(
      M3EComponentTheme(
        builder: (context) =>
            M3EDialogInset(padding: dialogTheme.screenMargin, child: child),
      ),
    ),
  );
}

/// Builds the app's spring sheet as a page-backed root route.
Route<T> springSheetRouteBuilder<T>(
  BuildContext context,
  Widget child,
  AutoRoutePage<T> page,
) {
  return SpringSheetRoute<T>(
    capturedTheme: Theme.of(context),
    builder: (_) => child,
    settings: page,
  );
}

/// Destinations in [MainShellPage]'s tab router. The shell's back policy and
/// the route list must agree on these positions.
const _discoverTabIndex = 0;
const _collectionsTabIndex = 1;

@RoutePage()
final class MainShellPage extends StatelessWidget {
  const MainShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AutoTabsRouter(
      // No `homeIndex`: a tab router that owns a home index consumes system
      // back itself (`TabsRouter.maybePop` jumps straight to its home tab)
      // before the shell's PopScope can see it. Leaving back to bubble keeps
      // the whole policy — cancel a collections selection, then switch to
      // Discover — in this one place.
      routes: const [
        DiscoverTabRoute(),
        CollectionsTabRoute(),
        FavoritesTabRoute(),
        SettingsTabRoute(),
      ],
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        return ListenableBuilder(
          listenable: tabsRouter,
          builder: (context, _) => PopScope<void>(
            // The shell is the root page, so the nested tabs router must
            // consume back before the system is allowed to leave the app.
            canPop: tabsRouter.activeIndex == _discoverTabIndex,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop || tabsRouter.activeIndex == _discoverTabIndex) {
                return;
              }
              // Transient state outranks destination switching: while
              // collections are selected, back only cancels that selection
              // and leaves the user on the Collections tab. A later back then
              // follows the usual tab policy. The nested tab navigator cannot
              // own this: its own PopScope never sees the system's back
              // request, because the shell is the root navigator's top route.
              if (tabsRouter.activeIndex == _collectionsTabIndex &&
                  locator<CollectionsController>().hasSelection.value) {
                locator<CollectionsController>().clearSelection();
                return;
              }
              tabsRouter.setActiveIndex(_discoverTabIndex);
            },
            child: Scaffold(
              body: child,
              bottomNavigationBar: M3ENavigationBar(
                selectedIndex: tabsRouter.activeIndex,
                backgroundColor: Theme.of(context).colorScheme.surface,
                // Pin the wide-layout chip width to the M3E spec default
                // (128dp). Without it the package measures the widest label,
                // and its wide band has no overflow guard when the slots
                // don't fit the available width.
                wideDestinationWidth: 128,
                onDestinationSelected: (index) {
                  M3EHaptics.trigger(M3EHapticFeedback.light);
                  if (index == tabsRouter.activeIndex) {
                    locator<TabScrollCoordinator>().scrollToTop(index);
                    return;
                  }
                  tabsRouter.setActiveIndex(index);
                },
                destinations: const [
                  M3ENavigationBarDestination(
                    icon: Icon(PhosphorIconsBold.compass),
                    selectedIcon: Icon(PhosphorIconsFill.compass),
                    label: 'Discover',
                  ),
                  M3ENavigationBarDestination(
                    icon: Icon(PhosphorIconsBold.stack),
                    selectedIcon: Icon(PhosphorIconsFill.stack),
                    label: 'Collections',
                  ),
                  M3ENavigationBarDestination(
                    icon: Icon(PhosphorIconsBold.heart),
                    selectedIcon: Icon(PhosphorIconsFill.heart),
                    label: 'Favorites',
                  ),
                  M3ENavigationBarDestination(
                    icon: Icon(PhosphorIconsBold.gear),
                    selectedIcon: Icon(PhosphorIconsFill.gear),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

@RoutePage()
final class DiscoverTabPage extends StatelessWidget {
  const DiscoverTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The M3E search bar can report a tap twice (upstream double onTap), so
    // guard against stacking duplicate search pages.
    void openSearch() {
      if (context.router.root.stack.any((route) => route.name == SearchRoute.name)) {
        return;
      }
      context.router.root.push(SearchRoute());
    }

    return DiscoverScreen(
      onOpenSearch: openSearch,
      onOpenWallpaper: (wallpaper) => context.router.root.push(
        WallpaperDetailRoute(
          wallpaperId: wallpaper.id,
          initial: wallpaper,
          heroScope: 'discover-',
        ),
      ),
    );
  }
}

@RoutePage()
final class CollectionsTabPage extends StatelessWidget {
  const CollectionsTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CollectionsScreen(
      onOpenCollection: (id) =>
          context.router.root.push(CollectionExploreRoute(collectionId: id)),
    );
  }
}

@RoutePage()
final class FavoritesTabPage extends StatelessWidget {
  const FavoritesTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FavoritesScreen(
      onOpenWallpaper: (wallpaper) => context.router.root.push(
        WallpaperDetailRoute(
          wallpaperId: wallpaper.id,
          initial: wallpaper,
          heroScope: 'favorites-',
        ),
      ),
    );
  }
}

@RoutePage()
final class SettingsTabPage extends StatelessWidget {
  const SettingsTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScreen(
      onOpenApiKey: () => context.router.root.push(const ApiKeySettingsRoute()),
      onOpenBlockedTags: () =>
          context.router.root.push(const BlockedTagsRoute()),
    );
  }
}

@RoutePage()
final class SearchPage extends StatelessWidget {
  const SearchPage({@QueryParam('q') this.query, super.key});

  final String? query;

  @override
  Widget build(BuildContext context) {
    return SearchScreen(
      initialQuery: query,
      onOpenWallpaper: (wallpaper) => context.router.root.push(
        WallpaperDetailRoute(
          wallpaperId: wallpaper.id,
          initial: wallpaper,
          heroScope: 'search-',
        ),
      ),
    );
  }
}

@RoutePage()
final class CollectionExplorePage extends StatelessWidget {
  const CollectionExplorePage({
    @PathParam('collectionId') required this.collectionId,
    super.key,
  });

  final String collectionId;

  @override
  Widget build(BuildContext context) {
    return CollectionExploreScreen(
      collectionId: collectionId,
      onOpenWallpaper: (wallpaper) => context.router.root.push(
        WallpaperDetailRoute(
          wallpaperId: wallpaper.id,
          initial: wallpaper,
          heroScope: 'collection-$collectionId-',
        ),
      ),
    );
  }
}

@RoutePage()
final class WallpaperDetailPage extends StatefulWidget {
  const WallpaperDetailPage({
    @PathParam('wallpaperId') required this.wallpaperId,
    this.initial,
    this.heroScope = '',
    super.key,
  });

  final String wallpaperId;
  final Wallpaper? initial;
  final String heroScope;

  @override
  State<WallpaperDetailPage> createState() => _WallpaperDetailPageState();
}

final class _WallpaperDetailPageState extends State<WallpaperDetailPage> {
  late final WallpaperDetailController _controller;

  @override
  void initState() {
    super.initState();
    _controller = locator<WallpaperDetailController>(
      param1: widget.wallpaperId,
      param2: widget.initial,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WallpaperDetailScreen(
      controller: _controller,
      onBack: () => context.router.root.pop(),
      heroScope: widget.heroScope,
      onColorTap: (hex) {
        final normalized = hex.startsWith('#')
            ? hex.toUpperCase()
            : '#${hex.toUpperCase()}';
        context.router.root.push(
          FilteredWallpapersRoute(title: normalized, colors: normalized),
        );
      },
      onTagTap: (tag) {
        context.router.root.push(
          FilteredWallpapersRoute(title: tag, query: tag),
        );
      },
    );
  }
}

@RoutePage()
final class FilteredWallpapersPage extends StatelessWidget {
  const FilteredWallpapersPage({
    @QueryParam('title') this.title = '',
    @QueryParam('q') this.query = '',
    @QueryParam('colors') this.colors = '',
    super.key,
  });

  final String title;
  final String query;
  final String colors;

  List<String> get colorHexes => colors
      .split(',')
      .where((color) => color.isNotEmpty)
      .toList(growable: false);

  String get heroScope =>
      colorHexes.isNotEmpty ? 'color-${colorHexes.first}-' : 'tag-$query-';

  @override
  Widget build(BuildContext context) {
    return FilteredWallpapersScreen(
      title: title,
      query: query,
      colorHexes: colorHexes,
      onBack: () => context.router.root.pop(),
      onOpenWallpaper: (wallpaper) => context.router.root.push(
        WallpaperDetailRoute(
          wallpaperId: wallpaper.id,
          initial: wallpaper,
          heroScope: heroScope,
        ),
      ),
    );
  }
}

@RoutePage()
final class ApiKeySettingsPage extends StatelessWidget {
  const ApiKeySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ApiKeyScreen(onBack: () => context.router.root.pop());
  }
}

@RoutePage()
final class BlockedTagsPage extends StatelessWidget {
  const BlockedTagsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlockedTagsScreen(onBack: () => context.router.root.pop());
  }
}

@RoutePage()
final class DeleteCollectionsDialogPage extends StatelessWidget {
  const DeleteCollectionsDialogPage({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return M3EDialog(
      title: count == 1
          ? 'Remove collection?'
          : 'Remove $count collections?',
      content: const Text('Wallpapers and favorites won’t be affected.'),
      actions: [
        M3EButton.text(
          onPressed: () => context.router.root.pop(false),
          child: const Text('Cancel'),
        ),
        M3EButton.filled(
          decoration: M3EButtonDecoration(
            backgroundColor: WidgetStatePropertyAll(scheme.error),
            foregroundColor: WidgetStatePropertyAll(scheme.onError),
          ),
          onPressed: () => context.router.root.pop(true),
          child: const Text('Remove'),
        ),
      ],
    );
  }
}

@RoutePage()
final class RemoveApiKeyDialogPage extends StatelessWidget {
  const RemoveApiKeyDialogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return M3EDialog(
      title: 'Remove API key?',
      content: const Text(
        'NSFW access will be disabled until another key is configured.',
      ),
      actions: [
        M3EButton.text(
          onPressed: () => context.router.root.pop(false),
          child: const Text('Cancel'),
        ),
        M3EButton.filled(
          decoration: M3EButtonDecoration(
            backgroundColor: WidgetStatePropertyAll(scheme.error),
            foregroundColor: WidgetStatePropertyAll(scheme.onError),
          ),
          onPressed: () => context.router.root.pop(true),
          child: const Text('Remove'),
        ),
      ],
    );
  }
}

@RoutePage()
final class SetWallpaperDialogPage extends StatelessWidget {
  const SetWallpaperDialogPage({required this.controller, super.key});

  final WallpaperDetailController controller;

  @override
  Widget build(BuildContext context) {
    return SetWallpaperTheme(
      controller: controller,
      child: SetWallpaperDialog(controller: controller),
    );
  }
}

@RoutePage()
final class FeedFilterSheetPage extends StatelessWidget {
  const FeedFilterSheetPage({required this.initial, super.key});

  final FeedFilter initial;

  @override
  Widget build(BuildContext context) {
    return FeedFilterSheetContent(initial: initial);
  }
}
