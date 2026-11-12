import 'dart:typed_data';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart' hide SearchController;
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/app.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/collections/collections_repository.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/storage/settings_store.dart';
import 'package:vanne/core/downloads/download_destination_controller.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/discover/application/discover_controller.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:vanne/features/search/application/search_controller.dart';
import 'package:vanne/features/settings/application/settings_controller.dart';
import 'package:vanne/features/settings/presentation/settings_screen.dart';

const _events = 'com.saicharanrajana.vanne/dynamic_palette';
const _codec = StandardMethodCodec();

/// Surface roles the plugin previously took from a regenerated seed.
const _surfaceRoles = <String>[
  'surface',
  'surfaceDim',
  'surfaceBright',
  'surfaceContainerLowest',
  'surfaceContainerLow',
  'surfaceContainer',
  'surfaceContainerHigh',
  'surfaceContainerHighest',
];

/// Dark-mode tones Material assigns on the neutral palette.
const _darkSurfaceTones = <String, int>{
  'surface': 6,
  'surfaceDim': 6,
  'surfaceBright': 24,
  'surfaceContainerLowest': 4,
  'surfaceContainerLow': 10,
  'surfaceContainer': 12,
  'surfaceContainerHigh': 17,
  'surfaceContainerHighest': 22,
};

class _EmptyRepository implements WallpaperRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<SearchOutcome> search({
    String query = '',
    Set<WallhavenColor> colors = const {},
    List<WallhavenCategory> categories = const [],
    FeedFilter filter = const FeedFilter(),
    int page = 1,
    String? seed,
  }) async => const SearchOutcome(
    page: PaginatedResult<Wallpaper>(
      items: [],
      meta: SearchMeta(currentPage: 1, lastPage: 1, perPage: 24),
    ),
    nsfwClamped: false,
  );
}

/// Builds a platform palette with the given accent and neutral sources.
Int32List _palette({required int accent, int? neutral}) {
  // ignore: deprecated_member_use
  final accentPalette = CorePalette.of(accent).asList();
  if (neutral == null) return Int32List.fromList(accentPalette);
  // ignore: deprecated_member_use
  final neutralPalette = CorePalette.of(neutral).asList();
  // Sections: primary, secondary, tertiary, neutral, neutral variant.
  return Int32List.fromList([
    ...accentPalette.sublist(0, 39),
    ...neutralPalette.sublist(39),
  ]);
}

// ignore: deprecated_member_use
CorePalette _parse(List<int> list) => CorePalette.fromList(list);

Map<String, Object?> _roles(ColorScheme scheme) => {
  'brightness': scheme.brightness,
  'primary': scheme.primary,
  'onPrimary': scheme.onPrimary,
  'primaryContainer': scheme.primaryContainer,
  'onPrimaryContainer': scheme.onPrimaryContainer,
  'primaryFixed': scheme.primaryFixed,
  'primaryFixedDim': scheme.primaryFixedDim,
  'onPrimaryFixed': scheme.onPrimaryFixed,
  'onPrimaryFixedVariant': scheme.onPrimaryFixedVariant,
  'secondary': scheme.secondary,
  'onSecondary': scheme.onSecondary,
  'secondaryContainer': scheme.secondaryContainer,
  'onSecondaryContainer': scheme.onSecondaryContainer,
  'secondaryFixed': scheme.secondaryFixed,
  'secondaryFixedDim': scheme.secondaryFixedDim,
  'onSecondaryFixed': scheme.onSecondaryFixed,
  'onSecondaryFixedVariant': scheme.onSecondaryFixedVariant,
  'tertiary': scheme.tertiary,
  'onTertiary': scheme.onTertiary,
  'tertiaryContainer': scheme.tertiaryContainer,
  'onTertiaryContainer': scheme.onTertiaryContainer,
  'tertiaryFixed': scheme.tertiaryFixed,
  'tertiaryFixedDim': scheme.tertiaryFixedDim,
  'onTertiaryFixed': scheme.onTertiaryFixed,
  'onTertiaryFixedVariant': scheme.onTertiaryFixedVariant,
  'error': scheme.error,
  'onError': scheme.onError,
  'errorContainer': scheme.errorContainer,
  'onErrorContainer': scheme.onErrorContainer,
  'surface': scheme.surface,
  'onSurface': scheme.onSurface,
  'surfaceDim': scheme.surfaceDim,
  'surfaceBright': scheme.surfaceBright,
  'surfaceContainerLowest': scheme.surfaceContainerLowest,
  'surfaceContainerLow': scheme.surfaceContainerLow,
  'surfaceContainer': scheme.surfaceContainer,
  'surfaceContainerHigh': scheme.surfaceContainerHigh,
  'surfaceContainerHighest': scheme.surfaceContainerHighest,
  'onSurfaceVariant': scheme.onSurfaceVariant,
  'outline': scheme.outline,
  'outlineVariant': scheme.outlineVariant,
  'shadow': scheme.shadow,
  'scrim': scheme.scrim,
  'inverseSurface': scheme.inverseSurface,
  'onInverseSurface': scheme.onInverseSurface,
  'inversePrimary': scheme.inversePrimary,
  'surfaceTint': scheme.surfaceTint,
  // ignore: deprecated_member_use
  'background': scheme.background,
  // ignore: deprecated_member_use
  'onBackground': scheme.onBackground,
  // ignore: deprecated_member_use
  'surfaceVariant': scheme.surfaceVariant,
};

