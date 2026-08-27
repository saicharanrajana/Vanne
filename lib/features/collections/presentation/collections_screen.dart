import 'package:auto_route/auto_route.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../app/dependencies.dart';
import '../../../app/router/app_route.dart';
import '../../../app/router/tab_scroll_coordinator.dart';
import '../../../app/theme/app_shapes.dart';
import '../../../core/collections/collection_entry.dart';
import '../../../shared/utils/hex_color.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../application/collections_controller.dart';
import 'widgets/create_collection_dialog.dart';

/// Collections destination: user-manageable shortcuts to search queries.
///
/// Grid of [CollectionEntry] cards styled like the old category cards
/// (centered initial + title on an expressive M3E shape). Long-press enters
/// multi-select; a floating toolbar with clear/delete actions replaces the
/// FAB while anything is selected. Creating happens via the FAB; deleting
/// asks for confirmation.
final class CollectionsScreen extends StatelessWidget {
  final ValueChanged<String> onOpenCollection;

  const CollectionsScreen({super.key, required this.onOpenCollection});

  Future<void> _confirmDelete(
    BuildContext context,
    CollectionsController controller,
    List<CollectionEntry> entries,
  ) async {
    final selected = controller.selectedIds.value;
    final names = entries
        .where((e) => selected.contains(e.id))
        .map((e) => e.displayName)
        .toList();
    final count = names.length;
    final ok = await context.router.root.push<bool>(
      DeleteCollectionsDialogRoute(names: names),
    );
    if (ok != true) return;
    final deleted = await controller.removeMany(Set<String>.from(selected));
    controller.clearSelection();
    AppSnack.showRoot(
      deleted ? 'Deleted $count' : 'Couldn’t delete. Please try again.',
      type: deleted ? AppSnackType.success : AppSnackType.error,
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
                  iconData: PhosphorIconsFill.stack,
                  title: 'No collections yet',
                  message:
                      'Create a collection to save a search. They’re just '
                      'shortcuts, e.g. “Anime” or “Minimal”.',
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final entry = entries[i];
                    // Keyed by id: after deletions shift positions, each
                    // card must remount fresh instead of the sliver reusing
                    // the index's element; the shape container morphs between
                    // silhouettes on config change, which painted the old
                    // shape underneath the new one ("ghost" overlap).
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
                      padding: const EdgeInsets.only(bottom: 16),
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
                              tooltip: 'Delete selected',
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
          // Add lives on a FAB; while selecting, it's replaced by the
          // floating toolbar above.
          floatingActionButton: hasSelection
              ? null
              : M3EExtendedFab(
                  onPressed: () => showCreateCollectionDialog(context),
                  icon: const Icon(PhosphorIconsBold.plus),
                  label: 'New collection',
                ),
        );
      },
    );
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

  static const _shape = M3EShapeKind.cookie12Sided;

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
    const shape = _shape;
    final bg = selected ? scheme.tertiaryContainer : scheme.secondaryContainer;
    final fg = selected
        ? scheme.onTertiaryContainer
        : scheme.onSecondaryContainer;
    final accent = selected ? scheme.tertiary : scheme.secondary;

    // Consistent transparent square: the shape floats inside it, leaving
    // clear margin so the selection badge NEVER clips on the silhouette.
    return Semantics(
      button: true,
      selected: selected,
      label: 'Open ${entry.displayName} collection',
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: M3EShapeContainer(
                  kind: shape,
                  color: accent.withValues(alpha: 0.18),
                  child: Padding(
                    padding: const EdgeInsets.all(1.2),
                    child: M3EShapeContainer(
                      kind: shape,
                      color: bg,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onTap,
                          onLongPress: onLongPress,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: fg.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Builder(
                                  builder: (context) {
                                    final isColorCollection =
                                        entry.colors.isNotEmpty ||
                                        entry.name.startsWith('#');
                                    if (isColorCollection) {
                                      final parsed = entry.colors.isNotEmpty
                                          ? parseHexColor(entry.colors.first)
                                          : parseHexColor(entry.name);
                                      final hashColor = parsed ?? fg;
                                      return Text(
                                        '#',
                                        style: textTheme.titleLarge?.copyWith(
                                          color: hashColor,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 22,
                                        ),
                                      );
                                    }
                                    return Text(
                                      entry.name.isEmpty
                                          ? '?'
                                          : entry.name[0].toUpperCase(),
                                      style: textTheme.titleLarge?.copyWith(
                                        color: fg,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 22,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Text(
                                entry.displayName,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.secondary, width: 2.5),
                        borderRadius: BorderRadius.circular(AppShapes.large),
                      ),
                    ),
                  ),
                ),
              ),
            if (selected)
              Positioned.directional(
                textDirection: Directionality.of(context),
                top: 0,
                end: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    PhosphorIconsBold.check,
                    size: 14,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
