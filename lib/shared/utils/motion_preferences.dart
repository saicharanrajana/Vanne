import 'package:flutter/widgets.dart';

/// Whether the platform asks the app to reduce motion.
///
/// Flutter 3.50 separates two accessibility signals that older releases
/// collapsed into one: [MediaQueryData.reduceMotion], which iOS and the web
/// report for "Reduce Motion", and [MediaQueryData.disableAnimations], which
/// Android reports for "Remove animations". The app treats either request as
/// "animate instantly", so every animated widget asks here rather than reading
/// a single flag and silently ignoring the other platform's setting.
bool prefersReducedMotion(BuildContext context) {
  final data = MediaQuery.maybeOf(context);
  return (data?.reduceMotion ?? false) || (data?.disableAnimations ?? false);
}
