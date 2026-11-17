import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
// Prefer material_ui over package:flutter/material.dart: the app runs on the
// material_ui widget tree — flutter-material Theme.of lookups here would
// silently fall back to the default light theme.
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_motion.dart';

/// Disk-cached, smoothly fading network image.
///
/// Backed by `cached_network_image` (flutter_cache_manager,
/// `libCachedImageData`) + `flutter_blurhash`.
/// While loading, an optional disk-cached thumbnail stays beneath the image
/// until its first frame fades in. Without a thumbnail, a blurhash (if
/// provided) or tonal/derived color box is shown; on failure a muted
/// broken-image icon appears.
/// Fade is 300ms emphasized-decelerate ([AppMotion]); disabled entirely
/// when the platform requests reduced motion.
class SmartNetworkImage extends StatelessWidget {
  const SmartNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.blurHash,
    this.placeholderColor,
    this.placeholderImageUrl,
  });

  /// Test seam: swaps the cache manager backing every [CachedNetworkImage]
  /// rendered through this widget. Production leaves it null and uses the
  /// package default; widget tests inject [FakeCacheManager] so
  /// `flutter_cache_manager`'s store — whose periodic cleanup timer leaks
  /// into the tests' fake-async zone — is never created.
  @visibleForTesting
  static BaseCacheManager? debugCacheManager;

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final String? blurHash;
  final Color? placeholderColor;

  /// A lower-resolution image to keep visible while [url] loads.
  ///
  /// This is intentionally rendered through [CachedNetworkImage] as well, so
  /// a thumbnail already shown in a preceding screen can be reused from the
  /// disk cache without downloading it again.
  final String? placeholderImageUrl;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Container(
        width: width,
        height: height,
        color: placeholderColor ?? scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          PhosphorIconsFill.image,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final fallback = placeholderColor ?? scheme.surfaceContainerHighest;
    // Reduced motion: snap straight to the image, no cross-fade.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final thumbnailUrl = placeholderImageUrl;
    final hasThumbnail =
        thumbnailUrl != null && thumbnailUrl.isNotEmpty && thumbnailUrl != url;

    final image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      cacheManager: debugCacheManager,
      // Decode at the consuming surface's size for RAM. The optional
      // placeholder image has its own cache entry and is never promoted to
      // the full-resolution image.
      memCacheWidth: memCacheWidth,
      fadeInDuration: reduceMotion ? Duration.zero : AppMotion.transition,
      fadeInCurve: AppMotion.arrivalCurve,
      fadeOutDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
      // Keep the thumbnail underneath instead of asking OctoImage to fade a
      // nested placeholder away. A transparent placeholder prevents a color
      // frame from being painted between the two images.
      placeholder: hasThumbnail
          ? (context, _) => const SizedBox.expand()
          : (context, _) => _BlurPlaceholder(
              blurHash: blurHash,
              fallbackColor: fallback,
              fit: fit,
            ),
      errorWidget: (context, _, _) => Container(
        color: fallback,
        alignment: Alignment.center,
        child: Icon(
          PhosphorIconsFill.image,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      ),
      imageBuilder: (context, provider) => Image(
        image: provider,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
      ),
    );
    if (!hasThumbnail) return image;

    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: thumbnailUrl,
          width: width,
          height: height,
          fit: fit,
          cacheManager: debugCacheManager,
          memCacheWidth: memCacheWidth,
          fadeInDuration: reduceMotion ? Duration.zero : AppMotion.transition,
          fadeInCurve: AppMotion.arrivalCurve,
          fadeOutDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 140),
          placeholder: (context, _) => _BlurPlaceholder(
            blurHash: blurHash,
            fallbackColor: fallback,
            fit: fit,
          ),
          errorWidget: (_, _, _) => _BlurPlaceholder(
            blurHash: blurHash,
            fallbackColor: fallback,
            fit: fit,
          ),
        ),
        image,
      ],
    );
  }
}

class _BlurPlaceholder extends StatelessWidget {
  const _BlurPlaceholder({
    required this.blurHash,
    required this.fallbackColor,
    this.fit = BoxFit.cover,
  });

  final String? blurHash;
  final Color fallbackColor;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (blurHash != null && blurHash!.length >= 6) {
      try {
        return SizedBox.expand(
          child: BlurHash(hash: blurHash!, imageFit: fit, color: fallbackColor),
        );
      } catch (_) {
        // Malformed hash — fall through to solid color.
      }
    }
    return Container(color: fallbackColor);
  }
}
