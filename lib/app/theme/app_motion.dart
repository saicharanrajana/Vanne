import 'package:flutter/animation.dart';
import 'package:motor/motor.dart';

/// Motion vocabulary for the whole app — every spring, curve and duration
/// used by shared widgets comes from here so the app's *feel* is tunable
/// in one place.
///
/// Spatial tokens move things the eye tracks (sheets, tiles, buttons);
/// effects tokens drive opacity/color/fades. Presets come from Material 3
/// Expressive springs via `motor`; the two sheet descriptions preserve
/// the hand-tuned SwiftUI `.smooth` parameters this app shipped with.
abstract final class AppMotion {
  // --- Spatial: position/size changes -------------------------------------

  /// Press feedback and other fast, small spatial changes.
  static const MaterialSpringMotion press = MaterialSpringMotion.standardSpatialFast();

  /// Default spatial motion for elements that move a visible distance.
  static const MaterialSpringMotion spatial =
      MaterialSpringMotion.standardSpatialDefault();

  /// Bouncier default for celebratory/emphatic transitions.
  static const MaterialSpringMotion expressiveSpatial =
      MaterialSpringMotion.expressiveSpatialDefault();

  // --- Effects: opacity/color/fades ---------------------------------------

  /// Fast non-spatial effects (image fade-in, scrim).
  static const MaterialSpringMotion effectsFast = MaterialSpringMotion.standardEffectsFast();

  /// Default non-spatial effect (color cross-fades, theme swaps).
  static const MaterialSpringMotion effects = MaterialSpringMotion.standardEffectsDefault();

  // --- Sheet physics -------------------------------------------------------
  //
  // SwiftUI's .smooth spring written out as plain numbers: critically
  // damped, stiffness 4pi^2 / duration^2 — 300 ms entering, 200 ms exiting.

  /// Enter/settle spring for modal sheets (drag & fling aware).
  static const SpringDescription sheetEnter = SpringDescription(
    mass: 1,
    stiffness: 438.6,
    damping: 41.9,
  );

  /// Exit/dismiss spring for modal sheets.
  static const SpringDescription sheetExit = SpringDescription(
    mass: 1,
    stiffness: 987.0,
    damping: 62.8,
  );

  // --- Durations (for the few non-spring, curve-based animations) ---------

  /// Standard animated-transition duration where a [Curves]-based tween
  /// is more appropriate than a spring (e.g. [AnimatedTheme]).
  static const Duration transition = Duration(milliseconds: 300);

  /// Curve paired with [transition] for content that should arrive
  /// decisively (emphasized decelerate).
  static const Curve arrivalCurve = Cubic(0.05, 0.7, 0.1, 1.0);
}
