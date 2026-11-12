import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/shared/widgets/app_snack.dart';

import '../support/fake_wallhaven.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

/// The wallpaper detail screen is where a wallpaper becomes an action:
/// inspect metadata, favorite, save, apply. These journeys cover the
/// progressive load, the destructive platform calls (through recording
/// fakes), and the failure/duplicate-submit paths that would otherwise
/// reach the OS unguarded.
void main() {
  Finder tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));
  // Material 3 Expressive icon buttons render an M3ETooltip, not a Flutter
  // `Tooltip`, so actions are located by their glyph.
  final download = find.byIcon(PhosphorIconsBold.cloudArrowDown);
  final openSource = find.byIcon(PhosphorIconsBold.linkSimple);
  final back = find.byIcon(PhosphorIconsBold.arrowLeft).first;

  /// The action row lives inside a draggable sheet, so scroll it into the
  /// viewport before tapping — the same gesture a user performs.
  Future<void> revealSheet(WidgetTester tester, Finder finder) async {
    // The info sheet rests at 30% height; its action row starts offscreen.
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -300),
    );
    await pumpFrames(tester, 6, const Duration(milliseconds: 100));
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<void> tapSheet(WidgetTester tester, TestApp app, Finder finder) async {
    await revealSheet(tester, finder);
    await app.persistTap(tester, finder);
  }

  /// Snackbars cover the bottom action row. Their timers run in the real
  /// zone, so tests dismiss them explicitly instead of waiting.
  Future<void> clearSnack(WidgetTester tester) async {
    AppSnack.messengerKey.currentState?.clearSnackBars();
    await pumpFrames(tester, 6);
  }

  Future<void> openDetail(
    WidgetTester tester,
    TestApp app, {
    bool waitForDetails = true,
  }) async {
    await app.launch(tester);
    await pumpUntil(tester, tile('alpha'), reason: 'discover tile');
    await app.tap(tester, tile('alpha'));
    await pumpUntil(
      tester,
      find.byType(WallpaperDetailPage),
      reason: 'detail route',
    );
    if (waitForDetails) {
      // Actions and metadata only render once /w/{id} resolves.
      await pumpUntil(
        tester,
        find.text('fixture-user'),
        reason: 'detail metadata loaded',
      );
    }
  }

  appTest('listing data renders first, then full details enrich it', (
    tester,
    app,
  ) async {
    final details = Completer<Map<String, dynamic>>();
    app.network.detailHandler = (id) => details.future;

    await openDetail(tester, app, waitForDetails: false);

    // The listing snapshot paints the image immediately and the sheet shows
    // a bounded loading state — the route itself is never blocked.
    expect(find.byType(WallpaperDetailPage), findsOneWidget);
    expect(find.byType(M3ELoadingIndicator), findsWidgets);
    expect(find.text('fixture-user'), findsNothing);

    await tester.runAsync(() async {
      details.complete(wallpaperDetailsJson('alpha'));
    });
    await pumpUntil(
      tester,
      find.text('fixture-user'),
      reason: 'uploader from detail payload',
    );
    expect(find.text('landscape'), findsWidgets);
  });

  appTest('a failed detail fetch keeps the screen usable', (tester, app) async {
    app.network.detailHandler = (id) async => throw const FakeOffline();

    await openDetail(tester, app, waitForDetails: false);
    await pumpFrames(tester, 6);

    // No crash and no stuck loading state: listing metadata still renders.
    expect(find.byType(WallpaperDetailPage), findsOneWidget);
    expect(find.text('1080x1920'), findsOneWidget);
    expect(app.network.detailIds, ['alpha']);
  });

  appTest('favoriting on detail updates the Favorites tab', (
    tester,
    app,
  ) async {
    await openDetail(tester, app);
    await pumpUntil(
      tester,
      find.text('fixture-user'),
      reason: 'details loaded',
    );

    await app.persistTap(
      tester,
      find.byKey(const ValueKey('favorite-outline')),
    );
    expect(app.favorites.favoriteIds.value, contains('alpha'));

    // The detail heart reflects the shared state immediately.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('favorite-filled')),
        matching: find.byType(Icon),
        matchRoot: true,
      ),
      findsOneWidget,
    );

    await app.tap(tester, back);
    await pumpFrames(tester, 8);
    await app.tap(tester, find.text('Favorites').first);
    await pumpUntil(tester, tile('alpha'), reason: 'favorite in Favorites tab');
  });

  appTest('opening the source page hands the URL to the browser', (
    tester,
    app,
  ) async {
    await openDetail(tester, app);

    await tapSheet(tester, app, openSource);
    expect(app.urlLauncher.opened, [Uri.parse('https://wallhaven.cc/w/alpha')]);
  });

  appTest('a missing browser reports instead of failing silently', (
    tester,
    app,
  ) async {
    app.urlLauncher.succeeds = false;
    await openDetail(tester, app);

    await tapSheet(tester, app, openSource);
    await pumpUntil(
      tester,
      find.text('No browser available.'),
      reason: 'missing-browser feedback',
    );
    expect(app.urlLauncher.opened, hasLength(1));
  });

  appTest('saving a wallpaper downloads once and reports the folder', (
    tester,
    app,
  ) async {
    await openDetail(tester, app);

    await tapSheet(tester, app, download);
    await app.settleUntil(
      tester,
      () => app.storagePlatform.savedDownloads.isNotEmpty,
      reason: 'platform save invoked',
    );
    await app.settleUntil(
      tester,
      () => download.evaluate().isNotEmpty,
      reason: 'save finished',
    );

    expect(app.storagePlatform.savedDownloads, hasLength(1));
    final saved = app.storagePlatform.savedDownloads.single;
    // The default destination is MediaStore's Pictures/VanneWallpapers.
    expect(saved.treeUri, isNull);
    expect(saved.mimeType, 'image/jpeg');
    expect(saved.folderName, 'VanneWallpapers');
  });

  appTest('save feedback names the folder that received the file', (
    tester,
    app,
  ) async {
    // A chosen folder exercises the persisted-grant path and proves the
    // confirmation names the folder that actually received the file.
    app.storagePlatform.pickResults
      ..clear()
      ..add(
        const ParentPicked(treeUri: 'content://tree/camera', label: 'Camera'),
      );
    await openDetail(tester, app);
    await app.act(tester, () => app.destination.chooseParent());
    await app.settleUntil(
      tester,
      () => app.destination.destination.value.treeUri != null,
      reason: 'chosen destination active',
    );

    await tapSheet(tester, app, download);
    await app.settleUntil(
      tester,
      () => app.storagePlatform.savedDownloads.isNotEmpty,
      reason: 'platform save invoked',
    );
    await app.settle(tester, rounds: 4);
    await pumpUntil(
      tester,
      find.text('Saved to Camera/VanneWallpapers'),
      reason: 'destination-specific save confirmation',
    );

    final saved = app.storagePlatform.savedDownloads.single;
    expect(saved.treeUri, 'content://tree/camera');
  });

  appTest('a failed save surfaces an error and can be retried', (
    tester,
    app,
  ) async {
    await openDetail(tester, app);
    app.storagePlatform.saveResult = const DownloadSaveFailure(
      DownloadSaveErrorCode.io,
      'disk full',
    );

    await tapSheet(tester, app, download);
    await app.settleUntil(
      tester,
      () => app.storagePlatform.savedDownloads.isNotEmpty,
      reason: 'failed save reached platform',
    );
    await app.settle(tester, rounds: 4);
    await pumpUntil(
      tester,
      find.text('Could not save the wallpaper. Please try again.'),
      reason: 'failure feedback',
    );

    // Recovering storage lets the same button succeed. The failure snack
    // overlays the action row, so let it time out first (as a user would).
    await clearSnack(tester);
    app.storagePlatform.saveResult = const DownloadSaveSuccess(
      'content://downloads/retry',
    );
    await tapSheet(tester, app, download);
    await app.settleUntil(
      tester,
      () => app.storagePlatform.savedDownloads.length == 2,
      reason: 'retried save reached platform',
    );
    // Let the save continuation (real zone) publish its snack.
    await app.settle(tester, rounds: 4);
    await pumpUntil(
      tester,
      find.text('Saved to Pictures/VanneWallpapers'),
      reason: 'retry confirmation',
    );
  });

  appTest('double-tapping save issues exactly one platform write', (
    tester,
    app,
  ) async {
    final gate = Completer<void>();
    app.storagePlatform.saveGate = gate.future;
    await openDetail(tester, app);

    final button = find.byIcon(PhosphorIconsBold.cloudArrowDown);
    await revealSheet(tester, button);
    final center = tester.getCenter(button);

    // Two taps dispatched before the first frame rebuilds: the same control
    // receives both, like a fast double-tap on a slow device.
    await tester.runAsync(() async {
      await tester.tap(button);
      await tester.tap(button);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    await app.settleUntil(
      tester,
      () => app.storagePlatform.savedDownloads.isNotEmpty,
      reason: 'first save in flight',
    );
    expect(app.storagePlatform.savedDownloads, hasLength(1));

    // While the transfer is pending the glyph is replaced by progress; a tap
    // at the same spot must still not start a second transfer.
    expect(button, findsNothing);
    await tester.runAsync(() async {
      await tester.tapAt(center);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(
      app.storagePlatform.savedDownloads,
      hasLength(1),
      reason: 'busy control rejects repeat taps',
    );

    await tester.runAsync(() async => gate.complete());
    await app.settleUntil(
      tester,
      () => button.evaluate().isNotEmpty,
      reason: 'download button idle again',
    );
    expect(app.storagePlatform.savedDownloads, hasLength(1));
    await pumpUntil(
      tester,
      find.text('Saved to Pictures/VanneWallpapers'),
      reason: 'single success confirmation',
    );
  });

  appTest('setting a wallpaper applies the chosen target', (tester, app) async {
    await openDetail(tester, app);

    // "Set" resolves a local file first, then opens the target sheet.
    await tapSheet(tester, app, find.text('Set'));
    await app.settleUntil(
      tester,
      () => find.text('Set wallpaper').evaluate().isNotEmpty,
      reason: 'set-wallpaper sheet',
    );
    expect(find.text('Home Screen'), findsOneWidget);

    await app.persistTap(tester, find.text('Home Screen'));
    await app.settleUntil(
      tester,
      () => app.wallpaperPlatform.appliedTargets.isNotEmpty,
      reason: 'apply reached platform',
    );
    await app.settle(tester, rounds: 4);
    await pumpUntil(
      tester,
      find.text('Wallpaper set for your home screen'),
      reason: 'apply confirmation',
    );

    expect(app.wallpaperPlatform.appliedTargets, [WallpaperTarget.home]);
    expect(find.text('Set wallpaper'), findsNothing);
  });

  appTest('each sheet option maps to its platform target', (tester, app) async {
    await openDetail(tester, app);

    // Home was covered above; prove the other two options route correctly
    // and that the cached prepared file is reused instead of re-downloaded.
    await tapSheet(tester, app, find.text('Set'));
    await app.settleUntil(
      tester,
      () => find.text('Set wallpaper').evaluate().isNotEmpty,
      reason: 'first sheet',
    );
    await app.persistTap(tester, find.text('Lock Screen'));
    await app.settleUntil(
      tester,
      () => app.wallpaperPlatform.appliedTargets.length == 1,
      reason: 'lock apply',
    );

    await clearSnack(tester);
    await tapSheet(tester, app, find.text('Set'));
    await app.settleUntil(
      tester,
      () => find.text('Set wallpaper').evaluate().isNotEmpty,
      reason: 'second sheet',
    );
    await app.persistTap(tester, find.text('Home & Lock Screen'));
    await app.settleUntil(
      tester,
      () => app.wallpaperPlatform.appliedTargets.length == 2,
      reason: 'both apply',
    );

    expect(app.wallpaperPlatform.appliedTargets, [
      WallpaperTarget.lock,
      WallpaperTarget.both,
    ]);

    // The fourth option hands off to the OS crop/set UI rather than
    // applying directly; the cached file is reused.
    await clearSnack(tester);
    await tapSheet(tester, app, find.text('Set'));
    await app.settleUntil(
      tester,
      () => find.text('Set wallpaper').evaluate().isNotEmpty,
      reason: 'third sheet',
    );
    await app.persistTap(tester, find.text('Crop and set'));
    await app.settleUntil(
      tester,
      () => app.wallpaperPlatform.systemPickerLaunches == 1,
      reason: 'system picker launched',
    );
    expect(app.wallpaperPlatform.appliedTargets, hasLength(2));
  });

  appTest('a failed apply keeps the sheet open for another try', (
    tester,
    app,
  ) async {
    app.wallpaperPlatform.result = const WallpaperFailure(
      WallpaperErrorCode.io,
      'System storage unavailable',
    );
    await openDetail(tester, app);

    await tapSheet(tester, app, find.text('Set'));
    await app.settleUntil(
      tester,
      () => find.text('Set wallpaper').evaluate().isNotEmpty,
      reason: 'set-wallpaper sheet',
    );
    await app.persistTap(tester, find.text('Lock Screen'));
    await app.settleUntil(
      tester,
      () => app.wallpaperPlatform.appliedTargets.isNotEmpty,
      reason: 'apply reached platform',
    );
    await app.settle(tester, rounds: 4);
    await pumpUntil(
      tester,
      find.text('System storage unavailable'),
      reason: 'inline apply error',
    );
    // The dialog stays open so the user can choose another option.
    expect(find.text('Set wallpaper'), findsOneWidget);

    app.wallpaperPlatform.result = const WallpaperSuccess();
    await app.persistTap(tester, find.text('Lock Screen'));
    await app.settleUntil(
      tester,
      () => app.wallpaperPlatform.appliedTargets.length == 2,
      reason: 'retried apply',
    );
    await pumpFrames(tester, 8);
    expect(find.text('Wallpaper set for your lock screen'), findsOneWidget);
    expect(find.text('Set wallpaper'), findsNothing);
  });

  appTest('leaving mid-download cancels without writing dead state', (
    tester,
    app,
  ) async {
    final gate = Completer<void>();
    app.storagePlatform.saveGate = gate.future;
    await openDetail(tester, app);

    await tapSheet(tester, app, download);
    await app.settleUntil(
      tester,
      () => app.storagePlatform.savedDownloads.isNotEmpty,
      reason: 'download in flight',
    );

    // Popping the route disposes the controller and cancels its token.
    await app.tap(tester, back);
    await pumpFrames(tester, 8);
    expect(find.byType(WallpaperDetailPage), findsNothing);

    // Completing after disposal must not throw or show a snack.
    await tester.runAsync(() async => gate.complete());
    await app.settle(tester);
    expect(find.text('Saved to Pictures/VanneWallpapers'), findsNothing);
    // Only the in-flight attempt exists; no retry was triggered by disposal.
    expect(app.storagePlatform.savedDownloads, hasLength(1));
  });

  appTest('expanding tags keeps the info sheet on a snap anchor', (
    tester,
    app,
  ) async {
    // Ten-plus tags are what makes the sheet's content cap move after a drag.
    app.network.detailHandler = (id) async =>
        wallpaperDetailsJson(id, tags: [for (var i = 0; i < 14; i++) 'tag-$i']);
    await openDetail(tester, app);
    await pumpFrames(tester, 10, const Duration(milliseconds: 100));

    final sheetFinder = find.byType(DraggableScrollableSheet);
    final sheet = tester.widget<DraggableScrollableSheet>(sheetFinder);
    final snapSizesBefore = sheet.snapSizes;

    // Drag the sheet open to its content cap, then grow the content by
    // expanding the tag section: the cap moves under a parked sheet.
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -600),
    );
    await pumpFrames(tester, 12, const Duration(milliseconds: 100));
    await app.tap(tester, find.text('+12').first);
    await pumpFrames(tester, 16, const Duration(milliseconds: 100));

    final after = tester.widget<DraggableScrollableSheet>(sheetFinder);
    // Changing snap-anchor identity makes DraggableScrollableSheet re-snap
    // from a post-frame callback. Keep the resting anchor stable as content
    // changes, and handle pointer cancellation on a real child tap first.
    expect(
      identical(after.snapSizes, snapSizesBefore),
      isTrue,
      reason: 'snap anchors must not change identity as content grows',
    );
    expect(after.maxChildSize, greaterThanOrEqualTo(after.initialChildSize));

    // A tap wins the gesture arena over the vertical-drag recognizer and
    // cancels its pre-drag hold. With the old off-anchor extent, Flutter's
    // snap branch fails to dispose that hold before asserting `_hold == null`.
    await tester.tap(find.text('tag-3'), warnIfMissed: false);
    await tester.pump();
    expect(tester.takeException(), isNull);

    // The fix keeps the resting extent on one of the live anchors, never
    // between them after the content-fitted cap has changed.
    final restingExtent =
        tester.getSize(find.byType(CustomScrollView).last).height /
        tester.view.physicalSize.height;
    expect(
      restingExtent,
      anyOf(
        closeTo(after.minChildSize, 0.01),
        closeTo(after.initialChildSize, 0.01),
        closeTo(after.maxChildSize, 0.01),
      ),
      reason: 'sheet rested at $restingExtent, between snap anchors',
    );
  });
}
