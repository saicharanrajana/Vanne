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
    displayLarge: font(60, 64, -0.25, bold),
    displayMedium: font(48, 52, 0, bold),
    displaySmall: font(40, 44, 0, bold),
    headlineLarge: font(36, 40, 0, bold),
    headlineMedium: font(32, 36, 0, semibold),
    headlineSmall: font(28, 32, 0, semibold),
    titleLarge: font(26, 30, 0, semibold),
    titleMedium: font(19, 25, 0.15, semibold),
    titleSmall: font(17, 22, 0.1, semibold),
    bodyLarge: font(18, 26, 0.15, regular),
    bodyMedium: font(16, 22, 0.25, regular),
    bodySmall: font(14, 18, 0.4, regular),
    labelLarge: font(16, 20, 0.1, semibold),
    labelMedium: font(14, 16, 0.5, medium),
    labelSmall: font(13, 16, 0.5, medium),
  );
}
