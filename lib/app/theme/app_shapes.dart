/// Shape corner-radius tokens mirroring the removed M3E shapes.
///
/// Values taken from the former expressive package's m3e_dimensions.dart.
///
/// **Concentric nesting rule:** when rounded surfaces stack (a card inside
/// a sheet, a thumb inside a track), the outer radius should equal the
/// inner radius plus the padding between them — the curves then share a
/// common center and read as one continuous surface:
///
/// ```dart
/// // Sheet: 28 top corners; toolbar inside with 12 padding → 28 - 12 = 16.
/// SheetContainer   → Radius.circular(AppShapes.extraLarge)          // 28
/// Toolbar inside   → Radius.circular(AppShapes.extraLarge - AppSpacing.md)
/// ```
abstract final class AppShapes {
  static const double none = 0;
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double largeIncreased = 20;
  static const double extraLarge = 28;
  static const double extraLargeIncreased = 32;
  static const double extraExtraLarge = 48;
  static const double full = 999;
}
