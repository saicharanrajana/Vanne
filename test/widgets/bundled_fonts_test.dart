import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanne/app/theme/app_theme.dart';

/// Why: the app used to fetch Outfit from fonts.gstatic.com at startup, so
/// first-frame latency and test determinism depended on the network. The font
/// is now bundled; these tests fail if the asset, its license, or the theme's
/// family and weight wiring is lost in a future refactor.
///
/// Engine behaviour behind the weight assertions (verified on an Android
/// emulator with the real bundled font, `TextPainter` widths at 40px for
/// "Weight ABCD"): plain base style = 243.02, `copyWith(w700)` = 250.56,
/// `copyWith(w800)` = 254.02, and w700 with an explicit
/// `FontVariation('wght', 700)` = 250.56. So ordinary `fontWeight` reaches
/// the variable axis natively — derived styles are not pinned — which is why
/// the theme intentionally sets no explicit `fontVariations`.

const _fontAsset = 'assets/fonts/Outfit-Variable.ttf';

/// Every weight the app asks for, including `w800` used by collection cards.
const _declaredWeights = <int>[400, 500, 600, 700, 800];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled Outfit asset and license are shipped', (tester) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();

    expect(assets, contains(_fontAsset));
    expect(assets, contains('assets/fonts/OFL.txt'));
    expect((await rootBundle.load(_fontAsset)).lengthInBytes, greaterThan(0));
  });

  testWidgets('FontManifest maps every app weight to the font', (tester) async {
    final raw = await rootBundle.loadString('FontManifest.json');
    final families = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final outfit = families.singleWhere((f) => f['family'] == 'Outfit');
    final fonts = (outfit['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    // One variable file registered per selectable weight: the engine can
    // then resolve fontWeight exactly instead of synthesizing bold.
    expect(fonts.map((f) => f['weight']), containsAll(_declaredWeights));
    expect(fonts.every((f) => f['asset'] == _fontAsset), isTrue);
  });

  testWidgets('theme uses Outfit without pinning the weight axis', (
    tester,
  ) async {
    final text = AppTheme.build(brightness: Brightness.dark).textTheme;

    for (final style in [
      text.displayLarge,
      text.displayMedium,
      text.displaySmall,
      text.headlineLarge,
      text.headlineMedium,
      text.headlineSmall,
      text.titleLarge,
      text.titleMedium,
      text.titleSmall,
      text.bodyLarge,
      text.bodyMedium,
      text.bodySmall,
      text.labelLarge,
      text.labelMedium,
      text.labelSmall,
    ]) {
      expect(style!.fontFamily, 'Outfit');
      // An explicit `wght` variation would survive copyWith and pin derived
      // styles to the base weight.
      expect(
        style.fontVariations,
        isNull,
        reason: 'A text style pins a weight axis',
      );
    }
    expect(text.bodyLarge!.fontWeight, FontWeight.w400);
    expect(text.displaySmall!.fontWeight, FontWeight.w700);
  });

  testWidgets('copyWith(fontWeight:) derives real 700/800 styles', (
    tester,
  ) async {
    final text = AppTheme.build(brightness: Brightness.light).textTheme;

    final bold = text.bodyLarge!.copyWith(fontWeight: FontWeight.w700);
    expect(bold.fontWeight, FontWeight.w700);
    expect(bold.fontVariations, isNull);
    expect(bold.fontFamily, 'Outfit');

    final extraBold = text.bodyLarge!.copyWith(fontWeight: FontWeight.w800);
    expect(extraBold.fontWeight, FontWeight.w800);
    expect(extraBold.fontVariations, isNull);
    expect(extraBold.fontFamily, 'Outfit');
  });
}
