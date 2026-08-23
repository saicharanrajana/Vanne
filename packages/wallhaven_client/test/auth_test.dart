import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

void main() {
  test('no API key → no authentication header', () async {
    final adapter = FakeWallhavenAdapter.json(fixture('search_response.json'));
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    await client.search(WallhavenSearchRequest());
    expect(adapter.lastRequest.hasHeader('X-API-Key'), isFalse);
    expect(client.authState, isA<Unauthenticated>());
  });

  test('API key → correct X-API-Key header and authenticated state', () async {
    final adapter = FakeWallhavenAdapter.json(fixture('search_response.json'));
    final manager = ApiKeyManager();
    final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
    addTearDown(client.close);

    manager.setApiKey('test-key-123');
    expect(client.authState, isA<Authenticated>());

    await client.search(WallhavenSearchRequest());
    expect(adapter.lastRequest.header('X-API-Key'), 'test-key-123');
  });

  test('replacing the key is reflected on the next request', () async {
    // Two canned responses; distinct queries avoid the response cache
    // answering the second call.
    final adapter = FakeWallhavenAdapter([FakeHandlers.ok, FakeHandlers.ok]);
    final manager = ApiKeyManager();
    final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
    addTearDown(client.close);

    manager.setApiKey('first-key');
    await client.search(WallhavenSearchRequest());
    manager.setApiKey('second-key');
    await client.search(WallhavenSearchRequest(query: 'x'));

    expect(adapter.requests[0].header('X-API-Key'), 'first-key');
    expect(adapter.requests[1].header('X-API-Key'), 'second-key');
  });

  test('removing the key drops the header again', () async {
    final adapter = FakeWallhavenAdapter([FakeHandlers.ok, FakeHandlers.ok]);
    final manager = ApiKeyManager();
    final client = buildTestClient(adapter: adapter, apiKeyManager: manager);
    addTearDown(client.close);

    manager.setApiKey('temp-key');
    manager.setApiKey(null);
    expect(client.authState, isA<Unauthenticated>());

    await client.search(WallhavenSearchRequest());
    expect(adapter.lastRequest.hasHeader('X-API-Key'), isFalse);
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
