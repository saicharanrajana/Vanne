/// A Dart-only client for the Wallhaven API v1.
///
/// Exposes the complete public surface of the package. Applications import
/// only this library — never `src/` internals, never JSON types.
library;

export 'src/auth/api_key_manager.dart';
export 'src/auth/authentication_state.dart';
export 'src/config/wallhaven_config.dart';
export 'src/domain/domain.dart';
export 'src/errors/wallhaven_exception.dart';
export 'src/http/cache/cache_store.dart';
export 'src/search/search_query.dart';
export 'src/search/search_request.dart';
export 'src/wallhaven_client.dart';
