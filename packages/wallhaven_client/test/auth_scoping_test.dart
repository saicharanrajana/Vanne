import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/src/http/dio_factory.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

/// Regression flows for authentication-scoped transport state.
///
/// Wallhaven serves account-specific payloads from shared paths (`/settings`,
/// `/collections`, and — once authenticated — per-user purity in `/search`).
/// The response cache and the in-flight request deduper must therefore never
/// hand one account's payload to another. Cache and dedupe keys are internal
/// and must also stay free of raw API-key material.
void main() {
  final request = WallhavenSearchRequest(query: 'scoped');

  group('cache isolation across API keys', () {
    test('account-specific endpoints are never shared between accounts',
        () async {
      final adapter = FakeWallhavenAdapter([
        // Call order below: settings A, collections A, settings B,
        // collections B.
        (_, _) async => _json(<String, dynamic>{
          'data': <String, dynamic>{'per_page': 24, 'toplist_range': 'A'},
        }),
        (_, _) async => _collections(['private-of-A']),
        (_, _) async => _json(<String, dynamic>{
          'data': <String, dynamic>{'per_page': 48, 'toplist_range': 'B'},
        }),
        (_, _) async => _collections(['private-of-B']),
      ]);
      final manager = ApiKeyManager(initialApiKey: 'key-a');
      final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
      addTearDown(client.close);

      expect((await client.settings()).toplistRange, 'A');
      expect((await client.collections()).single.label, 'private-of-A');

      manager.setApiKey('key-b');
      expect(
        (await client.settings()).toplistRange,
        'B',
        reason: 'the second account must not read the first one\'s settings',
      );
      expect(
        (await client.collections()).single.label,
        'private-of-B',
        reason: 'private collections must never cross accounts',
      );
      expect(adapter.callCount, 4);
    });

    test('signing in does not reuse the anonymous cache', () async {
      final adapter = FakeWallhavenAdapter([
        (_, _) async => _page('anonymous'),
        (_, _) async => _page('signed-in'),
      ]);
      final manager = ApiKeyManager();
      final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
      addTearDown(client.close);

      expect((await client.search(request)).items.single.id, 'anonymous');
      manager.setApiKey('key-a');
      expect(
        (await client.search(request)).items.single.id,
        'signed-in',
        reason: 'purity/blacklist settings change what a search returns',
      );
      expect(adapter.callCount, 2);
    });
  });

  group('in-flight deduplication across API keys', () {
    test('a key change neither joins nor is poisoned by the previous key',
        () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final adapter = FakeWallhavenAdapter([
        (_, _) async {
          if (!started.isCompleted) started.complete();
          await release.future;
          return _page('A');
        },
        (_, _) async => _page('B'),
      ]);
      final manager = ApiKeyManager(initialApiKey: 'key-a');
      final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
      addTearDown(client.close);

      final heldA = client.search(request);
      await started.future;

      manager.setApiKey('key-b');
      final bCall = client.search(request);
      // Bounded wait instead of awaiting the call directly: a regression here
      // means key B is parked on key A's future (opaque 30 s test timeout).
      await _waitForCalls(adapter, 2);
      final bPage = await bCall;
      expect(
        bPage.items.single.id,
        'B',
        reason: 'key B must issue its own request, not await key A\'s',
      );
      expect(adapter.requests.last.header('X-API-Key'), 'key-b');

      // Key A's response completes only after key B is active. It must be
      // cached (if at all) under key A's identity, never key B's.
      release.complete();
      expect((await heldA).items.single.id, 'A');

      final bCached = await client.search(request);
      expect(bCached.items.single.id, 'B',
          reason: 'the late key-A response must not overwrite key B\'s entry');
      expect(adapter.callCount, 2);
    });
  });

  group('credential captured at dispatch', () {
    test('dispatch identity is pinned before interceptors run', () async {
      // Scenario 1: an anonymous dispatch stays anonymous even if a key is
      // configured before the interceptors run.
      final anonymousAdapter = FakeWallhavenAdapter([
        (_, _) async => _page('anonymous'),
        (_, _) async => _page('signed-in'),
      ]);
      final anonymousManager = ApiKeyManager();
      final anonymousClient = buildTestClient(
        adapter: anonymousAdapter,
        apiKeyManager: anonymousManager,
      );
      addTearDown(anonymousClient.close);

      final pendingAnonymous = anonymousClient.search(request);
      anonymousManager.setApiKey('key-a');
      expect((await pendingAnonymous).items.single.id, 'anonymous');
      expect(anonymousAdapter.requests.single.hasHeader('X-API-Key'), isFalse);
      expect(
        (await anonymousClient.search(request)).items.single.id,
        'signed-in',
      );
      expect(anonymousAdapter.callCount, 2,
          reason: 'the signed-in request must not join/cache under anonymous');
      expect(anonymousAdapter.requests.last.header('X-API-Key'), 'key-a');

      // Scenario 2: a key change after dispatch cannot split the identity —
      // the request is sent with the key its cache/dedupe scope belongs to.
      final replacedAdapter = FakeWallhavenAdapter([
        (_, _) async => _page('A'),
        (_, _) async => _page('B'),
      ]);
      final replacedManager = ApiKeyManager(initialApiKey: 'key-a');
      final replacedClient = buildTestClient(
        adapter: replacedAdapter,
        apiKeyManager: replacedManager,
      );
      addTearDown(replacedClient.close);

      final pendingA = replacedClient.search(request);
      replacedManager.setApiKey('key-b');
      expect((await pendingA).items.single.id, 'A');
      expect(replacedAdapter.requests.single.header('X-API-Key'), 'key-a');

      // Key B is an independent identity with its own fetch and cache entry.
      expect((await replacedClient.search(request)).items.single.id, 'B');
      expect(replacedAdapter.requests.last.header('X-API-Key'), 'key-b');
      expect((await replacedClient.search(request)).items.single.id, 'B');
      expect(replacedAdapter.callCount, 2);
    });
  });

  group('policy queries stay cache-distinct', () {
    test('SFW and all-purity searches use separate cached responses', () async {
      final adapter = FakeWallhavenAdapter([
        (options, _) async => _page(
          options.uri.queryParameters['purity'] == '111'
              ? 'all-purities'
              : 'sfw-only',
        ),
      ]);
      final client = buildTestClient(
        adapter: adapter,
        apiKeyManager: ApiKeyManager(initialApiKey: 'key-a'),
      );
      addTearDown(client.close);

      final sfw = await client.search(WallhavenSearchRequest());
      final all = await client.search(
        WallhavenSearchRequest(purity: WallhavenPurity.values.toSet()),
      );

      expect(sfw.items.single.id, 'sfw-only');
      expect(all.items.single.id, 'all-purities');
      expect(adapter.callCount, 2);
      expect(adapter.requests[0].uri.queryParameters['purity'], '100');
      expect(adapter.requests[1].uri.queryParameters['purity'], '111');
    });
  });

  group('credential logging', () {
    test('a replaced credential is never printed by request logging', () async {
      final lines = <String>[];
      final manager = ApiKeyManager(initialApiKey: 'secret-key-a');
      final store = InMemoryCacheStore();
      final config = const WallhavenConfig(enableLogging: true);
      final dio = buildDio(config, apiKeyManager: manager, cacheStore: store);
      final adapter = FakeWallhavenAdapter([
        (_, _) async => _page('A'),
        (_, _) async => _page('B'),
      ]);
      dio.httpClientAdapter = adapter;
      final client = WallhavenClient(
        apiKeyManager: manager,
        config: config,
        dio: dio,
        cache: store,
      );
      addTearDown(client.close);

      await runZoned<Future<void>>(
        () async {
          final pendingA = client.search(request);
          manager.setApiKey('secret-key-b');
          await pendingA;
          final pendingB = client.search(WallhavenSearchRequest(query: 'next'));
          manager.setApiKey(null);
          await pendingB;
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );

      final log = lines.join('\n');
      expect(log, isNot(contains('secret-key-a')));
      expect(log, isNot(contains('secret-key-b')));
    });
  });

  group('cache keys stay secret-free', () {
    test('neither key material nor query swapping leaks into cache keys',
        () async {
      final store = RecordingCacheStore();
      final manager = ApiKeyManager(initialApiKey: 'super-secret-key');
      final adapter = FakeWallhavenAdapter([
        (_, _) async => _page('A'),
        (_, _) async => _page('B'),
      ]);
      final dio = buildDio(
        const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        apiKeyManager: manager,
        cacheStore: store,
      )..httpClientAdapter = adapter;
      final client = WallhavenClient(
        apiKeyManager: manager,
        config: const WallhavenConfig(baseUrl: 'https://unit.test/api/v1'),
        dio: dio,
        cache: store,
      );
      addTearDown(client.close);

      await client.search(request);
      manager.setApiKey('second-secret-key');
      await client.search(request);

      expect(
        store.keys,
        hasLength(2),
        reason: 'each identity generation needs its own cache entry',
      );
      for (final key in store.keys) {
        expect(key, isNot(contains('super-secret-key')));
        expect(key, isNot(contains('second-secret-key')));
      }
    });
  });
}

