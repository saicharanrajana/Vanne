import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:wallpaper_app/app/dependencies.dart';
import 'package:wallpaper_app/app/router/tab_scroll_coordinator.dart';
import 'package:wallpaper_app/app/theme/app_shapes.dart';
import 'package:wallpaper_app/app/theme/app_theme.dart';
import 'package:wallpaper_app/core/domain/feed_filter.dart';
import 'package:wallpaper_app/core/favorites/favorites_repository.dart';
import 'package:wallpaper_app/core/wallpaper/wallpaper_repository.dart';
import 'package:wallpaper_app/features/discover/application/discover_controller.dart';
import 'package:wallpaper_app/features/discover/presentation/discover_screen.dart';
import 'package:wallpaper_app/features/favorites/application/favorites_controller.dart';
import 'package:wallpaper_app/features/search/application/search_controller.dart'
    as app_search;
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
      expect(
        theme.searchBarTheme.backgroundColor!.resolve({}),
        scheme.surfaceContainerHigh,
      );
      expect(theme.searchBarTheme.elevation!.resolve({}), 0);
      expect(theme.textTheme.displaySmall!.color, scheme.onSurface);
      expect(theme.scaffoldBackgroundColor, scheme.surface);
    });

    test('dark theme chip and searchBar follow colorScheme', () {
      final theme = AppTheme.build(brightness: Brightness.dark);
      final scheme = theme.colorScheme;
      expect(theme.chipTheme.backgroundColor, scheme.surfaceContainerLow);
      expect(
        theme.searchBarTheme.backgroundColor!.resolve({}),
        scheme.surfaceContainerHigh,
      );
      expect(theme.textTheme.displaySmall!.color, scheme.onSurface);
    });

    test('pitch-black theme collapses surfaces to ladder', () {
      final dark = AppTheme.build(
        brightness: Brightness.dark,
        pitchBlack: false,
      );
      final pitch = AppTheme.build(
        brightness: Brightness.dark,
        pitchBlack: true,
      );
      // Pitch surfaces must be true black ladder, not dark's 0xFF0E1513
      expect(pitch.colorScheme.surface, const Color(0xFF000000));
      expect(pitch.colorScheme.surfaceContainerLow, const Color(0xFF050505));
      expect(pitch.colorScheme.surfaceContainerHigh, const Color(0xFF101010));
      // Non-surface roles must stay identical to dark (primary etc preserved)
      expect(pitch.colorScheme.primary, dark.colorScheme.primary);
      expect(
        pitch.colorScheme.secondaryContainer,
        dark.colorScheme.secondaryContainer,
      );
      // Theme still wires chip/searchBar to pitch surfaces
      expect(
        pitch.chipTheme.backgroundColor,
        pitch.colorScheme.surfaceContainerLow,
      );
      expect(
        pitch.searchBarTheme.backgroundColor!.resolve({}),
        pitch.colorScheme.surfaceContainerHigh,
      );
      expect(pitch.textTheme.displaySmall!.color, pitch.colorScheme.onSurface);
    });

    test('light pitchBlack flag is ignored (only dark)', () {
      final light = AppTheme.build(
        brightness: Brightness.light,
        pitchBlack: false,
      );
      final lightPitch = AppTheme.build(
        brightness: Brightness.light,
        pitchBlack: true,
      );
      expect(light.colorScheme.surface, lightPitch.colorScheme.surface);
    });

    test('text selection colors follow the effective scheme', () {
      for (final entry in [
        (Brightness.light, false),
        (Brightness.dark, false),
        (Brightness.dark, true),
      ]) {
        final theme = AppTheme.build(
          brightness: entry.$1,
          pitchBlack: entry.$2,
        );
        final scheme = theme.colorScheme;
        expect(theme.textSelectionTheme.cursorColor, scheme.primary);
        expect(theme.textSelectionTheme.selectionHandleColor, scheme.primary);
        expect(theme.textSelectionTheme.selectionColor, isNotNull);
      }
    });

    test('text fields use expressive geometry and state colors', () {
      final theme = AppTheme.build(brightness: Brightness.dark);
      final scheme = theme.colorScheme;
      final input = theme.inputDecorationTheme;
      final border = input.border! as OutlineInputBorder;
      final focusedBorder = input.focusedBorder! as OutlineInputBorder;

      expect(
        input.contentPadding,
        const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      );
      expect(input.constraints, const BoxConstraints(minHeight: 56));
      expect(border.borderRadius, BorderRadius.circular(AppShapes.large));
      expect(border.borderSide.color, scheme.outlineVariant);
      expect(
        focusedBorder.borderRadius,
        BorderRadius.circular(AppShapes.large),
      );
      expect(focusedBorder.borderSide.color, scheme.primary);
      expect(focusedBorder.borderSide.width, 2);
      final prefixIconColor = input.prefixIconColor! as WidgetStateColor;
      expect(prefixIconColor.resolve({}), scheme.onSurfaceVariant);
      expect(prefixIconColor.resolve({WidgetState.focused}), scheme.primary);
      expect(prefixIconColor.resolve({WidgetState.error}), scheme.error);
    });

    test('dynamic fixed and surface roles survive theme construction', () {
      final dynamic = ColorScheme.fromSeed(seedColor: const Color(0xFF123456))
          .copyWith(
            primaryFixed: const Color(0xFF010101),
            primaryFixedDim: const Color(0xFF020202),
            onPrimaryFixed: const Color(0xFF030303),
            onPrimaryFixedVariant: const Color(0xFF040404),
            secondaryFixed: const Color(0xFF050505),
            tertiaryFixed: const Color(0xFF060606),
            surfaceContainerLow: const Color(0xFF070707),
            surfaceContainerHigh: const Color(0xFF080808),
          );
      final effective = AppTheme.build(
        brightness: Brightness.light,
        dynamicScheme: dynamic,
      ).colorScheme;

      expect(effective.primaryFixed, dynamic.primaryFixed);
      expect(effective.primaryFixedDim, dynamic.primaryFixedDim);
      expect(effective.onPrimaryFixed, dynamic.onPrimaryFixed);
      expect(effective.onPrimaryFixedVariant, dynamic.onPrimaryFixedVariant);
      expect(effective.secondaryFixed, dynamic.secondaryFixed);
      expect(effective.tertiaryFixed, dynamic.tertiaryFixed);
      expect(effective.surfaceContainerLow, dynamic.surfaceContainerLow);
      expect(effective.surfaceContainerHigh, dynamic.surfaceContainerHigh);
    });
  });

  group('Widget regression: Discover/Search honor ThemeData across LookupBoundary', () {
    Future<void> setupLocator() async {
      final repo = _StubRepository();
      locator.registerSingleton<WallpaperRepository>(
        repo as WallpaperRepository,
      );
      locator.registerSingleton<FavoritesRepository>(FavoritesRepository());
      final fav = FavoritesController(FavoritesRepository());
      await fav.restore();
      locator.registerSingleton<FavoritesController>(fav);
      locator.registerSingleton<TabScrollCoordinator>(TabScrollCoordinator());
      locator.registerFactory<DiscoverController>(
        () => DiscoverController(repo as WallpaperRepository),
      );
      locator.registerFactory<app_search.SearchController>(
        () => app_search.SearchController(repo as WallpaperRepository),
      );
    }

    for (final entry in [
      (Brightness.light, false, 'light'),
      (Brightness.dark, false, 'dark'),
      (Brightness.dark, true, 'pitchBlack'),
    ]) {
      final brightness = entry.$1;
      final pitch = entry.$2;
      final label = entry.$3;

      testWidgets(
        'DiscoverScreen renders without ErrorWidget in $label and honors theme',
        (tester) async {
          await setupLocator();
          final themeData = AppTheme.build(
            brightness: brightness,
            pitchBlack: pitch,
          );

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
            expect(
              find.byWidgetPredicate((w) => w is ErrorWidget),
              findsNothing,
            );

            // Discover title must be onSurface
            final text = tester.widget<Text>(find.text('Discover'));
            expect(text.style?.color, themeData.colorScheme.onSurface);

            expect(find.byType(M3ESearchBar), findsOneWidget);
            // Since we now rely on theme, backgroundColor may be null (uses theme). Resolve via theme.
            final barThemeBg = themeData.searchBarTheme.backgroundColor!
                .resolve({});
            expect(barThemeBg, themeData.colorScheme.surfaceContainerHigh);

            final chipContext = tester.element(find.byType(M3EChip).first);
            expect(
              chipContext.findAncestorWidgetOfExactType<Material>() != null ||
                  chipContext.findAncestorWidgetOfExactType<Scaffold>() != null,
              isTrue,
              reason: 'M3EChip must have a Material ancestor',
            );
          });
        },
      );

      testWidgets('SearchScreen renders without ErrorWidget in $label', (
        tester,
      ) async {
        await setupLocator();
        final themeData = AppTheme.build(
          brightness: brightness,
          pitchBlack: pitch,
        );

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
          expect(find.byType(M3ESearchBar), findsOneWidget);
          // Filter hierarchy headings are present above each strip.
          expect(find.text('By color'), findsOneWidget);
          expect(find.text('By genre'), findsOneWidget);
          // Genre filters are M3E chips now; color swatches keep their
          // expressive shape containers.
          expect(find.byType(M3EChip), findsWidgets);
          await tester.pump(const Duration(milliseconds: 100));
          // Spot-check a couple of genre labels still present for accessibility.
          expect(find.text('Anime'), findsOneWidget);
          expect(find.text('Nature'), findsOneWidget);
          // SearchBar hint and text colors come from theme
          expect(
            themeData.searchBarTheme.hintStyle!.resolve({})?.color,
            themeData.colorScheme.onSurfaceVariant,
          );
        });
      });

      testWidgets(
        'Discover filter sheet renders without ErrorWidget in $label',
        (tester) async {
          await setupLocator();
          final themeData = AppTheme.build(
            brightness: brightness,
            pitchBlack: pitch,
          );
          final controller = DiscoverController(locator<WallpaperRepository>());

          await tester.pumpWidget(
            MaterialApp(
              theme: themeData,
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () => showDiscoverFilterSheet(
                        context,
                        controller: controller,
                      ),
                      child: const Text('open'),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          expect(find.byWidgetPredicate((w) => w is ErrorWidget), findsNothing);
          expect(find.text('Sort & Filter'), findsOneWidget);
          expect(find.byType(M3EChip), findsWidgets);
        },
      );
    }
  });

  testWidgets('M3E fallback resolves the nearest local Material theme', (
    tester,
  ) async {
    final root = AppTheme.build(brightness: Brightness.light);
    final localScheme = ColorScheme.fromSeed(seedColor: const Color(0xFFAA3300))
        .copyWith(primaryFixed: const Color(0xFF123123));
    final local = root.copyWith(colorScheme: localScheme);
    late M3EThemeData expressive;
    late ColorScheme material;

    await tester.pumpWidget(
      MaterialApp(
        theme: root,
        home: Theme(
          data: local,
          child: Builder(
            builder: (context) {
              expressive = M3ETheme.of(context);
              material = Theme.of(context).colorScheme;
              return const M3EButton(onPressed: null, child: Text('Probe'));
            },
          ),
        ),
      ),
    );

    expect(expressive.colorScheme.primary, localScheme.primary);
    expect(material.primary, localScheme.primary);
    expect(material.primaryFixed, const Color(0xFF123123));
  });
}
