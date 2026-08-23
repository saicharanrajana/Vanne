import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/src/http/dio_factory.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

void main() {
  group('cache store identity', () {
    test('transport caches into the same store exposed as cacheStore', () async {
      // If the interceptor cached into a DIFFERENT store than the one we
      // hold, clearing ours would have no effect and the second identical
      // request would still be served from cache.
      var hits = 0;
      final manager = ApiKeyManager();
      final store = InMemoryCacheStore();
      final dio = buildDio(
        const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        apiKeyManager: manager,
        cacheStore: store,
      )..httpClientAdapter = CountingAdapter(() => hits++);
      final client = WallhavenClient(
        apiKeyManager: manager,
        config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        dio: dio,
        cache: store,
      );
      expect(client.cacheStore, same(store));

      await client.search(WallhavenSearchRequest(query: 'identity'));
      expect(hits, 1);

      await client.cacheStore.clear();
      await client.search(WallhavenSearchRequest(query: 'identity'));
      expect(hits, 2);
    });

    test('close() clears the exposed store', () async {
      var hits = 0;
      final manager = ApiKeyManager();
      final store = InMemoryCacheStore();
      final dio = buildDio(
        const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        apiKeyManager: manager,
        cacheStore: store,
      )..httpClientAdapter = CountingAdapter(() => hits++);
      final client = WallhavenClient(
        apiKeyManager: manager,
        config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        dio: dio,
        cache: store,
      );

      await client.search(WallhavenSearchRequest(query: 'close'));
      expect(hits, 1);
      client.close();

      // Cache was cleared with close(): a new identical request must
      // reach the network again (fresh Dio here since old one is closed).
      final dio2 = buildDio(
        const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        apiKeyManager: manager,
        cacheStore: store,
      )..httpClientAdapter = CountingAdapter(() => hits++);
      final client2 = WallhavenClient(
        apiKeyManager: manager,
        config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        dio: dio2,
        cache: store,
      );
      await client2.search(WallhavenSearchRequest(query: 'close'));
      expect(hits, 2);
    });
  });

  group('TTL expiry', () {
    test('expired entries fall through to the network', () async {
      var hits = 0;
      final clock = MutableClock();
      final manager = ApiKeyManager();
      final store = InMemoryCacheStore();
      final dio = buildDio(
        const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        apiKeyManager: manager,
        cacheStore: store,
        clock: () => clock.now,
      )..httpClientAdapter = CountingAdapter(() => hits++);
      final client = WallhavenClient(
        apiKeyManager: manager,
        config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        dio: dio,
        cache: store,
        clock: () => clock.now,
      );

      final request = WallhavenSearchRequest(query: 'ttl');
      await client.search(request);
      expect(hits, 1);

      // Within TTL → cached.
      clock.now = clock.now.add(const Duration(minutes: 4));
      await client.search(request);
      expect(hits, 1);

      // Past the 5-minute default TTL → network again.
      clock.now = clock.now.add(const Duration(minutes: 2));
      await client.search(request);
      expect(hits, 2);
    });
  });

  group('InMemoryCacheStore eviction', () {
    test('respects maxEntries with LRU ordering', () async {
      final store = InMemoryCacheStore(maxEntries: 2);
      final now = DateTime.utc(2026, 1, 1);
      CacheEntry entry(int i) => CacheEntry(
            statusCode: 200,
            json: {'i': i},
            expiresAt: now.add(const Duration(hours: 1)),
          );

      await store.put('a', entry(0));
      await store.put('b', entry(1));
      // Touch 'a' so 'b' becomes the LRU victim.
      expect((await store.get('a', now: now))!.json, {'i': 0});
      await store.put('c', entry(2));

      expect(await store.get('b', now: now), isNull); // evicted
      expect((await store.get('a', now: now))!.json, {'i': 0});
      expect((await store.get('c', now: now))!.json, {'i': 2});
    });

    test('expired-but-unread entries do not accumulate forever', () async {
      final store = InMemoryCacheStore(maxEntries: 2);
      final now = DateTime.utc(2026, 1, 1);
      Future<void> put(String key, DateTime expiry) => store.put(
            key,
            CacheEntry(statusCode: 200, json: key, expiresAt: expiry),
          );

      await put('a', now.add(const Duration(seconds: 10)));
      await put('b', now.add(const Duration(seconds: 10)));
      final later = now.add(const Duration(minutes: 30));
      // Both a and b are expired now; putting two more must evict them.
      await put('c', later.add(const Duration(hours: 1)));
      await put('d', later.add(const Duration(hours: 1)));

      expect(await store.get('a', now: later), isNull);
      expect(await store.get('b', now: later), isNull);
      expect(await store.get('c', now: later), isNotNull);
      expect(await store.get('d', now: later), isNotNull);
    });
  });

  group('concurrent rate limiting', () {
    test('burst of parallel requests stays under the cap', () async {
      final delays = <Duration>[];
      final clock = MutableClock();
      final manager = ApiKeyManager();
      final dio = buildDio(
        const WallhavenConfig(
          baseUrl: 'https://unit.test/api/v1',
          requestsPerMinute: 3,
        ),
        apiKeyManager: manager,
        cacheStore: InMemoryCacheStore(),
        clock: () => clock.now,
        delay: (d) async {
          delays.add(d);
          // Simulate time passing while throttled so the window drains.
          clock.now = clock.now.add(d);
        },
      )..httpClientAdapter =
            FakeWallhavenAdapter(List.filled(12, FakeHandlers.ok));
      final client = WallhavenClient(
        apiKeyManager: manager,
        config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        dio: dio,
        clock: () => clock.now,
      );

      // 12 parallel searches against a 3-per-window limiter.
      final futures = [
        for (var i = 0; i < 12; i++)
          client.search(WallhavenSearchRequest(query: 'q$i')),
      ];
      // All complete without errors; the limiter engaged at least once
      // because the first window only admits 3 of the 12.
      await Future.wait(futures);
      expect(delays, isNotEmpty);
    });
  });

  group('dedupe cancellation semantics', () {
    test('one waiter cancelling fails all waiters sharing the flight',
        () async {
      final manager = ApiKeyManager();
      final dio = buildDio(
        const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        apiKeyManager: manager,
        cacheStore: InMemoryCacheStore(),
      );
      // Adapter never completes until we allow it — keeps the GET in flight.
      final gate = Completer<void>();
      dio.httpClientAdapter = NeverCompletingAdapter(gate.future);

      final client = WallhavenClient(
        apiKeyManager: manager,
        config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        dio: dio,
      );

      final cancelToken = CancelToken();
      final first = client.search(
        WallhavenSearchRequest(query: 'shared'),
        cancelToken: cancelToken,
      );
      final second = client.search(WallhavenSearchRequest(query: 'shared'));

      cancelToken.cancel();

      await expectLater(first, throwsA(isA<WallhavenCancelledException>()));
      await expectLater(second, throwsA(isA<WallhavenCancelledException>()));
      gate.complete();
    });
  });

  group('error contract hardening', () {
    test('non-dio transport failures surface as typed errors', () async {
      final manager = ApiKeyManager();
      final dio = buildDio(
        const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        apiKeyManager: manager,
        cacheStore: InMemoryCacheStore(),
      )..httpClientAdapter = ThrowingAdapter();
      final client = WallhavenClient(
        apiKeyManager: manager,
        config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        dio: dio,
      );

      await expectLater(
        client.search(WallhavenSearchRequest(query: 'boom')),
        throwsA(isA<WallhavenNetworkException>()),
      );
    });

    test('HTTP-date Retry-After maps to a duration via the injected clock',
        () async {
      final fixedNow = DateTime.utc(2026, 8, 24, 12, 0, 0);
      final manager = ApiKeyManager();
      final dio = buildDio(
        const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        apiKeyManager: manager,
        cacheStore: InMemoryCacheStore(),
      )..httpClientAdapter = RateLimitedAdapter(retryAfterHttpDate: true);
      final client = WallhavenClient(
        apiKeyManager: manager,
        config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        dio: dio,
        clock: () => fixedNow,
      );

      Object? error;
      try {
        await client.search(WallhavenSearchRequest(query: 'slow'));
      } on WallhavenRateLimitExceededException catch (e) {
        error = e;
      }
      expect(error, isA<WallhavenRateLimitExceededException>());
      final retryAfter = (error as WallhavenRateLimitExceededException)
          .retryAfter;
      expect(retryAfter, isNotNull);
      // "Mon, 24 Aug 2026 12:01:00 GMT" − 12:00:00 → 60 s.
      expect(retryAfter, const Duration(seconds: 60));
    });
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
      '"per_page": 24}}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Adapter that throws a raw (non-dio) exception.
class ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw StateError('adapter exploded');
  }

  @override
  void close({bool force = false}) {}
}

/// Adapter whose response never completes until [gate] completes.
class NeverCompletingAdapter implements HttpClientAdapter {
  NeverCompletingAdapter(this.gate);

  final Future<void> gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await gate;
    return ResponseBody.fromString(
      '{"data": [], "meta": {"current_page": 1, "last_page": 0, '
      '"per_page": 24}}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Adapter answering 429 with an HTTP-date Retry-After header.
class RateLimitedAdapter implements HttpClientAdapter {
  RateLimitedAdapter({required this.retryAfterHttpDate});

  final bool retryAfterHttpDate;

  static const _httpDate = 'Mon, 24 Aug 2026 12:01:00 GMT';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'error': 'Too many requests'}),
      429,
      headers: {
        'content-type': ['application/json'],
        if (retryAfterHttpDate) 'retry-after': [_httpDate],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
