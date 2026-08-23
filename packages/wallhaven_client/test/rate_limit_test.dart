import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/src/http/dio_factory.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

ResponseBody _json(Object? body, {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json'],
        ...headers,
      },
    );

void main() {
  group('429 handling', () {
    test('Retry-After header is parsed into the typed exception', () async {
      final adapter = FakeWallhavenAdapter([
        (_, _) async => _json(
              {'error': 'Too many requests.'},
              status: 429,
              headers: {
                'retry-after': ['30'],
              },
            ),
      ]);
      final client = buildTestClient(adapter: adapter);
      addTearDown(client.close);

      await expectLater(
        client.search(WallhavenSearchRequest()),
        throwsA(
          isA<WallhavenRateLimitExceededException>()
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 30)),
        ),
      );
    });

    test('missing Retry-After yields a null duration', () async {
      final client = buildTestClient(
        adapter: FakeWallhavenAdapter.json(
          fixture('error_429.json'),
          status: 429,
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.search(WallhavenSearchRequest()),
        throwsA(
          isA<WallhavenRateLimitExceededException>()
              .having((e) => e.retryAfter, 'retryAfter', isNull),
        ),
      );
    });

    test('no automatic retry happens after a 429', () async {
      final adapter = FakeWallhavenAdapter([
        (_, _) async => _json(const {}, status: 429),
        (_, _) async => _json(const {}),
      ]);
      final client = buildTestClient(adapter: adapter);
      addTearDown(client.close);

      await expectLater(
        client.search(WallhavenSearchRequest(query: 'a')),
        throwsA(isA<WallhavenRateLimitExceededException>()),
      );
      expect(adapter.callCount, 1,
          reason: 'the documented contract is zero automatic retries');
    });
  });

  group('client-side throttling (sliding window)', () {
    test('requests within the limit are never delayed', () async {
      final clock = MutableClock();
      final requestedDelays = <Duration>[];
      final adapter = FakeWallhavenAdapter([FakeHandlers.ok]);
      // Build the chain manually to capture the delay function.
      final manager = ApiKeyManager();
      final dio = buildDio(
        const WallhavenConfig(requestsPerMinute: 3),
        apiKeyManager: manager,
        cacheStore: InMemoryCacheStore(),
        clock: () => clock.now,
        delay: (d) async => requestedDelays.add(d),
      )..httpClientAdapter = adapter;
      final client = WallhavenClient(
        apiKeyManager: manager,
        dio: dio,
        clock: () => clock.now,
      );
      addTearDown(client.close);

      for (var i = 0; i < 3; i++) {
        await client.search(WallhavenSearchRequest(query: 'q$i'));
      }
      expect(adapter.callCount, 3);
      expect(requestedDelays, isEmpty);
    });

    test('request over the limit waits until the window frees', () async {
      final clock = MutableClock();
      final requestedDelays = <Duration>[];
      final adapter =
          FakeWallhavenAdapter([FakeHandlers.ok]); // repeats forever
      final manager = ApiKeyManager();
      final dio = buildDio(
        const WallhavenConfig(requestsPerMinute: 2),
        apiKeyManager: manager,
        cacheStore: InMemoryCacheStore(),
        clock: () => clock.now,
        delay: (d) async {
          requestedDelays.add(d);
          // Simulate the wait by advancing the fake clock.
          clock.now = clock.now.add(d);
        },
      )..httpClientAdapter = adapter;
      final client = WallhavenClient(
        apiKeyManager: manager,
        dio: dio,
        clock: () => clock.now,
      );
      addTearDown(client.close);

      for (var i = 0; i < 5; i++) {
        await client
            .search(WallhavenSearchRequest(query: 'q$i', sorting: WallhavenSorting.random, seed: null));
      }
      expect(adapter.callCount, 5,
          reason: 'every request eventually goes through — none dropped');
      expect(requestedDelays, isNotEmpty,
          reason: 'over-limit requests must have been delayed');
      // All delays are bounded by the one-minute window.
      for (final d in requestedDelays) {
        expect(d, lessThanOrEqualTo(const Duration(minutes: 1)));
      }
    });
  });
}
