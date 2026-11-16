// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_spacing.dart';
import 'pressable_scale.dart';

/// The one control for adding a browsing query to Collections or removing it
/// again.
///
/// Reads as an explicit verb instead of a bookmark glyph: an outlined
/// `+ Add` becomes a filled `✓ Added`. Tapping `Added` removes that exact
/// saved collection; the browsing page stays where it is.
///
/// Both states occupy the same footprint. The label slot is sized to the
/// widest of the two strings — measured with the same style and text scaler
/// the visible label uses — so swapping verbs never nudges neighbouring
/// content and long translations cannot clip. Curated (permanent)
/// collections never get this control at all; their screens omit it rather
/// than showing a disabled button.
final class CollectionMembershipButton extends StatefulWidget {
  const CollectionMembershipButton({
    super.key,
    required this.added,
    required this.onPressed,
    this.pending = false,
    this.subject,
    this.addLabel = 'Add',
    this.addedLabel = 'Added',
  });

  /// Whether the browsing query currently has a saved collection.
  final bool added;

  /// Invoked for both directions: save when [added] is false, remove when it
  /// is true. `null` disables the control.
  final VoidCallback? onPressed;

  /// A write is in flight. Taps are ignored without changing the layout or
  /// the colour, so the button cannot flicker into a disabled look while the
  /// snackbar it is about to show has not arrived yet.
  final bool pending;

  /// Name of the query, used only for the spoken label
  /// (`Add landscape to Collections`).
  final String? subject;

  final String addLabel;
  final String addedLabel;

  @override
  State<CollectionMembershipButton> createState() =>
      _CollectionMembershipButtonState();
}

final class _CollectionMembershipButtonState
    extends State<CollectionMembershipButton> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'CollectionMembership');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.pending) return;
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    M3EHaptics.trigger(M3EHapticFeedback.light);
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduceMotion ? Duration.zero : AppMotion.transition;
    final curve = AppMotion.arrivalCurve;

    final background = widget.added ? scheme.primary : Colors.transparent;
    final foreground = widget.added
        ? scheme.onPrimary
        : scheme.onSurfaceVariant;
    final sideColor = widget.added ? scheme.primary : scheme.outline;

    final labelStyle = (textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: foreground,
      fontWeight: FontWeight.w600,
    );

    final semanticsLabel = switch ((widget.subject, widget.added)) {
      (null, true) => '${widget.addedLabel}. Remove collection',
      (null, false) => '${widget.addLabel} collection',
      (final subject?, true) =>
        '${widget.addedLabel}. Remove $subject from Collections',
      (final subject?, false) => '${widget.addLabel} $subject to Collections',
    };

    return Semantics(
      container: true,
      button: true,
      toggled: widget.added,
      enabled: !widget.pending && widget.onPressed != null,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: _handleTap,
      child: M3EFocusRing(
        focused: _focused && M3EFocusRing.indicatorsEnabledOf(context),
        radius: BorderRadius.circular(_kPillHeight / 2),
        animationDuration: duration,
        child: PressableScale(
          pressedScale: 0.96,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              focusNode: _focusNode,
              canRequestFocus: true,
              onFocusChange: (focused) {
                if (focused == _focused) return;
                setState(() => _focused = focused);
              },
              onTap: widget.pending ? null : _handleTap,
              customBorder: const StadiumBorder(),
              child: SizedBox(
                // The target keeps the platform minimum; the visible pill is
                // [_kPillHeight] tall and centred inside it, so the extra
                // height stays tappable.
                height: _kTouchTarget,
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: AnimatedContainer(
                    key: const ValueKey('collection-membership-pill'),
                    duration: duration,
                    curve: curve,
                    height: _kPillHeight,
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    decoration: ShapeDecoration(
                      color: background,
                      shape: StadiumBorder(side: BorderSide(color: sideColor)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: duration,
                          switchInCurve: curve,
                          switchOutCurve: curve,
                          transitionBuilder: (child, animation) {
                            final eased = CurvedAnimation(
                              parent: animation,
                              curve: curve,
                            );
                            return FadeTransition(
                              opacity: eased,
                              child: RotationTransition(
                                turns: Tween<double>(
                                  begin: -0.08,
                                  end: 0,
                                ).animate(eased),
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.55,
                                    end: 1,
                                  ).animate(eased),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: Icon(
                            widget.added
                                ? PhosphorIconsBold.check
                                : PhosphorIconsBold.plus,
                            key: ValueKey<bool>(widget.added),
                            size: _kIconSize,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _StableLabel(
                          labels: [widget.addLabel, widget.addedLabel],
                          current: widget.added ? 1 : 0,
                          style: labelStyle,
                          duration: duration,
                          curve: curve,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill height, matching an `M3EButton` at size `sm` (40 dp).
const double _kPillHeight = 32;

/// Minimum touch target for an app-bar action.
const double _kTouchTarget = 48;

/// Glyph size inside the pill; pairs with `labelLarge` at 40 dp.
const double _kIconSize = 18;

/// A label that cross-fades while its slot stays the width of the widest
/// state.
///
/// Hidden copies of every state are laid out (opacity 0, semantics excluded)
/// so the [Stack] resolves to the widest measurement. That is what keeps the
/// pill's outer size identical between `Add` and `Added`, including at large
/// text scales and in longer translations, without hard-coding a width.
final class _StableLabel extends StatelessWidget {
  const _StableLabel({
    required this.labels,
    required this.current,
    required this.style,
    required this.duration,
    required this.curve,
  });

  final List<String> labels;
  final int current;
  final TextStyle style;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final visible = labels[current.clamp(0, labels.length - 1)];
    return Stack(
      alignment: Alignment.center,
      children: [
        for (final label in labels)
          ExcludeSemantics(
            child: Opacity(
              opacity: 0,
              child: Text(label, maxLines: 1, softWrap: false, style: style),
            ),
          ),
        AnimatedSwitcher(
          duration: duration,
          switchInCurve: curve,
          switchOutCurve: curve,
          transitionBuilder: (child, animation) {
            final eased = CurvedAnimation(parent: animation, curve: curve);
            return FadeTransition(
              opacity: eased,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.28),
                  end: Offset.zero,
                ).animate(eased),
                child: child,
              ),
            );
          },
          child: Text(
            visible,
            // Only the visible label carries a state key; the sizing ghosts
            // above stay anonymous so `Added` never appears twice in the tree
            // for a finder.
            key: ValueKey<String>('collection-membership-label-$visible'),
            maxLines: 1,
            softWrap: false,
            style: style,
          ),
        ),
      ],
    );
  }
}
