import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
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

  appTest('the search filter carousels fit a narrow phone at large text', (
    tester,
    app,
  ) async {
    // The header height is computed from the text scale, so this guards the
    // arithmetic that keeps both carousel rows inside the sliver.
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');
    await pumpFrames(tester, 6);

    expect(find.text('By color'), findsOneWidget);
    expect(find.text('By tag'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no layout overflow');

    // A committed search shows the sort/filter chip too; the tallest header
    // variant must still fit. Black is the leading card, so it is on screen
    // without scrolling the row first.
    await app.tapAt(
      tester,
      tester.getRect(find.byKey(const ValueKey('search-color-black'))).center,
    );
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'color results',
    );
    expect(tester.takeException(), isNull, reason: 'no layout overflow');
  });

  appTest('the floating toolbar keeps touch targets on a narrow phone', (
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
      reason: 'discover feed at large text',
    );

    for (final slug in ['discover', 'collections', 'favorites', 'settings']) {
      final rect = tester.getRect(find.byKey(ValueKey('nav-$slug')));
      expect(
        rect.width,
        greaterThanOrEqualTo(48),
        reason: '$slug stays a comfortable target at 320 dp',
      );
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$slug height');
    }
    expect(tester.takeException(), isNull, reason: 'no layout overflow');
  });

  appTest('the Discover filter action fits beside the destinations', (
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
      reason: 'discover feed at large text',
    );

    final trigger = find.byKey(const ValueKey('feed-filter-trigger-discover'));
    expect(trigger, findsOneWidget, reason: 'the action is available');
    // The trigger springs in; measure it at rest.
    await pumpFrames(tester, 20);

    // The trigger is the bar's own adjacent FAB, so the target is the FAB
    // surface rather than the glyph that names it.
    final target = tester.getRect(
      find.ancestor(of: trigger, matching: find.byType(M3EFab)),
    );
    expect(target.width, greaterThanOrEqualTo(48), reason: 'filter target');
    expect(target.height, greaterThanOrEqualTo(48), reason: 'filter height');

    // The visible destination band and actionable FAB stay within the narrow
    // viewport; M3E's full-width positioning wrapper may extend beyond it while
    // the internally centered controls remain safely inset.
    final row = tester.getRect(
      find.byKey(const ValueKey('shell-navigation-row')),
    );
    expect(row.left, greaterThanOrEqualTo(0));
    expect(row.right, lessThanOrEqualTo(320.5), reason: 'nav stays on screen');
    expect(target.left, greaterThanOrEqualTo(0));
    expect(
      target.right,
      lessThanOrEqualTo(320.5),
      reason: 'filter FAB stays on screen',
    );
    expect(tester.takeException(), isNull, reason: 'no layout overflow');
  });
}
