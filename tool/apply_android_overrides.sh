#!/usr/bin/env bash
# Applies the app-level Android overrides required by this app.
#
# WHY THIS EXISTS
# ---------------
# Most wallpaper behaviour lives in the first-party plugin
# (packages/system_wallpaper): SET_WALLPAPER permission, FileProvider,
# package-visibility <queries>, and all Kotlin plugin code. Those merge into
# the app automatically and survive recreating the android/ folder.
#
# Three things CANNOT live in a plugin (manifest merger cannot add attributes
# to an app-declared activity; Application class injection would break
# composability), so they are app-level:
#   1. android:configChanges incl. colorMode|navigation|mcc|mnc
#      - prevents recreation on wallpaper-triggered config changes
#   2. WallpaperApp.kt — pre-warms/caches the FlutterEngine ("main_engine")
#      - survives the Runtime Resource Overlay (RRO) recreation that the
#        system wallpaper picker (MagicPortrait / dynamic color) triggers
#   3. MainActivity.kt — binds to the cached engine so recreation is invisible
#   4. compileSdk / minSdk — bumped to the max required by the app's plugins
#      (inferred from each plugin's Android build file via
#      .flutter-plugins-dependencies; nothing is hardcoded here, so the script
#      self-heals when plugins raise their requirements — just re-run it)
#   5. res/ launch + icon resources — the day/night launch colour, the API 31+
#      splash theme, and the launcher icon colour. `flutter create` restores
#      the template splash and the stock Flutter logo, which would desync
#      Android's launch window from Flutter's first frame
#      (lib/app/launch_background.dart) and from the app icon. Launcher icon
#      bitmaps are regenerated from the checked-in masters by
#      tool/branding/build_icons.py (see step 1c).
#
# WHEN TO RUN
# -----------
# After deleting + recreating the android/ folder:
#   rm -rf android && flutter create . --platforms=android --org <your-org>
#   ./tool/apply_android_overrides.sh
#
# Idempotent: safe to run any number of times. Detects the app's Kotlin
# package from the existing MainActivity (works with any org/app name).
#
# TODO(guard): add a startup runtime check so forgetting to run this script is
#  caught automatically — a `verifyOverrides` MethodChannel method in
#  SystemWallpaperPlugin.kt (checks FlutterEngineCache for "main_engine")
#  called from bootstrap() in lib/app/dependencies.dart, warning in debug
#  builds. Both sides carry matching TODOs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERRIDES="$ROOT/tool/android_overrides"
MANIFEST="$ROOT/android/app/src/main/AndroidManifest.xml"

if [ ! -f "$MANIFEST" ]; then
  echo "error: android/ folder not found — run 'flutter create .' first" >&2
  exit 1
fi

# Detect the app's Kotlin package + MainActivity location.
EXISTING_MAIN="$(find "$ROOT/android/app/src/main/kotlin" -name 'MainActivity.kt' 2>/dev/null | head -1)"
if [ -z "$EXISTING_MAIN" ]; then
  echo "error: MainActivity.kt not found under android/app/src/main/kotlin" >&2
  exit 1
fi
KOTLIN_DIR="$(dirname "$EXISTING_MAIN")"
APP_PACKAGE="$(sed -n 's/^package \([A-Za-z0-9_.]*\)$/\1/p' "$EXISTING_MAIN" | head -1)"
if [ -z "$APP_PACKAGE" ]; then
  echo "error: could not read package declaration from $EXISTING_MAIN" >&2
  exit 1
fi
echo "detected package: $APP_PACKAGE"

# 1. Copy Kotlin sources, rewriting the package declaration to the detected one.
mkdir -p "$KOTLIN_DIR"
for file in MainActivity.kt WallpaperApp.kt; do
  sed "s/^package com\.saicharanrajana\.vanne$/package $APP_PACKAGE/" \
    "$OVERRIDES/$file" > "$KOTLIN_DIR/$file"
done
echo "ok: MainActivity.kt + WallpaperApp.kt (cached FlutterEngine)"

# 1b. Copy launch/splash resources (day + night colour, drawables, API 31+
#     splash theme) so Android's launch window keeps matching Flutter's first
#     frame (lib/app/launch_background.dart) after `flutter create`.
RES_OVERRIDES="$OVERRIDES/res"
if [ -d "$RES_OVERRIDES" ]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$RES_OVERRIDES"/}"
    mkdir -p "$ROOT/android/app/src/main/res/$(dirname "$rel")"
    cp "$src" "$ROOT/android/app/src/main/res/$rel"
  done < <(find "$RES_OVERRIDES" -type f -print0)
  echo "ok: res/ launch resources (colour + splash theme)"
fi

# 1c. Regenerate launcher icons (adaptive foreground, themed monochrome, legacy
#     day/night bitmaps) from assets/branding/*.png. `flutter create` restores
#     the stock Flutter logo, and the icons are not hand-maintained: the script
#     is the single reproducible source (and `--check` verifies them in CI).
python3 "$ROOT/tool/branding/build_icons.py"

# 2. Patch app/build.gradle.kts: compileSdk / minSdk = max required by plugins.
#    Requirements are inferred (not hardcoded): each Flutter plugin declares
#    its compileSdk/minSdk in its android/build.gradle[.kts]; the plugin list
#    comes from .flutter-plugins-dependencies (Flutter's own registry, written
#    by `flutter pub get`). Current numeric values act as a floor so the script
#    never regresses, and symbolic template values (flutter.compileSdkVersion)
#    are replaced only when a plugin requires more.
GRADLE_KTS="$ROOT/android/app/build.gradle.kts"
python3 - "$GRADLE_KTS" "$ROOT" <<'PY'
import json, os, re, sys

