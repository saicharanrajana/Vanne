# Architecture

How the `wallpaper_app` workspace is structured and why.

## Package boundaries

```
presentation (screens) → repository (app facade) → wallhaven_client → dio
```

- `packages/wallhaven_client` is a **pure Dart package**: it never imports
  Flutter or any widget library. It could be published standalone.
- The app consumes it as a normal workspace dependency. Presentation code
  depends only on the repository and domain models — Dio, JSON, API keys,
  rate limits, and URL construction are invisible to widgets.
- The client is replaceable: a future provider (e.g. Openverse) would expose
  the same shape of results (`PaginatedResult<Wallpaper>`, typed errors) and
  slot in behind the repository without touching UI code.

## Dio layer

All transport configuration lives in one file,
`lib/src/http/dio_factory.dart` — the only place a `Dio` is constructed.
Interceptor order is load-bearing:

1. **ApiKeyInterceptor** — injects `X-API-Key` (header form chosen over
   `?apikey=` so keys never appear in URLs or cache keys).
2. **CacheInterceptor** — can short-circuit before rate limiting so cache
   hits don't consume request budget.
3. **RateLimitInterceptor** — sliding-window throttle (45 req/min default)
   with injectable clock/delay for deterministic tests.
4. **Logging** — last, per dio guidance; output is passed through
   `redactApiKey()` so enabling debug logging cannot leak the key.

Additional infrastructure: `RequestDeduper` collapses concurrent identical
GETs into one in-flight call and deliberately does not cache failures.

## Authentication flow

```
flutter_secure_storage (device keystore/Keychain)
        ↓ restore / save / delete
WallpaperRepository.saveApiKey / removeApiKey
        ↓
ApiKeyManager (in-memory, broadcast stream of AuthenticationState)
        ↓ read per request
ApiKeyInterceptor → X-API-Key header
```

The key exists in exactly two places: platform secure storage and process
memory. Nothing else — not Hive, not logs, not crash reports — ever sees it.
SFW usage works with no key at all.

## Model mapping

DTOs (`src/models/`, one file per aggregate) absorb wire quirks: snake_case
keys, numeric strings (`"24"`), 0/1 booleans, timezone-less timestamps,
missing fields. Mappers (`src/domain/mappers.dart`) convert them into the
immutable domain models in `src/domain/`
(`Wallpaper`, `Tag`, `UserSettings`, …) which are the only types exported by
the package barrel. JSON types never escape `mappers.dart`; presentation code
sees `Purity`/`Category` enums instead of raw strings.

Listing responses omit `uploader`/`tags`; only `/w/{id}` includes them, so
`Wallpaper.uploader`/`.tags` are nullable and `hasDetails` reports whether a
detail fetch has occurred.

## Pagination

`PaginatedResult<T>` carries explicit metadata (`currentPage`, `lastPage`,
`perPage`, `total`, full `SearchMeta`). There is no automatic page crawling:
the UI requests "next page" via `client.nextPage(used, current)`.

Random sorting gets special treatment because Wallhaven assigns a seed to
prevent repeats across pages: when the first response's `meta.seed` exists,
`nextPage` propagates it automatically; an explicitly pinned seed on the
original request always wins (callers may be replaying a known sequence).

## Rate limiting

Sliding-window limiter over the trailing 60 s, capped at
`WallhavenConfig.requestsPerMinute`. Both the clock and the delay function
are constructor-injected, so tests simulate time without sleeping. On HTTP
429 the mapper parses `Retry-After` into
`WallhavenRateLimitExceededException.retryAfter`; the client performs zero
automatic retries — backoff policy belongs to callers.

## Caching strategy

Current phase: `InMemoryCacheStore` + TTL interceptor (GET only, 200-only).
Key = normalized method/path/query; auth headers are excluded by design.
The `CacheStore` interface is the seam for a future persistent cache — swap
the store passed to `CacheInterceptor`, nothing else changes.

## Testing strategy

- **Fixtures** under `test/fixtures/` mirror real Wallhaven payloads
  (including partial-tag and error bodies), so model tests exercise realistic
  JSON offline.
- **Fake adapter**: tests drive the *real* interceptor chain by replacing
  `dio.httpClientAdapter`, recording every request for assertions (URL,
  headers, call counts).
- **Injectable time**: clock + delay seams make rate-limit and TTL tests
  instant and deterministic.
- **Live suite** (`test/live/`) is gated behind `WALLHAVEN_LIVE=1` and makes
  ≤5 SFW requests; authenticated checks additionally need
  `WALLHAVEN_API_KEY`.
- **App layer**: one widget test fakes at the repository seam to prove the
  search screen renders counts/thumbnails/errors without network.

## Security posture

- Key storage: `flutter_secure_storage` v11 (Android EncryptedSharedPreferences-backed AES-GCM; iOS Keychain).
- Key transport: `X-API-Key` header only.
- Key visibility: redacted in logging; excluded from exceptions and caches.
- `.gitignore` blocks `.env*` patterns; docs instruct env-var injection for live tests.

## UI library convention: material_ui over flutter/material

The app runs on the `material_ui` package (the Flutter team's decoupled
Material library), not on `package:flutter/material.dart`. These are
**two separate widget type hierarchies**: the forked `Theme`,
`ScaffoldMessenger`, etc. are distinct classes from their flutter-material
namesakes.

Rules:

* UI code must import `package:material_ui/material_ui.dart` — never
  `package:flutter/material.dart` or `package:flutter/widgets.dart` for
  widgets/colors/theme. Otherwise `Theme.of(context)` silently falls back
  to the default light theme (lookup misses across the type boundary),
  and messenger/snackbar types stop matching what `MaterialApp`
  (`scaffoldMessengerKey`) installs.
* App-wide snackbar access goes through `AppSnack`
  (`shared/widgets/app_snack.dart`), which uses the root
  `scaffoldMessengerKey` — never ambient `ScaffoldMessenger.of(context)`
  from contexts captured across async gaps.
