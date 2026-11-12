/// A scripted, offline Wallhaven API.
///
/// The production [WallhavenClient] and [WallpaperRepository] run unchanged;
/// only the HTTP transport is replaced, so request construction, error
/// mapping and DTO parsing are exercised by every journey test.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'fixtures.dart';

/// One `GET /search` the app actually sent.
final class FakeSearchCall {
  const FakeSearchCall(this.uri);

  final Uri uri;

  int get page => int.tryParse(uri.queryParameters['page'] ?? '1') ?? 1;
  String get query => uri.queryParameters['q'] ?? '';
  String get categories => uri.queryParameters['categories'] ?? '';
  String get purity => uri.queryParameters['purity'] ?? '';
  String get sorting => uri.queryParameters['sorting'] ?? '';
  String get topRange => uri.queryParameters['topRange'] ?? '';
  String get minResolution => uri.queryParameters['atleast'] ?? '';
  String get color => uri.queryParameters['colors'] ?? '';
  String get ratios => uri.queryParameters['ratios'] ?? '';
  Set<String> get excludedTags => {
    for (final term in query.split(' '))
      if (term.startsWith('-') && term.length > 1) term.substring(1),
  };

  @override
  String toString() => 'GET ${uri.path}?${uri.query}';
}

/// Raised by scripted handlers to simulate a transport failure.
final class FakeOffline implements Exception {
  const FakeOffline();
}

typedef FakeSearchHandler =
    FutureOr<Map<String, dynamic>> Function(FakeSearchCall call);
typedef FakeDetailHandler =
    FutureOr<Map<String, dynamic>> Function(String id);

/// Fake Wallhaven backend with a default happy path overridable per test.
final class FakeWallhaven {
  FakeWallhaven({bool defaultFeed = true}) {
    if (defaultFeed) {
      searchHandler = (call) async => searchPageJson(
        call.page == 1 ? ['alpha', 'beta'] : const ['gamma'],
        currentPage: call.page,
        lastPage: 1,
      );
    }
    detailHandler = (id) async => wallpaperDetailsJson(id);
  }

  /// Every search request, in arrival order.
  final searches = <FakeSearchCall>[];

  /// Every detail request id, in arrival order.
  final detailIds = <String>[];

  FakeSearchHandler? searchHandler;
  FakeDetailHandler? detailHandler;

  /// Bytes returned for image downloads.
  List<int> imageBytes = _onePixelPng;

  /// The Dio the app's client uses. A [WallhavenClient] built with it skips
  /// the production interceptor chain (rate limit/cache), exactly as the
  /// client documents for injected transports.
  Dio createDio() => Dio(
    BaseOptions(baseUrl: 'https://wallhaven.test/api/v1'),
  )
    ..transformer = SyncTransformer()
    ..httpClientAdapter = _FakeAdapter(this);

  /// Dio used by DownloadService for image bytes.
  Dio createDownloadDio() => Dio(BaseOptions(baseUrl: 'https://images.test'))
    ..httpClientAdapter = _FakeImageAdapter(this);

  Future<ResponseBody> _handleSearch(RequestOptions options) async {
    final call = FakeSearchCall(options.uri);
    searches.add(call);
    final handler = searchHandler;
    if (handler == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'no search handler',
      );
    }
    try {
      final body = await handler(call);
      return _json(body);
    } on DioException {
      rethrow;
    } on FakeOffline {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const FakeOffline(),
      );
    }
  }

  Future<ResponseBody> _handleDetail(RequestOptions options) async {
    final id = options.uri.pathSegments.last;
    detailIds.add(id);
    final handler = detailHandler;
    if (handler == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'no detail handler',
      );
    }
    try {
      final body = await handler(id);
      return _json(body);
    } on DioException {
      rethrow;
    } on FakeOffline {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const FakeOffline(),
      );
    }
  }

  static ResponseBody _json(Map<String, dynamic> body) =>
      ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  static final _onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
}

final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._network);

  final FakeWallhaven _network;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (options.uri.path.endsWith('/search')) {
      return _network._handleSearch(options);
    }
    return _network._handleDetail(options);
  }

  @override
  void close({bool force = false}) {}
}

final class _FakeImageAdapter implements HttpClientAdapter {
  _FakeImageAdapter(this._network);

  final FakeWallhaven _network;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = Uint8List.fromList(_network.imageBytes);
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentLengthHeader: [bytes.length.toString()],
        Headers.contentTypeHeader: ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
