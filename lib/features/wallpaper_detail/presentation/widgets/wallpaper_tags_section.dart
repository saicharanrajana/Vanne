// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_shapes.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../application/wallpaper_detail_controller.dart';
import 'wallpaper_section_card.dart';

/// "Tags" section with a lightweight expand/collapse.
///
/// * Collapsed: the first two tags plus a `+N` pill (only when more exist).
/// * Expanded: every tag in a wrapping chip layout (never a horizontal
///   scroll) and a chevron collapse affordance in the header.
/// * Expansion animates via [AnimatedSize] — no nested-scroll concerns.
/// * Hidden entirely when the wallpaper has no tags (listings before the
///   detail fetch resolves).
final class WallpaperTagsSection extends StatefulWidget {
  final WallpaperDetailController controller;
  final ValueChanged<String>? onTagTap;

  /// Tags shown before the `+N` pill in the collapsed state.
  static const int collapsedPreviewCount = 2;

  const WallpaperTagsSection({
    super.key,
    required this.controller,
    this.onTagTap,
  });

  @override
  State<WallpaperTagsSection> createState() => _WallpaperTagsSectionState();
}

final class _WallpaperTagsSectionState extends State<WallpaperTagsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final tags = widget.controller.wallpaper.value.tags;
        if (tags == null || tags.isEmpty) return const SizedBox.shrink();

        final overflow =
            tags.length - WallpaperTagsSection.collapsedPreviewCount;
        final canExpand = overflow > 0;

        return WallpaperSectionCard(
          title: 'Tags',
          trailing: canExpand
              ? _Chevron(
                  expanded: _expanded,
                  onTap: () => setState(() => _expanded = !_expanded),
                )
              : null,
          child: AnimatedSize(
            duration: AppMotion.transition,
            curve: AppMotion.arrivalCurve,
            alignment: Alignment.topCenter,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final tag in _visibleTags(tags))
                  _TagChip(
                    name: tag.name,
                    onTap: widget.onTagTap == null
                        ? null
                        : () => widget.onTagTap!(tag.name),
                  ),
                if (!_expanded && canExpand)
                  _OverflowChip(
                    count: overflow,
                    onTap: () => setState(() => _expanded = true),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Collapsed shows only the preview slice; expanded shows everything.
  Iterable<Tag> _visibleTags(List<Tag> tags) =>
      _expanded ? tags : tags.take(WallpaperTagsSection.collapsedPreviewCount);
}

/// Tappable rotating chevron affordance — down when collapsible, up when
/// expanded.
final class _Chevron extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _Chevron({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return M3EIconButton(
      onPressed: onTap,
      tooltip: expanded ? 'Show fewer tags' : 'Show all tags',
      icon: AnimatedRotation(
        turns: expanded ? 0.5 : 0,
        duration: AppMotion.transition,
        child: Icon(
          PhosphorIconsBold.caretDown,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Stadium tag chip on the wallpaper-derived secondary container. Tappable
/// when [onTap] is provided.
final class _TagChip extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;

  const _TagChip({required this.name, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiary,
        borderRadius: BorderRadius.circular(AppShapes.full),
      ),
      child: Text(
        name,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: scheme.onTertiary),
      ),
    );
    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShapes.full),
        child: chip,
      ),
    );
  }
}

/// Tappable `+N` pill that expands the section.
final class _OverflowChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _OverflowChip({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return M3EChip(
      label: '+$count',
      type: M3EChipType.assist,
      elevated: true,
      onPressed: onTap,
    );
  }
}
