import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
// Prefer material_ui: the app renders on the material_ui widget tree.
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/collections/collections_repository.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/services/wallpaper_applier.dart';
import 'package:vanne/core/storage/settings_store.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/discover/application/discover_controller.dart';
import 'package:vanne/features/discover/presentation/discover_screen.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:vanne/features/filtered/presentation/filtered_wallpapers_screen.dart';
import 'package:vanne/features/search/application/search_controller.dart'
    as app_search;
import 'package:vanne/features/search/presentation/search_screen.dart';
import 'package:vanne/features/settings/application/settings_controller.dart';
import 'package:vanne/features/settings/presentation/api_key_screen.dart';
import 'package:vanne/features/settings/presentation/blocked_tags_screen.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:vanne/features/wallpaper_detail/presentation/wallpaper_detail_screen.dart';
import 'package:vanne/features/wallpaper_detail/presentation/widgets/wallpaper_tags_section.dart';
import 'package:vanne/shared/widgets/favorite_toggle_button.dart';
import 'package:vanne/shared/widgets/image_overlay_control.dart';

/// App-level regressions for the reported Material control and scroll defects.
///
/// Each group encodes one user-visible symptom and fails on the pre-fix
/// behaviour:
/// * feed headers re-expanding over the grid once a scroll ends,
/// * a filled, over-inset back prefix in the search bar,
/// * surface-coloured or mismatched-foreground controls over wallpaper.
///
/// Assertions are interaction/geometry based where the symptom is spatial;
/// the over-wallpaper contrast guarantee is computed from the colour pairing
/// the buttons actually paint with.

const int _feedItems = 24;

class _StubRepository implements WallpaperRepository {
  _StubRepository(this.items);

  final List<Wallpaper> items;

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
      items: page == 1 ? items : const [],
      meta: SearchMeta(currentPage: 1, lastPage: 1, perPage: items.length),
    ),
    nsfwClamped: false,
  );

  @override
  Future<Wallpaper> wallpaperDetails(String id) async =>
      items.firstWhere((wallpaper) => wallpaper.id == id);
}

Wallpaper _wallpaper(String id, {List<Tag>? tags, String colors = '#3B2A72'}) =>
    Wallpaper(
      id: id,
      url: 'https://wallhaven.cc/w/$id',
      source: '',
      purity: Purity.sfw,
      category: Category.general,
      width: 1920,
      height: 1080,
      resolution: '1920x1080',
      ratio: '1.78',
      fileSizeBytes: 2 * 1024 * 1024,
      fileType: 'image/jpeg',
      colors: [colors],
      views: 10,
      favorites: 4,
      path: 'https://w.wallhaven.cc/full/$id.jpg',
      thumbnails: Thumbnails(
        small: 'https://th.wallhaven.cc/small/$id.jpg',
        large: 'https://th.wallhaven.cc/lg/$id.jpg',
        original: 'https://w.wallhaven.cc/full/$id.jpg',
      ),
      tags: tags,
    );

List<Wallpaper> _feed() => [
  for (var i = 0; i < _feedItems; i++) _wallpaper('feed$i'),
];

/// Registers the dependencies the real screens resolve from [locator].
Future<app_search.SearchController> _registerDependencies({
  List<Wallpaper>? items,
}) async {
  final repository = _StubRepository(items ?? _feed());
  final favorites = FavoritesController(FavoritesRepository());
  await favorites.restore();
  final search = app_search.SearchController(repository);
  locator
    ..registerSingleton<FavoritesController>(favorites)
    ..registerSingleton<TabScrollCoordinator>(
      TabScrollCoordinator(),
      dispose: (coordinator) => coordinator.dispose(),
    )
    ..registerFactory<DiscoverController>(() => DiscoverController(repository))
    ..registerFactory<app_search.SearchController>(() => search);
  return search;
}

/// Registers what the settings sub-routes and the filtered feed resolve.
Future<void> _registerAppBarRoutes() async {
  final repository = _StubRepository(_feed());
  final collections = CollectionsController(CollectionsRepository());
  await collections.restore();
  final favorites = FavoritesController(FavoritesRepository());
  await favorites.restore();
  locator
    ..registerSingleton<WallpaperRepository>(repository)
    ..registerSingleton<FavoritesController>(favorites)
    ..registerSingleton<SettingsController>(
      SettingsController(SettingsStore(), repository),
    )
    ..registerSingleton<CollectionsController>(collections);
}

/// Advances fake time long enough for springs, inertia and any snap animation
/// to finish, without relying on global quiescence (the feed keeps animating).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

