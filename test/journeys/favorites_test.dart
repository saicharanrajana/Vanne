import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

Finder _tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

Finder _favoriteButton(String id) => find.descendant(
  of: _tile(id),
  matching: find.byKey(const ValueKey('favorite-outline')),
);

Finder _unfavoriteButton(String id) => find.descendant(
  of: _tile(id),
  matching: find.byKey(const ValueKey('favorite-filled')),
);

void main() {
  appTest('favorites survive an app restart', (tester, app) async {
    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha'), reason: 'discover tile alpha');
    await app.persistTap(tester, _favoriteButton('alpha'));
    expect(app.favorites.favoriteIds.value, contains('alpha'));

    // The action shows up in Favorites immediately, before the restart.
    await app.tap(tester, shellDestination('favorites'));
    await pumpFrames(tester, 10);
    expect(_tile('alpha'), findsOneWidget);
    expect(_unfavoriteButton('alpha'), findsOneWidget);

    await app.restart(tester);

    await app.tap(tester, shellDestination('favorites'));
    await pumpFrames(tester, 10);
    expect(_tile('alpha'), findsOneWidget);
  });

  appTest('a short favorites list shows no end-of-feed marker', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha'), reason: 'discover tile alpha');
    await app.persistTap(tester, _favoriteButton('alpha'));
    await app.persistTap(tester, _favoriteButton('beta'));

    await app.tap(tester, shellDestination('favorites'));
    await pumpFrames(tester, 10);
    expect(_tile('alpha'), findsOneWidget);
    expect(_tile('beta'), findsOneWidget);

    // Favorites is a finite local list; it never reports an "end of feed".
    expect(find.text("You've reached the end"), findsNothing);

    // Unfavoriting down to the empty state keeps the plain empty view.
    await app.persistTap(tester, _unfavoriteButton('alpha'));
    await app.persistTap(tester, _unfavoriteButton('beta'));
    await pumpFrames(tester, 6);
    expect(find.text('No favorites yet'), findsOneWidget);
    expect(find.text("You've reached the end"), findsNothing);
  });
}
