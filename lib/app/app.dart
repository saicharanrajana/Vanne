import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:signals/signals_flutter.dart';
import 'package:zenrouter/zenrouter.dart';

import '../core/services/dynamic_palette_refresher.dart';
import 'dependencies.dart';
import 'router/app_route.dart';
import 'theme/app_theme.dart';
import '../core/storage/settings_store.dart' show AppThemeMode;
import '../features/settings/application/settings_controller.dart';
import '../shared/widgets/app_snack.dart';

/// Root widget.
///
/// Owns one [AppCoordinator] and rebuilds the M3E theme from settings
/// signals: dynamic color (Material You with teal fallback), pitch-black
/// surfaces and system/light/dark mode.
///
/// Dynamic schemes are now reactive signals (`lightDynamicScheme` /
/// `darkDynamicScheme` in `dynamic_palette_refresher.dart`) driven by a
/// `futureSignal` that re-fetches `CorePalette` when the tick bumps after
/// wallpaper apply — no `ValueKey` remount needed.
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

    // Single SignalBuilder watches:
    // - settings.dynamicColor / themeMode / pitchBlack (via AppTheme)
    // - lightDynamicScheme / darkDynamicScheme (via futureSignal → computed)
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
        final lightDynamic = lightDynamicScheme.value;
        final darkDynamicRaw = darkDynamicScheme.value;

        return MaterialApp(
          title: 'Prisma Wallpapers',
          debugShowCheckedModeBanner: false,
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
            dynamicScheme: useDynamic ? darkDynamicRaw : null,
            pitchBlack: pitchBlack,
          ),
          themeMode: themeMode,
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
            initialUri: Uri.parse('/'),
          ),
        );
      },
    );
  }
}
