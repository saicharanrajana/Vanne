import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';

import '../support/fixtures.dart';
import '../support/test_app.dart';

/// The shell owns four destinations and one shared back-stack. These tests
/// protect the "native app" navigation contract:
/// * every tab is reachable and remembers where it was,
/// * reselecting the active tab scrolls it to the top,
/// * system back never drops the user out of a secondary tab,
/// * full-screen routes return to the tab that opened them,
/// * the search bar cannot stack duplicate Search pages.
void main() {
  Finder navBar() => find.byType(M3ENavigationBar);

  Finder tabLabel(String label) =>
      find.descendant(of: navBar(), matching: find.text(label));

  int activeTab(WidgetTester tester) =>
      tester.widget<M3ENavigationBar>(navBar()).selectedIndex;

  Finder tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

  appTest('every destination in the bottom bar is reachable', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await app.tap(tester, tabLabel('Collections'));
    await pumpUntil(tester, find.text('Art'), reason: 'seeded collections');
    expect(activeTab(tester), 1);

    await app.tap(tester, tabLabel('Favorites'));
    await pumpUntil(
      tester,
      find.text('No favorites yet'),
      reason: 'empty favorites destination',
    );
    expect(activeTab(tester), 2);

    await app.tap(tester, tabLabel('Settings'));
    await pumpUntil(tester, find.text('Appearance'), reason: 'settings');
    expect(activeTab(tester), 3);

    await app.tap(tester, tabLabel('Discover'));
    await pumpUntil(tester, tile('alpha'), reason: 'back on discover');
    expect(activeTab(tester), 0);
  });

  appTest('switching tabs preserves each tab’s scroll position', (
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

    await app.tap(tester, tabLabel('Favorites'));
    await pumpUntil(
      tester,
      find.text('No favorites yet'),
      reason: 'favorites destination',
    );
    await app.tap(tester, tabLabel('Discover'));
    await pumpFrames(tester, 6);

    // The tab was never rebuilt from scratch: its scroll offset is intact.
    expect(discoverScroll.offset, scrolledOffset);
  });

  appTest('reselecting the active tab scrolls that tab to the top', (
    tester,
    app,
  ) async {
    app.network.searchHandler = (call) async =>
        searchPageJson(['a1', 'a2', 'a3', 'a4', 'a5', 'a6']);
    await app.launch(tester);
    await pumpUntil(tester, tile('a1'), reason: 'long discover feed');

    final discoverScroll = read<TabScrollCoordinator>().discover;
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -600),
    );
    await tester.pump();
    expect(discoverScroll.offset, greaterThan(0));

    // Tapping the already-selected destination is the native "scroll to top"
    // gesture; it must not switch tabs.
    await app.tap(tester, tabLabel('Discover'));
    await pumpFrames(tester, 12);
    expect(activeTab(tester), 0);
    expect(discoverScroll.offset, 0);
  });

  appTest('system back on a secondary tab returns to Discover', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await app.tap(tester, tabLabel('Settings'));
    await pumpUntil(tester, find.text('Appearance'), reason: 'settings tab');
    expect(activeTab(tester), 3);

    // The shell's PopScope consumes back and lands on the home tab instead of
    // letting the platform close the app.
    await app.act(tester, () => tester.binding.handlePopRoute());
    await pumpFrames(tester, 10);

    expect(activeTab(tester), 0);
    await pumpUntil(tester, tile('alpha'), reason: 'discover after back');
  });

  appTest('system back on Discover is left to the platform', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    // On the root tab canPop is true, so the shell must not swallow back by
    // switching tabs (there is nowhere to switch to). The platform request is
    // answered, and the app stays on Discover for this test harness.
    final handled = await tester.binding.handlePopRoute();
    await pumpFrames(tester, 4);

    expect(handled, isFalse);
    expect(activeTab(tester), 0);
    expect(tile('alpha'), findsOneWidget);
  });

  appTest('double-tapping search opens exactly one Search page', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    // The M3E bar can report one physical tap twice. Both events are
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
    expect(activeTab(tester), 0);
  });

  appTest('detail opened from Favorites returns to the Favorites tab', (
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
    await app.tap(tester, tabLabel('Favorites'));
    await pumpUntil(tester, tile('alpha'), reason: 'favorited tile');

    await app.tap(tester, tile('alpha'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail route',
    );
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft));
    await pumpFrames(tester, 12);

    // Back pops the detail route only; the active tab is still Favorites.
    expect(find.byType(WallpaperDetailPage), findsNothing);
    expect(activeTab(tester), 2);
    expect(tile('alpha'), findsOneWidget);
  });
}
