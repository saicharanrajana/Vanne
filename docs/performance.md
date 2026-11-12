# Performance

How to measure this app, what the numbers should look like, and what has
already been measured. Two properties matter and both regress silently:

1. **The UI must be idle when nothing is animating.** A single always-mounted
   indeterminate indicator keeps a repeating ticker alive, which schedules a
   frame forever — invisible in tests, catastrophic for battery.
2. **Cold start must paint something immediately.** Startup work belongs off
   the first-frame path; the window must never stay blank while storage opens.

Run `tool/perf/measure.sh` before/after a change that touches the feed, the
shell, startup, or theming.

## Metrics and how they are obtained

| Metric | Source | Notes |
| --- | --- | --- |
| Android activity startup | `adb shell am start -W -n com.saicharanrajana.vanne/.MainActivity`, `TotalTime` | **Platform launch timing only** — when Android's activity manager considers this activity started/shown. It is not the Flutter engine's first frame, not "fully drawn by Flutter", and not content-ready; it also includes system-side work the app does not control. Report min/median/max over ≥5 runs on a quiet host. |
| First frame (engine) | VM-service timeline: process start from `/proc/<pid>/stat` field 22 vs the first `Animator::BeginFrame` `ts` (both CLOCK_MONOTONIC) | "The engine began a frame". What the user *sees* can lag this by a frame or two, and it says nothing about content. See recipe below. |
| Content-ready phases | `screencap` sampling (~110 ms) plus the timeline frame list | Splash/shell/first-photo boundaries. Approximate, and capture itself costs CPU. |
| Visible phases | `screencap` sampling every ~110 ms, classified by PNG size | ±1 sample. Screencap itself competes for CPU, so treat as approximate. |
| Idle | `dumpsys SurfaceFlinger --timestats -clear`, wait 4 s, `-dump -maxlayers 12` | Expect **0 frames**. Also check `top -p <pid> -o %CPU`: expect ~0. |
| Scroll | same TimeStats during scripted flings | Look at `droppedFrames`, `lateAcquireFrames`, `badDesiredPresentFrames`, `jankyFrames`, `averageFPS`, `present2present` histogram. |

**Do not use `dumpsys gfxinfo` for Flutter.** Flutter frames bypass HWUI, so it
reports `Total frames rendered: 0`. SurfaceFlinger TimeStats is the platform
instrument that works.

**Do not trust a VM timeline poll loop as an FPS source.** Polling
`getVMTimeline` while scrolling silently loses events when the ring buffer
wraps (observed 5.8 fps where SurfaceFlinger measured 118 fps). Use it only for
timestamps (first frame), not for counts.

## Emulator recipe

The measurement target is a disposable headless AVD, so results are repeatable
and the phone stays out of it:

```bash
emulator -avd Vanne_API35 -no-window -no-audio -no-boot-anim -no-snapshot \
         -gpu host -no-metrics -port 5554
adb -s emulator-5554 wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done'
flutter build apk --profile --target-platform android-arm64
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-profile.apk
tool/perf/measure.sh emulator-5554 "my change" 5 10
```

AVD `Vanne_API35`: API 35, `google_apis`, `arm64-v8a`, 1080×2400 @ 420 dpi,
**60 Hz**, 2 GB RAM, `disk.dataPartition.path=<temp>` (app data does not
survive an emulator restart — do a warm-up launch before timing).
Rendering: `-gpu host` → OpenGL ES Translator on Metal; Flutter logs
`Using the Impeller rendering backend (OpenGLES)` (not Vulkan).

### Limits — read before comparing to a phone

* **60 Hz** ⇒ 16.7 ms budget. The 120 Hz budget (8.3 ms) cannot be verified here.
* Host GPU translation + API 35's GLES 3.1 expectation (host exposes 3.0): raster
  cost is a proxy, not a match. Absolute ms are not phone ms.
* No thermal throttling, no AMOLED, no battery, no wallpaper-driven dynamic color.
* No accessibility service on the emulator ⇒ Flutter's semantics tree stays off.
  On a real device with TalkBack/accessibility on, every frame also regenerates
  semantics (measured ~30 % of frame CPU on a Pixel 9) — budget for it.
* Host CPU is shared. A `flutter test` or Gradle run during a measurement moved
  cold start from ~590 ms to 1.3–4.8 s in this repo. Check `uptime` (load < ~2)
  and discard the first run.

## First-frame recipe (dependency-free)

```bash
PKG=com.saicharanrajana.vanne; A="adb -s emulator-5554"
$A shell am force-stop $PKG; $A logcat -c
$A shell am start -n $PKG/.MainActivity
pid=$($A shell pidof $PKG | tr -d '\r')
start_us=$(( $($A shell cat /proc/$pid/stat | awk '{print $22}') * 10000 ))   # ticks (10 ms) -> µs
uri=$($A logcat -d | grep -o 'http://127.0.0.1:[0-9]*/[^ ]*' | head -1)      # profile builds expose the VM service
```

Then read the timeline from the VM service (`setVMTimelineFlags(['Embedder'])`,
`getVMTimeline`, first event named `Animator::BeginFrame`) and subtract
`start_us`. `flutter run --profile --trace-startup` writes
`build/start_up_info.json` with a similar breakdown, but it is unreliable over
wireless adb.

## What the harness refuses to report

`tool/perf/measure.sh` never degrades a broken measurement into a silent one:

* A TimeStats dump contains several layers whose names mention the package
  (`com.saicharanrajana.vanne/MainActivity#…`, `Splash Screen com.saicharanrajana.vanne#…`).
  Only Flutter's `SurfaceView[…](BLAST)` layer is a frame source, so the script
  selects that layer explicitly and prints which one it used. Earlier it took the
  first `vanne` match, which could silently report the splash or activity window.
