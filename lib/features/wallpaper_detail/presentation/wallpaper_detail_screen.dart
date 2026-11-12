import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_shapes.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/extensions/gap_extensions.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../../../shared/widgets/favorite_toggle_button.dart';
import '../../../shared/widgets/image_overlay_control.dart';
import '../../../shared/widgets/smart_network_image.dart';
import '../../../shared/utils/hex_color.dart';
import '../../favorites/application/favorites_controller.dart';

import '../application/wallpaper_detail_controller.dart';
import '../application/wallpaper_metadata.dart';
import 'wallpaper_theme.dart';
import 'widgets/wallpaper_action_bar.dart';
import 'widgets/wallpaper_color_palette.dart';
import 'widgets/wallpaper_info_card.dart';
import 'widgets/wallpaper_tags_section.dart';

/// Wallpaper detail: a full-bleed hero image that extends under the status
/// bar, with the rounded info panel floating ON TOP of it near the bottom.
///
/// Layout is a [Stack]:
/// * background → the wallpaper itself (cover, edge-to-edge),
/// * middle     → back / favorite controls, SafeArea-padded,
/// * bottom     → the opaque info panel whose rounded top corners reveal the
///   wallpaper behind them; metadata, tags and actions live inside it.
final class WallpaperDetailScreen extends StatefulWidget {
  final WallpaperDetailController controller;
  final VoidCallback onBack;

  /// Hero-tag namespace matching the originating list, so two lists
  /// showing the same wallpaper never produce duplicate tags.
  final String heroScope;
  final ValueChanged<String>? onColorTap;
  final ValueChanged<String>? onTagTap;

  const WallpaperDetailScreen({
    super.key,
    required this.controller,
    required this.onBack,
    this.heroScope = '',
    this.onColorTap,
    this.onTagTap,
  });

  @override
  State<WallpaperDetailScreen> createState() => _WallpaperDetailScreenState();
}

/// Peek height of the collapsed sheet — only the drag handle stays visible.
const double _sheetMinExtent = 0.1;

/// Height the sheet rests at when the route opens.
const double _sheetRestExtent = 0.3;

/// Upper bound for the expanded sheet, leaving the wallpaper visible.
const double _sheetCeilingExtent = 0.8;

/// Absorbs sub-pixel rounding so capping to the content never clips the
/// last row.
const double _sheetRoundSlackPx = 1;

/// Tolerance, in pixels, for treating the sheet as resting on a snap anchor.
const double _sheetAnchorTolerancePx = 1;

/// The sheet's interior snap anchors, as one constant list.
///
/// `DraggableScrollableSheet` re-snaps the sheet from a post-frame callback
/// whenever `snapSizes` changes *identity*, and that snap can dispose the
/// scroll position's in-flight drag/hold out from under a finger. A single
/// constant list never changes identity, so the interior anchor survives every
/// content change while the expanded cap moves (see [_expandedExtent]).
const List<double> _sheetSnapSizes = <double>[_sheetRestExtent];

/// Square face for the controls drawn on the wallpaper.
///
/// The button targets stay 48 dp; only the visible circle grows, so the
/// controls read as primary actions instead of incidental chips without
/// changing the touch contract.
const Size _overlayControlFace = Size.square(48);
const double _overlayControlGlyph = 26;

final class _WallpaperDetailScreenState extends State<WallpaperDetailScreen> {
  /// Memoized wallpaper-derived scheme; scheme generation is too
  /// expensive to re-run on every signal tick.
  ColorScheme? _cachedScheme;
  Object? _schemeKey;

  final _sheetController = DraggableScrollableController();

  /// Measures the sheet's natural content height so the expanded anchor can
  /// stop where the content ends instead of always opening to 80 % of the
  /// screen and leaving dead surface under the action group.
  final _sheetContentKey = GlobalKey();
  double _sheetAvailableHeight = 0;
  double? _measuredContentHeight;
  bool _measureScheduled = false;

