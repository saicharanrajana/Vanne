import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/router/app_route.dart';

import '../support/fake_wallhaven.dart';
import '../support/test_app.dart';

Finder _tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

Finder get _searchField => find.byType(EditableText);

/// Opens the Search page from the Discover search bar.
Future<void> _openSearch(WidgetTester tester, TestApp app) async {
  await app.launch(tester);
  await pumpUntil(
    tester,
    find.byKey(const ValueKey('wallpaper-tile-alpha')),
    reason: 'discover feed',
  );
  await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
  await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');
}

/// Types a query and presses the keyboard's search action.
Future<void> _submit(
  WidgetTester tester,
  TestApp app,
  String query,
) async {
  await app.enterText(tester, _searchField, query);
  // Submit is not a persistence action: keep it on the fake clock so the
  // trailing debounce timer obeys pump().
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  // The 350 ms trailing debounce must elapse before a request is sent.
  await pumpFrames(tester, 12, const Duration(milliseconds: 50));
}

void main() {
  appTest('typing alone never searches', (tester, app) async {
    await _openSearch(tester, app);

    await app.enterText(tester, _searchField, 'nature');
    await pumpFrames(tester, 20, const Duration(milliseconds: 50));

    expect(
      app.network.searches.where((c) => c.query.isNotEmpty),
      isEmpty,
      reason: 'keystrokes must not trigger I/O',
    );
    expect(find.text('Search wallpapers'), findsWidgets);
  });

  appTest('submitting a trimmed query loads results', (tester, app) async {
    await _openSearch(tester, app);
    await _submit(tester, app, '  nature  ');

    await pumpUntil(tester, _tile('alpha'), reason: 'search results');

    final search = app.network.searches.last;
    expect(search.query, 'nature', reason: 'query is trimmed');
    expect(
      app.network.searches.where((c) => c.query.isNotEmpty),
      hasLength(1),
      reason: 'one committed request per submit',
    );
  });

  appTest('rapid submissions collapse into one request with the last query', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);

    // Two commits inside the debounce window: only the trailing one runs.
    await app.enterText(tester, _searchField, 'first');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 50));
    await app.enterText(tester, _searchField, 'second');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpFrames(tester, 12, const Duration(milliseconds: 50));

    await pumpUntil(tester, _tile('alpha'), reason: 'results');

    final committed = app.network.searches
        .where((c) => c.query.isNotEmpty)
        .toList();
    expect(committed, hasLength(1));
    expect(committed.single.query, 'second');
  });

  appTest('a color chip searches by color and stays single-select', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);

    await app.tap(tester, find.byKey(const ValueKey('search-color-red')));
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    await pumpUntil(tester, _tile('alpha'), reason: 'color results');

    expect(app.network.searches.last.color, 'cc0000');

    // Selecting another color replaces the previous one.
    await app.tap(tester, find.byKey(const ValueKey('search-color-orange')));
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    expect(
      app.network.searches.last.color,
      'ff9900',
      reason: 'color chips are mutually exclusive',
    );
  });

  appTest('a genre chip appends its search term to the typed query', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);
    await _submit(tester, app, 'city');
    await pumpUntil(tester, _tile('alpha'), reason: 'typed results');

    await app.tap(tester, find.text('Abstract'));
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    expect(
      app.network.searches.last.query,
      'city abstract',
      reason: 'genre terms compose with the typed query',
    );
  });

  appTest('a failed search shows an error and Retry recovers', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);

    var offline = true;
    final previous = app.network.searchHandler;
    app.network.searchHandler = (call) async {
      if (offline && call.query == 'nature') throw const FakeOffline();
      return previous!(call);
    };

    await _submit(tester, app, 'nature');
    await pumpUntil(
      tester,
      find.text('Something went wrong'),
      reason: 'search error state',
    );

    offline = false;
    await app.tap(tester, find.text('Try again'));
    await pumpUntil(tester, _tile('alpha'), reason: 'retried results');
  });

  appTest('back returns to the Discover feed', (tester, app) async {
    await _openSearch(tester, app);

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);

    expect(find.byType(SearchPage), findsNothing);
    expect(
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      findsOneWidget,
    );
  });
}
