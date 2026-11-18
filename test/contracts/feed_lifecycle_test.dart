// Contract: how a feed controller behaves while requests overlap.
//
// These are deliberately direct controller tests. Overlapping requests can
// only be produced deterministically by holding repository futures open, and
// the guarantees below are invariants of the controller — not of any screen —
// so they are cheaper and far more precise here than through a widget tree.
//
// What is protected:
//  - a superseded request can never free the guard that keeps the live
//    request alone in flight,
//  - a stale response can never overwrite fresher results,
//  - one wallpaper ID appears at most once, even when the server sends
//    updated metadata for it,
//  - pagination failures keep already-visible content and retry only the
//    failed page,
//  - a random-sort seed travels across pages and resets on reload.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/core/wallpaper/feed_controller.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

/// One `search` call the test controls by hand.
final class _PendingSearch {
  _PendingSearch({required this.page, required this.seed});

  final int page;
  final String? seed;
  final _done = Completer<SearchOutcome>();

  void succeed(PaginatedResult<Wallpaper> page) =>
      _done.complete(SearchOutcome(page: page, nsfwClamped: false));

  void fail([String message = 'Network unavailable.']) =>
      _done.completeError(WallhavenUserException(message));

  /// Completes with a failure the repository contract does not describe, the
  /// way a decoding or platform bug would surface.
  void failUnexpectedly() =>
      _done.completeError(StateError('decoder blew up'));
}

final class _ScriptedRepository implements WallpaperRepository {
  /// Every page request in call order; tests complete them out of order.
  final searchCalls = <_PendingSearch>[];

  /// The content-policy revision the feed watches, mirroring the real
  /// repository: bumping it means purity, blocked tags or the API key changed.
  @override
  final policyRevision = signal(0);

  /// Simulates a content-policy change made from Settings.
  void changePolicy() => policyRevision.value++;