  /// Expanded anchor the sheet was last built with, so a content-driven cap
  /// change can re-anchor a sheet left behind at the old one.
  double? _lastExpandedExtent;
  bool _reanchorScheduled = false;

  Future<void> _collapseSheet() async {
    if (!_sheetController.isAttached) return;
    try {
      await _sheetController.animateTo(
        _sheetMinExtent,
        duration: AppMotion.transition,
        curve: AppMotion.arrivalCurve,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    widget.controller.loadDetails();
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  /// Reads the sheet content's laid-out height after the current frame.
  ///
  /// The content is measured implicitly: vertical space is unbounded inside
  /// the sheet's scroll view, so its height does not depend on the sheet
  /// height and measuring cannot feed back into the layout that triggered it.
  void _scheduleContentMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final renderObject = _sheetContentKey.currentContext?.findRenderObject();
      final height = renderObject is RenderBox && renderObject.hasSize
          ? renderObject.size.height
          : null;
      final measured = _measuredContentHeight;
      if (height != null &&
          measured != null &&
          (height - measured).abs() < 0.5) {
        return;
      }
      if (height == null && measured == null) return;
      setState(() => _measuredContentHeight = height);
    });
  }

  /// Expanded anchor: the content's own height, capped by the ceiling.
  ///
  /// Never below [_sheetRestExtent], so the resting anchor is always a valid
  /// snap size and [_sheetSnapSizes] can stay a constant.
  double _expandedExtent() {
    final content = _measuredContentHeight;
    if (content == null || _sheetAvailableHeight <= 0) {
      return _sheetCeilingExtent;
    }
    final fitted = (content + _sheetRoundSlackPx) / _sheetAvailableHeight;
    return fitted.clamp(_sheetRestExtent, _sheetCeilingExtent);
  }

