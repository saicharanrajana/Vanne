// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../theme/app_motion.dart';

/// Horizontal breathing room inside the selection indicator, either side of
/// its glyph and label. Together with the 24dp glyph this also *is* the
/// leading inset of an icon-only slot, so a destination's glyph never jumps
/// when it gains or loses its label.
const double _pillPadding = 12;

/// Glyph extent inside a destination.
const double _iconExtent = 24;

/// Gap between the glyph and the label of the selected destination.
const double _labelGap = 8;

/// Padding M3E's floating bar keeps either side of its content.
///
/// Budgeted conservatively: a row narrower than the bar's own padding simply
/// centres inside it, whereas a row wider than it overflows.
const double _barHorizontalPadding = 16;

/// The four primary destinations, in tab-router order.
///
/// Each destination owns its icon pair and visible selected-state label.
enum ShellDestination {
  discover('Discover', PhosphorIconsBold.compass, PhosphorIconsFill.compass),
  collections('Collections', PhosphorIconsBold.stack, PhosphorIconsFill.stack),
  favorites('Favorites', PhosphorIconsBold.heart, PhosphorIconsFill.heart),
  settings('Settings', PhosphorIconsBold.gear, PhosphorIconsFill.gear);

  const ShellDestination(this.label, this.icon, this.selectedIcon);

  final String label;

  /// Outlined glyph, shown while the destination is not selected.
  final IconData icon;

  /// Filled glyph, shown while the destination is selected.
  final IconData selectedIcon;
}

/// The shell's primary navigation: a floating Material 3 Expressive toolbar
/// with one shared selection pill that travels between the destinations.
///
/// The toolbar is hosted by [M3EToolbar], so its floating container, elevation
/// and safe-area treatment come from the design system. The shell supplies no
/// padding of its own: the distance from the bar to the screen edge is exactly
/// [screenOffset] on top of the dock-edge system inset, counted once.
final class ShellNavigationToolbar extends StatelessWidget {
  const ShellNavigationToolbar({
    required this.activeIndex,
    required this.onDestinationSelected,
    super.key,
  });

  /// Width of one inactive destination's hit target.
  static const double destinationExtent = 48;

  /// Height of the content band. The selection indicator fills it exactly, so
  /// there is one pill inside the M3E surface rather than two stacked ones.
  static const double contentExtent = 48;

  /// Clearance between the floating bar and the dock-edge system inset.
  ///
  /// Passed to [M3EToolbar.screenOffset] — M3E's own knob, and the only margin
  /// the shell applies around the bar. The visible gap below it is therefore
  /// exactly `safe area + this`, counted once.
  static const double screenOffset = 4;

  /// Height of the floating bar: the content band plus M3E's floating padding.
  static const double barExtent = contentExtent + 16;

  /// Space scrollable shell content must leave at the end of its list so its
  /// last row can rest clear of the floating bar and its breathing room.
  static const double scrollClearance = barExtent + screenOffset + 16;

  final int activeIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return M3EToolbar(
      safeArea: true,
      screenOffset: screenOffset,
      alignment: Alignment.bottomCenter,
      colorStyle: M3EToolbarColorStyle.standard,
      expanded: true,
      semanticLabel: 'Main navigation',
      actions: [
        M3EToolbarWidget(
          child: _DestinationBar(
            activeIndex: activeIndex,
            onDestinationSelected: onDestinationSelected,
          ),
        ),
      ],
    );
  }
}

/// The destinations themselves: one shared indicator, one glyph per slot.
///
/// Slot widths, the indicator's rectangle and the selected label's fade are
/// all derived from a single controller, so the indicator can never drift from
/// the destination it marks mid-flight.
final class _DestinationBar extends StatefulWidget {
  const _DestinationBar({
    required this.activeIndex,
    required this.onDestinationSelected,
  });

  final int activeIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<_DestinationBar> createState() => _DestinationBarState();
}

