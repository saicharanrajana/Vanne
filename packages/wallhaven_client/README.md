# wallhaven_client

A Dart-only client for the [Wallhaven API v1](https://wallhaven.cc/help/api).
Strongly typed models, optional API-key authentication, client-side rate
limiting, explicit pagination, and a fully typed error hierarchy. No Flutter
dependency — usable from any Dart project.

## Supported endpoints

| Method | Endpoint | Client call | Auth |
|---|---|---|---|
| GET | `/search` | `search(request)` / `nextPage(used, current)` | Optional (key changes defaults, unlocks NSFW) |
| GET | `/w/{id}` | `wallpaper(id)` | Optional (required for NSFW wallpapers) |
| GET | `/tag/{id}` | `tag(id)` | None |
| GET | `/settings` | `settings()` | **Required** |
| GET | `/collections` | `collections()` | **Required** (own collections incl. private) |
| GET | `/collections/{user}` | `collections(username: ...)` | None (public only) |
| GET | `/collections/{user}/{id}` | `collectionWallpapers(...)` | Optional (private needs owner's key) |

## Usage

```dart
final manager = ApiKeyManager(); // start unauthenticated — SFW just works
final client = WallhavenClient(apiKeyManager: manager);

// Search latest SFW wallpapers.
final page = await client.search(WallhavenSearchRequest(
  structuredQuery: WallhavenQuery().require('anime').exclude('nsfw'),
  minResolution: '1920x1080',
  colors: {WallhavenColor.blue0066cc},
));

// Pagination is explicit; nothing crawls ahead automatically.
if (page.hasNextPage) {
  final page2 = await client.nextPage(request, page);
}

// Random sorting: propagate the server seed so pages never repeat results.
final request = WallhavenSearchRequest(sorting: WallhavenSorting.random);
final first = await client.search(request);
final second = await client.nextPage(request, first); // carries meta.seed

// Authentication is opt-in.
manager.setApiKey('your-key');   // activates X-API-Key header
manager.setApiKey(null);         // removes it
```

The app layer decides where a key comes from. In our app it is stored with
`flutter_secure_storage` and fed into [ApiKeyManager] at startup; this
package itself never persists anything.

## Authentication model

- No key → normal SFW usage. Requests carry no credentials.
- Key set → sent as an `X-API-Key` header (never a query parameter), so keys
  cannot leak into URLs, cache keys, or exception messages.
- NSFW is fail-fast: requesting `purity: {..., nsfw}` without a key throws
  `NsfwAuthenticationRequiredException` before any network activity.

## Rate limiting

- The client throttles itself to 45 requests/minute (configurable via
  `WallhavenConfig.requestsPerMinute`) using a sliding window.
- HTTP 429 maps to `WallhavenRateLimitExceededException`, carrying
  `retryAfter` parsed from the `Retry-After` header when present.
- **Zero automatic retries** — a deliberate contract. Callers decide whether
  to retry after inspecting `retryAfter`.

## Error handling

All failures throw `WallhavenException` subtypes:

| Exception | Cause |
|---|---|
| `WallhavenNetworkException` | connection failure / DNS |
| `WallhavenTimeoutException` | connect/send/receive timeout (`kind`) |
| `WallhavenCancelledException` | `CancelToken` cancellation |
| `WallhavenInvalidResponseException` | unexpected body shape/status |
| `WallhavenMalformedJsonException` | undecodable JSON |
| `WallhavenBadRequestException` | HTTP 400 |
| `WallhavenUnauthorizedException` | HTTP 401 |
| `NsfwAuthenticationRequiredException` | NSFW without key (local or remote) |
| `AuthenticationRequiredException` | auth-only endpoint called anonymously |
| `WallhavenForbiddenException` | HTTP 403 |
| `WallhavenNotFoundException` | HTTP 404 |
| `WallhavenRateLimitExceededException` | HTTP 429 (+ `retryAfter`) |
| `WallhavenServerException` | HTTP 5xx |

Exception text never contains API keys.

## Caching

GET responses are cached in memory under a normalized key
(`method + path + percent-encoded sorted query`) with a configurable TTL
(`WallhavenConfig.cacheTtl`, default 5 minutes). The default
`InMemoryCacheStore` is LRU-capped (100 entries) so long sessions cannot
grow without bound; `close()` releases the transport and drops every cached
response. The cache lives behind the `CacheStore` interface, so a persistent
implementation can be swapped in without touching client code. Keys are
derived from URLs, and auth travels in headers — API keys can never enter
the cache.

## Testing

```bash
cd packages/wallhaven_client
flutter test        # 88 offline unit tests (fixtures + fake HTTP adapter)
```

### Live integration tests (opt-in)

Never run as part of the default suite:

```bash
WALLHAVEN_LIVE=1 dart test test/live/live_wallhaven_test.dart

# Optionally include authenticated checks (settings, own collections):
WALLHAVEN_LIVE=1 WALLHAVEN_API_KEY=your-key \
  dart test test/live/live_wallhaven_test.dart
```

Do not commit your key. Export it in your shell or use a git-ignored `.env`
mechanism of your choice; CI must inject secrets, never store them.

## Limitations

- GET-only: Wallhaven v1 exposes no write operations, and neither do we.
- No automatic retries by design.
- No download management — the package surfaces image URLs; persistence is
  an application concern.
- `WallhavenColor` covers the 29 documented search colors.