ResponseBody _page(String id) => ResponseBody.fromString(
  jsonEncode(<String, dynamic>{
    'data': <dynamic>[
      <String, dynamic>{
        'id': id,
        'url': 'https://wallhaven.cc/w/$id',
        'purity': 'sfw',
        'category': 'general',
      },
    ],
    'meta': <String, dynamic>{
      'current_page': 1,
      'last_page': 1,
      'per_page': 24,
    },
  }),
  200,
  headers: <String, List<String>>{
    'content-type': <String>['application/json'],
  },
);

Future<ResponseBody> _json(Map<String, dynamic> body) async =>
    ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        'content-type': <String>['application/json'],
      },
    );

ResponseBody _collections(List<String> labels) => ResponseBody.fromString(
  jsonEncode(<String, dynamic>{
    'data': <dynamic>[
      for (final label in labels) <String, dynamic>{'id': 1, 'label': label},
    ],
  }),
  200,
  headers: <String, List<String>>{
    'content-type': <String>['application/json'],
  },
);

/// Polls until [adapter] has served [count] requests, failing fast instead of
/// hanging when a regression parks a request on another identity's future.
Future<void> _waitForCalls(FakeWallhavenAdapter adapter, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (adapter.callCount < count) {
    if (DateTime.now().isAfter(deadline)) {
      fail('expected $count adapter calls, saw ${adapter.callCount}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Cache store that records the exact keys the transport used.
final class RecordingCacheStore implements CacheStore {
  final InMemoryCacheStore _inner = InMemoryCacheStore();
  final List<String> keys = <String>[];
  final List<String> removed = <String>[];

  @override
  Future<CacheEntry?> get(String key, {required DateTime now}) =>
      _inner.get(key, now: now);

  @override
  Future<void> put(String key, CacheEntry entry) {
    keys.add(key);
    return _inner.put(key, entry);
  }

  @override
  Future<void> remove(String key) {
    removed.add(key);
    return _inner.remove(key);
  }

  @override
  Future<void> clear() => _inner.clear();
}
