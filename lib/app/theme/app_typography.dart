import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized typography: **Outfit** everywhere — headings and body.
///
/// Headings use bold/semibold weights so titles land with presence; body/label
/// roles use regular/medium. Sizes are bumped +1-2 vs stock M3 so text never
/// feels small on modern high-DPI phones.
TextTheme buildAppTextTheme(ColorScheme scheme) {
  final onSurface = scheme.onSurface;

  TextStyle heading(
    double size,
    double height,
    double tracking,
    FontWeight weight,
  ) =>
      GoogleFonts.outfit(
        fontSize: size,
        height: height / size,
        letterSpacing: tracking,
        fontWeight: weight,
        color: onSurface,
      );

  TextStyle body(
    double size,
    double height,
    double tracking,
    FontWeight weight,
  ) =>
      GoogleFonts.outfit(
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
    displayLarge: heading(59, 64, -0.25, bold),
    displayMedium: heading(47, 52, 0, bold),
    displaySmall: heading(38, 44, 0, bold),
    headlineLarge: heading(34, 40, 0, bold),
    headlineMedium: heading(30, 36, 0, semibold),
    headlineSmall: heading(26, 32, 0, semibold),
    titleLarge: heading(24, 28, 0, semibold),
    titleMedium: heading(18, 24, 0.15, semibold),
    titleSmall: heading(16, 20, 0.1, semibold),
    bodyLarge: body(17, 24, 0.15, regular),
    bodyMedium: body(15, 20, 0.25, regular),
    bodySmall: body(13, 16, 0.4, regular),
    labelLarge: body(15, 20, 0.1, semibold),
    labelMedium: body(13, 16, 0.5, medium),
    labelSmall: body(12, 16, 0.5, medium),
  );
}