gradle_path, root = sys.argv[1], sys.argv[2]

with open(gradle_path) as f:
    src = f.read()

def plugin_requirements():
    """Max compileSdk/minSdk declared across the app's Android plugins."""
    deps_file = os.path.join(root, ".flutter-plugins-dependencies")
    req = {"compileSdk": 0, "minSdk": 0}
    try:
        with open(deps_file) as f:
            plugins = json.load(f)["plugins"]["android"]
    except (FileNotFoundError, KeyError, ValueError):
        return req
    for plugin in plugins:
        for name in ("build.gradle.kts", "build.gradle"):
            path = os.path.join(plugin["path"], "android", name)
            try:
                with open(path) as f:
                    text = f.read()
            except FileNotFoundError:
                continue
            for field in req:
                m = re.search(rf"{field}(?:Version)?\s*=?\s*(\d+)", text)
                if m:
                    req[field] = max(req[field], int(m.group(1)))
            break
    return req

required = plugin_requirements()

def current_value(field):
    m = re.search(rf"^\s*{field}\s*=\s*(\d+)\s*$", src, re.M)
    return int(m.group(1)) if m else None  # None → symbolic or absent

for field in ("compileSdk", "minSdk"):
    current = current_value(field)
    need = required[field]
    if need == 0:
        print(f"ok: {field} — no plugin requirement found, leaving as-is")
        continue
    if current is not None and current >= need:
        print(f"ok: {field} already {current} (>= plugin max {need})")
        continue
    new, n = re.subn(
        rf"^(\s*){field}\s*=[^\n]*$",
        rf"\g<1>{field} = {need}",
        src,
        count=1,
        flags=re.M,
    )
    if n == 0:
        print(f"error: {field} line not found in build.gradle.kts", file=sys.stderr)
        sys.exit(1)
    src = new
    print(f"ok: {field} → {need} (plugin max; was {current or 'symbolic'})")

with open(gradle_path, "w") as f:
    f.write(src)
PY

# 3. Patch the manifest: Application class, predictive back, and configChanges.
#    Use python for reliable in-place edits across macOS/Linux.
python3 - "$MANIFEST" <<'PY'
import re, sys

path = sys.argv[1]
with open(path) as f:
    src = f.read()

# a) Application class → .WallpaperApp (relative name works for any package;
#    matches both ${applicationName} and any existing android:name value).
src, n_name = re.subn(
    r'(<application\b[^>]*?)android:name="[^"]*"',
    r'\1android:name=".WallpaperApp"',
    src,
    count=1,
)
if n_name == 0:
    # No android:name on <application> at all — insert after the tag opening.
    src, n_name = re.subn(
        r'(<application\b)',
        r'\1\n        android:name=".WallpaperApp"',
        src,
        count=1,
    )

# b) predictive back must remain enabled after regenerating Android.
def patch_predictive_back(m):
    tag = m.group(0)
    attribute = 'android:enableOnBackInvokedCallback="true"'
    if 'android:enableOnBackInvokedCallback=' in tag:
        return re.sub(
            r'android:enableOnBackInvokedCallback="[^"]*"',
            attribute,
            tag,
            count=1,
        )
    return tag[:-1] + '\n        ' + attribute + '>'

src, n_predictive = re.subn(
    r'<application\b[^>]*>',
    patch_predictive_back,
    src,
    count=1,
)

# c) configChanges must include colorMode|navigation|mcc|mnc (wallpaper
#    changes can trigger colorMode/uiMode config changes → recreation).
required = {"colorMode", "navigation", "mcc", "mnc"}

def patch_config(m):
    tag, attrs = m.group(1), m.group(2)
    match = re.search(r'android:configChanges="([^"]*)"', attrs)
    if match:
        have = set(match.group(1).split("|"))
        missing = required - have
        if not missing:
            return m.group(0)
        attrs = attrs.replace(
            match.group(0),
            'android:configChanges="%s"' % "|".join(sorted(have | required)),
        )
    else:
        attrs += ' android:configChanges="%s"' % "|".join(sorted(required))
    return tag + attrs

src, n_cfg = re.subn(
    r'(<activity\b)([^>]*)',
    patch_config,
    src,
    count=1,
)

with open(path, "w") as f:
    f.write(src)

print("ok: manifest android:name='.WallpaperApp' (%s)" % ("set" if n_name else "UNCHANGED"))
print("ok: manifest predictive back enabled (%s)" % ("applied" if n_predictive else "no <application> found"))
print("ok: manifest configChanges patched (%s)" % ("applied" if n_cfg else "no <activity> found"))
PY

# 4. Remove Flutter template test debris. `flutter create .` regenerates
#    test/widget_test.dart (stock counter test referencing a MyApp class that
#    does not exist in this app), which breaks `flutter test` compilation.
#    Only removed when it matches the template signature, so a real
#    widget_test.dart written later is never touched.
TEMPLATE_TEST="$ROOT/test/widget_test.dart"
if [ -f "$TEMPLATE_TEST" ] && grep -q "Counter increments smoke test" "$TEMPLATE_TEST"; then
  rm "$TEMPLATE_TEST"
  echo "ok: removed template test/widget_test.dart (references non-existent MyApp)"
fi

echo
echo "done. Verify with: flutter build apk --debug"