/// Asserts two schemes match on every public role, naming the first mismatch.
///
/// `ColorScheme.operator ==` already compares all roles; the name map is only
/// there so a failure says which role drifted.
void _expectSameScheme(
  ColorScheme actual,
  ColorScheme expected,
  String reason,
) {
  final actualRoles = _roles(actual);
  final expectedRoles = _roles(expected);
  for (final role in expectedRoles.keys) {
    expect(actualRoles[role], expectedRoles[role], reason: '$reason → $role');
  }
  expect(actual, expected, reason: reason);
}

Color _role(ColorScheme scheme, String role) => switch (role) {
  'surface' => scheme.surface,
  'surfaceDim' => scheme.surfaceDim,
  'surfaceBright' => scheme.surfaceBright,
  'surfaceContainerLowest' => scheme.surfaceContainerLowest,
  'surfaceContainerLow' => scheme.surfaceContainerLow,
  'surfaceContainer' => scheme.surfaceContainer,
  'surfaceContainerHigh' => scheme.surfaceContainerHigh,
  'surfaceContainerHighest' => scheme.surfaceContainerHighest,
  _ => throw ArgumentError(role),
};

Future<SettingsController> _registerDependencies() async {
  final repository = _EmptyRepository();
  final favorites = FavoritesController(FavoritesRepository());
  final collections = CollectionsController(CollectionsRepository());
  await favorites.restore();
  await collections.restore();
  final settings = SettingsController(SettingsStore(), repository);
  locator
    ..registerSingleton<SettingsController>(settings)
    ..registerSingleton<FavoritesController>(favorites)
    ..registerSingleton<CollectionsController>(collections)
    ..registerSingleton<TabScrollCoordinator>(
      TabScrollCoordinator(),
      dispose: (value) => value.dispose(),
    )
    ..registerFactory<DiscoverController>(() => DiscoverController(repository))
    ..registerFactory<SearchController>(() => SearchController(repository))
    ..registerSingleton<DownloadDestinationController>(
      DownloadDestinationController(SettingsStore()),
    );
  return settings;
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _notify(WidgetTester tester) async {
  tester.binding.channelBuffers.push(
    _events,
    _codec.encodeMethodCall(const MethodCall('changed')),
    (_) {},
  );
  await _flush(tester);
}

MaterialApp _app(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

/// Pumps the app against a platform palette and a dark theme preference.
Future<void> _pumpDarkApp(
  WidgetTester tester, {
  required SettingsController settings,
  required List<int> palette,
}) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    DynamicColorPlugin.channel,
    (_) async => palette,
  );
  settings.themeMode.value = AppThemeMode.dark;
  await tester.pumpWidget(const WallpaperApp());
  await _flush(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('normal dark surfaces come from the system neutral palette', (
    tester,
  ) async {
    final settings = await _registerDependencies();
    final palette = _palette(accent: 0xff3366cc);
    final platformNeutral = _parse(palette).neutral;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _flush(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DynamicColorPlugin.channel,
        null,
      );
      await locator.reset();
    });

    await _pumpDarkApp(tester, settings: settings, palette: palette);

    final scheme = _app(tester).darkTheme!.colorScheme;
    for (final entry in _darkSurfaceTones.entries) {
      expect(
        _role(scheme, entry.key),
        Color(platformNeutral.get(entry.value)),
        reason:
            '${entry.key} must use the system neutral tone '
            '${entry.value}, not a reseeded neutral',
      );
    }
    // Regenerated neutrals carry tonal-spot chroma; the system ones must win.
    expect(
      scheme.surfaceContainerHigh,
      isNot(Color(_parse(palette).neutralVariant.get(17))),
    );

    // The whole normal-dark scheme is the plugin's conversion with exactly
    // those eight surface roles replaced — nothing else may move.
    // ignore: deprecated_member_use
    final legacy = _parse(palette).toColorScheme(brightness: Brightness.dark);
    // AppTheme harmonizes after selecting the scheme, so the reference must
    // too; harmonization only touches error roles but is part of the output.
    _expectSameScheme(
      scheme,
      legacy
          .copyWith(
            surface: Color(platformNeutral.get(6)),
            surfaceDim: Color(platformNeutral.get(6)),
            surfaceBright: Color(platformNeutral.get(24)),
            surfaceContainerLowest: Color(platformNeutral.get(4)),
            surfaceContainerLow: Color(platformNeutral.get(10)),
            surfaceContainer: Color(platformNeutral.get(12)),
            surfaceContainerHigh: Color(platformNeutral.get(17)),
            surfaceContainerHighest: Color(platformNeutral.get(22)),
          )
          .harmonized(),
      'normal dynamic dark',
    );
  });

  testWidgets(
    'same accents with different neutrals produce different surfaces',
    (tester) async {
      final settings = await _registerDependencies();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await _flush(tester);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          DynamicColorPlugin.channel,
          null,
        );
        await locator.reset();
      });

      final first = _palette(accent: 0xff3366cc, neutral: 0xff3366cc);
      await _pumpDarkApp(tester, settings: settings, palette: first);
      final firstScheme = _app(tester).darkTheme!.colorScheme;

      final second = _palette(accent: 0xff3366cc, neutral: 0xffee6600);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DynamicColorPlugin.channel,
        (_) async => second,
      );
      await _notify(tester);
      final secondScheme = _app(tester).darkTheme!.colorScheme;

      // Accents are identical, only the system neutrals changed.
      expect(secondScheme.primary, firstScheme.primary);
      expect(
        secondScheme.surfaceContainerHigh,
        isNot(firstScheme.surfaceContainerHigh),
      );
      expect(
        secondScheme.surfaceContainerHigh,
        Color(_parse(second).neutral.get(17)),
      );
      expect(
        firstScheme.surfaceContainerHigh,
        Color(_parse(first).neutral.get(17)),
      );
    },
  );

  testWidgets('light, pitch-black, accents and fallback keep their colors', (
    tester,
  ) async {
    final settings = await _registerDependencies();
    final palette = _palette(accent: 0xff3366cc);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _flush(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DynamicColorPlugin.channel,
        null,
      );
      await locator.reset();
    });

    await _pumpDarkApp(tester, settings: settings, palette: palette);
    final app = _app(tester);
    // The plugin's own conversion, used as the reference for unchanged modes.
    // ignore: deprecated_member_use
    final legacyDark = _parse(palette)
        .toColorScheme(brightness: Brightness.dark);

    // Light mode: the app must build exactly what it built before.
    _expectSameScheme(
      app.theme!.colorScheme,
      AppTheme.build(
        brightness: Brightness.light,
        // ignore: deprecated_member_use
        dynamicScheme: _parse(palette).toColorScheme(),
      ).colorScheme,
      'light mode',
    );

    // Normal dark is the corrected mode. Every role outside the surface family
    // must still equal the untouched build of the plugin's own scheme.
    final corrected = app.darkTheme!.colorScheme;
    final legacyBuild = AppTheme.build(
      brightness: Brightness.dark,
      dynamicScheme: legacyDark,
    ).colorScheme;
    expect(corrected, isNot(legacyBuild), reason: 'normal dark is corrected');
    final correctedRoles = _roles(corrected);
    final legacyRoles = _roles(legacyBuild);
    for (final role in legacyRoles.keys) {
      if (_surfaceRoles.contains(role)) continue;
      expect(
        correctedRoles[role],
        legacyRoles[role],
        reason: 'normal dark → $role must not change',
      );
    }

    settings.pitchBlack.value = true;
    await _flush(tester);
    _expectSameScheme(
      _app(tester).darkTheme!.colorScheme,
      AppTheme.build(
        brightness: Brightness.dark,
        dynamicScheme: legacyDark,
        pitchBlack: true,
      ).colorScheme,
      'pitch black',
    );

    settings.dynamicColor.value = false;
    settings.pitchBlack.value = false;
    await _flush(tester);
    _expectSameScheme(
      _app(tester).darkTheme!.colorScheme,
      AppTheme.build(brightness: Brightness.dark).colorScheme,
      'dynamic color off fallback',
    );
  });

  testWidgets('corrected surfaces reach the settings screen', (tester) async {
    final settings = await _registerDependencies();
    final palette = _palette(accent: 0xff3366cc);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _flush(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DynamicColorPlugin.channel,
        null,
      );
      await locator.reset();
    });

    await _pumpDarkApp(tester, settings: settings, palette: palette);
    await tester.tap(find.text('Settings').last);
    await _flush(tester);

    final element = tester.element(find.byType(SettingsScreen));
    final live = Theme.of(element).colorScheme;
    final expected = _app(tester).darkTheme!.colorScheme;
    expect(live.surfaceContainerHighest, expected.surfaceContainerHighest);
    expect(live.surfaceContainerHigh, expected.surfaceContainerHigh);
    expect(
      live.surfaceContainerHighest,
      Color(_parse(palette).neutral.get(22)),
    );
  });
}
