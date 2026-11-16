import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/core/collections/collection_entry.dart';
import 'package:vanne/core/collections/seed_collections.dart';

import '../support/fake_wallhaven.dart';
import '../support/test_app.dart';

Finder _tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

Finder get _searchField => find.byType(EditableText);

/// Opens the Search page from the Discover search bar.
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
Future<void> _submit(WidgetTester tester, TestApp app, String query) async {
  await app.enterText(tester, _searchField, query);
  // Submit is not a persistence action: keep it on the fake clock so the
  // trailing debounce timer obeys pump().
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  // The 350 ms trailing debounce must elapse before a request is sent.
  await pumpFrames(tester, 12, const Duration(milliseconds: 50));
}

/// Taps a carousel card.
///
/// A carousel item paints its card inside an `IgnorePointer` picture layer, so
/// the widget itself is never in the hit-test path; the carousel's own ink
/// layer above it is. Tapping the card's centre exercises exactly the gesture
/// a user makes.
Future<void> _tapCard(WidgetTester tester, TestApp app, Finder card) async {
  await app.tapAt(tester, tester.getRect(card).center);
}

void main() {
  appTest('typing alone never searches', (tester, app) async {
    await _openSearch(tester, app);

    await app.enterText(tester, _searchField, 'nature');
    await pumpFrames(tester, 20, const Duration(milliseconds: 50));

    expect(
      app.network.searches.where((c) => c.query.isNotEmpty),
      isEmpty,
      reason: 'keystrokes must not trigger I/O',
    );
    expect(find.text('Search wallpapers'), findsWidgets);
  });

  appTest('submitting a trimmed query loads results', (tester, app) async {
    await _openSearch(tester, app);
    await _submit(tester, app, '  nature  ');

    await pumpUntil(tester, _tile('alpha'), reason: 'search results');

    final search = app.network.searches.last;
    expect(search.query, 'nature', reason: 'query is trimmed');
    expect(
      app.network.searches.where((c) => c.query.isNotEmpty),
      hasLength(1),
      reason: 'one committed request per submit',
    );
  });

  appTest('rapid submissions collapse into one request with the last query', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);

    // Two commits inside the debounce window: only the trailing one runs.
    await app.enterText(tester, _searchField, 'first');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 50));
    await app.enterText(tester, _searchField, 'second');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpFrames(tester, 12, const Duration(milliseconds: 50));

    await pumpUntil(tester, _tile('alpha'), reason: 'results');

    final committed = app.network.searches
        .where((c) => c.query.isNotEmpty)
        .toList();
    expect(committed, hasLength(1));
    expect(committed.single.query, 'second');
  });

  appTest('a color card searches by color and stays single-select', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);

    expect(find.text('By color'), findsOneWidget);

    await _tapCard(
      tester,
      app,
      find.byKey(const ValueKey('search-color-black')),
    );
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    await pumpUntil(tester, _tile('alpha'), reason: 'color results');

    expect(app.network.searches.last.color, '000000');

    // Selecting another color replaces the previous one.
    await _tapCard(
      tester,
      app,
      find.byKey(const ValueKey('search-color-white')),
    );
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    expect(
      app.network.searches.last.color,
      'ffffff',
      reason: 'color cards are mutually exclusive',
    );
  });

  appTest('a saved tag collection composes with the typed query and toggles', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);
    await _submit(tester, app, 'city');
    await pumpUntil(tester, _tile('alpha'), reason: 'typed results');

    expect(find.text('By tag'), findsOneWidget);

    final artCard = find.byKey(const ValueKey('search-tag-seed-art'));
    await _tapCard(tester, app, artCard);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    expect(
      app.network.searches.last.query,
      'city art',
      reason: 'the collection tag composes with the typed query',
    );

    // Tapping the selected card again clears the tag.
    await _tapCard(tester, app, artCard);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    expect(app.network.searches.last.query, 'city');
  });

  appTest('the colour row scrolls to reveal further colour cards', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);
    final before = app.network.searches.length;

    // Cards keep a fixed extent and the row snaps to the nearest one, so reach
    // the fourth colour by dragging and then letting the snap settle. None of
    // these drags may apply a filter.
    final carousel = find.byKey(const ValueKey('search-color-carousel'));
    final orange = find.byKey(const ValueKey('search-color-orange'));
    for (var i = 0; i < 4; i++) {
      if (orange.evaluate().isNotEmpty) {
        final card = tester.getRect(orange);
        final viewport = tester.getRect(carousel);
        if (card.left >= 0 && card.right <= viewport.right) break;
      }
      await tester.drag(carousel, const Offset(-250, 0));
      await pumpFrames(tester, 12, const Duration(milliseconds: 50));
    }
    expect(
      app.network.searches,
      hasLength(before),
      reason: 'scrolling must not apply a filter',
    );

    // Let the snap animation finish before tapping: a card mid-snap does not
    // accept taps, exactly as in the real carousel.
    await pumpFrames(tester, 20, const Duration(milliseconds: 100));
    await _tapCard(tester, app, orange);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    await pumpUntil(tester, _tile('alpha'), reason: 'orange results');

    expect(app.network.searches.last.color, 'ff9900');
  });

  appTest('a carousel tap gives one light haptic and scrolling gives none', (
    tester,
    app,
  ) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _openSearch(tester, app);
    haptics.clear();

    // A tap gives light feedback while it applies the filter. This runs before
    // any scrolling so the card is fully on screen.
    await _tapCard(
      tester,
      app,
      find.byKey(const ValueKey('search-color-white')),
    );
    await pumpFrames(tester, 8, const Duration(milliseconds: 50));
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(app.network.searches.last.color, 'ffffff');

    // Stock carousel behaviour: browsing the row is silent. The widget only
    // buzzes on a tap, so a drag must not leave a haptic behind.
    haptics.clear();
    await tester.drag(
      find.byKey(const ValueKey('search-color-carousel')),
      const Offset(-250, 0),
    );
    await pumpFrames(tester, 20, const Duration(milliseconds: 100));
    expect(haptics, isEmpty);
  });

  appTest('the tag row lists tag collections only and hides when none', (
    tester,
    app,
  ) async {
    // A colour-only collection has no tag to apply, so it must not appear.
    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await app.act(tester, () async {
      await app.collections.removeMany(
        app.collections.entries.value.map((e) => e.id).toSet(),
      );
      await app.collections.create(
        name: 'Deep Blues',
        query: '',
        colors: const ['#0000ff'],
        origin: CollectionOrigin.color,
      );
    });

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');

    expect(find.text('By color'), findsOneWidget);
    expect(
      find.text('By tag'),
      findsNothing,
      reason: 'a colour collection is not a tag collection',
    );
    expect(
      find.byKey(const ValueKey('search-tag-carousel')),
      findsNothing,
      reason: 'the whole tag section is hidden when empty',
    );

    // A bookmarkable tag query brings the row back, with only that card.
    await app.act(
      tester,
      () => app.collections.create(
        name: 'Landscape',
        query: 'landscape',
        origin: CollectionOrigin.tag,
      ),
    );
    await pumpFrames(tester, 6);

    expect(find.text('By tag'), findsOneWidget);
    final tagId = app.collections.entries.value
        .firstWhere((e) => e.name == 'Landscape')
        .id;
    expect(find.byKey(ValueKey('search-tag-$tagId')), findsOneWidget);
    for (final entry in app.collections.entries.value.where(
      (e) => e.name != 'Landscape',
    )) {
      expect(find.byKey(ValueKey('search-tag-${entry.id}')), findsNothing);
    }
  });

  appTest('a tag collection keeps its origin across a restart', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await app.act(tester, () async {
      // Drop the seeds so Landscape is the first card: off-screen carousel
      // children are not built, so a card past the first screen cannot be
      // asserted without scrolling.
      await app.collections.removeMany({...curatedSeedIds});
      await app.collections.create(
        name: 'Landscape',
        query: 'landscape',
        origin: CollectionOrigin.tag,
      );
    });
    final tagId = app.collections.entries.value
        .firstWhere((e) => e.name == 'Landscape')
        .id;

    await app.restart(tester);
    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');

    expect(
      app.collections.entries.value.firstWhere((e) => e.id == tagId).origin,
      CollectionOrigin.tag,
      reason: 'origin is persisted, not derived from the row shape',
    );
    expect(find.byKey(ValueKey('search-tag-$tagId')), findsOneWidget);
  });

  appTest('a legacy saved search is preserved but never offered as a tag', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );

    // A row written before the origin field existed: an arbitrary saved
    // search with no colours, shaped exactly like a tag collection.
    await app.act(tester, () async {
      await app.collections.removeMany(
        app.collections.entries.value.map((e) => e.id).toSet(),
      );
      final box = Hive.box<String>('collections');
      await box.put(
        'legacy-like',
        jsonEncode(<String, Object?>{
          'id': 'legacy-like',
          'name': 'legacy like',
          'query': 'like:abc123',
          'kinds': <String>[],
          'filter': <String, Object?>{'sorting': 'newest'},
          'colors': <String>[],
          'createdAt': DateTime(2025, 1, 1).toIso8601String(),
        }),
      );
      await app.collections.restore();
    });

    final legacy = app.collections.entries.value.single;
    expect(legacy.id, 'legacy-like');
    expect(
      legacy.origin,
      CollectionOrigin.unknown,
      reason: 'a row without the field stays unclassified',
    );

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');

    expect(
      find.text('By tag'),
      findsNothing,
      reason: 'an arbitrary saved search is not a tag',
    );

    // Unclassified rows are user data: they must survive, just not as tags.
    await app.restart(tester);
    expect(app.collections.entries.value.single.id, 'legacy-like');
    expect(
      app.collections.entries.value.single.origin,
      CollectionOrigin.unknown,
    );
  });

  appTest('deleting the applied tag collection clears its filter', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);
    await _submit(tester, app, 'city');
    await pumpUntil(tester, _tile('alpha'), reason: 'typed results');

    final artCard = find.byKey(const ValueKey('search-tag-seed-art'));
    await _tapCard(tester, app, artCard);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    expect(app.network.searches.last.query, 'city art');

    // Every tag collection disappears while the tag filter is applied.
    await app.act(
      tester,
      () => app.collections.removeMany({...curatedSeedIds}),
    );
    await app.settle(tester);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    expect(
      app.network.searches.last.query,
      'city',
      reason: 'the filter cannot outlive its card',
    );
    expect(
      find.text('By tag'),
      findsNothing,
      reason: 'no tag collections remain, so the section hides',
    );
  });

  appTest('a failed search shows an error and Retry recovers', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);

    var offline = true;
    final previous = app.network.searchHandler;
    app.network.searchHandler = (call) async {
      if (offline && call.query == 'nature') throw const FakeOffline();
      return previous!(call);
    };

    await _submit(tester, app, 'nature');
    await pumpUntil(
      tester,
      find.text('Something went wrong'),
      reason: 'search error state',
    );

    offline = false;
    await app.tap(tester, find.text('Try again'));
    await pumpUntil(tester, _tile('alpha'), reason: 'retried results');
  });

  appTest('back returns to the Discover feed', (tester, app) async {
    await _openSearch(tester, app);

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);

    expect(find.byType(SearchPage), findsNothing);
    expect(find.byKey(const ValueKey('wallpaper-tile-alpha')), findsOneWidget);
  });
}