MaterialApp _host(Widget app, ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(body: app),
);

/// The single floating header of the screen under test.
RenderSliverFloatingPersistentHeader _floatingHeader(WidgetTester tester) {
  // Several elements adopt the same sliver render object, so dedupe it.
  final headers = <RenderSliverFloatingPersistentHeader>{
    ...tester.allRenderObjects
        .whereType<RenderSliverFloatingPersistentHeader>(),
  }.toList(growable: false);
  expect(
    headers,
    hasLength(1),
    reason: 'expected exactly one floating feed header on screen',
  );
  return headers.single;
}

double _visibleHeaderExtent(WidgetTester tester) =>
    _floatingHeader(tester).geometry!.paintExtent;

Finder get _feedScrollable => find.byType(CustomScrollView).first;

/// Scroll position of the feed under test.
ScrollPosition _feedPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(of: _feedScrollable, matching: find.byType(Scrollable))
          .first,
    )
    .position;

/// Scrolls the feed back to [targetOffset] with a real drag gesture.
Future<void> _revealTo(WidgetTester tester, double targetOffset) async {
  final delta = _feedPosition(tester).pixels - targetOffset;
  await tester.drag(_feedScrollable, Offset(0, delta));
  await _settle(tester);
  expect(
    _feedPosition(tester).pixels,
    moreOrLessEquals(targetOffset, epsilon: 1),
    reason: 'the reveal gesture should land where it was aimed',
  );
}

Finder _iconButtonWithTooltip(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is M3EIconButton && widget.tooltip == tooltip,
  description: 'M3EIconButton with tooltip "$tooltip"',
);

