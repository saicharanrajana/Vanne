import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/shared/widgets/collection_membership_button.dart';

import '../test/support/test_app.dart';

/// On-device integration journeys.
///
/// These run the REAL app on an emulator/device (real engine, Hive, isolates
/// and widget rendering) while the network and platform channels stay faked,
/// so the run is deterministic and needs no connectivity or OS dialogs.
///
///     flutter test integration_test/app_journeys_test.dart -d <emulator-id>
///
/// The deterministic widget suite (`flutter test`) gives fast feedback; this
/// suite catches device-only regressions (plugins, isolates, real painting).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

  /// Shell destination slot in the floating toolbar (harness-owned selector).
  Finder destination(String slug) => shellDestination(slug);

  /// The Add/Added control in a browsing page's app bar.
  Finder membershipButton() => find.byType(CollectionMembershipButton);

  /// The *visible* verb of the control. The widget keeps opacity-0 copies of
  /// both labels to reserve the wider slot, so state is read from the switch
  /// key rather than from raw text.
  Finder membershipVerb(String verb) =>
      find.byKey(ValueKey('collection-membership-label-$verb'));

  /// Taps a destination and lets the page transition and its spring settle.
  Future<void> goTo(WidgetTester tester, TestApp app, String slug) async {
    await app.tap(tester, destination(slug));
    await pumpFrames(tester, 24, const Duration(milliseconds: 16));
  }

  /// Opens a wallpaper's tag grid, like a user browsing from Discover.
  Future<void> openTagGrid(WidgetTester tester, TestApp app) async {
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');
    await app.tap(tester, tile('alpha'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail page',
    );
    await pumpUntil(
      tester,
      find.text('fixture-user'),
      reason: 'detail metadata loaded',
    );
    final tag = find.text('landscape').first;
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -300),
    );
    await pumpFrames(tester, 8, const Duration(milliseconds: 100));
    await tester.ensureVisible(tag);
    await pumpFrames(tester, 4);
    await app.tap(tester, tag);
    await pumpUntil(
      tester,
      find.byType(FilteredWallpapersPage),
      reason: 'tag grid',
    );
    await pumpUntil(tester, tile('alpha'), reason: 'tag results');
  }

  appTest('discover → detail → favorite → favorites → unfavorite', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await app.tap(tester, tile('alpha'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail page',
    );

    await app.persistTap(
      tester,
      find.byKey(const ValueKey('favorite-outline')).first,
    );
    expect(app.favorites.favoriteIds.value, contains('alpha'));

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await goTo(tester, app, 'favorites');
    await pumpUntil(tester, tile('alpha'), reason: 'favorite in Favorites tab');

    await app.persistTap(
      tester,
      find.byKey(const ValueKey('favorite-filled')).first,
    );
    await pumpFrames(tester, 8);
    expect(find.text('No favorites yet'), findsOneWidget);
  });

  appTest('search commit → result → detail → back to search', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');
    await app.enterText(tester, find.byType(EditableText), 'nature');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpFrames(tester, 12, const Duration(milliseconds: 50));

    await pumpUntil(tester, tile('beta'), reason: 'search results');
    await app.tap(tester, tile('beta'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail from search',
    );

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 10);
    expect(find.byType(SearchPage), findsOneWidget);
  });

  appTest('search filter carousels apply a color and a saved tag', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('search-color-black')),
      reason: 'search color carousel is laid out',
    );

    // Carousel cards paint inside an IgnorePointer picture layer, so tap the
    // card's rect the way a finger would.
    Future<void> tapCard(String key) =>
        app.tapAt(tester, tester.getRect(find.byKey(ValueKey(key))).center);

    await tapCard('search-color-black');
    await pumpFrames(tester, 12, const Duration(milliseconds: 50));
    await pumpUntil(tester, tile('alpha'), reason: 'color results');
    expect(app.network.searches.last.color, '000000');

    expect(find.text('By tag'), findsOneWidget);
    await tapCard('search-tag-seed-art');
    await pumpFrames(tester, 12, const Duration(milliseconds: 50));
    expect(app.network.searches.last.query, 'art');
    expect(app.network.searches.last.color, '000000');

    // Tapping the selected tag card again drops the tag, keeping the colour.
    await tapCard('search-tag-seed-art');
    await pumpFrames(tester, 12, const Duration(milliseconds: 50));
    expect(app.network.searches.last.query, isEmpty);
    expect(app.network.searches.last.color, '000000');
  });

  appTest('save download and open-source reach the platform fakes', (
    tester,
    app,
  ) async {
    app.storagePlatform.saveResult = const DownloadSaveSuccess(
      'content://downloads/alpha',
    );

    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');
    await app.tap(tester, tile('alpha'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail page',
    );

    // The info sheet rests at 30% height; its action row is inside the
    // scrollable content, so scroll the sheet like a user would.
    await pumpFrames(tester, 12, const Duration(milliseconds: 100));
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -300),
    );
    await pumpFrames(tester, 8, const Duration(milliseconds: 100));

    await app.persistTap(
      tester,
      find.byIcon(PhosphorIconsBold.cloudArrowDown).first,
    );
    await app.settleUntil(
      tester,
      () => app.storagePlatform.savedDownloads.isNotEmpty,
      reason: 'download saved through the platform bridge',
    );
    expect(app.storagePlatform.savedDownloads, hasLength(1));
    expect(app.storagePlatform.savedDownloads.single.treeUri, isNull);

    // Let the success snackbar clear, then use the source-link action.
    await pumpFrames(tester, 12, const Duration(milliseconds: 500));
    await app.persistTap(
      tester,
      find.byIcon(PhosphorIconsBold.linkSimple).first,
    );
    await app.settleUntil(
      tester,
      () => app.urlLauncher.opened.isNotEmpty,
      reason: 'source URL handed to the browser',
    );
    expect(
      app.urlLauncher.opened.single.toString(),
      'https://wallhaven.cc/w/alpha',
    );
  });

  appTest('shipped collections render and a tag grid can be added and removed', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await goTo(tester, app, 'collections');
    await pumpUntil(tester, find.text('Art'), reason: 'seeded collections');
    expect(find.text('Nature'), findsOneWidget);
    expect(find.text('Abstract'), findsOneWidget);
    expect(find.text('Minimal'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('collection-cover-seed-art')),
      findsOneWidget,
    );

    // A shipped collection is permanent: its browsing page offers no
    // add/remove control at all.
    await app.tap(tester, find.text('Art'));
    await pumpUntil(tester, tile('alpha'), reason: 'shipped collection feed');
    expect(membershipButton(), findsNothing);
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 10);

    // Open a wallpaper detail, then a tag grid, like a user browsing.
    await goTo(tester, app, 'discover');
    await openTagGrid(tester, app);
    expect(membershipButton(), findsOneWidget);
    expect(membershipVerb('Add'), findsOneWidget);
    expect(membershipVerb('Added'), findsNothing);

    // Add: the control fills in, and the grid stays where it is.
    await app.persistTap(tester, membershipButton());
    await app.settleUntil(
      tester,
      () => app.collections.entries.value.any((e) => e.name == 'Landscape'),
      reason: 'collection persisted',
    );
    await pumpFrames(tester, 8);
    expect(find.byType(FilteredWallpapersPage), findsOneWidget);
    expect(tile('alpha'), findsOneWidget);
    expect(membershipVerb('Added'), findsOneWidget);
    expect(membershipVerb('Add'), findsNothing);

    final entry = app.collections.entries.value.firstWhere(
      (e) => e.name == 'Landscape',
    );
    expect(entry.coverUrl, isNotNull);

    // Remove: same page, back to the outlined starting point.
    await app.persistTap(tester, membershipButton());
    await app.settleUntil(
      tester,
      () => !app.collections.entries.value.any(
        (e) => e.id == entry.id,
      ),
      reason: 'collection removed',
    );
    await pumpFrames(tester, 8);
    expect(find.byType(FilteredWallpapersPage), findsOneWidget);
    expect(tile('alpha'), findsOneWidget);
    expect(membershipVerb('Add'), findsOneWidget);
    expect(membershipVerb('Added'), findsNothing);

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await goTo(tester, app, 'collections');
    await pumpUntil(tester, find.text('Art'), reason: 'collections again');
    expect(find.text('Landscape'), findsNothing);
  });

  appTest('system back from a secondary destination returns to Discover', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await goTo(tester, app, 'settings');
    await pumpUntil(tester, find.text('Appearance'), reason: 'settings');

    // The platform back route must land on the home destination on a real
    // engine, not just in the host test binding.
    await app.act(tester, () => tester.binding.handlePopRoute());
    await pumpFrames(tester, 24, const Duration(milliseconds: 16));
    await pumpUntil(tester, tile('alpha'), reason: 'discover after back');
    expect(find.text('Appearance'), findsNothing);
  });
}
