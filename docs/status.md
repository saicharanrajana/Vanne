# Project Status

Last updated: 2026-08-23 — stabilization pass (all 8 original TODOs resolved + 8 new UX fixes).

## What is built and working

### Foundation
- **`packages/wallhaven_client`** — Dio transformer now `FusedTransformer(contentLengthIsolateThreshold: 0)` so every JSON response decodes via `compute` on a background isolate. Fallback String→JSON path also via `compute`. Added `compute` package dep — same package dio vendors internally.
- **`WallpaperRepository`** — unchanged request-translation / purity / NSFW logic.
- **Persistence** — Hive `SettingsStore` as before; `FavoritesRepository` JSON encode/decode now batched through `compute` (one isolate call for N favorites on restore, one per add). `FavoritesController.restore()`/`toggle()` now async; signal updates still land instantly before persistence.
- **DI** — `get_it` in `lib/app/dependencies.dart` (now awaits `favoritesController.restore()`).
- **State** — Signals 7 throughout; `FeedController` now drops intra-page duplicate IDs as well as cross-page ones (`seen.add` during scan). All controllers unchanged otherwise.

### Theme system (`lib/app/theme/`)
Unchanged — teal seed, Material You bridge, pitch-black ladder, Public Sans + Outfit.

### Navigation (`lib/app/router/app_route.dart`)
- `MainShell` navbar now `shapeFamily: square` (no rounded container), `backgroundColor: scheme.surface` opaque (no `surfaceContainer` alpha-tint), filled `selectedIcon`s (`fill: 1.0` per destination).
- Hero tags are now scoped per originating list (`discover-`, `search-`, `favorites-`, `category-<id>-`) to prevent collisions; `WallpaperTile.heroScope`, `WallpaperGrid.heroScope`, `WallpaperDetailScreen.heroScope`, `WallpaperDetailRoute.heroScope` carry the namespace. Deep-link routes default to `''` for compatibility.

### Screens
- **Discover** — heading + search bar → Search, filter chip → sheet, now a `CustomScrollView` with a collapsible `SliverToBoxAdapter` header. Scrolling down past 120 px hides the header (`SizeTransition` + `FadeTransition`, 220 ms, `easeOutCubic`); scrolling up or `ScrollEnd` restores it. Grid is `SliverMasonryGrid.count` via `WallpaperGrid.buildSlivers()` so the whole screen scrolls as one. Search bar has explicit `WidgetStatePropertyAll(EdgeInsetsDirectional(horizontal:14))` for correct icon/hint inset.
- **Categories** — same, now passes `category-<id>-` hero scope through grid + route.
- **Search** — no auto-submit on mount; pristine mounts show an `EmptyState` (clover + “Type a query or pick a color / genre”). `SearchController` now debounces reloads with a trailing `Timer(350 ms)` so rapid chip taps collapse to one request. `initialQuery` routes still run once. Same explicit search-bar padding as Discover.
- **Detail** — full Stack rewrite:
  - `Stack(fit: StackFit.expand)` with `Positioned.fill(_FullBleedImage)` (Hero + original image, placeholder is `SizedBox.expand`), `SafeArea` back/favorite row, and `PositionedDirectional(bottom:0, start:0, end:0, child: _InfoPanel)` floating on top with `surfaceContainerLow` and 28 dp top radius — wallpaper shows through the corner notches, image extends under the status bar.
  - `_InfoPanel`: `SignalBuilder` → `Column(min)` with 2×2 `_MetadataGrid` (Resolution/maximize, File size/hardDrive, Uploader/userRound, Favorites/heart — each row = icon 20 `primary` + value `titleMedium` + label `labelSmall` onSurfaceVariant), up to 3 tag chips + `+N` overflow, then `_ActionRow` inside the same container (arch Download | 150×68 filled Set | arch Open). Fixed the `_ArchAction` closure bug that returned the `SignalBuilder` widget itself (captured `idleIcon` instead).
  - Hero now uses the scoped tag and the same original URL as the grid, so flight pairs correctly; detail's original also serves as grid's disk-cache for instant open.
