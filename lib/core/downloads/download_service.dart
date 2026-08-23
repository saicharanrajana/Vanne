import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

/// Downloads wallpapers at full resolution.
///
/// Two destinations:
/// - [downloadToFile] — cache file, used before applying a wallpaper.
/// - [saveToGallery] — device gallery under the `WallpaperApp` album
///   (MediaStore `Pictures/`) via `gal`; no storage permissions needed on
///   Android 10+. The cache copy is deleted afterwards; MediaStore owns
///   the saved result.
final class DownloadService {
  static const albumName = 'WallpaperApp';

  final Dio _dio;

  DownloadService({Dio? dio}) : _dio = dio ?? Dio();

  /// Deterministic filename for [wallpaper]: `wallhaven_<id>.<ext>`.
  static String fileNameFor(Wallpaper wallpaper) {
    final mime = wallpaper.fileType.toLowerCase();
    final ext = switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    return 'wallhaven_${wallpaper.id}.$ext';
  }

  /// Downloads [wallpaper]'s full image into [destination] (a cache path).
  ///
  /// Throws [DownloadException] with a user-facing message on failure.
  /// Progress is reported through [onProgress] as 0.0–1.0. Pass a
  /// [cancelToken] to abort the transfer (e.g. when leaving the screen);
  /// cancellation surfaces as [DownloadException] with a neutral message.
  Future<void> downloadToFile(
    Wallpaper wallpaper,
    File destination, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = wallpaper.path;
    if (url.isEmpty) {
      throw const DownloadException(
        'No downloadable file is available for this wallpaper.',
      );
    }
    try {
      await _dio.download(
        url,
        destination.path,
        onReceiveProgress: (received, total) =>
            total > 0 ? onProgress?.call(received / total) : null,
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw const DownloadException('Download cancelled.');
      }
      throw DownloadException(
        error.type == DioExceptionType.connectionError
            ? 'Network unavailable — check your connection.'
            : 'Download failed. Please try again.',
      );
    }
  }

  /// Downloads [wallpaper]'s full image and saves it to the gallery.
  Future<void> saveToGallery(
    Wallpaper wallpaper, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    File? tempFile;
    try {
      final dir = await getTemporaryDirectory();
      tempFile = File('${dir.path}/${fileNameFor(wallpaper)}');
      await downloadToFile(
        wallpaper,
        tempFile,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      await Gal.putImage(tempFile.path, album: albumName);
    } on GalException catch (error) {
      throw DownloadException(switch (error.type) {
        GalExceptionType.notEnoughSpace =>
          'Not enough storage space to save the wallpaper.',
        GalExceptionType.accessDenied =>
          'Storage access was denied by the system.',
        GalExceptionType.notSupportedFormat =>
          'This wallpaper format is not supported.',
        GalExceptionType.unexpected =>
          'Could not save the wallpaper to your gallery.',
      });
    } finally {
      // The gallery copy lives in MediaStore; the cache copy is garbage.
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } on FileSystemException {
        // Non-fatal: the OS clears cache storage eventually.
      }
    }
  }
}

/// A download failure already phrased for display.
final class DownloadException implements Exception {
  final String message;
  const DownloadException(this.message);

  @override
  String toString() => message;
}