* The whole layer block is captured, not just the counters. Truncating at
  `averageFPS` dropped the `present2present` histogram that follows it, so
  cadence was silently omitted.
* Scroll with no Flutter surface layer exits **2**; a block that is not a
  `SurfaceView` layer exits **3**; a missing `present2present` histogram makes
  `read_histogram` exit 3, which `measure.sh` turns into exit **2** and echoes
  the captured block to stderr. Absent layers during an *idle* window are the
  pass condition (SurfaceFlinger omits layers that presented no frames).
* `MEASURE_DUMP_FILE=<dump>` replaces the layer dump with a captured
  `dumpsys SurfaceFlinger --timestats -dump` file (the rest of the script still
  talks to the device). For purely offline parsing, evaluate the helper block
  and feed it a dump:

  ```bash
  capture: adb -s emulator-5554 shell "dumpsys SurfaceFlinger --timestats -dump -maxlayers 12" > dump.txt
  eval "$(sed -n '/^# >>> perf-helpers$/,/^# <<< perf-helpers$/p' tool/perf/measure.sh)"
  extract_layer_block < dump.txt > block.txt
  read_histogram block.txt present2present 16   # nonzero (3) when cadence is absent
  ```

  The helpers are validated against: a real 60 Hz block captured on
  `emulator-5554`, a real 120 Hz full dump (Pixel), a multi-layer dump where the
  package's activity and splash layers precede the surface layer, a dump with no
  surface layer at all, and a counters-only block with no histogram.

## Recorded results

Profile builds, arm64, `emulator-5554` (60 Hz, Impeller GLES), quiet host
(load ~1.5), fresh install warmed once. Every number in this table was captured
on the emulator; nothing here is a physical-device post-fix measurement.

| Metric | `b4ebd00` (before) | final worktree (footer gating + startup shell + bundled fonts) |
| --- | --- | --- |
| Cold start, min/median/max ms (n) | 638 / 710 / 852 (5) | **573 / 587 / 598 (7)** |
| First frame, engine timeline | not measured separately (first frame *was* after bootstrap) | **224 ms, 255 ms** (n=2) |
| Shell + skeleton visible | ≈ same as cold start | **≈ 0.7–0.9 s** |
| First wallpaper photos | not measured | **≈ 1.5–1.6 s**; settled ≈ 1.8–2.0 s |
| Idle, Discover (4–5 s window) | 300 frames / 5 s (62 fps), CPU 12 % | **0 frames, CPU 0.0 %** |
| Idle, Collections / Favorites / Settings | 62 fps each (offstage ticker) | **0 frames each, CPU 0.0 %** |
| Idle on a pushed route (detail) | 1 fps | 0 frames |
| Scroll, 10 flings (3 windows) | 164 frames, dropped 0, janky 0 | 163 / 165 / 163 frames, dropped 0, lateAcquire 0, janky 0, 61.9 fps avg, present2present 63–71 % at 16 ms, rest 13–19 ms |

Root cause of the "before" idle numbers, found with
`debugPrintScheduleFrameStacks` + `ext.flutter.debugDumpApp`:
`_GridFooter` mounted an indeterminate `M3ELoadingIndicator` for the entire
life of an infinite feed (`material_3_expressive` drives it with
`repeat()`), and the tab stack keeps every tab mounted, so one spinner kept the
whole app at 120 fps. The footer now renders a static `SizedBox` unless a page
is actually in flight.

Reference from a physical device — **pre-fix build only**. These are the numbers
that motivated the work; there are **no post-fix measurements on physical
hardware**, so the gains above are verified on the emulator only. The Pixel
figures are also not comparable to the emulator rows (different refresh rate,
GPU path and accessibility state).

Pixel 9, 120 Hz, profile build of `b4ebd00` (before the fixes):

* first frame 1.72–1.76 s (quiet) / 3.03 s (post-install, loaded host)
* idle on the shell: 125 fps, 93.3 % CPU (accessibility service active, so the
  semantics tree was in play); scroll: 641 frames / 5.59 s, 0 dropped, 118 fps,
  95 % of frames at 8 ms

Fonts: `assets/fonts/Outfit-Variable.ttf` (110,884 B) and `OFL.txt` are inside
the APK under `assets/flutter_assets/assets/fonts/`, registered in `pubspec.yaml`
for weights 400/500/600/700/800, so the first frame never waits on
`fonts.gstatic.com`. Weight comes from ordinary `TextStyle.fontWeight`: the
engine resolves it to the variable font's `wght` axis natively (verified on the
emulator — `copyWith(w700)` measured the same width as an explicit
`FontVariation('wght', 700)`, and `copyWith(w800)` is a distinct, heavier
instance). No style sets an explicit `fontVariations`, which would pin derived
styles to the base weight. `lib/` no longer references `google_fonts` at
runtime.

## Regression gates

Fail the change if any of these regress on the emulator:

* idle on **every** tab and on a pushed route: **0 frames** in a 3–4 s window, app CPU < 2 %
* Android activity startup (`am start -W TotalTime`) median worse than the recorded
  587 ms by more than ~15 % (quiet host)
* scroll: `droppedFrames` > 0, `jankyFrames` > 0, or fewer than 60 % of frames at the display cadence
* first frame (engine timeline) later than ~350 ms

On a real 120 Hz device the stricter bar applies: ≥95 % of scroll frames at
8.3 ms and idle at 0 fps / < 5 % CPU.

## Not covered here

Frame-level raster profiling (`--trace-skia`), memory/RSS budgets, network
latency, download throughput, and the apply-wallpaper plugin path. The image
cache policy (256 MB / 4000 entries in `lib/main.dart`) is unvalidated for RSS
on low-RAM devices and is worth a follow-up measurement.
