# Architecture

How the `vanne` workspace is structured and why.

## Workspace shape

The application is feature-first. `presentation` owns widgets and user
interaction, `application` owns feature controllers, and `core` owns app-wide
facades, local persistence, platform services, and app domain objects.

```
main.dart
  -> WallpaperApp (MaterialApp.router + AppRouter)
       -> feature presentation
            -> feature controllers (signals)
                 -> core facades/repositories/services
                      -> wallhaven_client -> Dio -> Wallhaven API
                      -> Hive / secure storage / Flutter plugins
```

Important workspace packages:

- `packages/wallhaven_client` is a **pure Dart package**. It never imports
  Flutter or a widget library and can be used independently of this app.
- `packages/system_wallpaper` is the first-party Flutter plugin for wallpaper
  application. Its Android implementation is Kotlin; it has no API-client or
  presentation responsibilities.
- The root package contains all Flutter UI, app state, local storage, image
  caching, downloads, routing, theming, and platform-service adapters.

The app imports Wallhaven domain models from the public client barrel, but UI
code does not know about Dio, JSON DTOs, API keys, rate limits, or URL
construction. The `WallpaperRepository` is the app facade and the seam for a
future provider.

## Startup and dependency injection

`lib/main.dart` performs startup in this order:

1. Initialize Flutter bindings and enlarge Flutter's image-cache limits.
2. Load `intl` date data and preload the Outfit font weights used by the app.
3. Run `bootstrap()` in `lib/app/dependencies.dart`.
4. Install the global `ErrorWidget` fallback and call `runApp()`.

`bootstrap()` initializes Hive, opens the settings/favorites/collections
stores, seeds the built-in collections on first install, constructs the
`WallpaperRepository`, and restores the API key before registering services.
`get_it` is the application service locator.

- Singleton state: `SettingsController`, `FavoritesController`,
  `CollectionsController`, and `TabScrollCoordinator`.
- Singleton data services: `SettingsStore`, `FavoritesRepository`,
  `CollectionsRepository`, and `WallpaperRepository`.
- Lazy services: `DownloadService`, `WallpaperApplier`, and
  `UrlLauncherService`.
- Factory services: `DiscoverController`, `SearchController`,
  `CollectionExploreController`, and `WallpaperDetailController`.

The `WallhavenClient` is owned by `WallpaperRepository`, rather than being a
separate locator registration. Tests replace the repository or inject a Dio
instance at the appropriate seam.

## Routing and screen lifetime

Routing uses `auto_route` and a generated `lib/app/router/app_route.gr.dart`.
`WallpaperApp` owns one `AppRouter` and supplies its configuration to
`MaterialApp.router`.

The root stack contains:

- `MainShellRoute`, with nested Discover, Collections, Favorites, and Settings
  tab routes.
- Full-screen Search, collection exploration, wallpaper detail, filtered
  wallpapers, API-key settings, and blocked-tags routes.
- Page-backed modal routes for create/delete collection, remove API key, set
  wallpaper, and the feed-filter sheet.

The shell keeps the four tab destinations alive, preserving their widget and
scroll state. The app-level `TabScrollCoordinator` owns one scroll controller
per tab; reselecting the active navigation destination scrolls that tab to the
top. Back from a non-Discover tab first switches to Discover instead of
leaving the app.

Route arguments are typed. Wallpaper detail accepts an optional listing
wallpaper so a tile can transition immediately through a Hero; a cold deep
link gets a minimal placeholder and then loads `/w/{id}`. Search and filtered
values use query parameters, while collection and wallpaper IDs use path
parameters. Listing snapshots, Hero scopes, and modal controllers remain
runtime-only typed arguments. External deep links to modal routes are
transformed to `/` because modal arguments contain live runtime state and must
not be restored from a URI.

Controllers are created once per screen or route lifetime and disposed when
that route is removed:

- Discover and Search controllers are acquired from factories by their
  stateful screens. Discover remains alive while its tab is preserved.
- Collection exploration resolves its persisted `CollectionEntry` once and
  owns one `CollectionExploreController`.
- Filtered wallpapers owns an ephemeral `FilteredWallpapersController`.
- Wallpaper detail creates its controller in route `initState` and disposes it
  in route `dispose`.

## State management

Application and feature state uses `signals` (`Signal`, `computed`, and
`SignalBuilder`). Widget-local state such as text fields, focus, animations,
and route state remains ordinary Flutter state.

`FeedController` is the shared base for Discover, Search, collection
exploration, and filtered wallpapers. It owns:

- `FeedState` with first-page loading, load-more loading, first-load errors,
  pagination errors, items, and `hasMore`.
