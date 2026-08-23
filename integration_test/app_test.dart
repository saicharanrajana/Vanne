import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:wallpaper_app/app/app.dart';
import 'package:wallpaper_app/app/dependencies.dart';

/// On-device end-to-end smoke test against the REAL Wallhaven API.
///
/// Run with a device/emulator attached:
///
///     flutter test integration_test -d <device>
///
/// Makes a handful of SFW requests — well within the rate limit.
/// Requires network connectivity.

/// Pumps frames until [finder] locates a widget or [timeout] elapses.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Integration tests run on-device; bootstrap mirrors production
    // main() (Hive init, DI registration, API-key restore).
    await bootstrap();
  });

  testWidgets('discover feed loads and opens detail via hero tile', (
    tester,
  ) async {
    await tester.pumpWidget(const WallpaperApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 1. Discover loads live wallpapers into the staggered grid.
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-')).first,
      timeout: const Duration(seconds: 25),
    );

    // 2. Open the first result's detail screen (Hero transition).
    final tiles = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('wallpaper-tile-'),
      description: 'first wallpaper grid tile',
    );
    await tester.tap(tiles.first);
    await pumpUntil(
      tester,
      find.text('Details'),
      timeout: const Duration(seconds: 25),
    );
    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets('favorites empty state renders', (tester) async {
    await tester.pumpWidget(const WallpaperApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('No favorites yet'), findsOneWidget);
  });
}
