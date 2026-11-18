import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'helpers.dart';

void main() {
  Future<WallhavenException> capture(FakeWallhavenAdapter adapter) async {
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);
    try {
      await client.search(WallhavenSearchRequest());
    } on WallhavenException catch (error) {
      return error;
    }
    fail('expected a WallhavenException');
  }

  ResponseBody status(int code, {Map<String, List<String>>? headers}) =>
      ResponseBody.fromString(
        jsonEncode({'error': 'boom'}),
        code,
        headers: {
          'content-type': ['application/json'],
          ...?headers,
        },
      );

  test('HTTP statuses map to their typed exception', () async {
    for (final entry in {
      400: isA<WallhavenBadRequestException>(),
      401: isA<WallhavenUnauthorizedException>(),
      403: isA<WallhavenForbiddenException>(),
      404: isA<WallhavenNotFoundException>(),
      429: isA<WallhavenRateLimitExceededException>(),
    }.entries) {
      final error = await capture(
        FakeWallhavenAdapter([(_, _) async => status(entry.key)]),
      );
      expect(error, entry.value, reason: 'status ${entry.key}');
    }

    // 401 from the API is an auth failure, not the local NSFW guard.
    final unauthorized = await capture(
      FakeWallhavenAdapter([(_, _) async => status(401)]),
    );
    expect(unauthorized, isNot(isA<NsfwAuthenticationRequiredException>()));

    // 5xx keeps the upstream status code on the typed exception.
    final server = await capture(
      FakeWallhavenAdapter([(_, _) async => status(503)]),
    );
    expect(server, isA<WallhavenServerException>());
    expect((server as WallhavenServerException).statusCode, 503);
  });

  test('connection error → WallhavenNetworkException', () async {
    final adapter = FakeWallhavenAdapter([
      (_, _) async => throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/search'),
            reason: 'refused',
          ),
    ]);
    final error = await capture(adapter);
    expect(error, isA<WallhavenNetworkException>());
  });

  test('timeouts map to the right TimeoutKind', () async {
    for (final entry in {
      DioExceptionType.connectionTimeout: TimeoutKind.connect,
      DioExceptionType.sendTimeout: TimeoutKind.send,
      DioExceptionType.receiveTimeout: TimeoutKind.receive,
    }.entries) {
      final adapter = FakeWallhavenAdapter([
        (_, _) async => throw DioException(
              requestOptions: RequestOptions(path: '/search'),
              type: entry.key,
            ),
      ]);
      final client = buildTestClient(adapter: adapter);
      addTearDown(client.close);

      await expectLater(
        client.search(WallhavenSearchRequest()),
        throwsA(
          isA<WallhavenTimeoutException>()
              .having((e) => e.kind, 'kind', entry.value),
        ),
      );
    }
  });
}
