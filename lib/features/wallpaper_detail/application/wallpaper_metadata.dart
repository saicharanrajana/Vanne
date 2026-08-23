import 'package:wallhaven_client/wallhaven_client.dart';

/// Pure formatting helpers for the detail sheet's metadata cards.
///
/// Kept widget-free so the display rules are unit-testable in isolation;
/// the presentation layer maps these to cards verbatim.
abstract final class WallpaperMetadata {
  /// Human-readable file size: `2.1 MB` above a megabyte, `512 KB`
  /// below. Null when Wallhaven reports no size (listing entries).
  static String? fileSize(int bytes) {
    if (bytes <= 0) return null;
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  /// Aspect ratio as a reduced fraction of the pixel dimensions,
  /// e.g. `1920x1080` → `16:9`, `1080x2400` → `9:20`.
  ///
  /// Falls back to Wallhaven's preformatted decimal `ratio` string when
  /// dimensions are missing, and to `—` when nothing usable exists.
  static String aspectRatio(Wallpaper wallpaper) {
    if (wallpaper.width > 0 && wallpaper.height > 0) {
      final divisor = wallpaper.width.gcd(wallpaper.height);
      return '${wallpaper.width ~/ divisor}:${wallpaper.height ~/ divisor}';
    }
    final ratio = wallpaper.ratio;
    return ratio.isNotEmpty ? ratio : '—';
  }

  /// Short calendar date, e.g. `Jun 12, 2023`. Null when the listing
  /// carried no `created_at`.
  static String? uploadedDate(DateTime? createdAt) {
    if (createdAt == null) return null;
    return '${_monthAbbr(createdAt.month)} ${createdAt.day}, ${createdAt.year}';
  }

  static String _monthAbbr(int month) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
            'Oct', 'Nov', 'Dec'][month - 1];
}
