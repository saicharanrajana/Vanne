import 'package:google_fonts/google_fonts_lite.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'shared/widgets/friendly_error_view.dart';

Future<void> main() async {
  // 1. Flutter bindings — plugin calls (Hive, secure storage) need them.
  WidgetsFlutterBinding.ensureInitialized();
  // 2. Give the image cache headroom: the app's entire job is displaying
  //    large photos, and Flutter's default (~100 MiB / 1000 entries)
  //    evicts grid tiles after viewing a couple of full-res details,
  //    forcing constant disk re-decodes (visible as placeholder flashes).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 4000;
  // 3. Locale data for DateFormat before any UI can format a date.
  await initializeDateFormatting();
  // 4. Preload Outfit while the launch screen is still visible so first-
  //    frame text doesn't render in the fallback font, then swap. Never
  //    blocks startup when offline.
  await _preloadFonts();
  // 5. Hive, repositories, services, controllers (incl. API-key restore).
  await bootstrap();
  // 6. Friendly global error surface instead of the grey release box;
  //    long press copies diagnostics (visible only in debug).
  ErrorWidget.builder = (details) => FriendlyErrorView(details: details);
  // 7. UI.
  runApp(const WallpaperApp());
}

/// Loads exactly the Outfit weights `app_typography.dart` uses so no text
/// ever paints in the fallback font on a cold start.
Future<void> _preloadFonts() async {
  try {
    await GoogleFontsLite.pendingFonts([
      GoogleFontsLite.getFont('Outfit', fontWeight: FontWeight.w400),
      GoogleFontsLite.getFont('Outfit', fontWeight: FontWeight.w500),
      GoogleFontsLite.getFont('Outfit', fontWeight: FontWeight.w600),
      GoogleFontsLite.getFont('Outfit', fontWeight: FontWeight.w700),
    ]);
  } catch (error) {
    debugPrint('Font preload skipped: $error');
  }
}
