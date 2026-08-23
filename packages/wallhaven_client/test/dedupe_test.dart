import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

void main() {
  test('concurrent identical GETs produce one adapter call', () async {
    final adapter = FakeWallhavenAdapter([FakeHandlers.ok]);
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    // Same request fired twice without awaiting the first — e.g. two
    // widgets rebuilding while a fetch is in flight.
    final results = await Future.wait([
      client.search(WallhavenSearchRequest(query: 'dup')),
      client.search(WallhavenSearchRequest(query: 'dup')),
    ]);

    expect(results, hasLength(2));
    expect(adapter.callCount, 1,
        reason: 'the second identical GET must share the in-flight future');
    expect(results[0].items.length, results[1].items.length);
  });

  test('failures propagate to all waiters and clear the slot', () async {
    var calls = 0;
    final adapter = FakeWallhavenAdapter([
      (_, _) async {
        calls++;
        return ResponseBody.fromString('{"error":"boom"}', 500);
      },
      (_, _) async {
        calls++;
        return ResponseBody.fromString(
          jsonEncode(fixture('search_response.json')),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      },
    ]);
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    final first = client.search(WallhavenSearchRequest(query: 'flaky'));
    final second = client.search(WallhavenSearchRequest(query: 'flaky'));
    await expectLater(first, throwsA(isA<WallhavenServerException>()));
    await expectLater(second, throwsA(isA<WallhavenServerException>()));

    // After failure the deduper must NOT cache errors: a fresh call
    // reaches the network again and succeeds.
    final third = await client.search(WallhavenSearchRequest(query: 'flaky'));
    expect(third.items, hasLength(2));
    // First pair shares one failed call (dedup), retry adds the second.
    expect(calls, 2,
        reason: 'two shared failed calls + one successful retry');
  });
}
