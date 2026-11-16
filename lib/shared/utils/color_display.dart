import 'dart:math' as math;

import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

import 'hex_color.dart';

/// Presentation helpers for arbitrary wallpaper colors.
///
/// Nothing here writes color names back to storage: a saved collection keeps
/// its original hex name as its identity, while these helpers only make that
/// identity readable on screen.
abstract final class ColorDisplay {
  /// Minimum WCAG contrast for both a color card's title and its hex.
  static const double minimumContrast = 4.5;

  /// Minimum contrast for a selection stroke against the card it outlines.
  ///
  /// Deliberately well below [minimumContrast]: a stroke only has to be
  /// noticed against its card, and a text-grade tone turns into glare on dark
  /// cards and a near-black band on pale ones. This is the usual threshold for
  /// a non-text boundary, and it is only a floor — the tone targets below
  /// decide how the stroke actually looks.
  static const double minimumSelectionContrast = 3.0;

  /// Converts Wallhaven's `#rgb` / `#rrggbb` into normalized `#RRGGBB`.
  static String? normalizedHex(String raw) {
    final color = parseHexColor(raw);
    if (color == null) return null;
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// Normalizes a wallpaper palette into a small list of `#RRGGBB` values.
  ///
  /// Unparseable entries are dropped, duplicates collapsed, and the list is
  /// capped so a cover's palette stays a summary rather than a copy of every
  /// colour the API returned.
  static List<String> normalizedPalette(Iterable<String> raw, {int limit = 5}) {
    final seen = <String>{};
    for (final value in raw) {
      final hex = normalizedHex(value);
      if (hex == null || !seen.add(hex)) continue;
      if (seen.length == limit) break;
    }
    return List.unmodifiable(seen);
  }

  /// A friendly name for an arbitrary hex color, or `null` when unparseable.
  ///
  /// Names are descriptive, not authoritative: the nearest perceptual match
  /// in a small offline palette is used, and the hex remains on screen as the
  /// exact value. Matching happens in HCT so similar-looking colors land on
  /// similar names instead of nearest RGB distance.
  static String? nameForHex(String raw) {
    final color = parseHexColor(raw);
    if (color == null) return null;
    final hct = Hct.fromInt(color.toARGB32());

    var best = _namedColors.first;
    var bestDistance = double.infinity;
    for (final candidate in _namedColors) {
      final distance = _distance(hct, candidate.hct);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best.name;
  }

  /// A foreground that stays related to [background]'s hue and reaches
  /// [minimumContrast].
  ///
  /// Starts with a lightly tinted tone on the readable side of the background
  /// (pale for dark colors, deep for light ones) and only approaches pure
  /// black or white when the shade leaves too little contrast headroom.
  static Color onColorFor(Color background) {
    final opaque = Color(0xFF000000 | (background.toARGB32() & 0xFFFFFF));
    final hct = Hct.fromInt(opaque.toARGB32());
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);

    final useLight =
        contrastRatio(white, opaque) >= contrastRatio(black, opaque);
    final chroma = math.min(hct.chroma * 0.5, 24.0);
    var tone = useLight ? 88.0 : 18.0;
    var candidate = Hct.from(hct.hue, chroma, tone).toInt();

    while (contrastRatio(Color(candidate), opaque) < minimumContrast) {
      if (useLight) {
        tone = math.min(tone + 2, 100);
      } else {
        tone = math.max(tone - 2, 0);
      }
      candidate = Hct.from(hct.hue, chroma, tone).toInt();
      if (tone == 100 || tone == 0) break;
    }

    final tinted = Color(candidate);
    if (contrastRatio(tinted, opaque) >= minimumContrast) return tinted;
    // Defensive fallback for any rounding edge: the better pure extreme.
    return contrastRatio(white, opaque) >= contrastRatio(black, opaque)
        ? white
        : black;
  }

  /// A selection stroke for a card painted in [background].
  ///
  /// The stroke keeps the swatch's own hue, lightly desaturated, so it reads
  /// as belonging to the card rather than as a foreign accent. Its direction
  /// follows the card — a pale stroke on dark cards, a deep one on light cards
  /// — because a stroke can only separate from the fill it sits on.
  ///
  /// [brightness] then decides how far the stroke travels, which is what keeps
  /// the two themes looking alike: light mode wants a brighter pale and a
  /// softer deep (a fixed deep target turned yellow and green into near-black
  /// bands), while dark mode wants a deeper deep and needs no change to its
  /// pale stroke. [minimumSelectionContrast] is only a floor that pushes a
  /// too-subtle stroke further out; it never pulls one back.
  ///
  /// The stroke flips from pale to deep somewhere near the middle of the tone
  /// range. That cliff is intentional: between a lighter and a darker stroke
  /// there is nothing to see, so a mid-tone card can only be outlined by
  /// committing to one side.
  static Color selectionColorFor(
    Color background, {
    Brightness brightness = Brightness.light,
  }) {
    final opaque = Color(0xFF000000 | (background.toARGB32() & 0xFFFFFF));
    final hct = Hct.fromInt(opaque.toARGB32());
    final paleStroke = hct.tone <= 60;
    final chroma = math.min(hct.chroma * 0.6, 48.0);
    final dark = brightness == Brightness.dark;
    var tone = paleStroke ? (dark ? 74.0 : 90.0) : (dark ? 17.0 : 42.0);
    var candidate = Hct.from(hct.hue, chroma, tone).toInt();

    while (contrastRatio(Color(candidate), opaque) < minimumSelectionContrast) {
      final next = paleStroke
          ? math.min(tone + 2, 100.0)
          : math.max(tone - 2, 0.0);
      if (next == tone) break;
      tone = next;
      candidate = Hct.from(hct.hue, chroma, tone).toInt();
    }
    return Color(candidate);
  }

  /// WCAG 2.1 relative-luminance contrast ratio.
  static double contrastRatio(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color color) {
    final argb = color.toARGB32();
    double channel(int shift) {
      final value = ((argb >> shift) & 0xFF) / 255;
      return value <= 0.04045
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
  }

  static double _distance(Hct a, Hct b) {
    final hueDelta = _hueDistance(a.hue, b.hue);
    final chromaDelta = a.chroma - b.chroma;
    final toneDelta = a.tone - b.tone;
    // Hue is meaningless for near-gray colors, so fade its weight out as
    // chroma drops. Tone matters most to how a color reads (light/dark).
    final hueWeight = (math.min(a.chroma, b.chroma) / 50).clamp(0.0, 1.0);
    return toneDelta * toneDelta * 1.5 +
        chromaDelta * chromaDelta +
        hueDelta * hueDelta * hueWeight;
  }

  static double _hueDistance(double a, double b) {
    final delta = (a - b).abs() % 360;
    return delta > 180 ? 360 - delta : delta;
  }
}

/// Small offline palette of readable names.
///
/// Kept compact on purpose: exact CSS names for every corner of the gamut add
/// bytes and maintenance for little benefit when the hex is always shown.
const _palette = <(String, String)>[
  ('#663399', 'Vivid Purple'),
  ('#800080', 'Purple'),
  ('#4B0082', 'Indigo'),
  ('#6A5ACD', 'Slate Blue'),
  ('#8A2BE2', 'Blue Violet'),
  ('#9370DB', 'Medium Purple'),
  ('#DDA0DD', 'Plum'),
  ('#E6E6FA', 'Lavender'),
  ('#BA55D3', 'Medium Orchid'),
  ('#DA70D6', 'Orchid'),
  ('#EE82EE', 'Violet'),
  ('#C71585', 'Deep Magenta'),
  ('#FF00FF', 'Magenta'),
  ('#DB7093', 'Pale Violet Red'),
  ('#FF69B4', 'Hot Pink'),
  ('#FF1493', 'Deep Pink'),
  ('#FFB6C1', 'Light Pink'),
  ('#FFC0CB', 'Pink'),
  ('#FFE4E1', 'Misty Rose'),
  ('#FF7F50', 'Coral'),
  ('#FA8072', 'Salmon'),
  ('#FF4500', 'Orange Red'),
  ('#FF0000', 'Red'),
  ('#B22222', 'Firebrick'),
  ('#8B0000', 'Dark Red'),
  ('#800000', 'Maroon'),
  ('#FFA500', 'Orange'),
  ('#FF8C00', 'Dark Orange'),
  ('#FFD700', 'Gold'),
  ('#FFFF00', 'Yellow'),
  ('#F0E68C', 'Khaki'),
  ('#F5DEB3', 'Wheat'),
  ('#FFE4C4', 'Bisque'),
  ('#DEB887', 'Burlywood'),
  ('#D2691E', 'Chocolate'),
  ('#8B4513', 'Saddle Brown'),
  ('#A0522D', 'Sienna'),
  ('#BC8F8F', 'Rosy Brown'),
  ('#ADFF2F', 'Green Yellow'),
  ('#7FFF00', 'Chartreuse'),
  ('#32CD32', 'Lime Green'),
  ('#00FF00', 'Bright Green'),
  ('#008000', 'Green'),
  ('#006400', 'Dark Green'),
  ('#2E8B57', 'Sea Green'),
  ('#3CB371', 'Medium Sea Green'),
  ('#20B2AA', 'Light Sea Green'),
  ('#00FA9A', 'Spring Green'),
  ('#40E0D0', 'Turquoise'),
  ('#48D1CC', 'Medium Turquoise'),
  ('#00CED1', 'Dark Turquoise'),
  ('#00FFFF', 'Cyan'),
  ('#E0FFFF', 'Light Cyan'),
  ('#AFEEEE', 'Pale Turquoise'),
  ('#008080', 'Teal'),
  ('#2F4F4F', 'Dark Slate Gray'),
  ('#5F9EA0', 'Cadet Blue'),
  ('#87CEEB', 'Sky Blue'),
  ('#B0C4DE', 'Light Steel Blue'),
  ('#4682B4', 'Steel Blue'),
  ('#1E90FF', 'Dodger Blue'),
  ('#6495ED', 'Cornflower Blue'),
  ('#4169E1', 'Royal Blue'),
  ('#0000FF', 'Blue'),
  ('#00008B', 'Dark Blue'),
  ('#191970', 'Midnight Blue'),
  ('#708090', 'Slate Gray'),
  ('#D3D3D3', 'Light Gray'),
  ('#C0C0C0', 'Silver'),
  ('#A9A9A9', 'Dark Gray'),
  ('#808080', 'Gray'),
  ('#696969', 'Dim Gray'),
  ('#404040', 'Charcoal'),
  ('#F5F5F5', 'White Smoke'),
  ('#FFFFFF', 'White'),
  ('#000000', 'Black'),
  ('#FFF8DC', 'Cornsilk'),
  ('#FFF5EE', 'Seashell'),
  ('#F5FFFA', 'Mint Cream'),
  ('#F0FFFF', 'Azure'),
];

final List<_NamedColor> _namedColors = [
  for (final (hex, name) in _palette) _NamedColor(hex, name),
];

final class _NamedColor {
  _NamedColor(String hex, this.name)
    : hct = Hct.fromInt(0xFF000000 | int.parse(hex.substring(1), radix: 16));

  final String name;
  final Hct hct;
}
