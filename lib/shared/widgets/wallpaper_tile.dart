import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_shapes.dart';
import '../../app/theme/app_spacing.dart';

import 'package:signals/signals_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'pressable_scale.dart';
import 'favorite_toggle_button.dart';
import 'smart_network_image.dart';
import '../utils/hex_color.dart';

/// A single wallpaper card for staggered grids.
///
/// Image-first: the thumbnail dominates, aspect ratio is preserved from
/// metadata (no crop-jump), and chrome is limited to a small favorite
/// affordance that appears over a subtle bottom scrim.
///
/// Loads the original-aspect thumbnail (`wallpaper.thumbnails.original`)
/// uncropped at the metadata aspect ratio, sized to [memCacheWidth] so
/// photos cost cell-sized RAM; the full-res `wallpaper.path` is reserved
/// for the detail screen / download. Placeholder is a blurhash (when
/// available) or a solid derived from `wallpaper.colors` with a 320ms fade
/// into the photo. Hero tag (`wallpaper-<id>`) matches the detail screen.
final class WallpaperTile extends StatelessWidget {
  final Wallpaper wallpaper;

  /// Reactive favorite IDs; watched narrowly so only the heart rebuilds.
  final ReadonlySignal<Set<String>>? favoriteIds;

  final VoidCallback? onToggleFavorite;
  final VoidCallback? onOpen;

  /// Decode the original image at this pixel width (cell resolution) so
  /// full-res photos don't cost full-res RAM in the grid. The disk cache
  /// still holds the original, which detail view reuses.
  final int? memCacheWidth;

  /// Namespace for the tile's Hero tag so two lists showing the same
  /// wallpaper never collide (e.g. `discover`, `favorites`).
  final String heroScope;

  const WallpaperTile({
    super.key,
    required this.wallpaper,
    this.favoriteIds,
    this.memCacheWidth,
    this.heroScope = '',
    this.onToggleFavorite,
    this.onOpen,
  });

  String get heroTag => 'wallpaper-$heroScope${wallpaper.id}';

  double get _aspectRatio {
    if (wallpaper.width <= 0 || wallpaper.height <= 0) return 9 / 16;
    return wallpaper.width / wallpaper.height;
  }

  /// `thumbnails.original` is the uncropped original-aspect thumbnail —
  /// ideal for the grid (no hard crop like `small`/`large`). The full-res
  /// `wallpaper.path` is reserved for the detail screen / download.
  String get _imageUrl =>
      wallpaper.thumbnails.original ??
      (wallpaper.path.isNotEmpty ? wallpaper.path : _placeholderUrl);

  String get _placeholderUrl => wallpaper.thumbnails.bestForGrid ?? '';

  Color? get _placeholderColor {
    if (wallpaper.colors.isEmpty) return null;
    return parseHexColor(wallpaper.colors.first);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final image = Hero(
      tag: heroTag,
      // Use a transparent flight to keep the scaffold's surface (including
      // pitch-black) visible; the default white Material would flash.
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: SmartNetworkImage(
            _imageUrl,
            fit: BoxFit.cover,
            memCacheWidth: memCacheWidth,
            placeholderColor: _placeholderColor,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: 'Wallpaper ${wallpaper.resolution}, open details',
      child: Stack(
        children: [
          // Tactile press feedback: spring scale (ripples are disabled
          // app-wide, so this is the tile's only pressed response).
          PressableScale(
            child: Material(
              color: scheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              child: InkWell(onTap: onOpen, child: image),
            ),
          ),
          // Favorite affordance — bottom-right, heart outline/filled, opaque.
          PositionedDirectional(
            bottom: AppSpacing.sm,
            end: AppSpacing.sm,
            child: _FavoriteButton(
              wallpaperId: wallpaper.id,
              favoriteIds: favoriteIds,
              onPressed: onToggleFavorite,
            ),
          ),
        ],
      ),
    );
  }
}

final class _FavoriteButton extends StatelessWidget {
  final String wallpaperId;
  final ReadonlySignal<Set<String>>? favoriteIds;
  final VoidCallback? onPressed;

  const _FavoriteButton({
    required this.wallpaperId,
    this.favoriteIds,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final ids = favoriteIds;
    if (ids == null) {
      return FavoriteToggleButton(selected: false, onPressed: onPressed);
    }
    return SignalBuilder(
      builder: (context) => FavoriteToggleButton(
        selected: ids.value.contains(wallpaperId),
        onPressed: onPressed,
      ),
    );
  }
}
