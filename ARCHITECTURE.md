# Architecture

How the `wallpaper_app` workspace is structured and why.

## Package boundaries

```
presentation (screens) → controllers (signals) → repository (app facade)
                       → wallhaven_client → dio
```

- `packages/wallhaven_client` is a **pure Dart package**: it never imports
  Flutter or any widget library. It could be published standalone.
- The app consumes it as a normal workspace dependency. Presentation code
  depends only on controllers/repositories and domain models — Dio, JSON,
  API keys, rate limits, and URL construction are invisible to widgets.
- The client is replaceable: a future provider would expose the same shape
  of results (`PaginatedResult<Wallpaper>`, typed errors) and slot in behind
  the repository without touching UI code.

## State management: signals

All state flows through the `signals` package (`Signal`/`computed`) with
`SignalBuilder` for scoped rebuilds:

- App-lifetime singletons (`SettingsController`, `FavoritesController`,
  `CollectionsController`) live in `get_it`; per-navigation feeds
  (`DiscoverController`, `SearchController`, `CollectionExploreController`)
  and detail controllers are created once per screen/route lifetime and
  disposed on pop.
- Rebuild scopes are kept narrow — tiles watch only membership tests, so a
  favorite tap rebuilds hearts, not grids.
- Controllers never write to signals after disposal; long-running work
  (downloads, in-flight page loads) is guarded by disposed flags and
  generation counters so stale responses cannot corrupt fresh state.

## Dio layer

All transport configuration lives in one file,
`packages/wallhaven_client/lib/src/http/dio_factory.dart` — the only place
a `Dio` is constructed. Interceptor order is load-bearing:

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
(Trade-off: one waiter cancelling its token fails all waiters sharing that
flight — documented in `RequestDeduper`.)

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

`PaginatedResult<T>` carries explicit metadata via `SearchMeta`
(`currentPage`, `lastPage`, `perPage`, `total`, random-search `seed`).
There is no automatic page crawling: the UI requests "next page" via
`client.nextPage(used, current)`.

Random sorting gets special treatment because Wallhaven assigns a seed to
prevent repeats across pages: when the first response's `meta.seed` exists,
`nextPage` propagates it automatically; an explicitly pinned seed on the
original request always wins (callers may be replaying a known sequence).

## Rate limiting

Sliding-window limiter over the trailing 60 s, capped at
`WallhavenConfig.requestsPerMinute`. Both the clock and the delay function
are constructor-injected, so tests simulate time without sleeping. On HTTP
429 the mapper parses `Retry-After` (seconds or RFC 1123 HTTP-date) into
`WallhavenRateLimitExceededException.retryAfter`; the client performs zero
automatic retries — backoff policy belongs to callers.

## Caching strategy

GET-only, 200-only TTL cache over an LRU-capped `InMemoryCacheStore`
(default 100 entries; expired entries evicted lazily on read). Key =
normalized method/path/percent-encoded-sorted query; auth headers are
excluded by design. `close()` drops every cached entry alongside the
transport. The `CacheStore` interface is the seam for a future persistent
cache — swap the store passed to `CacheInterceptor`, nothing else changes.

## Error contract

The client throws **only** `WallhavenException` subtypes — dio errors are
mapped by `error_mapper.dart`, and anything non-dio escaping the transport
is wrapped into `WallhavenNetworkException`. At the app boundary,
`lib/core/errors/error_messages.dart` pre-localizes exceptions into short,
user-facing strings so screens render messages verbatim without knowing the
exception taxonomy.

## Image pipeline

Grid tiles load the **original** image (`wallpaper.path`) because CDN
thumbnails are hard-cropped to fixed aspect ratios; decode width is clamped
per cell (`memCacheWidth`) so full-res photos cost cell-sized RAM while the
disk cache keeps the uncropped original for instant detail-screen reuse.
Placeholders use blurhash or wallpaper-derived colors; fades honor reduced
motion.

