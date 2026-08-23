// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:material_ui/material_ui.dart';

/// Layout-spacing sugar: turns any number into the equivalent spacer.
///
/// ```dart
/// Column(children: [
///   Text('Title'),
///   AppSpacing.md.gap,          // SizedBox(height: 12)
/// ])
/// ```
///
/// Prefer token values ([AppSpacing]) over arbitrary numbers so spacing
/// stays on one scale.
extension GapX on num {
  /// A [SizedBox] of this many logical pixels tall — the vertical gap
  /// between widgets in a [Column], [Row] or list.
  SizedBox get gap => SizedBox(height: toDouble());
}
