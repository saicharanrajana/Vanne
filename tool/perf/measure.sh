#!/usr/bin/env bash
# Bounded on-device performance probe for vanne profile builds.
#
# Measures three things that regress easily and are invisible in `flutter test`:
#   1. Android activity startup – `am start -W` TotalTime (platform launch
#      timing: when the system considers the activity started/shown). It is
#      NOT the Flutter engine's first frame and NOT "content ready";
#      see docs/performance.md for how to measure those separately.
#   2. idle   – presented frames + app CPU while the UI is at rest
#   3. scroll – presented/dropped/janky frames and the frame-cadence histogram
#
# Frames come from SurfaceFlinger TimeStats. Do NOT use `dumpsys gfxinfo` for
# Flutter: frames bypass HWUI and it reports 0.
#
# Usage:
#   tool/perf/measure.sh <serial> [label] [start-runs] [flings]
# Example:
#   flutter build apk --profile --target-platform android-arm64
#   adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-profile.apk
#   tool/perf/measure.sh emulator-5554 "final" 5 10
#
# Run it on a quiet host: builds/tests on the same machine move cold start by
# seconds. Interpreting results: docs/performance.md.
set -u

SER=${1:?usage: measure.sh <serial> [label] [start-runs] [flings]}
LABEL=${2:-run}
RUNS=${3:-5}
FLINGS=${4:-10}
PKG=${PKG:-com.saicharanrajana.vanne}
A="adb -s $SER"

# Hard failures. Scroll numbers without a Flutter surface layer or without its
# cadence histogram are meaningless, so they never degrade to a silent skip.
EXIT_NO_CADENCE=2   # surface layer or present2present histogram missing
EXIT_WRONG_LAYER=3  # a block was read but it is not a Flutter surface layer

# >>> perf-helpers
# Pure text helpers. Kept dependency-free so they can be exercised against
# captured dumps (see docs/performance.md) without a device.

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

# Prints the complete TimeStats block for the app's Flutter render surface.
#
# Two things matter here:
#   * the block runs to the next layer header (or EOF), so every histogram line
#     is kept — truncating at a counter such as averageFPS used to drop the
#     cadence histograms that follow it;
#   * only Flutter's `SurfaceView[...](BLAST)` layer is a frame source. A dump
#     also contains other layers mentioning the package (the activity window,
#     `Splash Screen <pkg>`), and picking the first match would silently report
#     the wrong layer. When no surface layer is present the extractor prints
#     nothing: that means "no Flutter frames this window", which callers must
#     treat as idle (pass) or as a failed scroll measurement (hard error).
extract_layer_block() {
  awk '
    { line[NR] = $0 }
    /^layerName = / {
      if ($0 ~ /SurfaceView\[[^]]*vanne[^]]*\]/ && !chosen) chosen = NR
    }
    END {
      if (!chosen) exit
      for (i = chosen; i <= NR; i++) {
        if (i > chosen && line[i] ~ /^layerName = /) break
        print line[i]
      }
    }
  '
}

# Expected frame interval bucket, floor(1000 / refreshRate). SurfaceFlinger
# reports integer-millisecond buckets: 120 fps -> "8ms", 60 fps -> "16ms".
expected_interval_ms() { # <refresh rate, e.g. 60.000004 or 120>
  awk -v r="${1:-}" 'BEGIN {
    if (r == "") { exit }
    v = 1000 / r
    if (v > 0) printf "%d", v
  }'
}

# Header line of the layer block that extract_layer_block selected.
layer_header() { head -1; }

# Reads the first histogram named <label> out of a layer block on stdin and
# prints "frames=<n> at<interval>ms=<n> (<pct>%) buckets=<k=v,…>".
# Exits non-zero when the histogram is absent, so callers can fail loudly.
read_histogram() { # <block-file> <label> <expected-interval-ms|"">
  python3 - "$1" "$2" "${3:-}" <<'PY'
import re
import sys

path, label, expected = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8", errors="replace").read()

m = re.search(
    r"^" + re.escape(label) + r" histogram is as below:\s*\n(.*)$",
    text,
    re.MULTILINE,
)
if not m:
    sys.exit(3)

# One histogram line of "0ms=0 1ms=0 …" pairs, up to the next "…histogram"
# label or end of the block.
line = m.group(1).splitlines()[0] if m.group(1).strip() else ""
buckets = {int(k): int(v) for k, v in re.findall(r"(\d+)ms=(\d+)", line)}
if not buckets:
    sys.exit(3)

total = sum(buckets.values())
nonempty = sorted((k, v) for k, v in buckets.items() if v)
parts = [f"frames={total}"]
if expected:
    on = buckets.get(int(expected), 0)
    parts.append(
        f"at{expected}ms={on} ({on * 100 // max(total, 1)}%)"
    )
parts.append(f"buckets={nonempty[:8]}")
print("  " + " ".join(parts))
PY
}
# <<< perf-helpers

