import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
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

class _SearchRecord {
  const _SearchRecord(this.query, this.colors);

  final String query;
  final Set<WallhavenColor> colors;
}

_RecordingSearchRepository? _repository;

class _RecordingSearchRepository implements WallpaperRepository {
  final requests = <_SearchRecord>[];

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
    requests.add(_SearchRecord(query, colors));
    return SearchOutcome(
      page: PaginatedResult<Wallpaper>(
        items: const [],
        meta: const SearchMeta(currentPage: 1, lastPage: 1, perPage: 24),
      ),
      nsfwClamped: false,
    );
  }
}

Future<app_search.SearchController> _pumpSearch(
  WidgetTester tester, {
  required Brightness brightness,
}) async {
  final repository = _RecordingSearchRepository();
  _repository = repository;
  final favorites = FavoritesController(FavoritesRepository());
  await favorites.restore();
  final controller = app_search.SearchController(repository);
  locator
    ..registerSingleton<WallpaperRepository>(repository)
    ..registerSingleton<FavoritesController>(favorites)
    ..registerSingleton<TabScrollCoordinator>(TabScrollCoordinator())
    ..registerSingleton<app_search.SearchController>(controller);

  await mockNetworkImagesFor(() async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: brightness),
        home: SearchScreen(autofocus: false, onOpenWallpaper: (_) {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  });
  return controller;
}

void main() {
  tearDown(() async => locator.reset());

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('color and genre refinements remain accessible in $brightness', (
      tester,
    ) async {
      final controller = await _pumpSearch(tester, brightness: brightness);
      final colorKey = const ValueKey('search-color-black');
      final genreKey = const ValueKey('search-genre-nature');
      final color = find.byKey(colorKey);
      final genre = find.byKey(genreKey);

      expect(find.text('By color'), findsOneWidget);
      expect(find.text('By genre'), findsOneWidget);
      expect(color, findsOneWidget);
      expect(genre, findsOneWidget);
      expect(tester.getSize(color), const Size(48, 48));
      expect(tester.getSize(genre).height, greaterThanOrEqualTo(48));
      final genreChip = tester.widget<ChoiceChip>(genre);
      expect(genreChip.shape, isA<StadiumBorder>());
      expect(genreChip.showCheckmark, isTrue);

      await tester.tap(color);
      await tester.pump();
      expect(controller.selectedColors.value, {FeedColor.black});
      expect(
        tester.getSemantics(color).flagsCollection.isSelected ==
            Tristate.isTrue,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(_repository!.requests.last.colors.single.hex, '000000');
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('search-color-check')))
            .color,
        Colors.white,
      );

      await tester.tap(find.byKey(const ValueKey('search-color-white')));
      await tester.pump(const Duration(milliseconds: 160));
      expect(controller.selectedColors.value, {FeedColor.white});
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('search-color-check')))
            .color,
        Colors.black,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(_repository!.requests.last.colors.single.hex, 'ffffff');

      await tester.tap(genre);
      await tester.pump();
      expect(controller.selectedGenres.value, {FeedGenre.nature});
      expect(
        tester.getSemantics(genre).flagsCollection.isSelected ==
            Tristate.isTrue,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(_repository!.requests.last.query, 'nature');
      expect(_repository!.requests.last.colors.single.hex, 'ffffff');

      // Repeating a selected choice clears it and returns the request to the
      // color-only query, preserving the existing single-select toggle-off UX.
      await tester.tap(genre);
      await tester.pump();
      expect(controller.selectedGenres.value, isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(_repository!.requests.last.query, isEmpty);
      expect(controller.selectedColors.value, {FeedColor.white});
      await tester.tap(find.byKey(const ValueKey('search-color-white')));
      await tester.pump();
      expect(controller.selectedColors.value, isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(_repository!.requests.last.colors, isEmpty);
      expect(find.text('By color'), findsOneWidget);
      expect(find.text('By genre'), findsOneWidget);
    });
  }

  testWidgets(
    'selecting a partly visible distant genre reveals it on a narrow row',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = await _pumpSearch(
        tester,
        brightness: Brightness.light,
      );
      // Commit an input first so subsequent refinements stay on the same
      // results route while the horizontally scrolled row updates.
      await tester.tap(find.byKey(const ValueKey('search-genre-nature')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(controller.selectedGenres.value, {FeedGenre.nature});

      final genreStrip = find.byType(ListView).last;
      final target = find.byKey(const ValueKey('search-genre-architecture'));
      var partiallyClipped = false;
      var targetRect = Rect.zero;
      var stripRect = tester.getRect(genreStrip);

      for (var attempt = 0; attempt < 10 && !partiallyClipped; attempt++) {
        await tester.drag(genreStrip, const Offset(-80, 0));
        await tester.pumpAndSettle();
        stripRect = tester.getRect(genreStrip);
        if (target.evaluate().isEmpty) continue;
        targetRect = tester.getRect(target);
        partiallyClipped =
            (targetRect.left < stripRect.left &&
                targetRect.right > stripRect.left) ||
            (targetRect.right > stripRect.right &&
                targetRect.left < stripRect.right);
      }

      expect(
        partiallyClipped,
        isTrue,
        reason: 'Architecture must be partly visible before selection.',
      );
      final tapX = targetRect.left < stripRect.left
          ? stripRect.left + 3
          : stripRect.right - 3;
      await tester.tapAt(Offset(tapX, targetRect.center.dy));
      await tester.pump();
      expect(controller.selectedGenres.value, {FeedGenre.architecture});
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pumpAndSettle();

      final revealed = tester.getRect(target);
      final updatedStrip = tester.getRect(genreStrip);
      expect(revealed.left, greaterThanOrEqualTo(updatedStrip.left - 1));
      expect(revealed.right, lessThanOrEqualTo(updatedStrip.right + 1));
    },
  );

  testWidgets('typing stays a draft until explicit search submission', (
    tester,
  ) async {
    final controller = await _pumpSearch(tester, brightness: Brightness.light);
    final field = find.byType(EditableText).first;

    await tester.enterText(field, 'forest');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_repository!.requests, isEmpty);
    expect(controller.hasCommittedInput.value, isFalse);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(_repository!.requests.single.query, 'forest');
  });
}
