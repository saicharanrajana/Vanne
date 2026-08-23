import 'dart:collection';
import 'package:dio/dio.dart';

/// Client-side request throttling to stay under Wallhaven's documented
/// limit of 45 requests/minute.
///
/// Implements a sliding window over the trailing 60 seconds. When the
/// window is full, [onRequest] awaits (without blocking other isolates)
/// until the oldest recorded request exits the window.
///
/// [clock] and [delay] are injectable so tests can simulate time without
/// sleeping; production defaults use the real clock and `Future.delayed`.
final class RateLimitInterceptor extends Interceptor {
  /// Maximum requests allowed inside the sliding window.
  final int maxRequestsPerMinute;

  /// Returns the current instant. Injectable for deterministic tests.
  final DateTime Function() clock;

  /// Suspends execution for [duration]. Injectable for deterministic tests.
  final Future<void> Function(Duration duration) delay;

  /// Window length used by the limiter.
  static const Duration _window = Duration(minutes: 1);

  // Newest last; we only touch both ends, so a plain list suffices.
  final Queue<DateTime> _sentAt = Queue<DateTime>();

  RateLimitInterceptor({
    required this.maxRequestsPerMinute,
    DateTime Function()? clock,
    Future<void> Function(Duration duration)? delay,
  })  : clock = clock ?? DateTime.now,
        delay = delay ??
            ((duration) => Future<void>.delayed(duration));

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      while (_sentAt.length >= maxRequestsPerMinute) {
        final oldest = _sentAt.first;
        final elapsed = clock().difference(oldest);
        if (elapsed >= _window) {
          // Oldest entry has aged out of the window; drop it and re-check.
          _sentAt.removeFirst();
          continue;
        }
        await delay(_window - elapsed);
      }
      final now = clock();
      // Purge aged-out entries so the queue does not grow unbounded.
      while (_sentAt.isNotEmpty && now.difference(_sentAt.first) >= _window) {
        _sentAt.removeFirst();
      }
      _sentAt.addLast(now);
      handler.next(options);
    } catch (error, stackTrace) {
      // Deliberately NOT `requestCancelled`: cancellation means *the caller*
      // aborted, whereas a limiter failure is an internal error and must
      // surface as a network-type exception after error mapping.
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: 'Rate limiter failed: $error',
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
