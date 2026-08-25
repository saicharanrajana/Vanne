import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

/// Shared favorite toggle with M3E press motion and a selected glyph pop.
final class FavoriteToggleButton extends StatelessWidget {
  final bool selected;
  final VoidCallback? onPressed;
  final M3EIconButtonSize size;
  final Size? visualSize;

  const FavoriteToggleButton({
    super.key,
    required this.selected,
    required this.onPressed,
    this.size = M3EIconButtonSize.sm,
    this.visualSize,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return M3EIconButton(
      isSelected: selected,
      onPressed: onPressed,
      tooltip: selected ? 'Remove from favorites' : 'Save to favorites',
      semanticLabel: selected ? 'Remove from favorites' : 'Save to favorites',
      variant: M3EIconButtonVariant.tonal,
      size: size,
      visualSize: visualSize,
      haptic: M3EHapticFeedback.light,
      icon: Icon(
        PhosphorIconsBold.heart,
        key: const ValueKey('favorite-outline'),
        color: scheme.onSecondaryContainer,
      ),
      selectedIcon: TweenAnimationBuilder<double>(
        key: const ValueKey('favorite-filled'),
        tween: Tween(begin: 0.65, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Icon(PhosphorIconsFill.heart, color: scheme.error),
      ),
    );
  }
}
