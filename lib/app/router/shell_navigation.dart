// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
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

/// Padding M3E's floating bar keeps inside its pill, either side of the
/// content: its own floating padding plus the icon target's optical overhang
/// (measured as 16 either side, and matching what the bar lays out when the
/// content is fully sized). A row narrower than the bar's content box centres
/// inside it; a row wider than it overflows the bar's own `Row`.
const double _pillInnerPadding =
    M3EToolbarTokens.floatingContentPadding +
    M3EToolbarTokens.floatingContentPadding;

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
    this.filterAction,
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

  /// How much taller M3E draws a floating bar that has an adjacent FAB.
  ///
  /// It centres the content band inside the FAB's 80dp box instead of the
  /// bar's own 64dp. The FAB slot below is permanent, so this silhouette never
  /// changes with the destination; it is recorded because scroll clearance has
  /// to allow for it.
  static const double fabDrop = 8;

  /// Height of the floating bar: the content band plus M3E's floating padding.
  static const double barExtent = contentExtent + 16;

  /// Width of the bar's FAB slot: one FAB plus the gap to the pill.
  ///
  /// The slot is permanent. M3E draws a floating bar taller when it has an
  /// adjacent FAB, and that FAB's width is part of the bar's own width. Keeping
  /// the slot stable preserves vertical geometry; horizontal centering is
  /// handled by [_ToolbarHorizontalCentering] as the FAB appears or leaves.
  static const double fabSlotExtent =
      M3EToolbarTokens.fabBaseline + M3EToolbarTokens.toolbarToFabGap;

  /// Space scrollable shell content must leave at the end of its list so its
  /// last row can rest clear of the floating bar and its breathing room.
  static const double scrollClearance = barExtent + fabDrop + screenOffset + 16;

  final int activeIndex;
  final ValueChanged<int> onDestinationSelected;

  /// The active page's "open filters" action, or null when it offers none.
  ///
  /// Read through a listenable because the action is published by the page on
  /// its first frame, after the toolbar has already been built.
  final ValueListenable<VoidCallback?>? filterAction;

  @override
  Widget build(BuildContext context) {
    final listenable = filterAction;
    if (listenable == null) return _buildBar(context, null);
    return ValueListenableBuilder<VoidCallback?>(
      valueListenable: listenable,
      builder: (context, action, _) => _buildBar(context, action),
    );
  }

  Widget _buildBar(BuildContext context, VoidCallback? filter) {
    // Only Discover hosts the filter action: it is a page action, not a fifth
    // destination, so it rides beside the pill as the bar's own FAB rather
    // than taking a pill of its own.
    final showFilter =
        filter != null && activeIndex == ShellDestination.discover.index;

    return _ToolbarHorizontalCentering(
      filterVisible: showFilter,
      child: M3EToolbar(
        safeArea: true,
        screenOffset: screenOffset,
        alignment: Alignment.bottomCenter,
        colorStyle: M3EToolbarColorStyle.standard,
        expanded: true,
        semanticLabel: 'Main navigation',
        // The filter is the bar's own adjacent FAB rather than an appended
        // action: M3E lays the FAB out beside the pill, so the two never share
        // a selection state and the pill stays a destinations-only surface.
        // `fabExpandsToolbar: false` keeps the pill permanently open and gives
        // the FAB a single job — run [onFabPressed] — instead of expanding it.
        onFabPressed: showFilter ? filter : null,
        fabExpandIcon: const _FilterFabGlyph(),
        fabCollapseIcon: const _FilterFabGlyph(),
        fabExpandsToolbar: false,
        // The slot's surface animates in and out; the slot itself never moves.
        floatingActionButton: _FilterFabSurface(
          key: const ValueKey('shell-filter-fab'),
          onPressed: showFilter ? filter : null,
        ),
        actions: [
          M3EToolbarWidget(
            child: _DestinationBar(
              activeIndex: activeIndex,
              onDestinationSelected: onDestinationSelected,
              maxWidth: _rowBudget(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Widest the destination row may be without escaping the bar.
  ///
  /// M3E lays a floating bar out at its content's natural width, so the row
  /// has to know its own share: the screen, less the bar's screen offset, less
  /// the pill's inner padding, less the FAB slot.
  double _rowBudget(BuildContext context) =>
      MediaQuery.sizeOf(context).width -
      2 * (screenOffset + _pillInnerPadding) -
      fabSlotExtent;
}

/// Horizontally centers the visible toolbar contents as the FAB fades in/out.
///
/// M3E centers the two-piece FAB/pill layout on its combined optical bounds.
/// This compensates the pill/FAB group's package-derived asymmetric extents:
/// the pill alone is centered when hidden, and pill plus FAB are centered when
/// visible. AnimatedSlide keeps the two alignments fluid and reversible.
final class _ToolbarHorizontalCentering extends StatelessWidget {
  const _ToolbarHorizontalCentering({
    required this.filterVisible,
    required this.child,
  });

  final bool filterVisible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final halfSlot = ShellNavigationToolbar.fabSlotExtent / 2;
    final shownOverhang = halfSlot + M3EToolbarTokens.floatingContentPadding;
    final logicalOffset = filterVisible ? halfSlot - shownOverhang : halfSlot;
    final width = MediaQuery.sizeOf(context).width;

    return AnimatedSlide(
      offset: Offset((rtl ? -1 : 1) * logicalOffset / width, 0),
      duration: reduceMotion ? Duration.zero : AppMotion.tabSelectionFade,
      curve: AppMotion.tabTransitionCurve,
      child: child,
    );
  }
}

/// The Discover filter glyph, worn by the bar's own adjacent FAB.
///
/// Split out as a widget so the FAB's icon — the only interactive part of it
/// that the shell owns — keeps the trigger key journeys tap, and so the glyph
/// still carries a tooltip and a semantic name. M3E builds the default FAB
/// from an icon only, so the name has to travel with the icon.
final class _FilterFabGlyph extends StatelessWidget {
  const _FilterFabGlyph();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Filters',
      excludeFromSemantics: true,
      child: Semantics(
        key: const ValueKey('feed-filter-trigger-discover'),
        container: true,
        button: true,
        label: 'Filters',
        child: const Icon(PhosphorIconsBold.slidersHorizontal, size: 24),
      ),
    );
  }
}

/// The bar's FAB slot surface: the sort & filter trigger, or nothing.
///
/// The slot is permanent (see [ShellNavigationToolbar.fabSlotExtent]) and only
/// this surface changes, so the trigger can appear and leave smoothly without
/// the bar — or the selection pill beside it — shifting. While it is away the
/// slot is inert: no hit testing, no semantics, nothing painted.
final class _FilterFabSurface extends StatelessWidget {
  const _FilterFabSurface({required this.onPressed, super.key});

  /// The filter action, or null while the active destination has none.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final shown = onPressed != null;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduceMotion ? Duration.zero : AppMotion.tabSelectionFade;

    return IgnorePointer(
      ignoring: !shown,
      child: ExcludeSemantics(
        excluding: !shown,
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: duration,
          curve: AppMotion.tabTransitionCurve,
          child: AnimatedScale(
            scale: shown ? 1 : 0.72,
            duration: duration,
            curve: AppMotion.tabTransitionCurve,
            child: M3EFab(
              icon: const _FilterFabGlyph(),
              color: M3EFabColor.secondary,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
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
    required this.maxWidth,
  });

  final int activeIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Widest the destination row may become, already reduced by any trailing
  /// action the toolbar hosts.
  final double maxWidth;

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
    // budget the bar would happily grow wider than the screen.
    final budget = widget.maxWidth;

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
          // Where even the clamped slot cannot hold the whole label, the slot
          // stays icon-only with its name in the tooltip and semantics rather
          // than painting a clipped word.
          final labelFits = [
            for (final destination in destinations)
              _labelWidth(context, destination.label, textStyle) +
                      _iconExtent +
                      _labelGap +
                      _pillPadding * 2 <=
                  maxSelected,
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
                          showLabel: labelFits[index],
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
    this.showLabel = true,
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

  /// Whether this slot's label fits inside its selected extent.
  final bool showLabel;

  final Color idleColor;
  final Color selectedColor;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The label only appears in the last sliver of the indicator's travel —
    // once its slot is wide enough to hold it in full — so it is never caught
    // mid-clip, and exactly one label is in the tree at rest.
    final labelOpacity = showLabel
        ? ((activation - 0.9) / 0.1).clamp(0.0, 1.0)
        : 0.0;

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
