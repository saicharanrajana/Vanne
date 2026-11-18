import 'dart:io';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

void main() {
  group('WallpaperDto parsing (search fixture)', () {
    late Map<String, dynamic> search;

    setUp(() => search = fixture('search_response.json'));

    test('parses listing items without uploader/tags', () {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(search),
      );
      addTearDown(client.close);

      return client.search(WallhavenSearchRequest()).then((page) {
        expect(page.items, hasLength(2));
        final first = page.items.first;
        expect(first.id, '94x38z');
        expect(first.url, 'https://wallhaven.cc/w/94x38z');
        expect(first.shortUrl, 'http://whvn.cc/94x38z');
        expect(first.purity, Purity.sfw);
        expect(first.category, Category.anime);
        expect(first.width, 6742);
        expect(first.height, 3534);
        expect(first.resolution, '6742x3534');
        expect(first.ratio, '1.91');
        expect(first.fileSizeBytes, 5070446);
        expect(first.fileType, 'image/jpeg');
        expect(first.createdAt, DateTime.utc(2018, 10, 31, 1, 23, 10));
        expect(first.colors, hasLength(5));
        expect(first.path,
            'https://w.wallhaven.cc/full/94/wallhaven-94x38z.jpg');
        expect(
          first.thumbnails.small,
          'https://th.wallhaven.cc/small/94/94x38z.jpg',
        );
        expect(first.uploader, isNull);
        expect(first.tags, isNull);
        expect(first.hasDetails, isFalse);
      });
    });
  });

  group('Wallpaper detail parsing', () {
    test('full and partial detail payloads map optional metadata tolerantly',
        () async {
      final fullClient = buildTestClient(
        adapter: FakeWallhavenAdapter.json(fixture('wallpaper_response.json')),
      );
      addTearDown(fullClient.close);

      final wallpaper = await fullClient.wallpaper('94x38z');
      expect(wallpaper.hasDetails, isTrue);
      expect(wallpaper.uploader!.username, 'test-user');
      expect(wallpaper.uploader!.group, 'User');
      expect(wallpaper.uploader!.avatar['32px'], contains('avatar/32'));
      expect(wallpaper.tags, hasLength(2));
      expect(wallpaper.tags!.first.name, 'anime');
      expect(wallpaper.tags!.first.alias, 'Chinese cartoons');
      expect(wallpaper.tags!.first.categoryId, 1);

      // Partial payload: uploader without an avatar map, plus missing thumbs.
      const body = <String, dynamic>{
        'data': <String, dynamic>{
          'id': 'x1y2z3',
          'url': 'https://wallhaven.cc/w/x1y2z3',
          'uploader': <String, dynamic>{'username': 'u'},
          'views': 0,
          'favorites': 0,
          'source': '',
          'purity': 'sfw',
          'category': 'general',
          'dimension_x': 1,
          'dimension_y': 1,
          'resolution': '1x1',
          'ratio': '1',
          'file_size': 0,
          'file_type': 'image/jpeg',
          'colors': <dynamic>[],
          'path': '',
          'thumbs': <String, dynamic>{},
          'tags': <dynamic>[],
        },
      };
      final partialClient = buildTestClient(
        adapter: FakeWallhavenAdapter.json(body),
      );
      addTearDown(partialClient.close);

      final partial = await partialClient.wallpaper('x1y2z3');
      expect(partial.uploader!.username, 'u');
      expect(partial.uploader!.avatar, isEmpty);
      // Missing thumbs degrade to an all-null Thumbnails.
      expect(partial.thumbnails.bestForGrid, isNull);
    });
  });

  group('Tag parsing resilience', () {
    test('complete and partial tag payloads decode tolerantly', () async {
      final completeClient = buildTestClient(
        adapter: FakeWallhavenAdapter.json(fixture('tag_response.json')),
      );
      addTearDown(completeClient.close);

      final tag = await completeClient.tag(1);
      expect(tag.id, 1);
      expect(tag.name, 'anime');
      expect(tag.alias, 'Chinese cartoons');
      expect(tag.category, 'Anime & Manga');
      expect(tag.categoryId, 1);
      expect(tag.purity, 'sfw');
      expect(tag.createdAt, DateTime.utc(2015, 1, 16, 2, 6, 45));

      final partialClient = buildTestClient(
        adapter: FakeWallhavenAdapter.json(
          fixture('tag_partial_response.json'),
        ),
      );
      addTearDown(partialClient.close);

      final partial = await partialClient.tag(777);
      expect(partial.id, 777);
      expect(partial.name, 'minimalist');
      expect(partial.alias, isNull);
      expect(partial.category, isNull);
      expect(partial.categoryId, isNull);
      expect(partial.purity, isNull);
      expect(partial.createdAt, isNull);
    });
  });

  group('SearchMeta parsing', () {
    test('string query and seed surface in domain meta', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(fixture('search_response.json')),
      );
      addTearDown(client.close);

      final page = await client.search(WallhavenSearchRequest());
      expect(page.currentPage, 1);
      expect(page.lastPage, 36);
      expect(page.perPage, 24);
      expect(page.total, 848);
      expect(page.meta.query, 'test');
      expect(page.meta.seed, 'abc123');
      expect(page.meta.exactTagQuery, isNull);
      expect(page.hasNextPage, isTrue);
    });

    test('exact-tag meta.query decodes into ExactTagQuery', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(
          fixture('search_exact_tag_response.json'),
        ),
      );
      addTearDown(client.close);

      final page = await client.search(WallhavenSearchRequest());
      expect(page.meta.query, isNull);
      expect(page.meta.exactTagQuery!.id, 1);
      expect(page.meta.exactTagQuery!.tag, 'anime');
    });
  });

  group('Collections parsing', () {
    test('public flags and numeric-string fields decode compatibly', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(
          fixture('collections_response.json'),
        ),
      );
      addTearDown(client.close);

      final collections = await client.collections(username: 'someone');
      expect(collections, hasLength(2));
      expect(collections.first.label, 'Default');
      expect(collections.first.public, isTrue);
      expect(collections.last.public, isFalse);
      expect(collections.last.count, 7);

      // Wire values may arrive as strings; they decode to the same domain
      // types instead of being rejected.
      final numericClient = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <dynamic>[
            <String, dynamic>{
              'id': '7',
              'label': 'Favourites',
              'views': '12',
              'public': '1',
              'count': 3,
            },
          ],
        }),
      );
      addTearDown(numericClient.close);

      final numeric = await numericClient.collections(username: 'someone');
      expect(numeric.single.id, 7);
      expect(numeric.single.label, 'Favourites');
      expect(numeric.single.views, 12);
      expect(numeric.single.public, isTrue);
      expect(numeric.single.count, 3);
    });
  });

  group('Settings parsing', () {
    test('numeric-string per_page and enum lists decode tolerantly',
        () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(fixture('settings_response.json')),
      );
      addTearDown(client.close);

      // Settings require auth; provide a key for the request path.
      client.apiKeyManager.setApiKey('k');

      final settings = await client.settings();
      expect(settings.thumbSize, 'orig');
      expect(settings.perPage, 24); // parsed from "24"
      expect(settings.purities,
          [Purity.sfw, Purity.sketchy, Purity.nsfw]);
      expect(settings.categories,
          [Category.general, Category.anime, Category.people]);
      expect(settings.resolutions, ['1920x1080', '2560x1440']);
      expect(settings.aspectRatios, ['16x9']);
      expect(settings.toplistRange, '6M');
      expect(settings.tagBlacklist, ['blacklist tag', 'another']);
    });
  });

  group('Malformed JSON', () {
    test('invalid JSON body raises WallhavenMalformedJsonException',
        () async {
      final raw = File('test/fixtures/malformed.json').readAsStringSync();
      final adapter = FakeWallhavenAdapter([
        (_, _) async => ResponseBody.fromString(raw, 200),
      ]);
      final client = buildTestClient(adapter: adapter);
      addTearDown(client.close);

      await expectLater(
        client.search(WallhavenSearchRequest()),
        throwsA(isA<WallhavenMalformedJsonException>()),
      );
    });
  });
}
