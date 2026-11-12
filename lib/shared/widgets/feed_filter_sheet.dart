import 'package:auto_route/auto_route.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'package:wallhaven_client/wallhaven_client.dart';

import '../../app/router/app_route.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/domain/feed_filter.dart';

/// Generic feed filter sheet shared by Discover, Search and Collection explore.
///
/// Callers pass the current [initial] filter and receive the chosen filter via
/// [onApply]. The sheet owns a local draft so cancelling discards changes.
Future<void> showFeedFilterSheet(
  BuildContext context, {
  required FeedFilter initial,
  required ValueChanged<FeedFilter> onApply,
}) async {
  final result = await context.router.root.push<FeedFilter>(
    FeedFilterSheetRoute(initial: initial),
  );
  if (result != null) onApply(result);
}

final class FeedFilterSheetContent extends StatefulWidget {
  final FeedFilter initial;

  const FeedFilterSheetContent({required this.initial, super.key});

  @override
  State<FeedFilterSheetContent> createState() => _FeedFilterSheetState();
}

final class _FeedFilterSheetState extends State<FeedFilterSheetContent> {
  late FeedFilter _draft = _sanitize(widget.initial);

  static FeedFilter _sanitize(FeedFilter filter) {
    final withoutPeople = filter.categories
        .where((c) => c != WallhavenCategory.people)
        .toSet();
    final sanitized = withoutPeople.isEmpty
        ? const {WallhavenCategory.general}
        : withoutPeople;
    if (sanitized.length == filter.categories.length &&
        sanitized.containsAll(filter.categories)) {
      return filter;
    }
    return filter.copyWith(categories: sanitized);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sections = _sections();

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
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 24,
                    thickness: 1,
                    indent: 4,
                    endIndent: 4,
                    color: scheme.outlineVariant,
                  ),
                sections[i],
              ],
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
                        context.router.root.pop(_draft);
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

  List<Widget> _sections() => [
    _FilterSection(
      title: 'Sort by',
      child: Wrap(
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
    ),
    if (_draft.sorting == FeedSorting.popular)
      _FilterSection(
        title: 'Popular time window',
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final range in FeedTopRange.values)
              M3EChip(
                label: range.label,
                type: M3EChipType.filter,
                selected: _draft.topRange == range,
                onPressed: () => setState(() {
                  _draft = _draft.copyWith(topRange: range);
                }),
              ),
          ],
        ),
      ),
    _FilterSection(
      title: 'Categories',
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final cat in WallhavenCategory.values.where(
            (c) => c != WallhavenCategory.people,
          ))
            M3EChip(
              label: cat.name[0].toUpperCase() + cat.name.substring(1),
              type: M3EChipType.filter,
              selected: _draft.categories.contains(cat),
              onPressed: () => setState(() {
                final next = Set<WallhavenCategory>.from(_draft.categories);
                if (next.contains(cat)) {
                  if (next.length == 1) return;
                  next.remove(cat);
                } else {
                  next.add(cat);
                }
                _draft = _draft.copyWith(categories: next);
              }),
            ),
        ],
      ),
    ),
    _FilterSection(
      title: 'Minimum resolution',
      child: Wrap(
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
    ),
  ];

  static FeedFilter _withSorting(FeedFilter filter, FeedSorting sorting) =>
      filter.copyWith(
        sorting: sorting,
        topRange: sorting == FeedSorting.popular
            ? filter.topRange ?? FeedTopRange.month
            : filter.topRange,
      );
}

final class _FilterSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _FilterSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}
