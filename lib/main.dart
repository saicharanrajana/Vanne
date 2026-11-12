import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/app_startup.dart';
import 'app/dependencies.dart';
import 'shared/widgets/friendly_error_view.dart';

Future<void> main() async {
  // Plugin calls below need the binding; everything after this line is
  // synchronous so the first frame can be requested immediately.
  WidgetsFlutterBinding.ensureInitialized();

  // Give the image cache headroom: the app's entire job is displaying large
  // photos, and Flutter's default (~100 MiB / 1000 entries) evicts grid
  // tiles after viewing a couple of full-res details, forcing constant disk
  // re-decodes (visible as placeholder flashes).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 4000;

  // Friendly global error surface instead of the grey release box;
  // long press copies diagnostics (visible only in debug).
  ErrorWidget.builder = (details) => FriendlyErrorView(details: details);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Paint the themed launch surface on the very first frame, then hydrate
  // storage/DI behind it. Awaiting bootstrap() here used to leave the window
  // blank for the whole serial I/O chain (observed ~1.7s cold start).
  runApp(const AppStartup(initialize: _initialize, child: WallpaperApp()));
}

/// App-wide async initialization, off the first-frame path.
///
/// Runs at most once per launch, and again after a failed attempt (services
/// are reset by [AppStartup] first).
Future<void> _initialize() async {
  // Locale data for DateFormat before any UI can format a date (~5 ms).
  await initializeDateFormatting();
  // Hive, repositories, services, controllers (incl. API-key restore).
  // Outfit is a bundled asset, so fonts never block or hit the network.
  await bootstrap();
}
