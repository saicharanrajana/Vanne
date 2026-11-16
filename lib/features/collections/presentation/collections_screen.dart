import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:signals/signals_flutter.dart';

import '../../../app/dependencies.dart';
import '../../../app/router/tab_scroll_coordinator.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/collections/collection_entry.dart';
import '../../../core/collections/seed_collections.dart';
import '../../../shared/utils/color_display.dart';
import '../../../shared/utils/hex_color.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../../../shared/widgets/image_overlay_control.dart';
import '../../../shared/widgets/smart_network_image.dart';
import '../application/collections_controller.dart';

/// Collections destination: saved searches opened by bookmarking a tag or
/// color grid.
///
/// Square M3E cards show a wallpaper cover (or the exact color for color
/// searches) with the title centered on top. A tap opens the collection;
/// long-press-and-drag reorders the grid, which is persisted so the user's
/// own priority order survives a restart. Every collection can move,
/// including the curated defaults — permanence means "cannot be removed",
/// not "pinned to the top".
///
/// Collections are created and removed from the browsing screen they belong
/// to (the `+ Add` / `✓ Added` app-bar control), never in bulk from here, so
/// there is no selection mode and no "no collections" state: the curated
/// defaults are always present.
final class CollectionsScreen extends StatelessWidget {
  final ValueChanged<String> onOpenCollection;

  const CollectionsScreen({super.key, required this.onOpenCollection});

