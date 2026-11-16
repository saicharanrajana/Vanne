import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/core/collections/collection_entry.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/shared/utils/color_display.dart';
import 'package:vanne/shared/widgets/collection_membership_button.dart';
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

  /// The `+ Add` / `✓ Added` app-bar control of a tag or color browsing page.
  /// Exactly one is on screen, so type lookup is unambiguous.
  final membership = find.byType(CollectionMembershipButton);

  /// Bottom toolbar destination. The screen header can share the same word, so
  /// navigation taps target the shell's stable slot key rather than text.
  Finder tab(String label) =>
      find.byKey(ValueKey('nav-${label.toLowerCase()}'));

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
      expect(
        app.collections.entries.value.firstWhere((e) => e.id == id).coverColors,
        isNotEmpty,
        reason: 'seeded covers carry a palette sampled from the asset',
      );
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

    await app.persistTap(tester, membership);
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
    expect(
      entry.coverColors,
      ['#123456', '#ABCDEF'],
      reason: 'the palette travels with the wallpaper that supplied the cover',
    );
    expect(
      entry.origin,
      CollectionOrigin.tag,
      reason: 'a tag grid bookmark is recorded as a tag collection',
    );

    // Back to the shell, then into Collections.
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await app.settleUntil(
      tester,
      () => find.byType(FilteredWallpapersPage).evaluate().isEmpty,
      reason: 'tag grid popped',
    );
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await app.settleUntil(
      tester,
      () => find.byType(WallpaperDetailPage).evaluate().isEmpty,
      reason: 'detail popped',
    );
    // Only tap the shell once the popped routes are gone: a route that is
    // still animating out covers the floating toolbar.
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
    expect(afterOpen.coverColors, [
      '#123456',
      '#ABCDEF',
    ], reason: 'the palette snapshot is as stable as the cover');

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
    expect(restored.coverColors, ['#123456', '#ABCDEF']);
    expect(restored.origin, CollectionOrigin.tag);
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
    await app.persistTap(tester, membership);
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
    await app.settleUntil(
      tester,
      () => find.byType(FilteredWallpapersPage).evaluate().isEmpty,
      reason: 'tag grid popped',
    );
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await app.settleUntil(
      tester,
      () => find.byType(WallpaperDetailPage).evaluate().isEmpty,
      reason: 'detail popped',
    );
    // Only tap the shell once the popped routes are gone: a route that is
    // still animating out covers the floating toolbar.
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

    final filled = app.collections.entries.value.firstWhere(
      (e) => e.id == entry.id,
    );
    expect(filled.coverUrl, 'https://thumbs.test/lg/alpha.jpg');
    expect(filled.coverColors, [
      '#123456',
      '#ABCDEF',
    ], reason: 'the palette is captured with the cover it describes');
  });

  appTest('stored cover palettes normalize at the JSON boundary', (
    tester,
    app,
  ) async {
    final entry = CollectionEntry.fromJson({
      'id': 'palette-json',
      'name': 'palette json',
      'query': 'palette',
      'coverColors': [
        '#abc',
        '#AABBCC',
        'not-a-hex',
        '#123456',
        '#234567',
        '#345678',
        '#456789',
        '#56789A',
        '#6789AB',
      ],
      'createdAt': '2025-01-01T00:00:00.000',
    });

    expect(entry.coverColors, [
      '#AABBCC',
      '#123456',
      '#234567',
      '#345678',
      '#456789',
    ]);

    final malformed = CollectionEntry.fromJson({
      'id': 'palette-json-malformed',
      'name': 'palette json malformed',
      'query': 'palette',
      'coverColors': {'unexpected': 'object'},
      'createdAt': '2025-01-01T00:00:00.000',
    });
    expect(malformed.coverColors, isEmpty);
  });

  appTest('a legacy cover gains the palette of that same wallpaper', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);
    // Two rows saved before palettes existed: one whose cover the next grid
    // visit will show again, and one whose cover it will not.
    await app.act(tester, () async {
      await app.collections.create(
        name: 'seeing alpha',
        query: 'seeing',
        origin: CollectionOrigin.tag,
        coverUrl: 'https://thumbs.test/small/alpha.jpg',
      );
      await app.collections.create(
        name: 'missing zeta',
        query: 'missing',
        origin: CollectionOrigin.tag,
        coverUrl: 'https://thumbs.test/lg/zeta.jpg',
      );
    });
    CollectionEntry entryNamed(String name) =>
        app.collections.entries.value.firstWhere((e) => e.name == name);

    app.network.searchHandler = (call) async => searchPageJson(['alpha']);
    await app.tap(tester, collection('Seeing Alpha'));
    await pumpUntil(tester, tile('alpha'), reason: 'collection grid');
    await app.settleUntil(
      tester,
      () => entryNamed('seeing alpha').coverColors.isNotEmpty,
      reason: 'palette attached to the already-saved cover',
    );

    final seen = entryNamed('seeing alpha');
    expect(
      seen.coverUrl,
      'https://thumbs.test/small/alpha.jpg',
      reason: 'palette backfill must not replace the saved thumbnail URL',
    );
    expect(seen.coverColors, ['#123456', '#ABCDEF']);

    // A different cover was never on screen, so it gets no invented palette.
    expect(entryNamed('missing zeta').coverColors, isEmpty);

    await app.restart(tester);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(
      tester,
      collection('Seeing Alpha'),
      reason: 'restored legacy cover',
    );
    final restored = app.collections.entries.value.firstWhere(
      (e) => e.name == 'seeing alpha',
    );
    expect(restored.coverUrl, 'https://thumbs.test/small/alpha.jpg');
    expect(restored.coverColors, ['#123456', '#ABCDEF']);
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

    await app.persistTap(tester, membership);
    await app.settleUntil(
      tester,
      () => app.collections.entries.value.any((e) => e.name == '#123456'),
      reason: 'color collection persisted',
    );
    final entry = app.collections.entries.value.firstWhere(
      (e) => e.name == '#123456',
    );
    expect(entry.colors, ['#123456']);
    expect(
      entry.origin,
      CollectionOrigin.color,
      reason: 'a colour grid bookmark is recorded as a colour collection',
    );
    expect(
      find.byKey(const ValueKey('collection-membership-label-Added')),
      findsOneWidget,
    );

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await app.settleUntil(
      tester,
      () => find.byType(FilteredWallpapersPage).evaluate().isEmpty,
      reason: 'tag grid popped',
    );
    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await app.settleUntil(
      tester,
      () => find.byType(WallpaperDetailPage).evaluate().isEmpty,
      reason: 'detail popped',
    );
    // Only tap the shell once the popped routes are gone: a route that is
    // still animating out covers the floating toolbar.
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
    expect(restored.origin, CollectionOrigin.color);
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

  appTest(
    'the app bar adds then removes the browsing page collection in place',
    (tester, app) async {
      await openTagGrid(tester, app);

      Finder label(String state) =>
          find.byKey(ValueKey('collection-membership-label-$state'));

      // Not saved yet: an outlined verb, not a bookmark glyph.
      expect(label('Added'), findsNothing);
      final addSize = tester.getSize(membership);
      final backIcon = find.byIcon(PhosphorIconsBold.arrowLeft).first;
      final backButton = find
          .ancestor(of: backIcon, matching: find.byType(M3EIconButton))
          .first;
      final backButtonTarget = tester.getRect(backButton);
      final backRect = tester.getRect(backIcon);
      final titleRect = tester.getRect(find.text('Landscape'));
      final buttonRect = tester.getRect(membership);
      final pill = find.descendant(
        of: membership,
        matching: find.byKey(const ValueKey('collection-membership-pill')),
      );
      expect(
        buttonRect.right,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio -
              (backButtonTarget.left + (backButtonTarget.width - 32) / 2),
          1,
        ),
        reason: 'the visible right action inset mirrors the back surface inset',
      );
      expect(
        buttonRect.center.dy,
        closeTo(backRect.center.dy, 1),
        reason:
            'membership action and back button share the app-bar centerline',
      );
      expect(
        buttonRect.center.dy,
        closeTo(titleRect.center.dy, 1),
        reason: 'membership action and title share the app-bar centerline',
      );
      expect(
        buttonRect.height,
        48,
        reason: 'the action retains a 48 dp hit target',
      );
      expect(tester.getSize(pill).height, 32);

      // Inspect an in-flight transition, not just the final Added state. The
      // tap runs in the real async zone for Hive, then fake time advances only
      // partway through the expressive label transition.
      await tester.runAsync(() async => tester.tap(membership));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(label('Added'), findsOneWidget);
      final addedLabelFade = find
          .ancestor(of: label('Added'), matching: find.byType(FadeTransition))
          .first;
      final addedOpacity = tester
          .widget<FadeTransition>(addedLabelFade)
          .opacity
          .value;
      expect(
        addedOpacity,
        inExclusiveRange(0.0, 1.0),
        reason: 'the Added label visibly fades/slides in instead of snapping',
      );
      await app.settleUntil(
        tester,
        () =>
            app.collections.entries.value.any(
              (e) => e.query == 'landscape' && e.origin == CollectionOrigin.tag,
            ) &&
            !tester.widget<CollectionMembershipButton>(membership).pending,
        reason: 'collection saved from the browsing page',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await pumpUntil(tester, label('Added'), reason: 'Added state');
      expect(
        tester.getSize(membership),
        addSize,
        reason: 'Add and Added keep the same footprint',
      );

      // The browsing page is not replaced or reset by saving.
      expect(find.byType(FilteredWallpapersPage), findsOneWidget);
      expect(tile('alpha'), findsOneWidget);

      // A second tap removes that exact collection and stays put.
      await tester.runAsync(() async => tester.tap(membership));
      await tester.pump();
      await app.settleUntil(
        tester,
        () =>
            !app.collections.entries.value.any((e) => e.query == 'landscape') &&
            !tester.widget<CollectionMembershipButton>(membership).pending,
        reason: 'the collection was removed',
      );
      await tester.pump(const Duration(milliseconds: 90));
      expect(label('Add'), findsOneWidget);
      final addLabelFade = find
          .ancestor(of: label('Add'), matching: find.byType(FadeTransition))
          .first;
      final addOpacity = tester
          .widget<FadeTransition>(addLabelFade)
          .opacity
          .value;
      expect(
        addOpacity,
        inExclusiveRange(0.0, 1.0),
        reason: 'the Add label visibly returns during removal',
      );
      await pumpUntil(tester, label('Add'), reason: 'back to Add');
      expect(tester.getSize(membership), addSize);
      expect(
        find.byType(FilteredWallpapersPage),
        findsOneWidget,
        reason: 'removal keeps the browsing page open',
      );
      expect(
        tile('alpha'),
        findsOneWidget,
        reason: 'removal keeps the results the user was looking at',
      );
      expect(
        app.collections.entries.value.where((e) => e.isTagCollection).length,
        greaterThanOrEqualTo(2),
        reason: 'curated tag collections are untouched by a user removal',
      );
    },
  );

  appTest(
    'same-subject filters do not select the wrong collection and session id stays exact',
    (tester, app) async {
      await openTagGrid(tester, app);

      // A legacy row can carry an explicit category list that overrides its
      // filter categories at request time. Its subject/name must not make it
      // Added for this General-category browsing request.
      await app.act(
        tester,
        () => app.collections.create(
          name: 'Landscape',
          query: 'landscape',
          kinds: [WallhavenCategory.anime],
          filter: const FeedFilter(),
          origin: CollectionOrigin.tag,
        ),
      );
      await pumpUntil(tester, membership, reason: 'membership action present');
      expect(
        find.byKey(const ValueKey('collection-membership-label-Added')),
        findsNothing,
        reason: 'same query and name with different effective categories is not Added',
      );

      await app.persistTap(tester, membership);
      await app.settleUntil(
        tester,
        () => app.collections.entries.value.any(
          (e) => e.name == 'Landscape (2)' && e.query == 'landscape',
        ),
        reason: 'different filter definition saved under a unique name',
      );
      final sessionEntry = app.collections.entries.value.firstWhere(
        (e) => e.name == 'Landscape (2)',
      );
      final otherEntry = app.collections.entries.value.firstWhere(
        (e) => e.name == 'Landscape',
      );
      expect(
        find.byKey(const ValueKey('collection-membership-label-Added')),
        findsOneWidget,
      );

      // Change the browsing filter so exact query identity no longer matches
      // the session-created row. Its remembered ID still owns this toggle.
      await app.tap(tester, find.text('Newest'));
      await pumpUntil(
        tester,
        find.text('Sort & Filter'),
        reason: 'filter sheet',
      );
      await app.tap(tester, find.text('Anime'));
      await app.tap(tester, find.text('Apply'));
      await pumpFrames(tester, 12);
      expect(
        find.byKey(const ValueKey('collection-membership-label-Added')),
        findsOneWidget,
        reason: 'session save stays Added after a session-only filter change',
      );

      await app.persistTap(tester, membership);
      await app.settleUntil(
        tester,
        () => app.collections.entryById(sessionEntry.id) == null,
        reason: 'removes the exact id created in this browsing session',
      );
      expect(app.collections.entryById(otherEntry.id), isNotNull);
      expect(
        find.byKey(const ValueKey('collection-membership-label-Add')),
        findsOneWidget,
      );
    },
  );

  appTest('curated collections are permanent and offer no toggle', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    // Permanence is enforced below the UI, not just by hiding a button.
    late bool removed;
    await app.act(
      tester,
      () async => removed = await app.collections.remove('seed-art'),
    );
    expect(removed, isFalse);
    expect(
      app.collections.entries.value.any((e) => e.id == 'seed-art'),
      isTrue,
      reason: 'a curated collection cannot be deleted',
    );

    // Inside a curated collection there is no membership control at all.
    await app.tap(tester, collection('Art'));
    await pumpUntil(tester, tile('alpha'), reason: 'curated feed');
    expect(
      membership,
      findsNothing,
      reason: 'permanent collections show no Add/Added control',
    );
  });

  appTest('dragging a collection reorders the grid and survives a restart', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    List<String> order() => [
      for (final entry in app.collections.entries.value) entry.id,
    ];
    expect(order(), [
      'seed-art',
      'seed-nature',
      'seed-abstract',
      'seed-minimal',
    ]);

    // Long-press the first card and drop it on the second: move-by-drag, not
    // selection. The curated beginning of the list moves like any other row.
    final start = tester.getCenter(surface('seed-art'));
    final target = tester.getCenter(surface('seed-nature'));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(target + const Offset(0, 6));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await app.settle(tester, rounds: 20);

    expect(order(), [
      'seed-nature',
      'seed-art',
      'seed-abstract',
      'seed-minimal',
    ], reason: 'drag moved the card past its neighbour');

    await app.restart(tester);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(tester, collection('Art'), reason: 'restored grid');
    expect(order(), [
      'seed-nature',
      'seed-art',
      'seed-abstract',
      'seed-minimal',
    ], reason: 'the user order is stored, not just remembered in memory');
  });

  appTest('a new collection is appended after the user order', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    // Move Minimal to the front through the card menu, then save a fresh
    // search: it belongs at the end, not next to the curated block it was
    // created from, and the chosen order must not be reshuffled by the add.
    final minimalMenu = find.descendant(
      of: surface('seed-minimal'),
      matching: find.byIcon(PhosphorIconsBold.dotsThree),
    );
    await tester.ensureVisible(minimalMenu);
    await app.persistTap(tester, minimalMenu);
    await pumpUntil(tester, find.text('Move to start'), reason: 'reorder menu');
    await app.persistTap(tester, find.text('Move to start'));
    await app.settleUntil(
      tester,
      () => app.collections.entries.value.first.id == 'seed-minimal',
      reason: 'moved Minimal to the front',
    );

    await app.act(
      tester,
      () => app.collections.create(
        name: 'Landscape',
        query: 'landscape',
        origin: CollectionOrigin.tag,
      ),
    );
    await app.settleUntil(
      tester,
      () => app.collections.entries.value.any((e) => e.name == 'Landscape'),
      reason: 'saved a new collection',
    );

    expect(
      app.collections.entries.value.last.name,
      'Landscape',
      reason: 'new collections append to the end of the user order',
    );
    expect(
      app.collections.entries.value.first.id,
      'seed-minimal',
      reason: 'the chosen order is untouched by adding',
    );

    await app.restart(tester);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(tester, collection('Landscape'), reason: 'restored add');
    expect(
      [for (final entry in app.collections.entries.value) entry.name],
      ['Minimal', 'Art', 'Nature', 'Abstract', 'Landscape'],
      reason: 'order and append survive a restart',
    );
  });
}
