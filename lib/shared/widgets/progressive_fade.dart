// Convention: prefer material_ui over package:flutter/material.dart /
// package:flutter/widgets.dart for UI code — material_ui is the Flutter
// team's decoupled Material package and this app runs on ITS widget tree.
// Importing flutter-material here instead would create a second, parallel
// set of widget types (Theme lookups silently miss and fall back to the
// default light theme).
import 'package:material_ui/material_ui.dart';

/// Fades content behind the status bar.
///
/// Wrap the body of a [Scaffold] that has **no** AppBar so content dissolving
/// under the clock/battery feels soft rather than clipped. Uses [ShaderMask]
/// with an alpha gradient, so it works in light and dark mode.
class ProgressiveFade extends StatelessWidget {
  final Widget child;
  final double height;

  const ProgressiveFade({
    super.key,
    required this.child,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    final double end = (height / MediaQuery.of(context).size.height).clamp(0.0, 1.0);

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00FFFFFF),
            Color(0x26FFFFFF),
            Color(0x66FFFFFF),
            Color(0xB3FFFFFF),
            Color(0xFFFFFFFF),
          ],
          stops: [
            0.0,
            end * 0.25,
            end * 0.5,
            end * 0.75,
            end,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}