  @override
  Widget build(BuildContext context) {
    final controller = locator<CollectionsController>();
    final theme = Theme.of(context);

    return SignalBuilder(
      builder: (context) {
        final entries = controller.entries.value;

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

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              controller: locator<TabScrollCoordinator>().collections,
              slivers: [
                headerSliver,
                _CollectionsGridSliver(
                  entries: entries,
                  controller: controller,
                  onOpenCollection: onOpenCollection,
                ),
                const SliverToBoxAdapter(child: BottomPadding()),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The exact color a color collection was saved with, or `null` for a
  /// query collection. Wallhaven's raw hex is used, not its nearest search
  /// color.
  static String? colorHexFor(CollectionEntry entry) {
    if (entry.colors.isNotEmpty) return entry.colors.first;
    if (entry.name.trim().startsWith('#')) return entry.name.trim();
    return null;
  }
}

/// The reorderable grid itself.
///
/// A [StatefulWidget] (not a plain sliver) because the drag has cross-item
/// state: the pending order, the card currently lifted, the last pointer
/// position, and the auto-scroller. It renders exactly one sliver, so it can
/// sit directly in [CustomScrollView.slivers].
///
/// Reordering is local while the finger is down — the grid rebuilds in the
/// pending order, which is what the user sees — and is persisted once, on
/// drop. A failed write rolls back inside the controller, so the grid snaps
/// back to the stored order and a snackbar explains why.
final class _CollectionsGridSliver extends StatefulWidget {
  final List<CollectionEntry> entries;
  final CollectionsController controller;
  final ValueChanged<String> onOpenCollection;

  const _CollectionsGridSliver({
    required this.entries,
    required this.controller,
    required this.onOpenCollection,
  });

  @override
  State<_CollectionsGridSliver> createState() => _CollectionsGridSliverState();
}

final class _CollectionsGridSliverState extends State<_CollectionsGridSliver> {
  static const int _crossAxisCount = 2;

  /// Pending order while a drag is in flight; `null` means "use the
  /// controller's persisted order".
  List<String>? _dragOrder;

  String? _draggingId;
  Offset? _pointer;
  Size? _draggedCardSize;
  EdgeDraggingAutoScroller? _autoScroller;

  /// One key per card, so a card can be located under the pointer even while
  /// the auto-scroller is moving content (the drag avatar itself never moves,
  /// so [DragTarget] callbacks alone cannot notice that).
  final Map<String, GlobalKey> _cardKeys = {};

  GlobalKey _keyFor(String id) =>
      _cardKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'collection-$id'));

  @override
  void dispose() {
    _autoScroller?.stopAutoScroll();
    super.dispose();
  }

  List<String> get _order =>
      _dragOrder ?? [for (final entry in widget.entries) entry.id];

  void _beginDrag(String id) {
    M3EHaptics.trigger(M3EHapticFeedback.medium);
    final box = _cardKeys[id]?.currentContext?.findRenderObject();
    setState(() {
      _draggingId = id;
      _dragOrder = _order;
      _draggedCardSize = box is RenderBox && box.hasSize ? box.size : null;
    });
  }

  Future<void> _endDrag() async {
    final order = _dragOrder;
    if (_draggingId == null) return;
    _autoScroller?.stopAutoScroll();
    setState(() {
      _draggingId = null;
      _dragOrder = null;
      _pointer = null;
    });
    if (order == null) return;
    await _persistOrder(order);
  }

  /// Moves the lifted card to [targetId]'s slot.
  ///
  /// Standard move semantics: the dragged card lands *after* a target it was
  /// above, and *before* one it was below, which is what makes a drag feel
  /// like it is pushing the grid rather than swapping neighbours.
  void _moveOver(String targetId) {
    final draggingId = _draggingId;
    if (draggingId == null || draggingId == targetId) return;
    final order = List<String>.from(_order);
    final from = order.indexOf(draggingId);
    final to = order.indexOf(targetId);
    if (from < 0 || to < 0 || from == to) return;
    order.removeAt(from);
    order.insert(to.clamp(0, order.length), draggingId);
    if (listEquals(order, _order)) return;
    setState(() => _dragOrder = order);
  }

  Future<void> _persistOrder(List<String> order) async {
    final stored = [for (final entry in widget.entries) entry.id];
    if (listEquals(order, stored)) return;
    final persisted = await widget.controller.reorder(order);
    if (persisted) return;
    AppSnack.showRoot(
      'Couldn’t save the new order. Please try again.',
      type: AppSnackType.error,
    );
  }

  Future<void> _moveToEdge(String id, {required bool toStart}) async {
    final order = List<String>.from(_order)..remove(id);
    if (toStart) {
      order.insert(0, id);
    } else {
      order.add(id);
    }
    M3EHaptics.trigger(M3EHapticFeedback.light);
    setState(() => _dragOrder = null);
    await _persistOrder(order);
  }

  void _trackPointer(Offset globalPosition) {
    _pointer = globalPosition;
    _startAutoScroll(globalPosition);
  }

  void _startAutoScroll(Offset globalPosition) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    final scroller = _autoScroller ??= EdgeDraggingAutoScroller(
      scrollable,
      velocityScalar: 20,
      onScrollViewScrolled: _reorderUnderPointer,
    );
    scroller.startAutoScrollIfNecessary(
      Rect.fromCenter(center: globalPosition, width: 1, height: 1),
    );
  }

  /// After an auto-scroll step, the card under the finger has changed even
  /// though no new pointer event arrived. Recompute it from the rendered
  /// cards so a long drag keeps reordering while the grid scrolls.
  void _reorderUnderPointer() {
    final pointer = _pointer;
    if (pointer == null || _draggingId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pointer = _pointer;
      if (!mounted || pointer == null || _draggingId == null) return;
      final targetId = _cardIdAt(pointer);
      if (targetId != null) _moveOver(targetId);
    });
  }

