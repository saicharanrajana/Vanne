import 'package:material_ui/material_ui.dart';
// Importing google_fonts_lite (instead of google_fonts) keeps only the font
// map + dynamic resolution in the build, letting the compiler tree-shake
// every other Google Fonts family's generated methods.
import 'package:google_fonts/google_fonts_lite.dart';

/// Centralized typography: **Outfit** everywhere — headings and body.
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
  ) => GoogleFontsLite.getFont(
    'Outfit',
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
