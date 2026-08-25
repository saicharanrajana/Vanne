import 'package:material_ui/material_ui.dart';

/// Fades the leading/trailing edges of a horizontal scrollable only when
/// there is more content in that direction, hinting that the list scrolls.
///
/// Alpha-only mask, so it reads identically in light and dark themes.
final class HorizontalEdgeFade extends StatefulWidget {
  final Widget child;

  /// Fade width as a fraction of the viewport, per edge.
  final double fadeExtent;

  const HorizontalEdgeFade({
    super.key,
    required this.child,
    this.fadeExtent = 0.06,
  });

  @override
  State<HorizontalEdgeFade> createState() => _HorizontalEdgeFadeState();
}

final class _HorizontalEdgeFadeState extends State<HorizontalEdgeFade> {
  bool _fadeStart = false;
  bool _fadeEnd = true;

  void _updateFades(ScrollNotification notification) {
    final metrics = notification.metrics;
    final start = metrics.extentBefore > 4;
    final end = metrics.extentAfter > 4;
    if (start != _fadeStart || end != _fadeEnd) {
      setState(() {
        _fadeStart = start;
        _fadeEnd = end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          _fadeStart ? const Color(0x00FFFFFF) : const Color(0xFFFFFFFF),
          const Color(0xFFFFFFFF),
          const Color(0xFFFFFFFF),
          _fadeEnd ? const Color(0x00FFFFFF) : const Color(0xFFFFFFFF),
        ],
        stops: [0.0, widget.fadeExtent, 1 - widget.fadeExtent, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _updateFades(notification);
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
