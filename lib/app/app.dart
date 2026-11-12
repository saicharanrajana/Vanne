import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:signals/signals_flutter.dart';
import 'package:vanne/l10n/generated/app_localizations.dart';

import '../core/services/dynamic_palette_refresher.dart';
import 'dependencies.dart';
import 'router/app_route.dart';
import 'theme/app_theme.dart';
import '../core/storage/settings_store.dart' show AppThemeMode;
import '../features/settings/application/settings_controller.dart';
import '../shared/widgets/app_snack.dart';

/// Root widget.
///
/// Owns one [AppRouter] and rebuilds the M3E theme from settings
/// signals: dynamic color (Material You with teal fallback), pitch-black
/// surfaces and system/light/dark mode.
///
/// Dynamic schemes update on app resume and Android resource changes without
/// remounting the router or resetting screen state.
final class WallpaperApp extends StatefulWidget {
  const WallpaperApp({super.key});

  @override
  State<WallpaperApp> createState() => _WallpaperAppState();
}

final class _WallpaperAppState extends State<WallpaperApp> {
  final _router = AppRouter();
  final _dynamicPalette = DynamicPaletteController();
  late final AppLifecycleListener _paletteLifecycle;
  late final _routerConfig = _router.config(
    includePrefixMatches: true,
    deepLinkTransformer: appDeepLinkTransformer,
  );

  @override
  void dispose() {
    _paletteLifecycle.dispose();
    _dynamicPalette.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _paletteLifecycle = AppLifecycleListener(
      onResume: () => unawaited(_dynamicPalette.refresh()),
    );
    _dynamicPalette.start();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final settings = locator<SettingsController>();

    // Single SignalBuilder watches:
    // - settings.dynamicColor / themeMode / pitchBlack (via AppTheme)
    // - The last valid light/dark dynamic schemes.
    // Narrowing further would require splitting MaterialApp props, but the
    // entire MaterialApp must rebuild to propagate a new ColorScheme anyway,
    // so one builder is the minimal churn for this infrequent event.
    return SignalBuilder(
      builder: (context) {
        final useDynamic = settings.dynamicColor.value;
        final themeMode = switch (settings.themeMode.value) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        };
        final pitchBlack = settings.pitchBlack.value;
        final lightDynamic = _dynamicPalette.lightScheme.value;
        final darkDynamicLegacy = _dynamicPalette.darkScheme.value;
        // Pitch black overwrites the surface ladder, so it keeps the scheme it
        // has always used; normal dark uses the system-resolved surfaces.
        final darkDynamic =
            (pitchBlack
                ? darkDynamicLegacy
                : _dynamicPalette.darkSurfaceScheme.value) ??
            darkDynamicLegacy;

        return MaterialApp.router(
          title: 'Prisma Wallpapers',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: AppSnack.messengerKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.build(
            brightness: Brightness.light,
            dynamicScheme: useDynamic ? lightDynamic : null,
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            dynamicScheme: useDynamic ? darkDynamic : null,
            pitchBlack: pitchBlack,
          ),
          themeMode: themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(minScaleFactor: 0.8, maxScaleFactor: 1.15),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          routerConfig: _routerConfig,
        );
      },
    );
  }
}
