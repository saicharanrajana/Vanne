import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/buttons/enums/m3e_button_enums.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/domain/feed_filter.dart';
import '../../../../shared/widgets/spring_sheet.dart';
import '../../application/discover_controller.dart';

/// Opens the Discover filter/sort sheet — spring-driven.
///
/// Uses `showSpringBottomSheet` so all bottom sheets share the same spring
/// physics. Height = content height (no overshoot) and drag-to-dismiss
/// carries velocity. Collapsable via drag.
Future<void> showDiscoverFilterSheet(
  BuildContext context, {
  required DiscoverController controller,
}) {
  return showSpringBottomSheet<void>(
    context: context,
    builder: (context) => _DiscoverFilterSheet(controller: controller),
  );
}

final class _DiscoverFilterSheet extends StatefulWidget {
  final DiscoverController controller;

  const _DiscoverFilterSheet({required this.controller});

  @override
  State<_DiscoverFilterSheet> createState() => _DiscoverFilterSheetState();
}

final class _DiscoverFilterSheetState extends State<_DiscoverFilterSheet> {
  late FeedFilter _draft = widget.controller.filter.value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Center(
                child: Text(
                  'Sort & filter',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Sort by'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final sorting in FeedSorting.values)
                    M3EChip(
                      label: sorting.label,
                      type: M3EChipType.filter,
                      selected: _draft.sorting == sorting,
                      onPressed: () => setState(() {
                        _draft = _withSorting(_draft, sorting);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Popular time window'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final range in FeedTopRange.values)
                    M3EChip(
                      label: range.label,
                      type: M3EChipType.filter,
                      selected: _draft.topRange == range,
                      onPressed: _draft.sorting == FeedSorting.popular
                          ? () => setState(() {
                              _draft = _draft.copyWith(topRange: range);
                            })
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Minimum resolution'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final resolution in const ['1920x1080', '2560x1440'])
                    M3EChip(
                      label: '$resolution+',
                      type: M3EChipType.filter,
                      selected: _draft.minResolution == resolution,
                      onPressed: () => setState(() {
                        _draft = _draft.minResolution == resolution
                            ? _draft.copyWith(clearMinResolution: true)
                            : _draft.copyWith(minResolution: resolution);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              Row(
                children: [
                  Expanded(
                    child: M3EButton.icon(
                      style: M3EButtonStyle.outlined,
                      size: M3EButtonSize.md,
                      onPressed: () {
                        setState(() {
                          _draft = FeedFilter.discoverDefault;
                        });
                      },
                      icon: const Icon(
                        PhosphorIconsFill.arrowClockwise,
                        size: 18,
                      ),
                      label: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: M3EButton(
                      style: M3EButtonStyle.filled,
                      size: M3EButtonSize.md,
                      onPressed: () async {
                        await widget.controller.applyFilter(_draft);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static FeedFilter _withSorting(FeedFilter filter, FeedSorting sorting) =>
      sorting == FeedSorting.popular
      ? filter.copyWith(
          sorting: sorting,
          topRange: filter.topRange ?? FeedTopRange.month,
        )
      : filter.copyWith(sorting: sorting);
}

final class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.primary,
        letterSpacing: 0.8,
      ),
    );
  }
}
