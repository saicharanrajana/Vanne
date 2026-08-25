import 'package:cached_network_image/cached_network_image.dart';
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
/// While loading, a blurhash (if provided) or tonal/derived color box is
/// shown instead of a spinner; on failure a muted broken-image icon appears.
/// Fade is 320ms emphasized-decelerate ([AppMotion]); disabled entirely
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
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final String? blurHash;
  final Color? placeholderColor;

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

    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      // Decode at cell size for RAM, but keep the FULL-SIZE original on
      // disk: the detail screen requests the same URL uncropped and must
      // hit the disk cache instead of re-downloading.
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
