import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/buttons/enums/m3e_button_enums.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_spacing.dart';
import '../../core/domain/feed_filter.dart';
import 'spring_sheet.dart';

/// Generic feed filter sheet shared by Discover, Search and Collection explore.
///
/// Callers pass the current [initial] filter and receive the chosen filter via
/// [onApply]. The sheet owns a local draft so cancelling discards changes.
Future<void> showFeedFilterSheet(
  BuildContext context, {
  required FeedFilter initial,
  required ValueChanged<FeedFilter> onApply,
}) {
  return showSpringBottomSheet<void>(
    context: context,
    builder: (context) => _FeedFilterSheet(initial: initial, onApply: onApply),
  );
}

final class _FeedFilterSheet extends StatefulWidget {
  final FeedFilter initial;
  final ValueChanged<FeedFilter> onApply;

  const _FeedFilterSheet({required this.initial, required this.onApply});

  @override
  State<_FeedFilterSheet> createState() => _FeedFilterSheetState();
}

final class _FeedFilterSheetState extends State<_FeedFilterSheet> {
  late FeedFilter _draft = widget.initial;

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
                  'Sort & Filter',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Sort by'),
              const SizedBox(height: AppSpacing.md),
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
              const SizedBox(height: AppSpacing.md),
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
              const SizedBox(height: AppSpacing.md),
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
                        widget.onApply(_draft);
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
