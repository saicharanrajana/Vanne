import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:vanne/app/router/app_route.dart';
import 'package:vanne/core/downloads/download_destination.dart';
import 'package:vanne/core/security/api_key_store.dart';
import 'package:vanne/core/storage/settings_store.dart' show AppThemeMode;

import '../support/test_app.dart';

/// Settings owns durable user choices (theme, content policy, API key,
/// download destination). These tests protect the promises users rely on:
/// a choice survives a restart, and a security-relevant choice cannot be
/// silently lost or half-applied.
void main() {
  /// The shell's floating toolbar is icon-first: destinations are located by
  /// their stable slot keys, not by a visible word.
  Finder tabLabel(String slug) => shellDestination(slug);

  Finder backButton() => find.byIcon(PhosphorIconsBold.arrowLeft);

  /// Opens the Settings destination and waits for its first section.
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(tabLabel('settings'));
    await pumpFrames(tester, 6);
    await pumpUntil(tester, find.text('Appearance'), reason: 'settings screen');
  }

  /// Scrolls the settings list until [finder] is built and on screen. The
  /// list is longer than a phone viewport, and rows must be reachable without
  /// relying on a specific section order.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 6 && finder.evaluate().isEmpty; i++) {
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -260),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  appTest('theme selector is aligned, icon-only, and accessible', (
    tester,
    app,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    await app.launch(tester);
    await openSettings(tester);

    expect(
      find.text('Choose how Vanne follows your device appearance.'),
      findsOneWidget,
    );
    expect(find.byTooltip('System theme'), findsOneWidget);
    expect(find.byTooltip('Light theme'), findsOneWidget);
    expect(find.byTooltip('Dark theme'), findsOneWidget);
    expect(find.text('Auto'), findsNothing);
    expect(find.text('Light'), findsNothing);
    expect(find.text('Dark'), findsNothing);

    final themeCard = find.ancestor(
      of: find.text('Theme'),
      matching: find.byType(M3ECard),
    );
    final themeSurface = tester.widget<M3ECard>(themeCard);
    expect(themeSurface.color, Colors.transparent);
    expect(themeSurface.elevation, 0);

    final selector = find.byType(M3ESegmentedButton<AppThemeMode>);
    expect(selector, findsOneWidget);
    final selectorRect = tester.getRect(selector);
    final leadingRect = tester.getRect(
      find.byIcon(PhosphorIconsFill.sun).first,
    );
    expect(selectorRect.left, greaterThan(leadingRect.right));

    TextStyle styleOf(String label) =>
        tester.widget<Text>(find.text(label)).style!;
    expect(
      styleOf('Theme'),
      styleOf('Use dynamic color'),
      reason: 'Theme title must match an ordinary M3E list-row headline.',
    );
    expect(
      styleOf('Choose how Vanne follows your device appearance.'),
      styleOf('Match app colors to your wallpaper.'),
      reason: 'Theme subtitle must match an ordinary M3E supporting line.',
    );

    Finder segmentIcon(IconData icon) =>
        find.descendant(of: selector, matching: find.byIcon(icon));
    expect(segmentIcon(PhosphorIconsFill.deviceMobile), findsOneWidget);
    expect(segmentIcon(PhosphorIconsRegular.sun), findsOneWidget);
    expect(segmentIcon(PhosphorIconsRegular.moon), findsOneWidget);

    await app.persistTap(tester, find.byTooltip('Light theme'));
    expect(app.settings.themeMode.value, AppThemeMode.light);
    expect(segmentIcon(PhosphorIconsFill.sun), findsOneWidget);
    expect(segmentIcon(PhosphorIconsRegular.deviceMobile), findsOneWidget);
    expect(segmentIcon(PhosphorIconsRegular.moon), findsOneWidget);

    await app.persistTap(tester, find.byTooltip('Dark theme'));
    expect(app.settings.themeMode.value, AppThemeMode.dark);
    expect(segmentIcon(PhosphorIconsFill.moon), findsOneWidget);
    expect(segmentIcon(PhosphorIconsRegular.deviceMobile), findsOneWidget);
    expect(segmentIcon(PhosphorIconsRegular.sun), findsOneWidget);

    await app.persistTap(tester, find.byTooltip('System theme'));
    expect(app.settings.themeMode.value, AppThemeMode.system);
    expect(segmentIcon(PhosphorIconsFill.deviceMobile), findsOneWidget);
    expect(segmentIcon(PhosphorIconsRegular.sun), findsOneWidget);
    expect(segmentIcon(PhosphorIconsRegular.moon), findsOneWidget);

    await reveal(tester, find.text('Downloads'));
    expect(
      styleOf('Downloads'),
      styleOf('Use dynamic color'),
      reason: 'Downloads title must match an ordinary M3E list-row headline.',
    );
    expect(
      styleOf('Pictures/VanneWallpapers'),
      styleOf('Match app colors to your wallpaper.'),
      reason: 'Downloads detail must use M3E supporting-line typography.',
    );
    expect(
      styleOf('Tap to change the downloads location'),
      styleOf('Match app colors to your wallpaper.'),
      reason: 'Downloads hint must use M3E supporting-line typography.',
    );
    final downloadsCard = find.ancestor(
      of: find.text('Downloads'),
      matching: find.byType(M3ECard),
    );
    final downloadsSurface = tester.widget<M3ECard>(downloadsCard);
    expect(downloadsSurface.color, Colors.transparent);
    expect(downloadsSurface.elevation, 0);

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('System theme'), findsOneWidget);
    expect(find.bySemanticsLabel('Light theme'), findsOneWidget);
    expect(find.bySemanticsLabel('Dark theme'), findsOneWidget);
    semantics.dispose();
  });

  appTest('appearance choices survive a restart', (tester, app) async {
    await app.launch(tester);
    await openSettings(tester);

    // Each row's title toggles its switch, exactly like tapping the row.
    await app.persistTap(tester, find.byTooltip('Dark theme'));
    await reveal(tester, find.text('Pitch black mode'));
    await app.persistTap(tester, find.text('Pitch black mode'));
    await reveal(tester, find.text('Use dynamic color'));
    await app.persistTap(tester, find.text('Use dynamic color'));

    expect(app.settings.themeMode.value, AppThemeMode.dark);
    expect(app.settings.pitchBlack.value, isTrue);
    expect(app.settings.dynamicColor.value, isFalse);
    // Dark + pitch black is applied to the live theme immediately.
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );

    await app.restart(tester);
    await openSettings(tester);

    expect(app.settings.themeMode.value, AppThemeMode.dark);
    expect(app.settings.pitchBlack.value, isTrue);
    expect(app.settings.dynamicColor.value, isFalse);
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );
  });

  appTest('NSFW is unavailable until an API key is configured', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await openSettings(tester);

    await pumpUntil(
      tester,
      find.text('Requires a Wallhaven API key.'),
      reason: 'NSFW locked copy',
    );
    expect(app.settings.nsfwEnabled.value, isFalse);

    // Tapping the locked row is a shortcut to the screen that unlocks it.
    await app.tap(tester, find.text('Show NSFW wallpapers'));
    await pumpFrames(tester, 8);
    await pumpUntil(
      tester,
      find.text('Wallhaven API key'),
      reason: 'API key screen',
    );
  });

  appTest('saving an API key unlocks NSFW and survives a restart', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await openSettings(tester);

    await reveal(tester, find.text('API key'));
    await app.tap(tester, find.text('API key'));
    await pumpUntil(
      tester,
      find.text('Wallhaven API key'),
      reason: 'API key screen',
    );

    await app.enterText(tester, find.byType(TextField), 'test-api-key');
    await app.persistTap(tester, find.text('Save key'));
    await pumpUntil(
      tester,
      find.text('A key is configured on this device.'),
      reason: 'saved key state',
    );
    expect(app.settings.hasApiKey.value, isTrue);
    expect(app.repository.isAuthenticated, isTrue);

    await app.tap(tester, backButton());
    await pumpFrames(tester, 8);
    await reveal(tester, find.text('Show NSFW wallpapers'));
    await app.persistTap(tester, find.text('Show NSFW wallpapers'));
    expect(app.settings.nsfwEnabled.value, isTrue);
    expect(app.settingsStore.nsfwEnabled, isTrue);

    await app.restart(tester);

    expect(app.settings.hasApiKey.value, isTrue);
    expect(app.settings.nsfwEnabled.value, isTrue);
    // The stored preference now actually reaches the API as an unlocked
    // purity filter, not just the UI.
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed after restart',
    );
    await app.settleUntil(
      tester,
      () => app.network.searches.isNotEmpty,
      reason: 'discover request after restart',
    );
    // Wallhaven omits `purity` only when every purity is allowed, so an
    // empty value proves NSFW was not clamped back to SFW.
    expect(app.network.searches.last.purity, isEmpty);
  });

  appTest(
    'removing the API key disables NSFW access',
    (tester, app) async {
      await app.launch(tester);
      expect(app.settings.hasApiKey.value, isTrue);
      await openSettings(tester);

      // NSFW is usable while the key exists.
      await reveal(tester, find.text('Show NSFW wallpapers'));
      await app.persistTap(tester, find.text('Show NSFW wallpapers'));
      expect(app.settings.nsfwEnabled.value, isTrue);

      await reveal(tester, find.text('API key'));
      await app.tap(tester, find.text('API key'));
      await pumpUntil(
        tester,
        find.text('A key is configured on this device.'),
        reason: 'configured key',
      );

      // Cancelling the confirmation keeps the key.
      await app.persistTap(tester, find.text('Remove key'));
      await pumpUntil(tester, find.text('Remove API key?'), reason: 'confirm');
      expect(
        find.text(
          'NSFW access will be disabled until another key is configured.',
        ),
        findsOneWidget,
      );
      await app.persistTap(tester, find.text('Cancel'));
      await pumpFrames(tester, 6);
      expect(app.settings.hasApiKey.value, isTrue);

      // Confirming removal destroys the key and forces NSFW off.
      await reveal(tester, find.text('Remove key'));
      await app.persistTap(tester, find.text('Remove key'));
      await pumpUntil(tester, find.text('Remove API key?'), reason: 'confirm');
      await app.persistTap(tester, find.text('Remove'));
      await pumpFrames(tester, 8);

      expect(app.settings.hasApiKey.value, isFalse);
      expect(app.repository.isAuthenticated, isFalse);
      // ...and NSFW is forced off so the app never requests it unauthenticated.
      expect(app.settings.nsfwEnabled.value, isFalse);
      expect(app.settingsStore.nsfwEnabled, isFalse);
      expect(app.secureStorage, isEmpty);
    },
    // A key restored from secure storage at launch, like an installed user.
    create: () =>
        TestApp(secureStorage: {SecureApiKeyStore.storageKey: 'stored-key'}),
  );

  appTest('blocked tags are normalized and sent as exclusions', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await openSettings(tester);

    await reveal(tester, find.text('Blocked tags'));
    await app.tap(tester, find.text('Blocked tags'));
    await pumpUntil(
      tester,
      find.textContaining('Hide wallpapers containing these tags'),
      reason: 'blocked tags screen',
    );

    await app.enterText(tester, find.byType(TextField), 'Anime, AI-Generated');
    await app.persistTap(tester, find.text('Save'));
    await pumpFrames(tester, 8);
    expect(app.settings.blockedTags.value, {'anime', 'ai-generated'});

    // Exclusions apply to the next request, not only after a restart.
    await app.tap(tester, backButton());
    await pumpFrames(tester, 8);
    await app.tap(tester, tabLabel('discover'));
    await pumpFrames(tester, 8);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(tabLabel('discover')),
      isSemantics(isSelected: true),
      reason: 'Discover becomes the active destination',
    );
    semantics.dispose();
    await app.tap(tester, find.byType(M3ESearchBar).first);
    await pumpUntil(tester, find.byType(SearchPage), reason: 'Search page');
    // The expressive search bar edits through EditableText, not TextField.
    await app.enterText(tester, find.byType(EditableText), 'sky');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 400));
    await pumpFrames(tester, 4);

    final query = app.network.searches.last.query;
    expect(query, contains('sky'));
    expect(query, contains('-anime'));
    expect(query, contains('-ai-generated'));
  });

  appTest('download folder: cancel keeps the default destination', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await openSettings(tester);
    await pumpUntil(
      tester,
      find.text('Pictures/VanneWallpapers'),
      reason: 'default download path',
    );

    await reveal(tester, find.text('Downloads'));
    await app.persistTap(tester, find.text('Downloads'));
    await pumpUntil(tester, find.text('Download folder'), reason: 'dialog');
    // Default picker result in the fake is "canceled".
    await app.persistTap(tester, find.text('Choose folder'));
    await pumpFrames(tester, 8);

    expect(
      app.destination.destination.value,
      const DefaultDownloadDestination(),
    );
    expect(find.text('Pictures/VanneWallpapers'), findsOneWidget);
  });

  appTest('download folder choice persists and a revoked grant surfaces', (
    tester,
    app,
  ) async {
    app.storagePlatform.pickResults
      ..clear()
      ..add(
        const ParentPicked(treeUri: 'content://tree/walls', label: 'Walls'),
      );

    await app.launch(tester);
    await openSettings(tester);

    await reveal(tester, find.text('Downloads'));
    await app.persistTap(tester, find.text('Downloads'));
    await pumpUntil(tester, find.text('Download folder'), reason: 'dialog');
    await app.persistTap(tester, find.text('Choose folder'));
    await pumpUntil(
      tester,
      find.text('Walls/VanneWallpapers'),
      reason: 'chosen destination in settings',
    );
    expect(app.destination.destination.value.treeUri, 'content://tree/walls');
    expect(
      app.settingsStore.downloadTreeUri,
      'content://tree/walls',
      reason: 'choice is persisted immediately',
    );

    // The OS grant can disappear between launches; the restored destination
    // must say so instead of failing silently at download time.
    app.storagePlatform.checkResult = const ParentAccessLost();
    await app.restart(tester);
    await openSettings(tester);
    await pumpUntil(
      tester,
      find.textContaining('Folder access was lost'),
      reason: 'revoked grant hint',
    );
    expect(app.destination.access.value, DestinationAccess.lost);
  });
}
