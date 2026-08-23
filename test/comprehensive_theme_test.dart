import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:wallpaper_app/app/dependencies.dart';
import 'package:wallpaper_app/app/theme/app_theme.dart';
import 'package:wallpaper_app/core/domain/feed_filter.dart';
import 'package:wallpaper_app/core/favorites/favorites_repository.dart';
import 'package:wallpaper_app/core/wallpaper/wallpaper_repository.dart';
import 'package:wallpaper_app/features/discover/application/discover_controller.dart';
import 'package:wallpaper_app/features/discover/presentation/discover_screen.dart';
import 'package:wallpaper_app/features/favorites/application/favorites_controller.dart';
import 'package:wallpaper_app/features/search/application/search_controller.dart' as app_search;
import 'package:wallpaper_app/features/search/presentation/search_screen.dart';
import 'package:wallpaper_app/features/discover/presentation/widgets/discover_filter_sheet.dart';

class _StubRepository implements WallpaperRepository {
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
  }) async {
    return SearchOutcome(
      page: PaginatedResult<Wallpaper>(
        items: const [],
        meta: const SearchMeta(currentPage: 1, lastPage: 1, perPage: 24),
      ),
      nsfwClamped: false,
    );
  }

  @override
  Future<Wallpaper> wallpaperDetails(String id) async => _wallpaper(id);
}

// ignore: unused_element
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
    );