- A `Set<Wallpaper>` for insertion-order-preserving duplicate suppression.
- In-flight-page guards, page counters, random-search seed propagation, and
  retry behavior that preserves already-loaded content.
- A generation counter so a response from an older reload cannot update a
  newer feed.

Search separates live text-field content from committed query state. Submit
and chip changes use a 350 ms trailing debounce, so rapid edits produce one
request and typing alone never performs I/O. Color chips are single-select;
genre chips append their mapped search term to the committed query.

`FeedFilter` is a pure app value object containing sorting, popular-result time
range, minimum resolution, and category filters. Discover defaults to General
only. Search, collection exploration, and filtered feeds keep their sort/filter
  changes for the current screen session; they are not persisted. Portrait-only
  results, purity, and blocked tags are global policy and are applied by the
  repository on every search.

Favorites and collections update their signals optimistically, persist the
change, and roll back on persistence failure. Grid tiles subscribe only to the
favorite-ID membership signal, so a favorite tap does not rebuild the entire
grid. Collection cards subscribe only to the relevant selection membership.

All controllers guard signal writes after disposal. Detail downloads use a
cancel token tied to the screen lifetime, while feed reload generations prevent
stale network results from corrupting current state.

## Local persistence

Hive CE stores non-secret app data in three boxes:

- `app_settings`: dynamic color, pitch-black mode, theme mode, NSFW
  preference, and normalized blocked tags.
- `favorites`: JSON-encoded `FavoriteWallpaper` snapshots keyed by wallpaper
  ID. The snapshot includes the page URL, image URLs, dimensions, resolution,
  ratio, file metadata, and creation date, so favorites can render offline
  even when Wallhaven removes the wallpaper.
- `collections`: JSON-encoded `CollectionEntry` values keyed by collection ID.
  An entry stores its display name, query, categories, colors, feed filter, and
  creation date. Six curated collections are inserted when the store is empty
  on first bootstrap.

Favorites and collections use `compute` for JSON work. Restore is batched where
possible and malformed snapshots are skipped rather than preventing all local
content from loading. Collection deletion and favorite toggles are optimistic
and recover from write failures.

The API key is deliberately absent from Hive. It is handled only by
`SecureApiKeyStore` and `ApiKeyManager` below.

## Wallhaven client boundary

`packages/wallhaven_client` exposes typed search, wallpaper, tag, settings, and
collection operations. Its public barrel exports domain models, request/query
types, configuration, authentication state, cache abstractions, and typed
exceptions. DTOs and HTTP internals remain under `src/`.

DTOs (`src/models/`, one file per aggregate) absorb wire quirks: snake_case
keys, numeric strings, 0/1 booleans, timezone-less timestamps, missing fields,
and inconsistent optional fields. `src/domain/mappers.dart` converts them to
immutable domain models such as `Wallpaper`, `Tag`, and `UserSettings`. JSON
types do not escape the mapper layer.

Listing responses omit `uploader` and `tags`; only `/w/{id}` supplies them.
Consequently `Wallpaper.uploader` and `.tags` are nullable and `hasDetails`
indicates whether detail data is present. The app's detail controller starts
with listing data and enriches it in place when the detail request completes.

The app repository translates `FeedFilter` and global settings into a
`WallhavenSearchRequest`. Wallpaper palette colors are arbitrary hex values,
while Wallhaven accepts a fixed set of documented search colors; tapped colors
are mapped to the nearest supported wire color before a filtered request.

The client uses `package:compute`/Dio's fused transformer to decode JSON off the
UI isolate. The client promises that callers receive only `WallhavenException`
subtypes from transport and response failures.

## Wallhaven HTTP transport

All Wallhaven API transport configuration lives in
`packages/wallhaven_client/lib/src/http/dio_factory.dart`. It is the only
constructor for the client's API Dio. The app's `DownloadService` intentionally
uses a separate, bare Dio because image downloads are an app concern and do
not use the API transport's request policy.

Interceptor order is load-bearing:

1. **ApiKeyInterceptor** injects `X-API-Key` only when a key is active. A
   header is used instead of `?apikey=` so the key never enters URLs or cache
   keys.
2. **CacheInterceptor** can resolve a cache hit before rate limiting, so cache
   hits do not consume request budget.
3. **RateLimitInterceptor** applies the sliding-window throttle.
4. **Logging**, when enabled, is last and passes output through
   `redactApiKey()`.

`RequestDeduper` collapses concurrent identical GETs into one in-flight
request. The shared future is removed on both success and failure, so failures
are never cached. A known trade-off is that cancelling one waiter cancels the
shared request for every waiter using that key.

## Authentication flow

