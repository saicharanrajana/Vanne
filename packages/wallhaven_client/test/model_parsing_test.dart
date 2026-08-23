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
    test('detail response carries uploader and tags', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(fixture('wallpaper_response.json')),
      );
      addTearDown(client.close);

      final wallpaper = await client.wallpaper('94x38z');
      expect(wallpaper.hasDetails, isTrue);
      expect(wallpaper.uploader!.username, 'test-user');
      expect(wallpaper.uploader!.group, 'User');
      expect(wallpaper.uploader!.avatar['32px'], contains('avatar/32'));
      expect(wallpaper.tags, hasLength(2));
      expect(wallpaper.tags!.first.name, 'anime');
      expect(wallpaper.tags!.first.alias, 'Chinese cartoons');
      expect(wallpaper.tags!.first.categoryId, 1);
    });

    test('uploader with missing avatar map still parses', () async {
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
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(body),
      );
      addTearDown(client.close);

      final wallpaper = await client.wallpaper('x1y2z3');
      expect(wallpaper.uploader!.username, 'u');
      expect(wallpaper.uploader!.avatar, isEmpty);
      // Missing thumbs degrade to an all-null Thumbnails.
      expect(wallpaper.thumbnails.bestForGrid, isNull);
    });
  });

  group('Tag parsing resilience', () {
    test('complete tag parses all fields', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(fixture('tag_response.json')),
      );
      addTearDown(client.close);

      final tag = await client.tag(1);
      expect(tag.id, 1);
      expect(tag.name, 'anime');
      expect(tag.alias, 'Chinese cartoons');
      expect(tag.category, 'Anime & Manga');
      expect(tag.categoryId, 1);
      expect(tag.purity, 'sfw');
      expect(tag.createdAt, DateTime.utc(2015, 1, 16, 2, 6, 45));
    });

    test('partial tag with null metadata parses to nulls', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(
          fixture('tag_partial_response.json'),
        ),
      );
      addTearDown(client.close);

      final tag = await client.tag(777);
      expect(tag.id, 777);
      expect(tag.name, 'minimalist');
      expect(tag.alias, isNull);
      expect(tag.category, isNull);
      expect(tag.categoryId, isNull);
      expect(tag.purity, isNull);
      expect(tag.createdAt, isNull);
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
    test('public flag decodes from 0/1 wire values', () async {
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
