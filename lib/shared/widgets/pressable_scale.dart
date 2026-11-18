// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:material_ui/material_ui.dart';
import 'package:motor/motor.dart';

import '../../app/theme/app_motion.dart';
import '../utils/motion_preferences.dart';

/// Spring-driven press feedback for tappable content.
///
/// The app disables Material ripples/splashes globally ([AppTheme]), which
/// leaves tiles and icon buttons over imagery with no tactile response.
/// This restores one: while a pointer is down anywhere over the child, the
/// child springs to [pressedScale] on [AppMotion.press] and springs back
/// on release/cancel.
///
/// Uses a [Listener] (not [GestureDetector]) so it never competes with
/// the child's own tap handling; safe to wrap tiles and custom controls.
///
/// Honors reduced-motion: when the platform requests fewer animations the
/// scale snaps instead of springing (`motion.active` off).
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.97,
  });

  final Widget child;

  /// Scale while pressed. Small values read as "pushed in"; keep ≥ 0.94
  /// or taps start feeling broken rather than tactile.
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

final class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = prefersReducedMotion(context);

    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: SingleMotionBuilder(
        motion: AppMotion.press,
        value: _pressed ? widget.pressedScale : 1.0,
        // Snap instead of springing when reduced motion is requested.
        active: !reduceMotion,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: widget.child,
      ),
    );
  }
}
