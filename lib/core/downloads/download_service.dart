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
  }) : _dio = dio ?? _defaultDio(),
       _destination = destinationController,
       _platform = platform ?? const DownloadStoragePlatform();

  /// Transport for full-resolution images.
  ///
  /// Timeouts are mandatory here: without them a host that accepts the
  /// connection but stops sending leaves "Set" and Save spinning forever with
  /// no way out but leaving the screen. [receiveTimeout] is an inactivity
  /// window between chunks, not a cap on the whole transfer, so a large
  /// wallpaper on a slow link still completes.
  static Dio _defaultDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

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
  /// The destination only appears once the transfer is whole: bytes are written
  /// to a unique scratch file and renamed into place afterwards. Callers rely
  /// on that — "Set" treats an existing cache file as a complete wallpaper —
  /// so a killed process, a dropped connection, or a cancellation must leave
  /// the destination absent rather than half-written.
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
    // Unique per transfer: two downloads of one wallpaper (two detail routes,
    // or a retry) must never write into the same scratch file.
    final scratch = File(
      '${destination.path}.'
      '${DateTime.now().microsecondsSinceEpoch}_${_scratchSequence++}.part',
    );
    try {
      await _dio.download(
        url,
        scratch.path,
        onReceiveProgress: (received, total) =>
            total > 0 ? onProgress?.call(received / total) : null,
        cancelToken: cancelToken,
      );
      // A 200 with no body is not a wallpaper; publishing it would make every
      // later attempt reuse an empty file.
      if (await scratch.length() == 0) {
        throw const DownloadException('Download failed. Please try again.');
      }
      await scratch.rename(destination.path);
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw const DownloadException('Download cancelled.');
      }
      throw DownloadException(switch (error.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout =>
          'Network unavailable. Check your connection.',
        DioExceptionType.receiveTimeout || DioExceptionType.sendTimeout =>
          'The download stalled. Please try again.',
        _ => 'Download failed. Please try again.',
      });
    } on FileSystemException {
      // Local cache publication (length check or atomic rename) can fail after
      // the network transfer succeeds. Keep callers on the same retryable,
      // user-facing error contract as transport failures.
      throw const DownloadException('Download failed. Please try again.');
    } finally {
      // The rename consumed the scratch file on success; every other exit path
      // leaves only garbage behind, which the cache must not accumulate.
      try {
        if (await scratch.exists()) await scratch.delete();
      } on FileSystemException {
        // Non-fatal: the OS clears cache storage eventually.
      }
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
    Directory? scratch;
    _destination?.beginSave();
    try {
      // One scratch directory per save: two concurrent saves of the same
      // wallpaper must never overwrite — or clean up — each other's file.
      scratch = await _createScratchDirectory();
      final tempFile = File('${scratch.path}/${fileNameFor(wallpaper)}');
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
      // The platform copy owns the file; the cache copy is garbage. Whole
      // directory, so a failed transfer and its partial file both go.
      try {
        if (scratch != null && await scratch.exists()) {
          await scratch.delete(recursive: true);
        }
      } on FileSystemException {
        // Non-fatal: the OS clears cache storage eventually.
      }
      _destination?.endSave();
    }
  }

  /// Monotonic counter that keeps every scratch path unique in this process.
  static int _scratchSequence = 0;

  static Future<Directory> _createScratchDirectory() async {
    final cacheRoot = await getTemporaryDirectory();
    final dir = Directory(
      '${cacheRoot.path}/vanne_download_'
      '${DateTime.now().microsecondsSinceEpoch}_${_scratchSequence++}',
    );
    await dir.create(recursive: true);
    return dir;
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
