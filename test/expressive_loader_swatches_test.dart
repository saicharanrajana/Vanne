import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:vanne/features/search/application/search_controller.dart'
    as app_search;
import 'package:vanne/features/search/presentation/search_screen.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:vanne/features/wallpaper_detail/presentation/widgets/set_wallpaper_sheet.dart';
import 'package:vanne/features/wallpaper_detail/presentation/widgets/wallpaper_action_bar.dart';
import 'package:vanne/shared/widgets/app_snack.dart';
import 'package:vanne/shared/widgets/wallpaper_grid.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/core/services/wallpaper_applier.dart';

class _RecordingRepository implements WallpaperRepository {
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
  }) async => const SearchOutcome(
    page: PaginatedResult<Wallpaper>(
      items: [],
      meta: SearchMeta(currentPage: 1, lastPage: 1, perPage: 24),
    ),
    nsfwClamped: false,
  );
}

Wallpaper _wallpaper() => Wallpaper(
  id: 'loader-swatch-fixture',
  url: 'https://wallhaven.cc/w/loader-swatch-fixture',
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
  path: 'https://example.invalid/loader-swatch-fixture.jpg',
  thumbnails: const Thumbnails(),
);

WallpaperDetailController _controller() => WallpaperDetailController(
  initial: _wallpaper(),
  repository: _RecordingRepository(),
  downloader: DownloadService(),
  applier: WallpaperApplier(),
);

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      scaffoldMessengerKey: AppSnack.messengerKey,
      theme: AppTheme.build(brightness: brightness),
      home: Scaffold(body: child),
    );

Future<void> _pumpSearch(
  WidgetTester tester, {
  required Brightness brightness,
}) async {
  final repository = _RecordingRepository();
  final favorites = FavoritesController(FavoritesRepository());
  await favorites.restore();
  final search = app_search.SearchController(repository);
  locator
    ..registerSingleton<WallpaperRepository>(repository)
    ..registerSingleton<FavoritesController>(favorites)
    ..registerSingleton<TabScrollCoordinator>(TabScrollCoordinator())
    ..registerSingleton<app_search.SearchController>(search);
  await mockNetworkImagesFor(() async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: brightness),
        home: SearchScreen(autofocus: false, onOpenWallpaper: (_) {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  });
}

void main() {
  tearDown(() async => locator.reset());

  testWidgets('feed pagination uses the larger Material expressive loader', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        WallpaperGrid(
          items: [_wallpaper()],
          onOpen: (_) {},
          isLoadingMore: true,
        ),
      ),
    );

    final loader = tester.widget<M3ELoadingIndicator>(
      find.byType(M3ELoadingIndicator),
    );
    expect(loader.semanticLabel, 'Loading more wallpapers');
    expect(loader.variant, M3ELoadingIndicatorVariant.defaultStyle);
    expect(
      tester.getSize(find.byType(M3ELoadingIndicator)),
      const Size(36, 36),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('gallery download uses wavy progress without percentage text', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.download.set(const DownloadState.downloading(0.42));

    await tester.pumpWidget(_host(WallpaperActionBar(controller: controller)));

    final loader = tester.widget<M3EProgressIndicator>(
      find.byType(M3EProgressIndicator),
    );
    expect(loader.value, 0.42);
    expect(loader.semanticsLabel, isNull);
    expect(loader.size, 30);
    expect(find.textContaining('%'), findsNothing);
    expect(
      tester
          .widgetList<M3EIconButton>(find.byType(M3EIconButton))
          .map((button) => button.semanticLabel),
      contains('Downloading wallpaper'),
    );
  });

  testWidgets(
    'preparing and applying branches render valid expressive loaders',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);

      controller.prepare.set(const PrepareState.resolving());
      await tester.pumpWidget(
        _host(WallpaperActionBar(controller: controller)),
      );
      var loader = tester.widget<M3ELoadingIndicator>(
        find.byType(M3ELoadingIndicator),
      );
      expect(loader.containerWidth, 24);
      expect(loader.containerHeight, 24);
      expect(loader.indicatorSize, 18);
      expect(
        tester.getSize(find.byType(M3ELoadingIndicator)),
        const Size(24, 24),
      );
      expect(tester.takeException(), isNull);

      controller.apply.set(const ApplyState.applying(ApplyTarget.home));
      await tester.pumpWidget(
        _host(SetWallpaperDialog(controller: controller)),
      );
      loader = tester.widget<M3ELoadingIndicator>(
        find.byType(M3ELoadingIndicator),
      );
      expect(loader.containerWidth, 24);
      expect(loader.containerHeight, 24);
      expect(loader.indicatorSize, 18);
      expect(
        tester.getSize(find.byType(M3ELoadingIndicator)),
        const Size(24, 24),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown download progress stays unknown without false zero', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.download.set(const DownloadState.downloading());

    await tester.pumpWidget(_host(WallpaperActionBar(controller: controller)));

    final loader = tester.widget<M3EProgressIndicator>(
      find.byType(M3EProgressIndicator),
    );
    expect(loader.value, isNull);
    expect(loader.size, 30);
    expect(find.text('0%'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(
      tester
          .widgetList<M3EIconButton>(find.byType(M3EIconButton))
          .map((button) => button.semanticLabel),
      contains('Downloading wallpaper'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Search swatches grow while retaining 48dp targets and selection',
    (tester) async {
      await _pumpSearch(tester, brightness: Brightness.light);
      final black = find.byKey(const ValueKey('search-color-black'));
      expect(tester.getSize(black), const Size(48, 48));

      expect(
        tester.getSize(
          find.descendant(of: black, matching: find.byType(AnimatedContainer)),
        ),
        const Size(44, 44),
      );

      await tester.tap(black);
      await tester.pump(const Duration(milliseconds: 160));
      final semantics = tester.getSemantics(black);
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
      expect(
        tester.getSize(
          find.descendant(of: black, matching: find.byType(AnimatedContainer)),
        ),
        const Size(46, 46),
      );
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('search-color-check')))
            .size,
        18,
      );
    },
  );
}
