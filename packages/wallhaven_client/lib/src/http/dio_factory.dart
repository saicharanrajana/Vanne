import 'package:dio/dio.dart';

import '../auth/api_key_manager.dart';
import '../config/wallhaven_config.dart';
import '../auth/api_key_interceptor.dart';
import 'cache/cache_interceptor.dart';
import 'cache/cache_store.dart';
import 'rate_limit_interceptor.dart';

/// Builds the single [Dio] instance used by a [WallhavenClient].
///
/// This is the ONLY place in the package where a Dio instance is
/// constructed, so transport configuration (timeouts, interceptor order)
/// stays auditable. Tests inject their own Dio instead.
///
/// Interceptor order is load-bearing:
/// 1. [ApiKeyInterceptor] — header present before any other logic runs.
/// 2. [CacheInterceptor] — may short-circuit before the rate limiter so a
///    cache hit does not consume rate budget.
/// 3. [RateLimitInterceptor] — gates actual network sends.
/// 4. Logging — added LAST per dio's own guidance, so it observes what
///    earlier interceptors produced (including redaction of the key).
Dio buildDio(
  WallhavenConfig config, {
  required ApiKeyManager apiKeyManager,
  required CacheStore cacheStore,
  DateTime Function()? clock,
  Future<void> Function(Duration)? delay,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.sendTimeout,
      responseType: ResponseType.json,
    ),
  );
  // Decode JSON off the main isolate for every JSON response. Small pages
  // pay a small isolate round-trip, but keeping all decoding off the UI
  // thread guarantees no jank as response sizes grow.
  dio.transformer = FusedTransformer(contentLengthIsolateThreshold: 0);
  dio.interceptors.addAll([
    ApiKeyInterceptor(apiKeyManager),
    CacheInterceptor(
      store: cacheStore,
      config: config,
      clock: clock,
      authScope: () => apiKeyManager.authScope,
    ),
    RateLimitInterceptor(
      maxRequestsPerMinute: config.requestsPerMinute,
      clock: clock,
      delay: delay,
    ),
    if (config.enableLogging) createRedactingLogInterceptor(apiKeyManager),
  ]);
  return dio;
}

/// A `LogInterceptor` that omits request headers, so API-key credentials are
/// never written to debug logs (including a credential pinned before a key
/// rotation).
Interceptor createRedactingLogInterceptor(
  ApiKeyManager apiKeyManager, {
  void Function(String line)? logPrint,
}) {
  void printLine(Object line) => (logPrint ?? defaultPrint)(
    redactApiKey('$line', apiKey: apiKeyManager.apiKey),
  );
  return LogInterceptor(
    requestHeader: false,
    requestBody: true,
    responseBody: false,
    error: true,
    logPrint: printLine,
  );
}

void defaultPrint(String line) {
  // ignore: avoid_print
  print(line);
}