# Full layer block from the device, or from MEASURE_DUMP_FILE for offline
# replay of a captured `dumpsys SurfaceFlinger --timestats -dump`.
layer_block() {
  if [ -n "${MEASURE_DUMP_FILE:-}" ]; then
    extract_layer_block <"$MEASURE_DUMP_FILE"
  else
    $A shell "dumpsys SurfaceFlinger --timestats -dump -maxlayers 12" 2>/dev/null |
      extract_layer_block
  fi
}

# Counters only; cadence is read separately from the saved block.
block_counters() {
  grep -E "totalFrames|droppedFrames|lateAcquireFrames|badDesiredPresentFrames|jankyFrames|averageFPS" |
    sed 's/^/  /'
}

app_cpu() {
  local pid
  pid=$($A shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  [ -z "$pid" ] && { echo "n/a (app not running)"; return; }
  $A shell "top -b -n 1 -p $pid -o %CPU 2>/dev/null | tail -1" | tr -d '\r'
}

window_idle() { # <seconds>
  $A shell "dumpsys SurfaceFlinger --timestats -clear" >/dev/null 2>&1
  sleep "$1"
  local block
  block=$(layer_block)
  if [ -z "$block" ]; then
    # SurfaceFlinger omits layers with no frames in the window: that is the
    # pass condition for an idle UI.
    echo "0 frames (layer idle this window)"
  else
    echo "- layer: $(printf '%s\n' "$block" | layer_header)"
    printf '%s\n' "$block" | block_counters | tr '\n' ' '
    echo
  fi
}

REFRESH=$($A shell dumpsys display 2>/dev/null | grep -oE 'renderFrameRate [0-9.]+' |
  head -1 | grep -oE '[0-9.]+')
EXPECTED_MS=$(expected_interval_ms "$REFRESH")

$A shell "dumpsys SurfaceFlinger --timestats -enable" >/dev/null 2>&1

echo "## $LABEL"
echo "- device: $($A shell getprop ro.product.model | tr -d '\r') api=$($A shell getprop ro.build.version.sdk | tr -d '\r')"
echo "- refresh: ${REFRESH:-unknown} Hz"
echo "- host load: $(uptime | sed 's/.*load average/load/')"

echo
echo "### Android activity startup (am start -W TotalTime, ms)"
echo "  platform launch timing — not the engine's first frame, not content-ready"
starts=()
for _ in $(seq 1 "$RUNS"); do
  $A shell am force-stop "$PKG"
  sleep 1
  t=$($A shell am start -W -n "$PKG/.MainActivity" 2>&1 |
    grep -oE "TotalTime: [0-9]+" | grep -oE "[0-9]+")
  starts+=("${t:-0}")
  echo "- run: ${t:-?}"
  sleep 1
done
printf '%s\n' "${starts[@]}" | sort -n | awk '
  {a[NR]=$1}
  END {
    if (NR == 0) { print "- min/median/max: n/a"; exit }
    med = (NR % 2) ? a[(NR + 1) / 2] : int((a[NR / 2] + a[NR / 2 + 1]) / 2)
    printf "- min %d / median %d / max %d (n=%d)\n", a[1], med, a[NR], NR
  }'

# The startup loop above leaves the feed loading; let content settle so this
# window measures a resting UI instead of launch animation.
sleep 3
echo
echo "### idle, current screen (3 s settle, 4 s window)"
echo "- frames: $(window_idle 4)"
echo "- app cpu%: $(app_cpu)"

echo
echo "### scroll ($FLINGS flings)"
block_file=$(mktemp "${TMPDIR:-/tmp}/vanne_fling.XXXXXX")
trap 'rm -f "$block_file"' EXIT
$A shell "dumpsys SurfaceFlinger --timestats -clear" >/dev/null 2>&1
s=$(now_ms)
for _ in $(seq 1 "$FLINGS"); do
  $A shell input swipe 540 1900 540 700 100
  sleep 0.15
done
e=$(now_ms)
echo "- window: $((e - s)) ms"
layer_block >"$block_file"
if [ ! -s "$block_file" ]; then
  echo "ERROR: no Flutter SurfaceView layer block for $PKG after $FLINGS flings." >&2
  echo "       Either the app is not foreground/rendering, or SurfaceFlinger" >&2
  echo "       changed its layer naming. Run with MEASURE_DUMP_FILE=<dump> to" >&2
  echo "       replay a captured 'timestats -dump' and inspect the extraction." >&2
  exit "$EXIT_NO_CADENCE"
fi
echo "- layer: $(layer_header <"$block_file")"
if ! grep -q '^layerName = .*SurfaceView\[' "$block_file"; then
  echo "ERROR: the captured block is not a Flutter SurfaceView layer." >&2
  echo "       Refusing to report frames from another layer." >&2
  exit "$EXIT_WRONG_LAYER"
fi
block_counters <"$block_file"
if ! read_histogram "$block_file" present2present "$EXPECTED_MS"; then
  echo "ERROR: present2present histogram missing from the layer block." >&2
  echo "       Scroll cadence cannot be reported; captured block follows." >&2
  sed 's/^/  | /' "$block_file" >&2
  exit "$EXIT_NO_CADENCE"
fi

echo
echo "### idle after scroll settles (2 s settle, 3 s window)"
sleep 2
echo "- frames: $(window_idle 3)"
