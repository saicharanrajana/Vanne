import 'package:dio/dio.dart';

import '../errors/wallhaven_exception.dart';

/// Maps a [DioException] from the transport layer into the typed
/// [WallhavenException] hierarchy. Malformed JSON is handled by the parsing
/// layer, not here. [clock] makes time-dependent mapping (HTTP-date
/// `Retry-After`) deterministic in tests.
WallhavenException mapDioError(DioException error, {DateTime Function()? clock}) {
  final uri = error.requestOptions.uri;
  switch (error.type) {
    case DioExceptionType.cancel:
      return WallhavenCancelledException('Request cancelled.', uri: uri);
    case DioExceptionType.connectionTimeout:
      return WallhavenTimeoutException(
        'Connection timed out.',
        kind: TimeoutKind.connect,
        uri: uri,
      );
    case DioExceptionType.sendTimeout:
      return WallhavenTimeoutException(
        'Sending the request timed out.',
        kind: TimeoutKind.send,
        uri: uri,
      );
    case DioExceptionType.receiveTimeout:
      return WallhavenTimeoutException(
        'Receiving the response timed out.',
        kind: TimeoutKind.receive,
        uri: uri,
      );
    case DioExceptionType.connectionError:
      return WallhavenNetworkException(
        'Network unavailable: ${error.message ?? 'connection failed'}.',
        uri: uri,
      );
    case DioExceptionType.badCertificate:
      return WallhavenNetworkException(
        'Server certificate validation failed.',
        uri: uri,
      );
    case DioExceptionType.badResponse:
      return _mapBadResponse(error, uri, now: clock?.call().toUtc());
    case DioExceptionType.transformTimeout:
      return WallhavenTimeoutException(
        'Response transformation timed out.',
        kind: TimeoutKind.receive,
        uri: uri,
      );
    case DioExceptionType.unknown:
      // dio wraps arbitrary throwables (socket exceptions, JSON decode
      // errors inside its transformer, etc.) as `unknown`.
      if (error.error is FormatException) {
        return WallhavenMalformedJsonException(
          'Response was not valid JSON.',
          uri: uri,
        );
      }
      return WallhavenNetworkException(
        'Request failed: ${error.message ?? error.error ?? 'unknown error'}.',
        uri: uri,
      );
  }
}

WallhavenException _mapBadResponse(DioException error, Uri uri,
    {DateTime? now}) {
  final status = error.response?.statusCode;
  final message = _serverMessage(error.response) ?? 'HTTP ${status ?? '?'} error.';
  switch (status) {
    case 400:
      return WallhavenBadRequestException(message, uri: uri);
    case 401:
      return WallhavenUnauthorizedException(
        'Unauthorized: the API key is missing or invalid (or NSFW access was '
        'requested without one).',
        uri: uri,
      );
    case 403:
      return WallhavenForbiddenException(message, uri: uri);
    case 404:
      return WallhavenNotFoundException('Not found.', uri: uri);
    case 429:
      return WallhavenRateLimitExceededException(
        'Rate limit exceeded (45 requests/minute).',
        retryAfter: _parseRetryAfter(
          error.response?.headers,
          now: now ?? DateTime.now().toUtc(),
        ),
        uri: uri,
      );
    default:
      if (status != null && status >= 500 && status < 600) {
        return WallhavenServerException(message, statusCode: status, uri: uri);
      }
      return WallhavenInvalidResponseException(
        message,
        statusCode: status,
        uri: uri,
      );
  }
}

String? _serverMessage(Response<dynamic>? response) {
  final data = response?.data;
  if (data is Map<String, dynamic>) {
    final value = data['error'] ?? data['message'];
    if (value is String && value.isNotEmpty) return value;
  } else if (data is String && data.isNotEmpty) {
    return data;
  }
  return null;
}

Duration? _parseRetryAfter(Headers? headers, {required DateTime now}) {
  final raw = headers?.value('retry-after');
  if (raw == null || raw.isEmpty) return null;
  final seconds = int.tryParse(raw.trim());
  if (seconds != null) return Duration(seconds: seconds);
  // HTTP-date form (RFC 1123) — rare on this API; fall back to null rather
  // than guess.
  final date = _tryParseHttpDate(raw.trim());
  if (date == null) return null;
  final delta = date.difference(now);
  return delta.isNegative ? Duration.zero : delta;
}

const _httpMonths = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// Parses the RFC 1123 HTTP-date format (`Mon, 24 Aug 2026 12:01:00 GMT`).
/// [DateTime.tryParse] does not understand this format.
DateTime? _tryParseHttpDate(String value) {
  final match = RegExp(
    r'^[A-Za-z]{3}, (\d{1,2}) ([A-Za-z]{3}) (\d{4}) '
    r'(\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  if (match == null) return null;
  final month = _httpMonths[match.group(2)];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}
