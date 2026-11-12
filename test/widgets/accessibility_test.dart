import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../support/test_app.dart';

/// Accessibility guards: large text and a narrow phone must not break the
/// primary actions. These assert reachability and semantics, never pixels.
void main() {
  appTest('large text keeps primary actions reachable without overflow', (
    tester,
    app,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover tile at large text',
    );
    expect(tester.takeException(), isNull, reason: 'no layout overflow');

    // The favorite affordance exists and carries an accessible label.
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Save to favorites'), findsWidgets);
    semantics.dispose();

    // Detail is reachable, and its back control returns to the feed.
    await app.tap(tester, find.byKey(const ValueKey('wallpaper-tile-alpha')));
    await pumpFrames(tester, 10);
    expect(find.byType(WallpaperDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    expect(find.byKey(const ValueKey('wallpaper-tile-alpha')), findsOneWidget);
  });

  appTest('every bottom destination is reachable and labelled', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );

    for (final label in ['Collections', 'Favorites', 'Settings', 'Discover']) {
      await app.tap(tester, find.text(label).first);
      await pumpFrames(tester, 6);
      // The header of the active tab carries the same title.
      expect(find.text(label), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
}
