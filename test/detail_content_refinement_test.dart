import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/services/wallpaper_applier.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:vanne/features/wallpaper_detail/presentation/wallpaper_detail_screen.dart';
import 'package:vanne/features/wallpaper_detail/presentation/widgets/wallpaper_action_bar.dart';
import 'package:vanne/shared/widgets/favorite_toggle_button.dart';
import 'package:vanne/shared/widgets/wallpaper_tile.dart';

/// App-level regressions for the detail refinements:
///
/// * Back and favourite grow on detail only — feed hearts keep their size.
/// * Aspect ratio and upload date no longer take two cards of the sheet.
/// * The expanded sheet stops where its content ends instead of always
///   opening to 80 % of the screen and leaving dead surface below the
///   download / set / link row.
/// * The sheet keeps that invariant when tags expand or collapse, on a short
///   screen, and at 200 % text.
/// * Detail loading uses the standard expressive morphing indicator.

/// Pixels of sheet surface allowed below the action row: the intentional
/// bottom breathing room ([16] dp minimum) plus gesture-rounding slack.
const double _maxTrailingGap = 26;

const Size _viewport = Size(400, 800);

class _StubRepository implements WallpaperRepository {
  _StubRepository({this.detail, this.delay = Duration.zero, this.error});

  /// When set, `wallpaperDetails` resolves with it; otherwise it never
  /// completes, which keeps the detail sheet in its loading state.
  final Wallpaper? detail;

  /// How long the details request takes, so tests can drive the real
  /// loading → loaded transition.
  final Duration delay;

  /// When set, the details request fails with a handled repository error.
  final String? error;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Wallpaper> wallpaperDetails(String id) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (error case final message?) throw WallhavenUserException(message);
    return detail ?? Completer<Wallpaper>().future;
  }
}

List<Tag> _tags([int count = 6]) => [
  for (var i = 0; i < count; i++) Tag(id: i, name: 'tag$i'),
];

Wallpaper _wallpaper({
  String id = 'detail1',
  bool withDetails = true,
  List<String> colors = const ['#3B2A72', '#112233', '#AABBCC'],
}) => Wallpaper(
  id: id,
  url: 'https://wallhaven.cc/w/$id',
  source: '',
  purity: Purity.sfw,
  category: Category.general,
  width: 1920,
  height: 2880,
  resolution: '1920x2880',
  ratio: '0.67',
  fileSizeBytes: 3 * 1024 * 1024,
  fileType: 'image/jpeg',
  colors: colors,
  views: 128,
  favorites: 42,
  path: 'https://w.wallhaven.cc/full/$id.jpg',
  thumbnails: Thumbnails(
    small: 'https://th.wallhaven.cc/small/$id.jpg',
    large: 'https://th.wallhaven.cc/lg/$id.jpg',
    original: 'https://w.wallhaven.cc/full/$id.jpg',
  ),
  createdAt: DateTime.utc(2024, 5, 6),
  uploader: withDetails ? const Uploader(username: 'kejsirajbek') : null,
  tags: withDetails ? _tags() : null,
);

Future<FavoritesController> _registerFavorites() async {
  final favorites = FavoritesController(FavoritesRepository());
  await favorites.restore();
  locator.registerSingleton<FavoritesController>(favorites);
  return favorites;
}

Future<WallpaperDetailController> _pumpDetail(
  WidgetTester tester, {
  Wallpaper? wallpaper,
  bool withDetails = true,
  Wallpaper? resolved,
  String? detailError,
  Duration detailDelay = Duration.zero,
  Size viewport = _viewport,
  double textScale = 1,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final wallpaperUnderTest = wallpaper ?? _wallpaper(withDetails: withDetails);
  await _registerFavorites();
  final controller = WallpaperDetailController(
    initial: wallpaperUnderTest,
    repository: _StubRepository(
      detail: resolved ?? (withDetails ? wallpaperUnderTest : null),
      delay: detailDelay,
      error: detailError,
    ),
    downloader: DownloadService(),
    applier: WallpaperApplier(),
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(brightness: Brightness.light),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: WallpaperDetailScreen(controller: controller, onBack: () {}),
        ),
      ),
    ),
  );
  await _settle(tester);
  return controller;
}

/// Advances past the sheet snap, tag [AnimatedSize] and image fades without
/// depending on global quiescence.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The sheet's scroll view fills the sheet, so its box is the sheet's box.
Finder get _sheet => find.byType(CustomScrollView);

Rect _sheetRect(WidgetTester tester) => tester.getRect(_sheet);

Rect _actionRect(WidgetTester tester) =>
    tester.getRect(find.byType(WallpaperActionBar));

/// Grows the sheet to its expanded snap anchor, then parks the content at
/// the top so the measurement reflects the sheet's own height rather than
/// however far an over-drag happened to scroll the content.
Future<void> _expandSheet(WidgetTester tester) async {
  await tester.drag(_sheet, Offset(0, -_viewport.height));
  await _settle(tester);
  await _scrollContentToTop(tester);
}

