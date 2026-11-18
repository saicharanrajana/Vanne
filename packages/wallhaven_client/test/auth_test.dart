import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

void main() {
  test('credential lifecycle drives auth state, headers, and cache identity',
      () async {
    final adapter = FakeWallhavenAdapter([
      // Call order: anonymous, key A, key B, anonymous after removal, key A
      // re-added. The identical-key read between them is served from cache.
      (_, _) async => _searchPage('anonymous-first'),
      (_, _) async => _searchPage('key-a-first'),
      (_, _) async => _searchPage('key-b'),
      (_, _) async => _searchPage('anonymous'),
      (_, _) async => _searchPage('key-a-second-session'),
    ]);
    final manager = ApiKeyManager();
    final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
    addTearDown(client.close);

    // Anonymous: no header, unauthenticated state.
    expect(client.authState, isA<Unauthenticated>());
    await client.search(WallhavenSearchRequest(query: 'a'));
    expect(adapter.lastRequest.hasHeader('X-API-Key'), isFalse);

    // Signed in: header and authenticated state.
    manager.setApiKey('key-a');
    expect(client.authState, isA<Authenticated>());
    await client.search(WallhavenSearchRequest(query: 'a'));
    expect(adapter.lastRequest.header('X-API-Key'), 'key-a');
    expect(adapter.callCount, 2);

    // Re-setting the identical key is not an identity change: cache reuse.
    manager.setApiKey('key-a');
    await client.search(WallhavenSearchRequest(query: 'a'));
    expect(adapter.callCount, 2,
        reason: 'the same key must keep reusing its cached response');

    // Replacing the key fetches the new account's payload.
    manager.setApiKey('key-b');
    final replaced = await client.search(WallhavenSearchRequest(query: 'a'));
    expect(replaced.items.single.id, 'key-b');
    expect(adapter.lastRequest.header('X-API-Key'), 'key-b');

    // Removal drops the header and must not replay key A's cached payload.
    manager.setApiKey(null);
    expect(client.authState, isA<Unauthenticated>());
    final anonymous = await client.search(WallhavenSearchRequest(query: 'a'));
    expect(anonymous.items.single.id, 'anonymous');
    expect(adapter.lastRequest.hasHeader('X-API-Key'), isFalse);

    // Re-adding the same key is a new generation: fresh fetch, then cached.
    manager.setApiKey('key-a');
    final restored = await client.search(WallhavenSearchRequest(query: 'a'));
    expect(restored.items.single.id, 'key-a-second-session');
    await client.search(WallhavenSearchRequest(query: 'a'));
    expect(adapter.callCount, 5);
  });

  test('state changes are broadcast to listeners', () async {
    final manager = ApiKeyManager();
    final states = <AuthenticationState>[];
    final sub = manager.changes.listen(states.add);
    addTearDown(sub.cancel);

    manager.setApiKey('k');
    manager.setApiKey(null);
    await Future<void>.delayed(Duration.zero);

    expect(states, hasLength(2));
    expect(states[0], isA<Authenticated>());
    expect(states[1], isA<Unauthenticated>());
  });
}

ResponseBody _searchPage(String id) => ResponseBody.fromString(
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
