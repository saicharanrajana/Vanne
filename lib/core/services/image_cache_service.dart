import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Centralized image cache control replacing `extended_image_library` helpers.
///
/// Previously `settings_screen.dart` imported `extended_image` for
/// `getCachedSizeBytes()`, `clearDiskCachedImages()`, `clearMemoryImageCache()`.
/// This service delegates to `flutter_cache_manager` (`DefaultCacheManager`)
/// + `PaintingBinding.imageCache` and handles orphaned legacy dirs.
abstract final class ImageCacheService {
  const ImageCacheService._();

  static const _legacyFolderName = 'cacheImageFolderName';

  /// Total disk bytes used by the current image cache.
  /// On web returns 0. Sums `libCachedImageData` (flutter_cache_manager).
  static Future<int> getCachedSizeBytes() async {
    if (kIsWeb) return 0;
    try {
      final tmp = await getTemporaryDirectory();
      var total = 0;
      // Current manager dir.
      final current = Directory('${tmp.path}/libCachedImageData');
      if (await current.exists()) {
        await for (final e in current.list(recursive: true)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      }
      // Legacy extended_image dir (orphaned after migration) — include so
      // the tile doesn't hide bytes until manual clear.
      final legacy = Directory('${tmp.path}/$_legacyFolderName');
      if (await legacy.exists()) {
        await for (final e in legacy.list(recursive: true)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Clears both in-memory and on-disk caches.
  /// Returns true on success.
  static Future<bool> clearCache() async {
    try {
      // Memory.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      // Disk (current manager).
      await DefaultCacheManager().emptyCache();
      // Legacy extended_image files (best-effort).
      await clearLegacyCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the orphaned `extended_image` disk folder if it exists.
  static Future<void> clearLegacyCache() async {
    if (kIsWeb) return;
    try {
      final tmp = await getTemporaryDirectory();
      final legacy = Directory('${tmp.path}/$_legacyFolderName');
      if (await legacy.exists()) {
        await legacy.delete(recursive: true);
      }
    } catch (_) {}
  }
}
