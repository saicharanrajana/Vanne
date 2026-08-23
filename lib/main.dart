import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/dependencies.dart';

Future<void> main() async {
  // 1. Flutter bindings — plugin calls (Hive, secure storage) need them.
  WidgetsFlutterBinding.ensureInitialized();
  // 2. Hive, repositories, services, controllers (incl. API-key restore).
  await bootstrap();
  // 3. UI.
  runApp(const WallpaperApp());
}
