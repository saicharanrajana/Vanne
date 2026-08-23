import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'helpers.dart';

void main() {
  test('successful search hits /search with sorted params', () async {
    final adapter =
        FakeWallhavenAdapter.json(fixture('search_response.json'));
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final page = await client.search(
      WallhavenSearchRequest(query: 'anime', sorting: WallhavenSorting.views),
    );

    expect(page.items, hasLength(2));
    final uri = adapter.lastRequest.uri;
    expect(uri.path, '/api/v1/search');
    expect(uri.queryParameters['q'], 'anime');
    expect(uri.queryParameters['sorting'], 'views');
  });

  test('empty search result yields terminal page without error',
      () async {
    final client = buildTestClient(
      adapter: FakeWallhavenAdapter.json(
        fixture('search_empty_response.json'),
      ),
    );
    addTearDown(client.close);

    // current_page 3 > last_page 2 AND empty items → no next page.
    final page = await client.search(WallhavenSearchRequest(page: 3));
    expect(page.items, isEmpty);
    expect(page.hasNextPage, isFalse);
  });

  test('out-of-range page returns a valid empty result', () async {
    const body = <String, dynamic>{
      'data': <dynamic>[],
      'meta': <String, dynamic>{
        'current_page': 99,
        'last_page': 5,
        'per_page': 24,
        'total': 100,
      },
    };
    final client = buildTestClient(
      adapter: FakeWallhavenAdapter.json(body),
    );
    addTearDown(client.close);

    final page = await client.search(WallhavenSearchRequest(page: 99));
    expect(page.items, isEmpty);
    expect(page.currentPage, 99);
    expect(page.hasNextPage, isFalse);
  });

  test('wallpaper detail unwraps envelope and requests /w/{id}',
      () async {
    final adapter =
        FakeWallhavenAdapter.json(fixture('wallpaper_response.json'));
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final wallpaper = await client.wallpaper('94x38z');
    expect(adapter.lastRequest.uri.path, '/api/v1/w/94x38z');
    expect(wallpaper.id, '94x38z');
    expect(wallpaper.hasDetails, isTrue);
  });

  test('tag detail requests /tag/{id}', () async {
    final adapter = FakeWallhavenAdapter.json(fixture('tag_response.json'));
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final tag = await client.tag(1);
    expect(adapter.lastRequest.uri.path, '/api/v1/tag/1');
    expect(tag.name, 'anime');
  });

  test('settings requires an API key and sends it as header', () async {
    final adapter =
        FakeWallhavenAdapter.json(fixture('settings_response.json'));
    final manager = ApiKeyManager();
    final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
    addTearDown(client.close);

    await expectLater(
      client.settings(),
      throwsA(isA<AuthenticationRequiredException>()),
    );
    // No request was spent on the rejected call.
    expect(adapter.callCount, 0);

    manager.setApiKey('secret-key');
    await client.settings();
    expect(adapter.callCount, 1);
    expect(adapter.lastRequest.header('X-API-Key'), 'secret-key');
    // Key never leaks into the URL.
    expect(adapter.lastRequest.uri.toString(), isNot(contains('secret-key')));
  });

  test('collections: own require auth; user collections do not', () async {
    final manager = ApiKeyManager();
    final adapter = FakeWallhavenAdapter([
      (_, _) async => ResponseBody.fromString(
            '{"data":[]}',
            200,
            headers: {
              'content-type': ['application/json'],
            },
          ),
    ]);
    final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
    addTearDown(client.close);

    await expectLater(
      client.collections(),
      throwsA(isA<AuthenticationRequiredException>()),
    );

    await client.collections(username: 'alice');
    expect(adapter.lastRequest.uri.path, '/api/v1/collections/alice');
    expect(adapter.lastRequest.hasHeader('X-API-Key'), isFalse,
        reason: 'public listings must not attach the key');
  });

  test('collection wallpapers pass purity and page', () async {
    final adapter = FakeWallhavenAdapter.json(
      fixture('collection_wallpapers_response.json'),
    );
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final page = await client.collectionWallpapers(
      username: 'alice',
      collectionId: 15,
      purity: {WallhavenPurity.sfw},
      page: 2,
    );

    final uri = adapter.lastRequest.uri;
    expect(uri.path, '/api/v1/collections/alice/15');
    expect(uri.queryParameters['purity'], '100');
    expect(uri.queryParameters['page'], '2');
    expect(page.meta.seed, 'xyz789');
  });

  test('NSFW collection listing fails fast without a key', () async {
    // Fail fast means zero network activity.
    final adapter = FakeWallhavenAdapter.json(const {});
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    await expectLater(
      client.collectionWallpapers(
        username: 'alice',
        collectionId: 15,
        purity: {WallhavenPurity.sfw, WallhavenPurity.nsfw},
      ),
      throwsA(isA<NsfwAuthenticationRequiredException>()),
    );
    expect(adapter.callCount, 0);
  });
}
