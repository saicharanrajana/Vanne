import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/shared/utils/color_display.dart';
import 'package:vanne/shared/widgets/smart_network_image.dart';

import '../support/fake_wallhaven.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

/// Collections are saved search shortcuts. These journeys cover the full
/// lifecycle a user can reach: bundled starter cards, opening a saved search,
/// bookmarking a tag/color grid, stable cover snapshots, readable color cards,
/// deleting with confirmation, and persistence across a restart.
void main() {
  Finder tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));
  Finder collection(String name) => find.text(name);
  Finder cover(String id) => find.byKey(ValueKey('collection-cover-$id'));
  Finder surface(String id) => find.byKey(ValueKey('collection-surface-$id'));

  /// Bottom navigation label. The screen header can share the same word, so
  /// navigation taps always target the first (bar) occurrence.
  Finder tab(String label) => find.text(label).first;

  Future<void> openCollections(WidgetTester tester, TestApp app) async {
    await app.launch(tester);
    await pumpUntil(tester, tab('Collections'), reason: 'collections tab');
    await app.tap(tester, tab('Collections'));
    // The Collections header is rendered once the tab is active.
    await pumpUntil(
      tester,
      find.text('Collections'),
      reason: 'collections screen built',
    );
  }

  /// Opens the filtered grid for the first detail tag, like a user browsing
  /// from a wallpaper.
  Future<void> openTagGrid(
    WidgetTester tester,
    TestApp app, {
    bool waitForResults = true,
  }) async {
    await app.launch(tester);
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
    await pumpFrames(tester, 6, const Duration(milliseconds: 100));
    await tester.ensureVisible(tag);
    await pumpFrames(tester, 4);
    await app.tap(tester, tag);
    await pumpUntil(
      tester,
      find.byType(FilteredWallpapersPage),
      reason: 'filtered tag grid',
    );
    if (waitForResults) {
      await pumpUntil(tester, tile('alpha'), reason: 'filtered results');
    }
  }

  appTest('seeded collections render bundled covers and open their search', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    // Curated shortcuts are available on first install without network.
    for (final name in ['Art', 'Nature', 'Abstract', 'Minimal']) {
      expect(collection(name), findsOneWidget);
    }
    for (final id in [
      'seed-art',
      'seed-nature',
      'seed-abstract',
      'seed-minimal',
    ]) {
      expect(cover(id), findsOneWidget);
    }
    // Creation lives in the tag/color grid's bookmark, not this screen.
    expect(find.text('New collection'), findsNothing);

    final searchesBefore = app.network.searches.length;
    await app.tap(tester, collection('Art'));
    await pumpUntil(tester, tile('alpha'), reason: 'collection feed');

    // Opening a collection performs its persisted query, not a blank search.
    expect(app.network.searches.length, searchesBefore + 1);
    final call = app.network.searches.last;
    expect(call.query, 'art');
    expect(call.categories, '100');
    expect(find.byType(CollectionExplorePage), findsOneWidget);
  });

  appTest('collection query failures keep the screen retryable', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);
    // Fail only the collection request; Discover already succeeded.
    app.network.searchHandler = (call) async => throw const FakeOffline();

    await app.tap(tester, collection('Nature'));
    await pumpUntil(
      tester,
      find.text('Something went wrong'),
      reason: 'collection error state',
    );

    app.network.searchHandler = (call) async => searchPageJson(['alpha']);
    await app.tap(tester, find.text('Try again'));
    await pumpUntil(tester, tile('alpha'), reason: 'retried collection feed');
  });

  appTest('bookmarking a tag grid saves a stable wallpaper cover', (
    tester,
    app,
  ) async {
    await openTagGrid(tester, app);
    final searchesBefore = app.network.searches.length;

    await app.persistTap(
      tester,
      find.byIcon(PhosphorIconsBold.bookmarkSimple).first,
    );
    await app.settleUntil(
      tester,
      () => app.collections.entries.value.any((e) => e.name == 'Landscape'),
      reason: 'bookmarked collection persisted',
    );

    // The first already-fetched result becomes the cover; saving does not
    // issue a cover-only search.
    final entry = app.collections.entries.value.firstWhere(
      (e) => e.name == 'Landscape',
    );
    expect(entry.coverUrl, 'https://thumbs.test/lg/alpha.jpg');
    expect(app.network.searches.length, searchesBefore);
    expect(entry.coverAsset, isNull);

    // Back to the shell, then into Collections.
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(tester, collection('Landscape'), reason: 'bookmarked card');

    final coverWidget = tester.widget<SmartNetworkImage>(cover(entry.id));
    expect(coverWidget.url, 'https://thumbs.test/lg/alpha.jpg');

    // Reopening with different first results must not replace the snapshot.
    app.network.searchHandler = (call) async => searchPageJson(['beta']);
    await app.tap(tester, collection('Landscape'));
    await pumpUntil(tester, tile('beta'), reason: 'collection feed');

    final afterOpen = app.collections.entries.value.firstWhere(
      (e) => e.id == entry.id,
    );
    expect(afterOpen.coverUrl, 'https://thumbs.test/lg/alpha.jpg');

    await app.restart(tester);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(
      tester,
      collection('Landscape'),
      reason: 'restored bookmark',
    );
    final restored = app.collections.entries.value.firstWhere(
      (e) => e.id == entry.id,
    );
    expect(restored.coverUrl, 'https://thumbs.test/lg/alpha.jpg');
    expect(cover(entry.id), findsOneWidget);
  });

  appTest('saving before results saves with a fallback cover', (
    tester,
    app,
  ) async {
    // Hold the filtered search open so the bookmark is tapped before the
    // first page arrives.
    final pending = Completer<Map<String, dynamic>>();
    app.network.searchHandler = (call) => call.query == 'landscape'
        ? pending.future
        : searchPageJson(['alpha', 'beta']);

    await openTagGrid(tester, app, waitForResults: false);
    await app.persistTap(
      tester,
      find.byIcon(PhosphorIconsBold.bookmarkSimple).first,
    );
    await app.settleUntil(
      tester,
      () => app.collections.entries.value.any((e) => e.name == 'Landscape'),
      reason: 'bookmarked without results',
    );

    final entry = app.collections.entries.value.firstWhere(
      (e) => e.name == 'Landscape',
    );
    expect(entry.coverUrl, isNull);

    // Late results do not change the snapshot taken at save time.
    await tester.runAsync(() async {
      pending.complete(searchPageJson(['alpha']));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await pumpFrames(tester, 6);
    expect(
      app.collections.entries.value
          .firstWhere((e) => e.id == entry.id)
          .coverUrl,
      isNull,
    );

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(tester, collection('Landscape'), reason: 'fallback card');
    expect(cover(entry.id), findsNothing);
  });

  appTest('legacy collections fill a missing cover only on a grid visit', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);
    await app.act(
      tester,
      () => app.collections.create(name: 'legacy find', query: 'legacy'),
    );
    await pumpUntil(
      tester,
      collection('Legacy Find'),
      reason: 'legacy collection card',
    );
    final entry = app.collections.entries.value.firstWhere(
      (e) => e.name == 'legacy find',
    );
    expect(entry.coverUrl, isNull);
    expect(cover(entry.id), findsNothing);

    app.network.searchHandler = (call) async => searchPageJson(['alpha']);
    await app.tap(tester, collection('Legacy Find'));
    await pumpUntil(tester, tile('alpha'), reason: 'collection grid');
    await app.settleUntil(
      tester,
      () =>
          app.collections.entries.value
              .firstWhere((e) => e.id == entry.id)
              .coverUrl !=
          null,
      reason: 'cover filled from the visited grid',
    );

    expect(
      app.collections.entries.value
          .firstWhere((e) => e.id == entry.id)
          .coverUrl,
      'https://thumbs.test/lg/alpha.jpg',
    );
  });

  appTest('color collections show a readable name, exact hex and contrast', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);
    await app.act(
      tester,
      () => app.collections.create(
        name: '#663399',
        query: '',
        colors: const ['#663399'],
      ),
    );

    await pumpUntil(
      tester,
      find.text('Vivid Purple'),
      reason: 'human-readable color title',
    );
    expect(find.text('#663399'), findsOneWidget);

    final entry = app.collections.entries.value.firstWhere(
      (e) => e.name == '#663399',
    );
    final background = tester
        .widget<M3EShapeContainer>(surface(entry.id))
        .color;
    expect(background, const Color(0xFF663399));

    final title = tester.widget<Text>(find.text('Vivid Purple'));
    final subtitle = tester.widget<Text>(find.text('#663399'));
    expect(
      ColorDisplay.contrastRatio(title.style!.color!, background!),
      greaterThanOrEqualTo(ColorDisplay.minimumContrast),
    );
    expect(
      ColorDisplay.contrastRatio(subtitle.style!.color!, background),
      greaterThanOrEqualTo(ColorDisplay.minimumContrast),
    );
  });

  appTest('bookmarking a wallpaper color keeps the exact hex end to end', (
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
    await pumpUntil(
      tester,
      find.text('fixture-user'),
      reason: 'detail metadata loaded',
    );

    final swatch = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'View #123456 wallpapers',
    );
    await tester.ensureVisible(swatch);
    await pumpFrames(tester, 6, const Duration(milliseconds: 100));
    await app.tap(tester, swatch);
    await pumpUntil(
      tester,
      find.byType(FilteredWallpapersPage),
      reason: 'color grid',
    );
    await pumpUntil(tester, tile('alpha'), reason: 'color results');

    await app.persistTap(
      tester,
      find.byIcon(PhosphorIconsBold.bookmarkSimple).first,
    );
    await app.settleUntil(
      tester,
      () => app.collections.entries.value.any((e) => e.name == '#123456'),
      reason: 'color collection persisted',
    );
    final entry = app.collections.entries.value.firstWhere(
      (e) => e.name == '#123456',
    );
    expect(entry.colors, ['#123456']);
    expect(find.byIcon(PhosphorIconsFill.bookmarkSimple), findsOneWidget);

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(
      tester,
      find.text('Midnight Blue'),
      reason: 'color card title',
    );
    expect(find.text('#123456'), findsOneWidget);
    expect(
      tester.widget<M3EShapeContainer>(surface(entry.id)).color,
      const Color(0xFF123456),
    );

    await app.restart(tester);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(
      tester,
      find.text('Midnight Blue'),
      reason: 'restored color card',
    );
    final restored = app.collections.entries.value.firstWhere(
      (e) => e.id == entry.id,
    );
    expect(restored.name, '#123456');
    expect(restored.colors, ['#123456']);
    expect(find.text('#123456'), findsOneWidget);
  });

  appTest('color cards fit narrow phones at large text scale', (
    tester,
    app,
  ) async {
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // Navigate at the normal phone size, then apply the narrowest supported
    // width and the large-text setting to the Collections screen itself.
    await openCollections(tester, app);
    await app.act(
      tester,
      () => app.collections.create(
        name: '#663399',
        query: '',
        colors: const ['#663399'],
      ),
    );
    await pumpUntil(tester, find.text('Vivid Purple'), reason: 'color card');

    tester.view.physicalSize = const Size(320, 700);
    for (final scale in [1.3, 1.5, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'no layout overflow at $scale',
      );
      expect(find.text('#663399'), findsOneWidget);
    }
  });

  appTest('removing selected collections asks first, then persists', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);
    await app.act(
      tester,
      () => app.favorites.toggle(placeholderWallpaper('alpha')),
    );
    expect(app.favorites.favoriteIds.value, contains('alpha'));

    // Long-press enters selection mode; a second tap adds to the selection.
    // Selection is local UI state (no storage), so a raw gesture is safe.
    await tester.longPress(collection('Art'));
    await pumpFrames(tester, 4);
    expect(find.byIcon(PhosphorIconsFill.trash), findsOneWidget);

    await app.tap(tester, collection('Nature'));
    await pumpFrames(tester, 4);

    // Cancelling the confirmation must keep both collections.
    await app.persistTap(tester, find.byIcon(PhosphorIconsFill.trash));
    await pumpUntil(
      tester,
      find.text('Remove 2 collections?'),
      reason: 'delete confirmation',
    );
    await app.tap(tester, find.text('Cancel'));
    await pumpFrames(tester, 6);
    expect(collection('Art'), findsOneWidget);
    expect(collection('Nature'), findsOneWidget);

    // Cancelling keeps the selection, so confirm it as-is.
    await app.persistTap(tester, find.byIcon(PhosphorIconsFill.trash));
    await pumpUntil(
      tester,
      find.text('Remove 2 collections?'),
      reason: 'delete confirmation',
    );
    await app.persistTap(tester, find.text('Remove'));
    // The confirmation's continuation runs in the dialog's zone; give the
    // real Hive delete time to land before asserting feedback.
    await app.settle(tester, rounds: 20);
    await app.settleUntil(
      tester,
      () => app.collections.entries.value.every(
        (entry) => entry.name != 'Art' && entry.name != 'Nature',
      ),
      reason: 'collections deleted',
    );
    await pumpUntil(
      tester,
      find.text('Removed 2'),
      reason: 'delete confirmation snack',
    );
    expect(collection('Art'), findsNothing);
    expect(collection('Nature'), findsNothing);
    expect(
      app.favorites.favoriteIds.value,
      contains('alpha'),
      reason: 'removing collections leaves favorites untouched',
    );
  });

  appTest('removing every collection stays empty after restart', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    // Delete through the controller so the test focuses on the restart
    // contract rather than repeating the selection UI journey.
    await app.act(
      tester,
      () => app.collections.removeMany({
        for (final entry in app.collections.entries.value) entry.id,
      }),
    );
    await pumpFrames(tester, 6);
    expect(find.text('No collections yet'), findsOneWidget);

    // A curated seed must not come back on the next launch.
    await app.restart(tester);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(
      tester,
      find.text('No collections yet'),
      reason: 'empty collections after restart',
    );
    expect(collection('Art'), findsNothing);
  });
}
