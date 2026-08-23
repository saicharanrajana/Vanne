/// Typed exception hierarchy for the Wallhaven API client.
///
/// Every public client method throws only [WallhavenException] subtypes.
/// Exception messages never contain API keys or other secrets.
library;

/// Which phase of a request timed out.
enum TimeoutKind { connect, send, receive }

/// Base class of all errors surfaced by the Wallhaven client.
sealed class WallhavenException implements Exception {
  /// Human-readable description. Never contains secrets.
  final String message;

  /// Request URI, when known. Never contains the API key (auth travels in a
  /// header, not the URL).
  final Uri? uri;

  const WallhavenException(this.message, {this.uri});

  @override
  String toString() => '$runtimeType: $message';
}

/// Connection failure (DNS resolution, socket error, connection refused).
final class WallhavenNetworkException extends WallhavenException {
  const WallhavenNetworkException(super.message, {super.uri});
}

/// A request phase exceeded its configured timeout.
final class WallhavenTimeoutException extends WallhavenException {
  final TimeoutKind kind;

  const WallhavenTimeoutException(
    super.message, {
    required this.kind,
    super.uri,
  });
}

/// The request was cancelled via [CancelToken] before completing.
final class WallhavenCancelledException extends WallhavenException {
  const WallhavenCancelledException(super.message, {super.uri});
}

/// The server replied with an unexpected shape or unexpected status code.
final class WallhavenInvalidResponseException extends WallhavenException {
  final int? statusCode;

  const WallhavenInvalidResponseException(
    super.message, {
    this.statusCode,
    super.uri,
  });
}

/// The response body was not decodable JSON or had an unexpected JSON shape.
final class WallhavenMalformedJsonException extends WallhavenException {
  const WallhavenMalformedJsonException(super.message, {super.uri});
}

/// HTTP 400 — malformed request parameters.
final class WallhavenBadRequestException extends WallhavenException {
  const WallhavenBadRequestException(super.message, {super.uri});
}

/// HTTP 401 — invalid API key, or NSFW access attempted without one.
final class WallhavenUnauthorizedException extends WallhavenException {
  const WallhavenUnauthorizedException(super.message, {super.uri});
}

/// NSFW content was requested without an API key. Thrown before the
/// request is sent when detectable from the request itself, and used by the
/// error mapper for 401 responses to unauthenticated NSFW fetches.
final class NsfwAuthenticationRequiredException
    extends WallhavenUnauthorizedException {
  const NsfwAuthenticationRequiredException({
    String message =
        'NSFW content requires an API key. Configure one in settings to '
        'enable NSFW results.',
  }) : super(message);
}

final class AuthenticationRequiredException extends WallhavenException {
  const AuthenticationRequiredException({
    String message = 'This operation requires an API key.',
    super.uri,
  }) : super(message);
}

/// HTTP 403 — access denied.
final class WallhavenForbiddenException extends WallhavenException {
  const WallhavenForbiddenException(super.message, {super.uri});
}

/// HTTP 404 — unknown wallpaper id, tag id, username, or collection id.
final class WallhavenNotFoundException extends WallhavenException {
  const WallhavenNotFoundException(super.message, {super.uri});
}

/// HTTP 429 — the documented rate limit (45 requests/minute) was exceeded by
/// the server. [retryAfter] is parsed from the `Retry-After` header when the
/// server supplies it; otherwise `null` and callers should back off
/// conservatively (the client default window is one minute).
final class WallhavenRateLimitExceededException extends WallhavenException {
  final Duration? retryAfter;

  const WallhavenRateLimitExceededException(
    super.message, {
    this.retryAfter,
    super.uri,
  });
}

/// HTTP 5xx — Wallhaven server-side failure.
final class WallhavenServerException extends WallhavenException {
  final int statusCode;

  const WallhavenServerException(super.message, {required this.statusCode, super.uri});
}
