import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart' hide SearchController;
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/collections/collections_repository.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/services/wallpaper_applier.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/core/storage/settings_store.dart';
import 'package:vanne/core/downloads/download_destination_controller.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/discover/application/discover_controller.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:vanne/features/search/application/search_controller.dart';
import 'package:vanne/features/settings/application/settings_controller.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';

class _StubRepository implements WallpaperRepository {
  _StubRepository({this.items = const []});

  final List<Wallpaper> items;
  Future<Wallpaper>? detailFuture;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

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
      items: items,
      meta: SearchMeta(currentPage: 1, lastPage: 1, perPage: 24),
    ),
    nsfwClamped: false,
  );

  @override
  Future<Wallpaper> wallpaperDetails(String id) =>
      detailFuture ?? Future.value(_wallpaper(id));
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
  colors: const ['#123456'],
  views: 0,
  favorites: 0,
  path: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbnails: Thumbnails(
    small: 'https://th.wallhaven.cc/small/$id.jpg',
    large: 'https://th.wallhaven.cc/lg/$id.jpg',
    original: 'https://w.wallhaven.cc/full/$id.jpg',
  ),
);

Future<void> _registerDependencies({List<Wallpaper> items = const []}) async {
  final repository = _StubRepository(items: items);
  locator.registerSingleton<WallpaperRepository>(repository);
  locator.registerSingleton<FavoritesRepository>(FavoritesRepository());
  final favorites = FavoritesController(locator<FavoritesRepository>());
  await favorites.restore();
  locator.registerSingleton<FavoritesController>(favorites);

  locator.registerSingleton<CollectionsRepository>(CollectionsRepository());
  final collections = CollectionsController(locator<CollectionsRepository>());
  await collections.restore();
  locator.registerSingleton<CollectionsController>(collections);

  locator.registerSingleton<TabScrollCoordinator>(TabScrollCoordinator());
  locator.registerFactory<DiscoverController>(
    () => DiscoverController(repository),
  );
  locator.registerFactory<SearchController>(() => SearchController(repository));
  locator
    ..registerSingleton<SettingsController>(
      SettingsController(SettingsStore(), repository),
    )
    ..registerSingleton<DownloadDestinationController>(
      DownloadDestinationController(SettingsStore()),
    );
  locator
    ..registerLazySingleton<DownloadService>(DownloadService.new)
    ..registerLazySingleton<WallpaperApplier>(WallpaperApplier.new)
    ..registerFactoryParam<WallpaperDetailController, String, Wallpaper?>(
      (id, initial) => WallpaperDetailController(
        initial: initial ?? _wallpaper(id),
        repository: repository,
        downloader: locator<DownloadService>(),
        applier: locator<WallpaperApplier>(),
      ),
    );
}