```
flutter_secure_storage (Android EncryptedSharedPreferences / iOS Keychain)
        |
        | restore / save / delete
        v
WallpaperRepository
        |
        v
ApiKeyManager (in-memory key + AuthenticationState stream)
        |
        | read for each request
        v
ApiKeyInterceptor -> X-API-Key header
```

The key is never written to Hive, ordinary files, logs, cache entries, or
exceptions. It exists persistently in platform secure storage and at runtime
in `ApiKeyManager`; the request header is the only transport representation.
SFW usage works without a key. If NSFW is enabled without an authenticated
manager, the app repository clamps the request back to SFW and reports that the
preference was not honored. Removing a key also disables the NSFW preference.

## Pagination, throttling, and caching

Pagination is explicit. The package exposes `nextPage(used, current)` for
callers that want it, but the app's `FeedController` tracks its own page and
seed and asks `WallpaperRepository.search` for the next page. No layer
automatically crawls ahead.

`PaginatedResult<T>` carries `SearchMeta` with current page, last page, page
size, total, and an optional random-search seed. The feed stops only when the
server reports no next page and the current page is not below `lastPage`.
Random feeds retain the server seed between pages; an explicitly pinned seed
always wins. Repeated wallpapers across or within pages are removed before
they reach the grid. A failed later page leaves existing content visible and
offers a footer retry.

The client limiter uses the trailing 60 seconds and caps requests at
`WallhavenConfig.requestsPerMinute` (45 by default). Its clock and delay
function are injectable for deterministic tests. HTTP 429 responses map to
`WallhavenRateLimitExceededException`; `Retry-After` supports seconds and RFC
1123 HTTP dates. The client performs zero automatic retries.

The API cache is GET-only and stores successful 200 responses for five minutes
by default. `InMemoryCacheStore` is LRU-capped at 100 entries and evicts
expired entries lazily on read. Keys contain normalized method/path and sorted,
percent-encoded query parameters; authentication headers are excluded. The
`CacheStore` interface is the seam for a future persistent implementation.
`WallhavenClient.close()` closes its Dio and clears the store.

## Error contract

The package maps Dio failures, malformed JSON, invalid response shapes, HTTP
statuses, cancellation, and transport exceptions into `WallhavenException`
subtypes. It does not retry. `lib/core/errors/error_messages.dart` translates
Wallhaven exceptions at the app boundary into short user-facing strings, so
screens do not depend on the client exception taxonomy.

App-only operations have their own contracts: downloads expose
`DownloadException`, and the wallpaper plugin returns structured success or
`WallpaperFailure` results. `DownloadService` and `WallpaperApplier` map those
failures to display-safe messages before presentation handles them.

## Image pipeline and downloads

Grid tiles normally request `wallpaper.thumbnails.original`, the uncropped
original-aspect thumbnail. They fall back to the full path only when that
thumbnail is unavailable. The tile's aspect ratio comes from wallpaper
dimensions, and `memCacheWidth` is clamped to the cell's physical width so
thumbnail decoding does not consume full-resolution RAM.

The detail hero requests the full `wallpaper.path` when available. While it
loads, `SmartNetworkImage` keeps the listing thumbnail underneath. Both URLs
are cached independently by `cached_network_image`/`flutter_cache_manager`, so
the listing thumbnail can be reused without pretending it is the full image.
Detail decoding is clamped to the device screen width. Empty or failed images
fall back to a dominant-color surface, with optional blurhash support; fades
are disabled when reduced motion is requested.

`ImageCacheService` exposes the image-cache policy used by Settings. It clears
Flutter's memory cache, the `flutter_cache_manager` disk cache, and the
orphaned legacy `extended_image` directory. Startup raises Flutter's memory
cache limits to reduce re-decodes when returning from detail screens.

`DownloadService` downloads the full original to a temporary cache file,
reports progress, supports cancellation, and saves gallery images through
`gal` in the `WallpaperApp` album. Android 10+ MediaStore owns the gallery
copy; the temporary file is deleted afterward. Gallery persistence is separate
from the Wallhaven HTTP response cache.

The detail source action delegates to `UrlLauncherService`, which opens the
Wallhaven page in the platform's in-app browser view. The service is a small
testable adapter around `url_launcher` rather than a concern of the widget.

## Theming and presentation conventions

The app uses `material_ui` plus `material_3_expressive`, not Flutter's
`package:flutter/material.dart` widget hierarchy. These Material hierarchies
are distinct. UI code must import `package:material_ui/material_ui.dart` for
widgets, colors, themes, and messenger types. Mixing the hierarchies causes
theme and `ScaffoldMessenger` lookups to miss.