  String? _cardIdAt(Offset globalPosition) {
    for (final entry in _cardKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPosition)) return entry.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final entry in widget.entries) entry.id: entry};
    // Keys for rows that no longer exist would otherwise accumulate for the
    // lifetime of the tab, which stays mounted.
    if (_cardKeys.length > byId.length) {
      _cardKeys.removeWhere((id, _) => !byId.containsKey(id));
    }
    final ids = _order.where(byId.containsKey).toList(growable: false);
    if (ids.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final dragging = _draggingId;

    return SliverPadding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: 1,
        ),
        itemCount: ids.length,
        itemBuilder: (ctx, index) {
          final id = ids[index];
          final entry = byId[id]!;
          final card = KeyedSubtree(
            key: _keyFor(id),
            child: _CollectionCard(
              key: ValueKey('collection-${entry.id}'),
              entry: entry,
              onTap: () {
                if (dragging != null) return;
                widget.onOpenCollection(entry.id);
              },
              onMoveToStart: index == 0
                  ? null
                  : () => _moveToEdge(entry.id, toStart: true),
              onMoveToEnd: index == ids.length - 1
                  ? null
                  : () => _moveToEdge(entry.id, toStart: false),
            ),
          );

          if (ids.length < 2) return card;

          return DragTarget<String>(
            onWillAcceptWithDetails: (details) {
              if (details.data == id) return false;
              _trackPointer(details.offset);
              _moveOver(id);
              return true;
            },
            onMove: (details) => _trackPointer(details.offset),
            builder: (context, candidate, rejected) => LongPressDraggable<String>(
              data: id,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              hapticFeedbackOnStart: false,
              // The preview is a key-free copy of the card: the lifted card
              // is mounted in the overlay while its original is still in the
              // grid, so sharing keys (or a GlobalKey) would be a duplicate.
              feedback: _DragPreview(
                size: _draggedCardSize,
                child: _CollectionCard(
                  entry: entry,
                  preview: true,
                  onTap: () {},
                  onMoveToStart: null,
                  onMoveToEnd: null,
                ),
              ),
              childWhenDragging: AbsorbPointer(
                child: Opacity(opacity: 0.35, child: card),
              ),
              onDragStarted: () => _beginDrag(id),
              onDragEnd: (_) => _endDrag(),
              onDraggableCanceled: (_, _) => _endDrag(),
              child: card,
            ),
          );
        },
      ),
    );
  }
}

/// The lifted card: slightly grown and floating, so the grid reads as
/// "holding a card" rather than "the card vanished".
final class _DragPreview extends StatelessWidget {
  final Size? size;
  final Widget child;

