import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
// White-box import: tests construct the transport exactly like production.
import 'package:wallhaven_client/src/http/dio_factory.dart';

/// Loads a JSON fixture from `test/fixtures/`.
Map<String, dynamic> fixture(String name) {
  final raw = _fixtureCache.putIfAbsent(
    name,
    // Tests run with CWD at the package root.
    () => File('test/fixtures/$name').readAsStringSync(),
  );
  return jsonDecode(raw) as Map<String, dynamic>;
}

final _fixtureCache = <String, String>{};

/// A recorded request captured by [FakeWallhavenAdapter].
final class RecordedRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;

  const RecordedRequest(this.method, this.uri, this.headers);

  bool hasHeader(String name) => headers.containsKey(name.toLowerCase());

  String? header(String name) => headers[name.toLowerCase()];
}

typedef AdapterHandler =
    Future<ResponseBody> Function(RequestOptions options, int callIndex);

/// Deterministic in-memory [HttpClientAdapter] for driving the real Dio
/// interceptor chain without any network.
final class FakeWallhavenAdapter implements HttpClientAdapter {
  final List<RecordedRequest> requests = [];
  final List<AdapterHandler> _handlers;

  /// Responses are consumed from [handlers] in order; the last repeats.
  FakeWallhavenAdapter(List<AdapterHandler> handlers) : _handlers = handlers;

  /// Convenience for a single JSON response.
  factory FakeWallhavenAdapter.json(
    Map<String, dynamic> body, {
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) {
    return FakeWallhavenAdapter([
      (_, _) async => ResponseBody.fromString(
            jsonEncode(body),
            status,
            headers: <String, List<String>>{
              'content-type': ['application/json'],
              ...headers,
            },
          ),
    ]);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final index = requests.length;
    requests.add(
      RecordedRequest(
        options.method,
        options.uri,
        options.headers.cast<String, String>(),
      ),
    );
    if (_handlers.isEmpty) throw StateError('No fake response queued.');
    final handler =
        _handlers[index < _handlers.length ? index : _handlers.length - 1];
    return handler(options, index);
  }

  @override
  void close({bool force = false}) {}

  RecordedRequest get lastRequest => requests.last;

  int get callCount => requests.length;
}

/// Mutable fake clock: tests advance time by writing [now].
final class MutableClock {
  DateTime now;
  MutableClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 1, 1);
}

/// Builds a client wired to [adapter] with injectable clock/delay so no
/// test ever sleeps or depends on wall-clock time.
///
/// The same [apiKeyManager] instance is wired both into the client and its
/// Dio interceptors — matching production construction via `buildDio`.
WallhavenClient buildTestClient({
  required FakeWallhavenAdapter adapter,
  ApiKeyManager? apiKeyManager,
  MutableClock? clock,
  List<Duration> delays = const [],
}) {
  final manager = apiKeyManager ?? ApiKeyManager();
  final effectiveClock = clock ?? MutableClock();
  final delaySink = delays.isEmpty ? null : delays;
  var delayIndex = 0;
  final dio = buildDio(
    const WallhavenConfig(),
    apiKeyManager: manager,
    cacheStore: InMemoryCacheStore(),
    clock: () => effectiveClock.now,
    delay: (d) async {
      // Record requested backoff durations; never actually sleep.
      if (delaySink != null && delayIndex < delaySink.length) {
        delaySink[delayIndex] = d;
        delayIndex++;
      }
    },
  );
  // Route ALL traffic through the fake adapter — without this line,
  // requests would escape to the real network.
  dio.httpClientAdapter = adapter;
  return WallhavenClient(
    apiKeyManager: manager,
    config: const WallhavenConfig(),
    dio: dio,
    clock: () => effectiveClock.now,
  );
}

/// Shared canned handlers for multi-request tests.
class FakeHandlers {
  /// A minimal successful empty listing body.
  static const _okBody = '{"data": [], "meta": {"current_page": 1, '
      '"last_page": 0, "per_page": 24}}';

  static Future<ResponseBody> ok(RequestOptions options, int callIndex) async =>
      ResponseBody.fromString(
        _okBody,
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );

  /// Empty listing sitting on its last page.
  static Future<ResponseBody> okLastPage(
          RequestOptions options, int callIndex) async =>
      ResponseBody.fromString(
        '{"data": [], "meta": {"current_page": 5, "last_page": 5, '
        '"per_page": 24}}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
}
