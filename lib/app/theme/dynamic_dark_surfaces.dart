import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

/// Resolves the dark surface ladder from the system's real tonal palettes.
///
/// `dynamic_color`'s converter keeps Android's accents and neutral roles but
/// leaves `surfaceDim`, `surfaceBright` and the `surfaceContainer*` family from
/// `ColorScheme.fromSeed`, which regenerates neutrals at tonal-spot chroma.
/// Those regenerated grays are then used by search bars, cards, sheets and
/// empty states, while every other role uses the wallpaper's own neutrals.
///
/// This maps the same roles from [palette] with Material's own
/// [DynamicScheme] resolver, so the whole surface family shares one source.
/// Accent, error, outline and inverse roles are left exactly as the plugin
/// produced them.
///
/// Applied only to normal dark mode. Light mode already looks correct, and
/// pitch-black replaces the surfaces with its explicit black ladder, so both
/// keep their current values.
ColorScheme dynamicDarkSurfaceScheme(
  // CorePalette is the type exposed by dynamic_color's public API.
  // ignore: deprecated_member_use
  CorePalette palette, {
  required ColorScheme legacy,
}) {
  final scheme = DynamicScheme(
    // Only these surface roles are read, so the source color just anchors the
    // scheme; it does not replace any of the supplied palettes.
    sourceColorHct: Hct.fromInt(palette.primary.get(70)),
    variant: Variant.tonalSpot,
    isDark: true,
    primaryPalette: palette.primary,
    secondaryPalette: palette.secondary,
    tertiaryPalette: palette.tertiary,
    neutralPalette: palette.neutral,
    neutralVariantPalette: palette.neutralVariant,
    errorPalette: palette.error,
  );

  return legacy.copyWith(
    surface: Color(scheme.surface),
    surfaceDim: Color(scheme.surfaceDim),
    surfaceBright: Color(scheme.surfaceBright),
    surfaceContainerLowest: Color(scheme.surfaceContainerLowest),
    surfaceContainerLow: Color(scheme.surfaceContainerLow),
    surfaceContainer: Color(scheme.surfaceContainer),
    surfaceContainerHigh: Color(scheme.surfaceContainerHigh),
    surfaceContainerHighest: Color(scheme.surfaceContainerHighest),
  );
}