Future<void> _scrollContentToTop(WidgetTester tester) async {
  final position = tester
      .state<ScrollableState>(
        find.descendant(of: _sheet, matching: find.byType(Scrollable)).first,
      )
      .position;
  position.jumpTo(0);
  await _settle(tester);
}

/// Sheet surface left between the action row and the sheet's bottom edge.
///
/// Negative values mean the action row is scrolled below the sheet (content
/// taller than its cap), which is also "no dead space".
double _trailingGap(WidgetTester tester) =>
    _sheetRect(tester).bottom - _actionRect(tester).bottom;

void main() {
  tearDown(() async => locator.reset());

  group('detail metadata', () {
    testWidgets('shows four cards and drops aspect ratio and upload date', (
      tester,
    ) async {
      await mockNetworkImagesFor(() => _pumpDetail(tester));

      for (final label in [
        'Resolution',
        'File size',
        'Favorites',
        'Uploader',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label must remain');
      }
      for (final dropped in ['Aspect ratio', 'Uploaded']) {
        expect(
          find.text(dropped),
          findsNothing,
          reason: '$dropped was removed from the sheet',
        );
      }
      expect(find.text('1920x2880'), findsOneWidget);
      expect(find.text('kejsirajbek'), findsOneWidget);
    });

    testWidgets('formatters stay available for other surfaces', (tester) async {
      // Removing two cells is a presentation decision, not a data one.
      expect(_wallpaper().ratio, '0.67');
      expect(_wallpaper().createdAt, isNotNull);
    });
  });

  group('detail overlay controls', () {
    testWidgets('back and favourite grow while feed hearts do not', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        await _pumpDetail(tester);

        final back = tester.widget<M3EIconButton>(
          find.ancestor(
            of: find.byIcon(PhosphorIconsBold.arrowLeft),
            matching: find.byType(M3EIconButton),
          ),
        );
        expect(back.visualSize, const Size.square(48));
        expect(back.variant, M3EIconButtonVariant.standard);

        final heartButton = find.byType(FavoriteToggleButton);
        expect(heartButton, findsOneWidget);
        expect(
          tester.widget<FavoriteToggleButton>(heartButton).iconSize,
          greaterThan(24),
        );
        final heartGlyph = tester.widget<Icon>(
          find.descendant(of: heartButton, matching: find.byType(Icon)).first,
        );
        expect(heartGlyph.size, greaterThan(24));
        expect(heartGlyph.color, isNull);

        // Rendered face is the 48 dp circle, not the 40 dp default.
        expect(
          tester.getSize(
            find
                .descendant(
                  of: find.ancestor(
                    of: find.byIcon(PhosphorIconsBold.arrowLeft),
                    matching: find.byType(M3EIconButton),
                  ),
                  matching: find.byType(Material),
                )
                .first,
          ),
          const Size.square(48),
        );
      });
    });

    testWidgets('feed tile keeps the shared default heart size', (
      tester,
    ) async {
      tester.view.physicalSize = _viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await mockNetworkImagesFor(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(brightness: Brightness.light),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  child: WallpaperTile(
                    wallpaper: _wallpaper(),
                    onToggleFavorite: () {},
                    onOpen: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await _settle(tester);

        final tileHeart = tester.widget<FavoriteToggleButton>(
          find.byType(FavoriteToggleButton),
        );
        expect(tileHeart.visualSize, isNull);
        expect(tileHeart.iconSize, isNull);
        expect(tileHeart.surface, FavoriteToggleSurface.image);
      });
    });
  });

  group('sheet height follows its content', () {
    testWidgets('expanded sheet stops at the content, not at 80 %', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        await _pumpDetail(tester);
        await _expandSheet(tester);

        final sheet = _sheetRect(tester);
        expect(
          sheet.height,
          lessThan(_viewport.height * 0.8 - 1),
          reason: 'a short sheet must not stretch to the 80 % ceiling',
        );
        expect(
          _trailingGap(tester),
          inInclusiveRange(0, _maxTrailingGap),
          reason: 'only the intended bottom breathing room may remain',
        );
        expect(find.text('Set'), findsOneWidget);
      });
    });

    testWidgets(
      'resting sheet keeps its initial height (no first-frame jump)',
      (tester) async {
        await mockNetworkImagesFor(() async {
          await _pumpDetail(tester);
          final resting = _sheetRect(tester).height;
          expect(
            resting,
            moreOrLessEquals(_viewport.height * 0.3, epsilon: 1),
            reason: 'measuring the content must not resize the resting sheet',
          );

          // Further frames (measure -> rebuild -> measure) must be stable.
          await _settle(tester);
          await _settle(tester);
          expect(
            _sheetRect(tester).height,
            moreOrLessEquals(resting, epsilon: 0.5),
          );
        });
      },
    );

    testWidgets('capped after details arrive late (loading to loaded)', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        // The route opens from a listing entry: no uploader/tags yet, so the
        // sheet shows its loading state and only mounts real content once
        // /w/{id} resolves.
        await _pumpDetail(
          tester,
          wallpaper: _wallpaper(withDetails: false),
          resolved: _wallpaper(),
          detailDelay: const Duration(milliseconds: 120),
        );
        expect(find.text('kejsirajbek'), findsOneWidget);

        await _expandSheet(tester);
        expect(
          _sheetRect(tester).height,
          lessThan(_viewport.height * 0.8 - 1),
          reason: 'late-loaded content must still cap the expanded sheet',
        );
        expect(
          _trailingGap(tester),
          inInclusiveRange(0, _maxTrailingGap),
          reason: 'no dead surface may open up once details arrive',
        );
      });
    });

    testWidgets('capped after a handled details failure (fallback content)', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        await _pumpDetail(
          tester,
          wallpaper: _wallpaper(withDetails: false),
          detailError: 'Rate limit reached',
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await _expandSheet(tester);
        expect(
          _sheetRect(tester).height,
          lessThan(_viewport.height * 0.8 - 1),
          reason: 'the error fallback content must also cap the sheet',
        );
        expect(_trailingGap(tester), inInclusiveRange(0, _maxTrailingGap));
      });
    });

    testWidgets('short content still leaves no dead surface below actions', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        // No palette colours and no tags: the shortest realistic content.
        await _pumpDetail(tester, wallpaper: _wallpaper(colors: const []));
        await _expandSheet(tester);

        expect(_sheetRect(tester).height, lessThan(_viewport.height * 0.8 - 1));
        expect(_trailingGap(tester), inInclusiveRange(0, _maxTrailingGap));
      });
    });

    testWidgets('tags collapse re-anchors the sheet shorter', (tester) async {
      await mockNetworkImagesFor(() async {
        await _pumpDetail(tester);
        await _expandSheet(tester);
        final collapsedTagsHeight = _sheetRect(tester).height;

        await tester.tap(find.bySemanticsLabel('Show all tags'));
        await _settle(tester);
        await _scrollContentToTop(tester);
        expect(_trailingGap(tester), lessThanOrEqualTo(_maxTrailingGap));
        expect(
          _sheetRect(tester).height,
          lessThanOrEqualTo(_viewport.height * 0.8 + 0.5),
        );

        await tester.tap(find.bySemanticsLabel('Show fewer tags'));
        await _settle(tester);
        await _scrollContentToTop(tester);
        expect(
          _sheetRect(tester).height,
          lessThanOrEqualTo(collapsedTagsHeight + 0.5),
          reason: 'collapsing tags must not leave the sheet stretched',
        );
        expect(_trailingGap(tester), lessThanOrEqualTo(_maxTrailingGap));
      });
    });

    testWidgets('short screen keeps every action reachable', (tester) async {
      await mockNetworkImagesFor(() async {
        await _pumpDetail(tester, viewport: const Size(400, 600));
        await _expandSheet(tester);

        expect(
          _sheetRect(tester).height,
          lessThanOrEqualTo(600 * 0.8 + 0.5),
          reason: 'the sheet must respect its ceiling on a short screen',
        );

        await tester.scrollUntilVisible(
          find.byType(WallpaperActionBar),
          120,
          scrollable: find
              .descendant(of: _sheet, matching: find.byType(Scrollable))
              .first,
        );
        await _settle(tester);

        expect(
          tester.getRect(find.byType(WallpaperActionBar)).bottom,
          lessThanOrEqualTo(_sheetRect(tester).bottom + 0.5),
          reason: 'the download / set / link row must land inside the sheet',
        );
        expect(find.text('Set'), findsOneWidget);
      });
    });

    testWidgets('200 % text caps the sheet and keeps actions reachable', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        await _pumpDetail(tester, textScale: 2);
        await _expandSheet(tester);

        expect(
          _sheetRect(tester).height,
          lessThanOrEqualTo(_viewport.height * 0.8 + 0.5),
          reason: 'large text must never push the sheet past its ceiling',
        );
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.byType(WallpaperActionBar),
          160,
          scrollable: find
              .descendant(of: _sheet, matching: find.byType(Scrollable))
              .first,
        );
        await _settle(tester);
        expect(
          tester.getRect(find.byType(WallpaperActionBar)).bottom,
          lessThanOrEqualTo(_sheetRect(tester).bottom + 0.5),
        );
      });
    });
  });

  group('detail loading', () {
    testWidgets('uses the standard Material expressive loading shape', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        await _pumpDetail(tester, withDetails: false);

        final loader = tester.widget<M3ELoadingIndicator>(
          find.byType(M3ELoadingIndicator),
        );
        expect(loader.semanticLabel, 'Loading wallpaper details');
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });
    });
  });
}