The root theme supports system/light/dark mode, a teal-seeded fallback,
Android Material You dynamic color, and an optional pitch-black dark surface
ladder. Dynamic system palettes are signals: `futureSignal` reads a global
refresh tick, and computed light/dark schemes drive the root theme. Applying a
wallpaper requests one debounced palette refresh after the OS has had time to
extract colors.

Wallpaper detail derives a separate `ColorScheme` from the wallpaper's most
saturated readable palette color. Its `AnimatedTheme` covers the full detail
screen. The set-wallpaper dialog is a root route outside that subtree, so it
re-derives and applies the same wallpaper theme itself.

App-wide snackbar access goes through `AppSnack` and the root
`scaffoldMessengerKey`. It clears pending bars, suppresses duplicate messages
for a short window, uses semantic theme roles, and supports context-free
messages after asynchronous work. Screens do not retain a `BuildContext` over
an async gap just to show a snackbar.

## Wallpaper application: `packages/system_wallpaper`

The first-party plugin exposes four operations:

- Home, Lock, and Both call `WallpaperManager.setStream` with
  `FLAG_SYSTEM`/`FLAG_LOCK` from Kotlin `Dispatchers.IO`. The plugin streams
  the file and does not decode it into a Flutter bitmap.
- Crop and set launches the system picker using
  `getCropAndSetWallpaperIntent`, then falls back through
  `ACTION_ATTACH_DATA`, `ACTION_SET_WALLPAPER`, and `ACTION_VIEW`.

Picker operations use a `FileProvider` URI with read permission grants and
`ClipData`. The plugin manifest owns `SET_WALLPAPER`, the provider and its
file paths, and package-visibility queries for picker intents. It does not own
`INTERNET`; that permission remains in the app manifest.

The app-side `WallpaperApplier` translates plugin results into
`ApplyOutcome`. `WallpaperDetailController` downloads/resolves one local file
in the app cache before opening the set dialog, reuses it for all four choices,
and cancels the transfer when detail is disposed.

## Android app overrides

Some behavior cannot be supplied by a plugin because the manifest merger does
not add attributes to an app-declared activity, and injecting an Application
class would reduce plugin composability. The app therefore keeps these
overrides in `tool/android_overrides/` and reapplies them with
`tool/apply_android_overrides.sh` after recreating `android/`:

1. Activity `configChanges` includes `colorMode`, `navigation`, `mcc`, and
   `mnc` along with Flutter's normal configuration flags.
2. `WallpaperApp.kt` pre-warms a Flutter engine and stores it as
   `"main_engine"` in `FlutterEngineCache`.
3. `MainActivity.kt` binds to that cached engine and sets
   `shouldDestroyEngineWithHost = false`.
4. `android/app/build.gradle.kts` gets compile/min SDK floors based on the
   maximum numeric requirement found in the plugins listed by
   `.flutter-plugins-dependencies`.

The Pixel wallpaper picker can trigger a Runtime Resource Overlay change in
System UI. That can recreate the activity even with the configuration flags;
the cached engine makes recreation invisible by preserving navigation and
signal state. The override script is idempotent and detects the app's Kotlin
package. A startup verification hook is still a TODO, so running the script
after `rm -rf android && flutter create .` remains an operational requirement.

## Testing strategy

- Client fixtures under `packages/wallhaven_client/test/fixtures/` mirror
  search, detail, partial-tag, and error payloads.
- Client tests replace `dio.httpClientAdapter` with a fake adapter and drive
  the real interceptor chain, asserting URLs, headers, cache hits, and call
  counts.
- Injectable clocks and delay functions make rate-limit and TTL tests
  deterministic without sleeping.
- The opt-in live suite under `packages/wallhaven_client/test/live/` is gated
  by `WALLHAVEN_LIVE=1`, uses at most about five unauthenticated requests, and
  adds authenticated checks only when `WALLHAVEN_API_KEY` is present.
- App tests fake `WallpaperRepository` and platform seams, then run screens
  inside the real `material_ui`/M3E theme. They cover feed pagination and
  deduplication, routed deep links and back behavior, Hero transitions,
  settings, snackbar roles, image transitions, metadata formatting, and
  wallpaper-detail interactions.
- `integration_test/app_test.dart` runs on a device/emulator against the real
  Wallhaven API and checks discover loading, detail navigation, and favorites
  empty state.

## Security posture

- API keys use `flutter_secure_storage` v11: Android secure preferences with
  platform encryption and iOS Keychain.
- Keys travel only in the `X-API-Key` header.
- Logging redacts the active key; URLs, cache keys, exception text, and Hive do
  not retain it. While a user enters a key it is held by the password field,
  then that field is cleared after a successful save or removal and disposed
  when the screen leaves.
- `.gitignore` blocks `.env` variants. Live-test secrets must be injected via
  environment variables or another ignored local mechanism.
