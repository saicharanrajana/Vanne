import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/router/app_route.dart';

import '../support/fake_wallhaven.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

/// Collections are user-managed search shortcuts. These journeys cover the
/// full lifecycle a user can reach: open a seeded collection, create one,
/// validate the dialog, delete with confirmation, and prove every mutation
/// survives a restart (including deleting all of them — seeding must not
/// resurrect curated entries).
void main() {
  Finder tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));
  Finder collection(String name) => find.text(name);

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

  Future<void> createCollection(
    WidgetTester tester,
    TestApp app,
    String name,
  ) async {
    await app.persistTap(tester, find.text('New collection'));
    await pumpUntil(tester, find.text('New collection').last, reason: 'dialog');
    await app.enterText(tester, find.byType(TextField), name);
    await app.persistTap(tester, find.text('Create'));
    // The dialog closes only after the encode + Hive write complete, so
    // waiting for it to disappear also proves the write finished.
    await app.settleUntil(
      tester,
      () =>
          find.text('Create').evaluate().isEmpty &&
          app.collections.entries.value.any((e) => e.name == name),
      reason: 'collection persisted',
      maxRounds: 120,
    );
  }

  appTest('seeded collections render and open their search', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    // Curated shortcuts are available on first install without network.
    expect(collection('Anime'), findsOneWidget);
    expect(collection('Nature'), findsOneWidget);

    final searchesBefore = app.network.searches.length;
    await app.tap(tester, collection('Anime'));
    await pumpUntil(tester, tile('alpha'), reason: 'collection feed');

    // Opening a collection performs its persisted query, not a blank search.
    expect(app.network.searches.length, searchesBefore + 1);
    final call = app.network.searches.last;
    expect(call.query, 'anime');
    // Anime-only category bitfield (`general,anime,people` = 010).
    expect(call.categories, '010');
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

  appTest('creating a collection adds a card and opens its query', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    await createCollection(tester, app, 'moody nights');
    expect(find.text('Create'), findsNothing);
    expect(
      app.collections.entries.value.map((entry) => entry.name),
      contains('moody nights'),
    );

    // Seven cards no longer fit the viewport; scroll the new one into view.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -600),
    );
    await pumpUntil(
      tester,
      collection('Moody Nights'),
      reason: 'created collection card (display-cased)',
    );

    final searchesBefore = app.network.searches.length;
    await app.tap(tester, collection('Moody Nights'));
    await pumpUntil(tester, tile('alpha'), reason: 'new collection feed');
    expect(app.network.searches.length, searchesBefore + 1);
    expect(app.network.searches.last.query, 'moody nights');
  });

  appTest('create dialog rejects blank and duplicate names', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    await app.persistTap(tester, find.text('New collection'));
    await pumpUntil(tester, find.text('Create'), reason: 'create dialog');

    // Blank names never reach storage.
    await app.persistTap(tester, find.text('Create'));
    expect(find.text('Name required'), findsOneWidget);

    // Duplicate against a seeded entry is rejected in place.
    await app.enterText(tester, find.byType(TextField), 'Anime');
    await app.persistTap(tester, find.text('Create'));
    await pumpFrames(tester, 2);
    expect(find.text('Name already exists'), findsOneWidget);

    // Cancel leaves no card behind.
    await app.tap(tester, find.text('Cancel'));
    await pumpFrames(tester, 6);
    expect(find.text('Name already exists'), findsNothing);
    expect(collection('Anime'), findsOneWidget);
  });

  appTest('collections survive an app restart', (tester, app) async {
    await openCollections(tester, app);
    await createCollection(tester, app, 'Moody');
    expect(find.text('Create'), findsNothing);
    expect(
      app.collections.entries.value.map((entry) => entry.name),
      contains('Moody'),
    );

    await app.restart(tester);
    await app.tap(tester, tab('Collections'));
    await pumpUntil(tester, collection('Anime'), reason: 'restored cards');
    // Restored from Hive, newest card last in the grid.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -600),
    );
    await pumpUntil(tester, collection('Moody'), reason: 'restored card');
  });

  appTest('deleting selected collections asks first, then persists', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    // Long-press enters selection mode; a second tap adds to the selection.
    // Selection is local UI state (no storage), so a raw gesture is safe.
    await tester.longPress(collection('Anime'));
    await pumpFrames(tester, 4);
    expect(find.byIcon(PhosphorIconsFill.trash), findsOneWidget);

    await app.tap(tester, collection('Nature'));
    await pumpFrames(tester, 4);

    // Cancelling the confirmation must keep both collections.
    await app.persistTap(tester, find.byIcon(PhosphorIconsFill.trash));
    await pumpUntil(
      tester,
      find.text('Delete 2 collections?'),
      reason: 'delete confirmation',
    );
    await app.tap(tester, find.text('Cancel'));
    await pumpFrames(tester, 6);
    expect(collection('Anime'), findsOneWidget);
    expect(collection('Nature'), findsOneWidget);

    // Cancelling keeps the selection, so confirm it as-is.
    await app.persistTap(tester, find.byIcon(PhosphorIconsFill.trash));
    await pumpUntil(
      tester,
      find.text('Delete 2 collections?'),
      reason: 'delete confirmation',
    );
    await app.persistTap(tester, find.text('Delete'));
    // The confirmation's continuation runs in the dialog's zone; give the
    // real Hive delete time to land before asserting feedback.
    await app.settle(tester, rounds: 20);
    await app.settleUntil(
      tester,
      () => app.collections.entries.value.every(
        (entry) => entry.name != 'Anime' && entry.name != 'Nature',
      ),
      reason: 'collections deleted',
    );
    await pumpUntil(
      tester,
      find.text('Deleted 2'),
      reason: 'delete confirmation snack',
    );
    expect(collection('Anime'), findsNothing);
    expect(collection('Nature'), findsNothing);

  });

  appTest('deleting every collection stays empty after restart', (
    tester,
    app,
  ) async {
    await openCollections(tester, app);

    // Delete through the controller so the test focuses on the restart
    // contract rather than repeating the selection UI journey.
    await app.act(
      tester,
      () => app.collections.removeMany(
        {for (final entry in app.collections.entries.value) entry.id},
      ),
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
    expect(collection('Anime'), findsNothing);
  });

}
