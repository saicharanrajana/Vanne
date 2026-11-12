import 'package:material_ui/material_ui.dart';

/// Centralized typography: **Outfit** everywhere — headings and body.
///
/// Outfit ships as a bundled variable font (see `pubspec.yaml`), so text
/// paints in the real font on the very first frame: no network fetch, no
/// async `FontLoader`, no fallback-font flash.
///
/// Weight comes from ordinary [TextStyle.fontWeight], not from an explicit
/// `wght` variation: the bundled file is declared once per weight, so the
/// engine resolves `fontWeight` to the variable axis itself. That keeps
/// `theme.textTheme.bodyLarge.copyWith(fontWeight: FontWeight.w800)` — used
/// by several screens — actually rendering at 800 instead of staying pinned
/// to the base style's axis position.
///
/// Screen headings retain the app's expressive scale; supporting text uses
/// Material 3 body and label sizes for a quieter, consistent hierarchy.
TextTheme buildAppTextTheme(ColorScheme scheme) {
  final onSurface = scheme.onSurface;

  TextStyle font(
    double size,
    double height,
    double tracking,
    FontWeight weight,
  ) => TextStyle(
    fontFamily: 'Outfit',
    fontSize: size,
    height: height / size,
    letterSpacing: tracking,
    fontWeight: weight,
    color: onSurface,
  );

  const regular = FontWeight.w400;
  const medium = FontWeight.w500;
  const semibold = FontWeight.w600;
  const bold = FontWeight.w700;

  return TextTheme(
    displayLarge: font(60, 64, -0.25, bold),
    displayMedium: font(48, 52, 0, bold),
    displaySmall: font(40, 44, 0, bold),
    headlineLarge: font(36, 40, 0, bold),
    headlineMedium: font(32, 36, 0, semibold),
    headlineSmall: font(28, 32, 0, semibold),
    titleLarge: font(26, 30, 0, semibold),
    titleMedium: font(16, 24, 0.15, medium),
    titleSmall: font(14, 20, 0.1, medium),
    bodyLarge: font(16, 24, 0.5, regular),
    bodyMedium: font(14, 20, 0.25, regular),
    bodySmall: font(12, 16, 0.4, regular),
    labelLarge: font(14, 20, 0.1, medium),
    labelMedium: font(12, 16, 0.5, medium),
    labelSmall: font(11, 16, 0.5, medium),
  );
}
