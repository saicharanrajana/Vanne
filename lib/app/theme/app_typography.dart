import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized typography: **Outfit** everywhere — headings and body.
///
/// Headings use bold/semibold weights so titles land with presence; body/label
/// roles use regular/medium. Sizes are bumped +1-2 vs stock M3 so text never
/// feels small on modern high-DPI phones.
TextTheme buildAppTextTheme(ColorScheme scheme) {
  final onSurface = scheme.onSurface;

  TextStyle font(
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
    displayLarge: font(59, 64, -0.25, bold),
    displayMedium: font(47, 52, 0, bold),
    displaySmall: font(38, 44, 0, bold),
    headlineLarge: font(34, 40, 0, bold),
    headlineMedium: font(30, 36, 0, semibold),
    headlineSmall: font(26, 32, 0, semibold),
    titleLarge: font(24, 28, 0, semibold),
    titleMedium: font(18, 24, 0.15, semibold),
    titleSmall: font(16, 20, 0.1, semibold),
    bodyLarge: font(17, 24, 0.15, regular),
    bodyMedium: font(15, 20, 0.25, regular),
    bodySmall: font(13, 16, 0.4, regular),
    labelLarge: font(15, 20, 0.1, semibold),
    labelMedium: font(13, 16, 0.5, medium),
    labelSmall: font(12, 16, 0.5, medium),
  );
}
