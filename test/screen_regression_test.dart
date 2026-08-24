import 'package:flutter_test/flutter_test.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:wallpaper_app/app/theme/app_theme.dart';
import 'package:wallpaper_app/app/dependencies.dart';
import 'package:wallpaper_app/core/downloads/download_service.dart';
import 'package:wallpaper_app/core/favorites/favorites_repository.dart';
import 'package:wallpaper_app/core/services/wallpaper_applier.dart';
import 'package:wallpaper_app/core/storage/settings_store.dart';
import 'package:wallpaper_app/core/wallpaper/wallpaper_repository.dart';
import 'package:wallpaper_app/features/favorites/application/favorites_controller.dart';
import 'package:wallpaper_app/features/settings/application/settings_controller.dart';
import 'package:wallpaper_app/features/settings/presentation/settings_screen.dart';
import 'package:wallpaper_app/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:wallpaper_app/features/wallpaper_detail/presentation/wallpaper_detail_screen.dart';
import 'package:wallpaper_app/features/wallpaper_detail/presentation/widgets/wallpaper_action_bar.dart';

/// Regression probes for two device-only breakages observed on hardware:
/// 1. the Settings tab rendering blank,
/// 2. the download arch action on the detail screen rendering Flutter's
///    error widget.
///
/// Both screens are pumped inside a real M3E theme; any build-time
/// exception fails these tests with the actual stack trace, which
/// `flutter run` on-device hides behind a blank/error surface.

class _StubRepository implements WallpaperRepository {
  @override
  bool get isAuthenticated => false;

  @override
  Future<Wallpaper> wallpaperDetails(String id) async => _wallpaper(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  url: 'https://wallhaven.cc/w/$id',
  source: '',
  purity: Purity.sfw,
  category: Category.general,
  width: 1080,
  height: 2400,
  resolution: '1080x2400',
  ratio: '0.45',
  fileSizeBytes: 3 * 1024 * 1024,
  fileType: 'image/jpeg',
  colors: const ['#6655AA'],
  views: 10,
  favorites: 7,
  path: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbnails: Thumbnails(
    small: 'https://th.wallhaven.cc/small/x/$id.jpg',
    large: 'https://th.wallhaven.cc/lg/x/$id.jpg',
  ),
  uploader: const Uploader(username: 'tester'),
  tags: const [Tag(id: 1, name: 'test')],
);

void main() {
  tearDown(() async {
    await locator.reset();
  });

  testWidgets('settings screen renders every row without exceptions', (
    tester,
  ) async {
    final controller = SettingsController(SettingsStore(), _StubRepository())
      ..restore();
    locator.registerSingleton<SettingsController>(controller);
    // Detail screen probe shares this suite's locator reset; register what
    // Settings needs only.
    var openedApiKey = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.light, dynamicScheme: null),
        home: SettingsScreen(onOpenApiKey: () => openedApiKey = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Use dynamic color'), findsOneWidget);
    expect(find.text('Pitch black mode'), findsOneWidget);
    expect(find.text('Show NSFW wallpapers'), findsOneWidget);
    expect(find.text('Portrait wallpapers only'), findsNothing);
    expect(find.text('API key'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));
    expect(find.byType(SegmentedButton<AppThemeMode>), findsOneWidget);
    // Scroll to reveal About footer (CustomScrollView with SliverAppBar — was ListView).
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();
    // About footer — wallhaven source, open source.
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Open source'), findsOneWidget);
    // Back to top for NSFW tap
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show NSFW wallpapers'));
    expect(openedApiKey, isTrue);
  });

  testWidgets('detail action bar renders without error widget', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final controller = WallpaperDetailController(
        initial: _wallpaper('probe1'),
        repository: _StubRepository(),
        downloader: DownloadService(),
        applier: WallpaperApplier(),
      );
      final favorites = FavoritesController(FavoritesRepository());
      await favorites.restore();
      locator.registerSingleton<FavoritesController>(favorites);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: Brightness.light, dynamicScheme: null),
          home: WallpaperDetailScreen(controller: controller, onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();

      // Detail now uses the expressive WallpaperActionBar group with
      // Material icons. Verify it is present and no ErrorWidget in tree.
      expect(find.byType(WallpaperActionBar), findsOneWidget);
      expect(find.byIcon(BootstrapIcons.cloud_arrow_down_fill), findsOneWidget);
      expect(find.byIcon(BootstrapIcons.image_fill), findsOneWidget);
      expect(find.byIcon(BootstrapIcons.arrow_up_right_square_fill), findsOneWidget);
      expect(find.text('Set'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is ErrorWidget),
        findsNothing,
      );
    });
  });
}
