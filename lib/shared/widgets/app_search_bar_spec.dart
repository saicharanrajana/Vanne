import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

/// One geometry spec for both search bars in the app.
///
/// Discover shows a collapsed, read-only bar that opens Search; the Search view
/// shows the same bar as an editable field. They must be optically identical:
/// same height, same leading slot, same distance from the bar's edge to the
/// glyph and to the hint. Only the glyph (magnifier vs back) and the page-level
/// padding around the bar differ, because each bar aligns with its own screen's
/// content column.
///
/// Both screens build their bar through [buildBar], so the two call sites
/// cannot drift apart again.
abstract final class AppSearchBarSpec {
  /// Glyph size inside the leading slot.
  static const double leadingIconSize = 20;

  /// The bar's own horizontal padding.
  ///
  /// This is the material_3_expressive default (8); it is restated rather than
  /// left implicit so both bars pass the same value instead of one inheriting
  /// a wider inset.
  static const double barPadding = 8;

  /// Padding applied to both bars.
  static const WidgetStateProperty<EdgeInsetsDirectional> padding =
      WidgetStatePropertyAll(
        EdgeInsetsDirectional.symmetric(horizontal: barPadding),
      );

  /// Resting expand inset.
  ///
  /// Zeroed for both bars: the default 8 would make the bar wider while idle
  /// than when focused, and would stack on top of [barPadding].
  static const double restingExpandPadding = 0;

  /// Leading action as a plain (transparent) icon button.
  ///
  /// Discover's magnifier used to be a bare [Icon], which sat 6dp further in
  /// than Search's back button and left a smaller hit area. Both now use the
  /// same component, so the glyph sits at the same offset and carries the same
  /// 48dp target.
  static Widget leading({
    required Widget icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) => M3EIconButton(
    variant: M3EIconButtonVariant.standard,
    icon: icon,
    tooltip: tooltip,
    semanticLabel: tooltip,
    onPressed: onPressed,
  );

  /// Builds the app's search bar.
  ///
  /// Discover passes the magnifier with [readOnly] and an [onTap]; the Search
  /// view passes the back glyph with a controller/focus node. Glyph, labels
  /// and callbacks stay call-site specific; every geometric property is fixed
  /// here.
  static Widget buildBar({
    required String hintText,
    required IconData glyph,
    required String tooltip,
    required VoidCallback onLeadingPressed,
    bool readOnly = false,
    VoidCallback? onTap,
    TextEditingController? controller,
    FocusNode? focusNode,
    ValueChanged<String>? onSubmitted,
  }) => M3ESearchBar(
    controller: controller,
    focusNode: focusNode,
    hintText: hintText,
    expandRestPadding: restingExpandPadding,
    padding: padding,
    readOnly: readOnly,
    onTap: onTap,
    textInputAction: readOnly ? null : TextInputAction.search,
    onSubmitted: onSubmitted,
    leading: leading(
      icon: Icon(glyph, size: leadingIconSize),
      tooltip: tooltip,
      onPressed: onLeadingPressed,
    ),
  );
}
