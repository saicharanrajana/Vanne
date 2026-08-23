import 'package:dio/dio.dart';

import '../../config/wallhaven_config.dart';
import 'cache_store.dart';

/// Option key on `Options.extra` to bypass the cache for a single request:
/// `options: Options(extra: {CacheInterceptor.optOutExtra: true})`.
final class CacheInterceptor extends Interceptor {
  /// Extra key disabling caching for one request.
  static const String optOutExtra = 'wallhaven_cache';

  final CacheStore store;
  final WallhavenConfig config;

  /// Returns "now" — injectable so tests can advance past the TTL.
  final DateTime Function() clock;

  CacheInterceptor({
    required this.store,
    required this.config,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Builds the normalized cache key for a request.
  ///
  /// Key = `GET <path>?<sorted encoded query>` — sorted so that parameter
  /// order never splits cache entries. The API key never participates: it
  /// travels in a header (see [ApiKeyInterceptor]), not the URL.
  String cacheKey(RequestOptions options) =>
      '${options.method} ${options.path}?${normalizedQuery(options.queryParameters)}';

  /// Canonical form of a query map: keys sorted, every key and value
  /// percent-encoded so semantically different queries never collide
  /// (`a=1&b` vs `a=1%26b`) and order never matters.
  static String normalizedQuery(Map<String, Object?> query) {
    final pairs = query.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return pairs
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent('${e.value}')}')
        .join('&');
  }

  bool _isCacheable(RequestOptions options) =>
      options.method.toUpperCase() == 'GET' &&
      options.extra[optOutExtra] != true;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isCacheable(options)) {
      handler.next(options);
      return;
    }
    try {
      final entry = await store.get(cacheKey(options), now: clock());
      if (entry != null) {
        // Serve from cache without hitting the network at all.
        handler.resolve(
          Response<dynamic>(
            data: entry.json,
            statusCode: entry.statusCode,
            requestOptions: options,
          ),
        );
        return;
      }
    } catch (_) {
      // A broken cache must never break requests; fall through to network.
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    if (_isCacheable(options) && response.statusCode == 200) {
      try {
        store.put(
          cacheKey(options),
          CacheEntry(
            statusCode: response.statusCode ?? 200,
            json: response.data,
            expiresAt: clock().add(config.cacheTtl),
          ),
        );
      } catch (_) {
        // Caching is best-effort; ignore store failures.
      }
    }
    handler.next(response);
  }
}
