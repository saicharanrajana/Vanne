import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:dynamic_color/dynamic_color.dart';
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals.dart';

/// Tick that drives [corePaletteSignal] — bumping it forces a re-fetch.
final dynamicPaletteTick = signal(0);

Timer? _debounceTimer;

/// Requests a re-fetch of the system Material You palette.
///
/// Debounces rapid calls (e.g. Home → Lock) into a single fetch and delays
/// ~800ms so the OS has time to extract colors from the new wallpaper
/// (`WallpaperManager.setStream` → `systemui-dynamic.frro` RRO).
Future<void> requestDynamicPaletteRefresh() {
  _debounceTimer?.cancel();
  final completer = Completer<void>();
  _debounceTimer = Timer(const Duration(milliseconds: 800), () {
    try {
      dynamicPaletteTick.value++;
    } catch (_) {}
    completer.complete();
  });
  return completer.future;
}

/// Async palette — re-runs when [dynamicPaletteTick] changes.
///
/// `futureSignal` ensures single evaluation, handles loading/error, and
/// auto-disposes the previous Future (per `signals-dart/async/future_signal.md`).
final corePaletteSignal = futureSignal(() async {
  // Subscribe to tick.
  dynamicPaletteTick.value;
  return await DynamicColorPlugin.getCorePalette();
});

/// Memoized light/dark ColorSchemes derived from the palette.
///
/// `computed` only recomputes when the palette actually changes, so
/// `AppTheme.build` isn't re-run on unrelated signal changes.
final lightDynamicScheme = computed<ColorScheme?>(() {
  final state = corePaletteSignal.value;
  return switch (state) {
    // ignore: deprecated_member_use
    AsyncData<CorePalette?> data => data.value?.toColorScheme(),
    _ => null,
  };
});

final darkDynamicScheme = computed<ColorScheme?>(() {
  final state = corePaletteSignal.value;
  return switch (state) {
    // ignore: deprecated_member_use
    AsyncData<CorePalette?> data =>
      // ignore: deprecated_member_use
      data.value?.toColorScheme(brightness: Brightness.dark),
    _ => null,
  };
});