## Testing strategy

- **Fixtures** under `packages/wallhaven_client/test/fixtures/` mirror real
  Wallhaven payloads (including partial-tag and error bodies), so model
  tests exercise realistic JSON offline.
- **Fake adapter**: tests drive the *real* interceptor chain by replacing
  `dio.httpClientAdapter`, recording every request for assertions (URL,
  headers, call counts).
- **Injectable time**: clock + delay seams make rate-limit and TTL tests
  instant and deterministic.
- **Live suite** (`test/live/`) is gated behind `WALLHAVEN_LIVE=1` and makes
  ≤5 SFW requests; authenticated checks additionally need
  `WALLHAVEN_API_KEY`.
- **App layer**: widget tests fake at the repository seam to prove screens
  render counts/thumbnails/errors without network, inside the real M3E
  theme so build-time breakage fails loudly instead of showing a blank
  screen on device.

## Security posture

- Key storage: `flutter_secure_storage` v11 (Android
  EncryptedSharedPreferences-backed AES-GCM; iOS Keychain).
- Key transport: `X-API-Key` header only.
- Key visibility: redacted in logging; excluded from exceptions and caches;
  plaintext dropped from text fields immediately after save.
- `.gitignore` blocks `.env*` patterns; docs instruct env-var injection for
  live tests.

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

## Wallpaper setting: `packages/system_wallpaper`

First-party Android plugin replacing `async_wallpaper`. Four operations:

* Home / Lock / Both — `WallpaperManager.setStream` with
  `FLAG_SYSTEM`/`FLAG_LOCK` on `Dispatchers.IO` (no bitmap decode, no
  Picasso, no main-thread work).
* **Crop and set** — system picker via `getCropAndSetWallpaperIntent`
  (fallback `ACTION_ATTACH_DATA` → `SET_WALLPAPER` → `VIEW`), served from a
  `FileProvider` URI with `FLAG_GRANT_READ_URI_PERMISSION` + `ClipData`.

Plugin-owned (survives recreating `android/` — merged via manifest merger):
`SET_WALLPAPER` permission, `FileProvider` + `file_paths.xml`, and
package-visibility `<queries>` for the picker intents. `INTERNET` is **not**
owned by this plugin — it must still merge from the app manifest or another
plugin (verify with `grep INTERNET` on the merged manifest after builds).

### App-level Android overrides (must be re-applied after recreating android/)

Three behaviours cannot live in a plugin (the manifest merger cannot add
attributes to an app-declared activity, and Application-class injection
would break plugin composability):

1. `android:configChanges` including `colorMode|navigation|mcc|mnc` —
   wallpaper changes can alter systemui color overlays; without these flags
   the activity recreates.
2. `WallpaperApp.kt` — pre-warms and caches a `FlutterEngine`
   (`"main_engine"` in `FlutterEngineCache`) at app start.
3. `MainActivity.kt` — binds to the cached engine
   (`getCachedEngineId`, `shouldDestroyEngineWithHost = false`).
4. `compileSdk` / `minSdk` in `android/app/build.gradle.kts` — bumped to the
   maximum required by the app's Android plugins. **Not hardcoded**: the
   script reads each plugin's declared SDKs (via
   `.flutter-plugins-dependencies`, Flutter's own plugin registry) and takes
   the max, so re-running the script after a plugin raises its requirement
   self-heals the build.

The system picker (Pixel wallpaper app → MagicPortrait live wallpaper)
changes Runtime Resource Overlays (`systemui-dynamic.frro`), which forces
activity recreation regardless of `configChanges`. The cached engine makes
that recreation invisible: no splash, no navigation/state loss.

**After `rm -rf android && flutter create .`**, re-apply:

```bash
./tool/apply_android_overrides.sh
```

Canonical copies live in `tool/android_overrides/`; the script detects the
app's Kotlin package, rewrites `package` lines, patches the manifest, and is
idempotent.
