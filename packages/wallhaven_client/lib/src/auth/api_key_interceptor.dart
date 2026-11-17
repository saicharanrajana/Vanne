import 'package:dio/dio.dart';

import 'api_key_manager.dart';

/// Injects the optional API key into every outgoing request via the
/// `X-API-Key` header.
///
/// The header form (rather than the `?apikey=` query parameter) is chosen
/// deliberately so the key never appears in URLs, cache keys, or exception
/// `uri` fields. When no key is set, requests pass through untouched —
/// SFW usage never requires a key.
///
/// A request that already carries the header keeps it: `WallhavenClient`
/// pins the credential when it dispatches the call, so the header always
/// matches the identity the cache and dedupe entries were filed under, even
/// when the key changes before this interceptor runs.
final class ApiKeyInterceptor extends Interceptor {
  final ApiKeyManager _manager;

  ApiKeyInterceptor(this._manager);

  static const String headerName = 'X-API-Key';

  /// Marks requests whose credential (including anonymous) was captured by
  /// the client at dispatch time. Direct Dio users omit this and retain
  /// the normal live-manager injection behaviour.
  static const String credentialCapturedExtra = 'wallhaven_credential_captured';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[credentialCapturedExtra] == true ||
        options.headers.containsKey(headerName)) {
      handler.next(options);
      return;
    }
    final key = _manager.apiKey;
    if (key != null && key.isNotEmpty) {
      options.headers[headerName] = key;
    }
    handler.next(options);
  }
}

/// Replaces any occurrence of [apiKey] in [text] with `<redacted>`.
///
/// Used by the logging interceptor so debug output can never leak the key.
String redactApiKey(String text, {String? apiKey}) {
  final key = apiKey;
  if (key == null || key.isEmpty) return text;
  return text.replaceAll(key, '<redacted>');
}
