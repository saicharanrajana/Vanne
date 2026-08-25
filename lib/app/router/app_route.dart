import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/navigation_bar/models/m3e_navigation_bar_destination.dart';
import 'package:material_ui/material_ui.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:zenrouter/zenrouter.dart';

import '../dependencies.dart';
import '../../features/collections/presentation/collection_explore_screen.dart';
import '../../features/collections/presentation/collections_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/api_key_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import '../../features/wallpaper_detail/presentation/wallpaper_detail_screen.dart';

/// Route hierarchy.
///
/// The four primary destinations live in one [IndexedStackPath] rendered
/// by [MainShell] (persistent bottom navigation, state preserved per tab).
/// Everything else is pushed onto the root stack with a Material page
/// transition so Hero animations animate correctly.
abstract class AppRoute extends RouteTarget with RouteUnique {
  @override
  Widget build(AppCoordinator coordinator, BuildContext context);
}

// ---------------------------------------------------------------------------
// Primary destinations
// ---------------------------------------------------------------------------

class DiscoverTab extends AppRoute {
  @override
  Type get layout => MainShell;

  @override
  Uri toUri() => Uri.parse('/');

  @override
  Widget build(AppCoordinator coordinator, BuildContext context) =>
      DiscoverScreen(
        onOpenSearch: () => coordinator.push(SearchRoute()),
        onOpenWallpaper: (wallpaper) => coordinator.push(
          WallpaperDetailRoute(
            wallpaperId: wallpaper.id,
            initial: wallpaper,
            heroScope: 'discover-',
          ),
        ),
      );
}

class CollectionsTab extends AppRoute {
  @override
  Type get layout => MainShell;

  @override
  Uri toUri() => Uri.parse('/collections');

  @override
  Widget build(AppCoordinator coordinator, BuildContext context) =>
      CollectionsScreen(
        onOpenCollection: (id) =>
            coordinator.push(CollectionExploreRoute(collectionId: id)),
      );
}

class FavoritesTab extends AppRoute {
  @override
  Type get layout => MainShell;

  @override
  Uri toUri() => Uri.parse('/favorites');

  @override
  Widget build(AppCoordinator coordinator, BuildContext context) =>
      FavoritesScreen(
        onOpenWallpaper: (wallpaper) => coordinator.push(
          WallpaperDetailRoute(
            wallpaperId: wallpaper.id,
            initial: wallpaper,
            heroScope: 'favorites-',
          ),
        ),
      );
}

class SettingsTab extends AppRoute {
  @override
  Type get layout => MainShell;

  @override
  Uri toUri() => Uri.parse('/settings');

  @override
  Widget build(AppCoordinator coordinator, BuildContext context) =>
      SettingsScreen(
        onOpenApiKey: () => coordinator.push(ApiKeySettingsRoute()),
      );
}

/// Persistent navigation shell hosting the four tabs as an IndexedStack.
class MainShell extends AppRoute with RouteLayout<AppRoute> {
  @override
  IndexedStackPath<AppRoute> resolvePath(AppCoordinator coordinator) =>
      coordinator.tabs;

