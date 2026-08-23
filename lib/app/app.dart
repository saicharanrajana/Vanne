import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:signals/signals_flutter.dart';
import 'package:zenrouter/zenrouter.dart';

import 'dependencies.dart';
import 'router/app_route.dart';
import 'theme/app_theme.dart';
import '../features/settings/application/settings_controller.dart';
import '../core/storage/settings_store.dart' show AppThemeMode;
import '../shared/widgets/app_snack.dart';

/// Root widget.
///
/// Owns one [AppCoordinator] and rebuilds the M3E theme from settings
/// signals: dynamic color (Material You with teal fallback), pitch-black
/// surfaces and system/light/dark mode.
final class WallpaperApp extends StatefulWidget {
  const WallpaperApp({super.key});

  @override
  State<WallpaperApp> createState() => _WallpaperAppState();
}

final class _WallpaperAppState extends State<WallpaperApp> {
  final _coordinator = AppCoordinator();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final settings = locator<SettingsController>();

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return SignalBuilder(
          builder: (context) {
            final useDynamic = settings.dynamicColor.value;
            final themeMode = switch (settings.themeMode.value) {
              AppThemeMode.system => ThemeMode.system,
              AppThemeMode.light => ThemeMode.light,
              AppThemeMode.dark => ThemeMode.dark,
            };

            return MaterialApp(
              title: 'Prisma Wallpapers',
              debugShowCheckedModeBanner: false,
              // Root messenger for AppSnack — snacks never depend on
              // ambient context lookups (see AppSnack.messengerKey).
              scaffoldMessengerKey: AppSnack.messengerKey,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: AppTheme.build(
                brightness: Brightness.light,
                dynamicScheme: useDynamic ? lightDynamic : null,
              ),
              darkTheme: AppTheme.build(
                brightness: Brightness.dark,
                dynamicScheme: useDynamic ? darkDynamic : null,
                pitchBlack: settings.pitchBlack.value,
              ),
              themeMode: themeMode,
              // Cap accessibility text scaling slightly above the default
              // range: full unbounded scaling breaks the masonry grid
              // overlays and sheet layouts. Real a11y scaling (up to ~1.15)
              // still applies.
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(minScaleFactor: 0.8, maxScaleFactor: 1.15),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
              home: CoordinatorView(
                coordinator: _coordinator,
                // Headless host: without an initialUri the root stack
                // stays empty and renders nothing (blank screen).
                initialUri: Uri.parse('/'),
              ),
            );
          },
        );
      },
    );
  }
}
