// Journeys: what Search does when its inputs are removed underneath it.
//
// Search composes three inputs — a typed query, one colour (plain swatch or
// saved colour collection) and one saved tag collection — into a single
// request. Inputs can disappear without the user touching the search bar
// (a saved collection is deleted from another surface, the content policy
// changes, credentials are removed), so the results have to follow the
// committed inputs at every moment.
//
// What is protected:
//  - deleting the selected colour reruns the search with the tag that is
//    still applied, instead of leaving colour+tag results on screen and
//    appending tag-only pages beneath them,
//  - deleting the last applied collection returns to the pristine screen
//    without spending a request on a search nobody asked for,
//  - submitting an empty search never fetches the generic feed,
//  - a policy change refetches a committed search and leaves a pristine one
//    untouched.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/core/collections/collection_entry.dart';
import 'package:vanne/core/security/api_key_store.dart';

import '../support/test_app.dart';

Finder _tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

Finder get _searchField => find.byType(EditableText);

/// The copy only the pristine search shows.
final _pristine = find.text(
  'Type a query, pick a color, or start from a saved collection.',
);

/// Opens Search from the Discover search bar.
Future<void> _openSearch(WidgetTester tester, TestApp app) async {
  await app.launch(tester);
  await pumpUntil(
    tester,
    find.byKey(const ValueKey('wallpaper-tile-alpha')),
    reason: 'discover feed',
  );
  await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
  await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');
}

/// Types a query and presses the keyboard's search action.
Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(_searchField, query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  // The trailing debounce must elapse before a request is sent.
  await pumpFrames(tester, 12, const Duration(milliseconds: 50));
}

/// Taps a carousel card the way a finger does: through the row's ink layer.
Future<void> _tapCard(WidgetTester tester, TestApp app, Finder card) async {
  await app.tapAt(tester, tester.getRect(card).center);
}

/// Creates a saved collection and returns its id.
Future<String> _saveCollection(
  WidgetTester tester,
  TestApp app, {
  required String name,
  required String query,
  List<String> colors = const [],
  required CollectionOrigin origin,
}) async {
  await app.act(tester, () async {
    final error = await app.collections.create(
      name: name,
      query: query,
      colors: colors,
      origin: origin,
    );
    // A duplicate name would hand back a curated seed row instead, and the
    // seed can never be deleted — the whole journey would pass vacuously.
    if (error != null) throw TestFailure('could not save "$name": $error');
  });
  return app.collections.entries.value.firstWhere((e) => e.name == name).id;
}

/// The committed search requests, keyed off the empty generic feed.
List<String> _queries(TestApp app) => [
  for (final call in app.network.searches)
    if (call.query.isNotEmpty) call.query,
];

