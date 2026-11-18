import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanne/app/theme/app_theme.dart';

/// Why: the app used to fetch Outfit from fonts.gstatic.com at startup, so
/// first-frame latency and test determinism depended on the network. The font
/// is now bundled; these tests fail if the asset, its license, or the theme's
/// family and weight wiring is lost in a future refactor.
///
/// The contract is app-owned: the licensed variable font is bundled, all
/// declared weights point to it, and theme styles leave the weight axis free.

const _fontAsset = 'assets/fonts/Outfit-Variable.ttf';

/// Every weight the app asks for, including `w800` used by collection cards.
const _declaredWeights = <int>[400, 500, 600, 700, 800];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled Outfit asset is licensed and used by the theme', (
    tester,
  ) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    expect(assets, contains(_fontAsset));
    expect(assets, contains('assets/fonts/OFL.txt'));
    expect((await rootBundle.load(_fontAsset)).lengthInBytes, greaterThan(0));

    final raw = await rootBundle.loadString('FontManifest.json');
    final families = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final outfit = families.singleWhere((f) => f['family'] == 'Outfit');
    final fonts = (outfit['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    // Keep the app-owned manifest wiring for every weight used by its theme.
    expect(fonts.map((f) => f['weight']), containsAll(_declaredWeights));
    expect(fonts.every((f) => f['asset'] == _fontAsset), isTrue);

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
      // Explicit variations would pin variable-font styles to one weight.
      expect(
        style.fontVariations,
        isNull,
        reason: 'A text style pins a weight axis',
      );
    }
    expect(text.bodyLarge!.fontWeight, FontWeight.w400);
    expect(text.displaySmall!.fontWeight, FontWeight.w700);
  });
}
