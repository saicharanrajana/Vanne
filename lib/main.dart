import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/dependencies.dart';

Future<void> main() async {
  // 1. Flutter bindings — plugin calls (Hive, secure storage) need them.
  WidgetsFlutterBinding.ensureInitialized();
  // 2. Give the image cache headroom: the app's entire job is displaying
  //    large photos, and Flutter's default (~100 MiB / 1000 entries)
  //    evicts grid tiles after viewing a couple of full-res details,
  //    forcing constant disk re-decodes (visible as placeholder flashes).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 4000;
  // 3. Hive, repositories, services, controllers (incl. API-key restore).
  await bootstrap();
  // 4. UI.
  runApp(const WallpaperApp());
}
