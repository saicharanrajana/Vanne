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
  appTest('favoriting a tile shows it in the Favorites tab', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha'), reason: 'discover tile alpha');

    await app.persistTap(tester, _favoriteButton('alpha'));
    expect(app.favorites.favoriteIds.value, contains('alpha'));

    await app.tap(tester, find.text('Favorites').first);
    await pumpFrames(tester, 10);
    expect(_tile('alpha'), findsOneWidget);
    expect(_unfavoriteButton('alpha'), findsOneWidget);
  });

  appTest('favorites survive an app restart', (tester, app) async {
    await app.launch(tester);
    await pumpUntil(tester, _tile('alpha'), reason: 'discover tile alpha');
    await app.persistTap(tester, _favoriteButton('alpha'));
    await app.restart(tester);

    await app.tap(tester, find.text('Favorites').first);
    await pumpFrames(tester, 10);
    expect(_tile('alpha'), findsOneWidget);
  });
}
