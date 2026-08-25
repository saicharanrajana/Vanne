import 'package:m3e_core/m3e_core.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../app/dependencies.dart';
import '../../../core/collections/collection_entry.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../../../shared/widgets/wallpaper_grid.dart';
import '../application/collections_controller.dart';
import 'widgets/create_collection_dialog.dart';

/// Collections destination: user-manageable shortcuts to search queries.
///
/// Grid of [CollectionEntry] cards styled like the old category cards
/// (centered initial + title on an expressive M3E shape). Long-press enters
/// multi-select; a filled trash appears in the header while anything is
/// selected. Creating happens via the FAB; deleting asks for confirmation.
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
        .map((e) => e.name)
        .toList();
    final count = names.length;
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count collection${count == 1 ? '' : 's'}?'),
        content: Text(
          '${names.join(', ')}\n\nWallpapers aren’t deleted — only these '
          'shortcuts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await controller.removeMany(Set<String>.from(selected));
    controller.clearSelection();
    if (!context.mounted) return;
    AppSnack.show(
      context,
      deleted ? 'Deleted $count' : 'Couldn’t delete — please try again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = locator<CollectionsController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SignalBuilder(
      builder: (context) {
        final entries = controller.entries.value;
        final hasSelection = controller.hasSelection.value;

        // Selection chrome lives INSIDE flexibleSpace: SliverAppBar.actions
        // render in the toolbar row whose height is 0 here, so they'd be
        // invisible. The Row below is proven-visible (same slot as the old
        // title).
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          'Collections',
                          style: theme.textTheme.displaySmall,
                        ),
                      ),
                    ),
                    if (hasSelection) ...[
                      IconButton(
                        tooltip: 'Clear selection',
                        icon: const Icon(BootstrapIcons.x_lg),
                        onPressed: controller.clearSelection,
                      ),
                      IconButton(
                        tooltip: 'Delete selected',
                        icon: Icon(
                          BootstrapIcons.trash_fill,
                          color: scheme.error,
                        ),
                        onPressed: () =>
                            _confirmDelete(context, controller, entries),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );

        final Widget list;
        if (entries.isEmpty) {
          list = CustomScrollView(
            slivers: [
              headerSliver,
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  iconData: BootstrapIcons.collection_fill,
                  title: 'No collections yet',
                  message:
                      'Create a collection to save a search — they’re just '
                      'shortcuts, e.g. “Anime” or “Dark minimal”.',
                ),
              ),
              const SliverToBoxAdapter(child: BottomPadding()),
            ],
          );
        } else {
          list = CustomScrollView(
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
                    // the index's element — M3EContainer morphs between
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
                      onLongPress: () => controller.toggleSelection(entry.id),
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
          body: SafeArea(bottom: false, child: list),
          // Add lives on a FAB; the header stays clean unless deleting.
          floatingActionButton: hasSelection
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => showCreateCollectionDialog(context),
                  icon: const Icon(BootstrapIcons.plus_lg),
                  label: const Text('New collection'),
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

  static const _shapes = [
    Shapes.circle,
    Shapes.square,
    Shapes.c9SidedCookie,
    Shapes.c12SidedCookie,
    Shapes.gem,
    Shapes.arch,
    Shapes.clampShell,
  ];

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
    final hash = entry.id.hashCode.abs();
    final shape = _shapes[hash % _shapes.length];
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
                child: M3EContainer(
                  shape,
                  color: bg,
                  border: BorderSide(
                    color: accent.withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
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
                            child: Text(
                              entry.name.isEmpty
                                  ? '?'
                                  : entry.name[0].toUpperCase(),
                              style: textTheme.titleLarge?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                              ),
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
                    BootstrapIcons.check_lg,
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
