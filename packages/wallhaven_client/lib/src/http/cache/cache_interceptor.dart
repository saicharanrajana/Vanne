import 'package:dio/dio.dart';

import '../../config/wallhaven_config.dart';
import 'cache_store.dart';

/// Option key on `Options.extra` to bypass the cache for a single request:
/// `options: Options(extra: {CacheInterceptor.optOutExtra: true})`.
final class CacheInterceptor extends Interceptor {
  /// Extra key disabling caching for one request.
  static const String optOutExtra = 'wallhaven_cache';

  /// Extra key holding the authentication scope captured when the request
  /// entered the chain. It is read back when the response arrives, so a late
  /// reply is filed under the identity that produced it.
  static const String authScopeExtra = 'wallhaven_auth_scope';

  final CacheStore store;
  final WallhavenConfig config;

  /// Returns "now" — injectable so tests can advance past the TTL.
  final DateTime Function() clock;

  /// Returns the opaque identity token of the current credential (see
  /// `ApiKeyManager.authScope`). Responses are cached per token, so two
  /// accounts sharing an endpoint never see each other's payloads.
  final String Function()? authScope;

  CacheInterceptor({
    required this.store,
    required this.config,
    DateTime Function()? clock,
    this.authScope,
  }) : clock = clock ?? DateTime.now;

  /// Scope used when no [authScope] provider is wired (a bare interceptor in
  /// a unit test).
  static const String _unscoped = 'unscoped';

  /// Builds the normalized cache key for a request.
  ///
  /// Key = `<scope> <METHOD> <path>?<sorted encoded query>` — sorted so that
  /// parameter order never splits cache entries. The API key never
  /// participates: it travels in a header (see `ApiKeyInterceptor`), and the
  /// scope is an opaque generation token rather than the key itself.
  String cacheKey(RequestOptions options) {
    _scopeOf(options);
    return keyFor(options);
  }

  /// The cache key for an already-scoped request.
  ///
  /// [discard] keys off it too, so the client can drop exactly the entry the
  /// transport wrote for a response it rejected on validation.
  static String keyFor(RequestOptions options) {
    final scope = options.extra[authScopeExtra];
    return '${scope is String ? scope : _unscoped} ${options.method} '
        '${options.path}?${normalizedQuery(options.queryParameters)}';
  }

  /// Returns — capturing on first use — the auth scope for [options].
  String _scopeOf(RequestOptions options) {
    final captured = options.extra[authScopeExtra];
    if (captured is String) return captured;
    final scope = authScope?.call() ?? _unscoped;
    options.extra[authScopeExtra] = scope;
    return scope;
  }

  /// Drops the cached response for [options], if one exists.
  ///
  /// Called when the client rejects a payload it just received: the transport
  /// caches a `200` before the body is understood, so leaving it in place
  /// would make every retry replay the same unusable response until the TTL
  /// expired. Best-effort — a failing cache must never change the error the
  /// caller sees.
  Future<void> discard(RequestOptions options) async {
    try {
      await store.remove(keyFor(options));
    } catch (_) {
      // Ignored on purpose; see above.
    }
  }

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
    // Capture the identity before the network call, so the matching response
    // is never attributed to a credential that replaced it meanwhile.
    _scopeOf(options);
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
