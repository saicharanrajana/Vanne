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

  test('400 → WallhavenBadRequestException', () async {
    final error = await capture(FakeWallhavenAdapter([(_, _) async => status(400)]));
    expect(error, isA<WallhavenBadRequestException>());
  });

  test('401 → WallhavenUnauthorizedException', () async {
    final error = await capture(FakeWallhavenAdapter([(_, _) async => status(401)]));
    expect(error, isA<WallhavenUnauthorizedException>());
    expect(error, isNot(isA<NsfwAuthenticationRequiredException>()));
  });

  test('403 → WallhavenForbiddenException', () async {
    final error = await capture(FakeWallhavenAdapter([(_, _) async => status(403)]));
    expect(error, isA<WallhavenForbiddenException>());
  });

  test('404 → WallhavenNotFoundException', () async {
    final error = await capture(FakeWallhavenAdapter([(_, _) async => status(404)]));
    expect(error, isA<WallhavenNotFoundException>());
  });

  test('500 → WallhavenServerException with status code', () async {
    final error = await capture(FakeWallhavenAdapter([(_, _) async => status(503)]));
    final server = error;
    expect(server, isA<WallhavenServerException>());
    expect((server as WallhavenServerException).statusCode, 503);
  });

  test('429 → WallhavenRateLimitExceededException', () async {
    final error = await capture(
      FakeWallhavenAdapter([
        (_, _) async => status(
              429,
              headers: {
                'retry-after': ['15'],
              },
            ),
      ]),
    );
    final rate = error;
    expect(rate, isA<WallhavenRateLimitExceededException>());
    expect(
      (rate as WallhavenRateLimitExceededException).retryAfter,
      const Duration(seconds: 15),
    );
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

  test('cancellation → WallhavenCancelledException', () async {
    final token = CancelToken();
    final adapter = FakeWallhavenAdapter([
      (_, _) async => throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: '/search'),
            reason: 'user cancelled',
          ),
    ]);
    final client = buildTestClient(adapter: adapter);
    addTearDown(client.close);

    await expectLater(
      client.search(WallhavenSearchRequest(), cancelToken: token),
      throwsA(isA<WallhavenCancelledException>()),
    );
  });
}

