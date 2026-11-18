import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

void main() {
  test('nextPage advances the page and carries query, sorting, and seed',
      () async {
    // Scenario 1: query parameters survive the page increment.
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
    var adapter = FakeWallhavenAdapter([
      (_, _) async => ResponseBodies.json(fixture('search_response.json')),
      (_, _) async => ResponseBodies.json(page2Body),
    ]);
    var client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final request = WallhavenSearchRequest(query: 'anime');
    final first = await client.search(request);
    final second = await client.nextPage(request, first);
    expect(second.currentPage, 2);
    expect(adapter.requests[1].uri.queryParameters['page'], '2');
    expect(adapter.requests[1].uri.queryParameters['q'], 'anime');

    // Scenario 2: a random search with no caller seed adopts the server's
    // seed for the follow-up page.
    const seededPage2 = <String, dynamic>{
      'data': <dynamic>[],
      'meta': <String, dynamic>{
        'current_page': 2,
        'last_page': 9,
        'per_page': 24,
        'total': 200,
      },
    };
    adapter = FakeWallhavenAdapter([
      (_, _) async => ResponseBodies.json(fixture('search_response.json')),
      (_, _) async => ResponseBodies.json(seededPage2),
    ]);
    client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final randomRequest =
        WallhavenSearchRequest(sorting: WallhavenSorting.random);
    final randomFirst = await client.search(randomRequest);
    expect(randomFirst.meta.seed, 'abc123'); // server-assigned

    await client.nextPage(randomRequest, randomFirst);
    final secondUrl = adapter.requests[1].uri;
    expect(secondUrl.queryParameters['seed'], 'abc123');
    expect(secondUrl.queryParameters['sorting'], 'random');
    expect(secondUrl.queryParameters['page'], '2');

    // Scenario 3: a caller-pinned seed wins over the server echo.
    adapter = FakeWallhavenAdapter([ResponseBodies.okListing]);
    client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final pinned = WallhavenSearchRequest(seed: 'zzz999', page: 1);
    final pinnedFirst = await client.search(pinned);
    // The canned fixture echoes seed abc123; caller pinned zzz999.
    final pinnedNext = await client.nextPage(pinned, pinnedFirst);
    expect(adapter.lastRequest.uri.queryParameters['page'], '2');
    expect(adapter.lastRequest.uri.queryParameters['seed'], 'zzz999');
    expect(pinnedNext.items, hasLength(1));
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
