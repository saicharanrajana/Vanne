// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'dart:math' as math;

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
/// Adds a scroll-end inset without shrinking the viewport.
///
/// The main shell uses this scope to let scrollable destinations clear its
/// floating navigation overlay. It is inherited only by shell content, so
/// standalone/detail routes retain their normal system-bar spacing.
class BottomPaddingScope extends InheritedWidget {
  const BottomPaddingScope({
    required this.bottomInset,
    required super.child,
    super.key,
  });

  final double bottomInset;

  static double maybeBottomInsetOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BottomPaddingScope>()
          ?.bottomInset ??
      0;

  @override
  bool updateShouldNotify(BottomPaddingScope oldWidget) =>
      bottomInset != oldWidget.bottomInset;
}

class BottomPadding extends StatelessWidget {
  const BottomPadding({super.key});

  static double of(BuildContext context, {double minimum = 16}) {
    final double viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final double defaultInset = math.max(viewPadding, minimum);
    final double shellInset =
        BottomPaddingScope.maybeBottomInsetOf(context) + viewPadding;
    return math.max(defaultInset, shellInset);
  }

  @override
  Widget build(BuildContext context) {
    final double height = of(context);
    return SizedBox(height: height);
  }
}
