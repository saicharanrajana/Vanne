import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:signals/signals_flutter.dart';

import '../../../app/dependencies.dart';
import '../../../app/router/app_route.dart';
import '../../../app/router/tab_scroll_coordinator.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/collections/collection_entry.dart';
import '../../../core/collections/seed_collections.dart';
import '../../../shared/utils/color_display.dart';
import '../../../shared/utils/hex_color.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../../../shared/widgets/smart_network_image.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../application/collections_controller.dart';

/// Collections destination: saved searches opened by bookmarking a tag or
/// color grid.
///
/// Square M3E cards show a wallpaper cover (or the exact color for color
/// searches) with the title centered on top. Long-press enters multi-select;
/// a floating toolbar with clear/delete actions appears. Collections are
/// created only by bookmarking a tag or color grid.
final class CollectionsScreen extends StatelessWidget {
  final ValueChanged<String> onOpenCollection;

  const CollectionsScreen({super.key, required this.onOpenCollection});

  Future<void> _confirmDelete(
    BuildContext context,
    CollectionsController controller,
    List<CollectionEntry> entries,
  ) async {
    final selected = controller.selectedIds.value;
    final count = entries
        .where((entry) => selected.contains(entry.id))
        .length;
    final ok = await context.router.root.push<bool>(
      DeleteCollectionsDialogRoute(count: count),
    );
    if (ok != true) return;
    final removed = await controller.removeMany(Set<String>.from(selected));
    controller.clearSelection();
    AppSnack.showRoot(
      removed ? 'Removed $count' : 'Couldn’t remove. Please try again.',
      type: removed ? AppSnackType.success : AppSnackType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = locator<CollectionsController>();
    final theme = Theme.of(context);

    return SignalBuilder(
      builder: (context) {
        final entries = controller.entries.value;
        final hasSelection = controller.hasSelection.value;

        final headerSliver = SliverAppBar(
          floating: true,
          snap: true,
          pinned: false,
          automaticallyImplyLeading: false,
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 0,
          collapsedHeight: 0,
          expandedHeight: 80,
          flexibleSpace: FlexibleSpaceBar(
            background: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
                child: Align(
                  alignment: AlignmentDirectional.bottomStart,
                  child: Text(
                    'Collections',
                    style: theme.textTheme.displaySmall,
                  ),
                ),
              ),
            ),
          ),
        );

        final Widget list;
        if (entries.isEmpty) {
          list = CustomScrollView(
            controller: locator<TabScrollCoordinator>().collections,
            slivers: [
              headerSliver,
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  iconData: PhosphorIconsFill.bookmarkSimple,
                  title: 'No collections yet',
                  message:
                      'Open a wallpaper’s tag or color, then tap the bookmark '
                      'to save it here.',
                ),
              ),
              const SliverToBoxAdapter(child: BottomPadding()),
            ],
          );
        } else {
          list = CustomScrollView(
            controller: locator<TabScrollCoordinator>().collections,
            slivers: [
              headerSliver,
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 1,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final entry = entries[i];
                    // Keyed by id: after deletions shift positions, each
                    // card must remount fresh instead of the sliver reusing
                    // the index's element.
                    return _CollectionCard(
                      key: ValueKey('collection-${entry.id}'),
                      controller: controller,
                      entry: entry,
                      onTap: () {
                        if (hasSelection) {
                          controller.toggleSelection(entry.id);
                        } else {
                          onOpenCollection(entry.id);
                        }
                      },
                      onLongPress: () {
                        M3EHaptics.trigger(M3EHapticFeedback.medium);
                        controller.toggleSelection(entry.id);
                      },
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: BottomPadding()),
            ],
          );
        }

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Stack(
            children: [
              SafeArea(bottom: false, child: list),
              if (hasSelection)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: Center(
                        child: M3EToolbar(
                          colorStyle: M3EToolbarColorStyle.vibrant,
                          actions: [
                            M3EToolbarAction(
                              icon: PhosphorIconsBold.x,
                              tooltip: 'Clear selection',
                              onPressed: controller.clearSelection,
                            ),
                            M3EToolbarAction(
                              icon: PhosphorIconsFill.trash,
                              tooltip: 'Remove selected',
                              isDestructive: true,
                              active: true,
                              onPressed: () =>
                                  _confirmDelete(context, controller, entries),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The exact color a color collection was saved with, or `null` for a
  /// query collection. Wallhaven's raw hex is used, not its nearest search
  /// color.
  static String? _colorHexFor(CollectionEntry entry) {
    if (entry.colors.isNotEmpty) return entry.colors.first;
    if (entry.name.trim().startsWith('#')) return entry.name.trim();
    return null;
  }
}

final class _CollectionCard extends StatelessWidget {
  final CollectionsController controller;
  final CollectionEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CollectionCard({
    super.key,
    required this.controller,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Per-card subscription: each visible card watches [selectedIds]
    // directly (same pattern as WallpaperTile's favorite heart), so every
    // card reflects selection immediately — not just the one tapped.
    return SignalBuilder(
      builder: (context) {
        final selected = controller.selectedIds.value.contains(entry.id);
        return _buildCard(context, selected);
      },
    );
  }

  Widget _buildCard(BuildContext context, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final colorHex = CollectionsScreen._colorHexFor(entry);
    final color = colorHex == null ? null : parseHexColor(colorHex);
    final coverAsset = entry.coverAsset ?? seedCoverAssets[entry.id];
    final hasCover =
        color == null && (coverAsset != null || entry.coverUrl != null);

    final title = colorHex == null
        ? entry.displayName
        : ColorDisplay.nameForHex(colorHex) ?? entry.displayName;
    final subtitle = colorHex == null
        ? null
        : ColorDisplay.normalizedHex(colorHex) ?? entry.displayName;

    // Color cards keep the saved RGB as the background and pick a foreground
    // that is both related to its hue and at least 4.5:1 against it. Image
    // cards always use light text over the fixed scrim below.
    final background = color ?? scheme.secondaryContainer;
    final foreground = color != null
        ? ColorDisplay.onColorFor(color)
        : hasCover
        ? Colors.white
        : scheme.onSecondaryContainer;

    return Semantics(
      button: true,
      selected: selected,
      label: subtitle == null
          ? 'Open $title collection'
          : 'Open $title collection, $subtitle',
      child: M3EShapeContainer(
        kind: M3EShapeKind.square,
        color: selected ? scheme.primary : Colors.transparent,
        child: Padding(
          // Always inset: the outer silhouette is the selection ring, and a
          // constant inset avoids the card resizing when selection changes.
          padding: const EdgeInsets.all(3),
          child: M3EShapeContainer(
            key: ValueKey('collection-surface-${entry.id}'),
            kind: M3EShapeKind.square,
            color: background,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasCover) _cover(context, coverAsset: coverAsset),
                if (hasCover)
                  // A light full-card scrim keeps bright covers from washing
                  // out the image edges, while the broad radial overlay
                  // concentrates extra shade behind the centred text without
                  // a hard band or plateau.
                  const IgnorePointer(
                    child: ColoredBox(color: Color(0x2E000000)),
                  ),
                if (hasCover)
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.95,
                          colors: [Color(0x99000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    onLongPress: onLongPress,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // A narrow card loses vertical room first. Trim the
                        // padding before shrinking text, then scale the whole
                        // block down only when even the compact layout cannot
                        // fit (very large accessibility text sizes).
                        final compact =
                            constraints.maxHeight < 160 ||
                            constraints.maxWidth < 160;
                        final verticalPadding = compact
                            ? AppSpacing.sm
                            : AppSpacing.lg;
                        final contentWidth =
                            constraints.maxWidth - AppSpacing.md * 2;
                        final baseTitleStyle = textTheme.titleLarge!.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                          height: 1.08,
                          shadows: hasCover
                              ? const [
                                  Shadow(
                                    color: Color(0x8A000000),
                                    blurRadius: 10,
                                  ),
                                ]
                              : null,
                        );
                        final titleStyle = baseTitleStyle.copyWith(
                          fontSize: _fittedTitleSize(
                            context: context,
                            title: title,
                            style: baseTitleStyle.copyWith(
                              fontSize: compact ? 22 : 26,
                            ),
                            maxWidth: contentWidth,
                          ),
                        );
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: verticalPadding,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: contentWidth,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle,
                                  ),
                                  if (subtitle != null) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      subtitle,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodyLarge?.copyWith(
                                        color: foreground,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps the largest word of [title] on one line without shrinking the
  /// rest of the card. A title longer than a narrow card still wraps at
  /// spaces; this only prevents mid-word breaks such as `Cornsil / k`.
  static double _fittedTitleSize({
    required BuildContext context,
    required String title,
    required TextStyle style,
    required double maxWidth,
  }) {
    final baseSize = style.fontSize ?? 26;
    final scaler = MediaQuery.textScalerOf(context);
    final words = title.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty || maxWidth <= 0) return baseSize;

    double widest(double candidate) {
      final candidateStyle = style.copyWith(fontSize: candidate);
      var width = 0.0;
      for (final word in words) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: candidateStyle),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        width = math.max(width, painter.width);
      }
      return width;
    }

    var size = baseSize;
    var width = widest(size);
    // Font metrics are not perfectly linear with size; remeasure once after
    // scaling so a small correction cannot leave a word one pixel too wide.
    for (var attempt = 0; attempt < 2 && width > maxWidth; attempt++) {
      size = (size * maxWidth / width).clamp(14.0, baseSize);
      width = widest(size);
    }
    return size;
  }

  Widget _cover(BuildContext context, {String? coverAsset}) {
    final scheme = Theme.of(context).colorScheme;
    final key = ValueKey('collection-cover-${entry.id}');
    final asset = coverAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        key: key,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => ColoredBox(color: scheme.secondaryContainer),
      );
    }
    return SmartNetworkImage(
      entry.coverUrl!,
      key: key,
      fit: BoxFit.cover,
      memCacheWidth: 600,
      placeholderColor: scheme.secondaryContainer,
    );
  }
}