void main() {
  tearDown(() async => locator.reset());

  test('route constructors encode stable paths and query values', () {
    final detail = WallpaperDetailRoute(wallpaperId: 'abc');
    final filtered = FilteredWallpapersRoute(
      title: '#AABBCC',
      query: 'nature',
      colors: '#AABBCC,#112233',
    );

    expect(detail.rawPathParams['wallpaperId'], 'abc');
    expect(filtered.rawQueryParams, {
      'title': '#AABBCC',
      'q': 'nature',
      'colors': '#AABBCC,#112233',
    });
  });

  test('deep-link paths resolve to the intended route entries', () {
    final router = AppRouter();

    expect(
      router.matcher.match('/collections/lofi')?.last.name,
      CollectionExploreRoute.name,
    );
    expect(
      router.matcher.match('/settings/api-key')?.last.name,
      ApiKeySettingsRoute.name,
    );
    expect(
      router.matcher.match('/filtered?title=nature&q=nature')?.last.name,
      FilteredWallpapersRoute.name,
    );
  });

  test('external modal deep links fall back to the application root', () async {
    expect(
      await appDeepLinkTransformer(Uri.parse('/_modal/feed-filter')),
      Uri.parse('/'),
    );
    expect(
      await appDeepLinkTransformer(Uri.parse('/wallpaper/abc')),
      Uri.parse('/wallpaper/abc'),
    );
  });

  test('metadata responses after detail disposal are ignored', () async {
    final repository = _StubRepository();
    final pending = Completer<Wallpaper>();
    repository.detailFuture = pending.future;
    final controller = WallpaperDetailController(
      initial: _wallpaper('disposed'),
      repository: repository,
      downloader: DownloadService(),
      applier: WallpaperApplier(),
    );
    final loading = controller.loadDetails();

    controller.dispose();
    pending.complete(_wallpaper('disposed'));
    await loading;
  });

  testWidgets('back from a non-home tab switches to Discover before exit', (
    tester,
  ) async {
    await _registerDependencies();
    final router = AppRouter();

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.build(brightness: Brightness.light),
        routerConfig: router.config(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discover'), findsWidgets);

    await tester.tap(find.text('Favorites').last);
    await tester.pumpAndSettle();
    expect(find.text('No favorites yet'), findsOneWidget);

    final settingsRoute = router.push(const ApiKeySettingsRoute());
    await tester.pumpAndSettle();
    expect(find.byType(ApiKeySettingsPage), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await settingsRoute;
    await tester.pumpAndSettle();
    expect(find.byType(ApiKeySettingsPage), findsNothing);
    expect(find.text('No favorites yet'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Discover'), findsWidgets);

    for (final entry in {
      'Collections': 1,
      'Favorites': 2,
      'Settings': 3,
    }.entries) {
      await tester.tap(find.text(entry.key).last);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is M3ENavigationBar && widget.selectedIndex == entry.value,
        ),
        findsOneWidget,
      );

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is M3ENavigationBar && widget.selectedIndex == 0,
        ),
        findsOneWidget,
      );
    }

    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('a routed dialog is popped before its underlying page', (
    tester,
  ) async {
    await _registerDependencies();
    final router = AppRouter();

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.build(brightness: Brightness.light),
        routerConfig: router.config(),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = router.push<void>(const CreateCollectionDialogRoute());
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    expect(await router.maybePopTop(), isTrue);
    await dialog;
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Discover'), findsWidgets);
  });

  testWidgets('a deep-linked child route keeps the tab shell underneath', (
    tester,
  ) async {
    await _registerDependencies();
    final router = AppRouter();

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.build(brightness: Brightness.light),
        routerConfig: router.config(includePrefixMatches: true),
      ),
    );
    await tester.pumpAndSettle();

    await router.navigatePath('/settings/api-key', includePrefixMatches: true);
    await tester.pumpAndSettle();

    expect(find.byType(MainShellPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(ApiKeySettingsPage), findsOneWidget);
  });

  testWidgets('system back from search returns through the shared Hero route', (
    tester,
  ) async {
    await _registerDependencies();
    final router = AppRouter();

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.build(brightness: Brightness.light),
        routerConfig: router.config(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(M3ESearchBar));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == 'search-bar-hero',
      ),
      findsOneWidget,
    );

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsNothing);
    expect(find.byType(MainShellPage), findsOneWidget);
  });

  testWidgets('Set Wallpaper closes without popping the detail route', (
    tester,
  ) async {
    await _registerDependencies();
    final router = AppRouter();
    final wallpaper = _wallpaper('detail');
    final dialogController = WallpaperDetailController(
      initial: wallpaper,
      repository: locator<WallpaperRepository>(),
      downloader: locator<DownloadService>(),
      applier: locator<WallpaperApplier>(),
    );
    addTearDown(dialogController.dispose);

    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.build(brightness: Brightness.light),
          routerConfig: router.config(),
        ),
      );
      await tester.pumpAndSettle();

      final detail = router.push(
        WallpaperDetailRoute(
          wallpaperId: wallpaper.id,
          initial: wallpaper,
          heroScope: 'discover-',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WallpaperDetailPage), findsOneWidget);

      final dialog = router.push<void>(
        SetWallpaperDialogRoute(controller: dialogController),
      );
      await tester.pumpAndSettle();
      expect(find.text('Set wallpaper'), findsOneWidget);

      expect(await router.maybePopTop(), isTrue);
      await dialog;
      await tester.pumpAndSettle();
      expect(find.text('Set wallpaper'), findsNothing);
      expect(find.byType(WallpaperDetailPage), findsOneWidget);

      router.pop();
      await detail;
    });
  });

  testWidgets('a wallpaper tile reaches detail through a Hero-capable route', (
    tester,
  ) async {
    final wallpaper = _wallpaper('hero');
    await _registerDependencies(items: [wallpaper]);
    final router = AppRouter();

    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.build(brightness: Brightness.light),
          routerConfig: router.config(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wallpaper-tile-hero')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('wallpaper-tile-hero')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(WallpaperDetailPage), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == 'wallpaper-discover-hero',
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wallpaper-tile-hero')), findsOneWidget);
    });
  });
}
