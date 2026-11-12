import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:wallpaper_app/app/theme/app_theme.dart';
import 'package:wallpaper_app/app/dependencies.dart';
import 'package:wallpaper_app/app/router/tab_scroll_coordinator.dart';
import 'package:wallpaper_app/core/downloads/download_service.dart';
import 'package:wallpaper_app/core/favorites/favorites_repository.dart';
import 'package:wallpaper_app/core/services/wallpaper_applier.dart';
import 'package:wallpaper_app/core/storage/settings_store.dart';
import 'package:wallpaper_app/core/wallpaper/wallpaper_repository.dart';
import 'package:wallpaper_app/features/favorites/application/favorites_controller.dart';
import 'package:wallpaper_app/features/settings/application/settings_controller.dart';
import 'package:wallpaper_app/features/settings/presentation/api_key_screen.dart';
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
    original: 'https://th.wallhaven.cc/original/x/$id.jpg',
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
    locator.registerSingleton<TabScrollCoordinator>(TabScrollCoordinator());
    // Detail screen probe shares this suite's locator reset; register what
    // Settings needs only.
    var openedApiKey = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          brightness: Brightness.light,
          dynamicScheme: null,
        ),
        home: SettingsScreen(
          onOpenApiKey: () => openedApiKey = true,
          onOpenBlockedTags: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Use dynamic color'), findsOneWidget);
    expect(find.text('Pitch black mode'), findsOneWidget);
    expect(find.text('Show NSFW wallpapers'), findsOneWidget);
    expect(find.text('Blocked tags'), findsOneWidget);
    expect(find.text('Portrait wallpapers only'), findsNothing);
    // Blocked tags addition pushes API key near viewport edge on test size;
    // ensure it's built by scrolling slightly.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('API key'), findsOneWidget);
    expect(find.byType(M3ESwitch), findsNWidgets(3));
    expect(find.byType(M3ESegmentedButton<AppThemeMode>), findsOneWidget);
    // Scroll through the lower Settings groups; the removed About footer and
    // its informational rows must stay absent after the content is built.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Clear image cache'), findsOneWidget);
    expect(find.text('WALLHAVEN ACCOUNT'), findsNothing);
    expect(find.text('ABOUT'), findsNothing);
    expect(find.text('Source'), findsNothing);
    expect(find.text('Open source'), findsNothing);
    // Back to top for NSFW tap
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show NSFW wallpapers'));
    expect(openedApiKey, isTrue);
  });

  testWidgets('api key screen focuses field, toggles visibility, '
      'dismisses keyboard on drag', (tester) async {
    final controller = SettingsController(SettingsStore(), _StubRepository())
      ..restore();
    locator.registerSingleton<SettingsController>(controller);
    locator.registerSingleton<TabScrollCoordinator>(TabScrollCoordinator());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.light),
        home: ApiKeyScreen(onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();

    // Single-purpose input page: the only text field is focused on open.
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);

    // Dragging the form dismisses the keyboard (now CustomScrollView + SliverAppBar).
    final scroll = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(
      scroll.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );

    // Save stays inert with empty input.
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();
    expect(controller.hasApiKey.value, isFalse);
  });

  testWidgets('detail action bar renders without error widget', (tester) async {
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
          theme: AppTheme.build(
            brightness: Brightness.light,
            dynamicScheme: null,
          ),
          home: WallpaperDetailScreen(controller: controller, onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();

      // Detail now uses the expressive WallpaperActionBar group.
      // Verify it is present and no ErrorWidget in tree.
      expect(find.byType(WallpaperActionBar), findsOneWidget);
      expect(find.text('Set'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is ErrorWidget), findsNothing);
    });
  });

  testWidgets('detail uses the listing thumbnail while full image loads', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final wallpaper = _wallpaper('transition1');
      final controller = WallpaperDetailController(
        initial: wallpaper,
        repository: _StubRepository(),
        downloader: DownloadService(),
        applier: WallpaperApplier(),
      );
      addTearDown(controller.dispose);
      final favorites = FavoritesController(FavoritesRepository());
      await favorites.restore();
      locator.registerSingleton<FavoritesController>(favorites);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(
            brightness: Brightness.light,
            dynamicScheme: null,
          ),
          home: WallpaperDetailScreen(controller: controller, onBack: () {}),
        ),
      );

      final fullImageFinder = find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage && widget.imageUrl == wallpaper.path,
      );
      expect(fullImageFinder, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CachedNetworkImage &&
              widget.imageUrl == wallpaper.thumbnails.original,
        ),
        findsOneWidget,
      );
      final fullImage = tester.widget<CachedNetworkImage>(fullImageFinder);
      final loadingPlaceholder = fullImage.placeholder!(
        tester.element(fullImageFinder),
        fullImage.imageUrl,
      );
      expect(loadingPlaceholder, isA<SizedBox>());
    });
  });
}
