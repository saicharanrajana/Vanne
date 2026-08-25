import 'package:wallhaven_client/wallhaven_client.dart';

/// Maps an arbitrary hex string (with or without `#`, any casing) to the
/// nearest documented Wallhaven search color.
///
/// Wallhaven only supports 29 discrete `colors=` values; wallpapers' palettes
/// are arbitrary. We pick the Euclidean-nearest wire color so tapping
/// `#EA4C88` still filters rather than returning unfiltered results.
WallhavenColor? wallhavenColorForHex(String hex) {
  var raw = hex.trim().replaceFirst('#', '').toLowerCase();
  if (raw.length == 3) raw = raw.split('').map((c) => '$c$c').join();
  if (raw.length != 6) return null;
  final r = int.tryParse(raw.substring(0, 2), radix: 16);
  final g = int.tryParse(raw.substring(2, 4), radix: 16);
  final b = int.tryParse(raw.substring(4, 6), radix: 16);
  if (r == null || g == null || b == null) return null;
  // Exact match first — avoids distance work when possible.
  for (final c in WallhavenColor.values) {
    if (c.hex.toLowerCase() == raw) return c;
  }
  WallhavenColor? best;
  var bestDist = double.infinity;
  for (final c in WallhavenColor.values) {
    final cr = int.parse(c.hex.substring(0, 2), radix: 16);
    final cg = int.parse(c.hex.substring(2, 4), radix: 16);
    final cb = int.parse(c.hex.substring(4, 6), radix: 16);
    final dr = (r - cr).toDouble();
    final dg = (g - cg).toDouble();
    final db = (b - cb).toDouble();
    final dist = dr * dr + dg * dg + db * db;
    if (dist < bestDist) {
      bestDist = dist;
      best = c;
    }
  }
  return best;
}
