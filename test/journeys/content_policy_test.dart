// Journeys: which user choices are allowed to change what a live feed shows.
//
// Purity, blocked tags and the API key are read fresh on every request, so the
// coverage for "a policy change refreshes the retained tab" lives in
// `settings_test.dart` (that is where the user makes those choices). This file
// covers the two boundaries that file does not: changes that must *never*
// spend a request, and a page that was already in flight when the policy
// changed.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fixtures.dart';
import '../support/test_app.dart';

Finder _tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

Finder get _feed => find.byType(CustomScrollView).first;

void main() {
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(shellDestination('settings'));
    await pumpFrames(tester, 6);
    await pumpUntil(tester, find.text('Appearance'), reason: 'settings screen');
  }

  /// Scrolls the settings list until [finder] is built and on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 6 && finder.evaluate().isEmpty; i++) {
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -260),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  appTest('appearance changes never refetch a feed', (tester, app) async {
    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha'), reason: 'discover feed');

    await openSettings(tester);
    final before = app.network.searches.length;

    await reveal(tester, find.text('Pitch black mode'));
    await app.persistTap(tester, find.text('Pitch black mode'));
    await reveal(tester, find.text('Use dynamic color'));
    await app.persistTap(tester, find.text('Use dynamic color'));
    await app.settle(tester);

    expect(
      app.network.searches,
      hasLength(before),
      reason: 'theme choices do not change what the API may return',
    );
  });

  appTest('a page fetched under the old policy never lands after a change', (
    tester,
    app,
  ) async {
    // Page 2 is held open so the policy can change while it is in flight.
    final gate = Completer<Map<String, dynamic>>();
    const firstPage = ['a1', 'a2', 'a3', 'a4', 'a5', 'a6'];
    app.network.searchHandler = (call) async {
      if (call.excludedTags.contains('anime')) {
        return searchPageJson(const ['filtered']);
      }
      if (call.page == 2) return gate.future;
      return searchPageJson(firstPage, lastPage: 2);
    };

    await app.launch(tester);
    await pumpUntil(tester, _tile('a1'), reason: 'first page');

    // Scroll far enough that the feed asks for page 2.
    await tester.drag(_feed, const Offset(0, -2400));
    await pumpFrames(tester, 10, const Duration(milliseconds: 100));
    await app.settleUntil(
      tester,
      () => app.network.searches.any((call) => call.page == 2),
      reason: 'second page request',
    );

    // The user saves a blocked tag while page 2 is still loading.
    await app.act(tester, () async => app.settings.setBlockedTags({'anime'}));
    await app.settleUntil(
      tester,
      () => app.network.searches.last.excludedTags.contains('anime'),
      reason: 'the feed restarts under the new policy',
    );
    await app.settle(tester);

    // The superseded page arrives last.
    await tester.runAsync(() async {
      gate.complete(searchPageJson(const ['b1'], currentPage: 2, lastPage: 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await app.settle(tester);
    await tester.drag(_feed, const Offset(0, 3200));
    await pumpFrames(tester, 10, const Duration(milliseconds: 100));

    expect(
      _tile('b1'),
      findsNothing,
      reason: 'a page fetched under the old policy is dropped, not appended',
    );
    expect(
      _tile('a1'),
      findsNothing,
      reason: 'the first page fetched before the exclusion is dropped too',
    );
    expect(
      _tile('filtered'),
      findsOneWidget,
      reason: 'the grid shows only what the new policy returned',
    );
  });
}
