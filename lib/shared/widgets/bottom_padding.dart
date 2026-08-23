// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree — see progressive_fade.dart for the full note.
import 'package:material_ui/material_ui.dart';

/// Breathing room at the bottom of scrollable content.
///
/// Unlike [SafeArea], this does **not** shrink the viewport — it just adds
/// a box whose height is the bottom system inset (gesture bar / navigation
/// bar) or [minimum] when no inset is present. Content scrolls through the
/// full viewport; only the final resting position gains space.
///
/// Use as the last sliver child or as [EdgeInsets] padding:
/// ```dart
/// ListView(padding: EdgeInsets.only(bottom: BottomPadding.of(context)));
/// SliverToBoxAdapter(child: BottomPadding());
/// ```
class BottomPadding extends StatelessWidget {
  const BottomPadding({super.key});

  static double of(
    BuildContext context, {
    double minimum = 16,
  }) {
    final double viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final double height = viewPadding > minimum ? viewPadding : minimum;
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final double height = of(context);
    return SizedBox(height: height);
  }
}

/// Top breathing room counterpart; rarely needed but symmetric.
class TopPadding extends StatelessWidget {
  const TopPadding({super.key});

  static double of(BuildContext context, {double minimum = 0}) {
    final double viewPadding = MediaQuery.viewPaddingOf(context).top;
    final double height = viewPadding > minimum ? viewPadding : minimum;
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final double height = of(context);
    return SizedBox(height: height);
  }
}
