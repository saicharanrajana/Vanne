// dynamic_color and CorePalette are the platform/plugin contract the app
// consumes; their deprecations are upstream, not ours to migrate here.
// ignore_for_file: deprecated_member_use

import 'dart:typed_data';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vanne/app/theme/app_theme.dart';

import '../support/test_app.dart';

/// App-level appearance behaviour: explicit theme choices, plus the live
/// Material You palette that Android pushes while the app is running.
///
/// The palette tests drive the REAL `DynamicPaletteController` through the two
/// platform channels it uses:
/// * `getCorePalette` on `io.material.plugins/dynamic_color` (the read),
/// * `changed` on `com.saicharanrajana.vanne/dynamic_palette` (the push).
void main() {
  const dynamicColorChannel = MethodChannel(
    'io.material.plugins/dynamic_color',
  );
  const paletteChangedChannel = MethodChannel(
    'com.saicharanrajana.vanne/dynamic_palette',
  );

  /// Android sends the palette as an `IntArray`, which the standard codec
  /// decodes as a typed int list. Mirroring that keeps the plugin's own
  /// `toList()` cast working, exactly as it does on a device.
  Int32List palette(int seed) =>
      Int32List.fromList(CorePalette.of(seed).asList());

  /// Installs a scripted response for the palette read. [throwOnRead] models
  /// a platform failure such as a revoked/unsupported dynamic-color service.
  void mockPaletteRead(
    List<int> Function() current, {
    bool Function()? throwOnRead,
  }) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(dynamicColorChannel, (call) async {
      if (call.method != DynamicColorPlugin.methodName) return null;
      if (throwOnRead?.call() ?? false) {
        throw PlatformException(code: 'unavailable');
      }
      return current();
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(dynamicColorChannel, null),
    );
  }

  /// Delivers the native "wallpaper colours changed" notification.
  Future<void> sendPaletteChanged(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      paletteChangedChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('changed'),
      ),
      (_) {},
    );
    await tester.pump();
  }

  /// Reads the theme actually applied *inside* the app shell. Reading at the
  /// MaterialApp element itself would find the ambient default theme.
  Color primaryOn(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary;

  Color expectedPrimary(List<int> colors) => AppTheme.build(
    brightness: Brightness.light,
    dynamicScheme: CorePalette.fromList(colors).toColorScheme(),
  ).colorScheme.primary;

  Future<void> waitForPrimary(
    WidgetTester tester,
    TestApp app,
    List<int> colors, {
    required String reason,
  }) => app.settleUntil(
    tester,
    () => primaryOn(tester) == expectedPrimary(colors),
    reason: reason,
  );


  appTest('choosing Dark applies a dark theme without losing the screen', (
    tester,
    app,
  ) async {
    // Force a light system preference so the explicit choice is what changes.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );

    await app.tap(tester, find.text('Settings').first);
    await pumpFrames(tester, 8);
    await app.persistTap(tester, find.text('Dark'));
    await pumpFrames(tester, 8);

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
      reason: 'the whole app, not just the toggle, follows the choice',
    );
    // Still on Settings: a theme change must not reset navigation.
    expect(find.text('Appearance'), findsOneWidget);
    expect(app.settings.themeMode.value.name, 'dark');
  });

  appTest('the appearance controls persist across a restart', (
    tester,
    app,
  ) async {
    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await app.tap(tester, find.text('Settings').first);
    await pumpFrames(tester, 8);

    await app.persistTap(tester, find.text('Pitch black mode'));
    await app.persistTap(tester, find.text('Use dynamic color'));

    expect(app.settings.pitchBlack.value, isTrue);
    expect(app.settings.dynamicColor.value, isFalse);

    await app.restart(tester);

    // A relaunch starts on Discover; open Settings again.
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover after restart',
    );
    await app.tap(tester, find.text('Settings').first);
    await pumpFrames(tester, 8);

    expect(app.settings.pitchBlack.value, isTrue);
    expect(app.settings.dynamicColor.value, isFalse);
  });

  appTest('a live palette push repaints the app without resetting the route', (
    tester,
    app,
  ) async {
    final first = palette(0xFF3366CC);
    final second = palette(0xFFAA2244);
    var currentPalette = first;
    mockPaletteRead(() => currentPalette);

    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await waitForPrimary(tester, app, first, reason: 'palette adopted at startup');

    // Open Settings and scroll it so navigation + scroll state can be
    // checked after the palette changes.
    await app.tap(tester, find.text('Settings').first);
    await pumpFrames(tester, 8);
    expect(find.text('Appearance'), findsOneWidget);
    app.tabs.settings.jumpTo(60);
    await tester.pump();
    final offsetBefore = app.tabs.settings.offset;
    expect(offsetBefore, greaterThan(0));

    // Android notifies that the system wallpaper (and palette) changed.
    currentPalette = second;
    await sendPaletteChanged(tester);
    await pumpFrames(tester, 6);

    await waitForPrimary(
      tester,
      app,
      second,
      reason: 'live palette push drives the theme',
    );
    expect(
      find.text('Appearance'),
      findsOneWidget,
      reason: 'a palette change must not remount the router',
    );
    expect(
      app.tabs.settings.offset,
      offsetBefore,
      reason: 'the current screen keeps its scroll position',
    );
  });

  appTest('resuming the app refreshes the system palette', (tester, app) async {
    final first = palette(0xFF225533);
    final second = palette(0xFFCC8822);
    var currentPalette = first;
    mockPaletteRead(() => currentPalette);

    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await waitForPrimary(tester, app, first, reason: 'initial palette adopted');

    // The user changed the system wallpaper while the app was backgrounded;
    // no push arrives, so resume must re-read the palette.
    currentPalette = second;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await pumpFrames(tester, 6);

    await waitForPrimary(
      tester,
      app,
      second,
      reason: 'resume re-reads the palette',
    );
  });

  appTest('a failed palette read keeps the last valid colours', (
    tester,
    app,
  ) async {
    final first = palette(0xFF114477);
    var failRead = false;
    mockPaletteRead(() => first, throwOnRead: () => failRead);

    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await waitForPrimary(tester, app, first, reason: 'initial palette adopted');
    final valid = primaryOn(tester);

    // A transient platform failure must not blank or reset the palette.
    failRead = true;
    await sendPaletteChanged(tester);
    await pumpFrames(tester, 6);

    expect(primaryOn(tester), valid);
    expect(find.text('Discover'), findsWidgets);
  });

  appTest('palette pushes are ignored when dynamic color is off', (
    tester,
    app,
  ) async {
    final paletteB = palette(0xFF9955EE);
    mockPaletteRead(() => paletteB);

    await app.launch(tester);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('wallpaper-tile-alpha')),
      reason: 'discover feed',
    );
    await app.tap(tester, find.text('Settings').first);
    await pumpFrames(tester, 8);
    await app.persistTap(tester, find.text('Use dynamic color'));
    expect(app.settings.dynamicColor.value, isFalse);

    final staticPrimary = primaryOn(tester);
    await sendPaletteChanged(tester);
    await pumpFrames(tester, 6);

    expect(
      primaryOn(tester),
      staticPrimary,
      reason: 'the teal seed stays in charge when dynamic color is off',
    );
  });
}
