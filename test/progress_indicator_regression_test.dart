import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/core/services/wallpaper_applier.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:vanne/features/wallpaper_detail/presentation/widgets/wallpaper_action_bar.dart';
import 'package:vanne/shared/widgets/app_snack.dart';
import 'package:vanne/shared/widgets/wallpaper_grid.dart';

class _StubRepository implements WallpaperRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Wallpaper _wallpaper() => Wallpaper(
  id: 'progress-fixture',
  url: 'https://wallhaven.cc/w/progress-fixture',
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
  path: 'https://example.invalid/progress-fixture.jpg',
  thumbnails: const Thumbnails(),
);

WallpaperDetailController _controller() => WallpaperDetailController(
  initial: _wallpaper(),
  repository: _StubRepository(),
  downloader: DownloadService(),
  applier: WallpaperApplier(),
);

Widget _host(Widget child) => MaterialApp(
  scaffoldMessengerKey: AppSnack.messengerKey,
  theme: AppTheme.build(brightness: Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('feed pagination uses a larger expressive indeterminate loader', (
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
  });

  testWidgets('gallery download uses a large wavy indicator without percent', (
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
    expect(find.textContaining('%'), findsNothing);
    expect(
      tester.getSize(find.byType(M3EProgressIndicator)),
      const Size(30, 30),
    );
    expect(
      tester.getSize(find.byType(M3EIconButton).first),
      const Size(64, 64),
    );
    expect(find.byType(M3ELoadingIndicator), findsNothing);
    expect(
      tester
          .widgetList<M3EIconButton>(find.byType(M3EIconButton))
          .map((button) => button.semanticLabel),
      contains('Downloading wallpaper'),
    );
  });

  testWidgets('unknown gallery download progress stays indeterminate', (
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
    expect(loader.semanticsLabel, isNull);
    expect(find.textContaining('%'), findsNothing);
    expect(
      tester
          .widgetList<M3EIconButton>(find.byType(M3EIconButton))
          .map((button) => button.semanticLabel),
      contains('Downloading wallpaper'),
    );
  });
}