  const _DragPreview({required this.size, required this.child});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1.04,
      child: SizedBox.fromSize(
        size: size ?? const Size.square(160),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

final class _CollectionCard extends StatelessWidget {
  final CollectionEntry entry;
  final VoidCallback onTap;

  /// Reordering actions offered through the card's menu. `null` disables the
  /// entry (already first/last), which keeps the affordance discoverable
  /// without letting it promise a no-op.
  final VoidCallback? onMoveToStart;
  final VoidCallback? onMoveToEnd;

  /// Rendered as drag feedback: the same artwork and title, without the
  /// interactive parts or any keys, because the real card is still mounted.
  final bool preview;

  const _CollectionCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onMoveToStart,
    required this.onMoveToEnd,
    this.preview = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final colorHex = CollectionsScreen.colorHexFor(entry);
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

    final reorderActions = <CustomSemanticsAction, VoidCallback>{
      const CustomSemanticsAction(label: 'Move to start'): ?onMoveToStart,
      const CustomSemanticsAction(label: 'Move to end'): ?onMoveToEnd,
    };

    if (preview) {
      return M3EShapeContainer(
        kind: M3EShapeKind.square,
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover) _cover(context, coverAsset: coverAsset),
            if (hasCover) ..._coverScrims(),
            _label(
              context: context,
              title: title,
              subtitle: subtitle,
              foreground: foreground,
              hasCover: hasCover,
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label: subtitle == null
          ? 'Open $title collection'
          : 'Open $title collection, $subtitle',
      customSemanticsActions: reorderActions.isEmpty ? null : reorderActions,
      child: M3EShapeContainer(
        key: ValueKey('collection-surface-${entry.id}'),
        kind: M3EShapeKind.square,
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover) _cover(context, coverAsset: coverAsset),
            if (hasCover) ..._coverScrims(),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                child: _label(
                  context: context,
                  title: title,
                  subtitle: subtitle,
                  foreground: foreground,
                  hasCover: hasCover,
                ),
              ),
            ),
            // Reorder actions live in the corner so they are reachable
            // without a drag gesture (keyboard, switch access, small precise
            // targets) and without a long press the card itself consumes.
            if (onMoveToStart != null || onMoveToEnd != null)
              PositionedDirectional(
                end: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: _ReorderMenu(
                  onMoveToStart: onMoveToStart,
                  onMoveToEnd: onMoveToEnd,
                  hasCover: hasCover,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Dark shading over the cover so the centred title stays legible on both
  /// bright and busy artwork.
  List<Widget> _coverScrims() => const [
    // A light full-card scrim keeps bright covers from washing out the image
    // edges, while the broad radial overlay concentrates extra shade behind
    // the centred text without a hard band or plateau.
    IgnorePointer(child: ColoredBox(color: Color(0x2E000000))),
    IgnorePointer(
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
  ];

  /// The centred title (and, for colour cards, the exact hex) shared by the
  /// live card and its drag preview.
  Widget _label({
    required BuildContext context,
    required String title,
    required String? subtitle,
    required Color foreground,
    required bool hasCover,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A narrow card loses vertical room first. Trim the padding before
        // shrinking text, then scale the whole block down only when even the
        // compact layout cannot fit (very large accessibility text sizes).
        final compact =
            constraints.maxHeight < 160 || constraints.maxWidth < 160;
        final verticalPadding = compact ? AppSpacing.sm : AppSpacing.lg;
        final contentWidth = constraints.maxWidth - AppSpacing.md * 2;
        final baseTitleStyle = textTheme.titleLarge!.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
          height: 1.08,
          shadows: hasCover
              ? const [Shadow(color: Color(0x8A000000), blurRadius: 10)]
              : null,
        );
        final titleStyle = baseTitleStyle.copyWith(
          fontSize: _fittedTitleSize(
            context: context,
            title: title,
            style: baseTitleStyle.copyWith(fontSize: compact ? 22 : 26),
            maxWidth: contentWidth,
          ),
        );
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: verticalPadding,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
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
          ),
        );
      },
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
    final key = preview ? null : ValueKey('collection-cover-${entry.id}');
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

/// The card-corner menu with the two non-drag reorder actions.
final class _ReorderMenu extends StatelessWidget {
  final VoidCallback? onMoveToStart;
  final VoidCallback? onMoveToEnd;
  final bool hasCover;

  const _ReorderMenu({
    required this.onMoveToStart,
    required this.onMoveToEnd,
    required this.hasCover,
  });

  @override
  Widget build(BuildContext context) {
    return M3EMenu.entries(
      position: M3EMenuAnchorPosition.topEnd,
      anchorBuilder: (context, open) => M3EIconButton(
        variant: M3EIconButtonVariant.standard,
        size: M3EIconButtonSize.xs,
        decoration: hasCover ? imageOverlayIconButtonDecoration : null,
        onPressed: open,
        tooltip: 'Reorder collection',
        semanticLabel: 'Reorder collection',
        icon: const Icon(PhosphorIconsBold.dotsThree),
      ),
      entries: [
        M3EMenuEntry(
          label: 'Move to start',
          leading: const Icon(PhosphorIconsBold.arrowLineUp, size: 18),
          enabled: onMoveToStart != null,
          onPressed: onMoveToStart,
        ),
        M3EMenuEntry(
          label: 'Move to end',
          leading: const Icon(PhosphorIconsBold.arrowLineDown, size: 18),
          enabled: onMoveToEnd != null,
          onPressed: onMoveToEnd,
        ),
      ],
    );
  }
}
