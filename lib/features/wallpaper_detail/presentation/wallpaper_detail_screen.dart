import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_shapes.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/services/url_launcher_service.dart';
import '../../../shared/widgets/app_snack.dart';
import '../../../shared/widgets/pressable_scale.dart';
import '../../../shared/widgets/smart_network_image.dart';
import '../../../shared/utils/hex_color.dart';
import '../../favorites/application/favorites_controller.dart';

import '../application/wallpaper_detail_controller.dart';
import 'widgets/set_wallpaper_sheet.dart';
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

  const WallpaperDetailScreen({
    super.key,
    required this.controller,
    required this.onBack,
    this.heroScope = '',
  });

  @override
  State<WallpaperDetailScreen> createState() => _WallpaperDetailScreenState();
}

final class _WallpaperDetailScreenState extends State<WallpaperDetailScreen> {
  /// Memoized wallpaper-derived scheme; [M3EColorScheme.generate] is too
  /// expensive to re-run on every signal tick.
  ColorScheme? _cachedScheme;
  Object? _schemeKey;

  @override
  void initState() {
    super.initState();
    widget.controller.loadDetails();
  }

  @override
  void dispose() {
    widget.controller.dispose();
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
        final key = Object.hash(wallpaper.id, brightness, wallpaper.colors);
        if (key != _schemeKey || _cachedScheme == null) {
          _cachedScheme =
              _wallpaperScheme(wallpaper, brightness, baseTheme.colorScheme);
          _schemeKey = key;
        }
        final scheme = _cachedScheme!;
        final wallpaperTheme = _wallpaperTheme(scheme, baseTheme);
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
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          PressableScale(
                            child: IconButton(
                              onPressed: widget.onBack,
                              tooltip: 'Back',
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    wallpaperTheme.colorScheme.surfaceContainerHighest,
                              ),
                              icon: Icon(
                                Icons.arrow_back,
                                color: wallpaperTheme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          _FavoriteHeroButton(
                            wallpaperId: wallpaper.id,
                            favoriteIds: favorites.favoriteIds,
                            onPressed: () => favorites.toggle(wallpaper),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Draggable info sheet — collapsable to 0.08 peek, perfect height
                // 0.32 (≈ content + handle + bottom padding), max 0.32 so no
                // white-space overshoot beyond content. Snap 0.08 ↔ 0.32.
                // Uses native DraggableScrollableSheet for consistency.
                DraggableScrollableSheet(
                  initialChildSize: 0.32,
                  minChildSize: 0.08,
                  maxChildSize: 0.32,
                  snap: true,
                  snapSizes: const [0.08, 0.32],
                  builder: (context, scrollController) {
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      child: _DraggableInfoSheet(
                        controller: widget.controller,
                        scrollController: scrollController,
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

/// Draggable, scrollable info sheet over the wallpaper: a 2×2 metadata
/// grid with prefix icons and the [ Download | Set | Open ] action group.
/// Colors are derived from the wallpaper's dominant colors for a vibrant
/// but readable look in both light/dark. Shows a centered contained loading
/// indicator until details are fetched.
///
/// The outer [DraggableScrollableSheet] in the screen owns the sheet height;
/// this widget provides the wallpaper-derived surface, drag handle, and
/// scrollable content using the sheet's [scrollController] so drag and
/// scroll are unified (native iOS/Android physics).
final class _DraggableInfoSheet extends StatelessWidget {
  final WallpaperDetailController controller;
  final ScrollController scrollController;

  const _DraggableInfoSheet({
    required this.controller,
    required this.scrollController,
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
                  child: Center(child: M3EContainedLoadingIndicator()),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MetadataGrid(wallpaper: wallpaper, colorScheme: scheme),
                            const SizedBox(height: 16),
                            Center(child: _ActionRow(controller: controller, colorScheme: scheme)),
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
/// best thumbnail until `/w/{id}` resolves.
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
        final url = wallpaper.path.isNotEmpty
            ? wallpaper.path
            : (wallpaper.thumbnails.original ??
                  wallpaper.thumbnails.bestForGrid ??
                  '');

        return Hero(
          tag: 'wallpaper-$heroScope${wallpaper.id}',
          flightShuttleBuilder: (flightContext, animation, direction,
              fromHeroContext, toHeroContext) {
            final hero = direction == HeroFlightDirection.push
                ? toHeroContext.widget as Hero
                : fromHeroContext.widget as Hero;
            return Material(
              color: Colors.transparent,
              child: hero.child,
            );
          },
          placeholderBuilder: (context, size, child) =>
              SizedBox.fromSize(size: size, child: child),
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerHigh,
            child: url.isEmpty
                ? Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 32,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : SmartNetworkImage(
                    url,
                    fit: BoxFit.cover,
                    memCacheWidth: decodeWidth,
                    placeholderColor: wallpaper.colors.isNotEmpty
                        ? parseHexColor(wallpaper.colors.first)
                        : null,
                  ),
          ),
        );
      },
    );
  }
}

ColorScheme _wallpaperScheme(
  Wallpaper wallpaper,
  Brightness brightness,
  ColorScheme fallback,
) {
  if (wallpaper.colors.isEmpty) return fallback;

  // Readability window for seeds: outside it, containers/text pairs lose
  // contrast no matter how saturated the color is.
  const minLightness = 0.35;
  const maxLightness = 0.65;

  HSLColor? best;
  HSLColor? bestAny;
  for (final hex in wallpaper.colors) {
    final color = parseHexColor(hex);
    if (color == null) continue;
    final hsl = HSLColor.fromColor(color);
    if (bestAny == null || hsl.saturation > bestAny.saturation) {
      bestAny = hsl;
    }
    final inWindow =
        hsl.lightness >= minLightness && hsl.lightness <= maxLightness;
    if (inWindow && (best == null || hsl.saturation > best.saturation)) {
      best = hsl;
    }
  }

  var chosen = best ?? bestAny;
  if (chosen == null) return fallback;
  // No candidate sat inside the readability window — nudge the most
  // saturated one into it rather than falling back to the app scheme.
  chosen = chosen.withLightness(
    chosen.lightness.clamp(minLightness, maxLightness),
  );

  // Generate a full scheme from the vibrant seed *without* systemColorScheme.
  // When systemColorScheme is passed, M3EColorScheme keeps system primary/
  // secondary (app's blue) and only overrides surfaces — which is why
  // variety wallpapers still looked blue. Passing null makes primary,
  // primaryContainer, secondary etc come from the wallpaper seed.
  return M3EColorScheme.generate(
    seedColor: chosen.toColor(),
    brightness: brightness,
  );
}

/// Robust wallpaper-derived ThemeData. Wrapping the detail screen with
/// this ensures *every* descendant that does `Theme.of(context)` gets
/// wallpaper colors — no per-widget `colorScheme` plumbing. Future
/// widgets added under the detail `Theme` automatically honor the
/// wallpaper palette without manual updates.
ThemeData _wallpaperTheme(ColorScheme scheme, ThemeData base) {
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: buildAppTextTheme(scheme),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.secondaryContainer,
      checkmarkColor: scheme.onSecondaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      secondaryLabelStyle: TextStyle(color: scheme.onSecondaryContainer),
      shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      showCheckmark: true,
    ),
    iconTheme: base.iconTheme.copyWith(color: scheme.onSurfaceVariant),
    primaryIconTheme: base.primaryIconTheme.copyWith(color: scheme.onSurfaceVariant),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: scheme.outlineVariant,
  );
}

/// 2×2 grid: Resolution · File size · Uploader · Favorites.
/// Uses the wallpaper-derived [colorScheme] for vibrant but readable text.
final class _MetadataGrid extends StatelessWidget {
  final Wallpaper wallpaper;
  final ColorScheme colorScheme;
  const _MetadataGrid({required this.wallpaper, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    String? sizeLabel;
    if (wallpaper.fileSizeBytes > 0) {
      final mb = wallpaper.fileSizeBytes / (1024 * 1024);
      sizeLabel = mb >= 1
          ? '${mb.toStringAsFixed(1)} MB'
          : '${(wallpaper.fileSizeBytes / 1024).round()} KB';
    }

    final cells = <_MetadataCellData>[
      (
        icon: Icons.aspect_ratio,
        label: 'Resolution',
        value: wallpaper.resolution.isNotEmpty ? wallpaper.resolution : '—',
      ),
      (
        icon: Icons.sd_storage_outlined,
        label: 'File size',
        value: sizeLabel ?? '—',
      ),
      (
        icon: Icons.person_outline,
        label: 'Uploader',
        value: wallpaper.uploader?.username ?? '—',
      ),
      (
        icon: Icons.favorite_border,
        label: 'Favorites',
        value: '${wallpaper.favorites}',
      ),
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var row = 0; row < cells.length; row += 2)
          Padding(
            padding: EdgeInsets.only(bottom: row + 2 < cells.length ? 12 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _MetadataCell(
                    data: cells[row],
                    colorScheme: colorScheme,
                  ),
                ),
                if (row + 1 < cells.length) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetadataCell(
                      data: cells[row + 1],
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

typedef _MetadataCellData = ({IconData icon, String label, String value});

final class _MetadataCell extends StatelessWidget {
  final _MetadataCellData data;
  final ColorScheme colorScheme;

  const _MetadataCell({required this.data, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(data.icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                data.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Floating toolbar for wallpaper actions — vibrant, centered, expressive.
final class _ActionRow extends StatelessWidget {
  final ColorScheme colorScheme;
  final WallpaperDetailController controller;

  const _ActionRow({required this.colorScheme, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final download = controller.download.value;
        final isBusy = download.isBusy;

        return M3EHorizontalFloatingToolbar(
          expanded: true,
          decoration: M3EFloatingToolbarDecoration(
            colors: M3EFloatingToolbarColors(
              toolbarContainerColor: colorScheme.primaryContainer,
              toolbarContentColor: colorScheme.onPrimaryContainer,
              fabContainerColor: colorScheme.primaryContainer,
              fabContentColor: colorScheme.onPrimaryContainer,
            ),
          ),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBusy)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: M3ECircularProgressIndicator(
                    size: 24,
                    strokeWidth: 2.5,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Download to gallery',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => _download(context, controller),
                ),
              IconButton(
                tooltip: 'Set as wallpaper',
                icon: const Icon(Icons.wallpaper_outlined),
                onPressed: () =>
                    showSetWallpaperPopup(context, controller: controller),
              ),
              IconButton(
                tooltip: 'Open on Wallhaven',
                icon: const Icon(Icons.open_in_new_outlined),
                onPressed: () => _openSource(context, controller),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Runs the gallery download and reports the terminal outcome. All
  /// failures are caught: anything escaping here would surface as an
  /// unhandled zone error instead of user feedback.
  static Future<void> _download(
    BuildContext context,
    WallpaperDetailController controller,
  ) async {
    try {
      await controller.downloadToGallery();
    } catch (_) {
      // downloadToGallery already maps known failures; this guards against
      // unexpected errors becoming unhandled zone exceptions.
      if (!context.mounted) return;
      AppSnack.show(context, 'Download failed. Please try again.', error: true);
      return;
    }
    final state = controller.download.peek();
    if (!context.mounted) return;
    if (state.done) {
      AppSnack.show(context, 'Wallpaper saved to your gallery');
    } else if (state.error != null) {
      AppSnack.show(context, state.error!, error: true);
    }
  }

  static Future<void> _openSource(
    BuildContext context,
    WallpaperDetailController controller,
  ) async {
    final url = Uri.parse(controller.wallpaper.peek().url);
    final ok = await locator<UrlLauncherService>().openInApp(url);
    if (!ok && context.mounted) {
      AppSnack.show(context, 'No browser available.', error: true);
    }
  }
}

/// Heart toggle overlaid on the hero image; mirrors the grid tile style.
final class _FavoriteHeroButton extends StatelessWidget {
  final String wallpaperId;
  final ReadonlySignal<Set<String>> favoriteIds;
  final VoidCallback onPressed;

  const _FavoriteHeroButton({
    required this.wallpaperId,
    required this.favoriteIds,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SignalBuilder(
      builder: (context) {
        final selected = favoriteIds.value.contains(wallpaperId);
        return IconButton(
          onPressed: onPressed,
          tooltip: 'Save to favorites',
          icon: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(8),
            child: Icon(
              selected ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: selected ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}
