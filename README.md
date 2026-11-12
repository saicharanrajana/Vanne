# Vanne

An open-source, Android-first wallpaper application backed by the
[Wallhaven API](https://wallhaven.cc/help/api), built with Flutter and
Material 3 Expressive.

Browse and search thousands of wallpapers, organize them into collections,
save favorites offline, download originals to your gallery, and set them as
home/lock screen backgrounds — all with full-resolution images, a
wallpaper-derived color theme on the detail screen, and secure optional
API-key storage.

## Features

- **Discover** — infinite masonry feed with a collapsible header and filter
  sheet (purity, portrait-only).
- **Search** — power-user query syntax plus dominant-color chips and genre
  chips; rapid input is debounced into single requests.
- **Collections** — bookmark a tag or color grid to save it as a square card,
  with a stable wallpaper cover, readable color names, and multi-select
  deletion. Four curated cards ship with bundled covers on first install.
- **Favorites** — persisted snapshots that render fully offline, even if the
  wallpaper disappears from Wallhaven.
- **Detail** — full-bleed hero, draggable info sheet with metadata cards,
  dominant-color palette (tap to copy hex), expandable tags, download to
  gallery, set as home/lock/both wallpaper, open source page.
- **Settings** — Material You / custom themes (teal seed + pitch-black
  ladder), cache management, optional Wallhaven API key stored in platform
  secure storage.

## Credits

Bundled collection covers are CC0/public-domain works; see
[`docs/collection-covers.md`](docs/collection-covers.md) for sources and
licences.

Inspired by [BunPod](https://github.com/kamranbekirovyz/bunpod) by
[Kamran Bekirov](https://kamranbekirov.com) — its feature-first project
layout and Material 3 Expressive component ideas shaped this app's
architecture.

## Getting started

Requirements:

- [Flutter](https://docs.flutter.dev/get-started/install) (Dart SDK ^3.13.1)
- An Android device or emulator (primary target)

```bash
git clone <repo-url> && cd vanne
flutter pub get          # resolves the root app + packages/wallhaven_client workspace
flutter run              # debug launch on a connected device/emulator
```

### Running tests

```bash
flutter test                                   # app unit & widget tests

cd packages/wallhaven_client && flutter test    # client unit suite (offline)
```

Opt-in live integration tests hit the real Wallhaven API (≤5 SFW requests):

```bash
cd packages/wallhaven_client
WALLHAVEN_LIVE=1 flutter test test/live/live_wallhaven_test.dart

# Authenticated checks additionally need:
WALLHAVEN_LIVE=1 WALLHAVEN_API_KEY=your-key flutter test test/live/
```

Never commit your key — export it in your shell or use a git-ignored `.env`;
CI must inject secrets, never store them.

## Architecture at a glance

```
presentation (screens) → controllers (signals) → repository (app facade)
                       → wallhaven_client → dio
```

Key decisions:

- **`packages/wallhaven_client`** — pure Dart API client: typed models,
  interceptor chain (API key → TTL cache → sliding-window rate limit →
  redacted logging), request deduplication, explicit pagination with
  random-seed propagation, and an exceptions-only error hierarchy.
- **signals everywhere** — reactive state with narrowly scoped rebuilds;
  per-navigation controllers are created once per route and disposed on pop.
- **material_ui over flutter/material** — the app runs on the decoupled
  Material widget tree; mixing the two silently breaks theme lookups.
- **Security** — the optional API key lives only in platform secure storage
  and process memory, travels in a header, and is redacted from logs.

Full details, rationale, and conventions live in [ARCHITECTURE.md](ARCHITECTURE.md).

## Project layout

```
lib/
  app/                 bootstrap, DI (get_it), router (zenrouter), theme
  core/                domain models, repositories, downloads, services,
                       storage (Hive), security (secure storage)
  features/            one folder per feature (application + presentation):
                       discover, search, collections, favorites,
                       wallpaper_detail, settings
  shared/              reusable widgets, extensions, utils
packages/
  wallhaven_client/    standalone Dart Wallhaven API client (+ its own suite)
test/                  app unit & widget tests
integration_test/      end-to-end device test
```

## Status

Stable daily-driver feature set: discover/search/collections/favorites,
download & apply wallpapers, theming, secure key management. Known
follow-ups are tracked in the repository issue tracker.
