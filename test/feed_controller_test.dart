import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:wallpaper_app/core/domain/feed_filter.dart';
import 'package:wallpaper_app/core/wallpaper/feed_controller.dart';
import 'package:wallpaper_app/core/wallpaper/wallpaper_repository.dart';
import 'package:wallpaper_app/shared/widgets/wallpaper_grid.dart';

/// Fake repository exercising only [search]; everything else on
/// [WallpaperRepository] is a thin facade over the package client, which
/// carries its own unit suite. Faking at this seam keeps widget tests
/// deterministic and offline.
class FakeRepository implements WallpaperRepository {
  FakeRepository({required this.pages});

  /// Page number → result. Missing page throws a network-style user error.
  final Map<int, PaginatedResult<Wallpaper>> pages;

  final requestedPages = <int>[];

  @override
  Future<SearchOutcome> search({
    String query = '',
    Set<WallhavenColor> colors = const {},
    List<WallhavenCategory> categories = const [],
    FeedFilter filter = const FeedFilter(),
    int page = 1,
    String? seed,
  }) async {
    requestedPages.add(page);
    final result = pages[page];
    if (result == null) {
      throw const WallhavenUserException('Network unavailable.');
    }
    return SearchOutcome(page: result, nsfwClamped: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingFeed extends FeedController {
  _CountingFeed(super.repository);

  @override
  SearchRequestSpec buildSpec() => const SearchRequestSpec(query: 'test');
}

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  url: 'https://wallhaven.cc/w/$id',
  source: '',
  purity: Purity.sfw,
  category: Category.anime,
  width: 90,
  height: 160,
  resolution: '90x160',
  ratio: '0.5625',
  fileSizeBytes: 1,
  fileType: 'image/jpeg',
  colors: const [],
  views: 0,
  favorites: 0,
  path: '',
  thumbnails: Thumbnails(small: 'https://example.com/$id.jpg'),
);

PaginatedResult<Wallpaper> _page(int number, List<String> ids) =>
    PaginatedResult<Wallpaper>(
      items: [for (final id in ids) _wallpaper(id)],
      meta: SearchMeta(currentPage: number, lastPage: 2, perPage: 24),
    );

void main() {
  testWidgets('feed controller paginates, appends and dedupes', (tester) async {
    await mockNetworkImagesFor(() async {
      final repository = FakeRepository(
        pages: {
          1: _page(1, ['aaa111']),
          // Server repeats aaa111 across the boundary; must be dropped.
          2: _page(2, ['aaa111', 'bbb222']),
        },
      );
      final feed = _CountingFeed(repository);

      await feed.reload();
      expect(feed.state.value.items.map((w) => w.id), ['aaa111']);
      expect(feed.state.value.hasMore, isTrue);

      await feed.loadMore();
      expect(feed.state.value.items.map((w) => w.id), ['aaa111', 'bbb222']);
      expect(feed.state.value.hasMore, isFalse);
      expect(repository.requestedPages, [1, 2]);
    });
  });

  testWidgets('duplicates within one page are dropped too', (tester) async {
    await mockNetworkImagesFor(() async {
      final repository = FakeRepository(
        pages: {
          1: _page(1, ['aaa111']),
          // ccc333 repeated inside the same page must yield ONE tile;
          // otherwise duplicate grid keys / Hero tags collide.
          2: _page(2, ['bbb222', 'ccc333', 'ccc333']),
        },
      );
      final feed = _CountingFeed(repository);

      await feed.reload();
      await feed.loadMore();

      expect(feed.state.value.items.map((w) => w.id), [
        'aaa111',
        'bbb222',
        'ccc333',
      ]);
    });
  });

  testWidgets('pagination failure keeps loaded items and offers retry', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final repository = FakeRepository(
        pages: {
          1: _page(1, ['aaa111']),
        },
      );
      final feed = _CountingFeed(repository);

      await feed.reload();
      await feed.loadMore(); // page 2 missing → localized failure

      expect(feed.state.value.error, isNull);
      expect(feed.state.value.paginationError, 'Network unavailable.');
      expect(feed.state.value.items.map((w) => w.id), contains('aaa111'));

      // Retry succeeds once the page exists.
      repository.pages[2] = _page(2, ['bbb222']);
      await feed.retryPagination();
      expect(feed.state.value.paginationError, isNull);
      expect(feed.state.value.items.length, 2);
    });
  });

  testWidgets(
    'first-load failure surfaces the error state instead of content',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final repository = FakeRepository(pages: {});
        final feed = _CountingFeed(repository);

        await feed.reload();
        expect(feed.state.value.error, 'Network unavailable.');
        expect(feed.state.value.items, isEmpty);
      });
    },
  );

  testWidgets('grid renders tiles and empty state per inputs', (tester) async {
    await mockNetworkImagesFor(() async {
      // Empty feed → intentional empty state.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WallpaperGrid(items: const [], onOpen: (_) {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('No wallpapers found'), findsOneWidget);

      // Loaded feed → one tile per item, keyed by wallpaper ID.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WallpaperGrid(
              items: [_wallpaper('aaa111'), _wallpaper('bbb222')],
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('wallpaper-tile-aaa111')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('wallpaper-tile-bbb222')),
        findsOneWidget,
      );
    });
  });

  testWidgets('grid shows retry affordance for pagination errors', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WallpaperGrid(
              items: [_wallpaper('aaa111')],
              paginationError: 'Rate limit reached.',
              hasMore: true,
              onRetryPagination: () => retries++,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Unable to load more'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });
  });
}
