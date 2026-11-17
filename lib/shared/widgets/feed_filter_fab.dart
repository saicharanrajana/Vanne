import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Floating trigger for the sort & filter sheet.
///
/// Browsing screens (search, tag/colour results, saved collections) show the
/// sheet's trigger as one expressive FAB rather than a labelled chip: the
/// glyph says what the control does, so no row of shelf-like text competes
/// with the wallpaper grid and no empty space is left beside it. Discover
/// hosts the same action inside the shell toolbar instead.
final class FeedFilterFab extends StatelessWidget {
  const FeedFilterFab({required this.onPressed, this.triggerKey, super.key});

  /// Side of the regular (56dp) FAB.
  static const double extent = 56;

  /// Extra scroll-end padding a list needs so its last row can rest clear of
  /// the FAB instead of sliding underneath it.
  static const double scrollClearance = extent + 32;

  final VoidCallback onPressed;

  /// Key for the button itself, used by journeys and semantics.
  final Key? triggerKey;

  @override
  Widget build(BuildContext context) {
    // Return the button itself so Scaffold can place it above snackbars and
    // account for safe areas and the on-screen keyboard. A full-body Align
    // prevents Scaffold from knowing the FAB's bounds.
    return M3EFab(
      key: triggerKey,
      icon: const Icon(PhosphorIconsBold.slidersHorizontal, size: 24),
      size: M3EFabSize.regular,
      color: M3EFabColor.secondary,
      tooltip: 'Filters',
      onPressed: () {
        M3EHaptics.trigger(M3EHapticFeedback.light);
        onPressed();
      },
    );
  }
}
