import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:vanne/app/router/app_route.dart';

import '../test/support/test_app.dart';

/// On-device integration journeys.
///
/// These run the REAL app on an emulator/device (real engine, Hive, isolates
/// and widget rendering) while the network and platform channels stay faked,
/// so the run is deterministic and needs no connectivity or OS dialogs.
///
///     flutter test integration_test/app_journeys_test.dart -d <emulator-id>
///
/// The deterministic widget suite (`flutter test`) gives fast feedback; this
/// suite catches device-only regressions (plugins, isolates, real painting).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));

  appTest('discover → detail → favorite → favorites → unfavorite', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await app.tap(tester, tile('alpha'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail page',
    );

    await app.persistTap(
      tester,
      find.byKey(const ValueKey('favorite-outline')).first,
    );
    expect(app.favorites.favoriteIds.value, contains('alpha'));

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 8);
    await app.tap(tester, find.text('Favorites').first);
    await pumpUntil(tester, tile('alpha'), reason: 'favorite in Favorites tab');

    await app.persistTap(
      tester,
      find.byKey(const ValueKey('favorite-filled')).first,
    );
    await pumpFrames(tester, 8);
    expect(find.text('No favorites yet'), findsOneWidget);
  });

  appTest('search commit → result → detail → back to search', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');

    await app.tap(tester, find.byIcon(PhosphorIconsBold.magnifyingGlass).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'search page');

    await app.enterText(tester, find.byType(EditableText), 'nature');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpFrames(tester, 12, const Duration(milliseconds: 50));

    await pumpUntil(tester, tile('beta'), reason: 'search results');
    await app.tap(tester, tile('beta'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail from search',
    );

    await app.tap(tester, find.byIcon(PhosphorIconsBold.arrowLeft).first);
    await pumpFrames(tester, 10);
    expect(find.byType(SearchPage), findsOneWidget);
  });

  appTest('save download and open-source reach the platform fakes', (
    tester,
    app,
  ) async {
    app.storagePlatform.saveResult = const DownloadSaveSuccess(
      'content://downloads/alpha',
    );

    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover feed');
    await app.tap(tester, tile('alpha'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail page',
    );

    // The info sheet rests at 30% height; its action row is inside the
    // scrollable content, so scroll the sheet like a user would.
    await pumpFrames(tester, 12, const Duration(milliseconds: 100));
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -300),
    );
    await pumpFrames(tester, 8, const Duration(milliseconds: 100));

    await app.persistTap(
      tester,
      find.byIcon(PhosphorIconsBold.cloudArrowDown).first,
    );
    await app.settleUntil(
      tester,
      () => app.storagePlatform.savedDownloads.isNotEmpty,
      reason: 'download saved through the platform bridge',
    );
    expect(app.storagePlatform.savedDownloads, hasLength(1));
    expect(app.storagePlatform.savedDownloads.single.treeUri, isNull);

    // Let the success snackbar clear, then use the source-link action.
    await pumpFrames(tester, 12, const Duration(milliseconds: 500));
    await app.persistTap(
      tester,
      find.byIcon(PhosphorIconsBold.linkSimple).first,
    );
    await app.settleUntil(
      tester,
      () => app.urlLauncher.opened.isNotEmpty,
      reason: 'source URL handed to the browser',
    );
    expect(
      app.urlLauncher.opened.single.toString(),
      'https://wallhaven.cc/w/alpha',
    );
  });
}
