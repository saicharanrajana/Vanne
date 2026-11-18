import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/app/router/shell_navigation.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';

import '../support/fixtures.dart';
import '../support/test_app.dart';

/// The shell owns four destinations, a floating M3E toolbar and one shared
/// back-stack. These tests protect the "native app" navigation contract:
/// * every destination is reachable, labelled and individually selectable,
/// * the selection indicator is one shared pill that lands on the active slot,
/// * a distant switch moves straight there instead of travelling through the
///   destinations in between,
/// * every tab remembers where it was, and reselecting scrolls it back up,
/// * system back never drops the user out of a secondary destination,
/// * full-screen routes return to the destination that opened them,
/// * the search bar cannot stack duplicate Search pages.
void main() {
  /// Destination slots expose a stable key. The index mirrors the tab order
  /// the shell's back policy relies on: 0 Discover … 3 Settings.
  const slugs = ['discover', 'collections', 'favorites', 'settings'];
  const labels = {
    'discover': 'Discover',
    'collections': 'Collections',
    'favorites': 'Favorites',
    'settings': 'Settings',
  };

  /// A destination slot inside the floating toolbar. The harness owns the
  /// selector so every suite taps the same slot; the semantics of each slot
  /// (name + selected flag) is asserted separately below.
  Finder destination(String slug) => shellDestination(slug);

  /// The one shared selection indicator that travels between destinations.
  Finder selectionPill() => find.byKey(const ValueKey('nav-selection-pill'));

  /// Each destination's outlined glyph and its selected counterpart. The
  /// selected state is also announced through semantics (asserted in the
  /// accessibility journey); here it is read off the glyph a user sees.
  const glyphs = {
    'discover': (PhosphorIconsBold.compass, PhosphorIconsFill.compass),
    'collections': (PhosphorIconsBold.stack, PhosphorIconsFill.stack),
    'favorites': (PhosphorIconsBold.heart, PhosphorIconsFill.heart),
    'settings': (PhosphorIconsBold.gear, PhosphorIconsFill.gear),
  };

  /// Whether the slot is painting its selected glyph, i.e. is the active one.
  bool showsSelectedGlyph(WidgetTester tester, String slug) {
    final (outline, filled) = glyphs[slug]!;
    final slot = destination(slug);
    return find
            .descendant(of: slot, matching: find.byIcon(filled))
            .evaluate()
            .isNotEmpty &&
        find
            .descendant(of: slot, matching: find.byIcon(outline))
            .evaluate()
            .isEmpty;
  }

  Finder tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

  /// Waits out the toolbar's spring so geometry assertions see the resting
  /// position rather than a frame mid-flight.
  Future<void> settleNav(WidgetTester tester) async {
    await pumpFrames(tester, 30, const Duration(milliseconds: 16));
  }

  Future<void> goTo(WidgetTester tester, TestApp app, String slug) async {
    await app.tap(tester, destination(slug));
    await settleNav(tester);
  }

  /// The destination's own content, used to prove where the shell actually
  /// went rather than trusting the toolbar's internal state.
  Finder contentOf(String slug) => switch (slug) {
    'discover' => tile('alpha'),
    'collections' => find.text('Art'),
    'favorites' => find.text('No favorites yet'),
    'settings' => find.text('Appearance'),
    _ => throw ArgumentError(slug),
  };

  appTest(
    'each destination is reachable, labelled and only the active one is selected',
    (tester, app) async {
    // The semantics tree is what a screen reader walks, so this is the only
    // journey that turns it on. It must be released before the test ends.
    final semantics = tester.ensureSemantics();
    try {
      await app.launch(tester);
      await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

      // Assistive tech can still name every icon slot.
      for (final slug in slugs) {
        expect(
          find.bySemanticsLabel(labels[slug]!),
          findsWidgets,
          reason: '${labels[slug]} must expose a semantics label',
        );
      }

      // The selected flag follows the active destination, so an icon-only bar
      // never relies on colour alone.
      void expectOnlySelected(String active) {
        for (final slug in slugs) {
          expect(
            tester.getSemantics(destination(slug)),
            slug == active
                ? isSemantics(isSelected: true, isButton: true)
                : isNot(isSemantics(isSelected: true)),
            reason: '${labels[slug]} selected state with $active active',
          );
        }
      }

      // Every destination is reachable, paints its own content, marks itself
      // selected, and never draws a glyph over its own label.
      for (final slug in ['collections', 'favorites', 'settings', 'discover']) {
        await goTo(tester, app, slug);
        await pumpUntil(
          tester,
          contentOf(slug),
          reason: '${labels[slug]} destination content',
        );
        expectOnlySelected(slug);

        final labelRect = tester.getRect(
          find.byKey(ValueKey('nav-selected-label-${slugs.indexOf(slug)}')),
        );
        expect(
          tester.getRect(destination(slug)).contains(labelRect.center),
          isTrue,
          reason: '${labels[slug]} label sits inside its slot',
        );
        final glyphs = find.descendant(
          of: find.byKey(const ValueKey('shell-navigation-row')),
          matching: find.byType(Icon),
        );
        for (final element in glyphs.evaluate()) {
          final box = element.renderObject! as RenderBox;
          expect(
            (box.localToGlobal(Offset.zero) & box.size).overlaps(labelRect),
            isFalse,
            reason: '${labels[slug]} glyph never overlaps its label',
          );
        }
      }

      expectOnlySelected('discover');
      expect(
        find.byKey(const ValueKey('nav-selected-label-0')),
        findsOneWidget,
      );
      for (var index = 1; index < slugs.length; index++) {
        expect(find.byKey(ValueKey('nav-selected-label-$index')), findsNothing);
      }
      final initialPill = tester.getRect(selectionPill());
      await tester.tap(destination('settings'));
      // Build the new selection first: the animation starts on that frame.
      await tester.pump();
      // Half-way through the pan: assert the indicator's geometry. The label
      // itself lands in the last sliver of the travel (asserted after settle),
      // so it is never caught clipped mid-resize.
      await tester.pump(const Duration(milliseconds: 160));
      final movingPill = tester.getRect(selectionPill());
      final targetSlot = tester.getRect(destination('settings'));

      // The pill *is* the selected slot's rectangle on every frame, so it can
      // never drift off the destination it marks while the row reflows.
      expect(movingPill.left, closeTo(targetSlot.left, 0.5));
      expect(movingPill.width, closeTo(targetSlot.width, 0.5));
      expect(
        movingPill.width,
        greaterThan(ShellNavigationToolbar.destinationExtent),
        reason: 'mid-flight the pill is already growing for its label',
      );
      expect(
        movingPill.left,
        isNot(closeTo(initialPill.left, 0.5)),
        reason: 'the pill left the destination it used to mark',
      );
      final pill = tester.getRect(selectionPill());
      expect(pill.width, greaterThan(ShellNavigationToolbar.destinationExtent));
      await goTo(tester, app, 'settings');
      await pumpUntil(tester, find.text('Appearance'), reason: 'settings');
      expectOnlySelected('settings');
      expect(
        find.byKey(const ValueKey('nav-selected-label-3')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('nav-selected-label-0')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  appTest(
    'the scrollable content can reach its final item behind the overlay',
    (tester, app) async {
      await app.launch(tester);
      await pumpUntil(tester, tile('alpha'), reason: 'discover feed');
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -1800),
      );
      await pumpFrames(tester, 10, const Duration(milliseconds: 80));
      final scrollable = find.byType(CustomScrollView).first;
      await tester.dragUntilVisible(
        tile('beta'),
        scrollable,
        const Offset(0, -300),
      );
      expect(tile('beta'), findsOneWidget);
      expect(
        tester.getRect(tile('beta')).bottom,
        lessThan(tester.getRect(selectionPill()).top),
        reason: 'the final content item can be scrolled clear of the toolbar',
      );
    },
  );

  appTest('a distant switch never travels through the destinations between', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');
    final searchesBefore = app.network.searches.length;

    await tester.tap(destination('settings'));
    // Frame by frame through the transition: an intermediate page sliding
    // past would put its content on screen here.
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.text('No favorites yet'),
        findsNothing,
        reason: 'Favorites is not on the way to Settings',
      );
      expect(
        find.text('Art'),
        findsNothing,
        reason: 'Collections is not on the way to Settings',
      );
    }
    await settleNav(tester);
    await pumpUntil(tester, find.text('Appearance'), reason: 'settings');
    expect(
      app.network.searches.length,
      searchesBefore,
      reason: 'passing destinations must not load their feeds',
    );

    // The slot the Discover filter trigger occupied is inert while another
    // destination is shown: tapping there must not open its sheet.
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('shell-filter-fab'))),
    );
    await pumpFrames(tester, 12);
    expect(
      find.text('Sort & Filter'),
      findsNothing,
      reason: 'an off-destination filter slot is inert',
    );
  });

  appTest('horizontal swipes do not switch destinations', (tester, app) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    // Page-style motion is tap-driven; a horizontal drag on content stays a
    // no-op for navigation, so it cannot fight a screen's own gestures.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(-260, 0),
    );
    await settleNav(tester);

    expect(tile('alpha'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);
    expect(showsSelectedGlyph(tester, 'discover'), isTrue);
  });

  appTest('switching destinations preserves each one’s scroll position', (
    tester,
    app,
  ) async {
    // A long first page guarantees the feed is actually scrollable.
    app.network.searchHandler = (call) async =>
        searchPageJson(['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8']);
    await app.launch(tester);
    await pumpUntil(tester, tile('a1'), reason: 'long discover feed');

    final discoverScroll = read<TabScrollCoordinator>().discover;
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -600),
    );
    await tester.pump();
    final scrolledOffset = discoverScroll.offset;
    expect(scrolledOffset, greaterThan(0));

    await goTo(tester, app, 'favorites');
    await pumpUntil(
      tester,
      find.text('No favorites yet'),
      reason: 'favorites destination',
    );
    await goTo(tester, app, 'discover');

    // The destination was never rebuilt from scratch: its offset is intact.
    expect(discoverScroll.offset, scrolledOffset);

    // Tapping the already-active destination is the native "scroll to top"
    // gesture; it must not navigate anywhere else.
    await goTo(tester, app, 'discover');
    expect(discoverScroll.offset, 0);
    expect(tile('a1'), findsOneWidget);
  });

  appTest('system back on a secondary destination returns to Discover', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await goTo(tester, app, 'settings');
    await pumpUntil(tester, find.text('Appearance'), reason: 'settings');

    // The shell's PopScope consumes back and lands on the home destination
    // instead of letting the platform close the app.
    await app.act(tester, () => tester.binding.handlePopRoute());
    await settleNav(tester);

    await pumpUntil(tester, tile('alpha'), reason: 'discover after back');
    expect(find.text('Appearance'), findsNothing);

    // On the root destination canPop is true, so the shell must not swallow
    // back by switching destinations (there is nowhere to switch to).
    final handled = await tester.binding.handlePopRoute();
    await pumpFrames(tester, 4);
    expect(handled, isFalse);
    expect(tile('alpha'), findsOneWidget);
  });

  appTest('double-tapping search opens exactly one Search page', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    // The M3E search bar can report one physical tap twice. Both events are
    // delivered before any frame, so the route guard must recognise that a
    // Search page is already on the stack and collapse the duplicate.
    await app.act(tester, () async {
      await tester.tap(find.byType(M3ESearchBar).first);
      await tester.tap(find.byType(M3ESearchBar).first);
    });
    await pumpFrames(tester, 10);
    expect(find.byType(SearchPage), findsOneWidget);

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft));
    await pumpFrames(tester, 12);
    expect(find.byType(SearchPage), findsNothing);
    expect(tile('alpha'), findsOneWidget);
  });

  appTest('detail opened from Favorites returns to the Favorites destination', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await app.persistTap(
      tester,
      find.descendant(
        of: tile('alpha'),
        matching: find.byKey(const ValueKey('favorite-outline')),
      ),
    );
    await goTo(tester, app, 'favorites');
    await pumpUntil(tester, tile('alpha'), reason: 'favorited tile');

    await app.tap(tester, tile('alpha'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail route',
    );
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft));
    await pumpFrames(tester, 12);

    // Back pops the detail route only. The filled heart proves the shell
    // returned to Favorites rather than to Discover, whose copy of the tile
    // still shows the outline.
    expect(find.byType(WallpaperDetailPage), findsNothing);
    expect(tile('alpha'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('favorite-filled')),
      findsOneWidget,
      reason: 'the Favorites copy of the tile kept its filled heart',
    );
    expect(find.byKey(const ValueKey('favorite-outline')), findsNothing);
  });





  appTest('reduced motion skips the motion without hiding the destinations', (
    tester,
    app,
  ) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    final surface = find.byKey(const ValueKey('shell-filter-fab'));
    final fade = find.descendant(
      of: surface,
      matching: find.byType(FadeTransition),
    );
    double opacity() => tester.widget<FadeTransition>(fade.first).opacity.value;
    final phase = 'navigation still reaches every destination';

    // Android reports "remove animations"; iOS/web report "reduce motion".
    // Either request must skip the fade, and neither may hide a destination.
    final inputs = <String, FakeAccessibilityFeatures>{
      'disableAnimations': const FakeAccessibilityFeatures(
        disableAnimations: true,
      ),
      'reduceMotion': const FakeAccessibilityFeatures(reduceMotion: true),
    };
    for (final entry in inputs.entries) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = entry.value;
      await pumpFrames(tester, 8);
      await goTo(tester, app, 'discover');
      await pumpUntil(tester, tile('alpha'), reason: 'discover, ${entry.key}');
      await pumpFrames(tester, 6);
      expect(opacity(), 1, reason: 'trigger shown on Discover, ${entry.key}');

      await tester.tap(destination('collections'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        opacity(),
        0,
        reason: 'no linger when ${entry.key} is requested',
      );
      await pumpUntil(tester, find.text('Art'), reason: 'collections, ${entry.key}');
      expect(tester.takeException(), isNull, reason: '$phase (${entry.key})');
      final screenCenter = tester
          .getRect(find.byType(ShellTabTransition))
          .center
          .dx;
      expect(
        tester
            .getRect(find.byKey(const ValueKey('shell-navigation-row')))
            .center
            .dx,
        closeTo(screenCenter, 1),
        reason: 'the hidden FAB leaves the pill centered, ${entry.key}',
      );

      await tester.tap(destination('discover'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(opacity(), 1, reason: 'returns without a fade, ${entry.key}');
      await pumpUntil(tester, tile('alpha'), reason: 'discover, ${entry.key}');
      expect(tester.takeException(), isNull, reason: '$phase (${entry.key})');
    }
  });


  appTest('retargeting lands on the last choice, before or during motion', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    // Three switches before a single frame: only the last one may win.
    await app.act(tester, () async {
      await tester.tap(destination('settings'));
      await tester.tap(destination('favorites'));
      await tester.tap(destination('collections'));
    });
    await settleNav(tester);
    await pumpUntil(tester, find.text('Art'), reason: 'collections wins');
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('No favorites yet'), findsNothing);
    expect(showsSelectedGlyph(tester, 'collections'), isTrue);
    final quickSlot = tester.getRect(destination('collections'));
    expect(
      tester.getRect(selectionPill()).center.dx,
      inInclusiveRange(quickSlot.left, quickSlot.right),
      reason: 'the indicator follows the destination that won',
    );

    await tester.tap(destination('settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // A second choice arrives while the first is still crossing the screen.
    await tester.tap(destination('collections'));
    await pumpFrames(tester, 4, const Duration(milliseconds: 16));
    await tester.tap(destination('favorites'));
    await settleNav(tester);

    await pumpUntil(tester, contentOf('favorites'), reason: 'favorites wins');
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('Art'), findsNothing);
    final body = tester.getRect(find.byType(ShellTabTransition));
    expect(
      tester.getRect(find.byType(FavoritesTabPage)).left,
      closeTo(body.left, 0.5),
      reason: 'the final page is flush, not stranded mid-flight',
    );
    final slot = tester.getRect(destination('favorites'));
    expect(
      tester.getRect(selectionPill()).center.dx,
      inInclusiveRange(slot.left, slot.right),
      reason: 'the pill settles on the destination that won',
    );
  });
}
