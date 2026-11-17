import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/core/collections/collection_entry.dart';

import '../support/fake_wallhaven.dart';
import '../support/fixtures.dart';
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

/// Drags [row] until [card] is fully inside its viewport, then lets the snap
/// settle.
///
/// Cards keep a fixed extent and the row snaps to the nearest one, so the card
/// under test only becomes tappable once a drag has brought it into view.
/// Off-screen carousel children are not built, hence the "is it built yet"
/// loop condition.
Future<void> _revealCard(
  WidgetTester tester,
  Finder row,
  Finder card, {
  int maxDrags = 8,
}) async {
  for (var i = 0; i < maxDrags; i++) {
    if (card.evaluate().isNotEmpty) {
      final rect = tester.getRect(card);
      final viewport = tester.getRect(row);
      if (rect.left >= viewport.left && rect.right <= viewport.right) break;
    }
    await tester.drag(row, const Offset(-250, 0));
    await pumpFrames(tester, 12, const Duration(milliseconds: 50));
  }
  // A card mid-snap does not accept taps, exactly as in the real carousel.
  await pumpFrames(tester, 20, const Duration(milliseconds: 100));
}

/// Scroll offset of the carousel inside [row].
double _rowOffset(WidgetTester tester, Finder row) {
  final scrollable = find
      .descendant(of: row, matching: find.byType(Scrollable))
      .first;
  return tester.state<ScrollableState>(scrollable).position.pixels;
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

    final carousel = find.byKey(const ValueKey('search-color-carousel'));
    final orange = find.byKey(const ValueKey('search-color-orange'));
    await _revealCard(tester, carousel, orange);
    expect(
      app.network.searches,
      hasLength(before),
      reason: 'scrolling must not apply a filter',
    );

    await _tapCard(tester, app, orange);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    await pumpUntil(tester, _tile('alpha'), reason: 'orange results');

    expect(app.network.searches.last.color, 'ff9900');
  });

  appTest('a far colour card stays in view once selected', (tester, app) async {
    await _openSearch(tester, app);
    final carousel = find.byKey(const ValueKey('search-color-carousel'));
    final purple = find.byKey(const ValueKey('search-color-purple'));
    await _revealCard(tester, carousel, purple);

    final offset = _rowOffset(tester, carousel);
    final card = tester.getRect(purple);
    expect(offset, greaterThan(0), reason: 'the row really is scrolled');

    await _tapCard(tester, app, purple);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    await pumpUntil(tester, _tile('alpha'), reason: 'purple results');

    expect(app.network.searches.last.color, '993399');
    expect(
      _rowOffset(tester, carousel),
      offset,
      reason: 'the committed search must not rewind the row the user scrolled',
    );
    expect(
      tester.getRect(purple),
      card,
      reason: 'the tapped card stays exactly where the finger left it',
    );
  });

  appTest('a far tag card stays in view once selected', (tester, app) async {
    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    // Enough saved tags that a far card is only reachable by scrolling.
    await app.act(tester, () async {
      for (var i = 0; i < 8; i++) {
        await app.collections.create(
          name: 'Tags $i',
          query: 'tags$i',
          origin: CollectionOrigin.tag,
        );
      }
    });
    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');

    final carousel = find.byKey(const ValueKey('search-tag-carousel'));
    final minimal = find.byKey(const ValueKey('search-tag-seed-minimal'));
    await _revealCard(tester, carousel, minimal);

    final offset = _rowOffset(tester, carousel);
    final card = tester.getRect(minimal);
    expect(offset, greaterThan(0), reason: 'the row really is scrolled');

    await _tapCard(tester, app, minimal);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    await pumpUntil(tester, _tile('alpha'), reason: 'tag results');

    expect(app.network.searches.last.query, 'minimalist');
    expect(
      _rowOffset(tester, carousel),
      offset,
      reason: 'applying a tag must not rewind the row the user scrolled',
    );
    expect(
      tester.getRect(minimal),
      card,
      reason: 'the tapped card stays exactly where the finger left it',
    );
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

  appTest('the tag row lists tag collections only', (tester, app) async {
    // A colour-only collection has no tag to apply, so it must not appear.
    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await app.act(
      tester,
      () => app.collections.create(
        name: 'Deep Blues',
        query: '',
        colors: const ['#0000ff'],
        origin: CollectionOrigin.color,
      ),
    );
    final colorId = app.collections.entries.value
        .firstWhere((e) => e.name == 'Deep Blues')
        .id;

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');

    expect(find.text('By color'), findsOneWidget);
    expect(
      find.text('By tag'),
      findsOneWidget,
      reason: 'the bundled tag collections always offer the row',
    );
    expect(
      find.byKey(ValueKey('search-tag-$colorId')),
      findsNothing,
      reason: 'a colour collection is not a tag collection',
    );

    // A bookmarkable tag query appears alongside the bundled cards.
    await app.act(
      tester,
      () => app.collections.create(
        name: 'Landscape',
        query: 'landscape',
        origin: CollectionOrigin.tag,
      ),
    );
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('search-tag-carousel')),
      reason: 'tag carousel',
    );
    final tagId = app.collections.entries.value
        .firstWhere((e) => e.name == 'Landscape')
        .id;

    // The new card is last, past the bundled four; scroll it into view rather
    // than assuming the whole row is built.
    await tester.drag(
      find.byKey(const ValueKey('search-tag-carousel')),
      const Offset(-320, 0),
    );
    await pumpFrames(tester, 20, const Duration(milliseconds: 100));
    expect(find.byKey(ValueKey('search-tag-$tagId')), findsOneWidget);
    expect(
      find.byKey(ValueKey('search-tag-$colorId')),
      findsNothing,
      reason: 'saving a tag collection does not leak the colour one in',
    );
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
      await app.collections.create(
        name: 'Landscape',
        query: 'landscape',
        origin: CollectionOrigin.tag,
      );
      // Off-screen carousel children are not built, so the card under test has
      // to lead the row. Bundled collections are permanent, so this asks for
      // the reorder the user has rather than deleting them.
      final created = app.collections.entries.value.firstWhere(
        (e) => e.name == 'Landscape',
      );
      await app.collections.moveToStart(created.id);
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

    final legacy = app.collections.entries.value.firstWhere(
      (entry) => entry.id == 'legacy-like',
    );
    expect(
      legacy.origin,
      CollectionOrigin.unknown,
      reason: 'a row without the field stays unclassified',
    );

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');

    expect(
      find.byKey(const ValueKey('search-tag-legacy-like')),
      findsNothing,
      reason: 'an arbitrary saved search is not a tag',
    );

    // Unclassified rows are user data: they must survive, just not as tags.
    await app.restart(tester);
    expect(
      app.collections.entries.value.map((entry) => entry.id),
      contains('legacy-like'),
    );
    expect(
      app.collections.entries.value
          .firstWhere((entry) => entry.id == 'legacy-like')
          .origin,
      CollectionOrigin.unknown,
    );
  });

  appTest('removing the applied tag collection clears its filter', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);
    await _submit(tester, app, 'city');
    await pumpUntil(tester, _tile('alpha'), reason: 'typed results');

    // A user-saved tag collection, which the user is allowed to remove.
    await app.act(
      tester,
      () => app.collections.create(
        name: 'Cityscape',
        query: 'cityscape',
        origin: CollectionOrigin.tag,
      ),
    );
    final cityId = app.collections.entries.value
        .firstWhere((e) => e.name == 'Cityscape')
        .id;
    // The bundled tag collections lead the carousel and off-screen cards are
    // not built, so put the new card first the way a user would.
    await app.act(tester, () => app.collections.moveToStart(cityId));
    await pumpFrames(tester, 8);

    final cityCard = find.byKey(ValueKey('search-tag-$cityId'));
    await _tapCard(tester, app, cityCard);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    expect(app.network.searches.last.query, 'city cityscape');

    // The applied collection disappears while its tag filter is live.
    await app.act(tester, () => app.collections.remove(cityId));
    await app.settle(tester);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    expect(
      app.network.searches.last.query,
      'city',
      reason: 'the filter cannot outlive its card',
    );
    expect(
      find.byKey(ValueKey('search-tag-$cityId')),
      findsNothing,
      reason: 'the removed card is gone',
    );
    expect(
      find.byKey(const ValueKey('search-tag-seed-art')),
      findsOneWidget,
      reason: 'the bundled collections are untouched',
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

  appTest('filters live behind a floating trigger, not a chip row', (
    tester,
    app,
  ) async {
    await _openSearch(tester, app);
    await _submit(tester, app, 'nature');
    await pumpUntil(tester, _tile('alpha'), reason: 'search results');

    expect(
      find.text('Newest'),
      findsNothing,
      reason: 'the header no longer carries a filter chip',
    );
    final trigger = find.byKey(const ValueKey('feed-filter-trigger-search'));
    expect(trigger, findsOneWidget, reason: 'search offers a filter FAB');

    final before = app.network.searches.length;
    await app.tap(tester, trigger);
    await pumpUntil(tester, find.text('Sort & Filter'), reason: 'filter sheet');
    await app.tap(tester, find.text('Most viewed'));
    await app.tap(tester, find.text('Apply'));

    await app.settleUntil(
      tester,
      () => app.network.searches.length == before + 1,
      reason: 'the filter re-runs the committed search',
    );
    final applied = app.network.searches.last;
    expect(applied.query, 'nature');
    expect(applied.sorting, 'views');
  });

  appTest('the filter trigger never covers the end of the results', (
    tester,
    app,
  ) async {
    app.network.searchHandler = (call) async => searchPageJson(const [
      'alpha',
      'beta',
      'gamma',
      'delta',
      'epsilon',
      'zeta',
      'eta',
      'theta',
    ]);
    await _openSearch(tester, app);
    await _submit(tester, app, 'nature');
    await pumpUntil(tester, _tile('alpha'), reason: 'search results');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
    await pumpFrames(tester, 10, const Duration(milliseconds: 100));

    final last = _tile('theta');
    expect(last, findsOneWidget, reason: 'last result reachable by scrolling');
    final trigger = find.byKey(const ValueKey('feed-filter-trigger-search'));
    expect(
      tester.getRect(last).bottom,
      lessThanOrEqualTo(tester.getRect(trigger).top),
      reason: 'the last tile can rest clear of the floating trigger',
    );
  });

  appTest('a saved colour collection leads the colour row', (
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
      await app.collections.create(
        name: '#0000ff',
        query: '',
        colors: const ['#0000ff'],
        origin: CollectionOrigin.color,
      );
      await app.collections.create(
        name: 'Landscape',
        query: 'landscape',
        origin: CollectionOrigin.tag,
      );
    });
    final colorId = app.collections.entries.value
        .firstWhere((e) => e.name == '#0000ff')
        .id;
    final tagId = app.collections.entries.value
        .firstWhere((e) => e.name == 'Landscape')
        .id;

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');

    final card = find.byKey(ValueKey('search-color-collection-$colorId'));
    expect(card, findsOneWidget, reason: 'the saved colour is a colour filter');
    expect(
      find.text('Blue'),
      findsOneWidget,
      reason: 'hex-named color collections use the human-readable title',
    );
    expect(
      find.bySemanticsLabel(RegExp('Collection Blue')),
      findsOneWidget,
      reason: 'accessibility uses the same displayed title',
    );
    expect(
      find.text('#0000ff'),
      findsNothing,
    );
    expect(
      tester.getRect(card).left,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('search-color-black'))).left,
      ),
      reason: 'saved colours lead the row, ahead of the bundled swatches',
    );
    expect(
      find.byKey(ValueKey('search-color-collection-$tagId')),
      findsNothing,
      reason: 'a tag collection is not a colour',
    );

    // #0000ff is not one of Wallhaven's documented values; the nearest one is
    // used so tapping still filters instead of returning everything.
    await _tapCard(tester, app, card);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    await pumpUntil(tester, _tile('alpha'), reason: 'colour results');
    expect(app.network.searches.last.color, '0066cc');

    // Tapping the selected card again clears the filter. Nothing else is
    // committed, so the screen returns to its pristine state instead of
    // spending a request on the generic feed.
    final beforeClearing = app.network.searches.length;
    await _tapCard(tester, app, card);
    await app.settle(tester);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    expect(
      app.network.searches,
      hasLength(beforeClearing),
      reason: 'an empty search has nothing to fetch',
    );
    expect(
      find.bySemanticsLabel(RegExp('Collection Blue, selected')),
      findsNothing,
      reason: 'the colour filter is cleared with its card',
    );
    expect(
      find.text(
        'Type a query, pick a color, or start from a saved collection.',
      ),
      findsOneWidget,
      reason: 'the screen is pristine again',
    );
  });

  appTest('a saved colour collection composes with the typed query', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await app.act(
      tester,
      () => app.collections.create(
        name: 'Deep Blues',
        query: '',
        colors: const ['#0000ff'],
        origin: CollectionOrigin.color,
      ),
    );
    final colorId = app.collections.entries.value
        .firstWhere((e) => e.name == 'Deep Blues')
        .id;

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');
    await _submit(tester, app, 'sky');
    await pumpUntil(tester, _tile('alpha'), reason: 'typed results');

    await _tapCard(
      tester,
      app,
      find.byKey(ValueKey('search-color-collection-$colorId')),
    );
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    final composed = app.network.searches.last;
    expect(composed.query, 'sky', reason: 'the typed query is kept');
    expect(composed.color, '0066cc', reason: 'the saved colour is applied');
  });

  appTest('removing the applied colour collection clears its filter', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await app.act(
      tester,
      () => app.collections.create(
        name: 'Deep Blues',
        query: '',
        colors: const ['#0000ff'],
        origin: CollectionOrigin.color,
      ),
    );
    final colorId = app.collections.entries.value
        .firstWhere((e) => e.name == 'Deep Blues')
        .id;

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');

    final card = find.byKey(ValueKey('search-color-collection-$colorId'));
    await _tapCard(tester, app, card);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));
    await pumpUntil(tester, _tile('alpha'), reason: 'colour results');
    expect(app.network.searches.last.color, '0066cc');

    final before = app.network.searches.length;
    await app.act(tester, () => app.collections.remove(colorId));
    await app.settle(tester);
    await pumpFrames(tester, 10, const Duration(milliseconds: 50));

    expect(card, findsNothing, reason: 'the removed card is gone from the row');
    expect(
      app.network.searches,
      hasLength(before),
      reason: 'no other input remains, so the generic feed is never fetched',
    );
    expect(
      find.byKey(const ValueKey('search-color-black')),
      findsOneWidget,
      reason: 'the bundled swatches are untouched',
    );
  });
}
