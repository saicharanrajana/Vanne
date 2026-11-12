import 'package:flutter/foundation.dart';
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

  Future<void> _collapseSheet() async {
    if (!_sheetController.isAttached) return;
    try {
      await _sheetController.animateTo(
        0.1,
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

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final brightness = baseTheme.brightness;
    final favorites = locator<FavoritesController>();

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
                // Draggable info sheet — collapses to a 0.08 peek and
                // expands to 0.9 for the full metadata / colors / tags /
                // actions content; content scrolls once expanded. Uses
                // native DraggableScrollableSheet for consistency.
                DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: 0.3,
                  minChildSize: 0.1,
                  maxChildSize: 0.8,
                  snap: true,
                  snapSizes: const [0.1, 0.3, 0.8],
                  builder: (context, scrollController) {
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      child: _DraggableInfoSheet(
                        controller: widget.controller,
                        scrollController: scrollController,
                        onColorTap: widget.onColorTap,
                        onTagTap: widget.onTagTap,
                        onCollapseForSet: _collapseSheet,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Draggable, scrollable info sheet over the wallpaper: a 2×3 metadata
/// card grid, Colors and Tags sections, and the action group. Colors are
/// derived from the wallpaper's dominant colors for a vibrant but readable
/// look in both light/dark. Shows a centered contained loading indicator
/// until details are fetched.
///
/// The outer [DraggableScrollableSheet] in the screen owns the sheet height;
/// this widget provides the wallpaper-derived surface, drag handle, and
/// scrollable content using the sheet's [scrollController] so drag and
/// scroll are unified (native iOS/Android physics).
final class _DraggableInfoSheet extends StatelessWidget {
  final WallpaperDetailController controller;
  final ScrollController scrollController;
  final ValueChanged<String>? onColorTap;
  final ValueChanged<String>? onTagTap;
  final Future<void> Function()? onCollapseForSet;

  const _DraggableInfoSheet({
    required this.controller,
    required this.scrollController,
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
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              if (isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: M3ELoadingIndicator(
                      variant: M3ELoadingIndicatorVariant.contained,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Center(
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
                  ),
                ),
            ],
          ),
        );
      },
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

/// 2-column metadata grid: Resolution · File size / Aspect ratio ·
/// Favorites / Uploader · Uploaded. Values come from the pure
/// [WallpaperMetadata] formatters; cards render with the ambient
/// wallpaper-derived theme.
final class _MetadataGrid extends StatelessWidget {
  final Wallpaper wallpaper;

  const _MetadataGrid({required this.wallpaper});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final size = WallpaperMetadata.fileSize(wallpaper.fileSizeBytes, locale);
    final uploaded = WallpaperMetadata.uploadedDate(
      wallpaper.createdAt,
      locale,
    );

    final cells = <({IconData icon, String label, String value})>[
      (
        icon: PhosphorIconsFill.frameCorners,
        label: 'Resolution',
        value: wallpaper.resolution.isNotEmpty ? wallpaper.resolution : '-',
      ),
      (icon: PhosphorIconsFill.file, label: 'File size', value: size ?? '-'),
      (
        icon: PhosphorIconsFill.crop,
        label: 'Aspect ratio',
        value: WallpaperMetadata.aspectRatio(wallpaper),
      ),
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
      (
        icon: PhosphorIconsFill.calendar,
        label: 'Uploaded',
        value: uploaded ?? '-',
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
