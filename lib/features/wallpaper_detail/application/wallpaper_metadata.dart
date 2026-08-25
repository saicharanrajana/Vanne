import 'package:intl/intl.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

/// Pure formatting helpers for the detail sheet's metadata cards.
///
/// Kept widget-free so the display rules are unit-testable in isolation;
/// the presentation layer maps these to cards verbatim. All user-facing
/// output is locale-aware — pass `Localizations.localeOf(context)` from
/// the call site.
abstract final class WallpaperMetadata {
  /// Human-readable file size: `2.1 MB` above a megabyte, `512 KB`
  /// below. Null when Wallhaven reports no size (listing entries).
  static String? fileSize(int bytes, String locale) {
    if (bytes <= 0) return null;
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) {
      return '${NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 1).format(mb)} MB';
    }
    return '${NumberFormat.decimalPattern(locale).format(bytes ~/ 1024)} KB';
  }

  /// Aspect ratio as a reduced fraction of the pixel dimensions,
  /// e.g. `1920x1080` → `16:9`, `1080x2400` → `9:20`.
  ///
  /// Falls back to Wallhaven's preformatted decimal `ratio` string when
  /// dimensions are missing, and to `-` when nothing usable exists.
  static String aspectRatio(Wallpaper wallpaper) {
    if (wallpaper.width > 0 && wallpaper.height > 0) {
      final divisor = wallpaper.width.gcd(wallpaper.height);
      return '${wallpaper.width ~/ divisor}:${wallpaper.height ~/ divisor}';
    }
    final ratio = wallpaper.ratio;
    return ratio.isNotEmpty ? ratio : '-';
  }

  /// Short localized calendar date, e.g. `Jun 12, 2023` (en) or
  /// `12. Juni 2023` (de). Null when the listing carried no `created_at`.
  static String? uploadedDate(DateTime? createdAt, String locale) {
    if (createdAt == null) return null;
    return DateFormat.yMMMd(Intl.canonicalizedLocale(locale)).format(createdAt);
  }

  /// Locale-aware grouping for large counts, e.g. `1,234` / `1.234`.
  static String count(int value, String locale) =>
      NumberFormat.decimalPattern(locale).format(value);
}
