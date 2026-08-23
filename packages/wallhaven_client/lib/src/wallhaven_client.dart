
import 'dart:convert';

import 'package:compute/compute.dart';
import 'package:dio/dio.dart';

import 'auth/api_key_manager.dart';
import 'auth/authentication_state.dart';
import 'config/wallhaven_config.dart';
import 'domain/domain.dart';
import 'errors/wallhaven_exception.dart';
import 'http/cache/cache_store.dart';
import 'http/dio_factory.dart';
import 'http/error_mapper.dart';
import 'http/request_deduper.dart';
import 'models/models.dart';
import 'search/search_request.dart';

/// The Wallhaven API v1 client.
///
/// - Never requires an API key for SFW usage; authentication is optional
///   and provided via [ApiKeyManager].
/// - Throws only [WallhavenException] subtypes; never raw dio errors and
///   never generic exceptions.
/// - Pagination is explicit: callers drive pages via [search]/[nextPage];
///   nothing is prefetched or crawled automatically.
///
/// The client owns its transport (see `buildDio`); tests inject a Dio
/// instance through the [dio] parameter instead.
final class WallhavenClient {
  final ApiKeyManager apiKeyManager;
  final WallhavenConfig config;
  final CacheStore cacheStore;

  /// Injectable clock, forwarded to rate limiting/caching (tests).
  final DateTime Function() clock;
  final Dio _dio;
  final RequestDeduper _deduper = RequestDeduper();

  /// Creates a client. When [dio] is omitted one is built from [config]
  /// with the standard interceptor chain.
  WallhavenClient({
    required this.apiKeyManager,
    this.config = const WallhavenConfig(),
    CacheStore? cache,
    Dio? dio,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  })  : cacheStore = cache ?? InMemoryCacheStore(),
        clock = clock ?? (() => DateTime.now().toUtc()),
        _dio = dio ??
            buildDio(
              config,
              apiKeyManager: apiKeyManager,
              cacheStore: cache ?? InMemoryCacheStore(),
              clock: clock,
              delay: delay,
            );

  AuthenticationState get authState => apiKeyManager.state;

  // -------------------------------------------------------------------------
  // Endpoints
  // -------------------------------------------------------------------------

  /// Searches wallpapers: `GET /search`.
  ///
  /// Throws [NsfwAuthenticationRequiredException] immediately when
  /// [WallhavenSearchRequest.purity] includes NSFW while unauthenticated —
  /// the request is not sent at all.
  Future<PaginatedResult<Wallpaper>> search(
    WallhavenSearchRequest request, {
    CancelToken? cancelToken,
  }) async {
    _assertNsfwAllowed(request.purity);
    final data = await _getBody('/search',
        query: request.toQueryParameters(), cancelToken: cancelToken);
    return _parseListing(data);
  }

  /// Requests the page following [current] by re-issuing [used] at
  /// `currentPage + 1`.
  ///
  /// Seed semantics: when [used] carried no explicit seed but the server
  /// returned one (random sorting), the server seed is propagated into the
  /// follow-up request so consecutive random pages never repeat results.
  /// When [current] has no next page, no request is made and the returned
  /// future completes with [current].
  Future<PaginatedResult<Wallpaper>> nextPage(
    WallhavenSearchRequest used,
    PaginatedResult<Wallpaper> current, {
    CancelToken? cancelToken,
  }) {
    if (!current.hasNextPage) return Future.value(current);
    final next = used.withPage(current.currentPage + 1);
    return search(
      // Propagate the server seed unless the caller already pinned one;
      // a caller-supplied seed wins because they may be replaying a
      // specific random sequence deliberately.
      next.seed != null ? next : _withSeed(next, current.meta.seed),
      cancelToken: cancelToken,
    );
  }

