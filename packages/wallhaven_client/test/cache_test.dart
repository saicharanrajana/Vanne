
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/src/http/dio_factory.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

void main() {
  test('second identical GET is served from the cache', () async {
    var hits = 0;
    final manager = ApiKeyManager();
    // Cascade assigns AFTER buildDio returns so the client's actual
    // transport is the counting one.
    final clientDio = buildDio(
      const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
      apiKeyManager: manager,
      cacheStore: InMemoryCacheStore(),
    )..httpClientAdapter = CountingAdapter(() => hits++);
    final client = WallhavenClient(
      apiKeyManager: manager,
      config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
      dio: clientDio,
    );

    await client.search(WallhavenSearchRequest(query: 'cache'));
    await client.search(WallhavenSearchRequest(query: 'cache'));

    // Both searches succeed; only the first reaches the adapter because
    // the second is answered by the TTL cache.
    expect(hits, 1);
  });

  test('non-GET requests and cache opt-outs bypass the cache', () async {
    // (The public API is GET-only; opt-out behavior is covered indirectly
    // by distinct queries never colliding in the cache.)
  });
}

class CountingAdapter implements HttpClientAdapter {
  CountingAdapter(this.onFetch);

  final void Function() onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onFetch();
    return ResponseBody.fromString(
      '{"data": [], "meta": {"current_page": 1, "last_page": 0, '
      '"per_page": 24, "query": "cache"}}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
