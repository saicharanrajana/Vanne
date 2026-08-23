// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_shapes.dart';
import '../../../../app/theme/app_spacing.dart';

/// Full-width rounded section container for the detail sheet (Colors,
/// Tags). Optionally carries a section [title] and a [trailing] widget
/// (count badge, expand affordance) on the header row.
final class WallpaperSectionCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;

  const WallpaperSectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppShapes.extraLargeIncreased),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null || trailing != null)
            Row(
              children: [
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ?trailing,
              ],
            ),
          if (title != null || trailing != null)
            const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
