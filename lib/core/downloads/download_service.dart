import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'app_identity.dart';
import 'download_destination.dart';
import 'download_destination_controller.dart';

/// Downloads wallpapers at full resolution.
///
/// Two destinations:
/// - [downloadToFile] — cache file, used before applying a wallpaper.
/// - [saveDownload] — the user's download folder. By default that is
///   `Pictures/<AppIdentity.storageFolderName>` through MediaStore (gallery
///   indexed, no storage permission); when the user picked a parent folder in
///   Settings it is `<parent>/<AppIdentity.storageFolderName>` inside the
///   persisted tree grant. The cache copy is deleted afterwards; the platform
///   owns the saved result.
final class DownloadService {
  final Dio _dio;
  final DownloadDestinationController? _destination;
  final DownloadStoragePlatform _platform;

  DownloadService({
    Dio? dio,
    DownloadDestinationController? destinationController,
    DownloadStoragePlatform? platform,
  }) : _dio = dio ?? Dio(),
       _destination = destinationController,
       _platform = platform ?? const DownloadStoragePlatform();

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

  /// Folder that receives downloads, phrased for display.
  ///
  /// `Pictures/VanneWallpapers` when the user never picked a parent folder, else
  /// `<picked parent>/VanneWallpapers`.
  String get destinationFolderPath =>
      _destination?.destination.peek().folderPath ??
      const DefaultDownloadDestination().folderPath;

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
            ? 'Network unavailable. Check your connection.'
            : 'Download failed. Please try again.',
      );
    }
  }

  /// Downloads [wallpaper]'s full image and saves it to the download folder.
  ///
  /// Resolves the destination once, up front, and passes it to the platform:
  /// a revoked chosen folder fails with an actionable error and is never
  /// silently replaced by the default folder.
  ///
  /// Returns the display folder the file was written to. The value is
  /// snapshotted when the write starts, so success feedback names the folder
  /// that actually received the file even if the user picks another one while
  /// the transfer is still running.
  Future<String> saveDownload(
    Wallpaper wallpaper, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final destination =
        _destination?.destination.peek() ?? const DefaultDownloadDestination();
    File? tempFile;
    _destination?.beginSave();
    try {
      final dir = await getTemporaryDirectory();
      tempFile = File('${dir.path}/${fileNameFor(wallpaper)}');
      await downloadToFile(
        wallpaper,
        tempFile,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

      final result = await _platform.saveDownload(
        sourcePath: tempFile.path,
        folderName: AppIdentity.storageFolderName,
        mimeType: _mimeTypeFor(wallpaper),
        treeUri: destination.treeUri,
      );

      switch (result) {
        case DownloadSaveSuccess():
          return destination.folderPath;
        case DownloadSaveFailure(:final code, :final message):
          if (code == DownloadSaveErrorCode.noPermission ||
              code == DownloadSaveErrorCode.destinationUnavailable) {
            _destination?.markAccessLost(destination.treeUri);
            throw DownloadException(
              'That download folder is no longer available. '
              'Choose it again in Settings, or use the default folder.',
            );
          }
          throw DownloadException(_messageFor(code, message));
      }
    } finally {
      // The platform copy owns the file; the cache copy is garbage.
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } on FileSystemException {
        // Non-fatal: the OS clears cache storage eventually.
      }
      _destination?.endSave();
    }
  }

  static String _mimeTypeFor(Wallpaper wallpaper) {
    final mime = wallpaper.fileType.toLowerCase();
    return switch (mime) {
      'image/png' => 'image/png',
      'image/webp' => 'image/webp',
      'image/gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  static String _messageFor(DownloadSaveErrorCode code, String fallback) {
    return switch (code) {
      DownloadSaveErrorCode.noSpace =>
        'Not enough storage space to save the wallpaper.',
      DownloadSaveErrorCode.unsupported =>
        'This wallpaper format is not supported.',
      // The native bridge answered nothing: a build/plugin problem, not a
      // property of the wallpaper.
      DownloadSaveErrorCode.nativeUnavailable =>
        'Saving downloads is unavailable in this build.',
      DownloadSaveErrorCode.notFound || DownloadSaveErrorCode.invalidArgs =>
        'Could not save the wallpaper. Please try again.',
      DownloadSaveErrorCode.noPermission ||
      DownloadSaveErrorCode.destinationUnavailable =>
        'That download folder is no longer available. '
            'Choose it again in Settings, or use the default folder.',
      DownloadSaveErrorCode.io || DownloadSaveErrorCode.unknown =>
        'Could not save the wallpaper. Please try again.',
    };
  }
}

/// A download failure already phrased for display.
final class DownloadException implements Exception {
  final String message;
  const DownloadException(this.message);

  @override
  String toString() => message;
}
