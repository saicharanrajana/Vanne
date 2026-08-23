import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../app/dependencies.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_shapes.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/app_typography.dart';
import '../../../features/settings/application/settings_controller.dart';
import '../../../shared/extensions/gap_extensions.dart';
import '../../../shared/widgets/bottom_padding.dart';
import '../../../shared/widgets/pressable_scale.dart';
import '../../../shared/widgets/smart_network_image.dart';
import '../../../shared/utils/hex_color.dart';
import '../../favorites/application/favorites_controller.dart';

import '../application/wallpaper_detail_controller.dart';
import '../application/wallpaper_metadata.dart';
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
        // isRegistered (not a bare get): the detail screen must render
        // even in hosts that never registered Settings (e.g. focused
        // widget tests).
        final settings = locator.isRegistered<SettingsController>()
            ? locator<SettingsController>()
            : null;
        final pitchBlack =
            (settings?.pitchBlack.value ?? false) &&
            brightness == Brightness.dark;
        final key = Object.hash(
          wallpaper.id,
          brightness,
          wallpaper.colors,
          pitchBlack,
        );
        if (key != _schemeKey || _cachedScheme == null) {
          _cachedScheme = _wallpaperScheme(
            wallpaper,
            brightness,
            baseTheme.colorScheme,
            pitchBlack,
          );
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
                                backgroundColor: wallpaperTheme
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                              icon: Icon(
                                Icons.arrow_back,
                                color:
                                    wallpaperTheme.colorScheme.onSurfaceVariant,
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
                // Draggable info sheet — collapses to a 0.08 peek and
                // expands to 0.9 for the full metadata / colors / tags /
                // actions content; content scrolls once expanded. Uses
                // native DraggableScrollableSheet for consistency.
                DraggableScrollableSheet(
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
                            WallpaperColorPalette(controller: controller),
                            AppSpacing.lg.gap,
                            WallpaperTagsSection(controller: controller),
                            AppSpacing.lg.gap,
                            WallpaperActionBar(controller: controller),
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
  bool pitchBlack,
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
  final scheme = M3EColorScheme.generate(
    seedColor: chosen.toColor(),
    brightness: brightness,
  );

  // Pitch-black mode: collapse surfaces to the true-black ladder while the
  // wallpaper-derived accents (primary, containers) stay intact.
  return pitchBlack && brightness == Brightness.dark
      ? AppTheme.toPitchBlack(scheme)
      : scheme;
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
    primaryIconTheme: base.primaryIconTheme.copyWith(
      color: scheme.onSurfaceVariant,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: scheme.outlineVariant,
  );
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
    final size = WallpaperMetadata.fileSize(wallpaper.fileSizeBytes);
    final uploaded = WallpaperMetadata.uploadedDate(wallpaper.createdAt);

    final cells = <({IconData icon, String label, String value})>[
      (
        icon: Icons.aspect_ratio,
        label: 'Resolution',
        value: wallpaper.resolution.isNotEmpty ? wallpaper.resolution : '—',
      ),
      (
        icon: Icons.insert_drive_file_outlined,
        label: 'File size',
        value: size ?? '—',
      ),
      (
        icon: Icons.crop_free,
        label: 'Aspect ratio',
        value: WallpaperMetadata.aspectRatio(wallpaper),
      ),
      (
        icon: Icons.favorite_border,
        label: 'Favorites',
        value: '${wallpaper.favorites}',
      ),
      (
        icon: Icons.person_outline,
        label: 'Uploader',
        value: wallpaper.uploader?.username ?? '—',
      ),
      (
        icon: Icons.calendar_month_outlined,
        label: 'Uploaded',
        value: uploaded ?? '—',
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
