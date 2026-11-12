import 'package:material_ui/material_ui.dart';

/// Solid colour of the app's launch window, day and night.
///
/// One visual contract, consumed by both halves of startup:
/// * Android paints it behind the system splash icon (`launch_colors.xml`,
///   wired through `launch_background.xml` and the API 31+ `LaunchTheme`), and
/// * Flutter paints it as the first frame (`AppStartup`'s launch surface).
///
/// The system splash uses only the transparent launcher foreground layer, not
/// the adaptive icon with its fixed-white background. This keeps the splash
/// white/black by theme while the home-screen icon stays white in both modes.
///
/// Pure white/black is deliberate: the icon needs a neutral, predictable field
/// in each mode. The app's own surfaces are slightly tinted, so the first real
/// screen does transition from this launch colour — that is the accepted
/// trade-off for an icon/splash pair that is seamless by construction.
/// `test/widgets/launch_transition_test.dart` and
/// `test/widgets/launcher_icon_test.dart` fail if any of the three sides drift.
abstract final class LaunchBackground {
  /// Matches `values/launch_colors.xml`; the launcher icon remains white.
  static const light = Color(0xFFFFFFFF);

  /// Matches `values-night/launch_colors.xml`.
  static const dark = Color(0xFF000000);

  static Color of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
