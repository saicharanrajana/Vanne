import 'dart:async';

import 'package:dio/dio.dart';

/// Collapses concurrent identical GET requests into a single in-flight
/// network call.
///
/// Waiters share the same [Future]; on completion (success or failure) the
/// shared future is removed, so later requests start fresh. This prevents
/// duplicate simultaneous requests when widgets rebuild while a fetch is
/// still running — without ever caching stale results.
///
/// Known trade-off: waiters share one [CancelToken]-less future, so if any
/// caller cancels its token, every waiter on the same key fails with a
/// cancellation — including callers that never cancelled. Acceptable here
/// because deduped callers are always the same logical fetch within one
/// screen; callers needing independent cancellation should not share keys.
final class RequestDeduper {
  final Map<String, Future<Response<dynamic>>> _inFlight = {};

  /// Returns an existing future for [key] or registers [start] as the new
  /// in-flight request.
  Future<Response<dynamic>> run(
    String key,
    Future<Response<dynamic>> Function() start,
  ) {
    final existing = _inFlight[key];
    if (existing != null) return existing;
    // `whenComplete` guarantees removal whether the request succeeds,
    // fails, or is cancelled.
    //
    // Block body deliberately: an arrow (`=> _inFlight.remove(key)`)
    // would RETURN the removed future, so whenComplete would await the
    // very future it wraps — a self-deadlock on every request.
    final future = start().whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }
}
