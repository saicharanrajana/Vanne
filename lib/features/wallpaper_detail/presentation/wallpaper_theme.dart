import 'package:material_ui/material_ui.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/utils/hex_color.dart';

/// Wallpaper-derived color scheme and theme, shared by the detail screen and
/// any overlay rendered on the root navigator (e.g. the set-wallpaper popup)
/// that must match the screen's palette even though it sits outside the
/// screen's [AnimatedTheme].
///
/// Seed selection: the most saturated Wallhaven palette color inside a
/// readability window (HSL lightness 0.35–0.65); if none qualifies, the most
/// saturated color is nudged into the window. Empty/invalid palettes fall
/// back to the ambient app scheme.

/// Readability window for seeds: outside it, containers/text pairs lose
/// contrast no matter how saturated the color is.
const _minSeedLightness = 0.35;
const _maxSeedLightness = 0.65;

/// Builds a full [ColorScheme] seeded from [wallpaper]'s palette.
///
/// Falls back to [fallback] when the wallpaper has no usable colors.
/// [pitchBlack] collapses dark surfaces to the true-black ladder while
/// keeping the wallpaper-derived accents intact.
ColorScheme wallpaperScheme(
  Wallpaper wallpaper,
  Brightness brightness,
  ColorScheme fallback,
  bool pitchBlack,
) {
  if (wallpaper.colors.isEmpty) return fallback;

  HSLColor? best;
  HSLColor? bestAny;
  for (final hex in wallpaper.colors) {
    final color = parseHexColor(hex);
    if (color == null) continue;
    final hsl = HSLColor.fromColor(color);
    if (bestAny == null || hsl.saturation > bestAny.saturation) {
      bestAny = hsl;
    }
    final inWindow =
        hsl.lightness >= _minSeedLightness &&
        hsl.lightness <= _maxSeedLightness;
    if (inWindow && (best == null || hsl.saturation > best.saturation)) {
      best = hsl;
    }
  }

  var chosen = best ?? bestAny;
  if (chosen == null) return fallback;
  // No candidate sat inside the readability window — nudge the most
  // saturated one into it rather than falling back to the app scheme.
  chosen = chosen.withLightness(
    chosen.lightness.clamp(_minSeedLightness, _maxSeedLightness),
  );

  // Generate a full scheme from the vibrant seed *without* systemColorScheme.
  // When systemColorScheme is passed, M3EColorScheme keeps system primary/
  // secondary (app's blue) and only overrides surfaces — which is why
  // variety wallpapers still looked blue. Passing null makes primary,
  // primaryContainer, secondary etc come from the wallpaper seed.
  final scheme = ColorScheme.fromSeed(
    seedColor: chosen.toColor(),
    brightness: brightness,
  );

  // Pitch-black mode: collapse surfaces to the true-black ladder while the
  // wallpaper-derived accents (primary, containers) stay intact.
  return pitchBlack && brightness == Brightness.dark
      ? AppTheme.toPitchBlack(scheme)
      : scheme;
}

/// Robust wallpaper-derived ThemeData. Wrapping a subtree with this ensures
/// *every* descendant that does `Theme.of(context)` gets wallpaper colors —
/// no per-widget `colorScheme` plumbing. Future widgets added under the
/// theme automatically honor the wallpaper palette without manual updates.
ThemeData wallpaperThemeData(ColorScheme scheme, ThemeData base) {
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: buildAppTextTheme(scheme),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: scheme.primary.withValues(alpha: 0.30),
      selectionHandleColor: scheme.primary,
      cursorColor: scheme.primary,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.secondaryContainer,
      checkmarkColor: scheme.onSecondaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      secondaryLabelStyle: TextStyle(color: scheme.onSecondaryContainer),
      shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      showCheckmark: true,
    ),
    iconTheme: base.iconTheme.copyWith(color: scheme.onSurfaceVariant),
    primaryIconTheme: base.primaryIconTheme.copyWith(
      color: scheme.onSurfaceVariant,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: scheme.outlineVariant,
  );
}
