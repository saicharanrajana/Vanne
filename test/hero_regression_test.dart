import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide SearchController;
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/discover/application/discover_controller.dart';
import 'package:vanne/features/discover/presentation/discover_screen.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:vanne/features/search/application/search_controller.dart';
import 'package:vanne/features/search/presentation/search_screen.dart';
import 'package:vanne/shared/widgets/wallpaper_tile.dart';

class _StubRepo implements WallpaperRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  Future<SearchOutcome> search({
    String query = '',
    Set<WallhavenColor> colors = const {},
    List<WallhavenCategory> categories = const [],
    FeedFilter filter = const FeedFilter(),
    int page = 1,
    String? seed,
  }) async => SearchOutcome(
    page: PaginatedResult<Wallpaper>(
      items: const [],
      meta: const SearchMeta(currentPage: 1, lastPage: 1, perPage: 24),
    ),
    nsfwClamped: false,
  );
  @override
  Future<Wallpaper> wallpaperDetails(String id) async => _wallpaper(id);
}

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  url: 'https://wallhaven.cc/w/$id',
  source: '',
  purity: Purity.sfw,
  category: Category.general,
  width: 1080,
  height: 1920,
  resolution: '1080x1920',
  ratio: '0.56',
  fileSizeBytes: 1000,
  fileType: 'image/jpeg',
  colors: const [],
  views: 0,
  favorites: 0,
  path: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbnails: Thumbnails(
    small: 'https://th.wallhaven.cc/small/$id.jpg',
    large: 'https://th.wallhaven.cc/lg/$id.jpg',
  ),
);

void main() {
  tearDown(() async => locator.reset());

  test('WallpaperTile and detail share hero tag pattern', () {
    const heroScope = 'discover-';
    const id = 'abc123';
    final wallpaper = _wallpaper(id);
    final tile = WallpaperTile(
      wallpaper: wallpaper,
      heroScope: heroScope,
      onOpen: () {},
    );
    expect(tile.heroTag, 'wallpaper-$heroScope$id');
  });

  test('generated routes carry typed navigation arguments', () {
    final search = SearchRoute(query: 'test');
    final detail = WallpaperDetailRoute(
      wallpaperId: 'abc',
      heroScope: 'discover-',
    );
    expect(search.routeName, 'SearchRoute');
    expect(search.rawQueryParams['q'], 'test');
    expect(detail.routeName, 'WallpaperDetailRoute');
    expect(detail.rawPathParams['wallpaperId'], 'abc');
  });

  testWidgets('Discover SearchBar hero exists and SearchScreen hero matches', (
    tester,
  ) async {
    await locator.reset();
    final repo = _StubRepo();
    locator.registerSingleton<WallpaperRepository>(repo as WallpaperRepository);
    locator.registerSingleton<FavoritesRepository>(FavoritesRepository());
    final fav = FavoritesController(FavoritesRepository());
    await fav.restore();
    locator.registerSingleton<FavoritesController>(fav);
    locator.registerSingleton<TabScrollCoordinator>(TabScrollCoordinator());
    locator.registerFactory<DiscoverController>(
      () => DiscoverController(repo as WallpaperRepository),
    );
    locator.registerFactory<SearchController>(
      () => SearchController(repo as WallpaperRepository),
    );

    const heroTag = 'search-bar-hero';

    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: Brightness.light),
          home: Scaffold(
            body: DiscoverScreen(onOpenSearch: () {}, onOpenWallpaper: (_) {}),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate((w) => w is Hero && w.tag == heroTag),
        findsOneWidget,
      );
      final discoverHero = tester.widget<Hero>(
        find.byWidgetPredicate((w) => w is Hero && w.tag == heroTag),
      );
      expect(discoverHero.flightShuttleBuilder, isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: Brightness.light),
          home: SearchScreen(autofocus: false, onOpenWallpaper: (_) {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byWidgetPredicate((w) => w is Hero && w.tag == heroTag),
        findsOneWidget,
      );
      final searchHero = tester.widget<Hero>(
        find.byWidgetPredicate((w) => w is Hero && w.tag == heroTag),
      );
      expect(searchHero.tag, heroTag);
      expect(searchHero.flightShuttleBuilder, isNotNull);

      final theme = AppTheme.build(brightness: Brightness.light);
      expect(theme.scaffoldBackgroundColor, isNot(Colors.white));
    });
  });

  testWidgets('WallpaperTile renders Hero with correct tag inside grid', (
    tester,
  ) async {
    final wallpaper = _wallpaper('hero123');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.light),
        home: Scaffold(
          body: WallpaperTile(
            wallpaper: wallpaper,
            heroScope: 'discover-',
            onOpen: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'wallpaper-discover-hero123',
      ),
      findsOneWidget,
    );
    final hero = tester.widget<Hero>(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'wallpaper-discover-hero123',
      ),
    );
    expect(hero.flightShuttleBuilder, isNotNull);
  });

  test('AppTheme scaffold is opaque and not white (no flash)', () {
    final light = AppTheme.build(brightness: Brightness.light);
    final dark = AppTheme.build(brightness: Brightness.dark);
    final pitch = AppTheme.build(brightness: Brightness.dark, pitchBlack: true);
    for (final t in [light, dark, pitch]) {
      expect(
        t.scaffoldBackgroundColor.a,
        closeTo(1.0, 0.01),
        reason: 'scaffold must be opaque to hide window white',
      );
      expect(t.scaffoldBackgroundColor, t.colorScheme.surface);
    }
    expect(light.scaffoldBackgroundColor, isNot(Colors.white));
  });
}