final class _DestinationBarState extends State<_DestinationBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.tabTransition,
    value: 1,
  );

  late int _fromIndex = widget.activeIndex;
  late int _toIndex = widget.activeIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DestinationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.activeIndex;
    if (next == _toIndex) return;

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      setState(() {
        _fromIndex = next;
        _toIndex = next;
      });
      _controller.value = 1;
      return;
    }

    setState(() {
      // Retarget mid-flight from whichever destination the bar currently
      // shows most of, so a rapid second choice never rewinds the indicator.
      _fromIndex = _controller.isAnimating && _controller.value < 0.5
          ? _fromIndex
          : _toIndex;
      _toIndex = next;
    });
    if (_fromIndex == _toIndex) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  /// How far a destination is towards being the selected one: `1` at rest for
  /// the active slot, `0` for every inactive slot.
  double _activation(int index, double progress) {
    if (_fromIndex == _toIndex) return index == _toIndex ? 1 : 0;
    if (index == _toIndex) return progress;
    if (index == _fromIndex) return 1 - progress;
    return 0;
  }

  double _labelWidth(BuildContext context, String label, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelLarge;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    const destinations = ShellDestination.values;

    // M3E lays its floating content out at its intrinsic width, so without a
    // budget the bar would happily grow wider than the screen. Budget the row
    // against the screen: the shell's screen offset plus the bar's optical
    // padding either side.
    final budget =
        MediaQuery.sizeOf(context).width -
        2 * (ShellNavigationToolbar.screenOffset + _barHorizontalPadding);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: budget),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final maxSelected = math.max(
            ShellNavigationToolbar.destinationExtent,
            available -
                ShellNavigationToolbar.destinationExtent *
                    (destinations.length - 1),
          );
          final selectedExtents = [
            for (final destination in destinations)
              (_labelWidth(context, destination.label, textStyle) +
                      _iconExtent +
                      _labelGap +
                      _pillPadding * 2)
                  .clamp(ShellNavigationToolbar.destinationExtent, maxSelected),
          ];

          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = reduceMotion
                  ? 1.0
                  : AppMotion.tabTransitionCurve.transform(_controller.value);
              final activations = [
                for (var index = 0; index < destinations.length; index++)
                  _activation(index, progress),
              ];
              final widths = [
                for (var index = 0; index < destinations.length; index++)
                  lerpDouble(
                    ShellNavigationToolbar.destinationExtent,
                    selectedExtents[index],
                    activations[index],
                  )!,
              ];
              final starts = <double>[];
              var cursor = 0.0;
              for (final width in widths) {
                starts.add(cursor);
                cursor += width;
              }
              final total = cursor;
              final rtl = Directionality.of(context) == TextDirection.rtl;

              // The indicator is the selected slot's rectangle: same interpolation,
              // so it is pixel-locked to the slot at rest and in flight.
              final pillStart = starts[_toIndex];
              final pillExtent = widths[_toIndex];

              double leadingEdge(double start, double width) =>
                  rtl ? total - (start + width) : start;

              return SizedBox(
                key: const ValueKey('shell-navigation-row'),
                width: total,
                height: ShellNavigationToolbar.contentExtent,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: leadingEdge(pillStart, pillExtent),
                      top: 0,
                      width: pillExtent,
                      height: ShellNavigationToolbar.contentExtent,
                      child: DecoratedBox(
                        key: const ValueKey('nav-selection-pill'),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(
                            ShellNavigationToolbar.contentExtent / 2,
                          ),
                        ),
                      ),
                    ),
                    for (var index = 0; index < destinations.length; index++)
                      Positioned(
                        left: leadingEdge(starts[index], widths[index]),
                        top: 0,
                        width: widths[index],
                        height: ShellNavigationToolbar.contentExtent,
                        child: _DestinationSlot(
                          key: ValueKey('nav-${destinations[index].name}'),
                          index: index,
                          destination: destinations[index],
                          selected: activations[index] >= 0.5,
                          activation: activations[index],
                          idleColor: scheme.onSurfaceVariant,
                          selectedColor: scheme.onSecondaryContainer,
                          textStyle: textStyle,
                          onTap: () => widget.onDestinationSelected(index),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

final class _DestinationSlot extends StatelessWidget {
  const _DestinationSlot({
    required this.index,
    required this.destination,
    required this.selected,
    required this.activation,
    required this.idleColor,
    required this.selectedColor,
    required this.textStyle,
    required this.onTap,
    super.key,
  });

  final int index;
  final ShellDestination destination;

  /// Whether the slot paints its filled glyph.
  final bool selected;

  /// How far the slot is towards being the selected one (0…1).
  final double activation;

  final Color idleColor;
  final Color selectedColor;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The label only appears in the last sliver of the indicator's travel —
    // once its slot is wide enough to hold it in full — so it is never caught
    // mid-clip, and exactly one label is in the tree at rest.
    final labelOpacity = ((activation - 0.9) / 0.1).clamp(0.0, 1.0);

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: destination.label,
      onTap: onTap,
      // The slot announces its destination once; the glyph and label below are
      // decoration for a screen reader that already has the name.
      excludeSemantics: true,
      // The indicator slides underneath the slot, so the slot's own ink is
      // only a response to hover and focus — never a second selection state.
      child: Tooltip(
        message: destination.label,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: _pillPadding,
            ),
            child: Row(
              children: [
                // One glyph per destination, at one fixed leading inset.
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: _iconExtent,
                  color: Color.lerp(idleColor, selectedColor, activation),
                ),
                if (labelOpacity > 0) ...[
                  const SizedBox(width: _labelGap),
                  Flexible(
                    child: Opacity(
                      opacity: labelOpacity,
                      child: Text(
                        destination.label,
                        key: ValueKey('nav-selected-label-$index'),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: textStyle?.copyWith(color: selectedColor),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Page-view style transition between primary destinations.
///
/// The destination being left and the one being entered stay mounted and are
/// laid out together at full viewport width, so they pan across the screen and
/// share one edge — a jump such as Discover → Settings never paints
/// Collections or Favorites in between.
///
/// Destinations that are not part of the current movement are kept in the tree
/// but [Offstage]: their elements (and therefore feeds, filters and scroll
/// positions) survive, while layout and paint are skipped. A destination is
/// only built once it is first shown, matching the router's lazy loading.
final class ShellTabTransition extends StatefulWidget {
  const ShellTabTransition({
    required this.activeIndex,
    required this.children,
    super.key,
  });

  final int activeIndex;

  /// One child per destination, in tab-router order.
  final List<Widget> children;

  @override
  State<ShellTabTransition> createState() => _ShellTabTransitionState();
}

final class _ShellTabTransitionState extends State<ShellTabTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.tabTransition,
    value: 1,
  );

  late int _from = widget.activeIndex;
  late int _to = widget.activeIndex;

  /// Destinations the user has visited at least once. Each stays built from
  /// then on so its state outlives its turn on screen.
  late final Set<int> _visited = {widget.activeIndex};

  @override
  void initState() {
    super.initState();
    // Once the movement settles the pair collapses back to a single
    // destination, so the page that was left stops being laid out at all.
    _controller.addStatusListener(_handleStatus);
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _from == _to) return;
    setState(() => _from = _to);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ShellTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.activeIndex;
    if (next == _to) return;
    _visited.add(next);

    // Retargeting mid-flight continues from whichever page already dominates
    // the viewport, so rapid taps neither replay an older pair nor settle on
    // a destination the user has moved past.
    final from = _controller.value < 0.5 ? _from : _to;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // Nothing to slide between when motion is off, or when the user came back
    // to the page that already dominates the viewport: settle there instead
    // of animating a pair that is not actually being crossed.
    if (reduceMotion || from == next) {
      setState(() {
        _from = next;
        _to = next;
      });
      _controller.value = 1;
      return;
    }

    setState(() {
      _from = from;
      _to = next;
    });
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final width = MediaQuery.sizeOf(context).width;
    final direction = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final travelling = !reduceMotion && _from != _to;
        final progress = travelling
            ? AppMotion.tabTransitionCurve.transform(_controller.value)
            : 1.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            for (var index = 0; index < widget.children.length; index++)
              _destination(
                index: index,
                progress: progress,
                entering: index == _to,
                leaving: travelling && index == _from,
                width: width,
                direction: direction,
              ),
          ],
        );
      },
    );
  }

  Widget _destination({
    required int index,
    required double progress,
    required bool entering,
    required bool leaving,
    required double width,
    required double direction,
  }) {
    // A destination is built the first time it is shown, then kept; the
    // wrapper chain below never changes shape, so starting or ending a
    // transition only flips flags and can never remount (and thereby reload)
    // a page that is merely on its way out.
    final child = _visited.contains(index)
        ? widget.children[index]
        : const SizedBox.shrink();

    // Both pages travel a full viewport width, so they always tile the screen
    // with a single shared edge and opaque pixels — the way a page view pans,
    // without ever being draggable.
    final dx = entering
        ? direction * width * (1 - progress)
        : (leaving ? -direction * width * progress : 0.0);

    return Offstage(
      offstage: !entering && !leaving,
      child: TickerMode(
        enabled: entering || leaving,
        // The page being left is still visible, but it must not take taps or
        // screen-reader focus on its way out.
        child: ExcludeSemantics(
          excluding: !entering,
          child: ExcludeFocus(
            excluding: !entering,
            child: IgnorePointer(
              ignoring: !entering,
              child: Transform.translate(offset: Offset(dx, 0), child: child),
            ),
          ),
        ),
      ),
    );
  }
}
