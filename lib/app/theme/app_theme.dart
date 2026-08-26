import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

import 'app_shapes.dart';
import 'app_typography.dart';

/// Application theme system.
///
/// One teal-seeded design language, three layered variations:
/// 1. light / dark schemes generated from the seed,
/// 2. Android dynamic color (Material You) mapped onto the same roles,
/// 3. pitch-black mode — the dark scheme with surfaces collapsed to true
///    black while preserving every other semantic relationship.
///
/// UI code reads semantic roles only (`Theme.of(context).colorScheme`);
/// no widget ever hard-codes a color from here.
abstract final class AppTheme {
  /// Teal seed — the brand fallback when dynamic color is off or
  /// unsupported.
  static const seed = Color(0xFF00897B);

  /// Builds theme data for [brightness], optionally derived from a
  /// Material You palette and/or flattened to pitch black.
  ///
  /// When [pitchBlack] is true and [brightness] is dark, the dark
  /// ThemeData is taken as-is and only the surface roles are overridden
  /// to true black — exactly `darkThemeData.copyWith(selective changes)`.
  static ThemeData build({
    required Brightness brightness,
    ColorScheme? dynamicScheme,
    bool pitchBlack = false,
  }) {
    final base = dynamicScheme != null && dynamicScheme.brightness == brightness
        ? dynamicScheme
        : ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    // Harmonize first so seed/dynamic colors are fully resolved, then
    // selectively override surfaces to true black — guarantees surfaces
    // stay black instead of being shifted by harmonization.
    final harmonized = base.harmonized();
    final effective = pitchBlack && brightness == Brightness.dark
        ? toPitchBlack(harmonized)
        : harmonized;
    final textTheme = buildAppTextTheme(effective);
    final fieldRadius = BorderRadius.circular(AppShapes.large);
    final fieldBorder = OutlineInputBorder(
      borderRadius: fieldRadius,
      borderSide: BorderSide(color: effective.outlineVariant),
    );
    final focusedFieldBorder = OutlineInputBorder(
      borderRadius: fieldRadius,
      borderSide: BorderSide(color: effective.primary, width: 2),
    );
    final errorFieldBorder = OutlineInputBorder(
      borderRadius: fieldRadius,
      borderSide: BorderSide(color: effective.error),
    );
    final focusedErrorFieldBorder = OutlineInputBorder(
      borderRadius: fieldRadius,
      borderSide: BorderSide(color: effective.error, width: 2),
    );
    final disabledFieldBorder = OutlineInputBorder(
      borderRadius: fieldRadius,
      borderSide: BorderSide(
        color: effective.onSurface.withValues(alpha: 0.12),
      ),
    );
    const noSplash = ButtonStyle(
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    );
    return ThemeData(
      colorScheme: effective,
      scaffoldBackgroundColor: effective.surface,
      canvasColor: effective.surface,
      useMaterial3: true,
      textTheme: textTheme,
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: effective.primary.withValues(alpha: 0.30),
        selectionHandleColor: effective.primary,
        cursorColor: effective.primary,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        labelStyle: WidgetStateTextStyle.resolveWith((states) {
          final color = states.contains(WidgetState.error)
              ? effective.error
              : states.contains(WidgetState.focused)
              ? effective.primary
              : effective.onSurfaceVariant;
          return textTheme.bodyLarge!.copyWith(color: color);
        }),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          final color = states.contains(WidgetState.error)
              ? effective.error
              : states.contains(WidgetState.focused)
              ? effective.primary
              : effective.onSurfaceVariant;
          return textTheme.labelMedium!.copyWith(color: color);
        }),
        hintStyle: textTheme.bodyLarge!.copyWith(
          color: effective.onSurfaceVariant,
        ),
        helperStyle: textTheme.labelSmall!.copyWith(
          color: effective.onSurfaceVariant,
        ),
        errorStyle: textTheme.labelSmall!.copyWith(color: effective.error),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        constraints: const BoxConstraints(minHeight: 56),
        prefixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return effective.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.error)) return effective.error;
          if (states.contains(WidgetState.focused)) return effective.primary;
          return effective.onSurfaceVariant;
        }),
        suffixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return effective.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.error)) return effective.error;
          if (states.contains(WidgetState.focused)) return effective.primary;
          return effective.onSurfaceVariant;
        }),
        focusColor: Colors.transparent,
        hoverColor: effective.primary.withValues(alpha: 0.04),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: focusedFieldBorder,
        errorBorder: errorFieldBorder,
        focusedErrorBorder: focusedErrorFieldBorder,
        disabledBorder: disabledFieldBorder,
        alignLabelWithHint: true,
      ),
      // Disable ripple/highlight globally — custom design language.
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      chipTheme: ChipThemeData(
        backgroundColor: effective.surfaceContainerLow,
        selectedColor: effective.secondaryContainer,
        checkmarkColor: effective.onSecondaryContainer,
        labelStyle: TextStyle(color: effective.onSurfaceVariant),
        secondaryLabelStyle: TextStyle(color: effective.onSecondaryContainer),
        secondarySelectedColor: effective.secondaryContainer,
        side: BorderSide(color: effective.outlineVariant),
        shape: StadiumBorder(side: BorderSide(color: effective.outlineVariant)),
        showCheckmark: true,
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(effective.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(0),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStatePropertyAll(effective.surfaceContainerHigh),
        hintStyle: WidgetStatePropertyAll(
          TextStyle(color: effective.onSurfaceVariant),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(color: effective.onSurface),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      iconButtonTheme: const IconButtonThemeData(style: noSplash),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        splashColor: Colors.transparent,
      ),
      textButtonTheme: const TextButtonThemeData(style: noSplash),
      elevatedButtonTheme: const ElevatedButtonThemeData(style: noSplash),
      outlinedButtonTheme: const OutlinedButtonThemeData(style: noSplash),
      filledButtonTheme: const FilledButtonThemeData(style: noSplash),
      menuButtonTheme: const MenuButtonThemeData(style: noSplash),
      segmentedButtonTheme: const SegmentedButtonThemeData(style: noSplash),
      navigationBarTheme: NavigationBarThemeData(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      tabBarTheme: TabBarThemeData(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
      ),
      checkboxTheme: CheckboxThemeData(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashRadius: 0,
      ),
      radioTheme: RadioThemeData(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashRadius: 0,
      ),
      switchTheme: SwitchThemeData(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        overlayColor: Colors.transparent,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      toggleButtonsTheme: const ToggleButtonsThemeData(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      searchViewTheme: SearchViewThemeData(backgroundColor: effective.surface),
    );
  }

  /// Collapses dark surfaces to a true-black ladder while keeping every
  /// other role (primary, containers, error, expressive accents) intact.
  ///
  /// Hierarchy is preserved through near-black steps so elevation still
  /// reads on AMOLED panels:
  /// lowest `#000000` → low `#050505` → container `#0A0A0A` → high
  /// `#101010` → highest `#161616`.
  ///
  /// Public so wallpaper-derived schemes (detail sheet) can honor
  /// pitch-black mode without duplicating the ladder.
  static ColorScheme toPitchBlack(ColorScheme dark) => dark.copyWith(
    surface: const Color(0xFF000000),
    surfaceDim: const Color(0xFF000000),
    surfaceContainerLowest: const Color(0xFF000000),
    surfaceContainerLow: const Color(0xFF050505),
    surfaceContainer: const Color(0xFF0A0A0A),
    surfaceContainerHigh: const Color(0xFF101010),
    surfaceContainerHighest: const Color(0xFF161616),
  );
}