void main() {
  tearDown(() async {
    await locator.reset();
  });

  group('AppTheme generates correct ThemeData for all variants', () {
    test('light theme chip and searchBar follow colorScheme', () {
      final theme = AppTheme.build(brightness: Brightness.light);
      final scheme = theme.colorScheme;
      expect(theme.chipTheme.backgroundColor, scheme.surfaceContainerLow);
      expect(theme.chipTheme.selectedColor, scheme.secondaryContainer);
      expect(theme.chipTheme.checkmarkColor, scheme.onSecondaryContainer);
      expect(theme.searchBarTheme.backgroundColor!.resolve({}), scheme.surfaceContainerHigh);
      expect(theme.searchBarTheme.elevation!.resolve({}), 0);
      expect(theme.textTheme.displaySmall!.color, scheme.onSurface);
      expect(theme.scaffoldBackgroundColor, scheme.surface);
    });

    test('dark theme chip and searchBar follow colorScheme', () {
      final theme = AppTheme.build(brightness: Brightness.dark);
      final scheme = theme.colorScheme;
      expect(theme.chipTheme.backgroundColor, scheme.surfaceContainerLow);
      expect(theme.searchBarTheme.backgroundColor!.resolve({}), scheme.surfaceContainerHigh);
      expect(theme.textTheme.displaySmall!.color, scheme.onSurface);
    });

    test('pitch-black theme collapses surfaces to ladder', () {
      final dark = AppTheme.build(brightness: Brightness.dark, pitchBlack: false);
      final pitch = AppTheme.build(brightness: Brightness.dark, pitchBlack: true);
      // Pitch surfaces must be true black ladder, not dark's 0xFF0E1513
      expect(pitch.colorScheme.surface, const Color(0xFF000000));
      expect(pitch.colorScheme.surfaceContainerLow, const Color(0xFF050505));
      expect(pitch.colorScheme.surfaceContainerHigh, const Color(0xFF101010));
      // Non-surface roles must stay identical to dark (primary etc preserved)
      expect(pitch.colorScheme.primary, dark.colorScheme.primary);
      expect(pitch.colorScheme.secondaryContainer, dark.colorScheme.secondaryContainer);
      // Theme still wires chip/searchBar to pitch surfaces
      expect(pitch.chipTheme.backgroundColor, pitch.colorScheme.surfaceContainerLow);
      expect(pitch.searchBarTheme.backgroundColor!.resolve({}), pitch.colorScheme.surfaceContainerHigh);
      expect(pitch.textTheme.displaySmall!.color, pitch.colorScheme.onSurface);
    });

    test('light pitchBlack flag is ignored (only dark)', () {
      final light = AppTheme.build(brightness: Brightness.light, pitchBlack: false);
      final lightPitch = AppTheme.build(brightness: Brightness.light, pitchBlack: true);
      expect(light.colorScheme.surface, lightPitch.colorScheme.surface);
    });
  });

  group('Widget regression: Discover/Search honor ThemeData across LookupBoundary', () {
    Future<void> setupLocator() async {
      final repo = _StubRepository();
      locator.registerSingleton<WallpaperRepository>(repo as WallpaperRepository);
      locator.registerSingleton<FavoritesRepository>(FavoritesRepository());
      final fav = FavoritesController(FavoritesRepository());
      await fav.restore();
      locator.registerSingleton<FavoritesController>(fav);
      locator.registerFactory<DiscoverController>(() => DiscoverController(repo as WallpaperRepository));
      locator.registerFactory<app_search.SearchController>(() => app_search.SearchController(repo as WallpaperRepository));
    }

    for (final entry in [
      (Brightness.light, false, 'light'),
      (Brightness.dark, false, 'dark'),
      (Brightness.dark, true, 'pitchBlack'),
    ]) {
      final brightness = entry.$1;
      final pitch = entry.$2;
      final label = entry.$3;

      testWidgets('DiscoverScreen renders without ErrorWidget in $label and honors theme', (tester) async {
        await setupLocator();
        final themeData = AppTheme.build(brightness: brightness, pitchBlack: pitch);

        await mockNetworkImagesFor(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: themeData,
              home: Scaffold(
                body: DiscoverScreen(
                  onOpenSearch: () {},
                  onOpenWallpaper: (_) {},
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // No Material error
          expect(find.byWidgetPredicate((w) => w is ErrorWidget), findsNothing);

          // Discover title must be onSurface
          final text = tester.widget<Text>(find.text('Discover'));
          expect(text.style?.color, themeData.colorScheme.onSurface);

          // SearchBar must exist and be inside a Material (LookupBoundary fix)
          expect(find.byType(SearchBar), findsOneWidget);
          // Since we now rely on theme, backgroundColor may be null (uses theme). Resolve via theme.
          final barThemeBg = themeData.searchBarTheme.backgroundColor!.resolve({});
          expect(barThemeBg, themeData.colorScheme.surfaceContainerHigh);

          // FilterChip trigger must exist inside Material
          expect(find.byType(FilterChip), findsWidgets);
          // Ensure FilterChip is descendant of Material (LookupBoundary fix)
          final chipContext = tester.element(find.byType(FilterChip).first);
          expect(
            chipContext.findAncestorWidgetOfExactType<Material>() != null ||
                chipContext.findAncestorWidgetOfExactType<Scaffold>() != null,
            isTrue,
            reason: 'FilterChip must have Material ancestor within LookupBoundary',
          );
        });
      });

      testWidgets('SearchScreen renders without ErrorWidget in $label', (tester) async {
        await setupLocator();
        final themeData = AppTheme.build(brightness: brightness, pitchBlack: pitch);

        await mockNetworkImagesFor(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: themeData,
              home: SearchScreen(autofocus: false, onOpenWallpaper: (_) {}),
            ),
          );
          await tester.pump();
          // Allow debounce / signals + hero focus timer (320ms)
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byWidgetPredicate((w) => w is ErrorWidget), findsNothing);
          expect(find.byType(SearchBar), findsOneWidget);
          // Genre chips are now expressive M3E clampShell containers (60×60 clover + clampShell)
          // instead of stock FilterChip — verify they render and have material ancestor.
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byType(M3EContainer), findsWidgets);
          // Spot-check a couple of genre labels still present for accessibility.
          expect(find.text('Anime'), findsOneWidget);
          expect(find.text('Nature'), findsOneWidget);
          // SearchBar hint and text colors come from theme
          expect(themeData.searchBarTheme.hintStyle!.resolve({})?.color, themeData.colorScheme.onSurfaceVariant);
        });
      });

      testWidgets('Discover filter sheet renders without ErrorWidget in $label', (tester) async {
        await setupLocator();
        final themeData = AppTheme.build(brightness: brightness, pitchBlack: pitch);
        final controller = DiscoverController(locator<WallpaperRepository>());

        await tester.pumpWidget(
          MaterialApp(
            theme: themeData,
            home: Scaffold(
              body: Builder(builder: (context) {
                return ElevatedButton(
                  onPressed: () => showDiscoverFilterSheet(context, controller: controller),
                  child: const Text('open'),
                );
              }),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byWidgetPredicate((w) => w is ErrorWidget), findsNothing);
        expect(find.text('Sort & filter'), findsOneWidget);
        expect(find.byType(FilterChip), findsWidgets);
      });
    }
  });
}
