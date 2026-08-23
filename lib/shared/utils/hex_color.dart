import 'package:material_ui/material_ui.dart';

/// Parses a CSS-style hex color into a [Color].
///
/// Accepts an optional leading `#`, 3-digit shorthand (`#abc` → `#aabbcc`)
/// and 6-digit RGB form (`#1a2b3c`). Returns null for anything else.
Color? parseHexColor(String input) {
  var hex = input.trim().replaceFirst('#', '');
  switch (hex.length) {
    case 3:
      hex = hex.split('').map((c) => '$c$c').join();
    case 6:
      break;
    default:
      return null;
  }
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}