  @override
  Future<SearchOutcome> search({
    String query = '',
    Set<WallhavenColor> colors = const {},
    List<WallhavenCategory> categories = const [],
    FeedFilter filter = const FeedFilter(),
    int page = 1,
    String? seed,
  }) {
    final call = _PendingSearch(page: page, seed: seed);
    searchCalls.add(call);
    return call._done.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TestFeed extends FeedController {
  _TestFeed(super.repository);

  @override
  SearchRequestSpec buildSpec() => const SearchRequestSpec(query: 'fixture');
}

Wallpaper _wallpaper(
  String id, {
  String resolution = '100x200',
  String path = '',
}) => Wallpaper(
  id: id,
  url: 'https://wallhaven.cc/w/$id',
  source: '',
  purity: Purity.sfw,
  category: Category.anime,
  width: 100,
  height: 200,
  resolution: resolution,
  ratio: '0.5',
  fileSizeBytes: 1,
  fileType: 'image/jpeg',
  colors: const [],
  views: 0,
  favorites: 0,
  path: path,
  thumbnails: Thumbnails(small: 'https://example.com/$id.jpg'),
);

PaginatedResult<Wallpaper> _page(
  int number, {
  int lastPage = 2,
  String? seed,
  List<Wallpaper> items = const [],
}) => PaginatedResult<Wallpaper>(
  items: items,
  meta: SearchMeta(
    currentPage: number,
    lastPage: lastPage,
    perPage: 24,
    seed: seed,
  ),
);

List<String> _ids(FeedController feed) =>
    feed.state.value.items.map((wallpaper) => wallpaper.id).toList();

void main() {
  late _ScriptedRepository repository;
  late _TestFeed feed;

  setUp(() {
    repository = _ScriptedRepository();
    feed = _TestFeed(repository);
  });

  tearDown(() => feed.dispose());

  // Lets every already-scheduled microtask and continuation run.
  Future<void> settle() => pumpEventQueue();

  group('overlapping requests', () {
    test('a superseded request cannot free the live request guard', () async {
      // Generation 1 stays in flight for the whole scenario.
      final stale = feed.reload(); // request 0
      await settle();

      final live = feed.reload(); // request 1
      await settle();
      repository.searchCalls[1].succeed(_page(1, items: [_wallpaper('aaa111')]));
      await live;

      // Generation 2 asks for page 2; that request stays in flight too.
      final paging = feed.loadMore(); // request 2
      await settle();
      expect(repository.searchCalls, hasLength(3));
      expect(repository.searchCalls[2].page, 2);

      // The superseded generation finally answers.
      repository.searchCalls[0].succeed(
        _page(1, items: [_wallpaper('stale')]),
      );
      await stale;
      await settle();
      expect(
        _ids(feed),
        ['aaa111'],
        reason: 'stale results are dropped',
      );

      // Page 2 is still running: nothing may start a second page-2 request.
      final extra = feed.loadMore();
      await settle();
      expect(
        repository.searchCalls,
        hasLength(3),
        reason: 'the finished stale request must not release the live guard',
      );

      repository.searchCalls[2].succeed(_page(2, items: [_wallpaper('bbb222')]));
      await paging;
      await extra;
      expect(_ids(feed), ['aaa111', 'bbb222']);
    });

    test('a slow stale response cannot replace fresher results', () async {
      final first = feed.reload();
      await settle();
      final second = feed.reload();
      await settle();

      repository.searchCalls[1].succeed(_page(1, items: [_wallpaper('fresh')]));
      await settle();
      repository.searchCalls[0].succeed(_page(1, items: [_wallpaper('stale')]));
      await first;
      await second;

      expect(_ids(feed), ['fresh']);
    });

    test('a stale failure cannot surface as an error', () async {
      final first = feed.reload();
      await settle();
      final second = feed.reload();
      await settle();

      repository.searchCalls[1].succeed(_page(1, items: [_wallpaper('fresh')]));
      await settle();
      repository.searchCalls[0].fail();
      await first;
      await second;

      expect(feed.state.value.error, isNull);
      expect(_ids(feed), ['fresh']);
    });
  });

  group('duplicate suppression', () {
    test('one ID yields one item when pages repeat it with new metadata', () async {
      final first = feed.reload();
      await settle();
      repository.searchCalls[0].succeed(
        _page(1, items: [_wallpaper('aaa111', resolution: '100x200')]),
      );
      await first;

      final second = feed.loadMore();
      await settle();
      repository.searchCalls[1].succeed(
        _page(
          2,
          items: [
            // Same wallpaper, higher-resolution snapshot: still one item.
            _wallpaper('aaa111', resolution: '3840x2160', path: 'https://x/a'),
            _wallpaper('bbb222'),
          ],
        ),
      );
      await second;

      expect(_ids(feed), ['aaa111', 'bbb222']);
      expect(
        feed.state.value.items.first.resolution,
        '100x200',
        reason: 'the first-seen snapshot keeps grid identity stable',
      );
    });

    test('an ID repeated inside one page yields one item', () async {
      final first = feed.reload();
      await settle();
      repository.searchCalls[0].succeed(
        _page(
          1,
          lastPage: 1,
          items: [
            _wallpaper('ccc333', resolution: '100x200'),
            _wallpaper('ccc333', resolution: '3840x2160'),
          ],
        ),
      );
      await first;

      expect(_ids(feed), ['ccc333']);
    });
  });

  group('pagination', () {
    test('a failed page keeps content and retries only that page', () async {
      final first = feed.reload();
      await settle();
      repository.searchCalls[0].succeed(_page(1, items: [_wallpaper('aaa111')]));
      await first;

      final second = feed.loadMore();
      await settle();
      repository.searchCalls[1].fail('Rate limit reached.');
      await second;

      expect(feed.state.value.paginationError, 'Rate limit reached.');
      expect(feed.state.value.loadingMore, isFalse);
      expect(feed.state.value.error, isNull, reason: 'content stays usable');
      expect(_ids(feed), ['aaa111']);
      expect(feed.state.value.hasMore, isTrue, reason: 'retry stays available');

      final retry = feed.retryPagination();
      await settle();
      repository.searchCalls[2].succeed(_page(2, items: [_wallpaper('bbb222')]));
      await retry;

      expect(feed.state.value.paginationError, isNull);
      expect(_ids(feed), ['aaa111', 'bbb222']);
      expect(
        repository.searchCalls.map((call) => call.page),
        [1, 2, 2],
        reason: 'page 1 is never re-requested',
      );
    });

    test('the last page stops further requests', () async {
      final first = feed.reload();
      await settle();
      repository.searchCalls[0].succeed(
        _page(1, lastPage: 1, items: [_wallpaper('aaa111')]),
      );
      await first;

      expect(feed.state.value.hasMore, isFalse);
      await feed.loadMore();
      expect(repository.searchCalls, hasLength(1));
    });

    test('an empty page ends pagination even if metadata claims more', () async {
      final first = feed.reload();
      await settle();
      repository.searchCalls[0].succeed(_page(1, items: []));
      await first;

      expect(feed.state.value.hasMore, isFalse);
      await feed.loadMore();
      expect(repository.searchCalls, hasLength(1));
    });

    test('a random-sort seed carries to the next page and resets on reload', () async {
      final first = feed.reload();
      await settle();
      expect(repository.searchCalls[0].seed, isNull);
      repository.searchCalls[0].succeed(
        _page(1, seed: 'seed-1', items: [_wallpaper('aaa111')]),
      );
      await first;

      final second = feed.loadMore();
      await settle();
      expect(repository.searchCalls[1].seed, 'seed-1');
      repository.searchCalls[1].succeed(
        _page(2, lastPage: 2, seed: 'seed-1', items: [_wallpaper('bbb222')]),
      );
      await second;

      final reload = feed.reload();
      await settle();
      expect(
        repository.searchCalls[2].seed,
        isNull,
        reason: 'a fresh feed starts a new random sequence',
      );
      repository.searchCalls[2].succeed(_page(1, items: [_wallpaper('ccc333')]));
      await reload;
      expect(_ids(feed), ['ccc333'], reason: 'reload replaces the feed');
    });
  });

  // Purity, blocked tags and the API key are read fresh on every request, so
  // a page loaded before a change is stale by definition: it may even show
  // content the user just filtered out. The feed must restart, and a page
  // whose request was already in flight must never land afterwards.
  group('content policy', () {
    test('a policy change restarts the feed from page 1', () async {
      final first = feed.reload();
      await settle();
      repository.searchCalls[0].succeed(
        _page(1, lastPage: 3, items: [_wallpaper('old111')]),
      );
      await first;
      expect(_ids(feed), ['old111']);

      repository.changePolicy();
      await settle();

      expect(
        repository.searchCalls,
        hasLength(2),
        reason: 'the retained feed refetches instead of keeping old items',
      );
      expect(repository.searchCalls[1].page, 1);
      expect(
        _ids(feed),
        isEmpty,
        reason: 'old-policy results are gone while the new page loads',
      );

      repository.searchCalls[1].succeed(
        _page(1, lastPage: 3, items: [_wallpaper('new222')]),
      );
      await settle();
      expect(_ids(feed), ['new222']);
    });

    test('a policy change during a request drops that stale response', () async {
      final stale = feed.reload();
      await settle();
      expect(repository.searchCalls, hasLength(1));

      // The change lands while page 1 is still open.
      repository.changePolicy();
      await settle();
      expect(repository.searchCalls, hasLength(2));

      repository.searchCalls[0].succeed(
        _page(1, items: [_wallpaper('old111')]),
      );
      await stale;
      await settle();
      expect(
        _ids(feed),
        isEmpty,
        reason: 'the old-policy response must never reach the grid',
      );

      repository.searchCalls[1].succeed(
        _page(1, items: [_wallpaper('new222')]),
      );
      await settle();
      expect(_ids(feed), ['new222']);
      expect(
        feed.state.value.error,
        isNull,
        reason: 'a superseded response is not an error either',
      );
    });

    test('a policy change after disposal starts no request', () async {
      final first = feed.reload();
      await settle();
      repository.searchCalls[0].succeed(
        _page(1, items: [_wallpaper('aaa111')]),
      );
      await first;

      feed.dispose();
      repository.changePolicy();
      await settle();

      expect(repository.searchCalls, hasLength(1));
    });
  });

  // A failure the repository never promised to translate is a bug, but the
  // user must still get an actionable surface: an endless skeleton or a
  // half-loaded feed would be worse than an error message with Retry.
  group('unexpected failures', () {
    test('an untyped first-load failure surfaces an error and retries', () async {
      final first = feed.reload();
      await settle();
      repository.searchCalls[0].failUnexpectedly();
      await first;

      expect(feed.state.value.error, isNotNull);
      expect(feed.state.value.loadingFirst, isFalse);

      final retry = feed.reload();
      await settle();
      repository.searchCalls[1].succeed(
        _page(1, items: [_wallpaper('aaa111')]),
      );
      await retry;

      expect(feed.state.value.error, isNull);
      expect(_ids(feed), ['aaa111']);
    });

    test('an untyped pagination failure keeps content and retries', () async {
      final first = feed.reload();
      await settle();
      repository.searchCalls[0].succeed(
        _page(1, lastPage: 2, items: [_wallpaper('aaa111')]),
      );
      await first;

      final more = feed.loadMore();
      await settle();
      repository.searchCalls[1].failUnexpectedly();
      await more;

      expect(_ids(feed), ['aaa111'], reason: 'loaded content stays usable');
      expect(feed.state.value.paginationError, isNotNull);
      expect(feed.state.value.loadingMore, isFalse);
      expect(feed.state.value.error, isNull);

      final retry = feed.retryPagination();
      await settle();
      repository.searchCalls[2].succeed(
        _page(2, lastPage: 2, items: [_wallpaper('bbb222')]),
      );
      await retry;

      expect(feed.state.value.paginationError, isNull);
      expect(_ids(feed), ['aaa111', 'bbb222']);
    });
  });

  group('disposal', () {
    test('a response arriving after disposal is dropped and calls are inert', () async {
      final load = feed.reload();
      await settle();
      feed.dispose();

      repository.searchCalls[0].succeed(_page(1, items: [_wallpaper('late')]));

      // No write-after-dispose error, and no new network work.
      await expectLater(load, completes);
      await feed.loadMore();
      await feed.retryPagination();
      expect(repository.searchCalls, hasLength(1));
    });
  });
}
