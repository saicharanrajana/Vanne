import 'package:material_ui/material_ui.dart';

/// Shared bottom-sheet styling so every modal sheet looks like one family.
///
/// Previously `smooth_sheets` `MaterialSheetDecoration` with `SheetSize.fit`.
/// Now native: `BoxDecoration` with rounded top corners and surface color,
/// used by `showSpringBottomSheet`'s `SheetContainer` and native
/// `showModalBottomSheet`. Keeps a single source of truth for sheet shape
/// and color, so all bottom sheets (filter + wallpaper details) are
/// consistent — no mixed smooth_sheets/native.
final class AppSheet {
  AppSheet._();

  static const double topRadius = 28.0;

  static BoxDecoration decoration(
    BuildContext context, {
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: color ?? scheme.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(topRadius)),
    );
  }

  static ShapeBorder shape() => const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      );
}