void main() {
  appTest(
    'deleting the applied colour reruns the search with the remaining tag',
    (tester, app) async {
      await _openSearch(tester, app);

      final tagId = await _saveCollection(
        tester,
        app,
        name: 'Anime',
        query: 'anime',
        origin: CollectionOrigin.tag,
      );
      // Off-screen carousel children are not built; the applied card has to
      // lead the row the way a user would arrange it.
      await app.act(tester, () => app.collections.moveToStart(tagId));
      final colorId = await _saveCollection(
        tester,
        app,
        name: 'Blues',
        query: '',
        colors: const ['#0000ff'],
        origin: CollectionOrigin.color,
      );
      await pumpFrames(tester, 8);

      // Tag only.
      await _tapCard(tester, app, find.byKey(ValueKey('search-tag-$tagId')));
      await pumpUntil(tester, _tile('alpha'), reason: 'tag results');
      expect(app.network.searches.last.query, 'anime');

      // Tag and colour together: the colour occupies the single colour slot.
      await _tapCard(
        tester,
        app,
        find.byKey(ValueKey('search-color-collection-$colorId')),
      );
      await pumpFrames(tester, 10, const Duration(milliseconds: 50));
      expect(app.network.searches.last.query, 'anime');
      expect(
        app.network.searches.last.color,
        '0066cc',
        reason: 'the saved colour is applied',
      );

      // The colour is deleted while both are applied.
      await app.act(tester, () => app.collections.remove(colorId));
      await app.settle(tester);
      await pumpFrames(tester, 10, const Duration(milliseconds: 50));

      expect(
        find.byKey(ValueKey('search-color-collection-$colorId')),
        findsNothing,
        reason: 'the deleted card is gone from the colour row',
      );
      expect(
        find.byKey(ValueKey('search-tag-$tagId')),
        findsOneWidget,
        reason: 'the tag is still applied',
      );

      final remaining = app.network.searches.last;
      expect(
        remaining.query,
        'anime',
        reason: 'the search reruns with the tag that is still applied',
      );
      expect(
        remaining.color,
        isEmpty,
        reason: 'the deleted colour can no longer filter the results',
      );
      await pumpUntil(tester, _tile('alpha'), reason: 'tag-only results');
    },
  );

  appTest(
    'deleting the last applied collection returns to the pristine screen',
    (tester, app) async {
      await _openSearch(tester, app);

      final tagId = await _saveCollection(
        tester,
        app,
        name: 'Nightscapes',
        query: 'minimalist',
        origin: CollectionOrigin.tag,
      );
      await app.act(tester, () => app.collections.moveToStart(tagId));
      await pumpFrames(tester, 8);

      await _tapCard(tester, app, find.byKey(ValueKey('search-tag-$tagId')));
      await pumpUntil(tester, _tile('alpha'), reason: 'tag results');
      expect(app.network.searches.last.query, 'minimalist');

      final before = app.network.searches.length;
      await app.act(tester, () => app.collections.remove(tagId));
      await app.settle(tester);
      await pumpFrames(tester, 10, const Duration(milliseconds: 50));

      expect(
        app.network.searches,
        hasLength(before),
        reason: 'no input remains, so no request is spent on the generic feed',
      );
      expect(
        _pristine,
        findsOneWidget,
        reason: 'an empty search shows its pristine state again',
      );
      expect(_tile('alpha'), findsNothing);

      // The same invariant holds when the vanished collection is a colour:
      // the filter dies with its card and the bundled swatches stay put.
      final colorId = await _saveCollection(
        tester,
        app,
        name: 'Deep Blues',
        query: '',
        origin: CollectionOrigin.color,
        colors: const ['#0000ff'],
      );
      final colorCard = find.byKey(
        ValueKey('search-color-collection-$colorId'),
      );
      await _tapCard(tester, app, colorCard);
      await pumpUntil(tester, _tile('alpha'), reason: 'colour results');
      expect(app.network.searches.last.color, '0066cc');

      final beforeColorRemoval = app.network.searches.length;
      await app.act(tester, () => app.collections.remove(colorId));
      await app.settle(tester);
      await pumpFrames(tester, 10, const Duration(milliseconds: 50));

      expect(colorCard, findsNothing, reason: 'the removed card is gone');
      expect(
        app.network.searches,
        hasLength(beforeColorRemoval),
        reason: 'no other input remains, so the generic feed is never fetched',
      );
      expect(
        find.byKey(const ValueKey('search-color-black')),
        findsOneWidget,
        reason: 'the bundled swatches are untouched',
      );
      expect(_pristine, findsOneWidget);
    },
  );

  appTest('submitting an empty search never fetches the generic feed', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);
    expect(_pristine, findsOneWidget, reason: 'pristine before submitting');

    final before = app.network.searches.length;
    await _submit(tester, '   ');
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    expect(
      app.network.searches,
      hasLength(before),
      reason: 'whitespace is not a committed query',
    );
    expect(_pristine, findsOneWidget);
  });

  appTest(
    'a credential change refetches the committed search',
    (tester, app) async {
      await _openSearch(tester, app);
      expect(_pristine, findsOneWidget);

      // Nothing is committed yet, so revoking the key fetches nothing.
      await app.act(tester, () => app.settings.removeApiKey());
      await app.settle(tester);
      await pumpFrames(tester, 10, const Duration(milliseconds: 50));
      expect(
        _queries(app),
        isEmpty,
        reason: 'nothing is committed, so nothing is fetched',
      );
      expect(_pristine, findsOneWidget);

      await app.act(tester, () => app.settings.saveApiKey('stored-key'));
      await app.settle(tester);
      await _submit(tester, 'sky');
      await pumpUntil(tester, _tile('alpha'), reason: 'typed results');
      expect(_queries(app), ['sky']);

      // The key is revoked from another surface while the results are on
      // screen; the query the user is running must be re-run under the new
      // policy rather than keep showing what the old one returned.
      await app.act(tester, () => app.settings.removeApiKey());
      await app.settle(tester);
      await pumpFrames(tester, 10, const Duration(milliseconds: 50));

      expect(
        _queries(app),
        ['sky', 'sky'],
        reason: 'the same search is repeated exactly once',
      );
      expect(
        app.repository.isAuthenticated,
        isFalse,
        reason: 'the refetch runs after the key was removed',
      );
      expect(
        app.network.searches.last.query,
        'sky',
        reason: 'the repeated search is the one the user is running',
      );
      await pumpUntil(tester, _tile('alpha'), reason: 'refreshed results');
    },
    create: () =>
        TestApp(secureStorage: {SecureApiKeyStore.storageKey: 'stored-key'}),
  );
}