/// Relative luminance of an sRGB [color] (WCAG 2.1 definition).
double _luminance(Color color) {
  double linear(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}

/// WCAG contrast ratio between [foreground] and [background].
double _contrastRatio(Color foreground, Color background) {
  final first = _luminance(foreground);
  final second = _luminance(background);
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Source-over composite of [foreground] onto opaque [background].
Color _composite(Color foreground, Color background) => Color.from(
  alpha: 1,
  red: foreground.r * foreground.a + background.r * (1 - foreground.a),
  green: foreground.g * foreground.a + background.g * (1 - foreground.a),
  blue: foreground.b * foreground.a + background.b * (1 - foreground.a),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async => locator.reset());

  group('Feed headers never expand on their own', () {
    testWidgets('Discover keeps the header down once the user scrolls down', (
      tester,
    ) async {
      _usePhoneViewport(tester);
      await _registerDependencies();

      await mockNetworkImagesFor(() async {
        await tester.pumpWidget(
          _host(
            DiscoverScreen(onOpenSearch: () {}, onOpenWallpaper: (_) {}),
            AppTheme.build(brightness: Brightness.light),
          ),
        );
        await _settle(tester);

        final maxExtent = _floatingHeader(tester).maxExtent;
        expect(maxExtent, greaterThan(150));
        expect(
          _visibleHeaderExtent(tester),
          moreOrLessEquals(maxExtent, epsilon: 1),
          reason: 'the header starts fully expanded at the top of the feed',
        );

        // Scroll the feed down (content moves up): header must leave.
        await tester.drag(_feedScrollable, const Offset(0, -700));
        await _settle(tester);
        expect(_visibleHeaderExtent(tester), 0);

        // A fling that only ever moves content up must not bring it back.
        await tester.fling(_feedScrollable, const Offset(0, -300), 2000);
        await _settle(tester);
        expect(
          _visibleHeaderExtent(tester),
          0,
          reason: 'downward scrolling alone must never reveal the header',
        );

        // Reveal part of it on purpose: it must stay where the gesture left
        // it. Snapping expanded the whole 188dp block as soon as scrolling
        // ended, which is the reported jump back over the feed.
        await _revealTo(tester, maxExtent - 60);
        expect(
          _visibleHeaderExtent(tester),
          moreOrLessEquals(60, epsilon: 4),
          reason: 'a 60dp reveal stays a 60dp reveal after release',
        );
        expect(
          _visibleHeaderExtent(tester),
          lessThan(maxExtent * 0.6),
          reason: 'releasing a partial reveal must not snap the header open',
        );

        // Intentional reveal still works: back at the top it is fully open.
        await _revealTo(tester, 0);
        expect(
          _visibleHeaderExtent(tester),
          moreOrLessEquals(maxExtent, epsilon: 1),
          reason: 'scrolling back to the top must restore the full header',
        );
      });
    });

    testWidgets('both Search headers reveal only as far as the user scrolls', (
      tester,
    ) async {
      _usePhoneViewport(tester);
      final search = await _registerDependencies();

      await mockNetworkImagesFor(() async {
        await tester.pumpWidget(
          _host(
            SearchScreen(autofocus: false, onOpenWallpaper: (_) {}),
            AppTheme.build(brightness: Brightness.light),
          ),
        );
        await _settle(tester);

        // --- Pristine header (no committed input) -------------------------
        // Nothing scrolls yet: the empty state fills the remaining viewport,
        // so only the settled height at the top is meaningful here.
        var maxExtent = _floatingHeader(tester).maxExtent;
        expect(maxExtent, greaterThan(200));
        expect(
          _visibleHeaderExtent(tester),
          moreOrLessEquals(maxExtent, epsilon: 1),
        );

        // --- Committed header (results + filter chip row) -----------------
        expect(find.text('Search wallpapers'), findsWidgets);
        search.queryText.value = 'forest';
        search.submit();
        await tester.pump(const Duration(milliseconds: 400));
        await _settle(tester);
        expect(
          find.byType(SearchScreen),
          findsOneWidget,
          reason: 'the committed results replace the pristine empty state',
        );

        maxExtent = _floatingHeader(tester).maxExtent;
        expect(maxExtent, greaterThan(250));
        expect(
          _visibleHeaderExtent(tester),
          moreOrLessEquals(maxExtent, epsilon: 1),
        );

        await tester.drag(_feedScrollable, const Offset(0, -700));
        await _settle(tester);
        expect(_visibleHeaderExtent(tester), 0);

        // More downward scrolling must never bring it back.
        await tester.fling(_feedScrollable, const Offset(0, -300), 2000);
        await _settle(tester);
        expect(_visibleHeaderExtent(tester), 0);

        // A partial reveal stays partial once released.
        await _revealTo(tester, maxExtent - 60);
        expect(
          _visibleHeaderExtent(tester),
          moreOrLessEquals(60, epsilon: 4),
          reason: 'committed Search header must not snap open on release',
        );
        expect(_visibleHeaderExtent(tester), lessThan(maxExtent * 0.7));

        // Intentional reveal still reaches the full header at the top.
        await _revealTo(tester, 0);
        expect(
          _visibleHeaderExtent(tester),
          moreOrLessEquals(maxExtent, epsilon: 1),
        );
      });
    });
  });

  group('Search prefix back control', () {
    testWidgets('is a bare standard icon button inset by the bar padding', (
      tester,
    ) async {
      _usePhoneViewport(tester);
      await _registerDependencies();

      await mockNetworkImagesFor(() async {
        await tester.pumpWidget(
          _host(
            SearchScreen(autofocus: false, onOpenWallpaper: (_) {}),
            AppTheme.build(brightness: Brightness.light),
          ),
        );
        await _settle(tester);

        final back = _iconButtonWithTooltip('Back');
        expect(back, findsOneWidget);
        expect(
          tester.widget<M3EIconButton>(back).variant,
          M3EIconButtonVariant.standard,
          reason: 'the 1.1.3 default `filled` variant painted a disc behind it',
        );

        // 48dp target, and only the bar's own padding to its left.
        final barLeft = tester.getTopLeft(find.byType(M3ESearchBar)).dx;
        final backRect = tester.getRect(back);
        expect(backRect.size, const Size(48, 48));
        expect(
          backRect.left - barLeft,
          moreOrLessEquals(8, epsilon: 0.5),
          reason: 'no extra 16dp inset may stack on the 48dp action slot',
        );

        // Focusing the field must not shift the bar or the back control:
        // the resting expand inset is zeroed.
        final barWidth = tester.getRect(find.byType(M3ESearchBar)).width;
        final fieldRect = tester.getRect(find.byType(EditableText));
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .requestFocus();
        await _settle(tester);

        expect(
          tester.getRect(find.byType(M3ESearchBar)).width,
          barWidth,
          reason: 'the resting expand inset must not resize the bar on focus',
        );
        expect(
          tester.getRect(back),
          backRect,
          reason: 'the back control must not shift on focus',
        );
        expect(
          tester.getRect(find.byType(EditableText)),
          fieldRect,
          reason: 'the field must not jump when it gains focus',
        );
      });
    });
  });

  group('Controls over wallpaper', () {
    for (final entry in [
      (Brightness.light, false, 'light'),
      (Brightness.dark, false, 'dark'),
      (Brightness.dark, true, 'pitch black'),
    ]) {
      testWidgets('detail back and heart stay readable in ${entry.$3}', (
        tester,
      ) async {
        _usePhoneViewport(tester);
        await _registerDependencies();
        final controller = WallpaperDetailController(
          initial: _wallpaper('detail1'),
          repository: _StubRepository([_wallpaper('detail1')]),
          downloader: DownloadService(),
          applier: WallpaperApplier(),
        );
        addTearDown(controller.dispose);

        await mockNetworkImagesFor(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(brightness: entry.$1, pitchBlack: entry.$2),
              home: WallpaperDetailScreen(
                controller: controller,
                onBack: () {},
              ),
            ),
          );
          await _settle(tester);

          // Both controls are drawn on the wallpaper, not on a surface.
          for (final tooltip in ['Back', 'Save to favorites']) {
            final button = tester.widget<M3EIconButton>(
              _iconButtonWithTooltip(tooltip),
            );
            expect(button.variant, M3EIconButtonVariant.standard);
            expect(button.decoration, imageOverlayIconButtonDecoration);
            final glyph = tester.widgetList<Icon>(
              find.descendant(
                of: _iconButtonWithTooltip(tooltip),
                matching: find.byType(Icon),
              ),
            );
            expect(
              glyph.every((icon) => icon.color == null),
              isTrue,
              reason:
                  'an explicit glyph colour fights the component foreground',
            );
          }

          // Toggling favourite swaps the glyph, keeps the treatment.
          await tester.tap(_iconButtonWithTooltip('Save to favorites'));
          await _settle(tester);
          final selected = tester.widget<M3EIconButton>(
            _iconButtonWithTooltip('Remove from favorites'),
          );
          expect(selected.isSelected, isTrue);
          expect(selected.decoration, imageOverlayIconButtonDecoration);
          expect(
            find.descendant(
              of: _iconButtonWithTooltip('Remove from favorites'),
              matching: find.byIcon(PhosphorIconsFill.heart),
            ),
            findsOneWidget,
            reason: 'selection is conveyed by the filled heart glyph',
          );
        });
      });
    }

    testWidgets('overlay scrim keeps at least 3:1 glyph contrast', (
      tester,
    ) async {
      final scrim = imageOverlayIconButtonDecoration.backgroundColor!.resolve(
        {},
      )!;
      final glyph = imageOverlayIconButtonDecoration.foregroundColor!.resolve(
        {},
      )!;

      expect(
        glyph.a,
        1.0,
        reason: 'only the container is translucent, never the glyph',
      );
      expect(scrim.a, moreOrLessEquals(0.5, epsilon: 0.02));

      // The state layer only paints during interaction, never at rest.
      final overlay = imageOverlayIconButtonDecoration.overlayColor!;
      expect(overlay.resolve({}), isNull);
      expect(overlay.resolve({WidgetState.pressed}), isNotNull);
      expect(overlay.resolve({WidgetState.focused}), isNotNull);

      // Worst cases for white-on-scrim: pure black and pure white wallpapers.
      for (final wallpaper in [
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
      ]) {
        final ratio = _contrastRatio(glyph, _composite(scrim, wallpaper));
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: 'glyph must stay legible over $wallpaper',
        );
      }
    });

    testWidgets('tag chevron sits on the sheet surface, not a filled disc', (
      tester,
    ) async {
      await _registerDependencies();
      final tags = [for (var i = 0; i < 6; i++) Tag(id: i, name: 'tag$i')];
      final controller = WallpaperDetailController(
        initial: _wallpaper('tagged', tags: tags),
        repository: _StubRepository([_wallpaper('tagged', tags: tags)]),
        downloader: DownloadService(),
        applier: WallpaperApplier(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          Padding(
            padding: const EdgeInsets.all(16),
            child: WallpaperTagsSection(controller: controller),
          ),
          AppTheme.build(brightness: Brightness.dark),
        ),
      );
      await _settle(tester);

      final chevron = _iconButtonWithTooltip('Show all tags');
      final button = tester.widget<M3EIconButton>(chevron);
      expect(
        button.variant,
        M3EIconButtonVariant.standard,
        reason: 'the filled default painted a primary disc on the sheet',
      );
      expect(button.decoration, isNull);
      final glyph = tester.widget<Icon>(
        find.descendant(of: chevron, matching: find.byType(Icon)),
      );
      expect(
        glyph.color,
        isNull,
        reason: 'the glyph must inherit the component foreground role',
      );

      // The chevron keeps its own semantics node, so the label is not
      // swallowed by the surrounding card.
      expect(find.bySemanticsLabel('Show all tags'), findsOneWidget);
      expect(find.text('tag2'), findsNothing);

      await tester.tap(chevron);
      await _settle(tester);
      expect(find.bySemanticsLabel('Show fewer tags'), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        expect(find.text('tag$i'), findsOneWidget);
      }
    });

    testWidgets('surface favourite uses component role pairs, not error', (
      tester,
    ) async {
      for (final selected in [false, true]) {
        await tester.pumpWidget(
          _host(
            FavoriteToggleButton(
              selected: selected,
              surface: FavoriteToggleSurface.surface,
              onPressed: () {},
            ),
            AppTheme.build(brightness: Brightness.light),
          ),
        );
        await _settle(tester);

        final button = tester.widget<M3EIconButton>(
          find.descendant(
            of: find.byType(FavoriteToggleButton),
            matching: find.byType(M3EIconButton),
          ),
        );
        expect(button.variant, M3EIconButtonVariant.tonal);
        expect(
          button.decoration,
          isNull,
          reason: 'surface usage leaves foreground and container to the theme',
        );
        final glyphs = tester.widgetList<Icon>(
          find.descendant(
            of: find.byType(FavoriteToggleButton),
            matching: find.byType(Icon),
          ),
        );
        expect(glyphs, isNotEmpty);
        expect(
          glyphs.every((icon) => icon.color == null),
          isTrue,
          reason: 'no error-coloured heart over an unrelated container',
        );
      }
    });
  });

  group('Tonal app-bar controls own their foreground pair', () {
    /// A tonal button resolves `onSecondaryContainer` for its glyph; pinning
    /// `onSurfaceVariant` on top of that container was the regression.
    void expectTonalPairOwnsGlyph(M3EIconButton button) {
      expect(button.variant, M3EIconButtonVariant.tonal);
      expect(button.decoration, isNull);
    }

    Iterable<Icon> glyphsOf(WidgetTester tester, String tooltip) =>
        tester.widgetList<Icon>(
          find.descendant(
            of: _iconButtonWithTooltip(tooltip),
            matching: find.byType(Icon),
          ),
        );

    testWidgets('API key and blocked tags backs inherit their tonal glyph', (
      tester,
    ) async {
      _usePhoneViewport(tester);
      await _registerAppBarRoutes();

      for (final screen in <Widget>[
        ApiKeyScreen(onBack: () {}),
        BlockedTagsScreen(onBack: () {}),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(brightness: Brightness.light),
            home: screen,
          ),
        );
        await _settle(tester);

        final back = _iconButtonWithTooltip('Back');
        expect(back, findsOneWidget);
        expectTonalPairOwnsGlyph(tester.widget<M3EIconButton>(back));
        final glyphs = glyphsOf(tester, 'Back');
        expect(glyphs, isNotEmpty);
        expect(
          glyphs.every((icon) => icon.color == null),
          isTrue,
          reason: '${screen.runtimeType} pinned a foreground on its container',
        );
        // The 32dp visual still keeps a 48dp-wide target in the bar slot.
        final backSize = tester.getSize(back);
        expect(backSize.width, 48);
        expect(backSize.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets(
      'filtered feed back inherits tonal; add action stays a standard action',
      (tester) async {
        _usePhoneViewport(tester);
        await _registerAppBarRoutes();

        await mockNetworkImagesFor(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(brightness: Brightness.light),
              home: FilteredWallpapersScreen(
                title: 'nature',
                query: 'nature',
                onOpenWallpaper: (_) {},
                onBack: () {},
              ),
            ),
          );
          await _settle(tester);

          final back = _iconButtonWithTooltip('Back');
          expect(back, findsOneWidget);
          expectTonalPairOwnsGlyph(tester.widget<M3EIconButton>(back));
          expect(
            glyphsOf(tester, 'Back').every((icon) => icon.color == null),
            isTrue,
          );

          // App-bar action, never a primary call to action. Unsaved, the
          // toggle reads "Save to Collections".
          final add = _iconButtonWithTooltip('Save to Collections');
          expect(add, findsOneWidget);
          expect(
            tester.widget<M3EIconButton>(add).variant,
            M3EIconButtonVariant.standard,
            reason:
                'the filled default turned a bar action into a primary disc',
          );
          expect(
            glyphsOf(
              tester,
              'Save to Collections',
            ).every((icon) => icon.color == null),
            isTrue,
          );
        });
      },
    );
  });
}