  /// Fetches wallpaper details including uploader and tags: `GET /w/{id}`.
  Future<Wallpaper> wallpaper(String id, {CancelToken? cancelToken}) async {
    final data =
        await _getEnvelope('/w/$id', cancelToken: cancelToken);
    return wallpaperFromDto(
      WallpaperDto.fromJson(_castObject(data)),
    );
  }

  /// Fetches tag metadata: `GET /tag/{id}`.
  Future<Tag> tag(int id, {CancelToken? cancelToken}) async {
    final data = await _getEnvelope('/tag/$id', cancelToken: cancelToken);
    return tagFromDto(TagDto.fromJson(_castObject(data)));
  }

  /// Reads authenticated user settings: `GET /settings`.
  ///
  /// Requires an API key; throws [AuthenticationRequiredException]
  /// otherwise. The rest of the application never needs to call this.
  Future<UserSettings> settings({CancelToken? cancelToken}) async {
    if (!apiKeyManager.isAuthenticated) {
      throw const AuthenticationRequiredException();
    }
    final data = await _getEnvelope('/settings', cancelToken: cancelToken);
    return userSettingsFromDto(UserSettingsDto.fromJson(_castObject(data)));
  }

  /// Lists collections. Without [username] lists the authenticated user's
  /// own collections (including private ones) and requires an API key;
  /// with [username] lists that user's public collections without a key.
  Future<List<WallpaperCollection>> collections({
    String? username,
    CancelToken? cancelToken,
  }) async {
    if (username == null && !apiKeyManager.isAuthenticated) {
      throw const AuthenticationRequiredException();
    }
    final path = username == null ? '/collections' : '/collections/$username';
    final data = await _getList(path, cancelToken: cancelToken);
    return [
      for (final item in data)
        collectionFromDto(CollectionDto.fromJson(_castObject(item))),
    ];
  }

