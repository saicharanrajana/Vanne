/// Spacing scale tokens — the single source of truth for padding, margins
/// and gaps.
///
/// Values sit on a 4 dp grid. Convention: layout code must not use raw
/// numeric literals for spacing (`SizedBox(height: 16)`,
/// `EdgeInsets.all(24)`, …); it references these tokens instead, e.g.
///
/// ```dart
/// SizedBox(height: AppSpacing.lg)
/// AppSpacing.lg.gap                 // via shared/extensions/num_extensions
/// EdgeInsets.all(AppSpacing.lg)
/// ```
///
/// Exemptions (not spacing): icon `size:` arguments, painted shapes
/// (drag handles, dots), and `0` / `double.infinity`.
///
/// Responsive behavior: tokens are constant logical pixels on purpose —
/// scaling gaps with screen size breaks visual rhythm. Screens adapt to
/// size through *layout structure* (column counts, max widths), not by
/// inflating whitespace.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