- **Favorites** — snapshots carry `path` (original) and render through the same grid (now with `surface` decode downsampling); `heroScope: favorites-`.
- **Settings / API key** — fixed: `_ThemeModeSelector` was a `Row` containing `M3ESegmentedButton` (which uses `width: double.infinity` inside `Flexible` segments and crashes under a Row's unbounded width). Restructured to a Column: label row, 12 dp gap, full-width segmented button. Screen verified on-device with every row rendering.

### Shared grid
- `WallpaperTile` now loads the **original** (`wallpaper.path`) uncropped at the metadata aspect ratio, with the cropped `small` thumb as the `placeholder` nested `CachedNetworkImage` so cells have instant content. `memCacheWidth` is computed per-screen from `(cellLogicalWidth * dpr).clamp(240,1440)` and passed down — full-res photos cost cell-sized RAM, disk cache still holds the original for detail reuse. Verified: `small` is always 300×200 and `lg` always 432×243 regardless of source ratio, so the original is the only ratio-preserving resource.
- `WallpaperGrid` refactored: `maybeTriggerLoadMore`, `buildSlivers()`, `CustomScrollView(controller:)`; skeleton is now `_SkeletonSliver` (`SliverMasonryGrid`). Default `build()` still works for non-collapsing hosts.

### Platform actions — unchanged
Download (`gal` → `Pictures/WallpaperApp`), set wallpaper (`async_wallpaper 3.1.0`), open source (`url_launcher`).

### Sheets (`lib/shared/widgets/app_sheet.dart` — new)
Central `AppSheet.decoration(context, color?)` returns `MaterialSheetDecoration(size: SheetSize.fit, color: scheme.surfaceContainerLow, shape: rounded 28 top, clipBehavior: antiAlias)`. Applied to both `showDiscoverFilterSheet` and `showSetWallpaperSheet`. Transparent default `DefaultSheetDecoration` is never used now.

### Verification
- `flutter analyze`: 0 errors, 0 warnings (3 `prefer_initializing_formals` infos kept intentionally).
- `flutter test` (app): **8/8 passing** — feed pagination/dedupe (incl. new intra-page duplicate test), grid rendering, retry, + 2 regression widget tests (`settings screen renders every row`, `detail action bar renders without error widget`).
- `wallhaven_client` `flutter test`: **80/80 passing**.
- Debug APK builds; launches on Pixel 9 (Android 17) with **zero** `E/flutter` exceptions at launch. Screenshots verified: Discover full uncropped portraits + square navbar, Settings fully rendered, Detail full-bleed with 2×2 panel + tags + actions, Search pristine empty state.
- Previous blank-screen root causes documented and covered by tests:
  - Download arch: Dart closure captured the reassigned `content` variable, returning the `SignalBuilder` widget itself → `debugWidgetBuilderValue` assertion.
  - Settings: `M3ESegmentedButton` in a horizontal `Row` received infinite-width constraints → `BoxConstraints(w=Infinity)` layout crash.

## Remaining / low-priority

1. **Integration test** (`integration_test/app_test.dart`) — rewritten for the new app but not yet run on a live device in CI.
2. Analyzer nits — the 3 `prefer_initializing_formals` infos are intentional (explicit field assignments kept for readability).

## Deliberate deviations from the original brief

| Original | Implemented | Reason |
|---|---|---|
| Downloads to `Downloads/WallpaperApp` | Gallery album `Pictures/WallpaperApp` via `gal` | Avoids owning MediaStore/SAF native code |
| Download-location setting | Removed | No SAF picker needed |
| async_wallpaper latest (3.2.0) | Pinned 3.1.0 | 3.2.0 Kotlin does not compile |
| Grid thumbnails (`small`/`lg`) | Original `path` at `memCacheWidth` + thumb placeholder | CDN thumbs are hard-cropped 300×200 / 432×243 for every ratio; original is the only uncropped source. Decode downsampling keeps RAM at cell size. |
| JSON on main isolate | All encode/decode via `compute` | Small per-call overhead accepted to guarantee no jank as payloads grow; transport uses `FusedTransformer(threshold:0)`, favorites batch in one call. |
| `packages/wallhaven_client` untouched | Dio + favorites now isolate-based | App-wide isolate discipline. |

## Key files

```
lib/app/            app.dart, dependencies.dart, router/app_route.dart,
                    theme/ (teal/pitch-black/typography)
lib/core/           domain/ (FeedFilter, AppCategory, FavoriteWallpaper),
                    wallpaper/ (repository, FeedController), downloads/, services/,
                    storage/, security/, errors/, favorites/ (now compute-based)
lib/features/       discover/ (CustomScrollView + SizeTransition header)
                    categories/ search/ (debounced, empty state) favorites/
                    settings/ (Column theme selector) wallpaper_detail/
                    (Stack full-bleed + floating panel)
lib/shared/widgets/ wallpaper_grid.dart (sliver refactor, memCacheWidth, heroScope),
                    wallpaper_tile.dart (original + thumb, heroScope),
                    app_sheet.dart (new, opaque decoration)
android/            minSdk 29, https VIEW query
packages/wallhaven_client/  dio_factory.dart (isolate transformer), wallhaven_client.dart (fallback compute)
test/               feed_controller_test.dart, screen_regression_test.dart (new)
```
