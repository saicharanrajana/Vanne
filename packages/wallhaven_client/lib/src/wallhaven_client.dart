import 'dart:convert';

import 'package:compute/compute.dart';
import 'package:dio/dio.dart';

import 'auth/api_key_interceptor.dart';
import 'auth/api_key_manager.dart';
import 'auth/authentication_state.dart';
import 'config/wallhaven_config.dart';
import 'domain/domain.dart';
import 'errors/wallhaven_exception.dart';
import 'http/cache/cache_interceptor.dart';
import 'http/cache/cache_store.dart';
import 'http/dio_factory.dart';
import 'http/error_mapper.dart';
import 'http/request_deduper.dart';
import 'models/collection_dto.dart';
import 'models/search_meta_dto.dart';
import 'models/settings_dto.dart';
import 'models/tag_dto.dart';
import 'models/wallpaper_dto.dart';
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
  late final Dio _dio;
  final RequestDeduper _deduper = RequestDeduper();

  /// Creates a client. When [dio] is omitted one is built from [config]
  /// with the standard interceptor chain.
  ///
  /// When [cache] is omitted a single [InMemoryCacheStore] is created and
  /// used for both [cacheStore] and the transport interceptor, so callers
  /// inspecting/clearing [cacheStore] see exactly what the transport caches.
  factory WallhavenClient({
    required ApiKeyManager apiKeyManager,
    WallhavenConfig config = const WallhavenConfig(),
    CacheStore? cache,
    Dio? dio,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  }) {
    final effectiveClock = clock ?? (() => DateTime.now().toUtc());
    final effectiveCache = cache ?? InMemoryCacheStore();
    return WallhavenClient._(
        apiKeyManager: apiKeyManager,
        config: config,
        cacheStore: effectiveCache,
        clock: effectiveClock,
      )
      .._dio =
          dio ??
          buildDio(
            config,
            apiKeyManager: apiKeyManager,
            cacheStore: effectiveCache,
            clock: effectiveClock,
            delay: delay,
          );
  }

  WallhavenClient._({
    required this.apiKeyManager,
    required this.config,
    required this.cacheStore,
    required this.clock,
  });

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
    final (:body, request: httpRequest) = await _getBody(
      '/search',
      query: request.toQueryParameters(),
      cancelToken: cancelToken,
    );
    return _decode(httpRequest, () => _parseListing('/search', body));
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
    final (:data, request: httpRequest) = await _getEnvelope(
      '/w/$id',
      cancelToken: cancelToken,
    );
    return _decode(httpRequest, () {
      final dto = WallpaperDto.fromJson(_castObject(data));
      // An id is the wallpaper's identity: without it the payload cannot be
      // opened, deduped or favorited, so it is a broken response rather than
      // a partially-filled wallpaper.
      if (dto.id.isEmpty) {
        throw WallhavenInvalidResponseException(
          'Wallpaper payload is missing its "id".',
          uri: _uri('/w/$id'),
        );
      }
      return wallpaperFromDto(dto);
    });
  }

  /// Fetches tag metadata: `GET /tag/{id}`.
  Future<Tag> tag(int id, {CancelToken? cancelToken}) async {
    final (:data, request: httpRequest) = await _getEnvelope(
      '/tag/$id',
      cancelToken: cancelToken,
    );
    return _decode(httpRequest, () {
      final dto = TagDto.fromJson(_castObject(data));
      // Tag ids are 1-based at the API; 0 means the field was absent/unusable.
      if (dto.id <= 0) {
        throw WallhavenInvalidResponseException(
          'Tag payload is missing its "id".',
          uri: _uri('/tag/$id'),
        );
      }
      return tagFromDto(dto);
    });
  }

  /// Reads authenticated user settings: `GET /settings`.
  ///
  /// Requires an API key; throws [AuthenticationRequiredException]
  /// otherwise. The rest of the application never needs to call this.
  Future<UserSettings> settings({CancelToken? cancelToken}) async {
    if (!apiKeyManager.isAuthenticated) {
      throw const AuthenticationRequiredException();
    }
    final (:data, request: httpRequest) = await _getEnvelope(
      '/settings',
      cancelToken: cancelToken,
    );
    return _decode(
      httpRequest,
      () => userSettingsFromDto(UserSettingsDto.fromJson(_castObject(data))),
    );
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
    final (:data, request: httpRequest) = await _getList(
      path,
      cancelToken: cancelToken,
    );
    return _decode(httpRequest, () {
      final collections = <WallpaperCollection>[];
      for (final item in data) {
        collections.add(_collectionFromPayload(item, path));
      }
      return collections;
    });
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
    final (:body, request: httpRequest) = await _getBody(
      '/collections/$username/$collectionId',
      query: query,
      cancelToken: cancelToken,
    );
    final listingPath = '/collections/$username/$collectionId';
    return _decode(httpRequest, () => _parseListing(listingPath, body));
  }

  /// Releases the underlying HTTP resources and drops all cached
  /// responses.
  void close() {
    _dio.close(force: true);
    cacheStore.clear();
  }

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

  /// Runs [parse] over a response and discards the cached copy when [parse]
  /// rejects the payload.
  ///
  /// The transport caches any `200` before its body is understood, so without
  /// this a structurally broken response would be replayed from the cache on
  /// every retry until the TTL expired — the user could not recover by
  /// retrying. Only validation failures evict: a network failure has nothing
  /// cached to discard.
  Future<T> _decode<T>(RequestOptions request, T Function() parse) async {
    try {
      return parse();
    } on WallhavenInvalidResponseException {
      await _discardCached(request);
      rethrow;
    }
  }

  /// Best-effort removal of the cached response for [request].
  ///
  /// The interceptor that owns the cache is asked directly rather than going
  /// through [cacheStore]: an injected Dio may have been wired to a different
  /// store instance, and the entry to drop is always the one the transport
  /// actually wrote.
  Future<void> _discardCached(RequestOptions request) async {
    for (final interceptor in _dio.interceptors) {
      if (interceptor is CacheInterceptor) {
        await interceptor.discard(request);
        return;
      }
    }
  }

  /// Performs a GET returning the `{data: ...}` envelope contents.
  Future<({Object? data, RequestOptions request})> _getEnvelope(
    String path, {
    Map<String, String> query = const {},
    CancelToken? cancelToken,
  }) async {
    final (:body, request: httpRequest) = await _getBody(
      path,
      query: query,
      cancelToken: cancelToken,
    );
    if (!body.containsKey('data')) {
      await _discardCached(httpRequest);
      throw WallhavenInvalidResponseException(
        'Expected a JSON object with a "data" field.',
        uri: _uri(path),
      );
    }
    return (data: body['data'], request: httpRequest);
  }

  /// GET whose envelope data must be a JSON array (collection listings).
  Future<({List<Object?> data, RequestOptions request})> _getList(
    String path, {
    Map<String, String> query = const {},
    CancelToken? cancelToken,
  }) async {
    final (:data, request: httpRequest) = await _getEnvelope(
      path,
      query: query,
      cancelToken: cancelToken,
    );
    if (data is! List<dynamic>) {
      await _discardCached(httpRequest);
      throw WallhavenInvalidResponseException(
        'Expected a JSON array in "data".',
        uri: _uri(path),
      );
    }
    return (data: List<Object?>.from(data), request: httpRequest);
  }

  /// GET returning the FULL decoded JSON body as a map — used by listing
  /// endpoints (`/search`, collection wallpapers) whose shape is
  /// `{"data": [...], "meta": {...}}` with no additional envelope.
  Future<({Map<String, dynamic> body, RequestOptions request})> _getBody(
    String path, {
    Map<String, String> query = const {},
    CancelToken? cancelToken,
  }) async {
    Object? body;
    final RequestOptions request;
    try {
      final response = await _dedupeGet(path, query, cancelToken);
      request = response.requestOptions;
      body = response.data;
    } on DioException catch (error) {
      throw mapDioError(error, clock: clock);
    } on Exception catch (error) {
      // Transport/adapter/isolate failures must not leak raw exceptions;
      // the client's contract is typed errors only.
      throw WallhavenNetworkException(
        'Request failed: $error',
        uri: _uri(path),
      );
    }
    if (body is String && body.isNotEmpty) {
      // dio leaves undecodable bodies as raw strings instead of throwing;
      // decode here so the failure surfaces as the typed error. Decoding
      // runs in a separate isolate via compute, like every other JSON
      // path in the client.
      try {
        body = await compute<String, Object?>(_decodeJsonBody, body);
      } on FormatException catch (error) {
        await _discardCached(request);
        throw WallhavenMalformedJsonException(error.message, uri: _uri(path));
      }
    }
    if (body is! Map<String, dynamic>) {
      await _discardCached(request);
      throw WallhavenInvalidResponseException(
        'Expected a JSON object body.',
        uri: _uri(path),
      );
    }
    return (body: body, request: request);
  }

  /// Deduplicates concurrent identical GETs so widget rebuilds never fire
  /// duplicate network calls.
  ///
  /// The target URI is built with [Uri.replace] and sent via `getUri`:
  /// dio's own query encoder would leave `+` inside values unencoded, and
  /// Wallhaven decodes `+` as a space — which would silently corrupt the
  /// `+requiredTag` operator. `Uri` encodes it as `%2B` exactly once.
  ///
  /// The credential is captured here, in one synchronous step, and pinned
  /// onto the request: the dedupe key, the cache scope and the `X-API-Key`
  /// header all describe the same identity even if the key changes before
  /// the interceptor chain runs.
  Future<Response<dynamic>> _dedupeGet(
    String path,
    Map<String, String> query,
    CancelToken? cancelToken,
  ) {
    final scope = apiKeyManager.authScope;
    final apiKey = apiKeyManager.apiKey;
    final key = '$scope GET $path?${_normalizedQuery(query)}';
    return _deduper.run(key, () {
      final target = Uri.parse('${config.baseUrl}$path')
          .replace(queryParameters: query);
      return _dio.getUri(
        target,
        cancelToken: cancelToken,
        options: Options(
          headers: <String, dynamic>{
            if (apiKey != null && apiKey.isNotEmpty)
              ApiKeyInterceptor.headerName: apiKey,
          },
          extra: <String, dynamic>{
            CacheInterceptor.authScopeExtra: scope,
            ApiKeyInterceptor.credentialCapturedExtra: true,
          },
        ),
      );
    });
  }

  PaginatedResult<Wallpaper> _parseListing(
    String path,
    Map<String, dynamic> listing,
  ) {
    // Listing envelope shape: {"data": [...], "meta": {...}}.
    final metaDto = SearchMetaDto.fromJson(
      _castObject(listing['meta'] ?? const <String, dynamic>{}),
    );
    final rawItems = listing['data'];
    // A listing with no "data" at all is an empty page; a listing whose
    // "data" is present but not an array violates the endpoint's shape, and
    // reporting it as "no results" would silently hide results the user
    // asked for.
    if (rawItems != null && rawItems is! List<dynamic>) {
      throw WallhavenInvalidResponseException(
        'Expected a JSON array in "data".',
        uri: _uri(path),
      );
    }
    final candidates = rawItems as List<dynamic>? ?? const <dynamic>[];
    final items = <Wallpaper>[];
    // Skip malformed entries instead of rejecting the whole page: one bad
    // row must never cost the user the other 23.
    for (final item in candidates) {
      if (item is! Map<String, dynamic>) continue;
      final wallpaper = wallpaperFromDto(WallpaperDto.fromJson(item));
      // An entry without an id cannot be deduped by the feed or opened by
      // the detail screen, so it is malformed even though it parsed.
      if (wallpaper.id.isEmpty) continue;
      items.add(wallpaper);
    }
    return PaginatedResult<Wallpaper>(
      items: items,
      meta: searchMetaFromDto(metaDto),
    );
  }

  /// Builds one collection, rejecting an entry with no usable identity.
  ///
  /// Unlike a wallpaper listing, a collection list is a small set the user
  /// navigates by id; silently dropping one would hide saved collections, so
  /// an unusable entry fails the whole response as a typed error.
  WallpaperCollection _collectionFromPayload(Object? payload, String path) {
    final dto = CollectionDto.fromJson(_castObject(payload));
    if (dto.id <= 0) {
      throw WallhavenInvalidResponseException(
        'Collection payload is missing its "id".',
        uri: _uri(path),
      );
    }
    return collectionFromDto(dto);
  }

  /// Returns [request] with [seed] applied, or unchanged when [seed] is
  /// null/empty.
  WallhavenSearchRequest _withSeed(
    WallhavenSearchRequest request,
    String? seed,
  ) => seed == null || seed.isEmpty ? request : request.withSeed(seed);

  Uri _uri(String path) => Uri.parse('${config.baseUrl}$path');

  static String _normalizedQuery(Map<String, String> query) =>
      CacheInterceptor.normalizedQuery(query);
}

Map<String, dynamic> _castObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const WallhavenInvalidResponseException('Expected a JSON object.');
}

/// Isolate entry point for [compute]: `jsonDecode`'s optional parameters
/// do not fit [compute]'s single-argument callback shape.
Object? _decodeJsonBody(String body) => jsonDecode(body);
