import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vanne/app/app_startup.dart';
import 'package:vanne/app/launch_background.dart';

/// Why: between Android's system splash (the real launcher icon on a solid
/// colour) and the first real screen, the app drew *its own* unrelated icon on
/// a slightly different background. On a debug build the bootstrap window is
/// long enough to see that as a "random icon" flash.
///
/// The replacement contract these tests pin:
/// 1. the Flutter launch frame is plain — no icon, no mark, nothing to flash;
/// 2. it is painted in the exact colour Android uses for its launch window, so
///    the system splash icon simply fades out over an identical background;
/// 3. the splash uses only the transparent launcher foreground, allowing its
///    background to stay white/black independently of the fixed-white launcher;
/// 4. the Android resources are mirrored in the regeneration templates, so
///    `flutter create` + `tool/apply_android_overrides.sh` cannot lose them.

const _resDir = 'android/app/src/main/res';
const _templateResDir = 'tool/android_overrides/res';

class _NeverReady extends StatelessWidget {
  const _NeverReady();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  return file.readAsStringSync();
}

/// Extracts `<color name="launch_background">#AARRGGBB</color>` from a
/// resource file. Only the app's own launch colour is parsed, so unrelated
/// colours (list icons, brand seeds) are never confused with it.
String _launchColor(String path) {
  final match = RegExp(
    r'<color\s+name="launch_background"\s*>\s*(#[0-9A-Fa-f]{8})\s*</color>',
  ).firstMatch(_read(path));
  expect(match, isNotNull, reason: '$path must define launch_background');
  return match!.group(1)!.toUpperCase();
}

String _argb(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

void main() {
  group('Flutter launch frame', () {
    testWidgets('paints the splash colour and nothing else', (tester) async {
      final initialized = Completer<void>();
      addTearDown(() {
        if (!initialized.isCompleted) initialized.complete();
      });

      await tester.pumpWidget(
        AppStartup(
          initialize: () => initialized.future,
          child: const _NeverReady(),
        ),
      );

      expect(find.byKey(const ValueKey('startup-surface')), findsOneWidget);
      // Nothing to flash: no hidden icon, no placeholder artwork.
      expect(find.byType(Icon), findsNothing);
      expect(find.byType(Image), findsNothing);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, LaunchBackground.light);
    });

    testWidgets('follows the platform brightness in dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final initialized = Completer<void>();
      addTearDown(() {
        if (!initialized.isCompleted) initialized.complete();
      });

      await tester.pumpWidget(
        AppStartup(
          initialize: () => initialized.future,
          child: const _NeverReady(),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, LaunchBackground.dark);
    });
  });

  group('Native splash matches the Flutter launch frame', () {
    test('day/night launch colors match the neutral Flutter colors', () {
      // Native splash resources and Flutter's first frame share exact values;
      // the neutral colors prevent a visible field around the launch icon.
      expect(
        _launchColor('$_resDir/values/launch_colors.xml'),
        _argb(LaunchBackground.light),
      );
      expect(
        _launchColor('$_resDir/values-night/launch_colors.xml'),
        _argb(LaunchBackground.dark),
      );
      expect(LaunchBackground.light, const Color(0xFFFFFFFF));
      expect(LaunchBackground.dark, const Color(0xFF000000));
    });

    test('launch window uses the colour and draws no app-side icon', () {
      for (final drawable in [
        '$_resDir/drawable/launch_background.xml',
        '$_resDir/drawable-v21/launch_background.xml',
      ]) {
        final xml = _read(drawable);
        expect(xml, contains('@color/launch_background'), reason: drawable);
        // A bitmap here would be a second, app-drawn splash icon.
        expect(xml, isNot(contains('<bitmap')), reason: drawable);
      }
    });

    test('API 31+ splash uses the theme colour and transparent mark layer', () {
      for (final styles in [
        '$_resDir/values-v31/styles.xml',
        '$_resDir/values-night-v31/styles.xml',
      ]) {
        final xml = _read(styles);
        expect(
          xml,
          contains(
            '<item name="android:windowSplashScreenBackground">'
            '@color/launch_background</item>',
          ),
          reason: styles,
        );
        expect(
          xml,
          contains('@drawable/ic_launcher_foreground'),
          reason:
              '$styles must use the transparent mark, not the white launcher tile',
        );
        expect(
          xml,
          isNot(contains('@mipmap/ic_launcher')),
          reason:
              '$styles must not place the white launcher tile on dark splash',
        );
      }
    });

    test('regeneration templates mirror the splash resources', () {
      // `flutter create .` restores the template splash; the override script
      // must be able to put these files back.
      for (final rel in [
        'values/launch_colors.xml',
        'values-night/launch_colors.xml',
        'values/colors.xml',
        'drawable/launch_background.xml',
        'drawable-v21/launch_background.xml',
        'values-v31/styles.xml',
        'values-night-v31/styles.xml',
      ]) {
        expect(
          _read('$_templateResDir/$rel'),
          _read('$_resDir/$rel'),
          reason: 'template copy of $rel must match the live resource',
        );
      }
    });
  });
}
