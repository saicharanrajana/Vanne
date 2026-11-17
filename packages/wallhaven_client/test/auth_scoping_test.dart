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
    test(
      'same key keeps the cache; a replaced key fetches its own payload',
      () async {
        final adapter = FakeWallhavenAdapter([
          (_, _) async => _page('A'),
          (_, _) async => _page('B'),
        ]);
        final manager = ApiKeyManager(initialApiKey: 'key-a');
        final client = buildTestClient(
          adapter: adapter,
          apiKeyManager: manager,
        );
        addTearDown(client.close);

        final first = await client.search(request);
        expect(first.items.single.id, 'A');

        // Re-setting the identical key is not an authentication change.
        manager.setApiKey('key-a');
        final cached = await client.search(request);
        expect(cached.items.single.id, 'A');
        expect(
          adapter.callCount,
          1,
          reason: 'the same identity must keep reusing its cached response',
        );

        manager.setApiKey('key-b');
        final second = await client.search(request);
        expect(
          second.items.single.id,
          'B',
          reason: 'key B must never be served key A\'s cached payload',
        );
        expect(adapter.callCount, 2);
        expect(adapter.requests.last.header('X-API-Key'), 'key-b');
      },
    );

    test(
      'removing the key does not serve the previous key\'s cached payload',
      () async {
        final adapter = FakeWallhavenAdapter([
          (_, _) async => _page('signed-in'),
          (_, _) async => _page('anonymous'),
        ]);
        final manager = ApiKeyManager(initialApiKey: 'key-a');
        final client = buildTestClient(
          adapter: adapter,
          apiKeyManager: manager,
        );
        addTearDown(client.close);

        await client.search(request);
        manager.setApiKey(null);

        final anonymous = await client.search(request);
        expect(anonymous.items.single.id, 'anonymous');
        expect(adapter.callCount, 2);
        expect(adapter.requests.last.hasHeader('X-API-Key'), isFalse);
      },
    );

    test('re-adding the same key after removal starts a fresh fetch', () async {
      final adapter = FakeWallhavenAdapter([
        (_, _) async => _page('first-session'),
        (_, _) async => _page('second-session'),
      ]);
      final manager = ApiKeyManager(initialApiKey: 'key-a');
      final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
      addTearDown(client.close);

      await client.search(request);
      manager.setApiKey(null);
      manager.setApiKey('key-a');

      // Conservative by design: a removed-and-restored credential is a new
      // identity generation, so nothing from the earlier session is reused.
      final page = await client.search(request);
      expect(page.items.single.id, 'second-session');
      expect(adapter.callCount, 2);

      // ...and that fresh response is then cached for the new generation.
      await client.search(request);
      expect(adapter.callCount, 2);
    });
  });

  group('in-flight deduplication across API keys', () {
    test(
      'a key change does not join the previous key\'s in-flight request',
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
        final client = buildTestClient(
          adapter: adapter,
          apiKeyManager: manager,
        );
        addTearDown(client.close);

        final firstKeyCall = client.search(request);
        await started.future;

        manager.setApiKey('key-b');
        final secondKeyCall = client.search(request);
        // Bounded wait instead of awaiting the call directly: a regression
        // here means key B is parked on key A's future, which would otherwise
        // surface as an opaque 30 s test timeout.
        await _waitForCalls(adapter, 2);
        final secondKeyResult = await secondKeyCall;
        expect(
          secondKeyResult.items.single.id,
          'B',
          reason: 'key B must issue its own request, not await key A\'s',
        );
        expect(adapter.requests.last.header('X-API-Key'), 'key-b');

        release.complete();
        final firstKeyResult = await firstKeyCall;
        expect(firstKeyResult.items.single.id, 'A');
      },
    );

    test(
      'a late response from the previous key never lands in the new cache',
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
        final client = buildTestClient(
          adapter: adapter,
          apiKeyManager: manager,
        );
        addTearDown(client.close);

        final held = client.search(request);
        await started.future;

        manager.setApiKey('key-b');
        release.complete();

        // Key A's response completes only after key B is active. It must be
        // cached (if at all) under key A's identity, never key B's.
        expect((await held).items.single.id, 'A');

        final bPage = await client.search(request);
        expect(bPage.items.single.id, 'B');
        expect(adapter.callCount, 2);

        // Key B's own response is what subsequent reads see.
        final bCached = await client.search(request);
        expect(bCached.items.single.id, 'B');
        expect(adapter.callCount, 2);
      },
    );
  });

  group('account-specific endpoints', () {
    test('settings are never shared between two accounts', () async {
      final adapter = FakeWallhavenAdapter([
        (_, _) async => _json(<String, dynamic>{
          'data': <String, dynamic>{'per_page': 24, 'toplist_range': 'A'},
        }),
        (_, _) async => _json(<String, dynamic>{
          'data': <String, dynamic>{'per_page': 48, 'toplist_range': 'B'},
        }),
      ]);
      final manager = ApiKeyManager(initialApiKey: 'key-a');
      final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
      addTearDown(client.close);

      expect((await client.settings()).toplistRange, 'A');
      manager.setApiKey('key-b');
      expect(
        (await client.settings()).toplistRange,
        'B',
        reason: 'the second account must not read the first one\'s settings',
      );
      expect(adapter.callCount, 2);
    });

    test('own (possibly private) collections are never shared', () async {
      final adapter = FakeWallhavenAdapter([
        (_, _) async => _collections(['private-of-A']),
        (_, _) async => _collections(['private-of-B']),
      ]);
      final manager = ApiKeyManager(initialApiKey: 'key-a');
      final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
      addTearDown(client.close);

      expect((await client.collections()).single.label, 'private-of-A');
      manager.setApiKey('key-b');
      expect((await client.collections()).single.label, 'private-of-B');
      expect(adapter.callCount, 2);
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

  group('credential captured at dispatch', () {
    test(
      'direct Dio requests still use the live manager when unpinned',
      () async {
        final manager = ApiKeyManager(initialApiKey: 'direct-key');
        final store = InMemoryCacheStore();
        final config = const WallhavenConfig();
        final dio = buildDio(config, apiKeyManager: manager, cacheStore: store);
        final adapter = FakeWallhavenAdapter([(_, _) async => _page('direct')]);
        dio.httpClientAdapter = adapter;
        addTearDown(dio.close);

        await dio.getUri(Uri.parse('${config.baseUrl}/search'));

        expect(adapter.requests.single.header('X-API-Key'), 'direct-key');
      },
    );

    test(
      'anonymous dispatch remains anonymous if a key is set before interceptors',
      () async {
        final adapter = FakeWallhavenAdapter([
          (_, _) async => _page('anonymous'),
          (_, _) async => _page('signed-in'),
        ]);
        final manager = ApiKeyManager();
        final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
        addTearDown(client.close);

        final pending = client.search(request);
        manager.setApiKey('key-a');
        final page = await pending;

        expect(page.items.single.id, 'anonymous');
        expect(adapter.requests.single.hasHeader('X-API-Key'), isFalse);
        expect((await client.search(request)).items.single.id, 'signed-in');
        expect(adapter.callCount, 2,
            reason: 'the signed-in request must not join/cache under anonymous');
        expect(adapter.requests.last.header('X-API-Key'), 'key-a');
      },
    );

    test(
      'a key change before the interceptors run cannot split the identity',
      () async {
        final adapter = FakeWallhavenAdapter([
          (_, _) async => _page('A'),
          (_, _) async => _page('B'),
        ]);
        final manager = ApiKeyManager(initialApiKey: 'key-a');
        final client = buildTestClient(
          adapter: adapter,
          apiKeyManager: manager,
        );
        addTearDown(client.close);

        final pending = client.search(request);
        // Changed after dispatch but before dio's interceptor chain runs. The
        // request already belongs to key A's cache/dedupe scope, so it must be
        // sent with key A — otherwise A's scope would hold key B's payload.
        manager.setApiKey('key-b');

        final page = await pending;
        expect(page.items.single.id, 'A');
        expect(adapter.requests.single.header('X-API-Key'), 'key-a');

        // Key B is an independent identity with its own fetch and its own
        // cache entry; a repeat read is served from that entry.
        expect((await client.search(request)).items.single.id, 'B');
        expect(adapter.requests.last.header('X-API-Key'), 'key-b');
        expect((await client.search(request)).items.single.id, 'B');
        expect(adapter.callCount, 2);
      },
    );
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
    test(
      'neither key material nor query swapping leaks into cache keys',
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
      },
    );
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
