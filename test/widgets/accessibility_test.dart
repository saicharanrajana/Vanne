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

  appTest('every toolbar destination is reachable and labelled', (
    tester,
    app,
  ) async {
    // The semantics tree must be released before the test ends.
    final semantics = tester.ensureSemantics();
    try {
      await app.launch(tester);
      await pumpUntil(
        tester,
        find.byKey(const ValueKey('wallpaper-tile-alpha')),
        reason: 'discover feed',
      );

      const destinations = {
        'discover': 'Discover',
        'collections': 'Collections',
        'favorites': 'Favorites',
        'settings': 'Settings',
      };
      var selectedIndex = 0;
      for (final entry in destinations.entries) {
        // Each slot announces its own name and its selection state.
        final slot = find.descendant(
          of: find.byType(M3EToolbar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == entry.value,
          ),
        );
        expect(slot, findsOneWidget, reason: '${entry.value} slot exists');
        expect(
          find.bySemanticsLabel(entry.value),
          findsWidgets,
          reason: '${entry.value} is named for assistive tech',
        );
        await app.tap(tester, slot);
        await pumpFrames(tester, 24);
        expect(
          find.byKey(ValueKey('nav-selected-label-$selectedIndex')),
          findsOneWidget,
          reason: 'visible label for ${entry.value}',
        );
        for (var index = 0; index < destinations.length; index++) {
          if (index != selectedIndex) {
            expect(
              find.byKey(ValueKey('nav-selected-label-$index')),
              findsNothing,
            );
          }
        }
        selectedIndex++;
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
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
}
