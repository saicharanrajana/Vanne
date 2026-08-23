// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_shapes.dart';
import '../../../../app/theme/app_spacing.dart';

/// One expressive rounded metadata card in the detail sheet's 2-column
/// grid: a leading icon, the prominent value, and a smaller label
/// (e.g. `1200 x 1697` / `Resolution`).
///
/// Colors come from the ambient wallpaper-derived [Theme] — no plumbing.
final class WallpaperInfoCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const WallpaperInfoCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppShapes.extraLargeIncreased),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
