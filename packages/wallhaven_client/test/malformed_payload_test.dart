import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

/// Regression flows for the "typed errors only" contract.
///
/// Wallhaven occasionally serves valid JSON with a field of the wrong type
/// (`"id": 42`, `"colors": "red"`, `"tags": {}`). An unchecked cast would
/// throw `TypeError` from a DTO, which escapes [WallhavenException] and
/// strands any caller that only handles typed errors — the feed and detail
/// screens catch nothing else, so they would sit in a loading state forever.
///
/// The contract these tests pin down:
///  * scalar/collection fields degrade to their documented defaults;
///  * a *listing* skips an entry that has no usable identity;
///  * a *detail* payload with no usable identity is a typed error.
void main() {
  group('wallpaper detail payloads', () {
    test('wrongly typed fields degrade instead of throwing', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <String, dynamic>{
            'id': 'abc123',
            'url': 'https://wallhaven.cc/w/abc123',
            // Every one of these used to be an unchecked cast.
            'views': <String, dynamic>{'n': 1},
            'dimension_x': '3840',
            'colors': 'red',
            'thumbs': <dynamic>['nope'],
            'tags': <String, dynamic>{'oops': true},
            'uploader': 'someone',
            'short_url': 7,
          },
        }),
      );
      addTearDown(client.close);

      final wallpaper = await client.wallpaper('abc123');

      expect(wallpaper.id, 'abc123');
      expect(wallpaper.url, 'https://wallhaven.cc/w/abc123');
      expect(wallpaper.views, 0, reason: 'non-scalar views → default');
      expect(wallpaper.width, 3840, reason: 'numeric strings still parse');
      expect(wallpaper.colors, isEmpty);
      expect(wallpaper.thumbnails.bestForGrid, isNull);
      expect(wallpaper.tags, isNull);
      expect(wallpaper.uploader, isNull);
      expect(wallpaper.shortUrl, isNull);
    });

    test('a wallpaper with no id is a typed error', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <String, dynamic>{
            'id': 42, // number where a string is documented
            'url': 'https://wallhaven.cc/w/abc123',
          },
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.wallpaper('abc123'),
        throwsA(
          isA<WallhavenInvalidResponseException>().having(
            (e) => e.message,
            'message',
            contains('id'),
          ),
        ),
      );
    });

    test(
      'overflowing numeric fields degrade instead of escaping as errors',
      () async {
        final adapter = FakeWallhavenAdapter([
          (_, _) async => ResponseBody.fromString(
            '{"data":{"id":"abc123","url":"https://wallhaven.cc/w/abc123",'
            '"dimension_x":1e999}}',
            200,
            headers: {
              'content-type': ['application/json'],
            },
          ),
        ]);
        final client = buildTestClient(adapter: adapter);
        addTearDown(client.close);

        final wallpaper = await client.wallpaper('abc123');
        expect(wallpaper.id, 'abc123');
        expect(
          wallpaper.width,
          0,
          reason: 'non-finite JSON numbers default safely',
        );
      },
    );

    test('an envelope without a data object is a typed error', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({'data': <dynamic>[]}),
      );
      addTearDown(client.close);

      await expectLater(
        client.wallpaper('abc123'),
        throwsA(isA<WallhavenInvalidResponseException>()),
      );
    });
  });

  group('tag detail payloads', () {
    test('partial metadata degrades instead of throwing', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <String, dynamic>{
            'id': 1,
            'name': 'anime',
            'alias': 5,
            'category': <dynamic>[],
            'purity': true,
          },
        }),
      );
      addTearDown(client.close);

      final tag = await client.tag(1);
      expect(tag.id, 1);
      expect(tag.name, 'anime');
      expect(tag.alias, isNull);
      expect(tag.category, isNull);
      expect(tag.purity, isNull);
    });

    test('a tag with no usable id is a typed error', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <String, dynamic>{'name': 'anime'},
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.tag(1),
        throwsA(isA<WallhavenInvalidResponseException>()),
      );
    });
  });

  group('search listings', () {
    test('malformed entries are skipped and healthy ones survive', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <dynamic>[
            // Not an object at all.
            'ghost',
            // Object without a usable id.
            <String, dynamic>{'id': 42},
            // Healthy entry with a malformed nested field.
            <String, dynamic>{
              'id': 'good1',
              'url': 'https://wallhaven.cc/w/good1',
              'colors': <dynamic>[1, '#aabbcc'],
              'thumbs': 'ignored',
            },
          ],
          'meta': <String, dynamic>{
            'current_page': 1,
            'last_page': 3,
            'per_page': 24,
            'seed': 9,
          },
        }),
      );
      addTearDown(client.close);

      final page = await client.search(WallhavenSearchRequest());

      expect(page.items.map((w) => w.id), ['good1']);
      expect(page.items.single.colors, [
        '#aabbcc',
      ], reason: 'non-string colour entries are dropped, not fatal');
      expect(page.meta.currentPage, 1);
      expect(page.meta.lastPage, 3);
      expect(page.meta.seed, isNull, reason: 'non-string seed is ignored');
    });

    test('a non-list data field fails as a typed error', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <String, dynamic>{'oops': true},
          'meta': <String, dynamic>{'current_page': 1, 'last_page': 1},
        }),
      );
      addTearDown(client.close);

      // Reporting a wrong-typed "data" as "no results" would silently hide
      // the results the user asked for; the shape is broken, so it fails.
      await expectLater(
        client.search(WallhavenSearchRequest()),
        throwsA(isA<WallhavenInvalidResponseException>()),
      );
    });

    test('an absent data field is an empty page', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'meta': <String, dynamic>{'current_page': 1, 'last_page': 0},
        }),
      );
      addTearDown(client.close);

      final page = await client.search(WallhavenSearchRequest());
      expect(page.items, isEmpty);
      expect(page.hasNextPage, isFalse);
    });

    test('a non-object meta block fails as a typed error', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <dynamic>[],
          'meta': 'nope',
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.search(WallhavenSearchRequest()),
        throwsA(isA<WallhavenInvalidResponseException>()),
      );
    });

    test('a rejected page does not poison the retry path', () async {
      ResponseBody body(String raw) => ResponseBody.fromString(
        raw,
        200,
        headers: const {
          'content-type': ['application/json'],
        },
      );
      final adapter = FakeWallhavenAdapter([
        (_, _) async => body('{"data": "not-an-object"}'),
        (_, _) async => body('{"data": [{"id": "good1"}], "meta": {}}'),
      ]);
      final client = buildTestClient(adapter: adapter);
      addTearDown(client.close);

      await expectLater(
        client.search(WallhavenSearchRequest()),
        throwsA(isA<WallhavenInvalidResponseException>()),
      );

      // Two things must hold for a retry to be worth offering the user:
      // the failed flight is dropped by the deduper, and the transport cache
      // no longer holds the rejected body.
      final page = await client.search(WallhavenSearchRequest());
      expect(page.items.single.id, 'good1');
      expect(adapter.callCount, 2, reason: 'the retry must reach the network');
    });

    test('rejected detail payloads are re-fetched on retry', () async {
      ResponseBody body(String raw) => ResponseBody.fromString(
        raw,
        200,
        headers: const {
          'content-type': ['application/json'],
        },
      );
      final adapter = FakeWallhavenAdapter([
        (_, _) async => body('{"data": {}}'),
        (_, _) async => body('{"data": {"id": "abc123"}}'),
      ]);
      final client = buildTestClient(adapter: adapter);
      addTearDown(client.close);

      await expectLater(
        client.wallpaper('abc123'),
        throwsA(isA<WallhavenInvalidResponseException>()),
      );

      final wallpaper = await client.wallpaper('abc123');
      expect(wallpaper.id, 'abc123');
      expect(
        adapter.callCount,
        2,
        reason: 'an unusable cached 200 must not be replayed',
      );
    });
  });

  group('collection payloads', () {
    test('malformed entries fail as typed errors (never TypeError)', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <dynamic>[
            <String, dynamic>{'id': 1, 'label': 'Default'},
            <String, dynamic>{'id': 'not-a-number', 'label': 'Broken'},
          ],
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.collections(username: 'someone'),
        throwsA(isA<WallhavenInvalidResponseException>()),
      );
    });

    test('numeric-string and 0/1 fields still decode', () async {
      final client = buildTestClient(
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
      addTearDown(client.close);

      final collections = await client.collections(username: 'someone');
      expect(collections.single.id, 7);
      expect(collections.single.label, 'Favourites');
      expect(collections.single.views, 12);
      expect(collections.single.public, isTrue);
      expect(collections.single.count, 3);
    });
  });

  group('settings payloads', () {
    test('wrongly typed fields degrade instead of throwing', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json({
          'data': <String, dynamic>{
            'thumb_size': 512,
            'per_page': '32',
            'purity': 'sfw',
            'categories': <dynamic>[1, 'anime'],
            'resolutions': <String, dynamic>{'oops': true},
            'toplist_range': <dynamic>[],
          },
        }),
      );
      addTearDown(client.close);
      client.apiKeyManager.setApiKey('k');

      final settings = await client.settings();

      expect(settings.thumbSize, isNull);
      expect(settings.perPage, 32);
      expect(settings.purities, isEmpty);
      expect(settings.categories, [Category.anime]);
      expect(settings.resolutions, isEmpty);
      expect(settings.toplistRange, isNull);
      expect(settings.tagBlacklist, isEmpty);
    });
  });
}