  /// Lists the wallpapers in [username]'s collection [collectionId]:
  /// `GET /collections/{username}/{id}`. Only the purity filter applies on
  /// this endpoint; viewing private collections requires owning them.
  Future<PaginatedResult<Wallpaper>> collectionWallpapers({
    required String username,
    required int collectionId,
    Set<WallhavenPurity>? purity,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    if (purity?.contains(WallhavenPurity.nsfw) ?? false) {
      _assertNsfwAllowed(purity!);
    }
    final query = <String, String>{
      if (purity != null && purity.length != WallhavenPurity.values.length)
        'purity': encodePurities(purity),
      if (page > 1) 'page': '$page',
    };
    final data = await _getBody(
      '/collections/$username/$collectionId',
      query: query,
      cancelToken: cancelToken,
    );
    return _parseListing(data);
  }

  /// Releases the underlying HTTP resources.
  void close() => _dio.close(force: true);

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  void _assertNsfwAllowed(Set<WallhavenPurity> purity) {
    if (purity.contains(WallhavenPurity.nsfw) &&
        !apiKeyManager.isAuthenticated) {
      // Fail fast: do not spend a request that Wallhaven will reject.
      throw const NsfwAuthenticationRequiredException();
    }
  }

  /// Performs a GET returning the `{data: ...}` envelope contents.
  Future<Object?> _getEnvelope(
    String path, {
    Map<String, String> query = const {},
    CancelToken? cancelToken,
  }) async {
    final body = await _getBody(path, query: query, cancelToken: cancelToken);
    if (!body.containsKey('data')) {
      throw WallhavenInvalidResponseException(
        'Expected a JSON object with a "data" field.',
        uri: _uri(path),
      );
    }
    return body['data'];
  }

  /// GET whose envelope data must be a JSON array (collection listings).
  Future<List<Object?>> _getList(
    String path, {
    Map<String, String> query = const {},
    CancelToken? cancelToken,
  }) async {
    final data = await _getEnvelope(path, query: query, cancelToken: cancelToken);
    if (data is! List<dynamic>) {
      throw WallhavenInvalidResponseException(
        'Expected a JSON array in "data".',
        uri: _uri(path),
      );
    }
    return List<Object?>.from(data);
  }

  /// GET returning the FULL decoded JSON body as a map — used by listing
  /// endpoints (`/search`, collection wallpapers) whose shape is
  /// `{"data": [...], "meta": {...}}` with no additional envelope.
  Future<Map<String, dynamic>> _getBody(
    String path, {
    Map<String, String> query = const {},
    CancelToken? cancelToken,
  }) async {
    Object? body;
    try {
      final response = await _dedupeGet(path, query, cancelToken);
      body = response.data;
    } on DioException catch (error) {
      throw mapDioError(error);
    }
    if (body is String && body.isNotEmpty) {
      // dio leaves undecodable bodies as raw strings instead of throwing;
      // decode here so the failure surfaces as the typed error. Decoding
      // runs in a separate isolate via compute, like every other JSON
      // path in the client.
      try {
        body = await compute<String, Object?>(_decodeJsonBody, body);
      } on FormatException catch (error) {
        throw WallhavenMalformedJsonException(error.message, uri: _uri(path));
      }
    }
    if (body is! Map<String, dynamic>) {
      throw WallhavenInvalidResponseException(
        'Expected a JSON object body.',
        uri: _uri(path),
      );
    }
    return body;
  }

  /// Deduplicates concurrent identical GETs so widget rebuilds never fire
  /// duplicate network calls.
  ///
  /// The target URI is built with [Uri.replace] and sent via `getUri`:
  /// dio's own query encoder would leave `+` inside values unencoded, and
  /// Wallhaven decodes `+` as a space — which would silently corrupt the
  /// `+requiredTag` operator. `Uri` encodes it as `%2B` exactly once.
  Future<Response<dynamic>> _dedupeGet(
    String path,
    Map<String, String> query,
    CancelToken? cancelToken,
  ) {
    final key = 'GET $path?${_normalizedQuery(query)}';
    return _deduper.run(key, () {
      final target =
          Uri.parse('${config.baseUrl}$path').replace(queryParameters: query);
      return _dio.getUri(target, cancelToken: cancelToken);
    });
  }

  PaginatedResult<Wallpaper> _parseListing(Map<String, dynamic> listing) {
    // Listing envelope shape: {"data": [...], "meta": {...}}.
    final metaDto = SearchMetaDto.fromJson(
      _castObject(listing['meta'] ?? const <String, dynamic>{}),
    );
    final rawItems = listing['data'];
    final items = [
      // Skip malformed entries instead of rejecting the whole page.
      for (final item in (rawItems is List<dynamic> ? rawItems : <dynamic>[]))
        if (item is Map<String, dynamic>)
          wallpaperFromDto(WallpaperDto.fromJson(item)),
    ];
    return PaginatedResult<Wallpaper>(
      items: items,
      currentPage: metaDto.currentPage,
      lastPage: metaDto.lastPage,
      perPage: metaDto.perPage,
      total: metaDto.total,
      meta: searchMetaFromDto(metaDto),
    );
  }

  /// Returns [request] with [seed] applied, or unchanged when [seed] is
  /// null/empty.
  WallhavenSearchRequest _withSeed(
    WallhavenSearchRequest request,
    String? seed,
  ) =>
      seed == null || seed.isEmpty ? request : request.withSeed(seed);

  Uri _uri(String path) => Uri.parse('${config.baseUrl}$path');

  static String _normalizedQuery(Map<String, String> query) {
    final keys = query.keys.toList()..sort();
    return [for (final key in keys) '$key=${query[key]}'].join('&');
  }
}

Map<String, dynamic> _castObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const WallhavenInvalidResponseException(
    'Expected a JSON object.',
  );
}

/// Isolate entry point for [compute]: `jsonDecode`'s optional parameters
/// do not fit [compute]'s single-argument callback shape.
Object? _decodeJsonBody(String body) => jsonDecode(body);
