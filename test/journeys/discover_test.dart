import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanne/app/router/app_route.dart';

import '../support/fake_wallhaven.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

Finder _tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

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
    // Purity and date_added sorting are the API defaults, so they are
    // omitted from the wire request rather than sent redundantly.
    expect(call.purity, isEmpty);
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

    await app.tap(tester, find.text('Newest'));
    await pumpUntil(tester, find.text('Sort & Filter'), reason: 'filter sheet');

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

    await app.tap(tester, find.text('Newest'));
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
    await app.tap(tester, find.text('Newest'));
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
}
