# Testing

The app is guarded by two layers:

| Layer | Location | Runs on | Purpose |
|---|---|---|---|
| Widget + contract | `test/` | Host (`flutter test`) | Fast, deterministic behaviour checks. The default feedback loop. |
| Integration | `integration_test/` | Emulator / device | Real engine, Hive, isolates and painting; fake network/platform boundaries. |
| Package boundaries | `packages/wallhaven_client/test`, `packages/system_wallpaper/test` | Host | Wire protocol, DTO parsing, rate limiting, native channel contracts. These are intentionally separate from app tests. |

## Commands

```sh
flutter test                                   # whole app suite (fast)
flutter test test/journeys/discover_test.dart  # one area while iterating
flutter analyze
flutter test --coverage                        # coverage/lcov.info
flutter test integration_test/app_journeys_test.dart -d <emulator-id>
(cd packages/wallhaven_client && dart test)    # client package
(cd packages/system_wallpaper && flutter test) # plugin package
```

The integration suite needs no network and no OS dialogs; any emulator works.

Currently **172 host tests** (journeys, widgets, contracts) plus **6
on-device integration journeys**, completing in ~15 s and ~65 s respectively.

Binary Android resources (launcher icon geometry/backgrounds, splash colours)
are checked by decoding the shipped PNGs: `test/widgets/launcher_icon_test.dart`,
`test/widgets/launch_transition_test.dart`. Generate icons with
`python3 tool/branding/build_icons.py`; `--check` fails when the shipped PNGs
are stale, so it belongs in CI next to `flutter analyze`.

## Layout

```
test/
  support/
    test_app.dart        # harness: real app + temp Hive + fake boundaries
    fake_wallhaven.dart  # scripted, recording Wallhaven transport
    fake_platform.dart   # recording storage / wallpaper / URL-launch fakes
    fixtures.dart        # deterministic API JSON
  journeys/              # user goals through the real widgets and routes
  widgets/               # reusable-widget contracts and accessibility
  contracts/             # concurrency/lifecycle rules impractical through UI
integration_test/
  app_journeys_test.dart # the critical journeys on a real device
```

## The harness (`test/support/test_app.dart`)

`appTest('does the thing', (tester, app) async { ... })` gives one isolated
app per test:

- fresh temporary Hive directory, real `SettingsStore`, `FavoritesRepository`
  and `CollectionsRepository` (JSON encoding and storage really run);
- the real `WallpaperApp`, router, screens, controllers and repository;
- a scripted `FakeWallhaven` as the only HTTP (see
  `app.network.searchHandler` / `detailHandler`), plus recording fakes for
  downloads, wallpaper applying, external links and the secure store;
- the bundled Outfit font and a 412×915 phone surface, so layout matches the
  real app instead of Flutter's square-metric test font;
- fake image responses, so nothing ever reaches the network;
- scripted dynamic-color channels (`io.material.plugins/dynamic_color` and
  the app's `.../dynamic_palette` push) so live palette behaviour is testable
  without a device.

`AppSnack` suppresses duplicate messages per `ScaffoldMessenger`, not per
process, so each launched app shell (and each test) gets fresh feedback state.

Useful helpers: `app.launch`, `app.restart`, `app.tap`, `app.persistTap`,
`app.enterText`, `app.act`, `app.settle`, `app.settleUntil`, `pumpUntil`,
`pumpFrames`, and the `app.network` / `app.storagePlatform` /
`app.wallpaperPlatform` / `app.urlLauncher` recorders.

### Two rules that keep the suite deterministic

1. **Use `app.persistTap`, not `tester.tap`, for anything that writes to
   Hive** (favorites, settings, collections, API key, download destination).
   It dispatches inside `tester.runAsync`, so the real I/O finishes before the
   next pump. Hive writes started in the fake-async zone leave their lock
   pending and hang later storage work.
2. **Use `app.tap` for everything else** (navigation, search chips, dialogs).
   Debounce timers started inside `runAsync` run on the wall clock, which no
   amount of `pump()` advances.

The async continuation keeps the zone it was awaited from, so the rule applies
to the tap that *opens* a writing dialog too: confirm a delete with
`persistTap` on both the trash button and the dialog's confirm button.
`app.persistTap` a route push whose screen writes when it pops.

The wallpaper detail info sheet rests at 30% height. Before tapping its action
row (download, `Set`, source link), scroll it like a user:

```dart
await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -300));
await pumpFrames(tester, 8, const Duration(milliseconds: 100));
```

Never use `pumpAndSettle` on a screen with an indeterminate loader; prefer
bounded `pumpFrames`/`pumpUntil`. `pumpUntil` fails with the visible text so a
broken screen explains itself.

## What to test when adding a feature

Write the failures first, then the happy path:

- first-load failure, retry, empty result, slow (held) response;
- a page/submit failure that must not discard content already on screen;
- stale responses after reload/dispose;
- persistence failure and what the UI does about it;
- leaving the screen mid-operation;
- narrow width (320 dp) and large text (`textScaleFactor` 1.3);
- exact request counts/parameters for anything that can spam the API.

Prefer visible labels, tooltips, semantics and stable `ValueKey`s. Assert
user-visible outcomes rather than widget-tree shape or pixels.

## Deliberately not covered

- Pixel-level visual polish (shapes, spacing, loader swatches) — better caught
  by screenshots/review than brittle assertions.
- Golden/screenshot diffs; there is no golden baseline in the repo.
- System dynamic-color *rendering* on a real OEM build: the channels and app
  reactions are tested, the device palette itself is not.
- Android's real document picker, MediaStore and `WallpaperManager`. The fakes
  assert the app's side of the contract; a manual smoke check is still needed
  after native changes.
- Live Wallhaven responses: `packages/wallhaven_client` keeps
  fixture-based tests plus an opt-in `live/` suite.
