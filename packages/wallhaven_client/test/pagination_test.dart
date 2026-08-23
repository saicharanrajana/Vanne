import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

void main() {
  test('page 1 of a paginated result maps metadata', () async {
    final client = buildTestClient(
      adapter: FakeWallhavenAdapter.json(fixture('search_response.json')),
    );
    addTearDown(client.close);

    final page = await client.search(WallhavenSearchRequest());
    expect(page.currentPage, 1);
    expect(page.lastPage, 36);
    expect(page.perPage, 24);
    expect(page.total, 848);
    expect(page.hasNextPage, isTrue);
  });

  test('nextPage increments the page and preserves parameters', () async {
    // Two distinct responses: page 1, then a page-2 body.
    const page2Body = <String, dynamic>{
      'data': <dynamic>[],
      'meta': <String, dynamic>{
        'current_page': 2,
        'last_page': 36,
        'per_page': 24,
        'total': 848,
        'query': 'anime',
      },
    };
    final adapter = FakeWallhavenAdapter([
      (_, _) async => ResponseBodies.json(fixture('search_response.json')),
      (_, _) async => ResponseBodies.json(page2Body),
    ]);
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final request = WallhavenSearchRequest(query: 'anime');
    final first = await client.search(request);
    final second = await client.nextPage(request, first);

    expect(second.currentPage, 2);
    expect(adapter.requests[1].uri.queryParameters['page'], '2');
    expect(adapter.requests[1].uri.queryParameters['q'], 'anime');
  });

  test('random seed from meta is propagated into the follow-up request',
      () async {
    const seededPage2 = <String, dynamic>{
      'data': <dynamic>[],
      'meta': <String, dynamic>{
        'current_page': 2,
        'last_page': 9,
        'per_page': 24,
        'total': 200,
      },
    };
    final adapter = FakeWallhavenAdapter([
      // Page 1 of a random search: server assigns the seed.
      (_, _) async => ResponseBodies.json(fixture('search_response.json')),
      (_, _) async => ResponseBodies.json(seededPage2),
    ]);
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final request =
        WallhavenSearchRequest(sorting: WallhavenSorting.random); // no seed
    final first = await client.search(request);
    expect(first.meta.seed, 'abc123'); // server-assigned

    await client.nextPage(request, first);

    final secondUrl = adapter.requests[1].uri;
    expect(secondUrl.queryParameters['seed'], 'abc123');
    expect(secondUrl.queryParameters['sorting'], 'random');
    expect(secondUrl.queryParameters['page'], '2');
  });

  test('caller-pinned seed wins over server seed', () async {
    final adapter = FakeWallhavenAdapter([ResponseBodies.okListing]);
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final request = WallhavenSearchRequest(seed: 'zzz999', page: 1);
    final first = await client.search(request);
    // The canned fixture echoes seed abc123; caller pinned zzz999.
    final next = await client.nextPage(request, first);

    // The canned handler always echoes current_page 1; what matters here
    // is that page advanced on the wire and the caller-pinned seed
    // reached it unchanged.
    expect(adapter.lastRequest.uri.queryParameters['page'], '2');
    expect(adapter.lastRequest.uri.queryParameters['seed'], 'zzz999');
    expect(next.items, hasLength(1));
  });

  test('last page has no next page and nextPage makes no request',
      () async {
    final adapter = FakeWallhavenAdapter([FakeHandlers.okLastPage]);
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final request = WallhavenSearchRequest();
    final last = await client.search(request);
    expect(last.hasNextPage, isFalse);

    await client.nextPage(request, last);
    expect(adapter.callCount, 1,
        reason: 'no network activity may occur past the last page');
  });
}

/// Reusable response builders for tests.
class ResponseBodies {
  static Future<ResponseBody> json(Object? body) async => ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );

  /// Minimal listing with items but no further pages.
  static Future<ResponseBody> okListing(
          RequestOptions options, int callIndex) async =>
      json(const {
        'data': [
          {
            'id': 'aa11bb',
            'url': 'https://wallhaven.cc/w/aa11bb',
            'purity': 'sfw',
            'category': 'general',
            'dimension_x': 100,
            'dimension_y': 100,
            'resolution': '100x100',
            'ratio': '1.0',
            'file_size': 1,
            'file_type': 'image/jpeg',
            'views': 0,
            'favorites': 0,
            'source': '',
            'colors': [],
            'path': '',
            'thumbs': {},
          }
        ],
        'meta': {'current_page': 1, 'last_page': 5, 'per_page': 24},
      });

  static Future<ResponseBody> okLastPage(
          RequestOptions options, int callIndex) async =>
      json(const {
        'data': [],
        'meta': {'current_page': 5, 'last_page': 5, 'per_page': 24},
      });
}
