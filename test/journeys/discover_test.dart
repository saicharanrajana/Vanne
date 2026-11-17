import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:vanne/app/router/app_route.dart';

import '../support/fake_wallhaven.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

Finder _tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

/// Discover's filter trigger: a toolbar action, not a chip in the header.
Finder get _filterTrigger =>
    find.byKey(const ValueKey('feed-filter-trigger-discover'));

/// The feed grid is the vertical scrollable on Discover.
Finder get _feed => find.byType(Scrollable).first;

/// A real user scroll gesture near the feed's end. The footer is already
/// within the load-more threshold, so one gesture is enough; stopping at one
/// keeps the request count deterministic.
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(_feed, const Offset(0, -200));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  appTest('Discover renders page 1 and sends the global content policy', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha'), reason: 'first discover tile');

    expect(_tile('beta'), findsOneWidget);

    // Exactly one request, portrait-only SFW, default newest sorting.
    expect(app.network.searches, hasLength(1));
    final call = app.network.searches.single;
    expect(call.page, 1);
    expect(call.query, isEmpty);
    expect(call.ratios, 'portrait');
    expect(call.categories, '100', reason: 'Discover defaults to General');
    // Purity is always stated on the wire, even when it is the SFW-only
    // default: the client cache and request deduper key on the query, so an
    // omitted purity could not be told apart from an all-purities request.
    expect(call.purity, '100', reason: 'SFW only');
    // date_added sorting is still the API default, so it stays omitted.
    expect(call.sorting, isEmpty);
  });

  appTest('a failed first page shows an error and Retry recovers', (
    tester,
    app,
  ) async {
    var offline = true;
    app.network.searchHandler = (call) async {
      if (offline) throw const FakeOffline();
      return searchPageJson(const ['alpha']);
    };

    await app.launch(tester);
    await pumpUntil(
      tester,
      find.textContaining('connection'),
      reason: 'first-load error message',
    );

    offline = false;
    await app.tap(tester, find.text('Try again'));
    await pumpUntil(tester, _tile('alpha'), reason: 'tile after retry');
    expect(app.network.searches, hasLength(2));
  });

  appTest('an empty result shows the empty state, not an error', (
    tester,
    app,
  ) async {
    app.network.searchHandler = (call) async => searchPageJson(const []);

    await app.launch(tester);
    await pumpUntil(
      tester,
      find.text('No wallpapers found'),
      reason: 'empty state',
    );
  });

  appTest('scrolling loads page 2 once and drops duplicate ids', (
    tester,
    app,
  ) async {
    app.network.searchHandler = (call) async => switch (call.page) {
      // The same wallpaper appears on both pages: it must render once.
      // Enough tiles to make the feed scroll without overscrolling.
      1 => searchPageJson(
        [for (var i = 0; i < 4; i++) 'alpha$i', 'beta'],
        currentPage: 1,
        lastPage: 2,
      ),
      _ => searchPageJson(
        const ['beta', 'gamma'],
        currentPage: 2,
        lastPage: 2,
      ),
    };

    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha0'), reason: 'page 1');

    await _scrollToEnd(tester);

    await pumpUntil(tester, _tile('gamma'), reason: 'page 2 tile');
    expect(_tile('beta'), findsOneWidget, reason: 'duplicate id rendered once');
    expect(
      app.network.searches.map((c) => c.page),
      [1, 2],
      reason: 'page 2 requested exactly once',
    );
  });

  appTest('a page-2 failure keeps page 1 and retries in place', (
    tester,
    app,
  ) async {
    var page2Fails = true;
    app.network.searchHandler = (call) async {
      if (call.page == 1) {
        return searchPageJson(
          [for (var i = 0; i < 4; i++) 'alpha$i'],
          currentPage: 1,
          lastPage: 2,
        );
      }
      if (page2Fails) throw const FakeOffline();
      return searchPageJson(const ['gamma'], currentPage: 2, lastPage: 2);
    };

    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha0'), reason: 'page 1');

    await _scrollToEnd(tester);
    await pumpUntil(
      tester,
      find.text('Unable to load more'),
      reason: 'pagination error footer',
    );
    expect(
      _tile('alpha3'),
      findsOneWidget,
      reason: 'loaded content must survive a pagination failure',
    );

    page2Fails = false;
    await app.tap(tester, find.text('Try again'));
    await pumpUntil(tester, _tile('gamma'), reason: 'retried page 2');
    expect(app.network.searches.map((c) => c.page), [1, 2, 2]);
  });

  appTest('applying a filter reloads with the chosen sorting and category', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha'), reason: 'default feed');

    await app.tap(tester, _filterTrigger);
    await pumpUntil(tester, find.text('Sort & Filter'), reason: 'filter sheet');

    final applyButton = find.widgetWithText(M3EButton, 'Apply');
    final resetButton = find.widgetWithText(M3EButton, 'Reset');
    expect(applyButton, findsOneWidget);
    expect(resetButton, findsOneWidget);
    final applyRect = tester.getRect(applyButton);
    final resetRect = tester.getRect(resetButton);
    expect(applyRect.height, 56);
    expect(resetRect.height, applyRect.height);
    expect(resetRect.width, applyRect.width);
    final applyText = tester.widget<Text>(find.text('Apply'));
    final resetText = tester.widget<Text>(find.text('Reset'));
    expect(applyText.style?.fontSize, 18);
    expect(resetText.style?.fontSize, 18);
    expect(applyText.style?.color, isNull);
    expect(resetText.style?.color, isNull);
    final m3eScheme = M3ETheme.of(tester.element(applyButton)).colorScheme;
    final applyParagraph = tester.renderObject<RenderParagraph>(
      find.text('Apply'),
    );
    final resetParagraph = tester.renderObject<RenderParagraph>(
      find.text('Reset'),
    );
    expect(applyParagraph.text.style?.color, m3eScheme.onPrimary);
    expect(resetParagraph.text.style?.color, m3eScheme.onSurfaceVariant);

    await app.tap(tester, find.text('Most viewed'));
    await app.tap(tester, find.text('Anime'));
    await app.tap(tester, find.text('Apply'));

    await app.settleUntil(
      tester,
      () => app.network.searches.length == 2,
      reason: 'filtered request sent',
    );
    expect(app.network.searches, hasLength(2));
    final applied = app.network.searches.last;
    expect(applied.sorting, 'views');
    expect(applied.categories, '110');
    expect(applied.page, 1);
  });

  appTest('dismissing the filter sheet does not refetch', (tester, app) async {
    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha'), reason: 'default feed');

    await app.tap(tester, _filterTrigger);
    await pumpUntil(tester, find.text('Sort & Filter'), reason: 'filter sheet');
    await app.tap(tester, find.text('Most viewed'));
    // Closing without Apply discards the draft.
    // Tapping the scrim dismisses the sheet without applying the draft.
    await app.act(tester, () async {
      await tester.tapAt(const Offset(8, 8));
    });
    await pumpFrames(tester, 8);

    expect(app.network.searches, hasLength(1));
  });

  appTest('a superseded first request cannot overwrite the new feed', (
    tester,
    app,
  ) async {
    final firstRequest = Completer<Map<String, dynamic>>();
    var calls = 0;
    app.network.searchHandler = (call) {
      calls++;
      if (calls == 1) return firstRequest.future;
      return Future.value(searchPageJson(const ['gamma']));
    };

    await app.launch(tester);
    // Page 1 for the default filter is still pending.
    expect(app.network.searches, hasLength(1));

    // Trigger a reload by applying a different filter.
    await app.tap(tester, _filterTrigger);
    await pumpUntil(tester, find.text('Sort & Filter'), reason: 'filter sheet');
    await app.tap(tester, find.text('Most viewed'));
    await app.tap(tester, find.text('Apply'));
    await app.settleUntil(
      tester,
      () => app.network.searches.length == 2,
      reason: 'second generation request sent',
    );
    await pumpUntil(tester, _tile('gamma'), reason: 'new generation result');

    // The stale response arrives last and must be ignored.
    firstRequest.complete(searchPageJson(const ['alpha']));
    await pumpFrames(tester, 10);

    expect(_tile('gamma'), findsOneWidget);
    expect(
      _tile('alpha'),
      findsNothing,
      reason: 'stale results must not corrupt the current feed',
    );
  });

  appTest('tapping a tile opens the wallpaper detail', (tester, app) async {
    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha'), reason: 'discover tile');

    await app.tap(tester, _tile('alpha'));
    await pumpFrames(tester, 10);

    expect(find.byType(WallpaperDetailPage), findsOneWidget);
    expect(app.network.detailIds, contains('alpha'));
  });

  appTest(
    'the toolbar hosts the filter action without becoming a destination',
    (tester, app) async {
      await app.launch(tester);
      await pumpUntil(tester, _tile('alpha'), reason: 'default feed');

      // The header no longer carries a shelf of filter text: one glyph says it.
      expect(
        find.text('Newest'),
        findsNothing,
        reason: 'the dynamic filter summary is gone',
      );
      expect(
        find.descendant(of: find.byType(M3EToolbar), matching: _filterTrigger),
        findsOneWidget,
        reason: 'filters are a toolbar action',
      );

      final pill = find.byKey(const ValueKey('nav-selection-pill'));
      final pillBefore = tester.getRect(pill);

      await app.tap(tester, _filterTrigger);
      await pumpUntil(
        tester,
        find.text('Sort & Filter'),
        reason: 'filter sheet',
      );
      await app.tap(tester, find.text('Most viewed'));
      await app.tap(tester, find.text('Apply'));
      await app.settleUntil(
        tester,
        () => app.network.searches.length == 2,
        reason: 'filtered request sent',
      );
      expect(app.network.searches.last.sorting, 'views');

      final pillAfter = tester.getRect(pill);
      expect(
        pillAfter.top,
        pillBefore.top,
        reason: 'filter actions never move the toolbar vertically',
      );
      expect(
        pillAfter.bottom,
        pillBefore.bottom,
        reason: 'filter actions never change the toolbar height',
      );
      expect(
        find.byKey(const ValueKey('nav-selected-label-0')),
        findsOneWidget,
        reason: 'Discover remains the selected destination',
      );
      expect(
        find.descendant(of: find.byType(M3EToolbar), matching: _filterTrigger),
        findsOneWidget,
        reason: 'still on Discover, still hosting its filter action',
      );
    },
  );
}