  @override
  Widget build(AppCoordinator coordinator, BuildContext context) {
    final path = coordinator.tabs;
    return Scaffold(
      body: buildPath(coordinator),
      bottomNavigationBar: ListenableBuilder(
        listenable: path,
        builder: (context, _) {
          return M3ENavigationBar(
            selectedIndex: path.activeIndex,
            backgroundColor: Theme.of(context).colorScheme.surface,
            onDestinationSelected: (index) => path.goToIndexed(index),
            destinations: const [
              M3ENavigationBarDestination(
                icon: Icon(BootstrapIcons.compass),
                selectedIcon: Icon(BootstrapIcons.compass_fill),
                label: 'Discover',
              ),
              M3ENavigationBarDestination(
                icon: Icon(BootstrapIcons.collection),
                selectedIcon: Icon(BootstrapIcons.collection_fill),
                label: 'Collections',
              ),
              M3ENavigationBarDestination(
                icon: Icon(BootstrapIcons.heart),
                selectedIcon: Icon(BootstrapIcons.heart_fill),
                label: 'Favorites',
              ),
              M3ENavigationBarDestination(
                icon: Icon(BootstrapIcons.gear),
                selectedIcon: Icon(BootstrapIcons.gear_fill),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pushed routes
// ---------------------------------------------------------------------------

class SearchRoute extends AppRoute with RouteTransition {
  /// Optional initial query (e.g. from a suggestion).
  final String? query;

  SearchRoute({this.query});

  @override
  Uri toUri() => Uri.parse('/search');

  @override
  Widget build(AppCoordinator coordinator, BuildContext context) =>
      SearchScreen(
        initialQuery: query,
        onOpenWallpaper: (wallpaper) => coordinator.push(
          WallpaperDetailRoute(
            wallpaperId: wallpaper.id,
            initial: wallpaper,
            heroScope: 'search-',
          ),
        ),
      );

  @override
  StackTransition<T> transition<T extends RouteUnique>(
    covariant Coordinator<RouteUnique> coordinator,
  ) {
    return StackTransition.material(
      Builder(
        builder: (context) => build(coordinator as AppCoordinator, context),
      ),
    );
  }
}

class CollectionExploreRoute extends AppRoute {
  final String collectionId;

  CollectionExploreRoute({required this.collectionId});

  @override
  Uri toUri() => Uri.parse('/collections/$collectionId');

  @override
  Widget build(AppCoordinator coordinator, BuildContext context) =>
      CollectionExploreScreen(
        collectionId: collectionId,
        onOpenWallpaper: (wallpaper) => coordinator.push(
          WallpaperDetailRoute(
            wallpaperId: wallpaper.id,
            initial: wallpaper,
            heroScope: 'collection-$collectionId-',
          ),
        ),
      );
}

class WallpaperDetailRoute extends AppRoute with RouteTransition {
  final String wallpaperId;
  final Wallpaper? initial;
  final String heroScope;

  WallpaperDetailRoute({
    required this.wallpaperId,
    this.initial,
    this.heroScope = '',
  });

  /// Created once per route instance; rebuilding the route must not spawn
  /// a fresh controller (and re-fire `/w/{id}`) on every build. The screen's
  /// [State.dispose] releases it when the route is popped.
  WallpaperDetailController? _controller;

  @override
  Uri toUri() => Uri.parse('/wallpaper/$wallpaperId');

  @override
  Widget build(AppCoordinator coordinator, BuildContext context) {
    final controller = _controller ??= locator<WallpaperDetailController>(
      param1: wallpaperId,
      param2: initial,
    );
    return WallpaperDetailScreen(
      controller: controller,
      onBack: () => coordinator.pop(),
      heroScope: heroScope,
    );
  }

  @override
  StackTransition<T> transition<T extends RouteUnique>(
    covariant Coordinator<RouteUnique> coordinator,
  ) {
    return StackTransition.material(
      Builder(
        builder: (context) => build(coordinator as AppCoordinator, context),
      ),
    );
  }
}

class ApiKeySettingsRoute extends AppRoute {
  @override
  Uri toUri() => Uri.parse('/settings/api-key');

  @override
  Widget build(AppCoordinator coordinator, BuildContext context) =>
      ApiKeyScreen(onBack: () => coordinator.pop());
}

// ---------------------------------------------------------------------------
// Coordinator
// ---------------------------------------------------------------------------

final class AppCoordinator extends Coordinator<AppRoute> {
  /// Fixed tab stack — content lives in one IndexedStack so each tab keeps
  /// its scroll position, feed state and widgets alive across switches.
  late final IndexedStackPath<AppRoute> tabs = IndexedStackPath.createWith(
    coordinator: this,
    label: 'tabs',
    [DiscoverTab(), CollectionsTab(), FavoritesTab(), SettingsTab()],
  )..bindLayout(MainShell.new);

  @override
  List<StackPath> get paths => [...super.paths, tabs];

  @override
  AppRoute parseRouteFromUri(Uri uri) => switch (uri.pathSegments) {
    [] || ['discover'] => DiscoverTab(),
    ['collections'] => CollectionsTab(),
    ['favorites'] => FavoritesTab(),
    ['settings'] => SettingsTab(),
    ['settings', 'api-key'] => ApiKeySettingsRoute(),
    ['search'] => SearchRoute(),
    ['wallpaper', final id] => WallpaperDetailRoute(wallpaperId: id),
    ['collections', final id] => CollectionExploreRoute(collectionId: id),
    _ => DiscoverTab(),
  };
}