  /// Re-anchors the sheet after a content-driven cap change.
  ///
  /// A sheet parked at the old cap would otherwise rest *between* snap anchors
  /// once the cap moves. `DraggableScrollableSheet` starts its snap without
  /// beginning a new scroll activity, which leaves the scrollable's pointer
  /// hold undisposed; the next tap inside the sheet then trips Flutter's
  /// `ScrollableState._handleDragCancel` assertion (`_hold == null`). Following
  /// the cap keeps every resting position on an anchor.
  void _scheduleSheetReanchor() {
    if (_reanchorScheduled) return;
    _reanchorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reanchorScheduled = false;
      if (!mounted || !_sheetController.isAttached) return;
      final expanded = _expandedExtent();
      final tolerance = _sheetAvailableHeight > 0
          ? _sheetAnchorTolerancePx / _sheetAvailableHeight
          : 0.001;
      final size = _sheetController.size;
      final onAnchor =
          size <= _sheetMinExtent + tolerance ||
          (size - _sheetRestExtent).abs() <= tolerance ||
          (size - expanded).abs() <= tolerance;
      if (!onAnchor) _sheetController.jumpTo(expanded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final brightness = baseTheme.brightness;
    final favorites = locator<FavoritesController>();

    // Re-anchor after layout-dependent changes (rotation, text scale) that do
    // not resize the content itself.
    _scheduleContentMeasure();

    // Wallpaper-derived theme — every descendant that uses Theme.of will
    // automatically get wallpaper colors. This makes the screen robust:
    // any future widget added under this Theme without explicit colors
    // will still be wallpaper-tinted without per-widget plumbing.
    //
    // AnimatedTheme cross-fades the whole scheme (colors, scaffold
    // background) when it changes — e.g. a deep-linked wallpaper whose
    // palette only arrives once /w/{id} resolves — instead of snapping.
    return SignalBuilder(
      builder: (context) {
        final wallpaper = widget.controller.wallpaper.value;
        // isRegistered (not a bare get): the detail screen must render
        // even in hosts that never registered Settings (e.g. focused
        // widget tests).
        // Infosheet background must stay wallpaper-derived — collapsing to the
        // true-black ladder (pitch-black) was erasing the palette from the
        // draggable card. The screen-level scaffold is behind the full-bleed
        // hero anyway, so the wallpaper scheme is intentionally kept
        // non-pitch-black.
        const pitchBlack = false;
        final key = Object.hash(wallpaper.id, brightness, wallpaper.colors);
        if (key != _schemeKey || _cachedScheme == null) {
          _cachedScheme = wallpaperScheme(
            wallpaper,
            brightness,
            baseTheme.colorScheme,
            pitchBlack,
          );
          _schemeKey = key;
        }
        final scheme = _cachedScheme!;
        final wallpaperTheme = wallpaperThemeData(scheme, baseTheme);
        return AnimatedTheme(
          data: wallpaperTheme,
          duration: AppMotion.transition,
          curve: AppMotion.arrivalCurve,
          child: Scaffold(
            backgroundColor: wallpaperTheme.colorScheme.surface,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Full-bleed wallpaper behind every other layer.
                Positioned.fill(
                  child: _FullBleedImage(
                    controller: widget.controller,
                    heroScope: widget.heroScope,
                  ),
                ),
                // Top controls — explicitly positioned at top, not relying on
                // Stack's default non-positioned layout which can center.
                Positioned(
                  top: 0,
                  left: 4,
                  right: 4,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          M3EIconButton(
                            onPressed: widget.onBack,
                            tooltip: 'Back',
                            // Sits on the full-bleed wallpaper, not on a
                            // surface: a translucent scrim keeps contrast
                            // without a bright chip over the photo.
                            variant: M3EIconButtonVariant.standard,
                            decoration: imageOverlayIconButtonDecoration,
                            visualSize: _overlayControlFace,
                            icon: const Icon(
                              PhosphorIconsBold.arrowLeft,
                              size: _overlayControlGlyph,
                            ),
                          ),
                          SignalBuilder(
                            builder: (context) => FavoriteToggleButton(
                              selected: favorites.favoriteIds.value.contains(
                                wallpaper.id,
                              ),
                              onPressed: () => favorites.toggle(wallpaper),
                              visualSize: _overlayControlFace,
                              iconSize: _overlayControlGlyph,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Draggable info sheet — snaps between a collapsed peek, a
                // resting height and an expanded anchor capped at the content
                // height (max 0.8) so no dead surface is left below the
                // actions. Content scrolls once it exceeds the sheet.
                Positioned.fill(
                  child: NotificationListener<SizeChangedLayoutNotification>(
                    onNotification: (_) {
                      _scheduleContentMeasure();
                      return true;
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _sheetAvailableHeight = constraints.maxHeight;
                        final expanded = _expandedExtent();
                        if (_lastExpandedExtent != null &&
                            expanded != _lastExpandedExtent) {
                          _scheduleSheetReanchor();
                        }
                        _lastExpandedExtent = expanded;
                        return DraggableScrollableSheet(
                          controller: _sheetController,
                          initialChildSize: _sheetRestExtent,
                          minChildSize: _sheetMinExtent,
                          maxChildSize: expanded,
                          snap: true,
                          snapSizes: _sheetSnapSizes,
                          builder: (context, scrollController) {
                            return ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                              child: _DraggableInfoSheet(
                                controller: widget.controller,
                                scrollController: scrollController,
                                contentKey: _sheetContentKey,
                                onContentLaidOut: _scheduleContentMeasure,
                                onColorTap: widget.onColorTap,
                                onTagTap: widget.onTagTap,
                                onCollapseForSet: _collapseSheet,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Draggable, scrollable info sheet over the wallpaper: a 2×2 metadata
/// card grid, Colors and Tags sections, and the action group. Colors are
/// derived from the wallpaper's dominant colors for a vibrant but readable
/// look in both light/dark. Shows a plain circular indicator until details
/// are fetched.
///
/// The outer [DraggableScrollableSheet] in the screen owns the sheet height;
/// this widget provides the wallpaper-derived surface, drag handle, and
/// scrollable content using the sheet's [scrollController] so drag and
/// scroll are unified (native iOS/Android physics).
///
/// Loaded content is wrapped in a [SizeChangedLayoutNotifier] and keyed by
/// [contentKey] so the screen can cap the expanded sheet to its real height.
final class _DraggableInfoSheet extends StatelessWidget {
  final WallpaperDetailController controller;
  final ScrollController scrollController;
  final GlobalKey contentKey;

  /// Called whenever loaded content is about to lay out.
  ///
  /// [SizeChangedLayoutNotifier] deliberately skips the *first* layout, and
  /// the outer screen does not rebuild when only this subtree swaps from the
  /// loading indicator to loaded content — e.g. when `/w/{id}` resolves after
  /// the route opened. Without this hook that first real content is never
  /// measured and the expanded sheet stays at its 80 % ceiling.
  final VoidCallback onContentLaidOut;

  final ValueChanged<String>? onColorTap;
  final ValueChanged<String>? onTagTap;
  final Future<void> Function()? onCollapseForSet;

  const _DraggableInfoSheet({
    required this.controller,
    required this.scrollController,
    required this.contentKey,
    required this.onContentLaidOut,
    this.onColorTap,
    this.onTagTap,
    this.onCollapseForSet,
  });

  @override
  Widget build(BuildContext context) {
    // The ancestor AnimatedTheme already carries the wallpaper-derived
    // scheme — no local re-derivation needed; scheme changes cross-fade.
    final scheme = Theme.of(context).colorScheme;
    return SignalBuilder(
      builder: (context) {
        final wallpaper = controller.wallpaper.value;
        final isLoading =
            !wallpaper.hasDetails &&
            controller.details.value == null &&
            controller.detailsError.value == null;
        // Chain into the screen's debounced post-frame measure: this rebuild
        // is triggered by a signal, not by the screen's own build.
        if (!isLoading) onContentLaidOut();
        return Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppShapes.extraLarge),
            ),
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              if (isLoading) ...[
                SliverToBoxAdapter(
                  child: _SheetDragHandle(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ),
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: M3ELoadingIndicator(
                      size: 60,
                      semanticLabel: 'Loading wallpaper details',
                    ),
                  ),
                ),
              ] else
                SliverToBoxAdapter(
                  child: SizeChangedLayoutNotifier(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: Column(
                        key: contentKey,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SheetDragHandle(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          AppSpacing.sm.gap,
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _MetadataGrid(wallpaper: wallpaper),
                                  AppSpacing.lg.gap,
                                  WallpaperColorPalette(
                                    controller: controller,
                                    onColorTap: onColorTap,
                                  ),
                                  AppSpacing.lg.gap,
                                  WallpaperTagsSection(
                                    controller: controller,
                                    onTagTap: onTagTap,
                                  ),
                                  AppSpacing.lg.gap,
                                  WallpaperActionBar(
                                    controller: controller,
                                    onBeforeSetPopup: onCollapseForSet,
                                  ),
                                  BottomPadding(),
                                ],
                              ),
                            ),
                          ),
                        ],
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
}

/// Rounded drag affordance at the top of the info sheet.
final class _SheetDragHandle extends StatelessWidget {
  final Color color;

  const _SheetDragHandle({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Edge-to-edge wallpaper surface. Shows listing data instantly when the
/// route carried an `initial`; deep-linked placeholders fall back to the
/// best available thumbnail until `/w/{id}` resolves. When the full-resolution
/// URL differs from that thumbnail, the thumbnail remains visible while it
/// loads.
final class _FullBleedImage extends StatelessWidget {
  final WallpaperDetailController controller;
  final String heroScope;

  const _FullBleedImage({required this.controller, required this.heroScope});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Decode the original at native screen resolution, NOT its full
    // sensor size: a 4K+ wallpaper decoded uncropped costs ~30 MB of RAM
    // and a couple of those evict every grid tile from the image cache
    // (mass placeholder reloads on back). Clamped to the device's physical
    // pixels it stays visually lossless on this screen.
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = (size.shortestSide * dpr).round().clamp(720, 2160);

    return SignalBuilder(
      builder: (context) {
        final wallpaper = controller.wallpaper.value;
        final fullResolutionUrl = wallpaper.path;
        final url = fullResolutionUrl.isNotEmpty
            ? fullResolutionUrl
            : (wallpaper.thumbnails.original ??
                  wallpaper.thumbnails.bestForGrid ??
                  '');
        final placeholderUrl = fullResolutionUrl.isNotEmpty
            ? (wallpaper.thumbnails.original ??
                  wallpaper.thumbnails.bestForGrid)
            : null;
        final imageFallbackColor = wallpaper.colors.isNotEmpty
            ? parseHexColor(wallpaper.colors.first)
            : null;

        return Hero(
          tag: 'wallpaper-$heroScope${wallpaper.id}',
          flightShuttleBuilder:
              (
                flightContext,
                animation,
                direction,
                fromHeroContext,
                toHeroContext,
              ) {
                final hero = direction == HeroFlightDirection.push
                    ? toHeroContext.widget as Hero
                    : fromHeroContext.widget as Hero;
                return Material(color: Colors.transparent, child: hero.child);
              },
          placeholderBuilder: (context, size, child) =>
              SizedBox.fromSize(size: size, child: child),
          child: ColoredBox(
            color: imageFallbackColor ?? theme.colorScheme.surfaceContainerHigh,
            child: url.isEmpty
                ? Center(
                    child: Icon(
                      PhosphorIconsFill.image,
                      size: 32,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : SmartNetworkImage(
                    url,
                    fit: BoxFit.cover,
                    memCacheWidth: decodeWidth,
                    placeholderImageUrl: placeholderUrl,
                    placeholderColor: imageFallbackColor,
                  ),
          ),
        );
      },
    );
  }
}

/// 2-column metadata grid: Resolution · File size / Favorites · Uploader.
///
/// Aspect ratio and upload date are deliberately not shown: they added two
/// cards without changing how anyone chooses a wallpaper. Values come from
/// the pure [WallpaperMetadata] formatters; cards render with the ambient
/// wallpaper-derived theme.
final class _MetadataGrid extends StatelessWidget {
  final Wallpaper wallpaper;

  const _MetadataGrid({required this.wallpaper});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final size = WallpaperMetadata.fileSize(wallpaper.fileSizeBytes, locale);

    final cells = <({IconData icon, String label, String value})>[
      (
        icon: PhosphorIconsFill.frameCorners,
        label: 'Resolution',
        value: wallpaper.resolution.isNotEmpty ? wallpaper.resolution : '-',
      ),
      (icon: PhosphorIconsFill.file, label: 'File size', value: size ?? '-'),
      (
        icon: PhosphorIconsFill.heart,
        label: 'Favorites',
        value: WallpaperMetadata.count(wallpaper.favorites, locale),
      ),
      (
        icon: PhosphorIconsFill.user,
        label: 'Uploader',
        value: wallpaper.uploader?.username ?? '-',
      ),
    ];

    return Column(
      children: [
        for (var row = 0; row < cells.length; row += 2) ...[
          if (row > 0) const SizedBox(height: AppSpacing.md),
          // IntrinsicHeight equalizes the two cards' heights without
          // stretching into the scroll view's unbounded constraints.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cells[row].toCard()),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: cells[row + 1].toCard()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

extension on ({IconData icon, String label, String value}) {
  WallpaperInfoCard toCard() =>
      WallpaperInfoCard(icon: icon, label: label, value: value);
}
