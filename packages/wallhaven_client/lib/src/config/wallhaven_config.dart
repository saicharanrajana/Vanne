/// Immutable client configuration.
final class WallhavenConfig {
  /// Wallhaven API v1 base URL.
  final String baseUrl;

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;

  /// Documented server limit is 45 requests/minute; the client throttles
  /// itself to this rate.
  final int requestsPerMinute;

  /// Enables dio request/response logging (with the API key redacted).
  /// Never enable in release builds.
  final bool enableLogging;

  /// Default TTL for the in-memory response cache.
  final Duration cacheTtl;

  const WallhavenConfig({
    this.baseUrl = 'https://wallhaven.cc/api/v1',
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 15),
    this.requestsPerMinute = 45,
    this.enableLogging = false,
    this.cacheTtl = const Duration(minutes: 5),
  });
}
