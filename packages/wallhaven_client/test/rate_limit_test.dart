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
    test('Retry-After parses numeric seconds and HTTP-date via the clock',
        () async {
      final numeric = buildTestClient(
        adapter: FakeWallhavenAdapter([
          (_, _) async => _json(
                {'error': 'Too many requests.'},
                status: 429,
                headers: {
                  'retry-after': ['30'],
                },
              ),
        ]),
      );
      addTearDown(numeric.close);
      await expectLater(
        numeric.search(WallhavenSearchRequest()),
        throwsA(
          isA<WallhavenRateLimitExceededException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 30),
          ),
        ),
      );

      // HTTP-date form: "Mon, 24 Aug 2026 12:01:00 GMT" − 12:00:00 → 60 s.
      final clock = MutableClock(DateTime.utc(2026, 8, 24, 12, 0, 0));
      final dated = buildTestClient(
        clock: clock,
        adapter: FakeWallhavenAdapter([
          (_, _) async => _json(
                {'error': 'Too many requests.'},
                status: 429,
                headers: {
                  'retry-after': ['Mon, 24 Aug 2026 12:01:00 GMT'],
                },
              ),
        ]),
      );
      addTearDown(dated.close);
      await expectLater(
        dated.search(WallhavenSearchRequest()),
        throwsA(
          isA<WallhavenRateLimitExceededException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 60),
          ),
        ),
      );
    });

    test('missing Retry-After yields null and 429s are never retried',
        () async {
      final adapter = FakeWallhavenAdapter([
        (_, _) async => _json(const {}, status: 429),
        (_, _) async => _json(const {}),
      ]);
      final client = buildTestClient(adapter: adapter);
      addTearDown(client.close);

      await expectLater(
        client.search(WallhavenSearchRequest(query: 'a')),
        throwsA(
          isA<WallhavenRateLimitExceededException>()
              .having((e) => e.retryAfter, 'retryAfter', isNull),
        ),
      );
      expect(adapter.callCount, 1,
          reason: 'the documented contract is zero automatic retries');
    });
  });

  group('client-side throttling (sliding window)', () {
    test('admits the limit immediately and delays only the overflow',
        () async {
      final clock = MutableClock();
      final delays = <Duration>[];
      // Build the chain manually to capture and advance the fake clock.
      final adapter = FakeWallhavenAdapter([FakeHandlers.ok]);
      final manager = ApiKeyManager();
      final dio = buildDio(
        const WallhavenConfig(requestsPerMinute: 3),
        apiKeyManager: manager,
        cacheStore: InMemoryCacheStore(),
        clock: () => clock.now,
        delay: (d) async {
          delays.add(d);
          clock.now = clock.now.add(d);
        },
      )..httpClientAdapter = adapter;
      final client = WallhavenClient(
        apiKeyManager: manager,
        dio: dio,
        clock: () => clock.now,
      );
      addTearDown(client.close);

      // The first three requests fit the window and must not wait.
      for (var i = 0; i < 3; i++) {
        await client.search(WallhavenSearchRequest(query: 'q$i'));
      }
      expect(delays, isEmpty,
          reason: 'requests within the limit must never be delayed');

      // The fourth hits a full window at elapsed 0, so it waits exactly the
      // remaining window; the delay advances the fake clock past the window.
      await client.search(WallhavenSearchRequest(query: 'overflow-1'));
      expect(delays, [const Duration(minutes: 1)]);

      // The window has drained, so the fifth is admitted without waiting.
      await client.search(WallhavenSearchRequest(query: 'overflow-2'));
      expect(delays, hasLength(1));
      expect(delays.single, lessThanOrEqualTo(const Duration(minutes: 1)));
      expect(adapter.callCount, 5,
          reason: 'every request eventually goes through — none dropped');
    });

    test('a concurrent burst is admitted in bounded windows', () async {
      final clock = MutableClock();
      final delays = <Duration>[];
      final adapter =
          FakeWallhavenAdapter(List.filled(6, FakeHandlers.ok));
      final manager = ApiKeyManager();
      final dio = buildDio(
        const WallhavenConfig(requestsPerMinute: 3),
        apiKeyManager: manager,
        cacheStore: InMemoryCacheStore(),
        clock: () => clock.now,
        delay: (d) async {
          delays.add(d);
          clock.now = clock.now.add(d);
        },
      )..httpClientAdapter = adapter;
      final client = WallhavenClient(
        apiKeyManager: manager,
        dio: dio,
        clock: () => clock.now,
      );
      addTearDown(client.close);

      // Six simultaneous requests against a three-per-window limiter: the
      // window must serialise admission rather than letting every request
      // through at once.
      await Future.wait([
        for (var i = 0; i < 6; i++)
          client.search(WallhavenSearchRequest(query: 'burst-$i')),
      ]);

      expect(adapter.callCount, 6, reason: 'none dropped');
      expect(delays, isNotEmpty,
          reason: 'concurrent admission must still enforce the window');
      for (final delay in delays) {
        expect(delay, lessThanOrEqualTo(const Duration(minutes: 1)));
      }
    });
  });
}
