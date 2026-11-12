// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'image_overlay_control.dart';

/// Where a [FavoriteToggleButton] is painted.
enum FavoriteToggleSurface {
  /// Directly on wallpaper imagery (feed tiles, full-bleed detail).
  ///
  /// Uses [imageOverlayIconButtonDecoration]: a translucent dark scrim with an
  /// opaque white glyph, so the control reads on both dark and bright photos.
  image,

  /// On a normal app surface (sheet, card, list row).
  ///
  /// Leaves both foreground and container to [M3EIconButton]'s own selected
  /// role pair, so the icon never fights the container it sits on.
  surface,
}

/// Shared favorite toggle with M3E press motion and a selected glyph pop.
///
/// Selection is conveyed by the glyph (outline versus filled heart) plus the
/// button's `selected` semantics, so it is not encoded in colour alone.
final class FavoriteToggleButton extends StatelessWidget {
  final bool selected;
  final VoidCallback? onPressed;
  final M3EIconButtonSize size;
  final Size? visualSize;

  /// Explicit glyph size; `null` inherits the size the component resolves for
  /// [size], which is what feed tiles want. Detail passes a larger value to
  /// make the control read as a primary action.
  final double? iconSize;
  final FavoriteToggleSurface surface;

  const FavoriteToggleButton({
    super.key,
    required this.selected,
    required this.onPressed,
    this.size = M3EIconButtonSize.sm,
    this.visualSize,
    this.iconSize,
    this.surface = FavoriteToggleSurface.image,
  });

  @override
  Widget build(BuildContext context) {
    final overImage = surface == FavoriteToggleSurface.image;
    return M3EIconButton(
      isSelected: selected,
      onPressed: onPressed,
      tooltip: selected ? 'Remove from favorites' : 'Save to favorites',
      semanticLabel: selected ? 'Remove from favorites' : 'Save to favorites',
      variant: overImage
          ? M3EIconButtonVariant.standard
          : M3EIconButtonVariant.tonal,
      decoration: overImage ? imageOverlayIconButtonDecoration : null,
      size: size,
      visualSize: visualSize,
      haptic: M3EHapticFeedback.light,
      icon: Icon(
        PhosphorIconsBold.heart,
        key: const ValueKey('favorite-outline'),
        size: iconSize,
      ),
      selectedIcon: TweenAnimationBuilder<double>(
        key: const ValueKey('favorite-filled'),
        tween: Tween(begin: 0.65, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Icon(PhosphorIconsFill.heart, size: iconSize),
      ),
    );
  }
}
